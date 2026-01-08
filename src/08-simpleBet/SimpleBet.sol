// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

/**
 * @title SimpleBet
 * @notice Minimal betting contract that allows two players to lock equal amounts
 *         of ETH into a 1 vs 1 bet.
 *
 *         An arbitrator, agreed by both players at creation time, resolves
 *         the bet by selecting a winner.
 *
 * @dev Implements a strict finite state machine with irreversible transitions.
 *      Funds can move only once and only in a valid state.
 */
contract SimpleBet {
    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Tracks the lifecycle of a bet.
    enum State {
        Uninitialized,
        Created,
        Accepted,
        Funded,
        Resolved,
        Cancelled
    }

    /// @notice Stores all bet-related data.
    struct Bet {
        address playerA;
        bool playerAFunded;
        address playerB;
        bool playerBFunded;
        address arbitrator;
        uint256 stakePerPlayer;
        State state;
    }

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Single bet instance.
    /// @dev Only one bet can exist per contract.
    Bet public bet;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a bet is created.
    event BetCreated(
        address indexed playerA,
        address indexed playerB,
        address indexed arbitrator,
        uint256 stakePerPlayer
    );

    /// @notice Emitted when playerB accepts the bet.
    event BetAccepted(address indexed playerB);

    /// @notice Emitted when a player funds the bet.
    event BetFunded(address indexed player, uint256 amount);

    /// @notice Emitted when the bet is resolved by the arbitrator.
    event BetResolved(address indexed winner, uint256 amount);

    /// @notice Emitted when the bet is cancelled.
    event BetCancelled();

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidBetValue();
    error NotPlayerA();
    error NotPlayerB();
    error InvalidState();
    error InvalidPlayer();
    error InvalidArbitrator();
    error ValueMustMatchStakePerPlayer();
    error NotBetPlayer();
    error PlayerAlreadyFunded();
    error NotArbitrator();
    error WinnerMustBePlayer();
    error PaymentFailed();

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyPlayerA() {
        if (msg.sender != bet.playerA) revert NotPlayerA();
        _;
    }

    modifier onlyPlayerB() {
        if (msg.sender != bet.playerB) revert NotPlayerB();
        _;
    }

    modifier onlyUninitialized() {
        if (bet.state != State.Uninitialized) revert InvalidState();
        _;
    }

    modifier onlyAcceptedBet() {
        if (bet.state != State.Accepted) revert InvalidState();
        _;
    }

    modifier onlyFundedBet() {
        if (bet.state != State.Funded) revert InvalidState();
        _;
    }

    modifier onlyBetParties() {
        if (msg.sender != bet.playerA && msg.sender != bet.playerB)
            revert NotBetPlayer();
        _;
    }

    modifier onlyArbitrator() {
        if (msg.sender != bet.arbitrator) revert NotArbitrator();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            BET CREATION
    //////////////////////////////////////////////////////////////*/

    function createBet(
        address _playerB,
        address _arbitrator,
        uint256 _stakePerPlayer
    ) public onlyUninitialized {
        if (_playerB == address(0)) revert InvalidPlayer();
        if (_playerB == msg.sender) revert InvalidPlayer();
        if (_arbitrator == address(0)) revert InvalidArbitrator();
        if (_arbitrator == msg.sender) revert InvalidArbitrator();
        if (_arbitrator == _playerB) revert InvalidArbitrator();
        if (_stakePerPlayer == 0) revert InvalidBetValue();

        bet = Bet({
            playerA: msg.sender,
            playerAFunded: false,
            playerB: _playerB,
            playerBFunded: false,
            arbitrator: _arbitrator,
            stakePerPlayer: _stakePerPlayer,
            state: State.Created
        });

        emit BetCreated(msg.sender, _playerB, _arbitrator, _stakePerPlayer);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCEPTANCE
    //////////////////////////////////////////////////////////////*/

    function acceptBet() public onlyPlayerB {
        if (bet.state != State.Created) revert InvalidState();

        bet.state = State.Accepted;

        emit BetAccepted(msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                            FUNDING
    //////////////////////////////////////////////////////////////*/

    function fundBet() public payable onlyAcceptedBet onlyBetParties {
        if (msg.value != bet.stakePerPlayer)
            revert ValueMustMatchStakePerPlayer();

        if (msg.sender == bet.playerA) {
            if (bet.playerAFunded) revert PlayerAlreadyFunded();
            bet.playerAFunded = true;
        } else {
            if (bet.playerBFunded) revert PlayerAlreadyFunded();
            bet.playerBFunded = true;
        }

        emit BetFunded(msg.sender, msg.value);

        if (bet.playerAFunded && bet.playerBFunded) {
            bet.state = State.Funded;
        }
    }

    /*//////////////////////////////////////////////////////////////
                            RESOLUTION
    //////////////////////////////////////////////////////////////*/

    function resolveBet(address _winner) public onlyArbitrator onlyFundedBet {
        if (_winner != bet.playerA && _winner != bet.playerB)
            revert WinnerMustBePlayer();

        uint256 betValue = bet.stakePerPlayer * 2;

        bet.state = State.Resolved;

        emit BetResolved(_winner, betValue);

        (bool success, ) = payable(_winner).call{value: betValue}("");
        if (!success) revert PaymentFailed();
    }

    /*//////////////////////////////////////////////////////////////
                            CANCELLATION
    //////////////////////////////////////////////////////////////*/

    function cancelBet() public onlyPlayerA {
        if (bet.state != State.Created && bet.state != State.Accepted)
            revert InvalidState();

        bet.state = State.Cancelled;

        if (bet.playerAFunded) {
            bet.playerAFunded = false;

            (bool success, ) = payable(bet.playerA).call{
                value: bet.stakePerPlayer
            }("");
            if (!success) revert PaymentFailed();
        } else if (bet.playerBFunded) {
            bet.playerBFunded = false;

            (bool success, ) = payable(bet.playerB).call{
                value: bet.stakePerPlayer
            }("");
            if (!success) revert PaymentFailed();
        }

        emit BetCancelled();
    }
}
