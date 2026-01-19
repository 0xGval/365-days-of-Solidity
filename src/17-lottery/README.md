# 17 – SimpleLottery

## Purpose

A decentralized lottery where participants buy tickets with ETH, and after a deadline, a winner is selected pseudo-randomly to claim the entire prize pool. This contract introduces **on-chain pseudo-randomness** using `blockhash` and explores its security limitations.

## Key Roles

| Role | Description |
|------|-------------|
| **Owner** | Deploys the lottery with parameters; can cancel if minimum players not reached |
| **Player** | Buys one or more tickets; can request refund if lottery is cancelled |
| **Winner** | The randomly selected player who can claim the prize pool |

## States

```
┌─────────────┐      deadline reached       ┌─────────────┐
│             │      & minPlayers met       │             │
│    Open     │ ─────────────────────────►  │   Drawing   │
│             │                             │             │
└─────────────┘                             └─────────────┘
      │                                           │
      │ deadline reached                          │ winner revealed
      │ & minPlayers NOT met                      │
      ▼                                           ▼
┌─────────────┐                             ┌─────────────┐
│             │                             │             │
│  Cancelled  │                             │  Completed  │
│             │                             │             │
└─────────────┘                             └─────────────┘
```

| State | Description |
|-------|-------------|
| **Open** | Players can buy tickets; lottery is accepting participants |
| **Drawing** | Ticket sales closed; waiting for winner to be revealed |
| **Completed** | Winner selected and prize claimed (or claimable) |
| **Cancelled** | Minimum players not reached; refunds available |

## Functional Overview

### Ticket Purchase
- Players call `buyTicket()` sending exactly `ticketPrice` ETH
- Each purchase adds the player's address to the players array
- A player can buy multiple tickets (multiple entries = higher chance)
- Purchases only allowed during `Open` state and before deadline

### Drawing Mechanism (Two-Step Process)

**Why two steps?** To mitigate miner manipulation of `blockhash`.

1. **`draw()`** - Called after deadline if minPlayers reached
   - Records `drawBlock = block.number`
   - Transitions state to `Drawing`
   - Does NOT select winner yet

2. **`revealWinner()`** - Called in a subsequent transaction
   - Must be called within 256 blocks of `drawBlock` (blockhash limitation)
   - Uses `blockhash(drawBlock + 1)` as random seed
   - Selects winner: `winnerIndex = randomSeed % players.length`
   - Transitions state to `Completed`

### Prize Claim
- Winner calls `claimPrize()` to withdraw the entire prize pool
- Pull-based payment pattern (winner withdraws, not pushed)

### Cancellation & Refunds
- If deadline passes and `minPlayers` not reached, owner can call `cancel()`
- Players can then call `refund()` to get their ETH back
- Must track each player's total contribution (they may have bought multiple tickets)

## Implementation Details

### Immutable Parameters (set at deployment)

| Parameter | Type | Description |
|-----------|------|-------------|
| `i_ticketPrice` | `uint256` | Cost of one ticket in wei |
| `i_minPlayers` | `uint256` | Minimum tickets for lottery to proceed |
| `i_maxPlayers` | `uint256` | Maximum tickets allowed (prevents gas issues) |
| `i_deadline` | `uint256` | Timestamp when ticket sales end |
| `i_owner` | `address` | Deployer address |

### State Variables

| Variable | Type | Description |
|----------|------|-------------|
| `s_players` | `address[]` | Array of player addresses (duplicates allowed for multiple tickets) |
| `s_contributions` | `mapping(address => uint256)` | Total ETH contributed per player (for refunds) |
| `s_state` | `State` | Current lottery state |
| `s_drawBlock` | `uint256` | Block number when draw() was called |
| `s_winner` | `address` | Selected winner address |
| `s_prizeClaimed` | `bool` | Whether prize has been claimed |

### Events

| Event | Parameters | When Emitted |
|-------|------------|--------------|
| `TicketPurchased` | `player` (indexed), `ticketNumber` | Player buys a ticket |
| `DrawInitiated` | `drawBlock` | draw() is called |
| `WinnerRevealed` | `winner` (indexed), `prize` | Winner is selected |
| `PrizeClaimed` | `winner` (indexed), `amount` | Winner withdraws prize |
| `LotteryCancelled` | - | Lottery is cancelled |
| `RefundClaimed` | `player` (indexed), `amount` | Player gets refund |

### Custom Errors

| Error | When |
|-------|------|
| `LotteryNotOpen()` | Trying to buy ticket when not in Open state |
| `IncorrectTicketPrice()` | Sent ETH doesn't match ticket price |
| `MaxPlayersReached()` | Lottery is full |
| `DeadlineNotReached()` | Trying to draw before deadline |
| `MinPlayersNotReached()` | Trying to draw without enough players |
| `NotInDrawingState()` | Trying to reveal winner when not in Drawing state |
| `TooEarlyToReveal()` | Trying to reveal in same block as draw |
| `TooLateToReveal()` | More than 256 blocks passed since draw |
| `NotWinner()` | Non-winner trying to claim prize |
| `PrizeAlreadyClaimed()` | Winner trying to claim twice |
| `NotCancelled()` | Trying to refund when lottery not cancelled |
| `NoContribution()` | Trying to refund with zero contribution |
| `TransferFailed()` | ETH transfer failed |

### Security Considerations

1. **Blockhash Limitation**: `blockhash(n)` returns `bytes32(0)` for blocks older than 256 blocks. The reveal must happen within this window.

2. **Miner Manipulation**: A miner could theoretically see the outcome and choose not to publish a block. The two-step process makes this attack more expensive but doesn't eliminate it entirely.

