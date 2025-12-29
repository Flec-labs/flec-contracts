// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title FLECHub
 * @dev Monolithic Hub for Freelance Agreements: OneTime, Milestone, and Monthly.
 * Features: Upfront Escrow, Individual Milestone Deadlines, Reject & Cancel Mechanism.
 */
contract FLECHub is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    enum PType { OneTime, Milestone, Monthly }
    enum Status { Created, Funded, Proposed, Accepted, Completed, Cancelled }
    struct Agreement {
        address company;
        address freelancer;
        address token;
        uint256 totalBudget;
        uint256 amountReleased;
        uint256 lastPaymentTime;
        uint256 monthlyRate;
        uint256[] milestoneDeadlines; // Array deadline per milestone
        Status status;
        PType paymentType;
        string projectName;
        string currentProofURI; 
        uint8 totalMilestones;
        uint8 currentMilestone;
    }

    mapping(uint256 => Agreement) public agreements;
    uint256 public nextId;

    // FE Helper: Pencarian ID proyek per user
    mapping(address => uint256[]) private userAgreements;

    event AgreementCreated(uint256 indexed id, PType indexed pType, string projectName);
    event FundsLocked(uint256 indexed id, uint256 totalAmount);
    event WorkSubmitted(uint256 indexed id, string proofURI);
    event WorkRejected(uint256 indexed id, string reason);
    event AgreementCancelled(uint256 indexed id, uint256 refundAmount);
    event PaymentReleased(uint256 indexed id, uint256 amount);

    constructor(address _initialOwner) Ownable(_initialOwner) {}

    /**
     * @dev Tahap 1: Inisialisasi Proyek
     */
    function createAgreement(
        address _freelancer,
        address _token,
        uint256 _totalBudget,
        uint256 _monthlyRate,
        uint256[] memory _milestoneDeadlines,
        PType _pType,
        uint8 _milestoneCount,
        string memory _projectName
    ) external returns (uint256) {
        nextId++;
        
        // Validasi jumlah deadline
        if (_pType == PType.Milestone) {
            require(_milestoneDeadlines.length == _milestoneCount, "Deadline count mismatch");
        } else if (_pType == PType.OneTime) {
            require(_milestoneDeadlines.length == 1, "OneTime needs 1 deadline");
        }

        agreements[nextId] = Agreement({
            company: msg.sender,
            freelancer: _freelancer,
            token: _token,
            totalBudget: _totalBudget,
            amountReleased: 0,
            lastPaymentTime: 0,
            monthlyRate: _pType == PType.Monthly ? _monthlyRate : 0,
            milestoneDeadlines: _pType == PType.Monthly ? new uint256[](0) : _milestoneDeadlines,
            status: Status.Created,
            paymentType: _pType,
            projectName: _projectName,
            currentProofURI: "",
            totalMilestones: _pType == PType.Milestone ? _milestoneCount : 0,
            currentMilestone: 0
        });

        userAgreements[msg.sender].push(nextId);
        userAgreements[_freelancer].push(nextId);

        emit AgreementCreated(nextId, _pType, _projectName);
        return nextId;
    }

    /**
     * @dev Tahap 2: Deposit 100% upfront
     */
    function deposit(uint256 _id) external nonReentrant {
        Agreement storage ag = agreements[_id];
        require(ag.status == Status.Created, "Sudah didanai");
        require(msg.sender == ag.company, "Hanya company");
        
        IERC20(ag.token).safeTransferFrom(msg.sender, address(this), ag.totalBudget);

        ag.status = Status.Funded;
        ag.lastPaymentTime = block.timestamp;
        emit FundsLocked(_id, ag.totalBudget);
    }

    /**
     * @dev Tahap 3: Submit Work dengan validasi deadline per milestone
     */
    function submitWork(uint256 _id, string memory _proofURI) external {
        Agreement storage ag = agreements[_id];
        require(msg.sender == ag.freelancer, "Bukan freelancer");
        require(ag.paymentType != PType.Monthly, "Monthly gausah proof");
        require(ag.status == Status.Funded, "Status salah");

        // Pengecekan deadline aktif
        uint256 activeDeadline = ag.milestoneDeadlines[ag.currentMilestone];
        require(block.timestamp <= activeDeadline, "Melewati deadline milestone ini!");

        ag.currentProofURI = _proofURI;
        ag.status = Status.Proposed;
        emit WorkSubmitted(_id, _proofURI);
    }

    /**
     * @dev FUNGSI REJECT: Company menolak bukti kerja
     */
    function rejectWork(uint256 _id, string memory _reason) external {
        Agreement storage ag = agreements[_id];
        require(msg.sender == ag.company, "Hanya company");
        require(ag.status == Status.Proposed, "Belum ada kiriman kerjaan");

        ag.status = Status.Funded;
        ag.currentProofURI = ""; // Reset proof

        emit WorkRejected(_id, _reason);
    }
    /**
    * @dev FUNGSI ACCEPT: Company menyetujui bukti kerja
    */
    function acceptWork(uint256 _id) external {
        Agreement storage ag = agreements[_id];
        require(msg.sender == ag.company, "Hanya company");
        require(ag.status == Status.Proposed, "Belum ada kiriman kerjaan");

        ag.status = Status.Accepted;
        // Emit event baru jika perlu: emit WorkAccepted(_id);
    }

    /**
     * @dev FUNGSI CANCEL: Company tarik refund jika telat deadline
     */
    function cancelAgreement(uint256 _id) external nonReentrant {
        Agreement storage ag = agreements[_id];
        require(msg.sender == ag.company, "Hanya company");
        require(ag.status != Status.Completed && ag.status != Status.Cancelled, "Sudah selesai");

        if (ag.paymentType != PType.Monthly) {
            uint256 activeDeadline = ag.milestoneDeadlines[ag.currentMilestone];
            require(block.timestamp > activeDeadline, "Belum melewati deadline");
        }

        uint256 refundAmount = ag.totalBudget - ag.amountReleased;
        ag.status = Status.Cancelled;

        IERC20(ag.token).safeTransfer(ag.company, refundAmount);
        emit AgreementCancelled(_id, refundAmount);
    }

    /**
    * @dev Tahap 4: Release Payment (Pencairan Dana)
    * Sekarang bisa dipanggil Company atau Freelancer (Trustless)
    */
    function releasePayment(uint256 _id) external nonReentrant {
        Agreement storage ag = agreements[_id];
        
        // Validasi Dasar: Hanya pihak terlibat yang bisa memicu
        require(msg.sender == ag.company || msg.sender == ag.freelancer, "Bukan pihak terlibat");
        
        uint256 payAmount;

        if (ag.paymentType == PType.Monthly) {
            require(ag.status == Status.Funded, "Status tidak valid");
            require(block.timestamp >= ag.lastPaymentTime + 30 days, "Belum 30 hari");
            
            if (ag.amountReleased + ag.monthlyRate >= ag.totalBudget) {
                payAmount = ag.totalBudget - ag.amountReleased;
                ag.status = Status.Completed;
            } else {
                payAmount = ag.monthlyRate;
                ag.lastPaymentTime = block.timestamp;
            }
        } 
        else {
            // UNTUK ONETIME & MILESTONE: Wajib berstatus Accepted (Sudah disetujui Company)
            require(ag.status == Status.Accepted, "Pekerjaan belum di-accept Company");
            
            if (ag.paymentType == PType.OneTime) {
                payAmount = ag.totalBudget;
                ag.status = Status.Completed;
            } 
            else if (ag.paymentType == PType.Milestone) {
                ag.currentMilestone++;
                
                if (ag.currentMilestone == ag.totalMilestones) {
                    payAmount = ag.totalBudget - ag.amountReleased;
                    ag.status = Status.Completed;
                } else {
                    payAmount = ag.totalBudget / ag.totalMilestones;
                    // Balik ke Funded agar freelancer bisa submit milestone berikutnya
                    ag.status = Status.Funded; 
                }
            }
            ag.currentProofURI = ""; // Bersihkan bukti lama
        }

        ag.amountReleased += payAmount;
        IERC20(ag.token).safeTransfer(ag.freelancer, payAmount);
        emit PaymentReleased(_id, payAmount);
    }

    // --- FRONT-END HELPERS ---
    function getAgreementsByUser(address _user) external view returns (uint256[] memory) {
        return userAgreements[_user];
    }

    function getAgreementDetails(uint256 _id) external view returns (Agreement memory) {
        return agreements[_id];
    }
}