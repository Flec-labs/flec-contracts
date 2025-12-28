// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IFLECBase.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract FLECMonthly is IFLECBase {
    using SafeERC20 for IERC20;

    address public company;
    address public freelancer;
    IERC20 public stablecoin;
    uint256 public monthlyAmount;
    uint256 public totalAmount;
    uint256 public nextPayrollTimestamp;
    Status public status;

    modifier onlyCompany() { require(msg.sender == company, "FLEC: Only Company"); _; }

    constructor(address _co, address _fr, address _tk, uint256 _total) {
        company = _co; freelancer = _fr; stablecoin = IERC20(_tk); 
        totalAmount = _total; monthlyAmount = _total / 12; status = Status.Created;
    }

    function deposit() external override onlyCompany {
        require(status == Status.Created, "FLEC: Already funded");
        stablecoin.safeTransferFrom(company, address(this), totalAmount);
        nextPayrollTimestamp = block.timestamp + 30 days;
        status = Status.Funded;
    }

    function triggerPayroll() external {
        require(block.timestamp >= nextPayrollTimestamp && status == Status.Funded, "FLEC: Not time yet");
        nextPayrollTimestamp += 30 days;
        stablecoin.safeTransfer(freelancer, monthlyAmount);
        emit PaymentReleased(freelancer, monthlyAmount);
    }

    function triggerDispute() external override {
        require(msg.sender == company || msg.sender == freelancer, "FLEC: Unauthorized");
        status = Status.Disputed;
        emit DisputeTriggered(msg.sender, block.timestamp);
    }
}