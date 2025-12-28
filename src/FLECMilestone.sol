// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IFLECBase.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract FLECMilestone is IFLECBase {
    using SafeERC20 for IERC20;

    struct Milestone {
        uint256 amount;
        uint256 deadlineTimestamp;   // Deadline untuk milestone ini
        uint256 submissionTimestamp; // Kapan milestone ini di-submit
        string proofURI;             // Bukti kerja milestone ini
        bool completed;
    }

    // Attributes
    Milestone[] public milestones;
    string public description;
    uint256 public currentMilestoneIndex;
    uint256 public totalAmount;
    uint256 public approvalWindow; // Window waktu auto-release (global untuk semua milestone)
    address public company;
    address public freelancer;
    IERC20 public stablecoin;
    Status public status;

    // Events
    event MilestoneSubmitted(uint256 indexed index, string proofURI);
    event MilestoneRejected(uint256 indexed index);
    event MilestoneRefunded(uint256 amount);

    // Modifiers
    modifier onlyCompany() { require(msg.sender == company, "FLEC: Only Company"); _; }
    modifier onlyFreelancer() { require(msg.sender == freelancer, "FLEC: Only Freelancer"); _; }

    constructor(
        address _co, 
        address _fr, 
        address _tk, 
        uint256 _total, 
        uint256 _win, 
        string memory _desc
    ) {
        company = _co; 
        freelancer = _fr; 
        stablecoin = IERC20(_tk); 
        totalAmount = _total; 
        approvalWindow = _win;
        description = _desc; 
        status = Status.Created;
    }

    // Menambahkan milestone dengan durasi deadline-nya masing-masing
    function addMilestone(uint256 _am, uint256 _deadlineDuration) external onlyCompany {
        require(status == Status.Created, "FLEC: Already funded");
        
        // Deadline dihitung dari waktu penambahan atau bisa juga relatif
        uint256 dl = block.timestamp + _deadlineDuration;
        milestones.push(Milestone(_am, dl, 0, "", false));
    }

    function deposit() external override onlyCompany {
        require(status == Status.Created, "FLEC: Already funded");
        require(milestones.length > 0, "FLEC: No milestones added");
        
        stablecoin.safeTransferFrom(company, address(this), totalAmount);
        status = Status.Funded;
    }

    // Freelancer submit per milestone yang aktif
    function submitMilestone(string memory _proof) external onlyFreelancer {
        require(status == Status.Funded, "FLEC: Not funded");
        Milestone storage m = milestones[currentMilestoneIndex];
        
        require(block.timestamp <= m.deadlineTimestamp, "FLEC: Deadline passed");
        require(!m.completed, "FLEC: Already completed");

        m.proofURI = _proof;
        m.submissionTimestamp = block.timestamp;

        emit MilestoneSubmitted(currentMilestoneIndex, _proof);
    }

    // Company reject submission milestone yang aktif
    function rejectMilestone() external onlyCompany {
        require(status == Status.Funded, "FLEC: Invalid status");
        Milestone storage m = milestones[currentMilestoneIndex];
        
        require(m.submissionTimestamp != 0, "FLEC: No submission");
        
        m.submissionTimestamp = 0;
        m.proofURI = "";
        
        emit MilestoneRejected(currentMilestoneIndex);
    }

    // Pembayaran manual oleh Company
    function approveMilestone() external onlyCompany {
        require(status == Status.Funded, "FLEC: Invalid status");
        _releaseMilestone();
    }

    // Auto-release jika Company ghosting setelah submission
    function triggerAutoRelease() external onlyFreelancer {
        Milestone storage m = milestones[currentMilestoneIndex];
        require(m.submissionTimestamp != 0, "FLEC: No work submitted");
        require(block.timestamp >= m.submissionTimestamp + approvalWindow, "FLEC: Window open");
        
        _releaseMilestone();
    }

    // Refund sisa dana jika Milestone melewati deadline tanpa submission
    function refundRemaining() external onlyCompany {
        require(status == Status.Funded, "FLEC: Invalid status");
        Milestone storage m = milestones[currentMilestoneIndex];
        
        require(m.submissionTimestamp == 0, "FLEC: Work submitted");
        require(block.timestamp > m.deadlineTimestamp, "FLEC: Deadline not passed");

        uint256 remaining = stablecoin.balanceOf(address(this));
        status = Status.Completed; // Tutup kontrak
        stablecoin.safeTransfer(company, remaining);
        
        emit MilestoneRefunded(remaining);
    }

    function _releaseMilestone() internal {
        require(currentMilestoneIndex < milestones.length, "FLEC: All done");
        Milestone storage m = milestones[currentMilestoneIndex];
        require(m.submissionTimestamp != 0, "FLEC: Not submitted");

        uint256 am = m.amount;
        m.completed = true;
        currentMilestoneIndex++;
        
        if(currentMilestoneIndex == milestones.length) status = Status.Completed;
        
        stablecoin.safeTransfer(freelancer, am);
        emit PaymentReleased(freelancer, am);
    }

    function triggerDispute() external override {
        require(msg.sender == company || msg.sender == freelancer, "FLEC: Unauthorized");
        status = Status.Disputed;
        emit DisputeTriggered(msg.sender, block.timestamp);
    }
}