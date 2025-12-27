// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IFLECWorkAgreement.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Agreement dideploy sebagai smart contract tunggal (Single Source of Truth)
contract FLECWorkAgreement is IFLECWorkAgreement {
    address public company;
    address public freelancer;
    IERC20 public stablecoin; // Menggunakan stablecoin global
    
    uint256 public amount;
    uint256 public approvalWindow; // Window waktu untuk persetujuan
    uint256 public submissionTimestamp;
    
    enum Status { Created, Funded, Completed, Disputed }
    Status public status; // Melacak status agreement

    modifier onlyCompany() { require(msg.sender == company, "FLEC: Only Company"); _; }
    modifier onlyFreelancer() { require(msg.sender == freelancer, "FLEC: Only Freelancer"); _; }

    constructor(address _company, address _freelancer, address _token, uint256 _amount, uint256 _window) {
        company = _company;
        freelancer = _freelancer;
        stablecoin = IERC20(_token);
        amount = _amount;
        approvalWindow = _window;
        status = Status.Created;
    }

    // Escrow Dana: Perusahaan mengunci dana di awal
    function deposit() external override onlyCompany {
        require(status == Status.Created, "FLEC: Already funded");
        require(stablecoin.transferFrom(company, address(this), amount), "FLEC: Transfer failed");
        status = Status.Funded; // Dana terkunci di smart contract
    }

    // Milestone Submission: Freelancer kirim progres
    function submitWork() external override onlyFreelancer {
        require(status == Status.Funded, "FLEC: Not funded");
        submissionTimestamp = block.timestamp;
        emit WorkSubmitted(freelancer, block.timestamp); // Mencatat log on-chain
    }

    // Happy Path: Perusahaan setuju dan dana cair
    function approveAndRelease() external override onlyCompany {
        require(status == Status.Funded, "FLEC: Invalid status");
        status = Status.Completed;
        require(stablecoin.transfer(freelancer, amount), "FLEC: Payment failed");
        emit PaymentReleased(freelancer, amount);
    }

    // Rule-Based: Auto-release jika perusahaan ghosting
    function triggerAutoRelease() external override onlyFreelancer {
        require(submissionTimestamp != 0, "FLEC: Not submitted");
        require(block.timestamp >= submissionTimestamp + approvalWindow, "FLEC: Window open");
        require(status == Status.Funded, "FLEC: Invalid status");

        status = Status.Completed;
        require(stablecoin.transfer(freelancer, amount), "FLEC: Auto-release failed");
        emit PaymentReleased(freelancer, amount);
    }

    // Dispute Lock: Dana dibekukan jika ada konflik
    function triggerDispute() external override {
        require(msg.sender == company || msg.sender == freelancer, "FLEC: Unauthorized");
        status = Status.Disputed; // Dana tetap terkunci, tidak ada eksekusi sepihak
        emit DisputeTriggered(msg.sender, block.timestamp);
    }
}