// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BaseTest.t.sol";

contract MonthlyTest is BaseTest {
    FLECMonthly public agreement;
    uint256 public duration = 3; // 3 Bulan

    function setUp() public override {
        super.setUp();
        vm.startPrank(company);
        // Kita pakai angka yang gak bulat (1000 / 3) buat ngetes "sapu bersih"
        address addr = factory.deployMonthly(
            freelancer, 
            address(usdt), 
            1000, 
            duration, 
            "Marketing Retainer"
        );
        agreement = FLECMonthly(addr);
        
        usdt.approve(address(agreement), 1000);
        agreement.deposit();
        vm.stopPrank();
    }

    function testMonthlyPayrollSweep() public {
        // Bulan 1: 1000 / 3 = 333
        vm.warp(block.timestamp + 31 days);
        agreement.triggerPayroll();
        assertEq(usdt.balanceOf(freelancer), 333);

        // Bulan 2: +333 = 666
        vm.warp(block.timestamp + 30 days);
        agreement.triggerPayroll();
        assertEq(usdt.balanceOf(freelancer), 666);

        // Bulan 3: Sapu bersih (Sisa 334)
        vm.warp(block.timestamp + 30 days);
        agreement.triggerPayroll();
        
        // Total harus pas 1000, meskipun 1000 / 3 itu gak bulat
        assertEq(usdt.balanceOf(freelancer), 1000);
        assertEq(uint(agreement.status()), 2); // Completed
    }
}