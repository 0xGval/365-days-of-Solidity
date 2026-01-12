# 12 – Simple Crowdfunding

A crowdfunding contract where contributors pledge ETH toward a goal.
If the goal is reached before the deadline, the creator can withdraw.
If not, contributors can claim refunds.

This implementation uses the **pull-based refund pattern** for safety
and demonstrates time-based state transitions without explicit state enums.

---

## SimpleCrowdfunding

### Purpose

`SimpleCrowdfunding` models a basic fundraising campaign with:
- A funding goal (minimum ETH to raise)
- A deadline (timestamp after which contributions close)
- Success/failure outcome based on whether goal was met

The contract handles ETH custody, tracks per-contributor amounts,
and enforces withdrawal/refund rules based on campaign outcome.

---

### Roles

- **Creator**: deploys the contract, sets goal and deadline, withdraws funds on success
- **Contributors**: send ETH before deadline, claim refunds on failure

---

### Functional Overview

- Creator deploys with a goal amount and deadline timestamp
- Anyone can contribute ETH before the deadline
- Multiple contributions from the same address accumulate
- After the deadline:
  - If `totalRaised >= goal`: creator can withdraw all funds
  - If `totalRaised < goal`: each contributor can claim their refund
- Refunds use pull pattern: contributors claim individually
- No partial withdrawals or extensions

---

### State

The contract tracks:

- `i_creator`: campaign creator (immutable)
- `i_goal`: minimum ETH required for success (immutable)
- `i_deadline`: unix timestamp when campaign ends (immutable)
- `totalRaised`: sum of all contributions
- `withdrawn`: whether creator has withdrawn funds
- `contributions`: mapping of address → amount contributed

---

### Functions

#### contribute()

- Accepts ETH before deadline
- Reverts if deadline passed
- Reverts if `msg.value == 0`
- Accumulates multiple contributions per address
- Emits `ContributionReceived`

---

#### withdraw()

- Only callable by creator
- Only callable after deadline
- Only callable if goal was reached (`totalRaised >= goal`)
- Reverts if already withdrawn
- Transfers entire contract balance to creator
- Emits `FundsWithdrawn`

---

#### refund()

- Only callable after deadline
- Only callable if goal was NOT reached (`totalRaised < goal`)
- Reverts if caller has no contribution
- Sets caller's contribution to zero before transfer (CEI pattern)
- Transfers caller's contribution back
- Emits `RefundClaimed`

---

### Events

##### ContributionReceived(address indexed contributor, uint256 amount, uint256 totalRaised)

- Emitted on every successful contribution
- Includes updated total raised

##### FundsWithdrawn(address indexed creator, uint256 amount)

- Emitted when creator withdraws after successful campaign

##### RefundClaimed(address indexed contributor, uint256 amount)

- Emitted when contributor claims refund after failed campaign

---

### Design Constraints

- One campaign per contract deployment
- ETH only (no token support)
- Fixed goal and deadline (immutable)
- No partial withdrawals
- No campaign extensions or cancellations
- Pull-based refunds (each contributor claims individually)
- Overfunding allowed (contributions accepted after goal is met)

---

### Security Considerations

- Creator immutability prevents ownership hijacking
- Deadline immutability prevents rule changes mid-campaign
- Pull refunds avoid loops and gas limit issues
- CEI pattern in refund prevents reentrancy
- Contribution zeroed before transfer
- No external calls except ETH transfers
- Integer overflow protected by Solidity 0.8+

---

### Concepts Practiced

- Time-based conditions (`block.timestamp`)
- Pull payment pattern (safe refunds)
- Derived state (success/failure from goal and totalRaised)
- CEI pattern (Checks-Effects-Interactions)
- Immutable deployment parameters
- Per-user accounting with mappings

---

### Not Implemented (Future Learning)

- Multiple campaigns per contract
- Stretch goals / milestones
- Campaign cancellation by creator
- Minimum contribution amounts
- Contribution caps
- Token-based crowdfunding
- Refund deadlines

---

## License

GPL-3.0
