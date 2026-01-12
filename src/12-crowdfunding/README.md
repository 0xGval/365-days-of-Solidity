# Day 12: SimpleCrowdfunding

## Purpose

A crowdfunding contract where contributors pledge ETH toward a goal. If the goal is reached before the deadline, the creator can withdraw the funds. If not, contributors can get refunds.

---

## Your Assignment

Build a `SimpleCrowdfunding` contract that:

1. Has a **funding goal** and **deadline** set at deployment
2. Allows anyone to **contribute** ETH before the deadline
3. Tracks **contributions per address**
4. If goal reached → **creator withdraws** all funds
5. If goal NOT reached after deadline → **contributors get refunds**

---

## Concepts to Practice

- **Deadline enforcement**: `block.timestamp` comparisons
- **Goal tracking**: Accumulating contributions
- **Refund pattern**: Pull-based refunds (safe pattern)
- **State transitions**: Active → Success/Failed
- **Per-user accounting**: Tracking individual contributions

---

## Roles

| Role | Capabilities |
|------|-------------|
| **Creator** | Deploys contract, sets goal/deadline, withdraws if successful |
| **Contributor** | Sends ETH, can refund if campaign fails |

---

## State Machine

```
                    deadline passed
                    + goal reached
[Active] ─────────────────────────────────► [Successful]
    │                                            │
    │ deadline passed                            │
    │ + goal NOT reached                         ▼
    │                                     creator withdraws
    ▼
[Failed] ──────────────────────────────────► contributors refund
```

### States

| State | Description |
|-------|-------------|
| `Active` | Campaign ongoing, accepting contributions |
| `Successful` | Goal reached, creator can withdraw |
| `Failed` | Deadline passed without reaching goal, refunds enabled |

---

## Suggested Storage

```solidity
address public immutable i_creator;
uint256 public immutable i_goal;
uint256 public immutable i_deadline;

uint256 public totalRaised;
bool public withdrawn;

mapping(address => uint256) public contributions;
```

---

## Required Functions

### Write Functions

| Function | Description |
|----------|-------------|
| `contribute()` | Send ETH to the campaign (payable) |
| `withdraw()` | Creator withdraws funds (only if successful) |
| `refund()` | Contributor gets their ETH back (only if failed) |

### View Functions

| Function | Description |
|----------|-------------|
| `getContribution(address)` | Returns contribution amount for address |
| `isSuccessful()` | Returns true if goal reached |
| `isActive()` | Returns true if deadline not passed |
| `isFailed()` | Returns true if deadline passed AND goal not reached |
| `timeLeft()` | Returns seconds until deadline (0 if passed) |

---

## Events

```solidity
event ContributionReceived(address indexed contributor, uint256 amount, uint256 totalRaised);
event FundsWithdrawn(address indexed creator, uint256 amount);
event RefundClaimed(address indexed contributor, uint256 amount);
```

---

## Custom Errors

```solidity
error CampaignEnded();
error CampaignNotEnded();
error GoalNotReached();
error GoalAlreadyReached();
error NotCreator();
error NoContribution();
error AlreadyWithdrawn();
error AlreadyRefunded();
error TransferFailed();
error ZeroContribution();
```

---

## Function Logic

### `contribute()`

```
1. Check campaign is still active (deadline not passed)
2. Check msg.value > 0
3. Add to contributor's balance
4. Add to totalRaised
5. Emit ContributionReceived
```

### `withdraw()`

```
1. Check caller is creator
2. Check deadline has passed
3. Check goal was reached
4. Check not already withdrawn
5. Mark as withdrawn
6. Transfer all ETH to creator
7. Emit FundsWithdrawn
```

### `refund()`

```
1. Check deadline has passed
2. Check goal was NOT reached
3. Check caller has contribution > 0
4. Store contribution amount
5. Set caller's contribution to 0 (before transfer!)
6. Transfer ETH to caller
7. Emit RefundClaimed
```

---

## Invariants