3. **Front-running**: Since `revealWinner()` is deterministic once `drawBlock` is set, front-running doesn't help an attacker.

4. **CEI Pattern**: Always update state before external calls.

5. **Reentrancy**: Use checks-effects-interactions; consider if reentrancy guard is needed.

### Key Solidity Concepts Practiced

- `blockhash(uint256 blockNumber)` - returns hash of given block (only for last 256 blocks)
- `block.number` - current block number
- `block.timestamp` - current block timestamp
- Array management with dynamic sizing
- Mapping for contribution tracking
- Two-step commit-reveal pattern (applied to randomness)

## Test Scenarios to Cover

### Constructor Tests
- [ ] Deploys with valid parameters
- [ ] Reverts if ticketPrice is zero
- [ ] Reverts if minPlayers is zero
- [ ] Reverts if maxPlayers < minPlayers
- [ ] Reverts if deadline is in the past

### Ticket Purchase Tests
- [ ] Player can buy one ticket
- [ ] Player can buy multiple tickets
- [ ] Reverts if wrong ETH amount sent
- [ ] Reverts if lottery is full (maxPlayers)
- [ ] Reverts if deadline passed
- [ ] Reverts if lottery not in Open state
- [ ] TicketPurchased event emitted correctly

### Draw Tests
- [ ] Owner can call draw after deadline with enough players
- [ ] Anyone can call draw (not just owner) - design choice
- [ ] Reverts if deadline not reached
- [ ] Reverts if minPlayers not reached
- [ ] Reverts if not in Open state
- [ ] DrawInitiated event emitted
- [ ] State transitions to Drawing

### Reveal Winner Tests
- [ ] Winner is selected correctly
- [ ] Reverts if called in same block as draw
- [ ] Reverts if called after 256 blocks
- [ ] Reverts if not in Drawing state
- [ ] WinnerRevealed event emitted
- [ ] State transitions to Completed

### Prize Claim Tests
- [ ] Winner can claim full prize pool
- [ ] Reverts if caller is not winner
- [ ] Reverts if prize already claimed
- [ ] Reverts if not in Completed state
- [ ] PrizeClaimed event emitted
- [ ] Contract balance is zero after claim

### Cancellation Tests
- [ ] Owner can cancel if deadline passed and minPlayers not reached
- [ ] Reverts if minPlayers was reached
- [ ] Reverts if deadline not passed
- [ ] LotteryCancelled event emitted
- [ ] State transitions to Cancelled

### Refund Tests
- [ ] Player can refund full contribution after cancellation
- [ ] Player with multiple tickets gets full refund
- [ ] Reverts if lottery not cancelled
- [ ] Reverts if player has no contribution
- [ ] Reverts if player already refunded
- [ ] RefundClaimed event emitted

### Edge Cases
- [ ] Exactly minPlayers participants
- [ ] Exactly maxPlayers participants
- [ ] Single player buys all tickets (maxPlayers)
- [ ] Draw and reveal in minimum valid block gap (drawBlock + 2)
- [ ] Draw and reveal at exactly 256 block limit
- [ ] Multiple players, verify randomness selects from array correctly

### Integration Scenarios
- [ ] Full happy path: deploy → buy tickets → draw → reveal → claim
- [ ] Cancellation path: deploy → buy (not enough) → deadline → cancel → refunds
- [ ] Multiple rounds of ticket purchases before deadline

## Not Implemented (Future Learning)

- **Chainlink VRF**: Secure verifiable random function (oracle-based)
- **Commit-reveal from players**: Players commit their own entropy
- **Multiple winners**: Split prize among top N
- **Ticket NFTs**: Represent tickets as NFTs
- **Recurring lotteries**: Automatic restart after completion
- **Fee mechanism**: Owner takes percentage of prize pool
- **Time-weighted tickets**: Earlier purchases have bonus weight

## Pseudorandomness Deep Dive

### Why `blockhash` is not truly random:

```
Block N:     Player calls draw(), drawBlock = N
Block N+1:   Miner creates block, blockhash(N) now available
Block N+2:   Anyone calls revealWinner(), uses blockhash(N+1)
```

**The vulnerability**: The miner of block N+1 knows what `blockhash(N+1)` will be before publishing. If the prize is large enough, they could:
1. See they would lose
2. Not publish the block (lose block reward ~2 ETH)
3. Hope another miner creates a favorable block

**Mitigation in this design**: Two-step process makes the attack window smaller and more expensive, but doesn't eliminate it.

**Production solution**: Use Chainlink VRF or similar oracle for true verifiable randomness.

## Hints (if you get stuck)

<details>
<summary>Hint 1: Player array structure</summary>

If a player buys 3 tickets, their address appears 3 times in the array:
```
s_players = [alice, bob, alice, alice, charlie]
```
This naturally gives alice 3x the chance of winning.

</details>

<details>
<summary>Hint 2: Contribution tracking</summary>

```solidity
s_contributions[msg.sender] += msg.value;
```
This accumulates across multiple purchases for accurate refunds.

</details>

<details>
<summary>Hint 3: Blockhash usage</summary>

```solidity
uint256 seed = uint256(blockhash(s_drawBlock + 1));
uint256 winnerIndex = seed % s_players.length;
s_winner = s_players[winnerIndex];
```

</details>

<details>
<summary>Hint 4: 256 block check</summary>

```solidity
if (block.number <= s_drawBlock + 1) revert TooEarlyToReveal();
if (block.number > s_drawBlock + 257) revert TooLateToReveal();
```

</details>
