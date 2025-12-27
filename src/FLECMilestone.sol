// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IFLECBase.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract FLECMilestone is IFLECBase {
    using SafeERC20 for IERC20;

    struct Milestone { uint256 amount; bool completed; }
    Milestone[] public milestones;
    uint256 public currentMilestoneIndex;
    uint256 public totalAmount;
    address public company;
    address public freelancer;
    IERC20 public stablecoin;
    Status public status;

    modifier onlyCompany() { require(msg.sender == company, "FLEC: Only Company"); _; }

    constructor(address _co, address _fr, address _tk, uint256 _total) {
        company = _co; freelancer = _fr; stablecoin = IERC20(_tk); 
        totalAmount = _total; status = Status.Created;
    }

    function addMilestone(uint256 _am) external onlyCompany {
        require(status == Status.Created, "FLEC: Already funded");
        milestones.push(Milestone(_am, false));
    }

    function deposit() external override onlyCompany {
        require(status == Status.Created, "FLEC: Already funded");
        stablecoin.safeTransferFrom(company, address(this), totalAmount);
        status = Status.Funded;
    }

    function approveMilestone() external onlyCompany {
        require(status == Status.Funded, "FLEC: Invalid status");
        require(currentMilestoneIndex < milestones.length, "FLEC: All done");
        
        uint256 am = milestones[currentMilestoneIndex].amount;
        milestones[currentMilestoneIndex].completed = true;
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