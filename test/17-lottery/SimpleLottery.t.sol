// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test} from "lib/forge-std/src/Test.sol";
import {SimpleLottery} from "../../src/17-lottery/SimpleLottery.sol";

contract SimpleLotteryTest is Test {
    SimpleLottery lottery;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address charlie = address(0xC0C);
    address outsider = address(0x0DD);

    uint256 constant TICKET_PRICE = 0.1 ether;
    uint256 constant MIN_PLAYERS = 3;
    uint256 constant MAX_PLAYERS = 10;
    uint256 constant DURATION = 1 days;

    event TicketPurchased(address indexed player, uint256 ticketNumber);
    event DrawInitiated(uint256 drawBlock);
    event WinnerRevealed(address indexed winner, uint256 prize);
    event PrizeClaimed(address indexed winner, uint256 amount);
    event LotteryCancelled();
    event RefundClaimed(address indexed player, uint256 amount);

    function setUp() public {
        uint256 deadline = block.timestamp + DURATION;
        lottery = new SimpleLottery(MIN_PLAYERS, deadline, TICKET_PRICE, MAX_PLAYERS);

        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(charlie, 10 ether);
        vm.deal(outsider, 10 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function testConstructorSetsParameters() public view {
        assertEq(lottery.i_minPlayers(), MIN_PLAYERS);
        assertEq(lottery.i_maxPlayers(), MAX_PLAYERS);
        assertEq(lottery.i_ticketPrice(), TICKET_PRICE);
        assertEq(lottery.i_deadline(), block.timestamp + DURATION);
        assertEq(lottery.i_owner(), address(this));
    }

    function testConstructorSetsOpenState() public view {
        assertEq(uint256(lottery.s_state()), uint256(SimpleLottery.State.Open));
    }

    function testConstructorRevertsIfTicketPriceIsZero() public {
        vm.expectRevert(SimpleLottery.InvalidPrice.selector);
        new SimpleLottery(MIN_PLAYERS, block.timestamp + DURATION, 0, MAX_PLAYERS);
    }

    function testConstructorRevertsIfMinPlayersIsZero() public {
        vm.expectRevert(SimpleLottery.InvalidPlayersNumber.selector);
        new SimpleLottery(0, block.timestamp + DURATION, TICKET_PRICE, MAX_PLAYERS);
    }

    function testConstructorRevertsIfMaxPlayersLessThanMinPlayers() public {
        vm.expectRevert(SimpleLottery.InvalidPlayersNumber.selector);
        new SimpleLottery(10, block.timestamp + DURATION, TICKET_PRICE, 5);
    }

    function testConstructorRevertsIfDeadlineInThePast() public {
        vm.expectRevert(SimpleLottery.InvalidDeadline.selector);
        new SimpleLottery(MIN_PLAYERS, block.timestamp - 1, TICKET_PRICE, MAX_PLAYERS);
    }

    function testConstructorRevertsIfDeadlineIsNow() public {
        vm.expectRevert(SimpleLottery.InvalidDeadline.selector);
        new SimpleLottery(MIN_PLAYERS, block.timestamp, TICKET_PRICE, MAX_PLAYERS);
    }

    /*//////////////////////////////////////////////////////////////
                        TICKET PURCHASE TESTS
    //////////////////////////////////////////////////////////////*/

    function testBuyTicketSucceeds() public {
        vm.prank(alice);
        lottery.buyTicket{value: TICKET_PRICE}();

        assertEq(lottery.getTicketCount(), 1);
        assertEq(lottery.getPlayer(0), alice);
        assertEq(lottery.getContribution(alice), TICKET_PRICE);
    }

    function testBuyMultipleTickets() public {
        vm.startPrank(alice);
        lottery.buyTicket{value: TICKET_PRICE}();
        lottery.buyTicket{value: TICKET_PRICE}();
        lottery.buyTicket{value: TICKET_PRICE}();
        vm.stopPrank();

        assertEq(lottery.getTicketCount(), 3);
        assertEq(lottery.getPlayer(0), alice);
        assertEq(lottery.getPlayer(1), alice);
        assertEq(lottery.getPlayer(2), alice);
        assertEq(lottery.getContribution(alice), TICKET_PRICE * 3);
    }

    function testBuyTicketEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit TicketPurchased(alice, 0);

        vm.prank(alice);
        lottery.buyTicket{value: TICKET_PRICE}();
    }

    function testBuyTicketEmitsCorrectTicketNumber() public {
        vm.prank(alice);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.expectEmit(true, false, false, true);
        emit TicketPurchased(bob, 1);

        vm.prank(bob);
        lottery.buyTicket{value: TICKET_PRICE}();
    }

    function testBuyTicketRevertsIfWrongAmount() public {
        vm.prank(alice);
        vm.expectRevert(SimpleLottery.IncorrectTicketPrice.selector);
        lottery.buyTicket{value: TICKET_PRICE + 1}();
    }

    function testBuyTicketRevertsIfTooLittleETH() public {
        vm.prank(alice);
        vm.expectRevert(SimpleLottery.IncorrectTicketPrice.selector);
        lottery.buyTicket{value: TICKET_PRICE - 1}();
    }

    function testBuyTicketRevertsIfNoETH() public {
        vm.prank(alice);
        vm.expectRevert(SimpleLottery.IncorrectTicketPrice.selector);
        lottery.buyTicket{value: 0}();
    }

    function testBuyTicketRevertsIfLotteryFull() public {
        // Fill up the lottery
        for (uint256 i = 0; i < MAX_PLAYERS; i++) {
            address player = address(uint160(i + 100));
            vm.deal(player, 1 ether);
            vm.prank(player);
            lottery.buyTicket{value: TICKET_PRICE}();
        }

        vm.prank(alice);
        vm.expectRevert(SimpleLottery.MaxPlayersReached.selector);
        lottery.buyTicket{value: TICKET_PRICE}();
    }

    function testBuyTicketRevertsIfDeadlinePassed() public {
        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(alice);
        vm.expectRevert(SimpleLottery.DeadlinePassed.selector);
        lottery.buyTicket{value: TICKET_PRICE}();
    }

    function testBuyTicketRevertsIfNotOpenState() public {
        // Buy enough tickets and trigger draw
        _buyTickets(MIN_PLAYERS);
        vm.warp(block.timestamp + DURATION + 1);
        lottery.draw();

        vm.prank(alice);
        vm.expectRevert(SimpleLottery.LotteryNotOpen.selector);
        lottery.buyTicket{value: TICKET_PRICE}();
    }

    /*//////////////////////////////////////////////////////////////
                            DRAW TESTS
    //////////////////////////////////////////////////////////////*/

    function testDrawSucceeds() public {
        _buyTickets(MIN_PLAYERS);
        vm.warp(block.timestamp + DURATION + 1);

        lottery.draw();

        assertEq(uint256(lottery.s_state()), uint256(SimpleLottery.State.Drawing));
        assertEq(lottery.s_drawBlock(), block.number);
    }

    function testDrawEmitsEvent() public {
        _buyTickets(MIN_PLAYERS);
        vm.warp(block.timestamp + DURATION + 1);

        vm.expectEmit(false, false, false, true);
        emit DrawInitiated(block.number);

        lottery.draw();
    }

    function testDrawCanBeCalledByAnyone() public {
        _buyTickets(MIN_PLAYERS);
        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(outsider);
        lottery.draw();

        assertEq(uint256(lottery.s_state()), uint256(SimpleLottery.State.Drawing));
    }

    function testDrawRevertsIfDeadlineNotReached() public {
        _buyTickets(MIN_PLAYERS);

        vm.expectRevert(SimpleLottery.DeadlineNotReached.selector);
        lottery.draw();
    }

    function testDrawRevertsIfMinPlayersNotReached() public {
        _buyTickets(MIN_PLAYERS - 1);
        vm.warp(block.timestamp + DURATION + 1);

        vm.expectRevert(SimpleLottery.MinPlayersNotReached.selector);
        lottery.draw();
    }

    function testDrawRevertsIfNotOpenState() public {
        _buyTickets(MIN_PLAYERS);
        vm.warp(block.timestamp + DURATION + 1);
        lottery.draw();

        vm.expectRevert(SimpleLottery.LotteryNotOpen.selector);
        lottery.draw();
    }

    /*//////////////////////////////////////////////////////////////
                        REVEAL WINNER TESTS
    //////////////////////////////////////////////////////////////*/

    function testRevealWinnerSucceeds() public {
        _buyTickets(MIN_PLAYERS);
        vm.warp(block.timestamp + DURATION + 1);
        lottery.draw();

        // Advance 2 blocks
        vm.roll(block.number + 2);

        lottery.revealWinner();

        assertEq(uint256(lottery.s_state()), uint256(SimpleLottery.State.Completed));
        assertTrue(lottery.s_winner() != address(0));
    }

    function testRevealWinnerSelectsFromPlayers() public {
        _buyTickets(MIN_PLAYERS);
        vm.warp(block.timestamp + DURATION + 1);
        lottery.draw();

        vm.roll(block.number + 2);
        lottery.revealWinner();

        address winner = lottery.s_winner();
        bool isValidPlayer = false;
        for (uint256 i = 0; i < lottery.getTicketCount(); i++) {
            if (lottery.getPlayer(i) == winner) {
                isValidPlayer = true;
                break;
            }
        }
        assertTrue(isValidPlayer);
    }

    function testRevealWinnerEmitsEvent() public {
        _buyTickets(MIN_PLAYERS);
        vm.warp(block.timestamp + DURATION + 1);
        lottery.draw();

        vm.roll(block.number + 2);

        // We don't know who the winner will be, but we can check event is emitted
        vm.expectEmit(false, false, false, false);
        emit WinnerRevealed(address(0), 0);

        lottery.revealWinner();
    }

    function testRevealWinnerRevertsIfNotDrawingState() public {
        _buyTickets(MIN_PLAYERS);

        vm.expectRevert(SimpleLottery.NotInDrawingState.selector);
        lottery.revealWinner();
    }

    function testRevealWinnerRevertsIfSameBlockAsDraw() public {
        _buyTickets(MIN_PLAYERS);
        vm.warp(block.timestamp + DURATION + 1);
        lottery.draw();

        // Same block
        vm.expectRevert(SimpleLottery.TooEarlyToReveal.selector);
        lottery.revealWinner();
    }

    function testRevealWinnerRevertsIfNextBlockAfterDraw() public {
        _buyTickets(MIN_PLAYERS);
        vm.warp(block.timestamp + DURATION + 1);
        lottery.draw();

        // Only 1 block ahead
        vm.roll(block.number + 1);

        vm.expectRevert(SimpleLottery.TooEarlyToReveal.selector);
        lottery.revealWinner();
    }

    function testRevealWinnerRevertsIfTooLate() public {
        _buyTickets(MIN_PLAYERS);
        vm.warp(block.timestamp + DURATION + 1);
        lottery.draw();

        // More than 257 blocks ahead
        vm.roll(block.number + 258);

        vm.expectRevert(SimpleLottery.TooLateToReveal.selector);
        lottery.revealWinner();
    }

    function testRevealWinnerAtMinimumBlockGap() public {
        _buyTickets(MIN_PLAYERS);
        vm.warp(block.timestamp + DURATION + 1);
        lottery.draw();

        // Exactly 2 blocks ahead (minimum valid)
        vm.roll(block.number + 2);

        lottery.revealWinner();
        assertEq(uint256(lottery.s_state()), uint256(SimpleLottery.State.Completed));
    }

    function testRevealWinnerAtMaximumBlockLimit() public {
        _buyTickets(MIN_PLAYERS);
        vm.warp(block.timestamp + DURATION + 1);
        lottery.draw();

        // Exactly at 257 blocks (s_drawBlock + 257)
        vm.roll(block.number + 257);

        lottery.revealWinner();
        assertEq(uint256(lottery.s_state()), uint256(SimpleLottery.State.Completed));
    }

    /*//////////////////////////////////////////////////////////////
                        PRIZE CLAIM TESTS
    //////////////////////////////////////////////////////////////*/

    function testClaimPrizeSucceeds() public {
        _buyTickets(MIN_PLAYERS);
        vm.warp(block.timestamp + DURATION + 1);
        lottery.draw();
        vm.roll(block.number + 2);
        lottery.revealWinner();

        address winner = lottery.s_winner();
        uint256 prize = lottery.getPrizePool();
        uint256 balanceBefore = winner.balance;

        vm.prank(winner);
        lottery.claimPrize();

        assertEq(winner.balance, balanceBefore + prize);
        assertTrue(lottery.s_prizeClaimed());
        assertEq(lottery.getPrizePool(), 0);
    }

    function testClaimPrizeEmitsEvent() public {
        _buyTickets(MIN_PLAYERS);
        vm.warp(block.timestamp + DURATION + 1);
        lottery.draw();
        vm.roll(block.number + 2);
        lottery.revealWinner();

        address winner = lottery.s_winner();
        uint256 prize = lottery.getPrizePool();

        vm.expectEmit(true, false, false, true);
        emit PrizeClaimed(winner, prize);

        vm.prank(winner);
        lottery.claimPrize();
    }

    function testClaimPrizeRevertsIfNotWinner() public {
        _buyTickets(MIN_PLAYERS);
        vm.warp(block.timestamp + DURATION + 1);
        lottery.draw();
        vm.roll(block.number + 2);
        lottery.revealWinner();

        address winner = lottery.s_winner();
        address notWinner = winner == alice ? bob : alice;

        vm.prank(notWinner);
        vm.expectRevert(SimpleLottery.NotWinner.selector);
        lottery.claimPrize();
    }

    function testClaimPrizeRevertsIfAlreadyClaimed() public {
        _buyTickets(MIN_PLAYERS);
        vm.warp(block.timestamp + DURATION + 1);
        lottery.draw();
        vm.roll(block.number + 2);
        lottery.revealWinner();

        address winner = lottery.s_winner();

        vm.prank(winner);
        lottery.claimPrize();

        vm.prank(winner);
        vm.expectRevert(SimpleLottery.PrizeAlreadyClaimed.selector);
        lottery.claimPrize();
    }

    function testClaimPrizeRevertsIfNotCompletedState() public {
        _buyTickets(MIN_PLAYERS);
        vm.warp(block.timestamp + DURATION + 1);
        lottery.draw();

        // Still in Drawing state
        vm.prank(alice);
        vm.expectRevert(SimpleLottery.NotInCompletedState.selector);
        lottery.claimPrize();
    }

    /*//////////////////////////////////////////////////////////////
                        CANCELLATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testCancelSucceeds() public {
        _buyTickets(MIN_PLAYERS - 1);
        vm.warp(block.timestamp + DURATION + 1);

        lottery.cancel();

        assertEq(uint256(lottery.s_state()), uint256(SimpleLottery.State.Cancelled));
    }

    function testCancelEmitsEvent() public {
        _buyTickets(MIN_PLAYERS - 1);
        vm.warp(block.timestamp + DURATION + 1);

        vm.expectEmit(false, false, false, false);
        emit LotteryCancelled();

        lottery.cancel();
    }

    function testCancelCanBeCalledByAnyone() public {
        _buyTickets(MIN_PLAYERS - 1);
        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(outsider);
        lottery.cancel();

        assertEq(uint256(lottery.s_state()), uint256(SimpleLottery.State.Cancelled));
    }

    function testCancelRevertsIfDeadlineNotReached() public {
        _buyTickets(MIN_PLAYERS - 1);

        vm.expectRevert(SimpleLottery.DeadlineNotReached.selector);
        lottery.cancel();
    }

    function testCancelRevertsIfMinPlayersReached() public {
        _buyTickets(MIN_PLAYERS);
        vm.warp(block.timestamp + DURATION + 1);

        vm.expectRevert(SimpleLottery.MinPlayersReached.selector);
        lottery.cancel();
    }

    function testCancelRevertsIfNotOpenState() public {
        _buyTickets(MIN_PLAYERS);
        vm.warp(block.timestamp + DURATION + 1);
        lottery.draw();

        vm.expectRevert(SimpleLottery.LotteryNotOpen.selector);
        lottery.cancel();
    }

    /*//////////////////////////////////////////////////////////////
                            REFUND TESTS
    //////////////////////////////////////////////////////////////*/

    function testRefundSucceeds() public {
        vm.prank(alice);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.warp(block.timestamp + DURATION + 1);
        lottery.cancel();

        uint256 balanceBefore = alice.balance;

        vm.prank(alice);
        lottery.refund();

        assertEq(alice.balance, balanceBefore + TICKET_PRICE);
        assertEq(lottery.getContribution(alice), 0);
    }

    function testRefundMultipleTickets() public {
        // Create lottery with higher minPlayers so 3 tickets won't trigger MinPlayersReached
        uint256 deadline = block.timestamp + DURATION;
        SimpleLottery lotteryHighMin = new SimpleLottery(5, deadline, TICKET_PRICE, MAX_PLAYERS);

        vm.startPrank(alice);
        lotteryHighMin.buyTicket{value: TICKET_PRICE}();
        lotteryHighMin.buyTicket{value: TICKET_PRICE}();
        lotteryHighMin.buyTicket{value: TICKET_PRICE}();
        vm.stopPrank();

        vm.warp(block.timestamp + DURATION + 1);
        lotteryHighMin.cancel();

        uint256 balanceBefore = alice.balance;

        vm.prank(alice);
        lotteryHighMin.refund();

        assertEq(alice.balance, balanceBefore + TICKET_PRICE * 3);
    }

    function testRefundEmitsEvent() public {
        vm.prank(alice);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.warp(block.timestamp + DURATION + 1);
        lottery.cancel();

        vm.expectEmit(true, false, false, true);
        emit RefundClaimed(alice, TICKET_PRICE);

        vm.prank(alice);
        lottery.refund();
    }

    function testRefundRevertsIfNotCancelled() public {
        vm.prank(alice);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(alice);
        vm.expectRevert(SimpleLottery.NotCancelled.selector);
        lottery.refund();
    }

    function testRefundRevertsIfNoContribution() public {
        _buyTickets(MIN_PLAYERS - 1);
        vm.warp(block.timestamp + DURATION + 1);
        lottery.cancel();

        vm.prank(outsider);
        vm.expectRevert(SimpleLottery.NoContribution.selector);
        lottery.refund();
    }

    function testRefundRevertsIfAlreadyRefunded() public {
        vm.prank(alice);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.warp(block.timestamp + DURATION + 1);
        lottery.cancel();

        vm.prank(alice);
        lottery.refund();

        vm.prank(alice);
        vm.expectRevert(SimpleLottery.NoContribution.selector);
        lottery.refund();
    }

    function testMultiplePlayersCanRefund() public {
        vm.prank(alice);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(bob);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.warp(block.timestamp + DURATION + 1);
        lottery.cancel();

        uint256 aliceBalanceBefore = alice.balance;
        uint256 bobBalanceBefore = bob.balance;

        vm.prank(alice);
        lottery.refund();

        vm.prank(bob);
        lottery.refund();

        assertEq(alice.balance, aliceBalanceBefore + TICKET_PRICE);
        assertEq(bob.balance, bobBalanceBefore + TICKET_PRICE);
    }

    /*//////////////////////////////////////////////////////////////
                            EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function testExactlyMinPlayers() public {
        _buyTickets(MIN_PLAYERS);
        vm.warp(block.timestamp + DURATION + 1);

        lottery.draw();
        assertEq(uint256(lottery.s_state()), uint256(SimpleLottery.State.Drawing));
    }

    function testExactlyMaxPlayers() public {
        _buyTickets(MAX_PLAYERS);

        assertEq(lottery.getTicketCount(), MAX_PLAYERS);
    }

    function testSinglePlayerBuysAllTickets() public {
        vm.startPrank(alice);
        for (uint256 i = 0; i < MAX_PLAYERS; i++) {
            lottery.buyTicket{value: TICKET_PRICE}();
        }
        vm.stopPrank();

        assertEq(lottery.getTicketCount(), MAX_PLAYERS);
        assertEq(lottery.getContribution(alice), TICKET_PRICE * MAX_PLAYERS);

        vm.warp(block.timestamp + DURATION + 1);
        lottery.draw();
        vm.roll(block.number + 2);
        lottery.revealWinner();

        // Alice must be the winner
        assertEq(lottery.s_winner(), alice);
    }

    function testRandomnessSelectsCorrectly() public {
        // Alice buys 1, Bob buys 1, Charlie buys 1
        vm.prank(alice);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(bob);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(charlie);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.warp(block.timestamp + DURATION + 1);
        lottery.draw();
        vm.roll(block.number + 2);
        lottery.revealWinner();

        address winner = lottery.s_winner();
        assertTrue(winner == alice || winner == bob || winner == charlie);
    }

    function testPlayerWithMoreTicketsHasHigherChance() public {
        // This test just verifies the mechanism works correctly
        // Alice buys 8 tickets, Bob buys 1, Charlie buys 1
        vm.startPrank(alice);
        for (uint256 i = 0; i < 8; i++) {
            lottery.buyTicket{value: TICKET_PRICE}();
        }
        vm.stopPrank();

        vm.prank(bob);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(charlie);
        lottery.buyTicket{value: TICKET_PRICE}();

        assertEq(lottery.getTicketCount(), 10);

        // Verify array structure
        for (uint256 i = 0; i < 8; i++) {
            assertEq(lottery.getPlayer(i), alice);
        }
        assertEq(lottery.getPlayer(8), bob);
        assertEq(lottery.getPlayer(9), charlie);
    }

    function testZeroPlayersCannotDraw() public {
        vm.warp(block.timestamp + DURATION + 1);

        vm.expectRevert(SimpleLottery.MinPlayersNotReached.selector);
        lottery.draw();
    }

    function testZeroPlayersCancelSucceeds() public {
        vm.warp(block.timestamp + DURATION + 1);

        lottery.cancel();
        assertEq(uint256(lottery.s_state()), uint256(SimpleLottery.State.Cancelled));
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION SCENARIOS
    //////////////////////////////////////////////////////////////*/

    function testFullHappyPath() public {
        // 1. Deploy (done in setUp)

        // 2. Buy tickets
        vm.prank(alice);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(bob);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(charlie);
        lottery.buyTicket{value: TICKET_PRICE}();

        assertEq(lottery.getTicketCount(), 3);
        assertEq(lottery.getPrizePool(), TICKET_PRICE * 3);

        // 3. Wait for deadline
        vm.warp(block.timestamp + DURATION + 1);

        // 4. Draw
        lottery.draw();
        assertEq(uint256(lottery.s_state()), uint256(SimpleLottery.State.Drawing));

        // 5. Reveal winner
        vm.roll(block.number + 2);
        lottery.revealWinner();
        assertEq(uint256(lottery.s_state()), uint256(SimpleLottery.State.Completed));

        address winner = lottery.s_winner();
        assertTrue(winner == alice || winner == bob || winner == charlie);

        // 6. Claim prize
        uint256 winnerBalanceBefore = winner.balance;
        uint256 prize = lottery.getPrizePool();

        vm.prank(winner);
        lottery.claimPrize();

        assertEq(winner.balance, winnerBalanceBefore + prize);
        assertEq(lottery.getPrizePool(), 0);
        assertTrue(lottery.s_prizeClaimed());
    }

    function testCancellationPath() public {
        // 1. Deploy (done in setUp)

        // 2. Buy tickets (not enough)
        vm.prank(alice);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(bob);
        lottery.buyTicket{value: TICKET_PRICE}();

        assertEq(lottery.getTicketCount(), 2);

        // 3. Wait for deadline
        vm.warp(block.timestamp + DURATION + 1);

        // 4. Cancel
        lottery.cancel();
        assertEq(uint256(lottery.s_state()), uint256(SimpleLottery.State.Cancelled));

        // 5. Refund
        uint256 aliceBalanceBefore = alice.balance;
        uint256 bobBalanceBefore = bob.balance;

        vm.prank(alice);
        lottery.refund();

        vm.prank(bob);
        lottery.refund();

        assertEq(alice.balance, aliceBalanceBefore + TICKET_PRICE);
        assertEq(bob.balance, bobBalanceBefore + TICKET_PRICE);
        assertEq(lottery.getPrizePool(), 0);
    }

    function testMultipleRoundsOfPurchases() public {
        // Round 1
        vm.prank(alice);
        lottery.buyTicket{value: TICKET_PRICE}();

        // Some time passes
        vm.warp(block.timestamp + 1 hours);

        // Round 2
        vm.prank(bob);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(alice);
        lottery.buyTicket{value: TICKET_PRICE}();

        // More time passes
        vm.warp(block.timestamp + 1 hours);

        // Round 3
        vm.prank(charlie);
        lottery.buyTicket{value: TICKET_PRICE}();

        assertEq(lottery.getTicketCount(), 4);
        assertEq(lottery.getContribution(alice), TICKET_PRICE * 2);
        assertEq(lottery.getContribution(bob), TICKET_PRICE);
        assertEq(lottery.getContribution(charlie), TICKET_PRICE);
    }

    function testCannotBuyAfterDraw() public {
        _buyTickets(MIN_PLAYERS);
        vm.warp(block.timestamp + DURATION + 1);
        lottery.draw();

        vm.prank(outsider);
        vm.expectRevert(SimpleLottery.LotteryNotOpen.selector);
        lottery.buyTicket{value: TICKET_PRICE}();
    }

    function testCannotCancelAfterDraw() public {
        _buyTickets(MIN_PLAYERS);
        vm.warp(block.timestamp + DURATION + 1);
        lottery.draw();

        vm.expectRevert(SimpleLottery.LotteryNotOpen.selector);
        lottery.cancel();
    }

    function testCannotRefundAfterCompletion() public {
        _buyTickets(MIN_PLAYERS);
        vm.warp(block.timestamp + DURATION + 1);
        lottery.draw();
        vm.roll(block.number + 2);
        lottery.revealWinner();

        vm.prank(alice);
        vm.expectRevert(SimpleLottery.NotCancelled.selector);
        lottery.refund();
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetTicketCount() public {
        assertEq(lottery.getTicketCount(), 0);

        vm.prank(alice);
        lottery.buyTicket{value: TICKET_PRICE}();

        assertEq(lottery.getTicketCount(), 1);
    }

    function testGetPlayer() public {
        vm.prank(alice);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(bob);
        lottery.buyTicket{value: TICKET_PRICE}();

        assertEq(lottery.getPlayer(0), alice);
        assertEq(lottery.getPlayer(1), bob);
    }

    function testGetContribution() public {
        assertEq(lottery.getContribution(alice), 0);

        vm.prank(alice);
        lottery.buyTicket{value: TICKET_PRICE}();

        assertEq(lottery.getContribution(alice), TICKET_PRICE);
    }

    function testGetPrizePool() public {
        assertEq(lottery.getPrizePool(), 0);

        vm.prank(alice);
        lottery.buyTicket{value: TICKET_PRICE}();

        assertEq(lottery.getPrizePool(), TICKET_PRICE);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    function _buyTickets(uint256 count) internal {
        address[3] memory players = [alice, bob, charlie];

        for (uint256 i = 0; i < count; i++) {
            address player = players[i % 3];
            vm.prank(player);
            lottery.buyTicket{value: TICKET_PRICE}();
        }
    }
}
