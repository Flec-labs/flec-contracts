// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./FLECOneTime.sol";
import "./FLECMilestone.sol";
import "./FLECMonthly.sol";

contract FLECFactory {
    event AgreementCreated(
        address indexed company, 
        address indexed freelancer, 
        address agreementAddr, 
        string workType,
        string description
    );

    // OneTime: Sekarang butuh 6 input agar bisa mengirim 7 argumen ke Constructor
    function deployOneTime(
        address _fr, 
        address _tk, 
        uint256 _am, 
        uint256 _win, 
        uint256 _dl, // <--- TAMBAHAN: Deadline duration
        string memory _desc
    ) external returns (address) {
        // Constructor FLECOneTime butuh: co, fr, tk, am, win, dl, desc
        FLECOneTime agr = new FLECOneTime(msg.sender, _fr, _tk, _am, _win, _dl, _desc);
        address agrAddr = address(agr);
        emit AgreementCreated(msg.sender, _fr, agrAddr, "OneTime", _desc);
        return agrAddr;
    }

    // Milestone: Sekarang butuh 5 input agar bisa mengirim 6 argumen ke Constructor
    function deployMilestone(
        address _fr, 
        address _tk, 
        uint256 _total, 
        uint256 _win, // <--- TAMBAHAN: Approval Window (untuk auto-release)
        string memory _desc
    ) external returns (address) {
        // Constructor FLECMilestone butuh: co, fr, tk, total, win, desc
        FLECMilestone agr = new FLECMilestone(msg.sender, _fr, _tk, _total, _win, _desc);
        address agrAddr = address(agr);
        emit AgreementCreated(msg.sender, _fr, agrAddr, "Milestone", _desc);
        return agrAddr;
    }

    // Monthly: Sekarang butuh 5 input agar bisa mengirim 6 argumen ke Constructor
    function deployMonthly(
        address _fr, 
        address _tk, 
        uint256 _total, 
        uint256 _dur, // <--- TAMBAHAN: Duration (bulan)
        string memory _desc
    ) external returns (address) {
        // Constructor FLECMonthly butuh: co, fr, tk, total, dur, desc
        FLECMonthly agr = new FLECMonthly(msg.sender, _fr, _tk, _total, _dur, _desc);
        address agrAddr = address(agr);
        emit AgreementCreated(msg.sender, _fr, agrAddr, "Monthly", _desc);
        return agrAddr;
    }
}