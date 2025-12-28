// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol"; // Fix warning: unchecked transfer
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title FLECHub
 * @dev Monolithic Hub for Freelance Agreements: OneTime, Milestone, and Monthly.
 */
contract FLECHub is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20; // Menggunakan SafeERC20 untuk keamanan transfer

    enum PType { OneTime, Milestone, Monthly }
    enum Status { Created, Funded, Proposed, Completed, Cancelled }

    struct Agreement {
        address company;
        address freelancer;
        address token;
        uint256 totalBudget;        // Dana total yang dikunci di awal (Upfront)
        uint256 amountReleased;     // Akumulasi dana yang sudah cair
        uint256 lastPaymentTime;    // Timestamp untuk kontrol Monthly
        uint256 monthlyRate;        // Dana per bulan (khusus Monthly)
        Status status;
        PType paymentType;
        string projectName;
        string currentProofURI;     // Bukti kerja (OneTime/Milestone)
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
    event PaymentReleased(uint256 indexed id, uint256 amount);

    constructor(address _initialOwner) Ownable(_initialOwner) {}

    /**
     * @dev Tahap 1: Inisialisasi data proyek dan mapping user.
     */
    function createAgreement(
        address _freelancer,
        address _token,
        uint256 _totalBudget,
        uint256 _monthlyRate,
        PType _pType,
        uint8 _milestoneCount,
        string memory _projectName
    ) external returns (uint256) {
        nextId++;
        agreements[nextId] = Agreement({
            company: msg.sender,
            freelancer: _freelancer,
            token: _token,
            totalBudget: _totalBudget,
            amountReleased: 0,
            lastPaymentTime: 0,
            monthlyRate: _pType == PType.Monthly ? _monthlyRate : 0,
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
     * @dev Tahap 2: Deposit 100% budget di muka (Upfront Escrow).
     */
    function deposit(uint256 _id) external nonReentrant {
        Agreement storage ag = agreements[_id];
        require(ag.status == Status.Created, "Sudah didanai");
        require(msg.sender == ag.company, "Hanya company");
        
        // Menggunakan safeTransferFrom untuk fix warning build
        IERC20(ag.token).safeTransferFrom(msg.sender, address(this), ag.totalBudget);

        ag.status = Status.Funded;
        ag.lastPaymentTime = block.timestamp; // Start timer untuk Monthly
        
        emit FundsLocked(_id, ag.totalBudget);
    }

    /**
     * @dev Tahap 3: Submit Work (Wajib untuk OneTime & Milestone, Monthly tidak perlu).
     */
    function submitWork(uint256 _id, string memory _proofURI) external {
        Agreement storage ag = agreements[_id];
        require(msg.sender == ag.freelancer, "Bukan freelancer");
        require(ag.paymentType != PType.Monthly, "Monthly gausah proof");
        require(ag.status == Status.Funded, "Status salah");

        ag.currentProofURI = _proofURI;
        ag.status = Status.Proposed;
        emit WorkSubmitted(_id, _proofURI);
    }

    /**
     * @dev Tahap 4: Pencairan dana dengan logika Anti-Rounding (Sweep Balance).
     */
    function releasePayment(uint256 _id) external nonReentrant {
        Agreement storage ag = agreements[_id];
        require(msg.sender == ag.company, "Hanya company");
        
        uint256 payAmount;

        if (ag.paymentType == PType.Monthly) {
            require(ag.status == Status.Funded, "Status tidak valid");
            require(block.timestamp >= ag.lastPaymentTime + 30 days, "Belum 30 hari");
            
            // Logika Anti-Rounding: Jika ini bulan terakhir, ambil sisa saldo pool
            if (ag.amountReleased + ag.monthlyRate >= ag.totalBudget) {
                payAmount = ag.totalBudget - ag.amountReleased;
                ag.status = Status.Completed;
            } else {
                payAmount = ag.monthlyRate;
                ag.lastPaymentTime = block.timestamp;
            }
        } 
        else {
            require(ag.status == Status.Proposed, "Wajib submit proof dulu");
            
            if (ag.paymentType == PType.OneTime) {
                payAmount = ag.totalBudget;
                ag.status = Status.Completed;
            } 
            else if (ag.paymentType == PType.Milestone) {
                ag.currentMilestone++;
                
                // Logika Anti-Rounding: Milestone terakhir ambil sisa balance agar pool kosong (0)
                if (ag.currentMilestone == ag.totalMilestones) {
                    payAmount = ag.totalBudget - ag.amountReleased;
                    ag.status = Status.Completed;
                } else {
                    payAmount = ag.totalBudget / ag.totalMilestones;
                    ag.status = Status.Funded; // Kembali ke Funded untuk submit proof tahap berikutnya
                }
            }
            ag.currentProofURI = ""; // Reset proof setelah dibayar
        }

        ag.amountReleased += payAmount;
        
        // Menggunakan safeTransfer untuk mengirim dana dari kontrak ke freelancer
        IERC20(ag.token).safeTransfer(ag.freelancer, payAmount);
        
        emit PaymentReleased(_id, payAmount);
    }

    // --- FRONT-END HELPERS ---

    /**
     * @dev Mengambil daftar ID agreement milik user tertentu.
     */
    function getAgreementsByUser(address _user) external view returns (uint256[] memory) {
        return userAgreements[_user];
    }

    /**
     * @dev Mengambil data lengkap agreement berdasarkan ID.
     */
    function getAgreementDetails(uint256 _id) external view returns (Agreement memory) {
        return agreements[_id];
    }
}