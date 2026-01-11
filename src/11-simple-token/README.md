# 11 – Simple Token

This phase introduces a fungible token contract implementing core ERC20
mechanics from scratch, without inheriting from external libraries.

The goal is to deeply understand token allowances, delegated transfers,
and the approval pattern that powers DeFi interactions.

---

## SimpleToken

### Purpose

`SimpleToken` implements a fungible token with owner-controlled minting,
a fixed maximum supply, and full allowance-based transfer delegation.

The contract models how tokens flow between addresses and how third parties
can be authorized to move tokens on behalf of holders.

---

### Roles

- **Owner**: deploys the contract, controls minting
- **Token Holders**: can transfer, approve spenders, and manage allowances
- **Spenders**: approved third parties that can transfer tokens on behalf of holders

---

### Functional Overview

- The token is deployed with name, symbol, decimals, and maximum supply
- Only the owner can mint new tokens (up to maxSupply)
- Holders can transfer their own tokens directly
- Holders can approve spenders to transfer on their behalf
- Spenders can transfer tokens using the allowance granted to them
- Allowances can be increased or decreased without full reset
- All transfers and approvals emit events for off-chain tracking

---

### State

The contract tracks:

- `owner`: the minting authority (immutable)
- `name`: token name (immutable)
- `symbol`: token symbol (immutable)
- `decimals`: decimal places for display (immutable)
- `maxSupply`: hard cap on total tokens (immutable)
- `totalSupply`: current circulating supply
- `balances`: per-address token balances
- `allowances`: nested mapping of owner → spender → amount

---

### Functions

#### Minting

##### mint(address to, uint256 amount)

- Only owner can call
- Increases totalSupply and receiver balance
- Reverts if totalSupply + amount > maxSupply
- Reverts if `to` is zero address
- Emits `Transfer(address(0), to, amount)`

---

#### Direct Transfers

##### transfer(address to, uint256 amount)

- Caller transfers from their own balance
- Reverts if caller has insufficient balance
- Reverts if `to` is zero address
- Emits `Transfer(from, to, amount)`
- Returns `true` on success

---

#### Allowance System

##### approve(address spender, uint256 amount)

- Sets exact allowance for spender
- Overwrites any existing allowance
- Reverts if `spender` is zero address
- Emits `Approval(owner, spender, amount)`
- Returns `true` on success

##### transferFrom(address from, address to, uint256 amount)

- Spender transfers tokens from `from` to `to`
- Requires sufficient allowance
- Decreases allowance by amount spent
- Reverts if insufficient balance or allowance
- Reverts if `to` is zero address
- Emits `Transfer(from, to, amount)`
- Returns `true` on success

##### increaseAllowance(address spender, uint256 addedValue)

- Increases current allowance by addedValue
- Safer than approve for incremental changes
- Reverts if `spender` is zero address
- Emits `Approval` with new total allowance
- Returns `true` on success

##### decreaseAllowance(address spender, uint256 subtractedValue)

- Decreases current allowance by subtractedValue
- Reverts if subtractedValue > current allowance
- Reverts if `spender` is zero address
- Emits `Approval` with new total allowance
- Returns `true` on success

---

#### View Functions

##### balanceOf(address account)

- Returns token balance of account

##### allowance(address owner, address spender)

- Returns current allowance granted by owner to spender

##### name(), symbol(), decimals()

- Return token metadata

##### totalSupply(), maxSupply()

- Return supply information

---

### Events

##### Transfer(address indexed from, address indexed to, uint256 value)

- Emitted on transfer, transferFrom, and mint
- For minting, `from` is `address(0)`

##### Approval(address indexed owner, address indexed spender, uint256 value)

- Emitted on approve, increaseAllowance, decreaseAllowance
- `value` is the new total allowance (not delta)

---

### Design Constraints

- No burn functionality
- No permit (EIP-2612) signatures
- No hooks or callbacks
- No external libraries
- Owner is immutable (set at deployment)
- Focus on correctness and explicit state management

---

### Security Considerations

- Owner immutability prevents ownership hijacking
- Zero-address checks on all transfers and approvals
- Allowance decrease checks for underflow
- No reentrancy risk (no external calls)
- Integer overflow protected by Solidity 0.8+
- Approve race condition: users should use increase/decrease helpers

---

### Concepts Practiced

- Nested mappings (allowances)
- Delegated authorization pattern
- ERC20 event standards
- View vs state-changing functions
- Return values for interface compliance
- Immutable deployment parameters

---

### Not Implemented (Future Learning)

- Burn functionality
- Permit (gasless approvals via signatures)
- Hooks (beforeTransfer, afterTransfer)
- Pausable functionality
- Blacklist/whitelist
- Full ERC20 interface declaration

---

## License

GPL-3.0
