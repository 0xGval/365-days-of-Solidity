# 18 – SimpleShares (Friend.tech-inspired)

## Purpose

A basic implementation of Friend.tech's social trading mechanics where users buy and sell "shares" of registered subjects. Share prices follow a quadratic bonding curve, creating speculative markets around social identity. This contract introduces **bonding curves**, **nested mappings**, and **dual-fee systems**.

> **Note**: This is a simplified version for learning purposes. A more advanced implementation with additional features (slippage protection, referrals, ERC1155 integration) will be covered in future days.

## Key Roles

| Role | Description |
|------|-------------|
| **Owner** | Deploys the contract; receives protocol fees on every trade |
| **Subject** | Registers via signup; must buy their first share to activate trading; earns fees when their shares are traded |
| **Trader** | Buys and sells shares of active subjects; speculates on social value |

## States

```
┌─────────────────┐         ┌─────────────────┐         ┌─────────────────┐
│                 │         │                 │         │                 │
│  Unregistered   │──────►  │   Registered    │──────►  │     Active      │
│                 │ signUp  │  (supply = 0)   │ buyFirst│  (supply >= 1)  │
│                 │         │                 │  Share  │                 │
└─────────────────┘         └─────────────────┘         └─────────────────┘
```

| State | Description |
|-------|-------------|
| **Unregistered** | Address has not signed up; shares cannot be traded |
| **Registered** | Address signed up but hasn't bought first share; trading not yet active |
| **Active** | Subject bought first share; anyone can now buy/sell their shares |

## Functional Overview

### Subject Registration
- Subject calls `signUp(username)` to register
- Sets `isRegistered[subject] = true`
- Initializes supply to 0 and records metadata

### First Share Purchase
- Subject calls `buyFirstShare()` to activate trading
- Only the subject can buy their first share (prevents squatting)
- First share is free (price at supply 0 = 0)
- Sets supply to 1 and activates trading

### Buying Shares
- Trader calls `buyShares(subject, amount)` with sufficient ETH
- Price calculated using quadratic bonding curve
- Subject fee (5%) sent to subject
- Protocol fee (5%) sent to owner
- Excess ETH refunded to buyer

### Selling Shares
- Trader calls `sellShares(subject, amount)`
- Price calculated using bonding curve
- Fees deducted from proceeds
- Non-subjects cannot sell the last share (prevents locking subject)

## Bonding Curve

The price follows a quadratic curve where each share costs its position squared:

```
price(n) = n² × PRICE_MULTIPLIER
```

| Supply | Price per Share | Notes |
|--------|-----------------|-------|
| 0 → 1  | 0 ETH           | First share free |
| 1 → 2  | ~0.0000625 ETH  | Second share |
| 10 → 11| ~0.00625 ETH    | Price grows quadratically |
| 100→101| ~0.625 ETH      | Expensive at high supply |

**Sum Formula** (to avoid loops):
```
Σi² from 0 to n = n(n+1)(2n+1) / 6
```

## Fee System

| Fee Type | Percentage | Recipient |
|----------|------------|-----------|
| Subject Fee | 5% (500 basis points) | The subject whose shares are traded |
| Protocol Fee | 5% (500 basis points) | Contract owner |
| **Total** | **10%** | |

```
Buy:  totalCost = price + subjectFee + protocolFee
Sell: proceeds  = price - subjectFee - protocolFee
```

## Implementation Details

### Immutable Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `i_owner` | `address` | Protocol fee recipient |
| `i_subjectFeePercent` | `uint256` | Subject fee in basis points (max 5000) |
| `i_protocolFeePercent` | `uint256` | Protocol fee in basis points (max 5000) |

### Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `PRICE_MULTIPLIER` | `1 ether / 16000` | Scaling factor for bonding curve |
| `BASIS_POINTS` | `10000` | Denominator for percentage calculations |

### State Variables

| Variable | Type | Description |
|----------|------|-------------|
| `isRegistered` | `mapping(address => bool)` | Whether address has signed up |
| `sharesSupply` | `mapping(address => uint256)` | Total shares per subject |
| `sharesBalance` | `mapping(address => mapping(address => uint256))` | Nested mapping: `[subject][holder] => amount` |
| `subjectData` | `mapping(address => SubjectInfo)` | Metadata per subject |

### SubjectInfo Struct

```solidity
struct SubjectInfo {
    uint256 registeredAt;      // Timestamp of signup
    uint256 totalVolume;       // Cumulative trading volume
    uint256 totalFeesEarned;   // Total subject fees earned
    string username;           // Display name
}
```

### Events

| Event | Parameters | When Emitted |
|-------|------------|--------------|
| `Registered` | `user` (indexed) | Subject signs up |
| `Trade` | `user` (indexed), `target` (indexed), `firstBuy` | Any share trade |

### Custom Errors

| Error | When |
|-------|------|
| `AlreadyRegistered()` | Calling signUp when already registered |
| `NotRegistered()` | Calling buyFirstShare without signup |
| `AlreadyHasShares()` | Calling buyFirstShare when supply > 0 |
| `InvalidUsername()` | Empty username in signUp |
| `InvalidAmount()` | Amount is zero |
| `InvalidSubject()` | Subject is zero address |
| `SubjectNotRegistered()` | Buying shares of unregistered subject |
| `SubjectNotActive()` | Buying shares before subject bought first share |
| `InsufficientPayment()` | msg.value < required cost |
| `InsufficientShares()` | Selling more shares than owned |
| `CannotSellLastShare()` | Non-subject trying to reduce supply to 0 |
| `TransferFailed()` | ETH transfer failed |
| `FeeTooHigh()` | Fee percentage exceeds 50% |

