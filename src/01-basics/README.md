# 01 – Basics

This folder contains the first set of smart contracts in the *365 Days of Solidity* project.

The goal of this phase is to establish a solid foundation in Solidity by focusing on
core language concepts, basic access control, and disciplined testing practices.

---

## ControlledStorage

### Purpose

`ControlledStorage` is a minimal but realistic smart contract designed to demonstrate
how on-chain state can be managed and protected.

The contract maintains a single numeric value and enforces strict write access through
an owner-based access control mechanism. All state changes are observable via events.

This contract intentionally avoids external libraries and advanced patterns in order
to focus on clarity and fundamentals.

---

### Functional Overview

The contract implements the following behavior:

- Stores a single `uint256` value on-chain  
- Assigns an owner at deployment time  
- Restricts state updates to the owner only  
- Allows anyone to read the stored value  
- Emits an event on every successful update  
- Explicitly reverts on unauthorized write attempts  

---

### Concepts Covered

This contract exercises several core Solidity concepts:

- State variables and persistent storage  
- Function visibility and access restrictions  
- Ownership and basic access control  
- Custom errors and explicit reverts  
- Events and state change traceability  

---

### Testing

The contract is covered by a dedicated test suite implemented with Foundry.

The tests verify:

- Correct initial state after deployment  
- Correct ownership assignment  
- Enforcement of access control against non-owner addresses  

Tests are written to be small, focused, and independent, with each test validating
a single expected behavior.

---

### Scope and Limitations

This contract is intentionally simple and does not include:

- Upgradeability patterns  
- Role-based access control beyond a single owner  
- Gas optimizations  
- Production-level security hardening  

The focus of this phase is correctness, readability, and understanding fundamentals.

---

### Notes

This contract serves as the baseline for more complex patterns introduced in later
phases of the project. The emphasis is on disciplined structure, clear intent, and
test-driven validation rather than feature completeness.
