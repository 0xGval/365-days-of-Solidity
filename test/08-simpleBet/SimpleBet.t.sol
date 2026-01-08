// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "../../src/08-simpleBet/simpleBet.sol";

contract SimpleBetTest is Test {
    SimpleBet betContract;

    address playerA = address(0xA11CE);
    address playerB = address(0xB0B);
    address arbitrator = address(0xA7B1);
    address attacker = address(0xBAD);

    uint256 constant STAKE = 1 ether;

    // Events (redeclared for testing)
    event BetCreated(
        address indexed playerA,
        address indexed playerB,
        address indexed arbitrator,
        uint256 stakePerPlayer
    );
    event BetAccepted(address indexed playerB);
    event BetFunded(address indexed player, uint256 amount);
    event BetResolved(address indexed winner, uint256 amount);
    event BetCancelled();

    function setUp() public {
        betContract = new SimpleBet();

        // Give ETH to test actors
        vm.deal(playerA, 10 ether);
        vm.deal(playerB, 10 ether);
        vm.deal(attacker, 10 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            CREATION
    //////////////////////////////////////////////////////////////*/

    function testCreateBetSetsCorrectValues() public {
        vm.prank(playerA);
        betContract.createBet(playerB, arbitrator, STAKE);

        (
            address storedPlayerA,
            bool playerAFunded,
            address storedPlayerB,
            bool playerBFunded,
            address storedArbitrator,
            uint256 stakePerPlayer,
            SimpleBet.State state
        ) = betContract.bet();

        assertEq(storedPlayerA, playerA);
        assertEq(storedPlayerB, playerB);
        assertEq(storedArbitrator, arbitrator);
        assertEq(stakePerPlayer, STAKE);
        assertFalse(playerAFunded);
        assertFalse(playerBFunded);
        assertEq(uint256(state), uint256(SimpleBet.State.Created));
    }

    function testCannotCreateBetTwice() public {
        vm.prank(playerA);
        betContract.createBet(playerB, arbitrator, STAKE);

        vm.prank(playerA);
        vm.expectRevert(SimpleBet.InvalidState.selector);
        betContract.createBet(playerB, arbitrator, STAKE);
    }

    function testCannotCreateBetWithZeroAddressPlayerB() public {
        vm.prank(playerA);
        vm.expectRevert(SimpleBet.InvalidPlayer.selector);
        betContract.createBet(address(0), arbitrator, STAKE);
    }

    function testCannotCreateBetWithSelfAsPlayerB() public {
        vm.prank(playerA);
        vm.expectRevert(SimpleBet.InvalidPlayer.selector);
        betContract.createBet(playerA, arbitrator, STAKE);
    }

    function testCannotCreateBetWithZeroAddressArbitrator() public {
        vm.prank(playerA);
        vm.expectRevert(SimpleBet.InvalidArbitrator.selector);
        betContract.createBet(playerB, address(0), STAKE);
    }

    function testCannotCreateBetWithSelfAsArbitrator() public {
        vm.prank(playerA);
        vm.expectRevert(SimpleBet.InvalidArbitrator.selector);
        betContract.createBet(playerB, playerA, STAKE);
    }

    function testCannotCreateBetWithPlayerBAsArbitrator() public {
        vm.prank(playerA);
        vm.expectRevert(SimpleBet.InvalidArbitrator.selector);
        betContract.createBet(playerB, playerB, STAKE);
    }

    function testCannotCreateBetWithZeroStake() public {
        vm.prank(playerA);
        vm.expectRevert(SimpleBet.InvalidBetValue.selector);
        betContract.createBet(playerB, arbitrator, 0);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCEPTANCE
    //////////////////////////////////////////////////////////////*/

    function testPlayerBCanAcceptBet() public {
        vm.prank(playerA);
        betContract.createBet(playerB, arbitrator, STAKE);

        vm.prank(playerB);
        betContract.acceptBet();

        (, , , , , , SimpleBet.State state) = betContract.bet();
        assertEq(uint256(state), uint256(SimpleBet.State.Accepted));
    }

    function testOnlyPlayerBCanAccept() public {
        vm.prank(playerA);
        betContract.createBet(playerB, arbitrator, STAKE);

        vm.prank(playerA);
        vm.expectRevert(SimpleBet.NotPlayerB.selector);
        betContract.acceptBet();

        vm.prank(attacker);
        vm.expectRevert(SimpleBet.NotPlayerB.selector);
        betContract.acceptBet();
    }

    function testCannotAcceptNonCreatedBet() public {
        vm.prank(playerB);
        vm.expectRevert(SimpleBet.NotPlayerB.selector);
        betContract.acceptBet();
    }

    function testCannotAcceptTwice() public {
        vm.prank(playerA);
        betContract.createBet(playerB, arbitrator, STAKE);

        vm.prank(playerB);
        betContract.acceptBet();

        vm.prank(playerB);
        vm.expectRevert(SimpleBet.InvalidState.selector);
        betContract.acceptBet();
    }

    /*//////////////////////////////////////////////////////////////
                            FUNDING
    //////////////////////////////////////////////////////////////*/

    function testPlayerACanFund() public {
        vm.prank(playerA);
        betContract.createBet(playerB, arbitrator, STAKE);

        vm.prank(playerB);
        betContract.acceptBet();

        vm.prank(playerA);
        betContract.fundBet{value: STAKE}();

        (, bool playerAFunded, , , , , SimpleBet.State state) = betContract.bet();
        assertTrue(playerAFunded);
        assertEq(uint256(state), uint256(SimpleBet.State.Accepted));
    }

    function testPlayerBCanFund() public {
        vm.prank(playerA);
        betContract.createBet(playerB, arbitrator, STAKE);

        vm.prank(playerB);
        betContract.acceptBet();

        vm.prank(playerB);
        betContract.fundBet{value: STAKE}();

        (, , , bool playerBFunded, , , SimpleBet.State state) = betContract.bet();
        assertTrue(playerBFunded);
        assertEq(uint256(state), uint256(SimpleBet.State.Accepted));
    }

    function testBothPlayersFundingTransitionsToFunded() public {
        vm.prank(playerA);
        betContract.createBet(playerB, arbitrator, STAKE);

        vm.prank(playerB);
        betContract.acceptBet();

        vm.prank(playerA);
        betContract.fundBet{value: STAKE}();

        vm.prank(playerB);
        betContract.fundBet{value: STAKE}();

        (
            ,
            bool playerAFunded,
            ,
            bool playerBFunded,
            ,
            ,
            SimpleBet.State state
        ) = betContract.bet();

        assertTrue(playerAFunded);
        assertTrue(playerBFunded);
        assertEq(uint256(state), uint256(SimpleBet.State.Funded));
        assertEq(address(betContract).balance, STAKE * 2);
    }

    function testCannotFundWithWrongAmount() public {
        vm.prank(playerA);
        betContract.createBet(playerB, arbitrator, STAKE);

        vm.prank(playerB);
        betContract.acceptBet();

        vm.prank(playerA);
        vm.expectRevert(SimpleBet.ValueMustMatchStakePerPlayer.selector);
        betContract.fundBet{value: STAKE + 1}();

        vm.prank(playerA);
        vm.expectRevert(SimpleBet.ValueMustMatchStakePerPlayer.selector);
        betContract.fundBet{value: STAKE - 1}();
    }

    function testCannotFundTwice() public {
        vm.prank(playerA);
        betContract.createBet(playerB, arbitrator, STAKE);

        vm.prank(playerB);
        betContract.acceptBet();

        vm.prank(playerA);
        betContract.fundBet{value: STAKE}();

        vm.prank(playerA);
        vm.expectRevert(SimpleBet.PlayerAlreadyFunded.selector);
        betContract.fundBet{value: STAKE}();
    }

    function testNonPlayerCannotFund() public {
        vm.prank(playerA);
        betContract.createBet(playerB, arbitrator, STAKE);

        vm.prank(playerB);
        betContract.acceptBet();

        vm.prank(attacker);
        vm.expectRevert(SimpleBet.NotBetPlayer.selector);
        betContract.fundBet{value: STAKE}();
    }

    function testCannotFundBeforeAcceptance() public {
        vm.prank(playerA);
        betContract.createBet(playerB, arbitrator, STAKE);

        vm.prank(playerA);
        vm.expectRevert(SimpleBet.InvalidState.selector);
        betContract.fundBet{value: STAKE}();
    }

    /*//////////////////////////////////////////////////////////////
                            RESOLUTION
    //////////////////////////////////////////////////////////////*/

    function testArbitratorCanResolveForPlayerA() public {
        _createAcceptAndFundBet();

        uint256 balanceBefore = playerA.balance;

        vm.prank(arbitrator);
        betContract.resolveBet(playerA);

        (, , , , , , SimpleBet.State state) = betContract.bet();
        assertEq(uint256(state), uint256(SimpleBet.State.Resolved));
        assertEq(playerA.balance, balanceBefore + STAKE * 2);
        assertEq(address(betContract).balance, 0);
    }

    function testArbitratorCanResolveForPlayerB() public {
        _createAcceptAndFundBet();

        uint256 balanceBefore = playerB.balance;

        vm.prank(arbitrator);
        betContract.resolveBet(playerB);

        (, , , , , , SimpleBet.State state) = betContract.bet();
        assertEq(uint256(state), uint256(SimpleBet.State.Resolved));
        assertEq(playerB.balance, balanceBefore + STAKE * 2);
        assertEq(address(betContract).balance, 0);
    }

    function testOnlyArbitratorCanResolve() public {
        _createAcceptAndFundBet();

        vm.prank(playerA);
        vm.expectRevert(SimpleBet.NotArbitrator.selector);
        betContract.resolveBet(playerA);

        vm.prank(playerB);
        vm.expectRevert(SimpleBet.NotArbitrator.selector);
        betContract.resolveBet(playerB);

        vm.prank(attacker);
        vm.expectRevert(SimpleBet.NotArbitrator.selector);
        betContract.resolveBet(playerA);
    }

    function testCannotResolveWithInvalidWinner() public {
        _createAcceptAndFundBet();

        vm.prank(arbitrator);
        vm.expectRevert(SimpleBet.WinnerMustBePlayer.selector);
        betContract.resolveBet(attacker);

        vm.prank(arbitrator);
        vm.expectRevert(SimpleBet.WinnerMustBePlayer.selector);
        betContract.resolveBet(arbitrator);
    }

    function testCannotResolveBeforeFunded() public {
        vm.prank(playerA);
        betContract.createBet(playerB, arbitrator, STAKE);

        vm.prank(playerB);
        betContract.acceptBet();

        vm.prank(playerA);
        betContract.fundBet{value: STAKE}();

        // Only playerA funded, not fully funded yet
        vm.prank(arbitrator);
        vm.expectRevert(SimpleBet.InvalidState.selector);
        betContract.resolveBet(playerA);
    }

    function testCannotResolveTwice() public {
        _createAcceptAndFundBet();

        vm.prank(arbitrator);
        betContract.resolveBet(playerA);

        vm.prank(arbitrator);
        vm.expectRevert(SimpleBet.InvalidState.selector);
        betContract.resolveBet(playerB);
    }

    /*//////////////////////////////////////////////////////////////
                            CANCELLATION
    //////////////////////////////////////////////////////////////*/

    function testPlayerACanCancelInCreatedState() public {
        vm.prank(playerA);
        betContract.createBet(playerB, arbitrator, STAKE);

        vm.prank(playerA);
        betContract.cancelBet();

        (, , , , , , SimpleBet.State state) = betContract.bet();
        assertEq(uint256(state), uint256(SimpleBet.State.Cancelled));
    }

    function testPlayerACanCancelInAcceptedState() public {
        vm.prank(playerA);
        betContract.createBet(playerB, arbitrator, STAKE);

        vm.prank(playerB);
        betContract.acceptBet();

        vm.prank(playerA);
        betContract.cancelBet();

        (, , , , , , SimpleBet.State state) = betContract.bet();
        assertEq(uint256(state), uint256(SimpleBet.State.Cancelled));
    }

    function testCancelRefundsPlayerAIfFunded() public {
        vm.prank(playerA);
        betContract.createBet(playerB, arbitrator, STAKE);

        vm.prank(playerB);
        betContract.acceptBet();

        vm.prank(playerA);
        betContract.fundBet{value: STAKE}();

        uint256 balanceBefore = playerA.balance;

        vm.prank(playerA);
        betContract.cancelBet();

        assertEq(playerA.balance, balanceBefore + STAKE);
        assertEq(address(betContract).balance, 0);
    }

    function testCancelRefundsPlayerBIfFunded() public {
        vm.prank(playerA);
        betContract.createBet(playerB, arbitrator, STAKE);

        vm.prank(playerB);
        betContract.acceptBet();

        vm.prank(playerB);
        betContract.fundBet{value: STAKE}();

        uint256 balanceBefore = playerB.balance;

        vm.prank(playerA);
        betContract.cancelBet();

        assertEq(playerB.balance, balanceBefore + STAKE);
        assertEq(address(betContract).balance, 0);
    }

    function testOnlyPlayerACanCancel() public {
        vm.prank(playerA);
        betContract.createBet(playerB, arbitrator, STAKE);

        vm.prank(playerB);
        vm.expectRevert(SimpleBet.NotPlayerA.selector);
        betContract.cancelBet();

        vm.prank(attacker);
        vm.expectRevert(SimpleBet.NotPlayerA.selector);
        betContract.cancelBet();
    }

    function testCannotCancelAfterFullyFunded() public {
        _createAcceptAndFundBet();

        vm.prank(playerA);
        vm.expectRevert(SimpleBet.InvalidState.selector);
        betContract.cancelBet();
    }

    function testCannotCancelAfterResolved() public {
        _createAcceptAndFundBet();

        vm.prank(arbitrator);
        betContract.resolveBet(playerA);

        vm.prank(playerA);
        vm.expectRevert(SimpleBet.InvalidState.selector);
        betContract.cancelBet();
    }

    function testCannotCancelTwice() public {
        vm.prank(playerA);
        betContract.createBet(playerB, arbitrator, STAKE);

        vm.prank(playerA);
        betContract.cancelBet();

        vm.prank(playerA);
        vm.expectRevert(SimpleBet.InvalidState.selector);
        betContract.cancelBet();
    }

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    function testBetCreatedEventEmitted() public {
        vm.expectEmit(true, true, true, true);
        emit BetCreated(playerA, playerB, arbitrator, STAKE);

        vm.prank(playerA);
        betContract.createBet(playerB, arbitrator, STAKE);
    }

    function testBetAcceptedEventEmitted() public {
        vm.prank(playerA);
        betContract.createBet(playerB, arbitrator, STAKE);

        vm.expectEmit(true, false, false, false);
        emit BetAccepted(playerB);

        vm.prank(playerB);
        betContract.acceptBet();
    }

    function testBetFundedEventEmitted() public {
        vm.prank(playerA);
        betContract.createBet(playerB, arbitrator, STAKE);

        vm.prank(playerB);
        betContract.acceptBet();

        vm.expectEmit(true, false, false, true);
        emit BetFunded(playerA, STAKE);

        vm.prank(playerA);
        betContract.fundBet{value: STAKE}();
    }

    function testBetResolvedEventEmitted() public {
        _createAcceptAndFundBet();

        vm.expectEmit(true, false, false, true);
        emit BetResolved(playerA, STAKE * 2);

        vm.prank(arbitrator);
        betContract.resolveBet(playerA);
    }

    function testBetCancelledEventEmitted() public {
        vm.prank(playerA);
        betContract.createBet(playerB, arbitrator, STAKE);

        vm.expectEmit(false, false, false, false);
        emit BetCancelled();

        vm.prank(playerA);
        betContract.cancelBet();
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    function _createAcceptAndFundBet() internal {
        vm.prank(playerA);
        betContract.createBet(playerB, arbitrator, STAKE);

        vm.prank(playerB);
        betContract.acceptBet();

        vm.prank(playerA);
        betContract.fundBet{value: STAKE}();

        vm.prank(playerB);
        betContract.fundBet{value: STAKE}();
    }
}
