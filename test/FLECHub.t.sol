// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.30;

// import "forge-std/Test.sol";
// import "../src/FLECHub.sol";
// import "../src/FLECHubErrors.sol";
// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// contract MockUSDC is ERC20 {
//     constructor() ERC20("Mock USDC", "mUSDC") {
//         _mint(msg.sender, 1000000 * 10 ** 6);
//     }

//     function decimals() public view virtual override returns (uint8) {
//         return 6;
//     }
// }

// contract MockBadDecimals is ERC20 {
//     constructor() ERC20("Mock Bad", "mBAD") {
//         _mint(msg.sender, 1000000 * 10 ** 19);
//     }

//     function decimals() public view virtual override returns (uint8) {
//         return 19;
//     }
// }

// contract FLECHubTest is Test {
//     FLECHub public hub;
//     MockUSDC public token;

//     address public owner = address(1);
//     address public company = address(2);
//     address public freelancer = address(3);
//     address public arbitrator = address(4);

//     uint256 constant USDC = 10 ** 6;

//     function setUp() public {
//         vm.startPrank(owner);
//         hub = new FLECHub(owner);
//         token = new MockUSDC();
//         token.transfer(company, 10000 * USDC);
//         vm.stopPrank();
//     }

//     // --- 1. TEST ONE-TIME FLOW ---
//     function testOneTimeFullFlow() public {
//         vm.startPrank(company);
//         uint256[] memory d = new uint256[](1);
//         d[0] = block.timestamp + 1 weeks;
//         uint256 budget = 100 * USDC;

//         uint256 id = hub.createAgreement(
//             freelancer,
//             address(token),
//             budget,
//             0,
//             d,
//             FLECHub.PType.OneTime,
//             "Logo Design",
//             "Design a minimalist logo with 3 revisions",
//             arbitrator
//         );

//         uint256 fee = hub.calculateExecutionFee(address(token), budget);
//         token.approve(address(hub), budget + fee);
//         hub.deposit(id);
//         vm.stopPrank();

//         vm.prank(freelancer);
//         hub.submitWork(id, "ipfs://logo-v1");

//         vm.prank(company);
//         hub.acceptWork(id);

//         vm.prank(freelancer);
//         hub.releasePayment(id);

//         assertEq(token.balanceOf(freelancer), 100 * USDC);
//         assertEq(uint256(hub.getAgreementDetails(id).status), 4);
//         assertEq(hub.getAgreementDetails(id).description, "Design a minimalist logo with 3 revisions");
//     }

//     // --- 2. TEST MILESTONE FLOW ---
//     function testMilestoneFullFlow() public {
//         vm.startPrank(company);
//         uint256 totalBudget = 100 * USDC;
//         uint256[] memory d = new uint256[](3);
//         d[0] = block.timestamp + 1 weeks;
//         d[1] = block.timestamp + 2 weeks;
//         d[2] = block.timestamp + 3 weeks;

//         uint256 id = hub.createAgreement(
//             freelancer,
//             address(token),
//             totalBudget,
//             0,
//             d,
//             FLECHub.PType.Milestone,
//             "Web Dev",
//             "Develop a landing page, dashboard, and API integration",
//             arbitrator
//         );

//         uint256 fee = hub.calculateExecutionFee(address(token), totalBudget);
//         token.approve(address(hub), totalBudget + fee);
//         hub.deposit(id);
//         vm.stopPrank();

//         for (uint256 i = 0; i < 3; i++) {
//             vm.prank(freelancer);
//             hub.submitWork(id, "proof");

//             vm.prank(company);
//             hub.acceptWork(id);

//             vm.prank(company);
//             hub.releasePayment(id);
//         }

//         assertEq(token.balanceOf(freelancer), 100 * USDC);
//         assertEq(uint256(hub.getAgreementDetails(id).status), 4);
//     }

