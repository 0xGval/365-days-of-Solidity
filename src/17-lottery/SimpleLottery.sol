// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

/// @title SimpleLottery
/// @notice A decentralized lottery with pseudo-random winner selection using blockhash.
/// @dev
/// - Two-step draw process to mitigate miner manipulation
/// - Players buy tickets at fixed price, can buy multiple tickets
/// - Winner selected using blockhash(drawBlock + 1) as random seed
/// - Pull-based prize claim and refund patterns
/// - CEI pattern used for all ETH transfers

contract SimpleLottery {
    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Lottery lifecycle states.
    enum State {
        Open,       // Accepting ticket purchases
        Drawing,    // Waiting for winner reveal
        Completed,  // Winner selected, prize claimable
        Cancelled   // Not enough players, refunds available
    }

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Deployer address.
    address public immutable i_owner;

    /// @notice Minimum tickets required for lottery to proceed.
    uint256 public immutable i_minPlayers;

    /// @notice Timestamp when ticket sales end.
    uint256 public immutable i_deadline;

    /// @notice Cost of one ticket in wei.
    uint256 public immutable i_ticketPrice;

    /// @notice Maximum tickets allowed (prevents gas issues).
    uint256 public immutable i_maxPlayers;

    /// @notice Array of player addresses (duplicates allowed for multiple tickets).
    address[] private s_players;

    /// @notice Total ETH contributed per player (for refunds).
    mapping(address => uint256) private s_contributions;

    /// @notice Current lottery state.
    State public s_state;

    /// @notice Block number when draw() was called.
    uint256 public s_drawBlock;

    /// @notice Selected winner address.
    address public s_winner;

    /// @notice Whether prize has been claimed.
    bool public s_prizeClaimed;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Reverts when minPlayers is zero or greater than maxPlayers.
    error InvalidPlayersNumber();

    /// @notice Reverts when deadline is in the past.
    error InvalidDeadline();

    /// @notice Reverts when ticket price is zero.
    error InvalidPrice();

    /// @notice Reverts when trying to buy ticket while not in Open state.
    error LotteryNotOpen();

    /// @notice Reverts when sent ETH doesn't match ticket price.
    error IncorrectTicketPrice();

    /// @notice Reverts when lottery is full.
    error MaxPlayersReached();

    /// @notice Reverts when trying to buy after deadline.
    error DeadlinePassed();

    /// @notice Reverts when trying to draw before deadline.
    error DeadlineNotReached();

    /// @notice Reverts when trying to draw without enough players.
    error MinPlayersNotReached();

    /// @notice Reverts when trying to reveal winner while not in Drawing state.
    error NotInDrawingState();

    /// @notice Reverts when trying to reveal in same block or next block as draw.
    error TooEarlyToReveal();

    /// @notice Reverts when more than 256 blocks passed since draw.
    error TooLateToReveal();

    /// @notice Reverts when non-winner tries to claim prize.
    error NotWinner();

    /// @notice Reverts when winner tries to claim twice.
    error PrizeAlreadyClaimed();

    /// @notice Reverts when trying to claim prize while not in Completed state.
    error NotInCompletedState();

    /// @notice Reverts when trying to cancel with enough players.
    error MinPlayersReached();

    /// @notice Reverts when trying to refund while lottery not cancelled.
    error NotCancelled();

    /// @notice Reverts when trying to refund with zero contribution.
    error NoContribution();

    /// @notice Reverts when ETH transfer fails.
    error TransferFailed();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a player buys a ticket.
    /// @param player Address of the player.
    /// @param ticketNumber The ticket index in the players array.
    event TicketPurchased(address indexed player, uint256 ticketNumber);

    /// @notice Emitted when draw() is called.
    /// @param drawBlock Block number recorded for randomness.
    event DrawInitiated(uint256 drawBlock);

    /// @notice Emitted when winner is selected.
    /// @param winner Address of the winner.
    /// @param prize Total prize pool amount.
    event WinnerRevealed(address indexed winner, uint256 prize);

    /// @notice Emitted when winner claims the prize.
    /// @param winner Address of the winner.
    /// @param amount ETH amount claimed.
    event PrizeClaimed(address indexed winner, uint256 amount);

    /// @notice Emitted when lottery is cancelled.
    event LotteryCancelled();

    /// @notice Emitted when a player claims refund.
    /// @param player Address of the player.
    /// @param amount ETH amount refunded.
    event RefundClaimed(address indexed player, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploys a new lottery with fixed parameters.
    /// @dev
    /// - minPlayers must be > 0 and <= maxPlayers
    /// - deadline must be in the future
    /// - ticketPrice must be > 0
    /// @param minPlayers Minimum tickets required.
    /// @param deadline Timestamp when sales end.
    /// @param ticketPrice Cost per ticket in wei.
    /// @param maxPlayers Maximum tickets allowed.
    constructor(
        uint256 minPlayers,
        uint256 deadline,
        uint256 ticketPrice,
        uint256 maxPlayers
    ) {
        if (minPlayers == 0 || minPlayers > maxPlayers)
            revert InvalidPlayersNumber();
        if (deadline <= block.timestamp) revert InvalidDeadline();
        if (ticketPrice == 0) revert InvalidPrice();

        i_owner = msg.sender;
        i_minPlayers = minPlayers;
        i_maxPlayers = maxPlayers;
        i_deadline = deadline;
        i_ticketPrice = ticketPrice;
    }

    /*//////////////////////////////////////////////////////////////
                        TICKET PURCHASE
    //////////////////////////////////////////////////////////////*/

    /// @notice Buys a lottery ticket.
    /// @dev
    /// - Must send exact ticket price
    /// - Can buy multiple tickets (each increases winning chance)
    /// - Player address added to array for each ticket
    /// - Contribution tracked for potential refunds
    function buyTicket() public payable {
        if (s_state != State.Open) revert LotteryNotOpen();
        if (block.timestamp > i_deadline) revert DeadlinePassed();
        if (msg.value != i_ticketPrice) revert IncorrectTicketPrice();
        if (s_players.length >= i_maxPlayers) revert MaxPlayersReached();

        s_players.push(msg.sender);
        s_contributions[msg.sender] += msg.value;

        emit TicketPurchased(msg.sender, s_players.length - 1);
    }

    /*//////////////////////////////////////////////////////////////
                        DRAW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Initiates the draw process.
    /// @dev
    /// - Can only be called after deadline
    /// - Requires minimum players reached
    /// - Records current block for randomness
    /// - Does NOT select winner (two-step process)
    function draw() public {
        if (s_state != State.Open) revert LotteryNotOpen();
        if (block.timestamp < i_deadline) revert DeadlineNotReached();
        if (s_players.length < i_minPlayers) revert MinPlayersNotReached();

        s_drawBlock = block.number;
        s_state = State.Drawing;

        emit DrawInitiated(s_drawBlock);
    }

    /// @notice Reveals the winner using blockhash randomness.
    /// @dev
    /// - Must wait at least 2 blocks after draw (for blockhash availability)
    /// - Must call within 256 blocks (blockhash limitation)
    /// - Uses blockhash(drawBlock + 1) as random seed
    /// - Winner index = seed % players.length
    function revealWinner() public {
        if (s_state != State.Drawing) revert NotInDrawingState();
        if (block.number <= s_drawBlock + 1) revert TooEarlyToReveal();
        if (block.number > s_drawBlock + 257) revert TooLateToReveal();

        uint256 seed = uint256(blockhash(s_drawBlock + 1));
        uint256 winnerIndex = seed % s_players.length;
        s_winner = s_players[winnerIndex];
        s_state = State.Completed;

        emit WinnerRevealed(s_winner, address(this).balance);
    }

    /*//////////////////////////////////////////////////////////////
                        PRIZE CLAIM
    //////////////////////////////////////////////////////////////*/

    /// @notice Allows winner to claim the prize pool.
    /// @dev
    /// - Only winner can call
    /// - Can only claim once
    /// - CEI pattern: state updated before transfer
    function claimPrize() public {
        if (s_state != State.Completed) revert NotInCompletedState();
        if (msg.sender != s_winner) revert NotWinner();
        if (s_prizeClaimed) revert PrizeAlreadyClaimed();

        uint256 prize = address(this).balance;
        s_prizeClaimed = true;

        (bool success, ) = payable(msg.sender).call{value: prize}("");
        if (!success) revert TransferFailed();

        emit PrizeClaimed(msg.sender, prize);
    }

    /*//////////////////////////////////////////////////////////////
                    CANCELLATION & REFUNDS
    //////////////////////////////////////////////////////////////*/

    /// @notice Cancels the lottery if minimum players not reached.
    /// @dev
    /// - Can only cancel after deadline
    /// - Cannot cancel if minPlayers reached
    /// - Enables refunds for all players
    function cancel() public {
        if (s_state != State.Open) revert LotteryNotOpen();
        if (block.timestamp < i_deadline) revert DeadlineNotReached();
        if (s_players.length >= i_minPlayers) revert MinPlayersReached();

        s_state = State.Cancelled;

        emit LotteryCancelled();
    }

    /// @notice Allows players to claim refund after cancellation.
    /// @dev
    /// - Only available when lottery is cancelled
    /// - Returns full contribution (all tickets purchased)
    /// - CEI pattern: contribution zeroed before transfer
    function refund() public {
        if (s_state != State.Cancelled) revert NotCancelled();

        uint256 amount = s_contributions[msg.sender];
        if (amount == 0) revert NoContribution();

        s_contributions[msg.sender] = 0;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) revert TransferFailed();

        emit RefundClaimed(msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns total number of tickets sold.
    /// @return Number of tickets.
    function getTicketCount() external view returns (uint256) {
        return s_players.length;
    }

    /// @notice Returns player address at specific ticket index.
    /// @param index Ticket index.
    /// @return Player address.
    function getPlayer(uint256 index) external view returns (address) {
        return s_players[index];
    }

    /// @notice Returns total contribution for an address.
    /// @param player Address to check.
    /// @return ETH contributed.
    function getContribution(address player) external view returns (uint256) {
        return s_contributions[player];
    }

    /// @notice Returns current prize pool.
    /// @return Contract balance.
    function getPrizePool() external view returns (uint256) {
        return address(this).balance;
    }
}
