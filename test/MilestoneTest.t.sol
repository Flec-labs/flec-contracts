// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BaseTest.t.sol";

contract MilestoneTest is BaseTest {
    FLECMilestone public agreement;

    function setUp() public override {
        super.setUp();
        vm.startPrank(company);
        address addr = factory.deployMilestone(
            freelancer, 
            address(usdt), 
            TOTAL_BUDGET, 
            WINDOW, 
            "App Development"
        );
        agreement = FLECMilestone(addr);

        // Tambah 2 Milestone
        agreement.addMilestone(400e18, 5 days); // Milestone 1
        agreement.addMilestone(600e18, 10 days); // Milestone 2
        
        usdt.approve(address(agreement), TOTAL_BUDGET);
        agreement.deposit();
        vm.stopPrank();
    }

    function testMilestoneSubmissionAndApproval() public {
        // Milestone 1
        vm.prank(freelancer);
        agreement.submitMilestone("proof-m1");

        vm.prank(company);
        agreement.approveMilestone();
        assertEq(usdt.balanceOf(freelancer), 400e18);

        // Milestone 2
        vm.prank(freelancer);
        agreement.submitMilestone("proof-m2");
        
        // Test Auto Release di Milestone 2
        vm.warp(block.timestamp + WINDOW + 1 seconds);
        vm.prank(freelancer);
        agreement.triggerAutoRelease();

        assertEq(usdt.balanceOf(freelancer), TOTAL_BUDGET);
        assertEq(uint(agreement.status()), 2); // Completed
    }
}