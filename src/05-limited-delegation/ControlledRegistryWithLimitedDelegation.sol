// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

/*
Purpose:
Extends the delegation model by introducing limited-use delegation.

A registered user may authorize a single delegate to act on their behalf
for a fixed number of actions. Each delegated action consumes one use.

Once the usage limit is reached, the delegation becomes inactive.
*/

contract ControlledRegistryWithLimitedDelegation {
    /// @notice Address with exclusive permission to register users.
    address public immutable i_owner;

    /// @notice Tracks whether an address is registered.
    mapping(address => bool) public isRegistered;

    /// @notice Delegation state for a user: who can act and how many times.
    struct Delegation {
        address delegate;
        uint256 remainingUses;
    }

    /// @notice Per-user delegation configuration.
    mapping(address => Delegation) public userToDelegation;

    /// @notice Per-user stored value.
    mapping(address => uint256) public userToValue;

    /// @notice Reverts when a non-owner calls an owner-only function.
    error NotOwner();

    /// @notice Reverts when registering an address that is already registered.
    error UserAlreadyRegistered();

    /// @notice Reverts when an unregistered address attempts a user-only action.
    error UserNotRegistered();

    /// @notice Reverts when the provided user address is invalid.
    error InvalidUserAddress();

    /// @notice Reverts when the provided delegate address is invalid.
    error InvalidDelegateAddress();

    /// @notice Reverts when attempting to self-delegate.
    error DelegateMustDifferFromUser();

    /// @notice Reverts when assigning a delegation with zero allowance.
    error InvalidAllowance();

    /// @notice Reverts when trying to revoke but no delegation is active.
    error NoDelegationActive();

    /// @notice Reverts when the caller is not the authorized delegate for a user.
    error NotAuthorizedDelegate();

    /// @notice Reverts when a delegate has no remaining uses.
    error NoRemainingUses();

    /// @notice Reverts when attempting to set a value equal to the current one.
    error NewValueMustDifferFromOldValue();

    /// @notice Emitted when a delegate is assigned to a user.
    event DelegateAssigned(
        address indexed user,
        address indexed delegate,
        uint256 allowance
    );

    /// @notice Emitted when a delegate is revoked (explicitly or via overwrite).
    event DelegateRevoked(address indexed user, address indexed delegate);

    /// @notice Emitted when a delegate updates a user's value.
    event DelegatedAction(
        address indexed user,
        address indexed delegate,
        uint256 newValue,
        uint256 remainingUses
    );

    constructor() {
        i_owner = msg.sender;
    }

    /// @notice Restricts execution to the contract owner.
    modifier onlyOwner() {
        if (msg.sender != i_owner) revert NotOwner();
        _;
    }

    /// @notice Restricts execution to registered users.
    modifier onlyRegisteredUser() {
        if (!isRegistered[msg.sender]) revert UserNotRegistered();
        _;
    }

    /// @notice Registers a new user.
    /// @dev Callable only by the owner.
    function registerUser(address user) external onlyOwner {
        if (user == address(0)) revert InvalidUserAddress();
        if (isRegistered[user]) revert UserAlreadyRegistered();
        isRegistered[user] = true;
    }

    /// @notice Assigns (or overwrites) the caller's delegate and allowance.
    /// @dev Overwriting an existing delegate emits a revoke event for the previous delegate.
    function setDelegate(
        address delegate,
        uint256 allowance
    ) external onlyRegisteredUser {
        if (delegate == address(0)) revert InvalidDelegateAddress();
        if (delegate == msg.sender) revert DelegateMustDifferFromUser();
        if (allowance == 0) revert InvalidAllowance();

        address previous = userToDelegation[msg.sender].delegate;
        if (previous != address(0)) {
            emit DelegateRevoked(msg.sender, previous);
        }

        userToDelegation[msg.sender] = Delegation({
            delegate: delegate,
            remainingUses: allowance
        });

        emit DelegateAssigned(msg.sender, delegate, allowance);
    }

    /// @notice Revokes the caller's delegate and clears remaining uses.
    function revokeDelegate() external onlyRegisteredUser {
        address current = userToDelegation[msg.sender].delegate;
        if (current == address(0)) revert NoDelegationActive();

        userToDelegation[msg.sender] = Delegation({
            delegate: address(0),
            remainingUses: 0
        });

        emit DelegateRevoked(msg.sender, current);
    }

    /// @notice Updates the caller’s own stored value.
    function setNumber(uint256 newValue) external onlyRegisteredUser {
        if (userToValue[msg.sender] == newValue)
            revert NewValueMustDifferFromOldValue();
        userToValue[msg.sender] = newValue;
    }

    /// @notice Updates a user's value using delegated authority.
    /// @dev Consumes exactly 1 remaining use on success.
    function setDelegateNumber(address user, uint256 newValue) external {
        if (!isRegistered[user]) revert UserNotRegistered();

        Delegation memory d = userToDelegation[user];

        if (d.delegate != msg.sender) revert NotAuthorizedDelegate();
        if (d.remainingUses == 0) revert NoRemainingUses();
        if (userToValue[user] == newValue)
            revert NewValueMustDifferFromOldValue();

        // Decrement allowance first (effects), then update state.
        userToDelegation[user].remainingUses = d.remainingUses - 1;
        userToValue[user] = newValue;

        emit DelegatedAction(user, msg.sender, newValue, d.remainingUses - 1);
    }
}
