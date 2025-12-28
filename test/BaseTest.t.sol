// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/FLECFactory.sol";
import "./utils/MockToken.sol"; 

abstract contract BaseTest is Test {
    FLECFactory public factory;
    MockToken public usdt;

    address public company = address(0x1);
    address public freelancer = address(0x2);
    
    uint256 public constant TOTAL_BUDGET = 1000e18;
    uint256 public constant WINDOW = 3 days;
    uint256 public constant DEADLINE = 7 days;

    function setUp() public virtual {
        factory = new FLECFactory();
        usdt = new MockToken();
        
        // Modal awal untuk Company
        usdt.mint(company, TOTAL_BUDGET * 10);
    }
}