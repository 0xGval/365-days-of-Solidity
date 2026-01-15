# 14 – Simple Staking

A staking contract where users lock ETH for a minimum period to earn rewards.
Rewards are distributed from a pool funded by the contract owner.

This implementation introduces **reward calculation mechanics**, **time-based accrual**,
and reinforces ETH custody patterns learned in previous days.

---

## SimpleStaking

### Purpose

`SimpleStaking` models a basic staking system with:
- A minimum lock period before unstaking
- Linear reward accrual based on amount and time
- A reward pool managed by the owner
- Individual stake tracking per user

The contract handles ETH custody for both staked funds and rewards,
tracks per-user stake information, and enforces time-based withdrawal rules.

---

### Roles

- **Owner**: deploys the contract, funds the reward pool, sets staking parameters
- **Stakers**: deposit ETH, earn rewards over time, withdraw after lock period

---

### Functional Overview

- Owner deploys with a minimum lock period and reward rate
- Owner deposits ETH into the reward pool to fund rewards
- Anyone can stake ETH (one active stake per address)
- Rewards accrue linearly: `reward = amount × time × rate / PRECISION`
- Stakers can claim accrued rewards at any time (if reward pool has funds)
- Stakers can unstake only after the lock period expires
- Unstaking returns principal + any unclaimed rewards
- Staked funds and reward pool are tracked separately

---

### State

The contract tracks:

- `i_owner`: contract deployer (immutable)
- `i_minLockPeriod`: minimum seconds before unstaking allowed (immutable)
- `i_rewardRatePerSecond`: reward rate in wei per ETH per second (immutable)
- `rewardPool`: ETH available for reward distribution
- `totalStaked`: sum of all active stakes
- `stakes`: mapping of address → Stake struct

#### Stake Struct

```solidity
struct Stake {
    uint256 amount;         // ETH staked
    uint256 stakedAt;       // timestamp when staked
    uint256 rewardsClaimed; // rewards already claimed
}
```

---

### Functions

#### Owner Functions

##### depositRewards()

- Only owner can call
- Accepts ETH to add to reward pool
- Reverts if `msg.value == 0`
- Emits `RewardsDeposited`

---

#### Staker Functions

##### stake()

- Accepts ETH as stake
- Reverts if `msg.value == 0`
- Reverts if caller already has an active stake
- Records amount, timestamp, and initializes rewardsClaimed to 0
- Updates totalStaked
- Emits `Staked`

---

##### unstake()

- Returns staked ETH plus any unclaimed rewards
- Reverts if caller has no active stake
- Reverts if lock period has not passed (`block.timestamp < stakedAt + minLockPeriod`)
- Calculates unclaimed rewards
- Caps rewards to available reward pool
- Zeroes stake before transfer (CEI pattern)
- Updates totalStaked and rewardPool
- Transfers principal + rewards to caller
- Emits `Unstaked`

---

##### claimRewards()

- Claims accrued rewards without unstaking
- Reverts if caller has no active stake
- Calculates rewards accrued since last claim
- Reverts if no rewards to claim
- Caps rewards to available reward pool
- Updates rewardsClaimed in stake
- Deducts from rewardPool
- Transfers rewards to caller
- Emits `RewardsClaimed`

---

#### View Functions

##### calculateRewards(address staker)

- Returns total rewards accrued for staker
- Returns 0 if staker has no active stake
- Formula: `(amount × timeStaked × rewardRate) / PRECISION`

##### getUnclaimedRewards(address staker)

- Returns rewards accrued minus rewards already claimed
- Used to determine claimable amount

##### getStakeInfo(address staker)

- Returns stake struct (amount, stakedAt, rewardsClaimed)

##### canUnstake(address staker)

- Returns true if lock period has passed
- Returns false if no stake or still locked

---

### Events

##### RewardsDeposited(address indexed owner, uint256 amount)

- Emitted when owner adds ETH to reward pool

##### Staked(address indexed staker, uint256 amount)

- Emitted when user stakes ETH

##### Unstaked(address indexed staker, uint256 principal, uint256 rewards)

- Emitted when user withdraws stake and rewards

##### RewardsClaimed(address indexed staker, uint256 amount)

- Emitted when user claims rewards without unstaking

---

### Design Constraints

- One stake per address (no multiple positions)
- ETH only (no token staking)
- Fixed reward rate (immutable)
- Fixed lock period (immutable)
- Linear reward calculation (no compounding)
- Rewards capped to available pool (no debt)
- No partial unstaking (all or nothing)
- No reward rate changes after deployment
- No slashing or penalties

---

### Security Considerations

- Owner immutability prevents ownership hijacking
- Lock period immutability prevents rule changes
- CEI pattern in unstake and claimRewards prevents reentrancy
- Stake zeroed before transfer
- Rewards capped to pool balance (cannot overdraw)
- No external calls except ETH transfers
- Integer overflow protected by Solidity 0.8+
- PRECISION constant prevents rounding to zero

---

### Concepts Practiced

- Time-based reward calculation
- Reward accrual tracking (rewardsClaimed)
- Separate pool management (staked vs rewards)
- CEI pattern (Checks-Effects-Interactions)
- Immutable deployment parameters
- Per-user state with structs
- View functions for off-chain queries
- Mathematical precision handling

---

### Test Scenarios to Cover

#### Constructor
- Sets owner correctly
- Sets minLockPeriod correctly
- Sets rewardRatePerSecond correctly
- Reverts if minLockPeriod is zero
- Reverts if rewardRate is zero

#### Deposit Rewards
- Only owner can deposit
- Increases rewardPool correctly
- Reverts if msg.value is zero
- Emits RewardsDeposited event

#### Staking
- Accepts ETH and creates stake
- Records correct timestamp
- Updates totalStaked
- Reverts if already staked
- Reverts if msg.value is zero
- Emits Staked event

#### Unstaking
- Returns principal after lock period
- Returns principal plus rewards
- Reverts before lock period ends
- Reverts if no active stake
- Updates totalStaked correctly
- Caps rewards to available pool
- Emits Unstaked event

#### Claiming Rewards
- Returns correct reward amount
- Updates rewardsClaimed
- Reverts if no stake
- Reverts if no rewards to claim
- Caps rewards to available pool
- Does not affect principal
- Emits RewardsClaimed event

#### Reward Calculation
- Rewards increase over time
- Rewards proportional to stake amount
- Returns zero for non-staker
- Accounts for already claimed rewards

#### Edge Cases
- Stake when reward pool is empty (stake works, no rewards)
- Claim when reward pool insufficient (partial claim)
- Multiple users staking simultaneously
- Unstake at exact lock period boundary

---

### Not Implemented (Future Learning)

- Multiple stakes per address
- Variable reward rates
- Compounding rewards
- Token staking (ERC20)
- Reward boosters / multipliers
- Slashing conditions
- Minimum stake amounts
- Maximum stake caps
- Emergency withdrawal (with penalty)
- Reward distribution end time

---

## License

GPL-3.0
