// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/FLECHub.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock Token untuk testing (seperti USDC)
contract MockToken is ERC20 {
    constructor() ERC20("Mock USDC", "mUSDC") {
        _mint(msg.sender, 1000000 * 10**18);
    }
}

contract FLECHubTest is Test {
    FLECHub public hub;
    MockToken public token;

    address public owner = address(1);
    address public company = address(2);
    address public freelancer = address(3);

    uint256 public constant TOTAL_BUDGET = 100 ether;
    uint256 public constant MONTHLY_RATE = 25 ether;

    function setUp() public {
        vm.startPrank(owner);
        hub = new FLECHub(owner);
        token = new MockToken();
        token.transfer(company, 500 ether); 
        
        vm.stopPrank();
    }

    // --- TEST ONE-TIME PAYMENT ---
    function testOneTimeFlow() public {
        vm.startPrank(company);
        
        // 1. Create
        uint256 id = hub.createAgreement(
            freelancer, address(token), TOTAL_BUDGET, 0, 
            FLECHub.PType.OneTime, 0, "Project Alpha"
        );

        // 2. Deposit
        token.approve(address(hub), TOTAL_BUDGET);
        hub.deposit(id);
        vm.stopPrank();

        // 3. Submit Work (Freelancer)
        vm.prank(freelancer);
        hub.submitWork(id, "ipfs://proof-data");

        // 4. Release
        vm.prank(company);
        hub.releasePayment(id);

        assertEq(token.balanceOf(freelancer), TOTAL_BUDGET);
        
        FLECHub.Agreement memory ag = hub.getAgreementDetails(id);
        assertEq(uint(ag.status), uint(FLECHub.Status.Completed));
    }

    // --- TEST MILESTONE & ROUNDING ---
    function testMilestoneRounding() public {
        // Kasus: Budget 100 dibagi 3 Milestone (100 / 3 = 33.33...)
        // Solidity akan membulatkan ke bawah menjadi 33.
        // Kita tes apakah milestone terakhir "menyapu" sisa saldo (anti-rounding).
        
        uint256 trickyBudget = 100; // 100 wei
        
        vm.startPrank(company);
        uint256 id = hub.createAgreement(
            freelancer, address(token), trickyBudget, 0, 
            FLECHub.PType.Milestone, 3, "Tricky Project"
        );
        token.approve(address(hub), trickyBudget);
        hub.deposit(id);
        vm.stopPrank();

        // Milestone 1 & 2
        for(uint8 i=0; i<2; i++) {
            vm.prank(freelancer);
            hub.submitWork(id, "proof");
            vm.prank(company);
            hub.releasePayment(id);
        }

        // Milestone 3 (Terakhir)
        vm.prank(freelancer);
        hub.submitWork(id, "final-proof");
        vm.prank(company);
        hub.releasePayment(id);

        // Freelancer harus terima GENAP 100, bukan 99 (33+33+33).
        assertEq(token.balanceOf(freelancer), trickyBudget);
    }

    // --- TEST MONTHLY TIMER ---
    function testMonthlyTimer() public {
        vm.startPrank(company);
        uint256 id = hub.createAgreement(
            freelancer, address(token), 100 ether, 25 ether, 
            FLECHub.PType.Monthly, 0, "Monthly Job"
        );
        token.approve(address(hub), 100 ether);
        hub.deposit(id);

        // Coba bayar langsung (harus gagal)
        vm.expectRevert("Belum 30 hari");
        hub.releasePayment(id);

        // Lompat waktu 31 hari
        vm.warp(block.timestamp + 31 days);
        hub.releasePayment(id);
        
        assertEq(token.balanceOf(freelancer), 25 ether);
        vm.stopPrank();
    }

    // --- TEST HELPER ---
    function testUserAgreementsHelper() public {
        vm.prank(company);
        hub.createAgreement(freelancer, address(token), 10, 0, FLECHub.PType.OneTime, 0, "P1");
        
        vm.prank(company);
        hub.createAgreement(freelancer, address(token), 20, 0, FLECHub.PType.OneTime, 0, "P2");

        uint256[] memory ids = hub.getAgreementsByUser(company);
        assertEq(ids.length, 2);
        assertEq(ids[0], 1);
        assertEq(ids[1], 2);
    }
}