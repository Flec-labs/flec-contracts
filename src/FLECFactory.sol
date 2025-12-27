// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./FLECOneTime.sol";
import "./FLECMilestone.sol";
import "./FLECMonthly.sol";

contract FLECFactory {
    address[] public allAgreements;

    function deployOneTime(address _fr, address _tk, uint256 _am, uint256 _win) external {
        FLECOneTime agr = new FLECOneTime(msg.sender, _fr, _tk, _am, _win);
        allAgreements.push(address(agr));
    }

    function deployMilestone(address _fr, address _tk, uint256 _am) external {
        FLECMilestone agr = new FLECMilestone(msg.sender, _fr, _tk, _am);
        allAgreements.push(address(agr));
    }

    function deployMonthly(address _fr, address _tk, uint256 _total) external {
        FLECMonthly agr = new FLECMonthly(msg.sender, _fr, _tk, _total);
        allAgreements.push(address(agr));
    }

    function getAgreements() external view returns (address[] memory) {
        return allAgreements;
    }
}