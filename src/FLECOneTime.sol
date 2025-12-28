// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IFLECBase.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract FLECOneTime is IFLECBase {
    using SafeERC20 for IERC20;

    address public company;
    address public freelancer;
    IERC20 public stablecoin;
    uint256 public amount;
    uint256 public approvalWindow;
    uint256 public submissionTimestamp;
    Status public status;

    modifier onlyCompany() { require(msg.sender == company, "FLEC: Only Company"); _; }
    modifier onlyFreelancer() { require(msg.sender == freelancer, "FLEC: Only Freelancer"); _; }

    constructor(address _co, address _fr, address _tk, uint256 _am, uint256 _win) {
        company = _co;
        freelancer = _fr;
        stablecoin = IERC20(_tk);
        amount = _am;
        approvalWindow = _win;
        status = Status.Created;
    }

    function deposit() external override onlyCompany {
        require(status == Status.Created, "FLEC: Already funded");
        stablecoin.safeTransferFrom(company, address(this), amount);
        status = Status.Funded;
    }

    function submitWork() external onlyFreelancer {
        require(status == Status.Funded, "FLEC: Not funded");
        submissionTimestamp = block.timestamp;
        emit WorkSubmitted(freelancer, block.timestamp);
    }

    function approveAndRelease() external onlyCompany {
        require(status == Status.Funded, "FLEC: Invalid status");
        status = Status.Completed;
        stablecoin.safeTransfer(freelancer, amount);
        emit PaymentReleased(freelancer, amount);
    }

    function triggerAutoRelease() external onlyFreelancer {
        require(submissionTimestamp != 0 && block.timestamp >= submissionTimestamp + approvalWindow, "FLEC: Window open");
        require(status == Status.Funded, "FLEC: Invalid status");
        status = Status.Completed;
        stablecoin.safeTransfer(freelancer, amount);
        emit PaymentReleased(freelancer, amount);
    }

    function triggerDispute() external override {
        require(msg.sender == company || msg.sender == freelancer, "FLEC: Unauthorized");
        status = Status.Disputed;
        emit DisputeTriggered(msg.sender, block.timestamp);
    }
}