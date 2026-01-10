# MultiSigWallet

A minimal, on-chain **multi-signature wallet** that allows a group of owners
to collectively manage native ETH using a **threshold-based approval system**.

The wallet is fully self-governing:
owners and approval threshold can only be changed through the same multi-sig
proposal → approval → execution flow.

This implementation intentionally focuses on **clarity, correctness, and invariants**
over feature bloat.

---

## Overview

- ETH-only multi-signature wallet
- Dynamic owners
- Dynamic approval threshold
- On-chain approvals (no signatures, no off-chain coordination)
- No privileged admin role

---

## Roles

### Owners

- Owners have voting power
- Any owner can:
  - Propose transactions
  - Approve or revoke approvals
  - Execute approved transactions
- No single owner can act unilaterally

---

## Core Concepts

### Threshold

- Minimum number of approvals required to execute a transaction
- Must always satisfy:
  - `threshold >= 1`
  - `threshold <= owners.length`

---

## Transaction Lifecycle

### 1. Proposal

Any owner can propose a transaction.

Types of proposals:
- ETH transfer
- Add owner
- Remove owner
- Change threshold

Each proposal:
- Gets a unique transaction ID
- Starts in `Pending` state
- Automatically counts the proposer as the first approval

---

### 2. Approval

- Any owner can approve a pending transaction
- Each owner can approve **only once per transaction**
- Approvals are tracked per `(txId, owner)`

---

### 3. Revocation (Optional but implemented)

- An owner can revoke their approval **before execution**
- Revocation decreases the approval count
- Cannot revoke after execution

---

### 4. Execution

- Any owner can execute a transaction once:
  - `approvalCount >= threshold`
- Execution:
  - Transfers ETH (for transfer transactions)
  - Modifies ownership or threshold (for governance transactions)
- Executed transactions are immutable

---

## Governance Transactions

Governance actions use the **same multisig flow** as ETH transfers.

### Add Owner

- Propose a new owner address
- Requires threshold approvals
- Zero address and duplicate owners are rejected

---

### Remove Owner

- Propose an existing owner for removal
- Requires threshold approvals
- Safety checks:
  - Owner count must remain ≥ 1
  - Threshold must not exceed remaining owner count
- Removed owner:
  - Is deleted from owners list
  - Loses all pending approvals

---

### Change Threshold

- Propose a new threshold value
- Requires threshold approvals
- New threshold must satisfy:
  - `1 <= newThreshold <= owners.length`

---

## ETH Transfers

- Only native ETH transfers are supported
- No arbitrary contract calls
- No token transfers

---

## States

Each transaction is always in one of the following states:

- `Pending`: awaiting approvals
- `Executed`: successfully executed
- `Cancelled`: not implemented (intentionally omitted to reduce complexity)

---

## Events

The contract emits the following events:

- `Deposit(sender, amount, balance)`
- `TransactionProposed(txId, proposer, destination, amount)`
- `TransactionApproved(txId, owner)`
- `TransactionRevoked(txId, owner)`
- `TransactionExecuted(txId, destination, amount)`
- `OwnerAdded(owner)`
- `OwnerRemoved(owner)`
- `ThresholdChanged(oldThreshold, newThreshold)`

---

## Security Guarantees

- Only owners can propose, approve, revoke, or execute
- No duplicate owners
- No zero address owners
- No double approvals
- Execution requires sufficient approvals
- Owner removal cannot break threshold invariants
- Reentrancy-safe ETH transfers (state updated before external call)
- Executed transactions cannot be modified

---

## Invariants

The following invariants are always preserved:

- `owners.length >= 1`
- `threshold >= 1`
- `threshold <= owners.length`
- Each address is owner at most once
- Pending approvals are consistent with active owners

---

## Design Decisions

- No external libraries
- No off-chain signatures
- No arbitrary calldata execution
- No time-based expiration
- No transaction cancellation (intentionally omitted)

The goal is to keep the contract **simple, auditable, and easy to reason about**.

---

## Intended Use

This contract is designed as:
- A learning implementation of multisig patterns
- A clean reference for dynamic access control
- A junior-level portfolio project demonstrating real-world Solidity reasoning

---

## License

GPL-3.0
