// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "../../src/09-CommitReveal/CommitReveal.sol";

contract CommitRevealGameTest is Test {
    CommitRevealGame game;

    address playerA = address(0xA11CE);
    address playerB = address(0xB0B);
    address attacker = address(0xBAD);

    uint256 constant COMMIT_DURATION = 1 hours;
    uint256 constant REVEAL_DURATION = 1 hours;

    // Secrets and choices for testing
    bytes32 constant CHOICE_A = bytes32(uint256(100));
    bytes32 constant CHOICE_B = bytes32(uint256(50));
    bytes32 constant SALT_A = bytes32(uint256(12345));
    bytes32 constant SALT_B = bytes32(uint256(67890));

    // Events (redeclared for testing)
    event GameCreated(
        address indexed playerA,
        address indexed playerB,
        uint256 commitDeadline
    );
    event Committed(address indexed player);
    event Revealed(address indexed player, bytes32 choice);
    event GameResolved(
        address indexed winner,
        bytes32 playerAChoice,
        bytes32 playerBChoice
    );

    function setUp() public {
        game = new CommitRevealGame(COMMIT_DURATION, REVEAL_DURATION);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    function _computeCommit(
        bytes32 choice,
        bytes32 salt
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(choice, salt));
    }

    function _createGame() internal {
        bytes32 commitA = _computeCommit(CHOICE_A, SALT_A);
        vm.prank(playerA);
        game.createGameRound(playerB, commitA);
    }

    function _createAndCommitB() internal {
        _createGame();
        bytes32 commitB = _computeCommit(CHOICE_B, SALT_B);
        vm.prank(playerB);
        game.commitChoice(commitB);
    }

    function _fullRevealBothPlayers() internal {
        _createAndCommitB();

        vm.prank(playerA);
        game.reveal(CHOICE_A, SALT_A);

        vm.prank(playerB);
        game.reveal(CHOICE_B, SALT_B);
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function testConstructorSetsCorrectDurations() public view {
        assertEq(game.commitDuration(), COMMIT_DURATION);
        assertEq(game.revealDuration(), REVEAL_DURATION);
    }

    /*//////////////////////////////////////////////////////////////
                            GAME CREATION
    //////////////////////////////////////////////////////////////*/

    function testCreateGameSetsCorrectValues() public {
        bytes32 commitA = _computeCommit(CHOICE_A, SALT_A);

        vm.prank(playerA);
        game.createGameRound(playerB, commitA);

        (
            address storedPlayerA,
            address storedPlayerB,
            bytes32 storedCommitA,
            bytes32 storedCommitB,
            ,
            ,
            ,
            ,
            uint256 commitDeadline,
            ,
            ,
            CommitRevealGame.State state
        ) = game.gameRound();

        assertEq(storedPlayerA, playerA);
        assertEq(storedPlayerB, playerB);
        assertEq(storedCommitA, commitA);
        assertEq(storedCommitB, bytes32(0));
        assertEq(commitDeadline, block.timestamp + COMMIT_DURATION);
        assertEq(uint256(state), uint256(CommitRevealGame.State.Commit));
    }

    function testCannotCreateGameTwice() public {
        _createGame();

        bytes32 commitA = _computeCommit(CHOICE_A, SALT_A);
        vm.prank(playerA);
        vm.expectRevert(CommitRevealGame.InvalidState.selector);
        game.createGameRound(playerB, commitA);
    }

    function testCannotCreateGameWithZeroAddressPlayerB() public {
        bytes32 commitA = _computeCommit(CHOICE_A, SALT_A);

        vm.prank(playerA);
        vm.expectRevert(CommitRevealGame.InvalidPlayer.selector);
        game.createGameRound(address(0), commitA);
    }

    function testCannotCreateGameWithSelfAsPlayerB() public {
        bytes32 commitA = _computeCommit(CHOICE_A, SALT_A);

        vm.prank(playerA);
        vm.expectRevert(CommitRevealGame.InvalidPlayer.selector);
        game.createGameRound(playerA, commitA);
    }

    function testCannotCreateGameWithZeroCommit() public {
        vm.prank(playerA);
        vm.expectRevert(CommitRevealGame.InvalidCommit.selector);
        game.createGameRound(playerB, bytes32(0));
    }

    /*//////////////////////////////////////////////////////////////
                            COMMIT PHASE
    //////////////////////////////////////////////////////////////*/

    function testPlayerBCanCommit() public {
        _createGame();

        bytes32 commitB = _computeCommit(CHOICE_B, SALT_B);

        vm.prank(playerB);
        game.commitChoice(commitB);

        (, , , bytes32 storedCommitB, , , , , , uint256 revealDeadline, , CommitRevealGame.State state) = game
            .gameRound();

        assertEq(storedCommitB, commitB);
        assertEq(revealDeadline, block.timestamp + REVEAL_DURATION);
        assertEq(uint256(state), uint256(CommitRevealGame.State.Reveal));
    }

    function testOnlyPlayerBCanCommit() public {
        _createGame();

        bytes32 commitB = _computeCommit(CHOICE_B, SALT_B);

        vm.prank(playerA);
        vm.expectRevert(CommitRevealGame.InvalidPlayer.selector);
        game.commitChoice(commitB);

        vm.prank(attacker);
        vm.expectRevert(CommitRevealGame.InvalidPlayer.selector);
        game.commitChoice(commitB);
    }

    function testCannotCommitAfterDeadline() public {
        _createGame();

        bytes32 commitB = _computeCommit(CHOICE_B, SALT_B);

        // Fast forward past commit deadline
        vm.warp(block.timestamp + COMMIT_DURATION + 1);

        vm.prank(playerB);
        vm.expectRevert(
            abi.encodeWithSelector(
                CommitRevealGame.CommitPhaseExpired.selector,
                block.timestamp - 1
            )
        );
        game.commitChoice(commitB);
    }

    function testCannotCommitWithZeroHash() public {
        _createGame();

        vm.prank(playerB);
        vm.expectRevert(CommitRevealGame.InvalidCommit.selector);
        game.commitChoice(bytes32(0));
    }

    function testCannotCommitTwice() public {
        _createAndCommitB();

        bytes32 newCommit = _computeCommit(bytes32(uint256(999)), SALT_B);

        vm.prank(playerB);
        vm.expectRevert(CommitRevealGame.InvalidState.selector);
        game.commitChoice(newCommit);
    }

    /*//////////////////////////////////////////////////////////////
                            REVEAL PHASE
    //////////////////////////////////////////////////////////////*/

    function testPlayerACanReveal() public {
        _createAndCommitB();

        vm.prank(playerA);
        game.reveal(CHOICE_A, SALT_A);

        (, , , , bytes32 storedChoiceA, , bool playerARevealed, , , , , ) = game
            .gameRound();

        assertEq(storedChoiceA, CHOICE_A);
        assertTrue(playerARevealed);
    }

    function testPlayerBCanReveal() public {
        _createAndCommitB();

        vm.prank(playerB);
        game.reveal(CHOICE_B, SALT_B);

        (, , , , , bytes32 storedChoiceB, , bool playerBRevealed, , , , ) = game
            .gameRound();

        assertEq(storedChoiceB, CHOICE_B);
        assertTrue(playerBRevealed);
    }

    function testOnlyPlayersCanReveal() public {
        _createAndCommitB();

        vm.prank(attacker);
        vm.expectRevert(CommitRevealGame.InvalidPlayer.selector);
        game.reveal(CHOICE_A, SALT_A);
    }

    function testCannotRevealWithWrongChoice() public {
        _createAndCommitB();

        bytes32 wrongChoice = bytes32(uint256(999));

        vm.prank(playerA);
        vm.expectRevert(CommitRevealGame.InvalidReveal.selector);
        game.reveal(wrongChoice, SALT_A);
    }

    function testCannotRevealWithWrongSalt() public {
        _createAndCommitB();

        bytes32 wrongSalt = bytes32(uint256(99999));

        vm.prank(playerA);
        vm.expectRevert(CommitRevealGame.InvalidReveal.selector);
        game.reveal(CHOICE_A, wrongSalt);
    }

    function testCannotRevealTwice() public {
        _createAndCommitB();

        vm.prank(playerA);
        game.reveal(CHOICE_A, SALT_A);

        vm.prank(playerA);
        vm.expectRevert(CommitRevealGame.AlreadyRevealed.selector);
        game.reveal(CHOICE_A, SALT_A);
    }

    function testCannotRevealAfterDeadline() public {
        _createAndCommitB();

        // Fast forward past reveal deadline
        vm.warp(block.timestamp + REVEAL_DURATION + 1);

        vm.prank(playerA);
        vm.expectRevert(
            abi.encodeWithSelector(
                CommitRevealGame.RevealPhaseExpired.selector,
                block.timestamp - 1
            )
        );
        game.reveal(CHOICE_A, SALT_A);
    }

    function testCannotRevealBeforeCommitPhase() public {
        _createGame();

        vm.prank(playerA);
        vm.expectRevert(CommitRevealGame.InvalidState.selector);
        game.reveal(CHOICE_A, SALT_A);
    }

    /*//////////////////////////////////////////////////////////////
                            AUTO-RESOLUTION
    //////////////////////////////////////////////////////////////*/

    function testAutoResolveWhenBothReveal() public {
        _fullRevealBothPlayers();

        (, , , , , , , , , , address winner, CommitRevealGame.State state) = game
            .gameRound();

        // CHOICE_A (100) > CHOICE_B (50), so playerA wins
        assertEq(winner, playerA);
        assertEq(uint256(state), uint256(CommitRevealGame.State.Resolved));
    }

    function testAutoResolvePlayerBWinsIfHigherChoice() public {
        _createGame();

        // B commits with higher choice
        bytes32 higherChoice = bytes32(uint256(200));
        bytes32 commitB = _computeCommit(higherChoice, SALT_B);

        vm.prank(playerB);
        game.commitChoice(commitB);

        vm.prank(playerA);
        game.reveal(CHOICE_A, SALT_A);

        vm.prank(playerB);
        game.reveal(higherChoice, SALT_B);

        (, , , , , , , , , , address winner, ) = game.gameRound();

        assertEq(winner, playerB);
    }

    function testAutoResolveTieResultsInNoWinner() public {
        _createGame();

        // B commits with same choice as A
        bytes32 commitB = _computeCommit(CHOICE_A, SALT_B);

        vm.prank(playerB);
        game.commitChoice(commitB);

        vm.prank(playerA);
        game.reveal(CHOICE_A, SALT_A);

        vm.prank(playerB);
        game.reveal(CHOICE_A, SALT_B);

        (, , , , , , , , , , address winner, ) = game.gameRound();

        assertEq(winner, address(0));
    }

    /*//////////////////////////////////////////////////////////////
                            TIMEOUT RESOLUTION
    //////////////////////////////////////////////////////////////*/

    function testResolveTimeoutPlayerAWinsIfBDoesNotCommit() public {
        _createGame();

        // Fast forward past commit deadline
        vm.warp(block.timestamp + COMMIT_DURATION + 1);

        game.resolveAfterTimeout();

        (, , , , , , , , , , address winner, CommitRevealGame.State state) = game
            .gameRound();

        assertEq(winner, playerA);
        assertEq(uint256(state), uint256(CommitRevealGame.State.Resolved));
    }

    function testResolveTimeoutPlayerAWinsIfOnlyAReveals() public {
        _createAndCommitB();

        vm.prank(playerA);
        game.reveal(CHOICE_A, SALT_A);

        // Fast forward past reveal deadline
        vm.warp(block.timestamp + REVEAL_DURATION + 1);

        game.resolveAfterTimeout();

        (, , , , , , , , , , address winner, CommitRevealGame.State state) = game
            .gameRound();

        assertEq(winner, playerA);
        assertEq(uint256(state), uint256(CommitRevealGame.State.Resolved));
    }

    function testResolveTimeoutPlayerBWinsIfOnlyBReveals() public {
        _createAndCommitB();

        vm.prank(playerB);
        game.reveal(CHOICE_B, SALT_B);

        // Fast forward past reveal deadline
        vm.warp(block.timestamp + REVEAL_DURATION + 1);

        game.resolveAfterTimeout();

        (, , , , , , , , , , address winner, CommitRevealGame.State state) = game
            .gameRound();

        assertEq(winner, playerB);
        assertEq(uint256(state), uint256(CommitRevealGame.State.Resolved));
    }

    function testResolveTimeoutNoWinnerIfNobodyReveals() public {
        _createAndCommitB();

        // Fast forward past reveal deadline without any reveals
        vm.warp(block.timestamp + REVEAL_DURATION + 1);

        game.resolveAfterTimeout();

        (, , , , , , , , , , address winner, CommitRevealGame.State state) = game
            .gameRound();

        assertEq(winner, address(0));
        assertEq(uint256(state), uint256(CommitRevealGame.State.Resolved));
    }

    function testCannotResolveTimeoutBeforeCommitDeadline() public {
        _createGame();

        vm.expectRevert(CommitRevealGame.InvalidState.selector);
        game.resolveAfterTimeout();
    }

    function testCannotResolveTimeoutBeforeRevealDeadline() public {
        _createAndCommitB();

        vm.expectRevert(CommitRevealGame.InvalidState.selector);
        game.resolveAfterTimeout();
    }

    function testCannotResolveTimeoutWhenAlreadyResolved() public {
        _fullRevealBothPlayers();

        vm.expectRevert(CommitRevealGame.InvalidState.selector);
        game.resolveAfterTimeout();
    }

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    function testGameCreatedEventEmitted() public {
        bytes32 commitA = _computeCommit(CHOICE_A, SALT_A);
        uint256 expectedDeadline = block.timestamp + COMMIT_DURATION;

        vm.expectEmit(true, true, false, true);
        emit GameCreated(playerA, playerB, expectedDeadline);

        vm.prank(playerA);
        game.createGameRound(playerB, commitA);
    }

    function testCommittedEventEmittedForPlayerA() public {
        bytes32 commitA = _computeCommit(CHOICE_A, SALT_A);

        vm.expectEmit(true, false, false, false);
        emit Committed(playerA);

        vm.prank(playerA);
        game.createGameRound(playerB, commitA);
    }

    function testCommittedEventEmittedForPlayerB() public {
        _createGame();

        bytes32 commitB = _computeCommit(CHOICE_B, SALT_B);

        vm.expectEmit(true, false, false, false);
        emit Committed(playerB);

        vm.prank(playerB);
        game.commitChoice(commitB);
    }

    function testRevealedEventEmitted() public {
        _createAndCommitB();

        vm.expectEmit(true, false, false, true);
        emit Revealed(playerA, CHOICE_A);

        vm.prank(playerA);
        game.reveal(CHOICE_A, SALT_A);
    }

    function testGameResolvedEventEmittedOnAutoResolve() public {
        _createAndCommitB();

        vm.prank(playerA);
        game.reveal(CHOICE_A, SALT_A);

        vm.expectEmit(true, false, false, true);
        emit GameResolved(playerA, CHOICE_A, CHOICE_B);

        vm.prank(playerB);
        game.reveal(CHOICE_B, SALT_B);
    }

    function testGameResolvedEventEmittedOnTimeout() public {
        _createGame();

        vm.warp(block.timestamp + COMMIT_DURATION + 1);

        vm.expectEmit(true, false, false, true);
        emit GameResolved(playerA, bytes32(0), bytes32(0));

        game.resolveAfterTimeout();
    }
}
