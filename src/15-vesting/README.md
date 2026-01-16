# 15 – Simple Vesting

A token vesting contract that releases tokens gradually to a beneficiary over time.
Commonly used for team allocations, investor unlocks, and advisor compensation.

This implementation introduces **linear vesting schedules**, **cliff periods**,
and reinforces time-based calculation patterns learned in previous days.

---

## SimpleVesting

### Purpose

`SimpleVesting` models a token release schedule with:
- A cliff period where no tokens are released
- Linear vesting after the cliff until full release
- Optional revocability by the owner
- Single beneficiary per contract instance

The contract holds tokens on behalf of the beneficiary and releases them
according to a predetermined schedule, ensuring gradual distribution.

---

### Roles

- **Owner**: deploys the contract, deposits tokens, can revoke (if revocable)
- **Beneficiary**: receives tokens over time, can claim vested tokens

---

### Functional Overview

- Owner deploys with beneficiary address, token address, cliff duration, and total vesting duration
- Owner specifies if the vesting is revocable at deployment
- Owner deposits the total token amount to be vested
- No tokens are releasable during the cliff period
- After the cliff, tokens vest linearly until the end of the vesting period
- Beneficiary can release vested tokens at any time (pulls available amount)
- If revocable, owner can revoke and recover unvested tokens
- Once revoked, beneficiary keeps already-vested tokens

---

### State

The contract tracks:

- `i_owner`: contract deployer (immutable)
- `i_beneficiary`: token recipient (immutable)
- `i_token`: ERC20 token address (immutable)
- `i_cliffDuration`: seconds before any tokens vest (immutable)
- `i_vestingDuration`: total vesting period in seconds (immutable)
- `i_revocable`: whether owner can revoke (immutable)
- `totalAmount`: total tokens deposited for vesting
- `startTime`: timestamp when vesting started (set on deposit)
- `released`: tokens already released to beneficiary
- `revoked`: whether vesting has been revoked

---

### Functions

#### Owner Functions

##### deposit(uint256 amount)

- Only owner can call
- Transfers tokens from owner to contract
- Can only be called once (sets startTime)
- Reverts if `amount == 0`
- Reverts if already deposited
- Reverts if token transfer fails
- Emits `TokensDeposited`

---

##### revoke()

- Only owner can call
- Only if contract is revocable
- Reverts if already revoked
- Reverts if vesting not started
- Calculates vested amount at revocation time
- Transfers unvested tokens back to owner
- Sets revoked to true
- Emits `VestingRevoked`

---

#### Beneficiary Functions

##### release()

- Only beneficiary can call
- Calculates releasable amount (vested minus already released)
- Reverts if nothing to release
- Updates released amount
- Transfers tokens to beneficiary
- Emits `TokensReleased`

---

#### View Functions

##### vestedAmount()

- Returns total tokens vested up to current timestamp
- Returns 0 if before cliff
- Returns totalAmount if after vesting end or revoked
- Linear interpolation between cliff and end

##### releasable()

- Returns tokens available to release now
- Formula: `vestedAmount() - released`

##### getVestingInfo()

- Returns full vesting state (beneficiary, token, amounts, timestamps, status)

##### getCliffEnd()

- Returns timestamp when cliff ends

##### getVestingEnd()

- Returns timestamp when vesting completes

---

### Events

##### TokensDeposited(address indexed owner, uint256 amount)

- Emitted when owner deposits tokens to start vesting

##### TokensReleased(address indexed beneficiary, uint256 amount)

- Emitted when beneficiary claims vested tokens

##### VestingRevoked(address indexed owner, uint256 amountRevoked)

- Emitted when owner revokes vesting and recovers unvested tokens

---

### Design Constraints

- Single beneficiary per contract
- Single token per contract
- One-time deposit (no top-ups)
- Linear vesting only (no step/milestone vesting)
- Cliff is part of total duration, not additional
- No partial revocation
- No beneficiary change after deployment
- No pause functionality

---

### Security Considerations

- Immutable beneficiary prevents recipient hijacking
- Immutable revocability prevents rule changes
- CEI pattern in release and revoke prevents reentrancy
- Released amount tracked before transfer
- Token transfer failures revert the transaction
- Owner cannot drain beneficiary's vested tokens
- Integer overflow protected by Solidity 0.8+
- View functions for transparency and off-chain verification

---

### Concepts Practiced

- External contract interaction (ERC20 token)
- Time-based linear calculations
- Cliff logic implementation
- Immutable deployment parameters
- Pull-based token distribution
- Revocation with fair split
- State flags (revoked)
- Interface usage (IERC20)

---

### Test Scenarios to Cover

#### Constructor
- Sets owner correctly
- Sets beneficiary correctly
- Sets token address correctly
- Sets cliff duration correctly
- Sets vesting duration correctly
- Sets revocable flag correctly
- Reverts if beneficiary is zero address
- Reverts if token is zero address
- Reverts if cliff > vesting duration
- Reverts if vesting duration is zero

#### Deposit
- Only owner can deposit
- Sets totalAmount correctly
- Sets startTime correctly
- Transfers tokens from owner
- Reverts if amount is zero
- Reverts if already deposited
- Reverts if insufficient allowance
- Emits TokensDeposited event

#### Vesting Calculation
- Returns 0 before deposit
- Returns 0 during cliff period
- Returns partial amount after cliff
- Returns full amount after vesting end
- Linear progression between cliff and end
- Correct calculation at exact boundaries

#### Release
- Only beneficiary can call
- Returns correct token amount
- Updates released correctly
- Reverts if nothing to release
- Reverts before deposit
- Reverts during cliff
- Multiple releases accumulate correctly
- Emits TokensReleased event

#### Revoke
- Only owner can call
- Only works if revocable
- Reverts if not revocable
- Reverts if already revoked
- Reverts if not started
- Returns unvested tokens to owner
- Beneficiary keeps vested portion
- Sets revoked flag
- Emits VestingRevoked event
- No further vesting after revoke

#### Edge Cases
- Release at exact cliff boundary
- Release at exact vesting end
- Revoke at exact cliff boundary
- Revoke when fully vested (owner gets nothing)
- Multiple release calls (no double-claim)
- View functions with no deposit yet

---

### Not Implemented (Future Learning)

- Multiple beneficiaries
- Multiple tokens
- Step/milestone vesting
- Vesting acceleration
- Beneficiary transfer
- Top-up deposits
- Vesting pause
- Governance integration
- Cliff as additional period
- Vesting factory pattern

---

## License

GPL-3.0
