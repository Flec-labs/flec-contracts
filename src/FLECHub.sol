// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * FLECHub
 * - Work agreement escrow with OneTime / Milestone / Monthly payroll
 * - Execution fee: 1.5% (150 bps) per agreement, paid upfront at first deposit, non-refundable
 * - Optional: approval-timeout auto-release and dispute lock
 */
contract FLECHub is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    enum PType { OneTime, Milestone, Monthly }
    // NOTE: Disputed appended at the end to avoid shifting existing enum values (for new deployments only).
    enum Status { Created, Funded, Proposed, Accepted, Completed, Cancelled, Disputed }

    struct Agreement {
        address company;
        address freelancer;
        address token;

        uint256 totalBudget;      // escrow budget (excludes execution fee)
        uint256 amountReleased;

        // Monthly payroll
        uint256 lastPaymentTime;
        uint256 monthlyRate;

        // OneTime / Milestone scheduling
        uint256[] milestoneDeadlines;
        uint8 totalMilestones;
        uint8 currentMilestone;

        // Workflow status
        Status status;
        PType paymentType;

        // Metadata
        string projectName;
        string description;

        // Proof
        string currentProofURI;
        uint256 submittedAt;      // last submission time (for approval timeout)

        // Execution fee
        bool feePaid;
        uint256 executionFee;     // cached fee amount in token units
    }

    // ===== Storage =====
    mapping(uint256 => Agreement) public agreements;
    uint256 public nextId;
    mapping(address => uint256[]) private userAgreements;

    // ===== Pricing config =====
    uint16 public feeBps = 150;          // 1.5% in basis points
    uint256 public minFeeUsd = 2;        // $2 (converted using token decimals)
    uint256 public maxFeeUsd = 500;      // $500 (converted using token decimals)
    address public treasury;

    // ===== Rule config =====
    uint256 public approvalTimeout = 7 days; // auto-release if company doesn't respond after submission

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

    event FeeConfigUpdated(uint16 feeBps, uint256 minFeeUsd, uint256 maxFeeUsd);
    event TreasuryUpdated(address treasury);
    event ApprovalTimeoutUpdated(uint256 approvalTimeout);

    constructor(address _initialOwner) Ownable(_initialOwner) {
        treasury = _initialOwner;
    }

    // ===== Admin =====
    function setFeeConfig(uint16 _feeBps, uint256 _minFeeUsd, uint256 _maxFeeUsd) external onlyOwner {
        require(_feeBps <= 10_000, "feeBps too large");
        require(_minFeeUsd <= _maxFeeUsd, "minFee > maxFee");
        feeBps = _feeBps;
        minFeeUsd = _minFeeUsd;
        maxFeeUsd = _maxFeeUsd;
        emit FeeConfigUpdated(_feeBps, _minFeeUsd, _maxFeeUsd);
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "treasury is zero");
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    function setApprovalTimeout(uint256 _approvalTimeout) external onlyOwner {
        require(_approvalTimeout >= 1 hours, "timeout too small");
        approvalTimeout = _approvalTimeout;
        emit ApprovalTimeoutUpdated(_approvalTimeout);
    }

    // ===== Fee math =====
    function calculateExecutionFee(address _token, uint256 _totalBudget) public view returns (uint256) {
        // % fee in token units
        uint256 raw = (_totalBudget * feeBps) / 10_000;

        // Convert USD min/max guardrails into token units using token decimals
        uint8 dec = IERC20Metadata(_token).decimals();
        uint256 scale = 10 ** uint256(dec);

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
        uint8 _milestoneCount,
        string memory _projectName,
        string memory _description
    ) external returns (uint256) {
        require(_freelancer != address(0), "Freelancer is zero address");
        require(_token != address(0), "Token is zero address");
        require(_totalBudget > 0, "Total budget must be > 0");

        if (_pType == PType.Monthly) {
            require(_monthlyRate > 0, "Monthly rate must be > 0");
            require(_monthlyRate <= _totalBudget, "Monthly rate exceeds budget");
            require(_milestoneDeadlines.length == 0, "Monthly: deadlines must be empty");
            require(_milestoneCount == 0, "Monthly: milestoneCount must be 0");
        } else if (_pType == PType.OneTime) {
            require(_milestoneDeadlines.length == 1, "OneTime needs 1 deadline");
            require(_milestoneDeadlines[0] > block.timestamp, "Deadline must be in future");
        } else {
            // Milestone
            require(_milestoneCount > 0, "Milestones must be > 0");
            require(_milestoneDeadlines.length == _milestoneCount, "Deadline count mismatch");

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
            token: _token,

            totalBudget: _totalBudget,
            amountReleased: 0,

            lastPaymentTime: 0,
            monthlyRate: _pType == PType.Monthly ? _monthlyRate : 0,

            milestoneDeadlines: _pType == PType.Monthly ? new uint256[](0) : _milestoneDeadlines,
            totalMilestones: _pType == PType.Milestone ? _milestoneCount : 0,
            currentMilestone: 0,

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
        return nextId;
    }

    // ===== Escrow funding (fee collected here) =====
    function deposit(uint256 _id) external nonReentrant {
        Agreement storage ag = agreements[_id];

        require(ag.status == Status.Created, "Agreement not in Created");
        require(msg.sender == ag.company, "Only the company can deposit");
        require(!ag.feePaid, "Already funded");

        uint256 fee = calculateExecutionFee(ag.token, ag.totalBudget);
        ag.executionFee = fee;
        ag.feePaid = true;

        // Company pays: escrowBudget + executionFee
        IERC20(ag.token).safeTransferFrom(msg.sender, address(this), ag.totalBudget + fee);

        // Fee is non-refundable and is immediately forwarded to treasury
        if (fee > 0) {
            IERC20(ag.token).safeTransfer(treasury, fee);
            emit ExecutionFeePaid(_id, ag.token, fee, treasury);
        }

        ag.status = Status.Funded;
        ag.lastPaymentTime = block.timestamp;
        emit FundsLocked(_id, ag.totalBudget);
    }

    // ===== Proof submission / review =====
    function submitWork(uint256 _id, string memory _proofURI) external {
        Agreement storage ag = agreements[_id];

        require(ag.status != Status.Disputed, "Agreement is disputed");
        require(msg.sender == ag.freelancer, "Caller is not the freelancer");
        require(ag.paymentType != PType.Monthly, "Monthly does not require proof");
        require(ag.status == Status.Funded, "Invalid status for submission");

        uint256 activeDeadline = ag.milestoneDeadlines[ag.currentMilestone];
        require(block.timestamp <= activeDeadline, "Milestone deadline exceeded");

        ag.currentProofURI = _proofURI;
        ag.submittedAt = block.timestamp;
        ag.status = Status.Proposed;

        emit WorkSubmitted(_id, _proofURI);
    }

    function rejectWork(uint256 _id, string memory _reason) external {
        Agreement storage ag = agreements[_id];

        require(ag.status != Status.Disputed, "Agreement is disputed");
        require(msg.sender == ag.company, "Only the company can reject work");
        require(ag.status == Status.Proposed, "No work submitted for review");

        ag.status = Status.Funded;
        ag.currentProofURI = "";
        ag.submittedAt = 0;

        emit WorkRejected(_id, _reason);
    }

    function acceptWork(uint256 _id) external {
        Agreement storage ag = agreements[_id];

        require(ag.status != Status.Disputed, "Agreement is disputed");
        require(msg.sender == ag.company, "Only the company can accept work");
        require(ag.status == Status.Proposed, "No work submitted to accept");

        ag.status = Status.Accepted;
        emit WorkAccepted(_id);
    }

    /**
     * Anyone can trigger this to prevent "ghosting" after the approval timeout.
     * It auto-accepts the submission and releases the corresponding payment.
     */
    function autoReleaseIfExpired(uint256 _id) external nonReentrant {
        Agreement storage ag = agreements[_id];

        require(ag.status != Status.Disputed, "Agreement is disputed");
        require(ag.paymentType != PType.Monthly, "Monthly not eligible");
        require(ag.status == Status.Proposed, "Not in Proposed");
        require(ag.submittedAt != 0, "No submission timestamp");
        require(block.timestamp >= ag.submittedAt + approvalTimeout, "Approval window not expired");

        ag.status = Status.Accepted;
        emit WorkAutoAccepted(_id);

        _releasePaymentInternal(_id, ag);
    }

    // ===== Cancel / dispute =====
    function cancelAgreement(uint256 _id) external nonReentrant {
        Agreement storage ag = agreements[_id];

        require(msg.sender == ag.company, "Only the company can cancel");
        require(ag.status != Status.Completed && ag.status != Status.Cancelled, "Agreement already finished");
        require(ag.status != Status.Disputed, "Agreement is disputed");

        // If never funded, allow cancellation without any token transfer
        if (ag.status == Status.Created) {
            ag.status = Status.Cancelled;
            emit AgreementCancelled(_id, 0);
            return;
        }

        // For non-monthly, enforce deadline-based cancellation (current milestone deadline must pass)
        if (ag.paymentType != PType.Monthly) {
            uint256 activeDeadline = ag.milestoneDeadlines[ag.currentMilestone];
            require(block.timestamp > activeDeadline, "Cannot cancel before deadline");
        }

        uint256 refundAmount = ag.totalBudget - ag.amountReleased;
        ag.status = Status.Cancelled;

        IERC20(ag.token).safeTransfer(ag.company, refundAmount);
        emit AgreementCancelled(_id, refundAmount);
    }

    function raiseDispute(uint256 _id, string calldata _reason) external {
        Agreement storage ag = agreements[_id];

        require(msg.sender == ag.company || msg.sender == ag.freelancer, "Not a party");
        require(ag.status != Status.Completed && ag.status != Status.Cancelled, "Agreement finished");
        require(ag.status != Status.Disputed, "Already disputed");
        require(ag.status != Status.Created, "Not funded yet");

        ag.status = Status.Disputed;
        emit AgreementDisputed(_id, msg.sender, _reason);
    }

    /**
     * Owner-mediated resolution (MVP-safe): splits remaining escrow budget (fee stays non-refundable).
     * - remaining = totalBudget - amountReleased
     * - payToFreelancer + refundToCompany must equal remaining
     * After resolution, agreement is finalized (Completed or Cancelled).
     */
    function resolveDispute(
        uint256 _id,
        uint256 payToFreelancer,
        uint256 refundToCompany
    ) external onlyOwner nonReentrant {
        Agreement storage ag = agreements[_id];

        require(ag.status == Status.Disputed, "Not disputed");

        uint256 remaining = ag.totalBudget - ag.amountReleased;
        require(payToFreelancer + refundToCompany == remaining, "Bad split");

        if (payToFreelancer > 0) {
            ag.amountReleased += payToFreelancer;
            IERC20(ag.token).safeTransfer(ag.freelancer, payToFreelancer);
            emit PaymentReleased(_id, payToFreelancer);
        }
        if (refundToCompany > 0) {
            IERC20(ag.token).safeTransfer(ag.company, refundToCompany);
        }

        // Finalize
        ag.currentProofURI = "";
        ag.submittedAt = 0;

        if (refundToCompany == remaining) {
            ag.status = Status.Cancelled;
        } else {
            ag.status = Status.Completed;
            emit AgreementCompleted(_id);
        }

        emit DisputeResolved(_id, payToFreelancer, refundToCompany);
    }

    // ===== Payment release =====
    function releasePayment(uint256 _id) external nonReentrant {
        Agreement storage ag = agreements[_id];

        require(ag.status != Status.Disputed, "Agreement is disputed");
        require(msg.sender == ag.company || msg.sender == ag.freelancer, "Not an authorized party");

        _releasePaymentInternal(_id, ag);
    }

    function _releasePaymentInternal(uint256 _id, Agreement storage ag) internal {
        uint256 payAmount;

        if (ag.paymentType == PType.Monthly) {
            require(ag.status == Status.Funded, "Invalid status for monthly release");
            require(block.timestamp >= ag.lastPaymentTime + 30 days, "Payment cycle not yet reached");

            if (ag.amountReleased + ag.monthlyRate >= ag.totalBudget) {
                payAmount = ag.totalBudget - ag.amountReleased;
                ag.status = Status.Completed;
            } else {
                payAmount = ag.monthlyRate;
                ag.lastPaymentTime = block.timestamp;
            }
        } else {
            require(ag.status == Status.Accepted, "Work must be accepted first");

            if (ag.paymentType == PType.OneTime) {
                payAmount = ag.totalBudget;
                ag.status = Status.Completed;
            } else if (ag.paymentType == PType.Milestone) {
                ag.currentMilestone++;

                if (ag.currentMilestone == ag.totalMilestones) {
                    payAmount = ag.totalBudget - ag.amountReleased;
                    ag.status = Status.Completed;
                } else {
                    payAmount = ag.totalBudget / ag.totalMilestones;
                    ag.status = Status.Funded;
                }
            }

            ag.currentProofURI = "";
            ag.submittedAt = 0;
        }

        ag.amountReleased += payAmount;
        IERC20(ag.token).safeTransfer(ag.freelancer, payAmount);
        emit PaymentReleased(_id, payAmount);

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
}
