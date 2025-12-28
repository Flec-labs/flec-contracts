// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BaseTest.t.sol";

contract OneTimeTest is BaseTest {
    FLECOneTime public agreement;

    function setUp() public override {
        super.setUp();
        vm.prank(company);
        address addr = factory.deployOneTime(
            freelancer, 
            address(usdt), 
            TOTAL_BUDGET, 
            WINDOW, 
            DEADLINE, 
            "Project Landing Page"
        );
        agreement = FLECOneTime(addr);
    }

    function testOneTimeFullFlow() public {
        // 1. Deposit
        vm.startPrank(company);
        usdt.approve(address(agreement), TOTAL_BUDGET);
        agreement.deposit();
        vm.stopPrank();

        // 2. Submit (Freelancer)
        vm.prank(freelancer);
        agreement.submitWork("ipfs://bukti-kerja-v1");
        assertEq(agreement.proofURI(), "ipfs://bukti-kerja-v1");

        // 3. Reject (Company)
        vm.prank(company);
        agreement.rejectWork();
        assertEq(agreement.proofURI(), ""); // Harus kosong lagi
        assertEq(agreement.submissionTimestamp(), 0);

        // 4. Submit Lagi (Freelancer)
        vm.prank(freelancer);
        agreement.submitWork("ipfs://bukti-kerja-final");

        // 5. Approve
        vm.prank(company);
        agreement.approveAndRelease();

        assertEq(usdt.balanceOf(freelancer), TOTAL_BUDGET);
    }

    function testRefundIfDeadlinePassed() public {
        vm.startPrank(company);
        usdt.approve(address(agreement), TOTAL_BUDGET);
        agreement.deposit();
        
        // Lewati Deadline tanpa ada submission
        vm.warp(block.timestamp + DEADLINE + 1 seconds);
        
        agreement.refund();
        vm.stopPrank();

        assertEq(usdt.balanceOf(company), TOTAL_BUDGET * 10); // Duit balik utuh
    }
}