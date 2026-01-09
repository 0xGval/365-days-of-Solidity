# 09 – Commit Reveal Game

This phase introduces the **commit–reveal pattern**, a fundamental technique
used to prevent front-running and cheating in on-chain games.

The goal is to reason about **secrecy, fairness, and time-bounded actions**
using hashes and irreversible state transitions.

---

## CommitRevealGame

### Purpose

`CommitRevealGame` allows two players to participate in a fair game where
choices are hidden at first and revealed later.

Players commit to a secret choice, then reveal it.
The contract verifies correctness and determines the winner.

---

## Roles

- **Player A**: creates the game
- **Player B**: joins the game
- No owner, no arbitrator

---

## Game Flow

The game follows these phases:

1. **Commit Phase**
2. **Reveal Phase**
3. **Resolved**

Each phase is strictly enforced.

---

## Commit Phase

- Player A creates the game
- Player B joins the game
- Both players submit a commitment hash:
  - `commit = keccak256(choice, salt)`
- No player can see the other’s choice

Rules:
- Each player can commit only once
- Commitments cannot be changed
- Choices are not stored on-chain yet

---

## Reveal Phase

- Players reveal their:
  - `choice`
  - `salt`
- Contract recomputes the hash and verifies it matches the commitment

Rules:
- Reveal must match the committed hash
- Reveal can happen only once per player
- Invalid reveals revert

---

## Resolution

- Once both reveals are valid:
  - The game resolves automatically
- The winner is determined by predefined rules
  (e.g. higher number wins, or parity-based rule)

---

## Time Constraints

- Commit phase has a fixed duration
- Reveal phase has a fixed duration

If a player fails to act in time:
- The other player wins by default

---

## State Transitions

The contract must enforce the following states:

- `Uninitialized`
- `Commit`
- `Reveal`
- `Resolved`

Transitions are irreversible.

---

## Events

The following events must be emitted:

- `GameCreated(playerA, playerB)`
- `Committed(player)`
- `Revealed(player, choice)`
- `GameResolved(winner)`

---

## Security Constraints

- No player can reveal before both commits
- No player can change their choice after committing
- Hash verification must be strict
- No external randomness
- No off-chain dependencies

---

## Design Constraints

- No owner or admin role
- One game per contract
- No token usage
- No external libraries
- Focus on correctness and clarity

---

## Learning Goals

- Commit–reveal pattern
- Hash-based verification
- Time-based state enforcement
- Fairness without trust
- Defensive state machines