## Security Considerations

1. **Reentrancy**: Uses CEI pattern - all state updates before external calls

2. **First Share Attack**: Only the subject can buy their first share, preventing squatting/front-running

3. **Last Share Protection**: Non-subjects cannot reduce supply to 0, preventing subject lockout

4. **Fee Validation**: Constructor rejects fees > 50% to prevent malicious deployments

5. **Integer Overflow**: Protected by Solidity 0.8+ checked arithmetic

6. **MEV/Sandwich Attacks**: Not mitigated in this basic version (see future improvements)

## Key Solidity Concepts Practiced

- **Bonding Curves**: Algorithmic price discovery based on supply
- **Nested Mappings**: `mapping(address => mapping(address => uint256))`
- **Sum of Squares Formula**: Mathematical optimization to avoid loops
- **Basis Points**: Precise percentage calculations (10000 = 100%)
- **Multiple ETH Transfers**: Handling subject fee, protocol fee, and refunds
- **CEI Pattern**: Checks-Effects-Interactions for reentrancy protection

## Test Scenarios to Cover

### Constructor Tests
- [ ] Deploys with correct owner
- [ ] Sets fee percentages correctly
- [ ] Reverts if subject fee > 50%
- [ ] Reverts if protocol fee > 50%

### SignUp Tests
- [ ] User can register successfully
- [ ] Registered event emitted
- [ ] Reverts if already registered
- [ ] Reverts if username empty
- [ ] Multiple users can register independently

### First Share Tests
- [ ] Subject can buy first share after signup
- [ ] First share is free
- [ ] Supply becomes 1
- [ ] isSubjectActive returns true
- [ ] Reverts if not registered
- [ ] Reverts if already has shares

### Buy Shares Tests
- [ ] Can buy shares of active subject
- [ ] Correct price calculated
- [ ] Subject receives fee
- [ ] Owner receives fee
- [ ] Excess ETH refunded
- [ ] Reverts if amount is 0
- [ ] Reverts if subject not registered
- [ ] Reverts if subject not active
- [ ] Reverts if insufficient payment

### Sell Shares Tests
- [ ] Can sell owned shares
- [ ] Correct proceeds calculated
- [ ] Fees deducted correctly
- [ ] Reverts if amount is 0
- [ ] Reverts if insufficient shares
- [ ] Reverts if non-subject sells last share
- [ ] Subject CAN sell last share

### Price Calculation Tests
- [ ] First share price is 0
- [ ] Price increases with supply
- [ ] getBuyPriceAfterFee adds fees
- [ ] getSellPriceAfterFee subtracts fees

### Integration Scenarios
- [ ] Full flow: signUp → buyFirstShare → others buy → sell
- [ ] Multiple subjects operate independently
- [ ] Fee accumulation across trades

## Not Implemented (Future Learning)

- **Slippage Protection**: `maxPrice` parameter to prevent sandwich attacks
- **Referral System**: Fee split for referrers
- **ERC1155 Integration**: Shares as semi-fungible tokens
- **Share Transfers**: P2P trading between users
- **Dynamic Fees**: Fees that adjust based on volume
- **Supply Caps**: Maximum shares per subject
- **Chainlink VRF**: For any randomness needs
- **Emergency Pause**: Circuit breaker for exploits

## Comparison with Friend.tech

| Feature | Friend.tech | SimpleShares |
|---------|-------------|--------------|
| Bonding Curve | Quadratic (supply²) | Quadratic (supply²) |
| Subject Fee | 5% | 5% |
| Protocol Fee | 5% | 5% |
| First Share | Subject only | Subject only |
| Registration | Implicit | Explicit (signUp) |
| Chain | Base | Any EVM |
| Slippage Protection | Yes | No (future) |
| Referrals | Yes | No (future) |

## Hints (if you get stuck)

<details>
<summary>Hint 1: Sum of Squares Formula</summary>

```solidity
function sumOfSquares(uint256 n) internal pure returns (uint256) {
    return (n * (n + 1) * (2 * n + 1)) / 6;
}
```

</details>

<details>
<summary>Hint 2: Price Calculation</summary>

```solidity
function getPrice(uint256 supply, uint256 amount) public pure returns (uint256) {
    uint256 sum1 = supply == 0 ? 0 : sumOfSquares(supply - 1);
    uint256 sum2 = sumOfSquares(supply + amount - 1);
    return (sum2 - sum1) * PRICE_MULTIPLIER;
}
```

</details>

<details>
<summary>Hint 3: Nested Mapping Access</summary>

```solidity
// Reading
uint256 balance = sharesBalance[subject][holder];

// Writing
sharesBalance[subject][msg.sender] += amount;
```

</details>

<details>
<summary>Hint 4: Fee Calculation</summary>

```solidity
uint256 subjectFee = (price * i_subjectFeePercent) / BASIS_POINTS;
uint256 protocolFee = (price * i_protocolFeePercent) / BASIS_POINTS;
```

</details>
