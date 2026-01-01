// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

/*
Purpose:
This contract implements a minimal but realistic state management pattern.

It maintains a single numeric value on-chain, restricts write access to a single
authorized address, and makes all state changes observable via events.

Functional requirements:
- Store a single numeric value on-chain
- Assign an owner at deployment time
- Allow only the owner to update the stored value
- Allow anyone to read the current value
- Emit an event on every state update
- Explicitly revert on unauthorized write attempts
*/

contract ControlledStorage {

    /// @notice Public state variable holding the stored numeric value.
    /// @dev Declared as public to expose an auto-generated getter function.
    uint256 public number;

    /// @notice Address authorized to modify the stored value.
    /// @dev Marked as immutable since it is assigned once at deployment and never changes.
    address public immutable i_owner;

    /// @notice Emitted whenever the stored value is updated.
    /// @param updater The address that performed the update.
    /// @param newNumber The new value written to storage.
    event NumberUpdated(address indexed updater, uint256 newNumber);

    /// @notice Reverts when a non-authorized address attempts a restricted action.
    error NotOwner();

    /// @notice Sets the deployer as the contract owner.
    constructor() {
        i_owner = msg.sender;
    }

    /// @notice Restricts function execution to the contract owner.
    modifier onlyOwner() {
        if (msg.sender != i_owner) revert NotOwner();
        _;
    }

    /// @notice Updates the stored numeric value.
    /// @dev Can only be called by the owner.
    /// @param _number The new value to be stored.
    function updateNumber(uint256 _number) public onlyOwner {
        number = _number;
        emit NumberUpdated(msg.sender, _number);
    }
}
