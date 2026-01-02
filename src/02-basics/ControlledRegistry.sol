// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

/*
Purpose:
This contract implements a minimal but realistic registry-based state management pattern.

It maintains a mapping between addresses and numeric values, while tracking registration
status separately to avoid ambiguity and allow zero values as valid entries.

Write access is restricted to a single owner, and all state changes are made observable
through events.
 
Functional requirements:
- Maintain mappings as the main state variables
- Assign an owner at deployment time
- Allow only the owner to register or update values
- Allow anyone to read stored values
- Emit an event on every state update
- Explicitly revert on unauthorized write attempts
*/

contract ControlledRegistry {
    /// @notice Address authorized to register and update values.
    /// @dev Immutable since ownership is fixed at deployment time.
    address public immutable i_owner;

    /// @notice Tracks whether an address has been registered.
    /// @dev Separates existence from stored value to avoid sentinel-value ambiguity.
    mapping(address user => bool registered) public isRegistered;

    /// @notice Stores the numeric value associated with a registered address.
    mapping(address user => uint256 number) public registry;

    /// @notice Reverts when a non-owner attempts a restricted action.
    error NotOwner();

    /// @notice Reverts when attempting to register an already registered address.
    error UserAlreadyRegistered();

    /// @notice Reverts when attempting to update an unregistered address.
    error UserNotRegistered();

    /// @notice Sets the deployer as the contract owner.
    constructor() {
        i_owner = msg.sender;
    }

    /// @notice Restricts function execution to the contract owner.
    modifier onlyOwner() {
        if (msg.sender != i_owner) revert NotOwner();
        _;
    }

    /// @notice Emitted when a new address is registered with an associated value.
    /// @param user The address being registered.
    /// @param number The value assigned at registration time.
    event NumberRegistered(address indexed user, uint256 number);

    /// @notice Emitted when an existing registered value is updated.
    /// @param user The address whose value is updated.
    /// @param newNumber The new value assigned.
    event NumberUpdated(address indexed user, uint256 newNumber);

    /// @notice Registers a new address with an associated numeric value.
    /// @dev Reverts if the address is already registered.
    /// @param _user The address to register.
    /// @param _number The value to associate with the address.
    function registerNumber(address _user, uint256 _number) public onlyOwner {
        if (isRegistered[_user]) revert UserAlreadyRegistered();

        isRegistered[_user] = true;
        registry[_user] = _number;

        emit NumberRegistered(_user, _number);
    }

    /// @notice Updates the numeric value associated with a registered address.
    /// @dev Reverts if the address has not been previously registered.
    /// @param _user The address whose value is being updated.
    /// @param _number The new value to store.
    function updateNumber(address _user, uint256 _number) public onlyOwner {
        if (!isRegistered[_user]) revert UserNotRegistered();

        registry[_user] = _number;

        emit NumberUpdated(_user, _number);
    }
}
