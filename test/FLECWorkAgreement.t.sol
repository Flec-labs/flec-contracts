// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/FLECWorkAgreement.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock Token sederhana untuk testing
contract MockStablecoin is ERC20 {
    constructor() ERC20("Mock Tether", "USDT") {}
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract FLECWorkAgreementTest is Test {
    FLECWorkAgreement public agreement;
    MockStablecoin public usdt;
    
    address public company = address(0x1);
    address public freelancer = address(0x2);
    uint256 public dealAmount = 1000 * 10**18;
    uint256 public window = 3 days;

    function setUp() public {
        // 1. Deploy Mock USDT
        usdt = new MockStablecoin();
        
        // 2. Deploy Agreement dengan alamat USDT
        agreement = new FLECWorkAgreement(
            company, 
            freelancer, 
            address(usdt), 
            dealAmount, 
            window
        );

        // 3. Beri saldo ke Company dan Approve kontrak 
        usdt.mint(company, dealAmount);
        vm.prank(company);
        usdt.approve(address(agreement), dealAmount);
    }

    // Test: Perusahaan mengunci dana (Escrow)
    function testDepositERC20() public {
        vm.prank(company);
        agreement.deposit();
        
        assertEq(usdt.balanceOf(address(agreement)), dealAmount);
        assertEq(uint(agreement.status()), 1); // Status.Funded
    }

    // Test: Happy Path (Selesai & Bayar)
    function testCompleteWorkFlow() public {
        vm.prank(company);
        agreement.deposit();

        vm.prank(freelancer);
        agreement.submitWork();

        vm.prank(company);
        agreement.approveAndRelease(); 

        assertEq(usdt.balanceOf(freelancer), dealAmount);
        assertEq(uint(agreement.status()), 2); // Status.Completed
    }

    // Test: Anti-Ghosting (Auto-release)
    function testAutoReleaseERC20() public {
        vm.prank(company);
        agreement.deposit();

        vm.prank(freelancer);
        agreement.submitWork();

        // Melewati batas waktu 3 hari
        vm.warp(block.timestamp + 4 days);

        vm.prank(freelancer);
        agreement.triggerAutoRelease();

        assertEq(usdt.balanceOf(freelancer), dealAmount);
    }

    // Test: Dispute (Dana Terkunci)
    function testDisputeLockERC20() public {
        vm.prank(company);
        agreement.deposit();

        vm.prank(freelancer);
        agreement.triggerDispute();

        assertEq(uint(agreement.status()), 3); // Status.Disputed
        // Dana tetap aman di kontrak, tidak bisa ditarik sepihak
        assertEq(usdt.balanceOf(address(agreement)), dealAmount);
    }
}