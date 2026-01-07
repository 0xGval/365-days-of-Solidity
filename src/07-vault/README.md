# 07 – Simple Vault

This phase introduces a **time-locked vault** for ETH deposits.

The goal is to reason about time-based conditions, per-user state tracking,
and penalty mechanisms for early withdrawals.

---

## SimpleVault

### Purpose

`SimpleVault` allows users to deposit ETH with a mandatory lock period.
Funds can only be withdrawn after the lock expires, unless the user
accepts an early withdrawal penalty.

The contract models individual vaults per user with time-based restrictions.

---

### Roles

- **Depositor**: any address that deposits ETH into their own vault
- **Fee Collector**: receives penalties from early withdrawals (set at deploy)

There is no owner role. Each user manages their own vault independently.

---

### Configuration (Set at Deploy)

| Parameter | Description |
|-----------|-------------|
| `lockDuration` | Time in seconds that deposits are locked |
| `earlyWithdrawFeeBps` | Penalty for early withdrawal in basis points (e.g., 1000 = 10%) |
| `feeCollector` | Address that receives early withdrawal fees |

---

### Per-User State

Each user has their own vault with:

- `balance`: total ETH deposited
- `unlockTime`: timestamp when funds become withdrawable

---

### Functional Overview

#### Deposits

- Any address can deposit ETH into their own vault
- Each deposit **adds** to the existing balance
- Each deposit **resets** the unlock time to `block.timestamp + lockDuration`
- Zero-value deposits are rejected

#### Normal Withdrawals

- `withdraw()`: withdraws entire balance after lock expires
- `withdrawPartial(amount)`: withdraws specified amount after lock expires
- Both revert if called before unlock time
- Both revert if user has no balance

#### Emergency Withdrawal

- `emergencyWithdraw()`: withdraws before lock expires with penalty
- Penalty is calculated as `balance * earlyWithdrawFeeBps / 10000`
- Fee is sent to `feeCollector`
- User receives `balance - fee`
- Available at any time, even if lock has expired (no penalty if unlocked)

#### Lock Extension

- `extendLock(extraSeconds)`: extends unlock time by specified duration
- Can only increase unlock time, never decrease
- Useful for users who want longer lock periods

---

### View Functions

| Function | Returns |
|----------|---------|
| `getVaultInfo(address)` | User's balance and unlock time |
| `isUnlocked(address)` | `true` if user can withdraw without penalty |
| `timeUntilUnlock(address)` | Seconds remaining until unlock (0 if already unlocked) |
| `calculatePenalty(address)` | Fee amount if user does emergency withdraw now |

---

### Events

All meaningful state changes are observable via events:

- `Deposited(address indexed user, uint256 amount, uint256 unlockTime)`
- `Withdrawn(address indexed user, uint256 amount)`
- `EmergencyWithdrawn(address indexed user, uint256 amountReceived, uint256 feePaid)`
- `LockExtended(address indexed user, uint256 newUnlockTime)`

---

### Custom Errors

| Error | Condition |
|-------|-----------|
| `NoDeposit()` | User has zero balance |
| `StillLocked()` | Withdrawal attempted before unlock |
| `InsufficientBalance()` | Partial withdrawal exceeds balance |
| `InvalidAmount()` | Zero amount specified |
| `InvalidExtension()` | Extension would not increase unlock time |

> **Note**: These errors use no parameters for simplicity. In future iterations,
> errors like `StillLocked(uint256 unlockTime)` or `InsufficientBalance(uint256 requested, uint256 available)`
> could provide more informative feedback to users and frontends.

---

### Design Constraints

- No owner or admin role
- Each user manages only their own vault
- No cross-user interactions
- No external dependencies
- Focus on time-based access control and penalty calculations

---

### Testing Strategy

Tests should cover:

1. **Deposits**: first deposit, additional deposits, zero-value rejection
2. **Normal withdrawals**: success after unlock, failure before unlock
3. **Partial withdrawals**: correct amount, insufficient balance
4. **Emergency withdrawals**: penalty calculation, fee distribution
5. **Lock extension**: valid extension, invalid (decreasing) extension
6. **View functions**: correct values in various states
7. **Edge cases**: unlock exactly at timestamp, multiple operations
