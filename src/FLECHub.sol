// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

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
        uint256[] milestoneDeadlines;
        Status status;
        PType paymentType;
        string projectName;
        string description; 
        string currentProofURI; 
        uint8 totalMilestones;
        uint8 currentMilestone;
    }

    mapping(uint256 => Agreement) public agreements;
    uint256 public nextId;
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
        string memory _projectName,
        string memory _description // Parameter baru ditambahkan
    ) external returns (uint256) {
        nextId++;
        
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
            description: _description, // Penugasan deskripsi
            currentProofURI: "",
            totalMilestones: _pType == PType.Milestone ? _milestoneCount : 0,
            currentMilestone: 0
        });

        userAgreements[msg.sender].push(nextId);
        userAgreements[_freelancer].push(nextId);

        emit AgreementCreated(nextId, _pType, _projectName);
        return nextId;
    }

    // ... (fungsi deposit, submitWork, rejectWork, acceptWork, cancelAgreement tetap sama)

    function deposit(uint256 _id) external nonReentrant {
        Agreement storage ag = agreements[_id];
        require(ag.status == Status.Created, "Agreement already funded");
        require(msg.sender == ag.company, "Only the company can deposit");
        
        IERC20(ag.token).safeTransferFrom(msg.sender, address(this), ag.totalBudget);

        ag.status = Status.Funded;
        ag.lastPaymentTime = block.timestamp;
        emit FundsLocked(_id, ag.totalBudget);
    }

    function submitWork(uint256 _id, string memory _proofURI) external {
        Agreement storage ag = agreements[_id];
        require(msg.sender == ag.freelancer, "Caller is not the freelancer");
        require(ag.paymentType != PType.Monthly, "Monthly agreements do not require proof submission");
        require(ag.status == Status.Funded, "Invalid agreement status for submission");

        uint256 activeDeadline = ag.milestoneDeadlines[ag.currentMilestone];
        require(block.timestamp <= activeDeadline, "Milestone deadline exceeded");

        ag.currentProofURI = _proofURI;
        ag.status = Status.Proposed;
        emit WorkSubmitted(_id, _proofURI);
    }

    function rejectWork(uint256 _id, string memory _reason) external {
        Agreement storage ag = agreements[_id];
        require(msg.sender == ag.company, "Only the company can reject work");
        require(ag.status == Status.Proposed, "No work submitted for review");

        ag.status = Status.Funded;
        ag.currentProofURI = ""; 

        emit WorkRejected(_id, _reason);
    }

    function acceptWork(uint256 _id) external {
        Agreement storage ag = agreements[_id];
        require(msg.sender == ag.company, "Only the company can accept work");
        require(ag.status == Status.Proposed, "No work submitted to accept");

        ag.status = Status.Accepted;
    }

    function cancelAgreement(uint256 _id) external nonReentrant {
        Agreement storage ag = agreements[_id];
        require(msg.sender == ag.company, "Only the company can cancel");
        require(ag.status != Status.Completed && ag.status != Status.Cancelled, "Agreement already finished");

        if (ag.paymentType != PType.Monthly) {
            uint256 activeDeadline = ag.milestoneDeadlines[ag.currentMilestone];
            require(block.timestamp > activeDeadline, "Cannot cancel before deadline");
        }

        uint256 refundAmount = ag.totalBudget - ag.amountReleased;
        ag.status = Status.Cancelled;

        IERC20(ag.token).safeTransfer(ag.company, refundAmount);
        emit AgreementCancelled(_id, refundAmount);
    }

    function releasePayment(uint256 _id) external nonReentrant {
        Agreement storage ag = agreements[_id];
        require(msg.sender == ag.company || msg.sender == ag.freelancer, "Not an authorized party");
        
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
        } 
        else {
            require(ag.status == Status.Accepted, "Work must be accepted by company first");
            
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
                    ag.status = Status.Funded; 
                }
            }
            ag.currentProofURI = ""; 
        }

        ag.amountReleased += payAmount;
        IERC20(ag.token).safeTransfer(ag.freelancer, payAmount);
        emit PaymentReleased(_id, payAmount);
    }

    function getAgreementsByUser(address _user) external view returns (uint256[] memory) {
        return userAgreements[_user];
    }

    function getAgreementDetails(uint256 _id) external view returns (Agreement memory) {
        return agreements[_id];
    }
}