# 08 – Simple 1v1 Bet with Arbitrator

This phase introduces a **two-player betting contract** resolved by a
mutually agreed arbitrator.

The goal is to reason about **multi-party coordination**, **explicit consent**,
and **third-party dispute resolution**, while keeping the system minimal
and deterministic.

---

## SimpleBet

### Purpose

`SimpleBet` allows two players to lock equal amounts of ETH into a bet.
An arbitrator, agreed upon by both parties at creation time, resolves
the bet by selecting a winner.

The contract enforces strict state transitions and guarantees that
funds are transferred **exactly once**.

---

## Roles

- **Player A**: creates the bet and defines the terms
- **Player B**: accepts the bet
- **Arbitrator**: resolves the bet by choosing the winner

There is no owner, admin, or privileged override.

---

## States

The contract follows a finite state machine:

- `Uninitialized`: contract deployed, no bet created yet
- `Created`: bet created by Player A
- `Accepted`: Player B has accepted the bet
- `Funded`: both players have deposited ETH
- `Resolved`: arbitrator has resolved the bet
- `Cancelled`: bet cancelled before full funding

---

## Functional Overview

### Creation

- Player A creates the bet
- Player B and arbitrator are fixed at creation
- Arbitrator cannot be Player A or Player B
- Bet amount is fixed
- Initial state is `Created`
- No ETH is deposited at creation

### Acceptance

- Only Player B may accept the bet
- State transitions to `Accepted`

### Funding

- Both players must deposit **exactly the bet amount**
- Each player may deposit only once
- When both deposits are received, state transitions to `Funded`

### Resolution

- Only the arbitrator may resolve the bet
- Resolution is allowed only in the `Funded` state
- Arbitrator selects Player A or Player B as winner
- All ETH is transferred to the winner
- State transitions to `Resolved`

### Cancellation

- Only Player A may cancel
- Cancellation allowed only before full funding (in `Created` or `Accepted` state)
- If a player has already deposited, they are refunded
- State transitions to `Cancelled`

---

## Invariants

- Both players must deposit the same amount
- ETH can be transferred only once
- After `Resolved` or `Cancelled`, no further actions are allowed
- Arbitrator cannot be Player A or Player B
- Arbitrator cannot deposit, cancel, or withdraw funds

---

## Events

All meaningful state changes emit events:

- `BetCreated`
- `BetAccepted`
- `BetFunded`
- `BetResolved`
- `BetCancelled`

---

## Design Constraints

- Single bet only (no mappings or bet IDs)
- No external libraries
- No owner or admin role
- No fees or commissions
- No time-based logic

The focus is on **clarity, correctness, and explicit authorization**.

---

## Scope

This contract intentionally avoids advanced features such as:
- Multiple concurrent bets
- Appeals or re-arbitration
- Arbitrator incentives or staking
- Timeouts or automatic resolution

These may be explored in later phases.
