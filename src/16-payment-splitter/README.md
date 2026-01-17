# 16 – Simple Payment Splitter

A contract that receives ETH and distributes it proportionally among multiple beneficiaries based on predefined shares.
Commonly used for revenue sharing, royalty splits, and team payment distribution.

This implementation introduces **proportional distribution mechanics**, **multi-beneficiary tracking**,
and reinforces ETH custody patterns learned in previous days.

---

## SimplePaymentSplitter

### Purpose

`SimplePaymentSplitter` models a payment distribution system with:
- Multiple payees defined at deployment
- Fixed shares determining each payee's proportion
- Automatic tracking of received and released amounts
- Pull-based withdrawals for each payee

The contract holds ETH on behalf of all payees and allows each to withdraw
their proportional share of all funds ever received.

---

### Roles

- **Payees**: receive proportional ETH distributions, can release their share at any time
- **Anyone**: can send ETH to the contract, can trigger release for any payee

---

### Functional Overview

- Deployer specifies payees array and corresponding shares array
- Payees and shares are immutable after deployment
- Anyone can send ETH to the contract (via `receive()`)
- Each payee's entitlement is calculated as: `(totalReceived × shares) / totalShares`
- Each payee can release their pending amount at any time
- Anyone can call `release()` on behalf of any payee
- Released amounts are tracked per payee to prevent double-claims
- Contract tracks total received (balance + already released)

---

### State

The contract tracks:

- `totalShares`: sum of all payee shares (immutable after constructor)
- `totalReleased`: total ETH already distributed to all payees
- `shares`: mapping of address → share amount
- `released`: mapping of address → ETH already released to that payee
- `payees`: array of all payee addresses

---

### Functions

#### Receive

##### receive()

- Accepts incoming ETH
- No restrictions on sender or amount
- Emits `PaymentReceived`

---

#### Release Functions

##### release(address payable account)

- Calculates pending payment for account
- Reverts if account has no shares
- Reverts if no payment is due (pending == 0)
- Updates `released[account]` before transfer (CEI pattern)
- Updates `totalReleased`
- Transfers ETH to account
- Emits `PaymentReleased`

---

#### View Functions

##### totalReceived()

- Returns total ETH ever received by contract
- Formula: `address(this).balance + totalReleased`

##### releasable(address account)

- Returns pending amount for account
- Formula: `(totalReceived() × shares[account] / totalShares) - released[account]`
- Returns 0 if account has no shares

##### getShares(address account)

- Returns share amount for account
- Returns 0 if not a payee

##### getReleased(address account)

- Returns ETH already released to account

##### getPayees()

- Returns array of all payee addresses

##### getPayee(uint256 index)

- Returns payee address at index
- Reverts if index out of bounds

---

### Events

##### PayeeAdded(address indexed account, uint256 shares)

- Emitted for each payee during construction

##### PaymentReceived(address indexed from, uint256 amount)

- Emitted when ETH is received

##### PaymentReleased(address indexed to, uint256 amount)

- Emitted when ETH is released to a payee

---

### Design Constraints

- Payees and shares fixed at deployment (no additions/removals)
- No minimum payment amount
- No owner role (fully decentralized after deployment)
- Pull-based only (no automatic push distributions)
- Integer division may leave dust in contract
- No way to recover stuck dust
- ETH only (no token splitting)
- Anyone can trigger release for any payee

---

### Security Considerations

- Payees array immutability prevents manipulation after deployment
- Shares immutability prevents rule changes
- CEI pattern in release prevents reentrancy
- Released amount updated before transfer
- No external calls except ETH transfers
- Zero address check in constructor
- Duplicate payee check in constructor
- Integer overflow protected by Solidity 0.8+
- Division by zero impossible (totalShares > 0 enforced)

---

### Concepts Practiced

- Multi-beneficiary state tracking
- Proportional calculation with integer math
- Pull-based payment pattern
- Array iteration in constructor
- Mapping and array coordination
- Immutable state after deployment
- Constructor validation (arrays match, no zeros, no duplicates)
- View functions for off-chain queries

---

### Test Scenarios to Cover

#### Constructor
- Sets payees array correctly
- Sets shares mapping correctly
- Sets totalShares correctly
- Emits PayeeAdded for each payee
- Reverts if payees array is empty
- Reverts if arrays have different lengths
- Reverts if any payee is zero address
- Reverts if any share is zero
- Reverts if duplicate payee address

#### Receiving ETH
- Accepts ETH via receive()
- Accepts ETH from any sender
- Emits PaymentReceived event
- Updates totalReceived correctly

#### Release
- Releases correct amount to payee
- Updates released mapping correctly
- Updates totalReleased correctly
- Reverts if account has no shares
- Reverts if nothing to release
- Emits PaymentReleased event
- Anyone can call release for any payee

#### Releasable Calculation
- Returns 0 for non-payee
- Returns 0 when nothing received
- Returns 0 after full release
- Correct proportional calculation
- Accounts for already released amounts
- Handles multiple deposits correctly

#### View Functions
- totalReceived returns balance + totalReleased
- getShares returns correct share
- getReleased returns correct amount
- getPayees returns full array
- getPayee returns correct address at index
- getPayee reverts on invalid index

#### Multi-Payee Scenarios
- Two payees with equal shares (50/50)
- Three payees with unequal shares (50/30/20)
- Multiple deposits over time
- Partial releases (some payees claim, others don't)
- All payees release at different times
- Correct distribution after multiple deposits

#### Edge Cases
- Single payee (100% share)
- Large number of payees
- Very small payment amounts (dust)
- Release when balance is zero but totalReceived > 0
- Integer division rounding

---

### Not Implemented (Future Learning)

- Dynamic payee management (add/remove)
- Owner role for administration
- Token splitting (ERC20)
- Minimum release amounts
- Push-based distribution
- Dust recovery mechanism
- Weighted voting for changes
- Release scheduling
- Fee mechanism
- Factory pattern for deployment

---

## License

GPL-3.0
