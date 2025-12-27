// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./FLECWorkAgreement.sol";

contract FLECFactory {
    address[] public allAgreements;

    function createAgreement(address _freelancer, address _token, uint256 _amount, uint256 _window) external {
        // Deploy kontrak baru sebagai single source of truth
        FLECWorkAgreement newAgreement = new FLECWorkAgreement(
            msg.sender, 
            _freelancer, 
            _token, 
            _amount, 
            _window
        );
        allAgreements.push(address(newAgreement));
    }

    function getAgreementsCount() external view returns (uint256) {
        return allAgreements.length;
    }
}