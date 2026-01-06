# 06 – Simple Escrow

This phase introduces a minimal escrow contract to model ETH transfers
under explicit and irreversible rules.

The goal is to reason about state transitions, ETH handling, and
clear execution flows rather than registry-style storage.

---

## SimpleEscrow

### Purpose

`SimpleEscrow` locks ETH between two parties until the payer explicitly
releases or cancels the escrow.

The contract models a finite state machine where funds can be transferred
exactly once and never recovered afterward.

---

### Roles

- **Payer**: creates the escrow, funds it, and controls its resolution
- **Payee**: receives the funds if the escrow is released

There is no owner role and no third-party authority.

---

### States

The escrow moves through the following states:

- `Uninitialized`
- `Created`
- `Funded`
- `Released`
- `Cancelled`

All state transitions are one-way and irreversible.

---

### Functional Overview

- The escrow is created with a fixed payer and payee
- Only the payer may fund the escrow
- Funding requires sending ETH and can occur only once
- Once funded, the payer may either:
  - Release the ETH to the payee
  - Cancel the escrow and refund themselves
- After release or cancellation, no further actions are allowed

---

### Events

All meaningful state transitions are observable via events:

- `Created`
- `Funded`
- `Released`
- `Cancelled`

---

### Design Constraints

- Single escrow instance
- No owner or admin role
- No mappings or arrays
- No external libraries
- Focus on correctness, clarity, and explicit state transitions