1. `totalRaised == sum of all contributions` (before refunds)
2. Cannot contribute after deadline
3. Cannot withdraw if goal not reached
4. Cannot refund if goal reached
5. Each contributor can refund only once
6. Creator can withdraw only once

---

## Edge Cases to Handle

1. Contribute exactly at deadline → should work or fail?
2. Contribute 0 ETH → revert
3. Multiple contributions from same address → accumulate
4. Withdraw when already withdrawn → revert
5. Refund when no contribution → revert
6. Refund twice → revert (balance is 0)
7. Goal exactly met → counts as successful

---

## Design Decisions

### Why Pull-Based Refunds?

Instead of the creator triggering refunds to everyone (push), each contributor claims their own refund (pull). This is safer because:
- No loop over unknown number of addresses
- No risk of running out of gas
- No risk of malicious contracts blocking refunds

### Why Immutable Goal/Deadline?

- Creator cannot change rules mid-campaign
- Contributors know exactly what they're funding
- Simplifies state management

---

## Test Scenarios

### Happy Path - Successful Campaign
1. Deploy with goal = 10 ETH, deadline = 7 days
2. Contributor A sends 6 ETH
3. Contributor B sends 5 ETH
4. Warp past deadline
5. Creator withdraws 11 ETH
6. Verify withdrawn flag, balances

### Happy Path - Failed Campaign
1. Deploy with goal = 10 ETH, deadline = 7 days
2. Contributor A sends 3 ETH
3. Contributor B sends 2 ETH
4. Warp past deadline
5. Contributor A refunds → gets 3 ETH
6. Contributor B refunds → gets 2 ETH

### Access Control
1. Non-creator cannot withdraw
2. Cannot contribute after deadline
3. Cannot refund before deadline
4. Cannot refund if goal reached

### Edge Cases
1. Contribute multiple times → balances accumulate
2. Exact goal amount → campaign successful
3. Refund twice → second call reverts
4. Withdraw twice → second call reverts

---

## Test Helpers

```solidity
// Setup
function setUp() public {
    creator = makeAddr("creator");
    alice = makeAddr("alice");
    bob = makeAddr("bob");

    vm.deal(alice, 100 ether);
    vm.deal(bob, 100 ether);

    vm.prank(creator);
    crowdfunding = new SimpleCrowdfunding(10 ether, 7 days);
}

// Time manipulation
vm.warp(block.timestamp + 7 days + 1); // Past deadline

// Check balances
assertEq(address(crowdfunding).balance, expectedBalance);
assertEq(alice.balance, expectedAliceBalance);
```

---

## Constructor

```solidity
constructor(uint256 goal, uint256 duration) {
    i_creator = msg.sender;
    i_goal = goal;
    i_deadline = block.timestamp + duration;
}
```

---

## Bonus Challenges (Optional)

1. Add minimum contribution amount
2. Add `getContributors()` that returns array of contributor addresses
3. Add campaign metadata (title as string, stored or emitted)
4. Allow creator to cancel before any contributions

---

## What You'll Learn

| Concept | Where |
|---------|-------|
| Time-based conditions | `block.timestamp < i_deadline` |
| Pull payment pattern | `refund()` function |
| State derived from data | No enum needed, derive from goal/deadline |
| CEI pattern | Check-Effects-Interactions in refund |
| Immutables | `i_creator`, `i_goal`, `i_deadline` |

---

## Comparison to Previous Days

| Day | Contract | Similarity |
|-----|----------|------------|
| 6 | SimpleEscrow | Two-party ETH transfers, state machine |
| 7 | SimpleVault | Time-based withdrawals |
| 8 | SimpleBet | Multiple participants, single winner |
| 10 | MultiSigWallet | ETH management, per-user tracking |

---

## Scope and Limitations

### In Scope
- Single campaign per contract
- ETH only (no tokens)
- Fixed goal and deadline
- Pull-based refunds

### Out of Scope (Future Days)
- Multiple campaigns in one contract
- Stretch goals / milestones
- Partial withdrawals
- Token rewards for contributors
- Campaign extensions

---

Good luck! This is a classic Web3 pattern. Focus on the state transitions and making sure refunds are safe.
