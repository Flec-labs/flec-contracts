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

    function deployOneTime(
        address _fr, 
        address _tk, 
        uint256 _am, 
        uint256 _win, 
        uint256 _dl,
        string memory _desc
    ) external returns (address) {
        FLECOneTime agr = new FLECOneTime(msg.sender, _fr, _tk, _am, _win, _dl, _desc);
        address agrAddr = address(agr);
        emit AgreementCreated(msg.sender, _fr, agrAddr, "OneTime", _desc);
        return agrAddr;
    }

    function deployMilestone(
        address _fr, 
        address _tk, 
        uint256 _total, 
        uint256 _win, 
        string memory _desc
    ) external returns (address) {
        FLECMilestone agr = new FLECMilestone(msg.sender, _fr, _tk, _total, _win, _desc);
        address agrAddr = address(agr);
        emit AgreementCreated(msg.sender, _fr, agrAddr, "Milestone", _desc);
        return agrAddr;
    }

    function deployMonthly(
        address _fr, 
        address _tk, 
        uint256 _total, 
        uint256 _dur, // Duration (bulan)
        string memory _desc
    ) external returns (address) {
        FLECMonthly agr = new FLECMonthly(msg.sender, _fr, _tk, _total, _dur, _desc);
        address agrAddr = address(agr);
        emit AgreementCreated(msg.sender, _fr, agrAddr, "Monthly", _desc);
        return agrAddr;
    }
}