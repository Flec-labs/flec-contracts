// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IFLECBase.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract FLECOneTime is IFLECBase {
    using SafeERC20 for IERC20;

    // Attributes
    address public company;
    address public freelancer;
    IERC20 public stablecoin;
    uint256 public amount;
    string public description;
    string public proofURI; // Link/Hash bukti kerja
    uint256 public deadlineTimestamp;
    uint256 public approvalWindow;
    uint256 public submissionTimestamp;
    Status public status;

    // Events
    event WorkRejected(address indexed company, uint256 timestamp);
    event Refunded(address indexed company, uint256 amount);
    event WorkSubmittedWithProof(address indexed freelancer, uint256 timestamp, string proofURI);

    // Modifiers
    modifier onlyCompany() { require(msg.sender == company, "FLEC: Only Company"); _; }
    modifier onlyFreelancer() { require(msg.sender == freelancer, "FLEC: Only Freelancer"); _; }

    constructor(
        address _co, 
        address _fr, 
        address _tk, 
        uint256 _am, 
        uint256 _win, 
        uint256 _deadlineDuration, 
        string memory _desc
    ) {
        company = _co;
        freelancer = _fr;
        stablecoin = IERC20(_tk);
        amount = _am;
        approvalWindow = _win;
        description = _desc;
        deadlineTimestamp = block.timestamp + _deadlineDuration;
        status = Status.Created;
    }

    function deposit() external override onlyCompany {
        require(status == Status.Created, "FLEC: Already funded");
        stablecoin.safeTransferFrom(company, address(this), amount);
        status = Status.Funded;
    }

    function submitWork(string memory _proof) external onlyFreelancer {
        require(status == Status.Funded, "FLEC: Not funded");
        require(block.timestamp <= deadlineTimestamp, "FLEC: Deadline passed");
        
        proofURI = _proof; // Simpan bukti kerja
        submissionTimestamp = block.timestamp;
        
        emit WorkSubmittedWithProof(freelancer, block.timestamp, _proof);
    }

    function rejectWork() external onlyCompany {
        require(status == Status.Funded, "FLEC: Invalid status");
        require(submissionTimestamp != 0, "FLEC: No submission to reject");
        
        submissionTimestamp = 0;
        proofURI = ""; // RESET: Bukti kerja dihapus karena ditolak
        
        emit WorkRejected(company, block.timestamp);
    }

    function refund() external onlyCompany {
        require(status == Status.Funded, "FLEC: Invalid status");
        require(submissionTimestamp == 0, "FLEC: Work currently submitted");
        require(block.timestamp > deadlineTimestamp, "FLEC: Deadline not yet passed");

        status = Status.Completed;
        stablecoin.safeTransfer(company, amount);
        emit Refunded(company, amount);
    }

    function approveAndRelease() external onlyCompany {
        require(status == Status.Funded, "FLEC: Invalid status");
        require(submissionTimestamp != 0, "FLEC: No work submitted");
        
        status = Status.Completed;
        stablecoin.safeTransfer(freelancer, amount);
        emit PaymentReleased(freelancer, amount);
    }

    function triggerAutoRelease() external onlyFreelancer {
        require(submissionTimestamp != 0, "FLEC: No work submitted");
        require(block.timestamp >= submissionTimestamp + approvalWindow, "FLEC: Window open");
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