//     // --- 3. TEST REJECT ---
//     function testRejectMechanism() public {
//         vm.startPrank(company);
//         uint256[] memory d = new uint256[](1);
//         d[0] = block.timestamp + 1 weeks;
//         uint256 id = hub.createAgreement(
//             freelancer,
//             address(token),
//             10 * USDC,
//             0,
//             d,
//             FLECHub.PType.OneTime,
//             "Art",
//             "Digital illustration task",
//             arbitrator
//         );
//         uint256 fee = hub.calculateExecutionFee(address(token), 10 * USDC);
//         token.approve(address(hub), 10 * USDC + fee);
//         hub.deposit(id);
//         vm.stopPrank();

//         vm.prank(freelancer);
//         hub.submitWork(id, "bad");

//         vm.prank(company);
//         hub.rejectWork(id, "Revision needed: poor quality");

//         assertEq(uint256(hub.getAgreementDetails(id).status), 1);
//     }

//     // --- 4. TEST CANCEL (DEADLINE) ---
//     function testCancelFlow() public {
//         vm.startPrank(company);
//         uint256[] memory d = new uint256[](1);
//         d[0] = block.timestamp + 1 days;
//         uint256 id = hub.createAgreement(
//             freelancer,
//             address(token),
//             100 * USDC,
//             0,
//             d,
//             FLECHub.PType.OneTime,
//             "App",
//             "Mobile app development",
//             arbitrator
//         );
//         uint256 fee = hub.calculateExecutionFee(address(token), 100 * USDC);
//         token.approve(address(hub), 100 * USDC + fee);
//         hub.deposit(id);

//         vm.warp(block.timestamp + 2 days);

//         uint256 balBefore = token.balanceOf(company);
//         hub.cancelAgreement(id);
//         uint256 balAfter = token.balanceOf(company);

//         assertEq(balAfter - balBefore, 100 * USDC);
//         assertEq(uint256(hub.getAgreementDetails(id).status), 5);
//         vm.stopPrank();
//     }

//     // --- 5. TEST REVERT MESSAGES ---

//     function test_RevertWhen_SubmitWorkAfterDeadline() public {
//         vm.startPrank(company);
//         uint256[] memory d = new uint256[](1);
//         d[0] = block.timestamp + 1 hours;
//         uint256 id = hub.createAgreement(
//             freelancer,
//             address(token),
//             10 * USDC,
//             0,
//             d,
//             FLECHub.PType.OneTime,
//             "Quick Task",
//             "Needs to be done fast",
//             arbitrator
//         );
//         uint256 fee = hub.calculateExecutionFee(address(token), 10 * USDC);
//         token.approve(address(hub), 10 * USDC + fee);
//         hub.deposit(id);
//         vm.stopPrank();

//         vm.warp(block.timestamp + 2 hours);

//         vm.expectRevert("Milestone deadline exceeded");
//         vm.prank(freelancer);
//         hub.submitWork(id, "late-proof");
//     }

//     function test_RevertWhen_ReleaseBeforeAccept() public {
//         vm.startPrank(company);
//         uint256[] memory d = new uint256[](1);
//         d[0] = block.timestamp + 1 weeks;
//         uint256 id = hub.createAgreement(
//             freelancer, address(token), 10 * USDC, 0, d, FLECHub.PType.OneTime, "Art", "Illustration", arbitrator
//         );
//         uint256 fee = hub.calculateExecutionFee(address(token), 10 * USDC);
//         token.approve(address(hub), 10 * USDC + fee);
//         hub.deposit(id);
//         vm.stopPrank();

//         vm.prank(freelancer);
//         hub.submitWork(id, "proof");

//         vm.expectRevert("Work must be accepted first");
//         vm.prank(freelancer);
//         hub.releasePayment(id);
//     }

