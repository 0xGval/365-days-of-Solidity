# 05 – Limited Delegation

This phase introduces **usage-limited delegation** into the registry model.

The goal is to model delegation as a **consumable permission**, where delegated
authority is explicitly bounded and automatically expires once its allowance
is exhausted.

---

## ControlledRegistryWithLimitedDelegation

### Purpose

`ControlledRegistryWithLimitedDelegation` allows registered users to assign a
delegate with a **fixed number of permitted actions**.

Each delegated action consumes one allowance unit. When the allowance reaches
zero, the delegation becomes inactive.

---

### Functional Overview

The contract implements the following behavior:

- A single owner registers users
- Registered users may assign one delegate with a limited allowance
- Each delegated action consumes one allowance unit
- Delegation becomes inactive when allowance is exhausted
- Users may revoke delegation at any time
- Delegates may act only within the granted allowance
- The owner has no authority over delegation

---

### Delegation Rules

- Self-delegation is not allowed
- The zero address cannot be assigned as a delegate
- Allowance must be greater than zero
- Delegates cannot assign, revoke, or extend delegation
- Revocation immediately removes all delegated permissions

---

### Observability

All delegation-related state changes are observable via events:

- `DelegateAssigned`
- `DelegateRevoked`
- `DelegatedAction` (includes remaining allowance)

---

### Scope

This contract intentionally avoids advanced features such as time-based expiry,
role hierarchies, or off-chain signatures.

The focus is on **explicit, stateful, and limited authority modeling**.
