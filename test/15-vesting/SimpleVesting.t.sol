// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "../../src/15-vesting/SimpleVesting.sol";

/// @notice Mock ERC20 token for testing
contract MockToken {
    string public name = "Mock Token";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }
}

contract SimpleVestingTest is Test {
    SimpleVesting vesting;
    MockToken token;

    address owner = address(0x0BABE);
    address beneficiary = address(0xBEEF);
    address alice = address(0xA11CE);

    uint256 constant CLIFF_DURATION = 30 days;
    uint256 constant VESTING_DURATION = 365 days;
    uint256 constant TOTAL_AMOUNT = 1000 ether;

    event TokensDeposited(address indexed owner, uint256 amount);
    event VestingRevoked(address indexed owner, uint256 amountRevoked);
    event TokensReleased(address indexed beneficiary, uint256 amount);

    function setUp() public {
        // Deploy mock token
        token = new MockToken();

        // Mint tokens to owner
        token.mint(owner, TOTAL_AMOUNT);

        // Deploy vesting contract
        vm.prank(owner);
        vesting = new SimpleVesting(
            address(token),
            beneficiary,
            CLIFF_DURATION,
            VESTING_DURATION,
            true // revocable
        );

        // Owner approves vesting contract
        vm.prank(owner);
        token.approve(address(vesting), TOTAL_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function testConstructorSetsOwner() public view {
        assertEq(vesting.i_owner(), owner);
    }

    function testConstructorSetsBeneficiary() public view {
        assertEq(vesting.i_beneficiary(), beneficiary);
    }

    function testConstructorSetsToken() public view {
        assertEq(address(vesting.i_token()), address(token));
    }

    function testConstructorSetsCliffDuration() public view {
        assertEq(vesting.i_cliffDuration(), CLIFF_DURATION);
    }

    function testConstructorSetsVestingDuration() public view {
        assertEq(vesting.i_vestingDuration(), VESTING_DURATION);
    }

    function testConstructorSetsRevocable() public view {
        assertTrue(vesting.i_revocable());
    }

    function testConstructorRevertsIfTokenIsZero() public {
        vm.prank(owner);
        vm.expectRevert(SimpleVesting.InvalidTokenAddress.selector);
        new SimpleVesting(address(0), beneficiary, CLIFF_DURATION, VESTING_DURATION, true);
    }

    function testConstructorRevertsIfBeneficiaryIsZero() public {
        vm.prank(owner);
        vm.expectRevert(SimpleVesting.InvalidBeneficiary.selector);
        new SimpleVesting(address(token), address(0), CLIFF_DURATION, VESTING_DURATION, true);
    }

    function testConstructorRevertsIfCliffExceedsVesting() public {
        vm.prank(owner);
        vm.expectRevert(SimpleVesting.InvalidCliff.selector);
        new SimpleVesting(address(token), beneficiary, 400 days, 365 days, true);
    }

    function testConstructorRevertsIfVestingIsZero() public {
        vm.prank(owner);
        vm.expectRevert(SimpleVesting.InvalidVesting.selector);
        new SimpleVesting(address(token), beneficiary, 0, 0, true);
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT
    //////////////////////////////////////////////////////////////*/

    function testDepositOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(SimpleVesting.NotOwner.selector);
        vesting.deposit(TOTAL_AMOUNT);
    }

    function testDepositSetsTotalAmount() public {
        vm.prank(owner);
        vesting.deposit(TOTAL_AMOUNT);

        assertEq(vesting.totalAmount(), TOTAL_AMOUNT);
    }

    function testDepositSetsStartTime() public {
        uint256 depositTime = block.timestamp;

        vm.prank(owner);
        vesting.deposit(TOTAL_AMOUNT);

        assertEq(vesting.startTime(), depositTime);
    }

    function testDepositTransfersTokens() public {
        uint256 ownerBalanceBefore = token.balanceOf(owner);

        vm.prank(owner);
        vesting.deposit(TOTAL_AMOUNT);

        assertEq(token.balanceOf(owner), ownerBalanceBefore - TOTAL_AMOUNT);
        assertEq(token.balanceOf(address(vesting)), TOTAL_AMOUNT);
    }

    function testDepositRevertsIfAmountIsZero() public {
        vm.prank(owner);
        vm.expectRevert(SimpleVesting.InvalidAmount.selector);
        vesting.deposit(0);
    }

    function testDepositRevertsIfAlreadyDeposited() public {
        vm.prank(owner);
        vesting.deposit(TOTAL_AMOUNT);

        // Mint more tokens and approve
        token.mint(owner, TOTAL_AMOUNT);
        vm.prank(owner);
        token.approve(address(vesting), TOTAL_AMOUNT);

        vm.prank(owner);
        vm.expectRevert(SimpleVesting.AlreadyStarted.selector);
        vesting.deposit(TOTAL_AMOUNT);
    }

    function testDepositEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit TokensDeposited(owner, TOTAL_AMOUNT);

        vm.prank(owner);
        vesting.deposit(TOTAL_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                        VESTING CALCULATION
    //////////////////////////////////////////////////////////////*/

    function testVestedAmountReturnsZeroBeforeDeposit() public view {
        assertEq(vesting.vestedAmount(), 0);
    }

    function testVestedAmountReturnsZeroDuringCliff() public {
        vm.prank(owner);
        vesting.deposit(TOTAL_AMOUNT);

        // Warp to middle of cliff
        vm.warp(block.timestamp + CLIFF_DURATION / 2);

        assertEq(vesting.vestedAmount(), 0);
    }

    function testVestedAmountReturnsZeroAtCliffBoundary() public {
        vm.prank(owner);
        vesting.deposit(TOTAL_AMOUNT);

        // Warp to 1 second before cliff ends
        vm.warp(block.timestamp + CLIFF_DURATION - 1);

        assertEq(vesting.vestedAmount(), 0);
    }

    function testVestedAmountReturnsPartialAfterCliff() public {
        vm.prank(owner);
        vesting.deposit(TOTAL_AMOUNT);

        // Warp to halfway through vesting (after cliff)
        vm.warp(block.timestamp + VESTING_DURATION / 2);

        uint256 expected = (TOTAL_AMOUNT * (VESTING_DURATION / 2)) / VESTING_DURATION;
        assertEq(vesting.vestedAmount(), expected);
    }

    function testVestedAmountReturnsTotalAfterVestingEnd() public {
        vm.prank(owner);
        vesting.deposit(TOTAL_AMOUNT);

        // Warp past vesting end
        vm.warp(block.timestamp + VESTING_DURATION + 1 days);

        assertEq(vesting.vestedAmount(), TOTAL_AMOUNT);
    }

    function testVestedAmountLinearProgression() public {
        vm.prank(owner);
        vesting.deposit(TOTAL_AMOUNT);

        uint256 startTime = block.timestamp;

        // Test at 25%, 50%, 75%, 100%
        uint256[] memory percentages = new uint256[](4);
        percentages[0] = 25;
        percentages[1] = 50;
        percentages[2] = 75;
        percentages[3] = 100;

        for (uint256 i = 0; i < percentages.length; i++) {
            uint256 timeElapsed = (VESTING_DURATION * percentages[i]) / 100;
            vm.warp(startTime + timeElapsed);

            uint256 expected = (TOTAL_AMOUNT * timeElapsed) / VESTING_DURATION;
            assertEq(vesting.vestedAmount(), expected);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            RELEASE
    //////////////////////////////////////////////////////////////*/

    function testReleaseOnlyBeneficiary() public {
        vm.prank(owner);
        vesting.deposit(TOTAL_AMOUNT);

        vm.warp(block.timestamp + VESTING_DURATION);

        vm.prank(alice);
        vm.expectRevert(SimpleVesting.NotBeneficiary.selector);
        vesting.release();
    }

    function testReleaseTransfersTokens() public {
        vm.prank(owner);
        vesting.deposit(TOTAL_AMOUNT);

        // Warp past cliff
        vm.warp(block.timestamp + VESTING_DURATION / 2);

        uint256 expectedRelease = vesting.releasable();

        vm.prank(beneficiary);
        vesting.release();

        assertEq(token.balanceOf(beneficiary), expectedRelease);
    }

    function testReleaseUpdatesReleasedAmount() public {
        vm.prank(owner);
        vesting.deposit(TOTAL_AMOUNT);

        vm.warp(block.timestamp + VESTING_DURATION / 2);

        uint256 expectedRelease = vesting.releasable();

        vm.prank(beneficiary);
        vesting.release();

        assertEq(vesting.released(), expectedRelease);
    }

    function testReleaseRevertsIfNothingToRelease() public {
        vm.prank(owner);
        vesting.deposit(TOTAL_AMOUNT);

        // Still in cliff
        vm.prank(beneficiary);
        vm.expectRevert(SimpleVesting.NothingToRelease.selector);
        vesting.release();
    }

    function testReleaseRevertsOnDoubleRelease() public {
        vm.prank(owner);
        vesting.deposit(TOTAL_AMOUNT);

        vm.warp(block.timestamp + VESTING_DURATION / 2);

        vm.prank(beneficiary);
        vesting.release();

        // Immediately try to release again (no time passed)
        vm.prank(beneficiary);
        vm.expectRevert(SimpleVesting.NothingToRelease.selector);
        vesting.release();
    }

    function testReleaseEmitsEvent() public {
        vm.prank(owner);
        vesting.deposit(TOTAL_AMOUNT);

        vm.warp(block.timestamp + VESTING_DURATION / 2);

        uint256 expectedRelease = vesting.releasable();

        vm.expectEmit(true, false, false, true);
        emit TokensReleased(beneficiary, expectedRelease);

        vm.prank(beneficiary);
        vesting.release();
    }

    function testMultipleReleases() public {
        vm.prank(owner);
        vesting.deposit(TOTAL_AMOUNT);

        uint256 startTime = block.timestamp;
        uint256 totalReleased = 0;

        // Release at 40%
        vm.warp(startTime + (VESTING_DURATION * 40) / 100);
        vm.prank(beneficiary);
        vesting.release();
        totalReleased = vesting.released();

        // Release at 70%
        vm.warp(startTime + (VESTING_DURATION * 70) / 100);
        vm.prank(beneficiary);
        vesting.release();

        // Release at 100%
        vm.warp(startTime + VESTING_DURATION);
        vm.prank(beneficiary);
        vesting.release();

        // Should have received all tokens
        assertEq(token.balanceOf(beneficiary), TOTAL_AMOUNT);
        assertEq(vesting.released(), TOTAL_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                            REVOKE
    //////////////////////////////////////////////////////////////*/

    function testRevokeOnlyOwner() public {
        vm.prank(owner);
        vesting.deposit(TOTAL_AMOUNT);

        vm.prank(alice);
        vm.expectRevert(SimpleVesting.NotOwner.selector);
        vesting.revoke();
    }

    function testRevokeOnlyIfRevocable() public {
        // Create non-revocable vesting
        vm.prank(owner);
        SimpleVesting nonRevocable = new SimpleVesting(
            address(token),
            beneficiary,
            CLIFF_DURATION,
            VESTING_DURATION,
            false
        );

        token.mint(owner, TOTAL_AMOUNT);
        vm.prank(owner);
        token.approve(address(nonRevocable), TOTAL_AMOUNT);

        vm.prank(owner);
        nonRevocable.deposit(TOTAL_AMOUNT);

        vm.prank(owner);
        vm.expectRevert(SimpleVesting.NotRevocable.selector);
        nonRevocable.revoke();
    }

    function testRevokeRevertsIfAlreadyRevoked() public {
        vm.prank(owner);
        vesting.deposit(TOTAL_AMOUNT);

        vm.prank(owner);
        vesting.revoke();

        vm.prank(owner);
        vm.expectRevert(SimpleVesting.AlreadyRevoked.selector);
        vesting.revoke();
    }

    function testRevokeRevertsIfNotStarted() public {
        vm.prank(owner);
        vm.expectRevert(SimpleVesting.VestingNotStarted.selector);
        vesting.revoke();
    }

    function testRevokeDuringCliff() public {
        vm.prank(owner);
        vesting.deposit(TOTAL_AMOUNT);

        // Revoke during cliff - owner gets everything back
        vm.warp(block.timestamp + CLIFF_DURATION / 2);

        uint256 ownerBalanceBefore = token.balanceOf(owner);

        vm.prank(owner);
        vesting.revoke();

        // Owner should get all tokens back (vested = 0 during cliff)
        assertEq(token.balanceOf(owner), ownerBalanceBefore + TOTAL_AMOUNT);
        assertEq(vesting.totalAmount(), 0);
        assertTrue(vesting.revoked());
    }

    function testRevokeAfterPartialVesting() public {
        vm.prank(owner);
        vesting.deposit(TOTAL_AMOUNT);

        // Revoke at 50% vesting
        vm.warp(block.timestamp + VESTING_DURATION / 2);

        uint256 vestedAtRevoke = vesting.vestedAmount();
        uint256 unvested = TOTAL_AMOUNT - vestedAtRevoke;
        uint256 ownerBalanceBefore = token.balanceOf(owner);

        vm.prank(owner);
        vesting.revoke();

        // Owner gets unvested tokens
        assertEq(token.balanceOf(owner), ownerBalanceBefore + unvested);
        // Beneficiary can still claim vested tokens
        assertEq(vesting.totalAmount(), vestedAtRevoke);
        assertTrue(vesting.revoked());
    }

    function testRevokeWhenFullyVested() public {
        vm.prank(owner);
        vesting.deposit(TOTAL_AMOUNT);

        // Revoke after full vesting
        vm.warp(block.timestamp + VESTING_DURATION);

        uint256 ownerBalanceBefore = token.balanceOf(owner);

        vm.prank(owner);
        vesting.revoke();

        // Owner gets nothing (all vested)
        assertEq(token.balanceOf(owner), ownerBalanceBefore);
        assertEq(vesting.totalAmount(), TOTAL_AMOUNT);
    }

    function testRevokeEmitsEvent() public {
        vm.prank(owner);
        vesting.deposit(TOTAL_AMOUNT);

        vm.warp(block.timestamp + VESTING_DURATION / 2);

        uint256 unvested = TOTAL_AMOUNT - vesting.vestedAmount();

        vm.expectEmit(true, false, false, true);
        emit VestingRevoked(owner, unvested);

        vm.prank(owner);
        vesting.revoke();
    }

    function testBeneficiaryCanReleaseAfterRevoke() public {
        vm.prank(owner);
        vesting.deposit(TOTAL_AMOUNT);

        // Warp to 50% and revoke
        vm.warp(block.timestamp + VESTING_DURATION / 2);
        uint256 vestedAtRevoke = vesting.vestedAmount();

        vm.prank(owner);
        vesting.revoke();

        // Beneficiary can still release vested tokens
        vm.prank(beneficiary);
        vesting.release();

        assertEq(token.balanceOf(beneficiary), vestedAtRevoke);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function testReleasableCalculation() public {
        vm.prank(owner);
        vesting.deposit(TOTAL_AMOUNT);

        vm.warp(block.timestamp + VESTING_DURATION / 2);

        uint256 vested = vesting.vestedAmount();
        uint256 releasable = vesting.releasable();

        assertEq(releasable, vested - vesting.released());
    }

    function testGetCliffEndReturnsZeroBeforeDeposit() public view {
        assertEq(vesting.getCliffEnd(), 0);
    }

    function testGetCliffEndReturnsCorrectTimestamp() public {
        uint256 depositTime = block.timestamp;

        vm.prank(owner);
        vesting.deposit(TOTAL_AMOUNT);

        assertEq(vesting.getCliffEnd(), depositTime + CLIFF_DURATION);
    }

    function testGetVestingEndReturnsZeroBeforeDeposit() public view {
        assertEq(vesting.getVestingEnd(), 0);
    }

    function testGetVestingEndReturnsCorrectTimestamp() public {
        uint256 depositTime = block.timestamp;

        vm.prank(owner);
        vesting.deposit(TOTAL_AMOUNT);

        assertEq(vesting.getVestingEnd(), depositTime + VESTING_DURATION);
    }

    function testGetVestingInfo() public {
        vm.prank(owner);
        vesting.deposit(TOTAL_AMOUNT);

        (
            address _beneficiary,
            address _token,
            uint256 _totalAmount,
            uint256 _released,
            uint256 _startTime,
            uint256 _cliffDuration,
            uint256 _vestingDuration,
            bool _revocable,
            bool _revoked
        ) = vesting.getVestingInfo();

        assertEq(_beneficiary, beneficiary);
        assertEq(_token, address(token));
        assertEq(_totalAmount, TOTAL_AMOUNT);
        assertEq(_released, 0);
        assertEq(_startTime, block.timestamp);
        assertEq(_cliffDuration, CLIFF_DURATION);
        assertEq(_vestingDuration, VESTING_DURATION);
        assertTrue(_revocable);
        assertFalse(_revoked);
    }

    /*//////////////////////////////////////////////////////////////
                            EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function testReleaseAtExactCliffBoundary() public {
        vm.prank(owner);
        vesting.deposit(TOTAL_AMOUNT);

        // Warp to exact cliff end
        vm.warp(block.timestamp + CLIFF_DURATION);

        // Should be able to release (cliff just ended)
        uint256 releasable = vesting.releasable();
        assertGt(releasable, 0);

        vm.prank(beneficiary);
        vesting.release();

        assertEq(token.balanceOf(beneficiary), releasable);
    }

    function testReleaseAtExactVestingEnd() public {
        vm.prank(owner);
        vesting.deposit(TOTAL_AMOUNT);

        // Warp to exact vesting end
        vm.warp(block.timestamp + VESTING_DURATION);

        vm.prank(beneficiary);
        vesting.release();

        assertEq(token.balanceOf(beneficiary), TOTAL_AMOUNT);
    }

    function testRevokeAtExactCliffBoundary() public {
        vm.prank(owner);
        vesting.deposit(TOTAL_AMOUNT);

        // Warp to exact cliff end
        vm.warp(block.timestamp + CLIFF_DURATION);

        uint256 vestedAtCliffEnd = vesting.vestedAmount();
        uint256 ownerBalanceBefore = token.balanceOf(owner);

        vm.prank(owner);
        vesting.revoke();

        // Owner gets unvested portion
        assertEq(token.balanceOf(owner), ownerBalanceBefore + (TOTAL_AMOUNT - vestedAtCliffEnd));
    }

    function testZeroCliffDuration() public {
        // Create vesting with no cliff
        vm.prank(owner);
        SimpleVesting noCliff = new SimpleVesting(
            address(token),
            beneficiary,
            0, // no cliff
            VESTING_DURATION,
            true
        );

        token.mint(owner, TOTAL_AMOUNT);
        vm.prank(owner);
        token.approve(address(noCliff), TOTAL_AMOUNT);

        vm.prank(owner);
        noCliff.deposit(TOTAL_AMOUNT);

        // Should be able to release immediately (linear vesting from start)
        vm.warp(block.timestamp + 1 days);

        uint256 releasable = noCliff.releasable();
        assertGt(releasable, 0);

        vm.prank(beneficiary);
        noCliff.release();

        assertEq(token.balanceOf(beneficiary), releasable);
    }

    function testCliffEqualsVestingDuration() public {
        // Create vesting where cliff = full duration (cliff vesting)
        vm.prank(owner);
        SimpleVesting cliffOnly = new SimpleVesting(
            address(token),
            beneficiary,
            VESTING_DURATION, // cliff equals duration
            VESTING_DURATION,
            true
        );

        token.mint(owner, TOTAL_AMOUNT);
        vm.prank(owner);
        token.approve(address(cliffOnly), TOTAL_AMOUNT);

        vm.prank(owner);
        cliffOnly.deposit(TOTAL_AMOUNT);

        // Nothing releasable before cliff ends
        vm.warp(block.timestamp + VESTING_DURATION - 1);
        assertEq(cliffOnly.releasable(), 0);

        // Everything releasable after cliff ends
        vm.warp(block.timestamp + 2);
        assertEq(cliffOnly.releasable(), TOTAL_AMOUNT);
    }

    function testNoVestingAfterRevoke() public {
        vm.prank(owner);
        vesting.deposit(TOTAL_AMOUNT);

        // Revoke at 25%
        vm.warp(block.timestamp + VESTING_DURATION / 4);
        uint256 vestedAtRevoke = vesting.vestedAmount();

        vm.prank(owner);
        vesting.revoke();

        // Warp further - vested amount should stay the same
        vm.warp(block.timestamp + VESTING_DURATION);

        // totalAmount was set to vestedAtRevoke during revoke
        assertEq(vesting.totalAmount(), vestedAtRevoke);
        assertEq(vesting.vestedAmount(), vestedAtRevoke);
    }
}
