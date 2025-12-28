// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IFLECWorkAgreement.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract FLECWorkAgreement is IFLECWorkAgreement {
    using SafeERC20 for IERC20;

    address public company;
    address public freelancer;
    IERC20 public stablecoin;
    
    WorkType public workType;
    Status public status;
    
    uint256 public totalAmount;
    uint256 public approvalWindow;
    uint256 public submissionTimestamp;
    
    struct Milestone {
        uint256 amount;
        bool completed;
    }
    Milestone[] public milestones;
    uint256 public currentMilestoneIndex;

    uint256 public nextPayrollTimestamp;
    uint256 public monthlyAmount;

    modifier onlyCompany() { require(msg.sender == company, "FLEC: Only Company"); _; }
    modifier onlyFreelancer() { require(msg.sender == freelancer, "FLEC: Only Freelancer"); _; }

    constructor(
        address _company, 
        address _freelancer, 
        address _token, 
        uint256 _totalAmount, 
        uint256 _window,
        WorkType _type
    ) {
        company = _company;
        freelancer = _freelancer;
        stablecoin = IERC20(_token);
        totalAmount = _totalAmount;
        approvalWindow = _window;
        workType = _type;
        status = Status.Created;
    }

    function addMilestone(uint256 _amount) external onlyCompany {
        // Perbaikan: Tambahkan pengecekan WorkType
        require(workType == WorkType.Milestone, "FLEC: Only for milestone agreements");
        require(status == Status.Created, "FLEC: Already funded");
        milestones.push(Milestone(_amount, false));
    }

    function deposit() external override onlyCompany {
        require(status == Status.Created, "FLEC: Already funded");
        
        // Untuk Milestone, opsional: tambahkan validasi total milestone == totalAmount
        
        stablecoin.safeTransferFrom(company, address(this), totalAmount);
        
        if (workType == WorkType.Monthly) {
            nextPayrollTimestamp = block.timestamp + 30 days;
            monthlyAmount = totalAmount / 12; // Asumsi kontrak tahunan
        }
        status = Status.Funded;
    }

    function submitWork() external override onlyFreelancer {
        require(status == Status.Funded, "FLEC: Not funded");
        submissionTimestamp = block.timestamp;
        emit WorkSubmitted(freelancer, block.timestamp);
    }

    function approveAndRelease() external override onlyCompany {
        require(status == Status.Funded, "FLEC: Invalid status");

        if (workType == WorkType.OneTime) {
            status = Status.Completed;
            _release(totalAmount);
        } 
        else if (workType == WorkType.Milestone) {
            require(currentMilestoneIndex < milestones.length, "FLEC: All milestones done");
            uint256 amountToPay = milestones[currentMilestoneIndex].amount;
            milestones[currentMilestoneIndex].completed = true;
            currentMilestoneIndex++;
            
            if (currentMilestoneIndex == milestones.length) status = Status.Completed;
            _release(amountToPay);
        }
    }

    function triggerAutoRelease() external override {
        require(status == Status.Funded, "FLEC: Invalid status");

        if (workType == WorkType.Monthly) {
            require(block.timestamp >= nextPayrollTimestamp, "FLEC: Not payroll time yet");
            nextPayrollTimestamp += 30 days;
            _release(monthlyAmount);
        } 
        else {
            require(submissionTimestamp != 0, "FLEC: No submission");
            require(block.timestamp >= submissionTimestamp + approvalWindow, "FLEC: Window open");
            
            if (workType == WorkType.OneTime) {
                status = Status.Completed;
                _release(totalAmount);
            } else {
                uint256 amountToPay = milestones[currentMilestoneIndex].amount;
                milestones[currentMilestoneIndex].completed = true;
                currentMilestoneIndex++;
                if (currentMilestoneIndex == milestones.length) status = Status.Completed;
                _release(amountToPay);
            }
        }
    }

    function triggerDispute() external override {
        require(msg.sender == company || msg.sender == freelancer, "FLEC: Unauthorized");
        status = Status.Disputed;
        emit DisputeTriggered(msg.sender, block.timestamp);
    }

    function _release(uint256 _amount) internal {
        stablecoin.safeTransfer(freelancer, _amount);
        emit PaymentReleased(freelancer, _amount);
    }
}