// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./FLECHubErrors.sol";

/**
 * FLECHub
 * - Work agreement escrow with OneTime / Milestone / Monthly payroll
 * - Execution fee: 1.5% (150 bps) per agreement, paid upfront at first deposit, non-refundable
 * - Optional: approval-timeout auto-release and dispute lock
 */
contract FLECHub is ReentrancyGuard, FLECHubErrors {
    using SafeERC20 for IERC20;

    enum PType {
        OneTime,
        Milestone,
        Monthly
    }
    // NOTE: Disputed appended at the end to avoid shifting existing enum values (for new deployments only).
    enum Status {
        Created,
        Funded,
        Proposed,
        Accepted,
        Completed,
        Cancelled,
        Disputed
    }

    struct Agreement {
        address company;
        address freelancer;
        address arbitrator;
        address token;
        uint256 totalBudget; // escrow budget (excludes execution fee)
        uint256 amountReleased;
        // Monthly payroll
        uint256 lastPaymentTime;
        uint256 monthlyRate;
        // OneTime / Milestone scheduling
        uint256[] milestoneDeadlines;
        uint8 currentMilestone;
        uint8 rejectsThisMilestone;
        uint256 firstSubmittedAt; // timestamp of first submission for current milestone (for grace period)
        // Workflow status
        Status status;
        PType paymentType;
        // Metadata
        string projectName;
        string description;
        // Proof
        string currentProofURI;
        uint256 submittedAt; // last submission time (for approval timeout)
        // Execution fee
        bool feePaid;
        uint256 executionFee; // cached fee amount in token units
    }

    // ===== Storage =====
    mapping(uint256 => Agreement) public agreements;
    uint256 public nextId;
    mapping(address => uint256[]) private userAgreements;
    mapping(address => string) public encryptionPublicKey;
    mapping(address => string) public profileCID;

    // ===== Pricing config =====
    uint16 public constant feeBps = 150; // 1.5% in basis points
    uint256 public constant minFeeUsd = 1; // $1 (converted using token decimals)
    uint256 public constant maxFeeUsd = 500; // $500 (converted using token decimals)
    address public immutable treasury;
    address public immutable allowedToken;

    // ===== Rule config =====
    uint256 public constant approvalTimeout = 7 days; // auto-release if company doesn't respond after submission
    uint8 public constant maxRejectsPerMilestone = 3;
    uint256 public constant resubmissionGrace = 2 days; // grace period to resubmit after rejection
    uint256 public constant maxMilestones = 50;

    // ==== Token decimals =====
    uint8 public immutable tokenDecimals;

    // ===== Events =====
    event AgreementCreated(uint256 indexed id, PType indexed pType, string projectName);
    event FundsLocked(uint256 indexed id, uint256 escrowBudget);
    event ExecutionFeePaid(uint256 indexed id, address indexed token, uint256 feeAmount, address indexed treasury);

    event WorkSubmitted(uint256 indexed id, string proofURI);
    event WorkRejected(uint256 indexed id, string reason);
    event WorkAccepted(uint256 indexed id);
    event WorkAutoAccepted(uint256 indexed id);

    event AgreementCancelled(uint256 indexed id, uint256 refundAmount);
    event PaymentReleased(uint256 indexed id, uint256 amount);
    event AgreementCompleted(uint256 indexed id);

    event AgreementDisputed(uint256 indexed id, address indexed raisedBy, string reason);
    event DisputeResolved(uint256 indexed id, uint256 paidToFreelancer, uint256 refundedToCompany);

    event ArbitratorSet(uint256 indexed id, address indexed arbitrator);
    event HubInitialized(address indexed treasury);
    event EncryptionPublicKeyUpdated(address indexed user, string key);
    event ProfileCIDUpdated(address indexed user, string cid);



    constructor(address _initialOwner, address _allowedToken) {
        require(_initialOwner != address(0), "Owner is zero");
        require(_allowedToken != address(0), "Token is zero");
        treasury = _initialOwner;
        allowedToken = _allowedToken;
        
        // Ambil desimal sekali saja di sini
        tokenDecimals = IERC20Metadata(_allowedToken).decimals();
        
        emit HubInitialized(_initialOwner);
}

    modifier onlyArbitrator(uint256 _id) {
        if (msg.sender != agreements[_id].arbitrator) revert OnlyArbitrator();
        _;
    }

    modifier validAgreement(uint256 _id) {
        if (agreements[_id].company == address(0)) revert InvalidAgreement();
        _;
    }

    modifier onlyCompany(uint256 _id) {
        if (msg.sender != agreements[_id].company) revert OnlyCompany();
        _;
    }

    modifier onlyFreelancer(uint256 _id) {
        if (msg.sender != agreements[_id].freelancer) revert OnlyFreelancer();
        _;
    }

    modifier onlyParty(uint256 _id) {
        if (msg.sender != agreements[_id].company && msg.sender != agreements[_id].freelancer) {
            revert OnlyParty();
        }
        _;
    }

    // ===== Fee math =====
    function calculateExecutionFee(address _token, uint256 _totalBudget) public view returns (uint256) {
        if (_token != allowedToken) revert TokenNotAllowed();
            
        uint256 raw = (_totalBudget * feeBps) / 10_000;
        
        // Gunakan variabel internal, bukan external call
        uint256 scale = 10 ** uint256(tokenDecimals);

        uint256 minFee = minFeeUsd * scale;
        uint256 maxFee = maxFeeUsd * scale;

        if (raw < minFee) return minFee;
        if (raw > maxFee) return maxFee;
        return raw;
    }

    // ===== MVP core: create agreement =====
    /**
     * Tahap 1: Inisialisasi Proyek
     */
    function createAgreement(
        address _freelancer,
        address _token,
        uint256 _totalBudget,
        uint256 _monthlyRate,
        uint256[] memory _milestoneDeadlines,
        PType _pType,
        string memory _projectName,
        string memory _description,
        address _arbitrator
    ) external returns (uint256) {
        // Validasi address kosong
        require(_freelancer != address(0), "Freelancer is zero address");
        require(_arbitrator != address(0), "Arbitrator is zero");
        require(_token != address(0), "Token is zero address");

        // Validasi token
        if (_token != allowedToken) revert TokenNotAllowed();

        // Validasi totalBudget
        require(_totalBudget > 0, "Total budget must be > 0");

        // Validasi address
        require(msg.sender != _freelancer, "Cannot contract with yourself");
        require(_arbitrator != msg.sender && _arbitrator != _freelancer, "Arbitrator must be neutral");

        // Validasi input field
        require(bytes(_projectName).length > 0, "Empty project name");
        require(bytes(_description).length > 0, "Empty description");

        if (_pType == PType.Monthly) {
            require(_monthlyRate > 0, "Monthly rate must be > 0");
            require(_monthlyRate <= _totalBudget, "Monthly rate exceeds budget");
            require(_milestoneDeadlines.length == 0, "Monthly: deadlines must be empty");
        } else if (_pType == PType.OneTime) {
            require(_milestoneDeadlines.length == 1, "OneTime needs 1 deadline");
            require(_milestoneDeadlines[0] > block.timestamp, "Deadline must be in future");
        } else {
            // Milestone
            require(_milestoneDeadlines.length > 0, "Milestones must be > 0");
            require(_milestoneDeadlines.length <= maxMilestones, "Too many milestones");

            // deadlines must be strictly increasing and in the future
            require(_milestoneDeadlines[0] > block.timestamp, "Deadline must be in future");
            for (uint256 i = 1; i < _milestoneDeadlines.length; i++) {
                require(_milestoneDeadlines[i] > _milestoneDeadlines[i - 1], "Deadlines not increasing");
            }
        }

        nextId++;

        agreements[nextId] = Agreement({
            company: msg.sender,
            freelancer: _freelancer,
            arbitrator: _arbitrator,
            token: _token,
            totalBudget: _totalBudget,
            amountReleased: 0,
            lastPaymentTime: 0,
            monthlyRate: _pType == PType.Monthly ? _monthlyRate : 0,
            milestoneDeadlines: _pType == PType.Monthly ? new uint256[](0) : _milestoneDeadlines,
            currentMilestone: 0,
            rejectsThisMilestone: 0,
            firstSubmittedAt: 0,
            status: Status.Created,
            paymentType: _pType,
            projectName: _projectName,
            description: _description,
            currentProofURI: "",
            submittedAt: 0,
            feePaid: false,
            executionFee: 0
        });

        userAgreements[msg.sender].push(nextId);
        userAgreements[_freelancer].push(nextId);

        emit AgreementCreated(nextId, _pType, _projectName);
        emit ArbitratorSet(nextId, _arbitrator);
        return nextId;
    }

    // ===== Escrow funding (fee collected here) =====
    /// @notice Deposit escrow and pay execution fee.
    /// @dev Only the agreement company can deposit.
    function deposit(uint256 _id) external nonReentrant validAgreement(_id) onlyCompany(_id) {
        Agreement storage ag = agreements[_id];

        // 1. CHECKS
        require(ag.status == Status.Created, "Agreement not in Created");
        require(!ag.feePaid, "Already funded");

        uint256 fee = calculateExecutionFee(ag.token, ag.totalBudget);

        // 2. EFFECTS (Update semua status internal SEBELUM transfer dana)
        ag.executionFee = fee;
        ag.feePaid = true;
        ag.status = Status.Funded; // PINDAH KE ATAS: Menandai kontrak sudah didanai
        ag.lastPaymentTime = block.timestamp; // PINDAH KE ATAS: Mengunci waktu mulai

        // 3. INTERACTIONS (Transfer dana dilakukan TERAKHIR)
        // Company pays: escrowBudget + executionFee
        IERC20(ag.token).safeTransferFrom(msg.sender, address(this), ag.totalBudget + fee);

        // Fee forwarded to treasury
        if (fee > 0) {
            IERC20(ag.token).safeTransfer(treasury, fee);
            emit ExecutionFeePaid(_id, ag.token, fee, treasury);
        }

        emit FundsLocked(_id, ag.totalBudget);
    }

    // ===== Proof submission / review =====
    /// @notice Submit work proof for review.
    /// @dev Only the assigned freelancer can submit.
    function submitWork(uint256 _id, string memory _proofURI)
        external
        nonReentrant
        validAgreement(_id)
        onlyFreelancer(_id)
    {
        Agreement storage ag = agreements[_id];

        require(ag.status != Status.Disputed, "Agreement is disputed");
        require(ag.status == Status.Funded, "Invalid status for submission");
        require(bytes(_proofURI).length > 0, "Empty proof");

        if (ag.paymentType != PType.Monthly) {
            require(ag.currentMilestone < ag.milestoneDeadlines.length, "Invalid milestone index");

            uint256 activeDeadline = ag.milestoneDeadlines[ag.currentMilestone];

            // If first submission for this milestone, record timestamp and enforce original deadline
            if (ag.firstSubmittedAt == 0) {
                require(block.timestamp <= activeDeadline, "Milestone deadline exceeded");
                ag.firstSubmittedAt = block.timestamp;
            } else {
                // Resubmission allowed until max(originalDeadline, firstSubmit + grace)
                // This ensures early submitters keep their deadline advantage while late rejects get grace extension
                uint256 gracefulDeadline = ag.firstSubmittedAt + resubmissionGrace;
                uint256 effectiveDeadline = activeDeadline > gracefulDeadline ? activeDeadline : gracefulDeadline;
                require(block.timestamp <= effectiveDeadline, "Resubmission window expired");
            }
        }

        ag.currentProofURI = _proofURI;
        ag.submittedAt = block.timestamp;
        ag.status = Status.Proposed;

        emit WorkSubmitted(_id, _proofURI);
    }

    /// @notice Reject submitted work with a reason.
    /// @dev Only the company can reject work.
    function rejectWork(uint256 _id, string memory _reason)
        external
        nonReentrant
        validAgreement(_id)
        onlyCompany(_id)
    {
        Agreement storage ag = agreements[_id];

        require(ag.status != Status.Disputed, "Agreement is disputed");
        require(ag.status == Status.Proposed, "No work submitted for review");
        require(ag.rejectsThisMilestone < maxRejectsPerMilestone, "Reject limit reached");

        ag.status = Status.Funded;
        ag.currentProofURI = "";
        ag.submittedAt = 0;
        ag.rejectsThisMilestone += 1;

        emit WorkRejected(_id, _reason);

        // If reject limit reached, auto-escalate to dispute
        if (ag.rejectsThisMilestone >= maxRejectsPerMilestone) {
            ag.status = Status.Disputed;
            emit AgreementDisputed(_id, msg.sender, "Reject limit reached");
        }
    }

    /// @notice Accept submitted work.
    /// @dev Only the company can accept work.
    function acceptWork(uint256 _id) external nonReentrant validAgreement(_id) onlyCompany(_id) {
        Agreement storage ag = agreements[_id];

        require(ag.status != Status.Disputed, "Agreement is disputed");
        require(ag.status == Status.Proposed, "No work submitted to accept");

        ag.status = Status.Accepted;
        emit WorkAccepted(_id);
    }

    /**
     * Anyone can trigger this to prevent "ghosting" after the approval timeout.
     * It auto-accepts the submission and releases the corresponding payment.
     */
    function autoReleaseIfExpired(uint256 _id) external nonReentrant validAgreement(_id) {
        Agreement storage ag = agreements[_id];

        require(msg.sender == ag.freelancer, "Only the freelancer can trigger auto-release");
        require(ag.status != Status.Disputed, "Agreement is disputed");
        require(ag.status == Status.Proposed, "Not in Proposed");
        require(ag.submittedAt != 0, "No submission timestamp");
        require(block.timestamp >= ag.submittedAt + approvalTimeout, "Approval window not expired");
        if (ag.paymentType == PType.Monthly) {
            require(block.timestamp >= ag.lastPaymentTime + 30 days, "Payment cycle not yet reached");
        }

        ag.status = Status.Accepted;
        emit WorkAutoAccepted(_id);

        _releasePaymentInternal(_id, ag);
    }

    // ===== Cancel / dispute =====
    /// @notice Cancel an agreement under allowed conditions.
    /// @dev Only the company can cancel.
    function cancelAgreement(uint256 _id) external nonReentrant validAgreement(_id) onlyCompany(_id) {
        Agreement storage ag = agreements[_id];

        require(ag.status != Status.Completed && ag.status != Status.Cancelled, "Agreement already finished");
        require(ag.status != Status.Disputed, "Agreement is disputed");

        // If never funded, allow cancellation without any token transfer
        if (ag.status == Status.Created) {
            ag.status = Status.Cancelled;
            emit AgreementCancelled(_id, 0);
            return;
        }

        // Can only cancel when Funded (not during Proposed/Accepted)
        require(ag.status == Status.Funded, "Can only cancel when Funded");

        // For monthly, enforce cycle-based cancellation (must wait 30 days from last payment)
        if (ag.paymentType == PType.Monthly) {
            require(block.timestamp >= ag.lastPaymentTime + 30 days, "Monthly: cannot cancel mid-cycle");
        } else {
            // For non-monthly, prevent cancel after work submission (must dispute instead)
            require(ag.firstSubmittedAt == 0, "Cannot cancel after submission, use dispute");

            // Enforce deadline-based cancellation
            require(ag.currentMilestone < ag.milestoneDeadlines.length, "Invalid milestone index");
            uint256 activeDeadline = ag.milestoneDeadlines[ag.currentMilestone];
            require(block.timestamp > activeDeadline, "Cannot cancel before deadline");
        }

        uint256 refundAmount = ag.totalBudget - ag.amountReleased;
        ag.status = Status.Cancelled;

        if (refundAmount > 0) {
            IERC20(ag.token).safeTransfer(ag.company, refundAmount);
        }
        emit AgreementCancelled(_id, refundAmount);
    }

    /// @notice Raise a dispute for the agreement.
    /// @dev Only the company or freelancer can raise a dispute.
    function raiseDispute(uint256 _id, string calldata _reason) external validAgreement(_id) onlyParty(_id) {
        Agreement storage ag = agreements[_id];

        require(ag.status != Status.Completed && ag.status != Status.Cancelled, "Agreement finished");
        require(ag.status != Status.Disputed, "Already disputed");
        require(ag.status != Status.Created, "Not funded yet");

        // Prevent dispute abuse to block auto-release
        if (ag.status == Status.Proposed) {
            require(ag.submittedAt != 0 && block.timestamp < ag.submittedAt + approvalTimeout, "Too late to dispute");
        }

        ag.status = Status.Disputed;
        emit AgreementDisputed(_id, msg.sender, _reason);
    }

    /**
     * Arbitrator-mediated resolution: splits remaining escrow budget (fee stays non-refundable).
     * - remaining = totalBudget - amountReleased
     * - payToFreelancer + refundToCompany must equal remaining
     * After resolution, agreement is finalized (Completed or Cancelled).
     */
    /// @notice Resolve a dispute and split remaining escrow.
    /// @dev Only the assigned arbitrator can resolve.
    function resolveDispute(uint256 _id, uint256 payToFreelancer, uint256 refundToCompany)
        external
        nonReentrant
        validAgreement(_id)
        onlyArbitrator(_id)
    {
        Agreement storage ag = agreements[_id];

        require(ag.status == Status.Disputed, "Not disputed");

        uint256 remaining = ag.totalBudget - ag.amountReleased;
        require(payToFreelancer + refundToCompany == remaining, "Bad split");

        // 1. UPDATE STATUS (Sesuai cara kamu, ini sudah benar)
        if (refundToCompany == remaining) {
            ag.status = Status.Cancelled;
        } else {
            ag.status = Status.Completed;
            emit AgreementCompleted(_id);
        }

        // 2. FINALIZE / CLEANUP (Pindahin ke sini agar 'Effects' selesai semua)
        ag.currentProofURI = "";
        ag.submittedAt = 0;
        ag.firstSubmittedAt = 0;
        ag.rejectsThisMilestone = 0;

        // 3. UPDATE BALANCE & TRANSFER (Interactions)
        if (payToFreelancer > 0) {
            ag.amountReleased += payToFreelancer; // Efek ke saldo harus sebelum transfer
            IERC20(ag.token).safeTransfer(ag.freelancer, payToFreelancer);
            emit PaymentReleased(_id, payToFreelancer);
        }
        
        if (refundToCompany > 0) {
            IERC20(ag.token).safeTransfer(ag.company, refundToCompany);
        }

        emit DisputeResolved(_id, payToFreelancer, refundToCompany);
    }

    // ===== Payment release =====
    /// @notice Release payment for accepted work or monthly cycle.
    /// @dev Only the company or freelancer can release payment.
    function releasePayment(uint256 _id) external nonReentrant validAgreement(_id) onlyParty(_id) {
        Agreement storage ag = agreements[_id];

        require(ag.status != Status.Disputed, "Agreement is disputed");

        _releasePaymentInternal(_id, ag);
    }

    // Internal; must be called only from nonReentrant entrypoints.
    function _releasePaymentInternal(uint256 _id, Agreement storage ag) internal {
        uint256 payAmount;

        // --- 1. CHECKS & LOGIC (Perhitungan Tetap Sama) ---
        if (ag.paymentType == PType.Monthly) {
            require(ag.status == Status.Accepted, "Monthly work must be accepted");
            require(block.timestamp >= ag.lastPaymentTime + 30 days, "Payment cycle not yet reached");

            if (ag.amountReleased + ag.monthlyRate >= ag.totalBudget) {
                payAmount = ag.totalBudget - ag.amountReleased;
                ag.status = Status.Completed;
            } else {
                payAmount = ag.monthlyRate;
                ag.lastPaymentTime = block.timestamp;
                ag.status = Status.Funded;
            }
        } else {
            require(ag.status == Status.Accepted, "Work must be accepted first");

            if (ag.paymentType == PType.OneTime) {
                payAmount = ag.totalBudget;
                ag.status = Status.Completed;
            } else if (ag.paymentType == PType.Milestone) {
                ag.currentMilestone++;
                uint256 totalMilestones = ag.milestoneDeadlines.length;
                require(totalMilestones > 0, "No milestones defined");
                
                uint256 perMilestone = ag.totalBudget / totalMilestones;
                uint256 remainder = ag.totalBudget % totalMilestones;
                
                if (ag.currentMilestone == totalMilestones) {
                    payAmount = perMilestone + remainder;
                    ag.status = Status.Completed;
                } else {
                    payAmount = perMilestone;
                    ag.status = Status.Funded;
                }
            }
        }

        // --- 2. EFFECTS (Pindahkan Semua Pembersihan ke Sini, SEBELUM Transfer) ---
        // Bersihkan metadata untuk SEMUA tipe pembayaran di satu tempat
        ag.currentProofURI = "";
        ag.submittedAt = 0;
        ag.firstSubmittedAt = 0;
        ag.rejectsThisMilestone = 0;

        if (payAmount > 0) {
            // Update saldo yang dirilis SEBELUM melakukan transfer (Sangat Penting untuk CEI)
            ag.amountReleased += payAmount;

            // --- 3. INTERACTIONS (Transfer Selalu Terakhir) ---
            IERC20(ag.token).safeTransfer(ag.freelancer, payAmount);
            emit PaymentReleased(_id, payAmount);
        }

        // Emit event penyelesaian di akhir
        if (ag.status == Status.Completed) {
            emit AgreementCompleted(_id);
        }
    }

    // ===== Views =====
    function getAgreementsByUser(address _user) external view returns (uint256[] memory) {
        return userAgreements[_user];
    }

    function getAgreementDetails(uint256 _id) external view returns (Agreement memory) {
        return agreements[_id];
    }

    function setEncryptionPublicKey(string calldata key) external {
        require(bytes(key).length > 0, "Key required");
        encryptionPublicKey[msg.sender] = key;
        emit EncryptionPublicKeyUpdated(msg.sender, key);
    }

    function getEncryptionPublicKey(address user) external view returns (string memory) {
        return encryptionPublicKey[user];
    }

    function setProfileCID(string calldata cid) external {
        require(bytes(cid).length > 0, "CID required");
        profileCID[msg.sender] = cid;
        emit ProfileCIDUpdated(msg.sender, cid);
    }

    function getProfileCID(address user) external view returns (string memory) {
        return profileCID[user];
    }
}
