// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

/*
Purpose:
Extends the registry pattern by allowing registered users to actively modify
their own stored state under explicit access rules.

The contract enforces a clear separation between owner responsibilities
(onboarding) and user responsibilities (self-managed state updates).
*/

contract ControlledRegistryWithActions {
    /// @notice Address authorized to register users.
    address public immutable i_owner;

    /// @notice Baseline value assigned to all users at registration time.
    /// @dev Represents a global policy applied uniformly to all users.
    uint256 public immutable defaultValue;

    /// @notice Tracks whether an address has been registered.
    mapping(address => bool) public isRegistered;

    /// @notice Stores the value associated with each registered address.
    mapping(address => uint256) public values;

    /// @notice Reverts when a non-owner attempts an owner-only action.
    error NotOwner();

    /// @notice Reverts when a non-registered address attempts a user-only action.
    error UserNotRegistered();

    /// @notice Reverts when attempting to register an already registered address.
    error UserAlreadyRegistered();

    /// @notice Reverts when attempting to update a value without changing it.
    error NewNumberMustDifferFromOldNumber();

    constructor() {
        i_owner = msg.sender;
        defaultValue = 1;
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

    /// @notice Emitted when a new user is successfully registered.
    event UserRegistered(address indexed user, uint256 initialValue);

    /// @notice Emitted when a registered user updates their stored value.
    event UserValueUpdated(address indexed user, uint256 newValue);

    /// @notice Registers a new user with the baseline value.
    /// @dev Only callable by the owner.
    function registerUser(address _user) public onlyOwner {
        if (isRegistered[_user]) revert UserAlreadyRegistered();

        isRegistered[_user] = true;
        values[_user] = defaultValue;

        emit UserRegistered(_user, defaultValue);
    }

    /// @notice Updates the caller's own stored value.
    /// @dev Only callable by registered users.
    function updateNumber(uint256 _newValue) public onlyRegisteredUser {
        if (values[msg.sender] == _newValue)
            revert NewNumberMustDifferFromOldNumber();

        values[msg.sender] = _newValue;
        emit UserValueUpdated(msg.sender, _newValue);
    }
}
