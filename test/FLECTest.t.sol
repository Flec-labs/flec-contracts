// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/FLECFactory.sol";
import "./utils/MockToken.sol";

contract FLECTest is Test {
    FLECFactory public factory;
    MockToken public usdt;

    address public company = address(0x1);
    address public freelancer = address(0x2);
    uint256 public constant TOTAL_BUDGET = 1000 * 10**18;
    uint256 public constant WINDOW = 3 days;

    function setUp() public {
        factory = new FLECFactory();
        usdt = new MockToken();
        
        // Setup saldo awal Company
        usdt.mint(company, TOTAL_BUDGET * 3);
    }

    // --- TEST ONE-TIME AGREEMENT ---
    function testOneTimeFlow() public {
        vm.startPrank(company);
        factory.deployOneTime(freelancer, address(usdt), TOTAL_BUDGET, WINDOW);
        address agreementAddr = factory.allAgreements(0);
        FLECOneTime agreement = FLECOneTime(agreementAddr);
        
        usdt.approve(agreementAddr, TOTAL_BUDGET);
        agreement.deposit(); // Dana terkunci
        vm.stopPrank();

        // Freelancer submit
        vm.prank(freelancer);
        agreement.submitWork();

        // Company approve
        vm.prank(company);
        agreement.approveAndRelease();

        assertEq(usdt.balanceOf(freelancer), TOTAL_BUDGET);
        assertEq(uint(agreement.status()), 2); // Completed
    }

    function testOneTimeAutoRelease() public {
        vm.startPrank(company);
        factory.deployOneTime(freelancer, address(usdt), TOTAL_BUDGET, WINDOW);
        address agreementAddr = factory.allAgreements(0);
        FLECOneTime agreement = FLECOneTime(agreementAddr);
        usdt.approve(agreementAddr, TOTAL_BUDGET);
        agreement.deposit();
        vm.stopPrank();

        vm.prank(freelancer);
        agreement.submitWork();

        // Percepat waktu melewati window 3 hari
        vm.warp(block.timestamp + 4 days);

        vm.prank(freelancer);
        agreement.triggerAutoRelease(); // Auto-pay

        assertEq(usdt.balanceOf(freelancer), TOTAL_BUDGET);
    }

    // --- TEST MILESTONE AGREEMENT ---
    function testMilestonePartialRelease() public {
        vm.startPrank(company);
        factory.deployMilestone(freelancer, address(usdt), TOTAL_BUDGET);
        FLECMilestone agreement = FLECMilestone(factory.allAgreements(0));
        
        uint256 m1 = 400 * 10**18;
        uint256 m2 = 600 * 10**18;
        agreement.addMilestone(m1); 
        agreement.addMilestone(m2);
        
        usdt.approve(address(agreement), TOTAL_BUDGET);
        agreement.deposit();

        // Release Milestone 1
        agreement.approveMilestone();
        vm.stopPrank();

        assertEq(usdt.balanceOf(freelancer), m1);
        assertEq(agreement.currentMilestoneIndex(), 1);
    }

    // --- TEST MONTHLY AGREEMENT ---
    function testMonthlyPayroll() public {
        vm.startPrank(company);
        factory.deployMonthly(freelancer, address(usdt), TOTAL_BUDGET);
        FLECMonthly agreement = FLECMonthly(factory.allAgreements(0));
        
        usdt.approve(address(agreement), TOTAL_BUDGET);
        agreement.deposit();
        vm.stopPrank();

        // Maju 30 hari
        vm.warp(block.timestamp + 31 days);

        agreement.triggerPayroll(); // Pembayaran gaji otomatis
        
        assertEq(usdt.balanceOf(freelancer), TOTAL_BUDGET / 12);
    }

    // --- TEST DISPUTE ---
    function testDisputeLock() public {
        vm.startPrank(company);
        factory.deployOneTime(freelancer, address(usdt), TOTAL_BUDGET, WINDOW);
        FLECOneTime agreement = FLECOneTime(factory.allAgreements(0));
        usdt.approve(address(agreement), TOTAL_BUDGET);
        agreement.deposit();

        // Terjadi konflik
        agreement.triggerDispute(); // Status DISPUTED
        vm.stopPrank();

        // Coba release dana saat dispute (harus gagal)
        vm.prank(company);
        vm.expectRevert(); 
        agreement.approveAndRelease(); // Dana tetap terkunci
    }
}