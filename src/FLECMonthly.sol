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
    
    string public description;
    uint256 public totalAmount;
    uint256 public monthlyAmount;
    uint256 public durationMonths;
    uint256 public paymentsMade;
    
    uint256 public nextPayrollTimestamp;
    Status public status;

    modifier onlyCompany() { require(msg.sender == company, "FLEC: Only Company"); _; }

    // Tambahkan parameter _duration di constructor
    constructor(
        address _co, 
        address _fr, 
        address _tk, 
        uint256 _total, 
        uint256 _duration, 
        string memory _desc
    ) {
        // Durasi tidak boleh 0 agar tidak terjadi 'Division by Zero' error.
        require(_duration > 0, "FLEC: Duration must be > 0");

        company = _co;
        freelancer = _fr;
        stablecoin = IERC20(_tk);
        
        totalAmount = _total;
        durationMonths = _duration; 
        description = _desc;
        
        // MENGHITUNG GAJI BULANAN:
        // Jika _total < _duration, monthlyAmount akan otomatis jadi 0.
        // Ini okay, karena di bulan terakhir (Final Month), fungsi triggerPayroll yang kita implement akan menyapu bersih sisa saldo kontrak.
        monthlyAmount = _total / _duration; 
        
        status = Status.Created;
    }

    function deposit() external override onlyCompany {
        require(status == Status.Created, "FLEC: Already funded");
        stablecoin.safeTransferFrom(company, address(this), totalAmount);
        
        nextPayrollTimestamp = block.timestamp + 30 days;
        status = Status.Funded;
    }

    function triggerPayroll() external {
        require(status == Status.Funded, "FLEC: Not funded");
        require(block.timestamp >= nextPayrollTimestamp, "FLEC: Not time yet");
        require(paymentsMade < durationMonths, "FLEC: Finished");

        paymentsMade++;
        nextPayrollTimestamp += 30 days;

        uint256 amountToSend;
        // JIKA BULAN TERAKHIR: Ambil semua saldo tersisa (mengatasi pembulatan)
        if (paymentsMade == durationMonths) {
            amountToSend = stablecoin.balanceOf(address(this));
            status = Status.Completed;
        } else {
            amountToSend = monthlyAmount;
        }

        stablecoin.safeTransfer(freelancer, amountToSend);
        emit PaymentReleased(freelancer, amountToSend);
    }

    function triggerDispute() external override {
        require(msg.sender == company || msg.sender == freelancer, "FLEC: Unauthorized");
        status = Status.Disputed;
        emit DisputeTriggered(msg.sender, block.timestamp);
    }
}