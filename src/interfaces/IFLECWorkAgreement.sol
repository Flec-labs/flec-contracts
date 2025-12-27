// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IFLECWorkAgreement {
    // Event untuk Activity & Proof Log 
    event WorkSubmitted(address indexed freelancer, uint256 timestamp);
    event PaymentReleased(address indexed to, uint256 amount);
    event DisputeTriggered(address indexed by, uint256 timestamp);

    function deposit() external; 
    function submitWork() external; 
    function approveAndRelease() external; 
    function triggerAutoRelease() external; 
    function triggerDispute() external;
}