// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

/*
Purpose:
Introduces delegated actions into a user-driven registry model.

Registered users may explicitly authorize a single delegate address to act on
their behalf under strict and verifiable rules.

The contract enforces clear separation between ownership, user authority, and
delegated authority.
*/

contract ControlledRegistryWithDelegation {
    /// @notice Address with exclusive permission to register users.
    address public immutable i_owner;

    constructor() {
        i_owner = msg.sender;
    }

    /// @notice Tracks whether an address is registered as a user.
    mapping(address => bool) public isRegistered;

    /// @notice Stores the delegate authorized by each user.
    mapping(address => address) public userToDelegate;

    /// @notice Stores the value associated with each user.
    mapping(address => uint256) public userToValue;

    /// @notice Reverts when a non-registered address is involved in a user-only action.
    error UserNotRegistered();

    /// @notice Reverts when attempting to register an already registered user.
    error UserAlreadyRegistered();

    /// @notice Reverts when a non-owner attempts an owner-only action.
    error NotOwner();

    /// @notice Reverts when an invalid delegate address is provided.
    error InvalidDelegateAddress();

    /// @notice Reverts when the caller is not the authorized delegate for a user.
    error MsgSenderIsNotTargetUserDelegate();

    /// @notice Reverts when attempting to self-delegate.
    error DelegateAddressMustDifferFromUserAddress();

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

    /// @notice Restricts execution to the delegate authorized by a specific user.
    modifier onlyDelegateOf(address userAddress) {
        if (userToDelegate[userAddress] != msg.sender)
            revert MsgSenderIsNotTargetUserDelegate();
        _;
    }

    /// @notice Ensures the target user is registered.
    modifier onlyRegisteredTarget(address userAddress) {
        if (!isRegistered[userAddress]) revert UserNotRegistered();
        _;
    }

    /// @notice Emitted when a registered user assigns a delegate.
    event DelegateAssigned(address indexed user, address indexed delegate);

    /// @notice Emitted when a registered user revokes a delegate.
    event DelegateRevoked(address indexed user, address indexed delegate);

    /// @notice Emitted when a delegate performs an action on behalf of a user.
    event DelegatedAction(
        address indexed user,
        address indexed delegate,
        uint256 newValue
    );

    /// @notice Registers a new user.
    /// @dev Callable only by the owner.
    function registerUser(address userAddress) public onlyOwner {
        if (isRegistered[userAddress]) revert UserAlreadyRegistered();
        isRegistered[userAddress] = true;
    }

    /// @notice Assigns a delegate to the caller.
    /// @dev Replaces any previously assigned delegate.
    function setDelegate(address delegatedAddress) public onlyRegisteredUser {
        if (delegatedAddress == address(0)) revert InvalidDelegateAddress();
        if (delegatedAddress == msg.sender)
            revert DelegateAddressMustDifferFromUserAddress();

        address previousDelegate = userToDelegate[msg.sender];

        // Revoke previous delegate only if one existed
        if (previousDelegate != address(0)) {
            emit DelegateRevoked(msg.sender, previousDelegate);
        }

        userToDelegate[msg.sender] = delegatedAddress;

        emit DelegateAssigned(msg.sender, delegatedAddress);
    }

    /// @notice Updates the caller’s own stored value.
    function updateNumber(uint256 newValue) public onlyRegisteredUser {
        userToValue[msg.sender] = newValue;
    }

    /// @notice Updates a user’s value via delegated authority.
    function updateNumberDelegate(
        address userAddress,
        uint256 newValue
    ) public onlyRegisteredTarget(userAddress) onlyDelegateOf(userAddress) {
        userToValue[userAddress] = newValue;
        emit DelegatedAction(userAddress, msg.sender, newValue);
    }

    /// @notice Revokes the caller’s delegate.
    function revokeDelegate() public onlyRegisteredUser {
        address delegateAddress;
        delegateAddress = userToDelegate[msg.sender];
        userToDelegate[msg.sender] = address(0);
        emit DelegateRevoked(msg.sender, delegateAddress);
    }
}
