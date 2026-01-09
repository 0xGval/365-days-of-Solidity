// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

/**
 * @title CommitRevealGame
 * @notice Minimal 2-player commit-reveal game with deadlines and events
 * @dev Strict flow: Commit -> Reveal -> Resolved. One game per contract.
 */
contract CommitRevealGame {
    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/

    enum State {
        Uninitialized,
        Commit,
        Reveal,
        Resolved
    }

    struct GameRound {
        address playerA;
        address playerB;
        bytes32 playerACommit;
        bytes32 playerBCommit;
        bytes32 playerAChoice;
        bytes32 playerBChoice;
        bool playerARevealed;
        bool playerBRevealed;
        uint256 commitDeadline;
        uint256 revealDeadline;
        address winner;
        State state;
    }

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    GameRound public gameRound;

    /// @notice Maximum time allowed for playerB to commit.
    uint256 public immutable commitDuration;

    /// @notice Maximum time allowed for both players to reveal.
    uint256 public immutable revealDuration;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidPlayer();
    error InvalidState();
    error InvalidCommit();
    error InvalidReveal();
    error AlreadyRevealed();
    error AlreadyCommitted();
    error MissingCommit();
    error CommitPhaseExpired(uint256 deadline);
    error RevealPhaseExpired(uint256 deadline);

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyUninitialized() {
        if (gameRound.state != State.Uninitialized) revert InvalidState();
        _;
    }

    modifier onlyCommit() {
        if (gameRound.state != State.Commit) revert InvalidState();
        _;
    }

    modifier onlyReveal() {
        if (gameRound.state != State.Reveal) revert InvalidState();
        _;
    }

    modifier onlyPlayerB() {
        if (msg.sender != gameRound.playerB) revert InvalidPlayer();
        _;
    }

    modifier onlyPlayer() {
        if (
            msg.sender != gameRound.playerA && msg.sender != gameRound.playerB
        ) {
            revert InvalidPlayer();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(uint256 _commitDuration, uint256 _revealDuration) {
        // puoi anche hardcodare se vuoi, ma così è più pulito
        commitDuration = _commitDuration;
        revealDuration = _revealDuration;
    }

    /*//////////////////////////////////////////////////////////////
                            GAME CREATION
    //////////////////////////////////////////////////////////////*/

    function createGameRound(
        address _playerB,
        bytes32 _playerACommit
    ) external onlyUninitialized {
        if (_playerB == address(0)) revert InvalidPlayer();
        if (_playerB == msg.sender) revert InvalidPlayer();
        if (_playerACommit == bytes32(0)) revert InvalidCommit();

        uint256 cd = block.timestamp + commitDuration;

        gameRound = GameRound({
            playerA: msg.sender,
            playerB: _playerB,
            playerACommit: _playerACommit,
            playerBCommit: bytes32(0),
            playerAChoice: bytes32(0),
            playerBChoice: bytes32(0),
            playerARevealed: false,
            playerBRevealed: false,
            commitDeadline: cd,
            revealDeadline: 0,
            winner: address(0),
            state: State.Commit
        });

        emit GameCreated(msg.sender, _playerB, cd);
        emit Committed(msg.sender); // A ha già “committato” passando l’hash in create
    }

    /*//////////////////////////////////////////////////////////////
                                COMMIT
    //////////////////////////////////////////////////////////////*/

    function commitChoice(
        bytes32 _playerBCommit
    ) external onlyPlayerB onlyCommit {
        if (block.timestamp > gameRound.commitDeadline) {
            revert CommitPhaseExpired(gameRound.commitDeadline);
        }
        if (_playerBCommit == bytes32(0)) revert InvalidCommit();
        if (gameRound.playerBCommit != bytes32(0)) revert AlreadyCommitted();

        gameRound.playerBCommit = _playerBCommit;

        // entra in reveal phase e fissa la deadline di reveal
        gameRound.state = State.Reveal;
        gameRound.revealDeadline = block.timestamp + revealDuration;

        emit Committed(msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                                REVEAL
    //////////////////////////////////////////////////////////////*/

    function reveal(
        bytes32 choice,
        bytes32 salt
    ) external onlyPlayer onlyReveal {
        if (block.timestamp > gameRound.revealDeadline) {
            revert RevealPhaseExpired(gameRound.revealDeadline);
        }

        // non si può rivelare se B non ha mai committato
        if (gameRound.playerBCommit == bytes32(0)) revert MissingCommit();

        bytes32 storedCommit;

        if (msg.sender == gameRound.playerA) {
            if (gameRound.playerARevealed) revert AlreadyRevealed();
            storedCommit = gameRound.playerACommit;
        } else {
            if (gameRound.playerBRevealed) revert AlreadyRevealed();
            storedCommit = gameRound.playerBCommit;
        }

        if (keccak256(abi.encodePacked(choice, salt)) != storedCommit) {
            revert InvalidReveal();
        }

        // effects
        if (msg.sender == gameRound.playerA) {
            gameRound.playerARevealed = true;
            gameRound.playerAChoice = choice;
        } else {
            gameRound.playerBRevealed = true;
            gameRound.playerBChoice = choice;
        }

        emit Revealed(msg.sender, choice);

        // auto-resolve se entrambi hanno rivelato
        if (gameRound.playerARevealed && gameRound.playerBRevealed) {
            _resolveInternal();
        }
    }

    /*//////////////////////////////////////////////////////////////
                                RESOLVE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Finalizza dopo timeout, oppure se vuoi una "manual finalize".
     * @dev Utile per win-by-default se qualcuno non rivela in tempo.
     */
    function resolveAfterTimeout() external {
        if (gameRound.state == State.Commit) {
            // se B non committa entro commitDeadline → A vince by default
            if (block.timestamp <= gameRound.commitDeadline)
                revert InvalidState();
            gameRound.winner = gameRound.playerA;
            gameRound.state = State.Resolved;

            emit GameResolved(
                gameRound.winner,
                gameRound.playerAChoice,
                gameRound.playerBChoice
            );
            return;
        }

        if (gameRound.state == State.Reveal) {
            if (block.timestamp <= gameRound.revealDeadline)
                revert InvalidState();

            // reveal scaduta:
            // - se uno solo ha rivelato → quello vince by default
            // - se nessuno → winner = address(0)
            if (gameRound.playerARevealed && !gameRound.playerBRevealed) {
                gameRound.winner = gameRound.playerA;
            } else if (
                !gameRound.playerARevealed && gameRound.playerBRevealed
            ) {
                gameRound.winner = gameRound.playerB;
            } else {
                gameRound.winner = address(0);
            }

            gameRound.state = State.Resolved;

            emit GameResolved(
                gameRound.winner,
                gameRound.playerAChoice,
                gameRound.playerBChoice
            );
            return;
        }

        revert InvalidState();
    }

    function _resolveInternal() internal {
        // regola semplice: choice numericamente più alta vince
        uint256 a = uint256(gameRound.playerAChoice);
        uint256 b = uint256(gameRound.playerBChoice);

        address winner;
        if (a > b) winner = gameRound.playerA;
        else if (b > a) winner = gameRound.playerB;
        else winner = address(0);

        gameRound.winner = winner;
        gameRound.state = State.Resolved;

        emit GameResolved(
            winner,
            gameRound.playerAChoice,
            gameRound.playerBChoice
        );
    }
}
