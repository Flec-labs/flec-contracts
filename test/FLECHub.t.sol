// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/FLECHub.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// 1. MOCK TOKEN DENGAN 6 DESIMAL (SESUAI USDC ASLI)
contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "mUSDC") {
        // Mint 1 juta token ke pembuat (deployer) dengan satuan 6 desimal
        _mint(msg.sender, 1000000 * 10**6);
    }

    // Override fungsi decimals agar menjadi 6 (default ERC20 adalah 18)
    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}

contract FLECHubTest is Test {
    FLECHub public hub;
    MockUSDC public token;

    address public owner = address(1);
    address public company = address(2);
    address public freelancer = address(3);

    // HELPER: Pengganti keyword 'ether' untuk USDC
    uint256 constant USDC = 10**6; 

    function setUp() public {
        vm.startPrank(owner);
        hub = new FLECHub(owner);
        token = new MockUSDC(); // Minting terjadi di sini ke arah 'owner'
        
        // Beri company modal 10.000 USDC (dalam satuan 6 desimal)
        token.transfer(company, 10000 * USDC);
        vm.stopPrank();
    }

    // --- 1. TEST ONE-TIME FLOW (100 USDC) ---
    function testOneTimeFullFlow() public {
        vm.startPrank(company);
        uint256[] memory d = new uint256[](1);
        d[0] = block.timestamp + 1 weeks;

        uint256 budget = 100 * USDC; // 100 USDC

        uint256 id = hub.createAgreement(
            freelancer, address(token), budget, 0, d, 
            FLECHub.PType.OneTime, 1, "Logo Design"
        );

        token.approve(address(hub), budget);
        hub.deposit(id);
        vm.stopPrank();

        vm.prank(freelancer);
        hub.submitWork(id, "ipfs://logo-v1");

        vm.prank(company);
        hub.releasePayment(id);

        assertEq(token.balanceOf(freelancer), 100 * USDC);
        assertEq(uint(hub.getAgreementDetails(id).status), 3); // Status.Completed
    }

    // --- 2. TEST MILESTONE FLOW (100 USDC / 3 Milestone) ---
    function testMilestoneFullFlow() public {
        vm.startPrank(company);
        uint256 totalBudget = 100 * USDC; 
        uint256[] memory d = new uint256[](3);
        d[0] = block.timestamp + 1 weeks;
        d[1] = block.timestamp + 2 weeks;
        d[2] = block.timestamp + 3 weeks;

        uint256 id = hub.createAgreement(
            freelancer, address(token), totalBudget, 0, d, 
            FLECHub.PType.Milestone, 3, "Web Dev"
        );

        token.approve(address(hub), totalBudget);
        hub.deposit(id);
        vm.stopPrank();

        // Milestone 1 & 2 (Masing-masing 33,33 USDC karena pembagian 100/3)
        for(uint i = 0; i < 2; i++) {
            vm.prank(freelancer);
            hub.submitWork(id, "proof");
            vm.prank(company);
            hub.releasePayment(id);
        }

        // Milestone 3 (Final - Harus menyapu sisa desimal agar genap 100)
        vm.prank(freelancer);
        hub.submitWork(id, "final-proof");
        vm.prank(company);
        hub.releasePayment(id);

        assertEq(token.balanceOf(freelancer), 100 * USDC);
        assertEq(uint(hub.getAgreementDetails(id).status), 3);
    }

    // --- 3. TEST MONTHLY FLOW (60 USDC Total, 20/Bulan) ---
    function testMonthlyFullFlow() public {
        vm.startPrank(company);
        uint256 totalBudget = 60 * USDC;
        uint256 rate = 20 * USDC;
        uint256[] memory emptyDeadlines;

        uint256 id = hub.createAgreement(
            freelancer, address(token), totalBudget, rate, emptyDeadlines, 
            FLECHub.PType.Monthly, 0, "Social Media"
        );

        token.approve(address(hub), totalBudget);
        hub.deposit(id);

        // Pencairan 3 bulan
        for(uint i = 0; i < 3; i++) {
            vm.warp(block.timestamp + 31 days);
            hub.releasePayment(id);
        }
        vm.stopPrank();

        assertEq(token.balanceOf(freelancer), 60 * USDC);
        assertEq(uint(hub.getAgreementDetails(id).status), 3);
    }

    // --- 4. TEST REJECT ---
    function testRejectMechanism() public {
        vm.startPrank(company);
        uint256[] memory d = new uint256[](1);
        d[0] = block.timestamp + 1 weeks;
        uint256 id = hub.createAgreement(freelancer, address(token), 10 * USDC, 0, d, FLECHub.PType.OneTime, 1, "Art");
        token.approve(address(hub), 10 * USDC);
        hub.deposit(id);
        vm.stopPrank();

        vm.prank(freelancer);
        hub.submitWork(id, "bad");

        vm.prank(company);
        hub.rejectWork(id, "Revisi ya");

        assertEq(uint(hub.getAgreementDetails(id).status), 1); // Kembali ke Funded
    }

    // --- 5. TEST CANCEL (DEADLINE) ---
    function testCancelFlow() public {
        vm.startPrank(company);
        uint256[] memory d = new uint256[](1);
        d[0] = block.timestamp + 1 days;
        uint256 id = hub.createAgreement(freelancer, address(token), 100 * USDC, 0, d, FLECHub.PType.OneTime, 1, "App");
        token.approve(address(hub), 100 * USDC);
        hub.deposit(id);

        vm.warp(block.timestamp + 2 days);

        uint256 balBefore = token.balanceOf(company);
        hub.cancelAgreement(id);
        uint256 balAfter = token.balanceOf(company);

        assertEq(balAfter - balBefore, 100 * USDC);
        vm.stopPrank();
    }
}