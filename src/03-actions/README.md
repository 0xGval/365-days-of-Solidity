# 03 – Actions

This folder contains the third set of smart contracts in the *365 Days of Solidity* project.

The goal of this phase is to introduce user-driven state transitions by extending
the registry pattern with explicit role-based actions and identity-dependent rules.

---

## ControlledRegistryWithActions

### Purpose

`ControlledRegistryWithActions` extends the registry model introduced in Day 2 by
allowing registered users to actively update their own stored state.

The contract models a simple permission system where ownership and user actions
are clearly separated, and where allowed behavior depends on both identity and
prior state.

---

### Functional Overview

The contract implements the following behavior:

- Assigns a single owner at deployment time  
- Allows only the owner to register new users  
- Associates each registered user with an initial numeric value  
- Applies a predefined baseline value uniformly to all users at registration  
- Allows registered users to update their own stored value  
- Prevents users from modifying the state of other addresses  
- Prevents non-registered addresses from performing user actions  
- Explicitly reverts on all invalid or unauthorized operations  

---

### Access Model

The contract defines two distinct roles:

**Owner**
- Responsible only for onboarding users
- Cannot modify user values after registration
- Cannot act on behalf of users

**User**
- Must be explicitly registered by the owner
- Can update only their own stored value
- Cannot access or modify other users’ state

This separation ensures that user agency begins only after registration.

---

### Events and Observability

State transitions are designed to be observable through events emitted on:

- Successful user registration
- Successful user-initiated value updates

This enables off-chain systems to track meaningful changes in contract state.

---

### Concepts Covered

This contract introduces several new concepts compared to previous days:

- Identity-based access control using `msg.sender`
- User-driven state transitions
- Role separation without role hierarchies
- Enforcement of business rules via custom errors
- Clear distinction between global policy and per-user actions

---

### Scope and Limitations

This contract intentionally avoids:

- Deregistration or user removal
- Role hierarchies beyond owner and user
- External libraries
- Upgradeability patterns
- Gas optimizations
- Production-level security hardening

The focus remains on correctness, clarity, and predictable behavior.

---

### Notes

This contract represents the first step toward modeling interactive systems
where users actively modify on-chain state.

It serves as a foundation for more advanced workflows involving permissions,
state transitions, and user interactions in later phases of the project.