//     function test_RevertWhen_CallerNotCompanyDeposits() public {
//         vm.startPrank(company);
//         uint256[] memory d = new uint256[](1);
//         d[0] = block.timestamp + 1 weeks;
//         uint256 id = hub.createAgreement(
//             freelancer, address(token), 10 * USDC, 0, d, FLECHub.PType.OneTime, "Art", "Illustration", arbitrator
//         );
//         vm.stopPrank();

//         vm.expectRevert(abi.encodeWithSelector(FLECHubErrors.OnlyCompany.selector));
//         vm.prank(freelancer);
//         hub.deposit(id);
//     }

//     function test_RevertWhen_InvalidAgreement() public {
//         vm.expectRevert(abi.encodeWithSelector(FLECHubErrors.InvalidAgreement.selector));
//         vm.prank(company);
//         hub.deposit(999);
//     }

//     function test_RevertWhen_UnsupportedDecimals() public {
//         MockBadDecimals bad = new MockBadDecimals();
//         vm.expectRevert(abi.encodeWithSelector(FLECHubErrors.UnsupportedDecimals.selector));
//         hub.calculateExecutionFee(address(bad), 100 * USDC);
//     }

//     // --- 6. TEST MONTHLY FLOW ---
//     function testMonthlyFlow() public {
//         vm.startPrank(company);
//         uint256 totalBudget = 70 * USDC;
//         uint256 monthlyRate = 30 * USDC;
//         uint256[] memory d = new uint256[](0);

//         uint256 id = hub.createAgreement(
//             freelancer,
//             address(token),
//             totalBudget,
//             monthlyRate,
//             d,
//             FLECHub.PType.Monthly,
//             "Retainer",
//             "Monthly maintenance",
//             arbitrator
//         );

//         uint256 fee = hub.calculateExecutionFee(address(token), totalBudget);
//         token.approve(address(hub), totalBudget + fee);
//         hub.deposit(id);

//         vm.warp(hub.getAgreementDetails(id).lastPaymentTime + 30 days);
//         hub.releasePayment(id);

//         vm.warp(hub.getAgreementDetails(id).lastPaymentTime + 30 days);
//         hub.releasePayment(id);

//         vm.warp(hub.getAgreementDetails(id).lastPaymentTime + 30 days);
//         hub.releasePayment(id);

//         vm.stopPrank();

//         assertEq(token.balanceOf(freelancer), totalBudget);
//         assertEq(uint256(hub.getAgreementDetails(id).status), 4);
//     }

//     // --- 7. TEST DISPUTE FLOW ---
//     function testDisputeFullRefundToCompany() public {
//         vm.startPrank(company);
//         uint256[] memory d = new uint256[](1);
//         d[0] = block.timestamp + 1 weeks;
//         uint256 id = hub.createAgreement(
//             freelancer, address(token), 20 * USDC, 0, d, FLECHub.PType.OneTime, "Fix Bug", "Critical patch", arbitrator
//         );
//         uint256 fee = hub.calculateExecutionFee(address(token), 20 * USDC);
//         token.approve(address(hub), 20 * USDC + fee);
//         hub.deposit(id);
//         vm.stopPrank();

//         vm.prank(company);
//         hub.raiseDispute(id, "Not satisfied");

//         uint256 balBefore = token.balanceOf(company);
//         vm.prank(arbitrator);
//         hub.resolveDispute(id, 0, 20 * USDC);
//         uint256 balAfter = token.balanceOf(company);

//         assertEq(balAfter - balBefore, 20 * USDC);
//         assertEq(uint256(hub.getAgreementDetails(id).status), 5);
//     }

//     function testDisputeSplitToFreelancerAndCompany() public {
//         vm.startPrank(company);
//         uint256[] memory d = new uint256[](1);
//         d[0] = block.timestamp + 1 weeks;
//         uint256 id = hub.createAgreement(
//             freelancer, address(token), 40 * USDC, 0, d, FLECHub.PType.OneTime, "Design", "Partial delivery", arbitrator
//         );
//         uint256 fee = hub.calculateExecutionFee(address(token), 40 * USDC);
//         token.approve(address(hub), 40 * USDC + fee);
//         hub.deposit(id);
//         vm.stopPrank();

