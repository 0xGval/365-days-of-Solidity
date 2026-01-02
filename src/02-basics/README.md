# 02 – Basics

This folder contains the second set of smart contracts in the *365 Days of Solidity* project.

The goal of this phase is to extend the foundational concepts introduced in Day 1 by
moving from a single controlled value to a small but realistic registry pattern,
while maintaining clarity, explicit rules, and disciplined testing.

---

## ControlledRegistry

### Purpose

`ControlledRegistry` is a minimal smart contract designed to demonstrate how on-chain
state can be managed when multiple entities are involved.

The contract maintains a registry that associates addresses with numeric values and
enforces strict write access through an owner-based access control mechanism.
Registration status and stored values are tracked separately to avoid ambiguity and
allow zero values as valid entries.

All state changes are observable via events.

---

### Functional Overview

The contract implements the following behavior:

- Maintains a registry mapping addresses to numeric values  
- Tracks registration status separately from stored values  
- Assigns an owner at deployment time  
- Allows only the owner to register new addresses  
- Allows only the owner to update values of registered addresses  
- Allows anyone to read registration status and stored values  
- Emits an event on every successful registration or update  
- Explicitly reverts on unauthorized or invalid operations  

---

### Concepts Covered

This contract exercises and expands on several Solidity concepts:

- Mappings and key-based storage  
- Separation of existence tracking from stored data  
- Ownership and access control  
- Custom errors and explicit revert conditions  
- Event-driven state change observability  
- Clear separation of responsibilities between functions  

---

### Testing

The contract is covered by a dedicated test suite implemented with Foundry.

The tests verify:

- Correct ownership assignment at deployment  
- Successful registration of new addresses by the owner  
- Prevention of duplicate registrations  
- Successful updates of registered values by the owner  
- Enforcement of access control against non-owner addresses  

Each test is small, focused, and validates a single expected behavior to ensure
clarity and isolation.

---

### Scope and Limitations

This contract is intentionally scoped to remain simple and focused.

It does not include:

- Deregistration or deletion of entries  
- Role-based access control beyond a single owner  
- Upgradeability patterns  
- Gas optimizations  
- Production-level security hardening  

The emphasis is on correctness, explicit rules, and maintainable structure.

---

### Notes

This contract represents a natural progression from Day 1 by introducing
multi-entity state management while preserving simplicity.

It serves as a foundation for more advanced patterns involving collections,
permissions, and state transitions in later phases of the project.
