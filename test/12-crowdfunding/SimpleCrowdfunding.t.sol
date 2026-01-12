// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "../../src/12-crowdfunding/SimpleCrowdfunding.sol";

contract SimpleCrowdfundingTest is Test {
    SimpleCrowdfunding crowdfunding;

    address creator = address(0xC4EA704);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    uint256 constant GOAL = 10 ether;
    uint256 constant DURATION = 7 days;

    event ContributionReceived(
        address indexed contributor,
        uint256 amount,
        uint256 totalRaised
    );
    event FundsWithdrawn(address indexed creator, uint256 amount);
    event RefundClaimed(address indexed contributor, uint256 amount);

    function setUp() public {
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);

        vm.prank(creator);
        crowdfunding = new SimpleCrowdfunding(GOAL, block.timestamp + DURATION);
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function testConstructorSetsValues() public view {
        assertEq(crowdfunding.i_creator(), creator);
        assertEq(crowdfunding.i_goal(), GOAL);
        assertEq(crowdfunding.i_deadline(), block.timestamp + DURATION);
        assertEq(crowdfunding.totalRaised(), 0);
        assertEq(crowdfunding.withdrawn(), false);
    }

    function testConstructorRevertsOnPastDeadline() public {
        vm.prank(creator);
        vm.expectRevert(SimpleCrowdfunding.invalidDeadline.selector);
        new SimpleCrowdfunding(GOAL, block.timestamp - 1);
    }

    function testConstructorRevertsOnZeroGoal() public {
        vm.prank(creator);
        vm.expectRevert(SimpleCrowdfunding.invalidFundingGoal.selector);
        new SimpleCrowdfunding(0, block.timestamp + DURATION);
    }

    /*//////////////////////////////////////////////////////////////
                            CONTRIBUTE
    //////////////////////////////////////////////////////////////*/

    function testContributeIncreasesBalance() public {
        vm.prank(alice);
        crowdfunding.contribute{value: 5 ether}();

        assertEq(crowdfunding.totalRaised(), 5 ether);
        assertEq(crowdfunding.contributions(alice), 5 ether);
        assertEq(address(crowdfunding).balance, 5 ether);
    }

    function testContributeAccumulatesMultiple() public {
        vm.prank(alice);
        crowdfunding.contribute{value: 3 ether}();

        vm.prank(alice);
        crowdfunding.contribute{value: 2 ether}();

        assertEq(crowdfunding.contributions(alice), 5 ether);
        assertEq(crowdfunding.totalRaised(), 5 ether);
    }

    function testContributeFromMultipleUsers() public {
        vm.prank(alice);
        crowdfunding.contribute{value: 6 ether}();

        vm.prank(bob);
        crowdfunding.contribute{value: 5 ether}();

        assertEq(crowdfunding.contributions(alice), 6 ether);
        assertEq(crowdfunding.contributions(bob), 5 ether);
        assertEq(crowdfunding.totalRaised(), 11 ether);
    }

    function testContributeEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit ContributionReceived(alice, 5 ether, 5 ether);

        vm.prank(alice);
        crowdfunding.contribute{value: 5 ether}();
    }

    function testContributeRevertsAfterDeadline() public {
        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(alice);
        vm.expectRevert(SimpleCrowdfunding.CampaignEnded.selector);
        crowdfunding.contribute{value: 5 ether}();
    }

    function testContributeRevertsOnZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(SimpleCrowdfunding.ZeroContribution.selector);
        crowdfunding.contribute{value: 0}();
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAW
    //////////////////////////////////////////////////////////////*/

    function testWithdrawTransfersFunds() public {
        // Contribute enough to reach goal
        vm.prank(alice);
        crowdfunding.contribute{value: 6 ether}();

        vm.prank(bob);
        crowdfunding.contribute{value: 5 ether}();

        // Warp past deadline
        vm.warp(block.timestamp + DURATION + 1);

        uint256 creatorBalanceBefore = creator.balance;

        vm.prank(creator);
        crowdfunding.withdraw();

        assertEq(creator.balance, creatorBalanceBefore + 11 ether);
        assertEq(address(crowdfunding).balance, 0);
        assertEq(crowdfunding.withdrawn(), true);
    }

    function testWithdrawEmitsEvent() public {
        vm.prank(alice);
        crowdfunding.contribute{value: 10 ether}();

        vm.warp(block.timestamp + DURATION + 1);

        vm.expectEmit(true, false, false, true);
        emit FundsWithdrawn(creator, 10 ether);

        vm.prank(creator);
        crowdfunding.withdraw();
    }

    function testWithdrawRevertsIfNotCreator() public {
        vm.prank(alice);
        crowdfunding.contribute{value: 10 ether}();

        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(alice);
        vm.expectRevert(SimpleCrowdfunding.NotCreator.selector);
        crowdfunding.withdraw();
    }

    function testWithdrawRevertsBeforeDeadline() public {
        vm.prank(alice);
        crowdfunding.contribute{value: 10 ether}();

        vm.prank(creator);
        vm.expectRevert(SimpleCrowdfunding.CampaignNotEnded.selector);
        crowdfunding.withdraw();
    }

    function testWithdrawRevertsIfGoalNotReached() public {
        vm.prank(alice);
        crowdfunding.contribute{value: 5 ether}();

        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(creator);
        vm.expectRevert(SimpleCrowdfunding.GoalNotReached.selector);
        crowdfunding.withdraw();
    }

    function testWithdrawRevertsIfAlreadyWithdrawn() public {
        vm.prank(alice);
        crowdfunding.contribute{value: 10 ether}();

        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(creator);
        crowdfunding.withdraw();

        vm.prank(creator);
        vm.expectRevert(SimpleCrowdfunding.AlreadyWithdrawn.selector);
        crowdfunding.withdraw();
    }

    function testWithdrawWorksWithExactGoal() public {
        vm.prank(alice);
        crowdfunding.contribute{value: 10 ether}();

        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(creator);
        crowdfunding.withdraw();

        assertEq(crowdfunding.withdrawn(), true);
    }

    /*//////////////////////////////////////////////////////////////
                            REFUND
    //////////////////////////////////////////////////////////////*/

    function testRefundReturnsContribution() public {
        vm.prank(alice);
        crowdfunding.contribute{value: 5 ether}();

        vm.warp(block.timestamp + DURATION + 1);

        uint256 aliceBalanceBefore = alice.balance;

        vm.prank(alice);
        crowdfunding.refund();

        assertEq(alice.balance, aliceBalanceBefore + 5 ether);
        assertEq(crowdfunding.contributions(alice), 0);
    }

    function testRefundEmitsEvent() public {
        vm.prank(alice);
        crowdfunding.contribute{value: 5 ether}();

        vm.warp(block.timestamp + DURATION + 1);

        vm.expectEmit(true, false, false, true);
        emit RefundClaimed(alice, 5 ether);

        vm.prank(alice);
        crowdfunding.refund();
    }

    function testRefundMultipleContributors() public {
        vm.prank(alice);
        crowdfunding.contribute{value: 3 ether}();

        vm.prank(bob);
        crowdfunding.contribute{value: 2 ether}();

        vm.warp(block.timestamp + DURATION + 1);

        uint256 aliceBalanceBefore = alice.balance;
        uint256 bobBalanceBefore = bob.balance;

        vm.prank(alice);
        crowdfunding.refund();

        vm.prank(bob);
        crowdfunding.refund();

        assertEq(alice.balance, aliceBalanceBefore + 3 ether);
        assertEq(bob.balance, bobBalanceBefore + 2 ether);
    }

    function testRefundRevertsBeforeDeadline() public {
        vm.prank(alice);
        crowdfunding.contribute{value: 5 ether}();

        vm.prank(alice);
        vm.expectRevert(SimpleCrowdfunding.CampaignNotEnded.selector);
        crowdfunding.refund();
    }

    function testRefundRevertsIfGoalReached() public {
        vm.prank(alice);
        crowdfunding.contribute{value: 10 ether}();

        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(alice);
        vm.expectRevert(SimpleCrowdfunding.GoalAlreadyReached.selector);
        crowdfunding.refund();
    }

    function testRefundRevertsIfNoContribution() public {
        vm.prank(alice);
        crowdfunding.contribute{value: 5 ether}();

        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(bob);
        vm.expectRevert(SimpleCrowdfunding.NoContribution.selector);
        crowdfunding.refund();
    }

    function testRefundRevertsOnSecondAttempt() public {
        vm.prank(alice);
        crowdfunding.contribute{value: 5 ether}();

        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(alice);
        crowdfunding.refund();

        vm.prank(alice);
        vm.expectRevert(SimpleCrowdfunding.NoContribution.selector);
        crowdfunding.refund();
    }

    /*//////////////////////////////////////////////////////////////
                            EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function testContributeExactlyAtDeadline() public {
        vm.warp(block.timestamp + DURATION);

        vm.prank(alice);
        crowdfunding.contribute{value: 5 ether}();

        assertEq(crowdfunding.totalRaised(), 5 ether);
    }

    function testOverfundingAllowed() public {
        vm.prank(alice);
        crowdfunding.contribute{value: 15 ether}();

        assertEq(crowdfunding.totalRaised(), 15 ether);

        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(creator);
        crowdfunding.withdraw();

        assertEq(crowdfunding.withdrawn(), true);
    }

    function testContractReceivesETHOnlyViaContribute() public {
        // Direct ETH transfer should fail (no receive/fallback)
        vm.prank(alice);
        (bool success, ) = address(crowdfunding).call{value: 1 ether}("");
        assertFalse(success);
    }
}