//         vm.prank(freelancer);
//         hub.raiseDispute(id, "Delivered partial");

//         uint256 freelancerBefore = token.balanceOf(freelancer);
//         uint256 companyBefore = token.balanceOf(company);
//         vm.prank(arbitrator);
//         hub.resolveDispute(id, 15 * USDC, 25 * USDC);
//         uint256 freelancerAfter = token.balanceOf(freelancer);
//         uint256 companyAfter = token.balanceOf(company);

//         assertEq(freelancerAfter - freelancerBefore, 15 * USDC);
//         assertEq(companyAfter - companyBefore, 25 * USDC);
//         assertEq(uint256(hub.getAgreementDetails(id).status), 4);
//     }

//     // --- 8. TEST AUTO RELEASE ---
//     function testAutoReleaseAfterTimeout() public {
//         vm.startPrank(company);
//         uint256[] memory d = new uint256[](1);
//         d[0] = block.timestamp + 1 weeks;
//         uint256 id = hub.createAgreement(
//             freelancer, address(token), 10 * USDC, 0, d, FLECHub.PType.OneTime, "Logo", "Auto release", arbitrator
//         );
//         uint256 fee = hub.calculateExecutionFee(address(token), 10 * USDC);
//         token.approve(address(hub), 10 * USDC + fee);
//         hub.deposit(id);
//         vm.stopPrank();

//         vm.prank(freelancer);
//         hub.submitWork(id, "proof");

//         vm.warp(block.timestamp + hub.approvalTimeout());
//         vm.prank(freelancer);
//         hub.autoReleaseIfExpired(id);

//         assertEq(token.balanceOf(freelancer), 10 * USDC);
//         assertEq(uint256(hub.getAgreementDetails(id).status), 4);
//     }

//     // --- 9. TEST REJECT LIMIT ESCALATION ---
//     function testRejectLimitEscalatesToDispute() public {
//         vm.startPrank(company);
//         uint256[] memory d = new uint256[](1);
//         d[0] = block.timestamp + 1 weeks;
//         uint256 id = hub.createAgreement(
//             freelancer, address(token), 10 * USDC, 0, d, FLECHub.PType.OneTime, "Art", "Reject escalation", arbitrator
//         );
//         uint256 fee = hub.calculateExecutionFee(address(token), 10 * USDC);
//         token.approve(address(hub), 10 * USDC + fee);
//         hub.deposit(id);
//         vm.stopPrank();

//         for (uint8 i = 0; i < hub.maxRejectsPerMilestone(); i++) {
//             vm.prank(freelancer);
//             hub.submitWork(id, "bad");
//             vm.prank(company);
//             hub.rejectWork(id, "reject");
//         }

//         assertEq(uint256(hub.getAgreementDetails(id).status), 6);
//     }

//     // --- 10. TEST MONTHLY CANCEL MID-CYCLE ---
//     function test_RevertWhen_MonthlyCancelMidCycle() public {
//         vm.startPrank(company);
//         uint256 totalBudget = 60 * USDC;
//         uint256 monthlyRate = 20 * USDC;
//         uint256[] memory d = new uint256[](0);

//         uint256 id = hub.createAgreement(
//             freelancer,
//             address(token),
//             totalBudget,
//             monthlyRate,
//             d,
//             FLECHub.PType.Monthly,
//             "Retainer",
//             "Cancel mid-cycle",
//             arbitrator
//         );

//         uint256 fee = hub.calculateExecutionFee(address(token), totalBudget);
//         token.approve(address(hub), totalBudget + fee);
//         hub.deposit(id);

//         vm.expectRevert("Monthly: cannot cancel mid-cycle");
//         hub.cancelAgreement(id);
//         vm.stopPrank();
//     }
// }
