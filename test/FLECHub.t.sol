// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/FLECHub.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "mUSDC") {
        _mint(msg.sender, 1000000 * 10**6);
    }

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

    uint256 constant USDC = 10**6; 

    function setUp() public {
        vm.startPrank(owner);
        hub = new FLECHub(owner);
        token = new MockUSDC();
        token.transfer(company, 10000 * USDC);
        vm.stopPrank();
    }

    // --- 1. TEST ONE-TIME FLOW ---
    function testOneTimeFullFlow() public {
        vm.startPrank(company);
        uint256[] memory d = new uint256[](1);
        d[0] = block.timestamp + 1 weeks;
        uint256 budget = 100 * USDC;

        uint256 id = hub.createAgreement(
            freelancer, 
            address(token), 
            budget, 
            0, 
            d, 
            FLECHub.PType.OneTime, 
            1, 
            "Logo Design", 
            "Design a minimalist logo with 3 revisions" // Added Description
        );

        uint256 fee = hub.calculateExecutionFee(address(token), budget);
        token.approve(address(hub), budget + fee);
        hub.deposit(id);
        vm.stopPrank();

        vm.prank(freelancer);
        hub.submitWork(id, "ipfs://logo-v1");

        vm.prank(company);
        hub.acceptWork(id);

        vm.prank(freelancer);
        hub.releasePayment(id);

        assertEq(token.balanceOf(freelancer), 100 * USDC);
        assertEq(uint(hub.getAgreementDetails(id).status), 4);
        assertEq(hub.getAgreementDetails(id).description, "Design a minimalist logo with 3 revisions");
    }

    // --- 2. TEST MILESTONE FLOW ---
    function testMilestoneFullFlow() public {
        vm.startPrank(company);
        uint256 totalBudget = 100 * USDC; 
        uint256[] memory d = new uint256[](3);
        d[0] = block.timestamp + 1 weeks;
        d[1] = block.timestamp + 2 weeks;
        d[2] = block.timestamp + 3 weeks;

        uint256 id = hub.createAgreement(
            freelancer, 
            address(token), 
            totalBudget, 
            0, 
            d, 
            FLECHub.PType.Milestone, 
            3, 
            "Web Dev",
            "Develop a landing page, dashboard, and API integration" // Added Description
        );

        uint256 fee = hub.calculateExecutionFee(address(token), totalBudget);
        token.approve(address(hub), totalBudget + fee);
        hub.deposit(id);
        vm.stopPrank();

        for(uint i = 0; i < 3; i++) {
            vm.prank(freelancer);
            hub.submitWork(id, "proof");

            vm.prank(company);
            hub.acceptWork(id); 

            vm.prank(company);
            hub.releasePayment(id);
        }

        assertEq(token.balanceOf(freelancer), 100 * USDC);
        assertEq(uint(hub.getAgreementDetails(id).status), 4);
    }

    // --- 3. TEST REJECT ---
    function testRejectMechanism() public {
        vm.startPrank(company);
        uint256[] memory d = new uint256[](1);
        d[0] = block.timestamp + 1 weeks;
        uint256 id = hub.createAgreement(
            freelancer, 
            address(token), 
            10 * USDC, 
            0, 
            d, 
            FLECHub.PType.OneTime, 
            1, 
            "Art", 
            "Digital illustration task" // Added Description
        );
        uint256 fee = hub.calculateExecutionFee(address(token), 10 * USDC);
        token.approve(address(hub), 10 * USDC + fee);
        hub.deposit(id);
        vm.stopPrank();

        vm.prank(freelancer);
        hub.submitWork(id, "bad");

        vm.prank(company);
        hub.rejectWork(id, "Revision needed: poor quality");

        assertEq(uint(hub.getAgreementDetails(id).status), 1);
    }

    // --- 4. TEST CANCEL (DEADLINE) ---
    function testCancelFlow() public {
        vm.startPrank(company);
        uint256[] memory d = new uint256[](1);
        d[0] = block.timestamp + 1 days;
        uint256 id = hub.createAgreement(
            freelancer, 
            address(token), 
            100 * USDC, 
            0, 
            d, 
            FLECHub.PType.OneTime, 
            1, 
            "App", 
            "Mobile app development" // Added Description
        );
        uint256 fee = hub.calculateExecutionFee(address(token), 100 * USDC);
        token.approve(address(hub), 100 * USDC + fee);
        hub.deposit(id);

        vm.warp(block.timestamp + 2 days);

        uint256 balBefore = token.balanceOf(company);
        hub.cancelAgreement(id);
        uint256 balAfter = token.balanceOf(company);

        assertEq(balAfter - balBefore, 100 * USDC);
        assertEq(uint(hub.getAgreementDetails(id).status), 5);
        vm.stopPrank();
    }

    // --- 5. TEST REVERT MESSAGES ---
    
    function test_RevertWhen_SubmitWorkAfterDeadline() public {
        vm.startPrank(company);
        uint256[] memory d = new uint256[](1);
        d[0] = block.timestamp + 1 hours;
        uint256 id = hub.createAgreement(
            freelancer, 
            address(token), 
            10 * USDC, 
            0, 
            d, 
            FLECHub.PType.OneTime, 
            1, 
            "Quick Task", 
            "Needs to be done fast" // Added Description
        );
        uint256 fee = hub.calculateExecutionFee(address(token), 10 * USDC);
        token.approve(address(hub), 10 * USDC + fee);
        hub.deposit(id);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 hours);

        vm.expectRevert("Milestone deadline exceeded");
        vm.prank(freelancer);
        hub.submitWork(id, "late-proof");
    }

    function test_RevertWhen_ReleaseBeforeAccept() public {
        vm.startPrank(company);
        uint256[] memory d = new uint256[](1);
        d[0] = block.timestamp + 1 weeks;
        uint256 id = hub.createAgreement(
            freelancer, 
            address(token), 
            10 * USDC, 
            0, 
            d, 
            FLECHub.PType.OneTime, 
            1, 
            "Art", 
            "Illustration" // Added Description
        );
        uint256 fee = hub.calculateExecutionFee(address(token), 10 * USDC);
        token.approve(address(hub), 10 * USDC + fee);
        hub.deposit(id);
        vm.stopPrank();

        vm.prank(freelancer);
        hub.submitWork(id, "proof");

        vm.expectRevert("Work must be accepted by company first");
        vm.prank(freelancer);
        hub.releasePayment(id);
    }

    function test_RevertWhen_CallerNotCompanyDeposits() public {
        vm.startPrank(company);
        uint256[] memory d = new uint256[](1);
        d[0] = block.timestamp + 1 weeks;
        uint256 id = hub.createAgreement(
            freelancer, 
            address(token), 
            10 * USDC, 
            0, 
            d, 
            FLECHub.PType.OneTime, 
            1, 
            "Art", 
            "Illustration" // Added Description
        );
        vm.stopPrank();

        vm.expectRevert("Only the company can deposit");
        vm.prank(freelancer);
        hub.deposit(id);
    }
}