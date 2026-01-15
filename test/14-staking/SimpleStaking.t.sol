// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "../../src/14-staking/SimpleStaking.sol";

contract SimpleStakingTest is Test {
    SimpleStaking staking;

    address owner = address(0x0BABE);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    uint256 constant MIN_LOCK_PERIOD = 7 days;
    uint256 constant REWARD_RATE = 1e12; // 0.000001 ETH per ETH per second (~31.5% APY)
    uint256 constant PRECISION = 1e18;

    event RewardsDeposited(address indexed owner, uint256 amount);
    event Staked(address indexed staker, uint256 amount);
    event Unstaked(address indexed staker, uint256 principal, uint256 rewards);
    event RewardsClaimed(address indexed staker, uint256 amount);

    function setUp() public {
        vm.deal(owner, 100 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);

        vm.prank(owner);
        staking = new SimpleStaking(MIN_LOCK_PERIOD, REWARD_RATE);

        // Fund reward pool
        vm.prank(owner);
        staking.depositRewards{value: 50 ether}();
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function testConstructorSetsOwner() public view {
        assertEq(staking.i_owner(), owner);
    }

    function testConstructorSetsMinLockPeriod() public view {
        assertEq(staking.i_minLockPeriod(), MIN_LOCK_PERIOD);
    }

    function testConstructorSetsRewardRate() public view {
        assertEq(staking.i_rewardRatePerSecond(), REWARD_RATE);
    }

    function testConstructorRevertsIfLockPeriodZero() public {
        vm.prank(owner);
        vm.expectRevert(SimpleStaking.InvalidLockPeriod.selector);
        new SimpleStaking(0, REWARD_RATE);
    }

    function testConstructorRevertsIfRewardRateZero() public {
        vm.prank(owner);
        vm.expectRevert(SimpleStaking.InvalidRewardRate.selector);
        new SimpleStaking(MIN_LOCK_PERIOD, 0);
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT REWARDS
    //////////////////////////////////////////////////////////////*/

    function testDepositRewardsOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(SimpleStaking.NotOwner.selector);
        staking.depositRewards{value: 1 ether}();
    }

    function testDepositRewardsIncreasesPool() public {
        uint256 poolBefore = staking.rewardPool();

        vm.prank(owner);
        staking.depositRewards{value: 10 ether}();

        assertEq(staking.rewardPool(), poolBefore + 10 ether);
    }

    function testDepositRewardsRevertsOnZero() public {
        vm.prank(owner);
        vm.expectRevert(SimpleStaking.InvalidDepositAmount.selector);
        staking.depositRewards{value: 0}();
    }

    function testDepositRewardsEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit RewardsDeposited(owner, 5 ether);

        vm.prank(owner);
        staking.depositRewards{value: 5 ether}();
    }

    /*//////////////////////////////////////////////////////////////
                            STAKING
    //////////////////////////////////////////////////////////////*/

    function testStakeAcceptsETH() public {
        vm.prank(alice);
        staking.stake{value: 10 ether}();

        (uint256 amount, , ) = staking.stakes(alice);
        assertEq(amount, 10 ether);
    }

    function testStakeRecordsTimestamp() public {
        uint256 stakingTime = block.timestamp;

        vm.prank(alice);
        staking.stake{value: 10 ether}();

        (, uint256 stakedAt, ) = staking.stakes(alice);
        assertEq(stakedAt, stakingTime);
    }

    function testStakeUpdatesTotalStaked() public {
        vm.prank(alice);
        staking.stake{value: 10 ether}();

        assertEq(staking.totalStaked(), 10 ether);
    }

    function testStakeRevertsIfAlreadyStaked() public {
        vm.prank(alice);
        staking.stake{value: 5 ether}();

        vm.prank(alice);
        vm.expectRevert(SimpleStaking.AlreadyStaked.selector);
        staking.stake{value: 5 ether}();
    }

    function testStakeRevertsOnZeroValue() public {
        vm.prank(alice);
        vm.expectRevert(SimpleStaking.InvalidStakeAmount.selector);
        staking.stake{value: 0}();
    }

    function testStakeEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit Staked(alice, 10 ether);

        vm.prank(alice);
        staking.stake{value: 10 ether}();
    }

    /*//////////////////////////////////////////////////////////////
                            UNSTAKING
    //////////////////////////////////////////////////////////////*/

    function testUnstakeReturnsPrincipal() public {
        vm.prank(alice);
        staking.stake{value: 10 ether}();

        vm.warp(block.timestamp + MIN_LOCK_PERIOD);

        uint256 balanceBefore = alice.balance;

        vm.prank(alice);
        staking.unstake();

        // Should have at least principal back
        assertGe(alice.balance, balanceBefore + 10 ether);
    }

    function testUnstakeReturnsPrincipalPlusRewards() public {
        vm.prank(alice);
        staking.stake{value: 10 ether}();

        // Warp past lock period
        vm.warp(block.timestamp + MIN_LOCK_PERIOD);

        uint256 balanceBefore = alice.balance;

        vm.prank(alice);
        staking.unstake();

        // Calculate expected rewards: 10 ETH * 7 days * rate / precision
        uint256 expectedReward = (10 ether * MIN_LOCK_PERIOD * REWARD_RATE) / PRECISION;

        assertEq(alice.balance, balanceBefore + 10 ether + expectedReward);
    }

    function testUnstakeRevertsBeforeLockPeriod() public {
        vm.prank(alice);
        staking.stake{value: 10 ether}();

        vm.warp(block.timestamp + MIN_LOCK_PERIOD - 1);

        vm.prank(alice);
        vm.expectRevert(SimpleStaking.MinLockNotPassed.selector);
        staking.unstake();
    }

    function testUnstakeRevertsIfNoStake() public {
        vm.prank(alice);
        vm.expectRevert(SimpleStaking.NoStake.selector);
        staking.unstake();
    }

    function testUnstakeUpdatesTotalStaked() public {
        vm.prank(alice);
        staking.stake{value: 10 ether}();

        vm.prank(bob);
        staking.stake{value: 5 ether}();

        assertEq(staking.totalStaked(), 15 ether);

        vm.warp(block.timestamp + MIN_LOCK_PERIOD);

        vm.prank(alice);
        staking.unstake();

        assertEq(staking.totalStaked(), 5 ether);
    }

    function testUnstakeCapsRewardsToPool() public {
        // Create new staking with small reward pool
        vm.prank(owner);
        SimpleStaking smallPoolStaking = new SimpleStaking(MIN_LOCK_PERIOD, REWARD_RATE);

        vm.prank(owner);
        smallPoolStaking.depositRewards{value: 0.001 ether}();

        vm.prank(alice);
        smallPoolStaking.stake{value: 10 ether}();

        // Warp far into future (would generate huge rewards)
        vm.warp(block.timestamp + 365 days);

        uint256 balanceBefore = alice.balance;
        uint256 poolBefore = smallPoolStaking.rewardPool();

        vm.prank(alice);
        smallPoolStaking.unstake();

        // Should get principal + entire pool (capped)
        assertEq(alice.balance, balanceBefore + 10 ether + poolBefore);
        assertEq(smallPoolStaking.rewardPool(), 0);
    }

    function testUnstakeEmitsEvent() public {
        vm.prank(alice);
        staking.stake{value: 10 ether}();

        vm.warp(block.timestamp + MIN_LOCK_PERIOD);

        uint256 expectedReward = (10 ether * MIN_LOCK_PERIOD * REWARD_RATE) / PRECISION;

        vm.expectEmit(true, false, false, true);
        emit Unstaked(alice, 10 ether, expectedReward);

        vm.prank(alice);
        staking.unstake();
    }

    /*//////////////////////////////////////////////////////////////
                            CLAIMING REWARDS
    //////////////////////////////////////////////////////////////*/

    function testClaimRewardsReturnsCorrectAmount() public {
        vm.prank(alice);
        staking.stake{value: 10 ether}();

        vm.warp(block.timestamp + 1 days);

        uint256 balanceBefore = alice.balance;
        uint256 expectedReward = (10 ether * 1 days * REWARD_RATE) / PRECISION;

        vm.prank(alice);
        staking.claimRewards();

        assertEq(alice.balance, balanceBefore + expectedReward);
    }

    function testClaimRewardsUpdatesRewardsClaimed() public {
        vm.prank(alice);
        staking.stake{value: 10 ether}();

        vm.warp(block.timestamp + 1 days);

        vm.prank(alice);
        staking.claimRewards();

        (, , uint256 rewardsClaimed) = staking.stakes(alice);
        assertGt(rewardsClaimed, 0);
    }

    function testClaimRewardsRevertsIfNoStake() public {
        vm.prank(alice);
        vm.expectRevert(SimpleStaking.NoStake.selector);
        staking.claimRewards();
    }

    function testClaimRewardsRevertsIfNoRewardsToClaim() public {
        vm.prank(alice);
        staking.stake{value: 10 ether}();

        // No time passed, no rewards
        vm.prank(alice);
        vm.expectRevert(SimpleStaking.NoRewardsToClaim.selector);
        staking.claimRewards();
    }

    function testClaimRewardsCapsToPool() public {
        // Create staking with tiny pool
        vm.prank(owner);
        SimpleStaking tinyPoolStaking = new SimpleStaking(MIN_LOCK_PERIOD, REWARD_RATE);

        vm.prank(owner);
        tinyPoolStaking.depositRewards{value: 0.0001 ether}();

        vm.prank(alice);
        tinyPoolStaking.stake{value: 10 ether}();

        vm.warp(block.timestamp + 365 days);

        uint256 poolBefore = tinyPoolStaking.rewardPool();
        uint256 balanceBefore = alice.balance;

        vm.prank(alice);
        tinyPoolStaking.claimRewards();

        assertEq(alice.balance, balanceBefore + poolBefore);
        assertEq(tinyPoolStaking.rewardPool(), 0);
    }

    function testClaimRewardsDoesNotAffectPrincipal() public {
        vm.prank(alice);
        staking.stake{value: 10 ether}();

        vm.warp(block.timestamp + 1 days);

        vm.prank(alice);
        staking.claimRewards();

        (uint256 amount, , ) = staking.stakes(alice);
        assertEq(amount, 10 ether);
    }

    function testClaimRewardsEmitsEvent() public {
        vm.prank(alice);
        staking.stake{value: 10 ether}();

        vm.warp(block.timestamp + 1 days);

        uint256 expectedReward = (10 ether * 1 days * REWARD_RATE) / PRECISION;

        vm.expectEmit(true, false, false, true);
        emit RewardsClaimed(alice, expectedReward);

        vm.prank(alice);
        staking.claimRewards();
    }

    /*//////////////////////////////////////////////////////////////
                            REWARD CALCULATION
    //////////////////////////////////////////////////////////////*/

    function testRewardsIncreaseOverTime() public {
        vm.prank(alice);
        staking.stake{value: 10 ether}();

        uint256 rewardsAt1Day = staking.calculateRewards(alice);

        vm.warp(block.timestamp + 1 days);
        uint256 rewardsAt2Days = staking.calculateRewards(alice);

        assertGt(rewardsAt2Days, rewardsAt1Day);
    }

    function testRewardsProportionalToAmount() public {
        vm.prank(alice);
        staking.stake{value: 10 ether}();

        vm.prank(bob);
        staking.stake{value: 20 ether}();

        vm.warp(block.timestamp + 1 days);

        uint256 aliceRewards = staking.calculateRewards(alice);
        uint256 bobRewards = staking.calculateRewards(bob);

        // Bob staked 2x, should have ~2x rewards
        assertEq(bobRewards, aliceRewards * 2);
    }

    function testCalculateRewardsReturnsZeroForNonStaker() public view {
        uint256 rewards = staking.calculateRewards(alice);
        assertEq(rewards, 0);
    }

    function testGetUnclaimedRewardsAccountsForClaimed() public {
        vm.prank(alice);
        staking.stake{value: 10 ether}();

        // Warp 1 day and claim
        vm.warp(block.timestamp + 1 days);
        uint256 rewardsDay1 = staking.getUnclaimedRewards(alice);

        vm.prank(alice);
        staking.claimRewards();

        // Immediately after claim, unclaimed should be 0
        assertEq(staking.getUnclaimedRewards(alice), 0);

        // Warp another day
        vm.warp(block.timestamp + 1 days);

        uint256 unclaimedAfterClaim = staking.getUnclaimedRewards(alice);

        // Unclaimed should be approximately 1 day worth (same as first day)
        assertApproxEqRel(unclaimedAfterClaim, rewardsDay1, 0.01e18); // 1% tolerance
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function testGetStakeInfo() public {
        vm.prank(alice);
        staking.stake{value: 10 ether}();

        SimpleStaking.Stake memory info = staking.getStakeInfo(alice);

        assertEq(info.amount, 10 ether);
        assertEq(info.stakedAt, block.timestamp);
        assertEq(info.rewardsClaimed, 0);
    }

    function testCanUnstakeReturnsFalseIfNoStake() public view {
        assertFalse(staking.canUnstake(alice));
    }

    function testCanUnstakeReturnsFalseBeforeLockPeriod() public {
        vm.prank(alice);
        staking.stake{value: 10 ether}();

        assertFalse(staking.canUnstake(alice));

        vm.warp(block.timestamp + MIN_LOCK_PERIOD - 1);
        assertFalse(staking.canUnstake(alice));
    }

    function testCanUnstakeReturnsTrueAfterLockPeriod() public {
        vm.prank(alice);
        staking.stake{value: 10 ether}();

        vm.warp(block.timestamp + MIN_LOCK_PERIOD);
        assertTrue(staking.canUnstake(alice));
    }

    /*//////////////////////////////////////////////////////////////
                            EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function testStakeWorksWithEmptyRewardPool() public {
        // Create staking with no rewards
        vm.prank(owner);
        SimpleStaking noRewardStaking = new SimpleStaking(MIN_LOCK_PERIOD, REWARD_RATE);

        // Stake should still work
        vm.prank(alice);
        noRewardStaking.stake{value: 10 ether}();

        (uint256 amount, , ) = noRewardStaking.stakes(alice);
        assertEq(amount, 10 ether);
    }

    function testUnstakeWithEmptyPoolReturnsOnlyPrincipal() public {
        // Create staking with no rewards
        vm.prank(owner);
        SimpleStaking noRewardStaking = new SimpleStaking(MIN_LOCK_PERIOD, REWARD_RATE);

        vm.prank(alice);
        noRewardStaking.stake{value: 10 ether}();

        vm.warp(block.timestamp + MIN_LOCK_PERIOD);

        uint256 balanceBefore = alice.balance;

        vm.prank(alice);
        noRewardStaking.unstake();

        // Only principal returned, no rewards
        assertEq(alice.balance, balanceBefore + 10 ether);
    }

    function testMultipleUsersStakingSimultaneously() public {
        vm.prank(alice);
        staking.stake{value: 10 ether}();

        vm.prank(bob);
        staking.stake{value: 15 ether}();

        assertEq(staking.totalStaked(), 25 ether);

        (uint256 aliceAmount, , ) = staking.stakes(alice);
        (uint256 bobAmount, , ) = staking.stakes(bob);

        assertEq(aliceAmount, 10 ether);
        assertEq(bobAmount, 15 ether);
    }

    function testUnstakeAtExactLockPeriodBoundary() public {
        vm.prank(alice);
        staking.stake{value: 10 ether}();

        // Warp to exactly lock period (not 1 second more)
        vm.warp(block.timestamp + MIN_LOCK_PERIOD);

        // Should work at exact boundary
        vm.prank(alice);
        staking.unstake();

        (uint256 amount, , ) = staking.stakes(alice);
        assertEq(amount, 0);
    }

    function testMultipleClaimsThenUnstake() public {
        vm.prank(alice);
        staking.stake{value: 10 ether}();

        // Claim after 1 day
        vm.warp(block.timestamp + 1 days);
        vm.prank(alice);
        staking.claimRewards();

        // Claim after another day
        vm.warp(block.timestamp + 1 days);
        vm.prank(alice);
        staking.claimRewards();

        // Unstake after lock period
        vm.warp(block.timestamp + MIN_LOCK_PERIOD);

        uint256 balanceBefore = alice.balance;

        vm.prank(alice);
        staking.unstake();

        // Should get principal + remaining unclaimed rewards
        assertGt(alice.balance, balanceBefore + 10 ether);
    }

    function testRewardPoolDecreasesOnClaim() public {
        vm.prank(alice);
        staking.stake{value: 10 ether}();

        vm.warp(block.timestamp + 1 days);

        uint256 poolBefore = staking.rewardPool();

        vm.prank(alice);
        staking.claimRewards();

        assertLt(staking.rewardPool(), poolBefore);
    }

    function testRewardPoolDecreasesOnUnstake() public {
        vm.prank(alice);
        staking.stake{value: 10 ether}();

        vm.warp(block.timestamp + MIN_LOCK_PERIOD);

        uint256 poolBefore = staking.rewardPool();

        vm.prank(alice);
        staking.unstake();

        assertLt(staking.rewardPool(), poolBefore);
    }
}
