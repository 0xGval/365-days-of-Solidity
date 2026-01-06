// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

/**
 * @title SimpleEscrow
 * @notice Minimal escrow contract that locks ETH between a payer and a payee
 *         until the payer explicitly releases or cancels the escrow.
 * @dev Implements a strict finite state machine with irreversible transitions.
 */
contract SimpleEscrow {
    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Lifecycle states of the escrow.
    enum State {
        Uninitialized,
        Created,
        Funded,
        Released,
        Cancelled
    }

    /// @notice Escrow configuration and state.
    struct Escrow {
        address payer;
        address payee;
        uint256 amount;
        State state;
    }

    /// @notice Single escrow instance managed by the contract.
    Escrow public escrow;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error EscrowMustBeUninitialized();
    error EscrowMustBeCreated();
    error EscrowMustBeFunded();

    error OnlyPayerCanFundEscrow();
    error OnlyPayerCanReleaseEscrow();
    error OnlyPayerCanCancelEscrow();

    error PayeeMustNotBeZeroAddress();
    error PayeeMustNotEqualToPayer();
    error ValueMustBeAboveZero();

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Allows execution only if escrow is uninitialized.
    modifier onlyUninitialized() {
        if (escrow.state != State.Uninitialized)
            revert EscrowMustBeUninitialized();
        _;
    }

    /// @notice Allows execution only if escrow is created.
    modifier onlyCreated() {
        if (escrow.state != State.Created) revert EscrowMustBeCreated();
        _;
    }

    /// @notice Allows execution only if escrow is funded.
    modifier onlyFunded() {
        if (escrow.state != State.Funded) revert EscrowMustBeFunded();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the escrow is created.
    event Created(address indexed payer, address indexed payee);

    /// @notice Emitted when the escrow is funded.
    event Funded(address indexed payer, uint256 amount);

    /// @notice Emitted when the escrow is released to the payee.
    event Released(
        address indexed payer,
        address indexed payee,
        uint256 amount
    );

    /// @notice Emitted when the escrow is cancelled and refunded.
    event Cancelled(address indexed payer, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                CREATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a new escrow with a fixed payer and payee.
     * @dev Can only be called once, when the escrow is uninitialized.
     */
    function createEscrow(address payee) external onlyUninitialized {
        if (payee == address(0)) revert PayeeMustNotBeZeroAddress();
        if (payee == msg.sender) revert PayeeMustNotEqualToPayer();

        escrow = Escrow({
            payer: msg.sender,
            payee: payee,
            amount: 0,
            state: State.Created
        });

        emit Created(msg.sender, payee);
    }

    /*//////////////////////////////////////////////////////////////
                                FUNDING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Funds the escrow with ETH.
     * @dev Callable only by the payer and only once.
     */
    function fundEscrow() external payable onlyCreated {
        if (escrow.payer != msg.sender) revert OnlyPayerCanFundEscrow();
        if (msg.value == 0) revert ValueMustBeAboveZero();

        escrow.amount = msg.value;
        escrow.state = State.Funded;

        emit Funded(msg.sender, msg.value);
    }

    /*//////////////////////////////////////////////////////////////
                                RELEASE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Releases the escrowed ETH to the payee.
     * @dev Callable only by the payer when funded.
     */
    function releaseEscrow() external onlyFunded {
        if (escrow.payer != msg.sender) revert OnlyPayerCanReleaseEscrow();

        uint256 amount = escrow.amount;

        escrow.amount = 0;
        escrow.state = State.Released;

        (bool success, ) = payable(escrow.payee).call{value: amount}("");
        require(success, "ETH transfer failed");

        emit Released(msg.sender, escrow.payee, amount);
    }

    /*//////////////////////////////////////////////////////////////
                                CANCELLATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Cancels the escrow and refunds the payer.
     * @dev Callable only by the payer when funded.
     */
    function cancelEscrow() external onlyFunded {
        if (escrow.payer != msg.sender) revert OnlyPayerCanCancelEscrow();

        uint256 amount = escrow.amount;

        escrow.amount = 0;
        escrow.state = State.Cancelled;

        (bool success, ) = payable(escrow.payer).call{value: amount}("");
        require(success, "ETH transfer failed");

        emit Cancelled(msg.sender, amount);
    }
}
