# 04 – Delegation

This phase introduces delegated authority into the user-driven registry model.

The goal is to model a minimal but realistic delegation workflow, where users
can explicitly authorize another address to act on their behalf under strict
and observable rules.

---

## ControlledRegistryWithDelegation

### Purpose

`ControlledRegistryWithDelegation` extends the registry pattern by allowing
registered users to assign a single delegate address.

Delegation is explicit, revocable, and strictly limited. The contract enforces
a clear separation between ownership, user authority, and delegated authority.

---

### Functional Overview

The contract implements the following behavior:

- A single owner is responsible for user registration
- Registered users may assign exactly one delegate
- Delegation can be overwritten or revoked at any time by the user
- A delegate may act only on behalf of the authorizing user
- Delegates lose permissions immediately upon revocation
- The owner has no authority over delegation

---

### Delegation Rules

- Self-delegation is not allowed
- The zero address cannot be assigned as a delegate
- Overwriting a delegate emits a revocation event for the previous delegate
  before assigning the new one
- Delegates cannot assign or revoke delegation

---

### Observability

All delegation-related state transitions are observable via events:

- `DelegateAssigned` is emitted when a delegate is assigned
- `DelegateRevoked` is emitted when a delegate is revoked or overwritten
- `DelegateAction` is emitted when a delegate performs an action

---

### Testing

The contract is covered by a dedicated test suite that verifies:

- Ownership and registration constraints
- Delegate assignment and revocation
- Overwriting delegation behavior
- Enforcement of delegated permissions
- Immediate loss of permissions after revocation
- Correct event emission for all observable actions

Each test focuses on a single behavioral rule.

---

### Scope and Limitations

This contract intentionally avoids:

- Role hierarchies or multisig logic
- Off-chain signatures
- External libraries
- Complex permission graphs

The emphasis is on clarity, correctness, and explicit authorization boundaries.
