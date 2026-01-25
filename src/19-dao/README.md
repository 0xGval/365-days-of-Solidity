# Day 19: SimpleDAO

A minimal on-chain governance system where token holders can create proposals, vote, and execute approved actions.

---

## Purpose

Learn decentralized governance mechanics: proposal lifecycle, voting power, quorum requirements, and time-bound execution. This builds on Day 10 (MultiSigWallet) by replacing fixed signers with dynamic token-based voting.

---

## Functional Overview

### Membership
- Members join by depositing ETH (1 ETH = 1 voting power)
- Members can withdraw their ETH at any time (if not locked in active vote)
- Voting power is proportional to deposited ETH

### Proposal Lifecycle
```
Created → Voting (active) → Succeeded/Defeated → Executed (if succeeded)
                                              → Expired (if not executed in time)
```

### Voting Rules
- Only members can create proposals
- Minimum proposal threshold: must have at least 1 ETH deposited to propose
- Voting period: fixed duration set at deployment (e.g., 3 days)
- Each member can vote once per proposal (FOR or AGAINST)
- Voting power = member's ETH balance at time of voting
- Quorum: minimum percentage of total voting power must participate (e.g., 25%)
- Proposal passes if: quorum reached AND forVotes > againstVotes

### Execution
- Anyone can execute a succeeded proposal
- Execution window: limited time after voting ends (e.g., 7 days)
- Proposals can only transfer ETH from DAO treasury to a recipient

---

## Technical Specification

### Structs

```solidity
struct Member {
    uint256 balance;           // ETH deposited (= voting power)
    uint256 joinedAt;          // Timestamp when joined
}

struct Proposal {
    uint256 id;                // Unique identifier
    address proposer;          // Who created it
    address recipient;         // Who receives ETH if executed
    uint256 amount;            // ETH amount to transfer
    string description;        // What this proposal does
    uint256 createdAt;         // Timestamp
    uint256 forVotes;          // Total voting power in favor
    uint256 againstVotes;      // Total voting power against
    bool executed;             // Whether executed
    bool canceled;             // Whether canceled by proposer
}
```

### State Variables

```solidity
// Configuration (immutable)
uint256 public immutable votingPeriod;      // Duration in seconds
uint256 public immutable executionWindow;    // Time to execute after voting
uint256 public immutable quorumPercentage;   // 1-100, percentage of total power needed
uint256 public immutable proposalThreshold;  // Min ETH to create proposal (1 ether)

// State
uint256 public totalVotingPower;             // Sum of all member balances
uint256 public proposalCount;                // Auto-incrementing ID

mapping(address => Member) public members;
mapping(uint256 => Proposal) public proposals;
mapping(uint256 => mapping(address => bool)) public hasVoted;  // proposalId => voter => voted
mapping(uint256 => mapping(address => bool)) public voteChoice; // proposalId => voter => true=for
```

### Functions to Implement

#### Membership

```solidity
/// @notice Join the DAO by depositing ETH
/// @dev Increases sender's voting power by msg.value
function join() external payable;

/// @notice Add more ETH to increase voting power
function addFunds() external payable;

/// @notice Withdraw ETH and reduce voting power
/// @param amount ETH to withdraw
function withdraw(uint256 amount) external;
```

#### Proposals

```solidity
/// @notice Create a new proposal to send ETH
/// @param recipient Address to receive ETH if proposal passes
/// @param amount ETH amount to send
/// @param description Human-readable description
/// @return proposalId The ID of the created proposal
function propose(
    address recipient,
    uint256 amount,
    string calldata description
) external returns (uint256 proposalId);

/// @notice Cancel a proposal (only proposer, only during voting)
/// @param proposalId The proposal to cancel
function cancel(uint256 proposalId) external;
```

#### Voting

```solidity
/// @notice Cast a vote on an active proposal
/// @param proposalId The proposal to vote on
/// @param support True = FOR, False = AGAINST
function vote(uint256 proposalId, bool support) external;
```

#### Execution

```solidity
/// @notice Execute a succeeded proposal
/// @param proposalId The proposal to execute
function execute(uint256 proposalId) external;
```

#### View Functions

```solidity
/// @notice Get the current state of a proposal
/// @return One of: Pending, Active, Canceled, Defeated, Succeeded, Expired, Executed
function getProposalState(uint256 proposalId) external view returns (ProposalState);

/// @notice Check if quorum was reached for a proposal
function quorumReached(uint256 proposalId) external view returns (bool);

/// @notice Check if a proposal succeeded (quorum + majority)
function proposalSucceeded(uint256 proposalId) external view returns (bool);
```

---

## Events

```solidity
event MemberJoined(address indexed member, uint256 amount);
event FundsAdded(address indexed member, uint256 amount);
event FundsWithdrawn(address indexed member, uint256 amount);
event ProposalCreated(
    uint256 indexed proposalId,
    address indexed proposer,
    address recipient,
    uint256 amount,
    string description
);
event ProposalCanceled(uint256 indexed proposalId);
event Voted(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight);
event ProposalExecuted(uint256 indexed proposalId);
```

---

## Custom Errors

```solidity
error NotAMember();
error AlreadyAMember();
error InsufficientBalance();
error InsufficientVotingPower();
error BelowProposalThreshold();
error ProposalNotActive();
error ProposalNotSucceeded();
error ProposalAlreadyExecuted();
error AlreadyVoted();
error InvalidRecipient();
error InsufficientTreasury();
error OnlyProposer();
error TransferFailed();
error ZeroAmount();
```

---

## Enum

```solidity
enum ProposalState {
    Pending,    // Created but voting not started (not used in simple version)
    Active,     // Voting is open
    Canceled,   // Proposer canceled
    Defeated,   // Voting ended, did not pass
    Succeeded,  // Voting ended, passed, awaiting execution
    Expired,    // Passed but execution window closed
    Executed    // Successfully executed
}
```

---

## Constructor

```solidity
/// @param _votingPeriod Duration of voting in seconds (e.g., 3 days = 259200)
/// @param _executionWindow Time to execute after voting ends (e.g., 7 days = 604800)
/// @param _quorumPercentage Percentage of total voting power needed (e.g., 25)
/// @param _proposalThreshold Minimum ETH balance required to create a proposal (e.g., 1 ether)
constructor(
    uint256 _votingPeriod,
    uint256 _executionWindow,
    uint256 _quorumPercentage,
    uint256 _proposalThreshold
);
```

---

## Design Constraints (Intentional Simplifications)

1. **ETH-based voting power** - No external token, just deposited ETH
2. **Simple proposals** - Only ETH transfers, no arbitrary contract calls
3. **No delegation** - Members vote with their own power only
4. **No vote changing** - Once voted, cannot change vote
5. **Snapshot-less** - Voting power counted at vote time, not proposal creation
6. **Single execution** - No batch proposals
7. **No proposal editing** - Once created, cannot modify

---

## Security Considerations

1. **Reentrancy**: Use CEI pattern for all ETH transfers (withdraw, execute)
2. **Treasury accounting**: Track treasury separately from member balances
3. **Overflow**: Solidity 0.8+ handles this, but be careful with percentages
4. **Time manipulation**: Miners can manipulate block.timestamp slightly (~15s)
5. **Quorum gaming**: Members could withdraw after voting to lower total power
6. **Flash loan attacks**: Not applicable here (ETH deposits, not tokens)

---

## Invariants

1. `address(this).balance >= totalVotingPower` (treasury can be higher due to direct sends)
2. Sum of all `members[x].balance` == `totalVotingPower`
3. `forVotes + againstVotes <= totalVotingPower` at any time
4. Executed proposals cannot be executed again
5. Cannot vote on non-active proposals

---

## Test Scenarios to Cover

### Membership
- [ ] Join with ETH increases voting power
- [ ] Cannot join with 0 ETH
- [ ] Add funds increases existing balance
- [ ] Withdraw reduces balance and voting power
- [ ] Cannot withdraw more than balance
- [ ] Non-member cannot withdraw

### Proposals
- [ ] Member with threshold can create proposal
- [ ] Member below threshold cannot propose
- [ ] Non-member cannot propose
- [ ] Cannot propose to zero address
- [ ] Cannot propose zero amount
- [ ] Cannot propose more than treasury
- [ ] Proposer can cancel during voting
- [ ] Non-proposer cannot cancel
- [ ] Cannot cancel after voting ends

### Voting
- [ ] Member can vote FOR
- [ ] Member can vote AGAINST
- [ ] Vote weight equals member balance
- [ ] Cannot vote twice on same proposal
- [ ] Cannot vote on non-active proposal
- [ ] Cannot vote after voting period ends
- [ ] Non-member cannot vote

### Proposal States
- [ ] New proposal is Active
- [ ] Canceled proposal shows Canceled
- [ ] After voting, under quorum shows Defeated
- [ ] After voting, quorum reached but minority FOR shows Defeated
- [ ] After voting, quorum + majority shows Succeeded
- [ ] After execution window, Succeeded becomes Expired
- [ ] After execute, shows Executed

### Execution
- [ ] Anyone can execute succeeded proposal
- [ ] Cannot execute defeated proposal
- [ ] Cannot execute expired proposal
- [ ] Cannot execute twice
- [ ] Execution transfers correct ETH amount
- [ ] Execution fails if treasury insufficient

### Edge Cases
- [ ] Exactly at quorum threshold
- [ ] Tie vote (forVotes == againstVotes) should fail
- [ ] Execute at last second of window
- [ ] Vote at last second of period
- [ ] Withdraw while having active votes (should work - no lock in simple version)

---

## Example Usage

```solidity
// Deploy with 3-day voting, 7-day execution window, 25% quorum, 1 ETH proposal threshold
SimpleDAO dao = new SimpleDAO(3 days, 7 days, 25, 1 ether);

// Alice joins with 10 ETH
dao.join{value: 10 ether}();

// Bob joins with 5 ETH
dao.join{value: 5 ether}();

// Total voting power: 15 ETH

// Alice proposes to send 2 ETH to Charlie
uint256 proposalId = dao.propose(charlie, 2 ether, "Fund Charlie's project");

// Alice votes FOR (10 voting power)
dao.vote(proposalId, true);

// Bob votes AGAINST (5 voting power)
dao.vote(proposalId, false);

// After voting period...
// Quorum: 15 total * 25% = 3.75 ETH needed, we have 15 votes = reached
// Result: 10 FOR > 5 AGAINST = SUCCEEDED

// Anyone executes
dao.execute(proposalId);
// Charlie receives 2 ETH
```

---

## Not Implemented (Future Learning)

- Governance token (ERC20 voting)
- Vote delegation
- Timelock between success and execution
- Arbitrary contract calls (not just ETH transfer)
- Voting snapshots (prevent double-voting after transfer)
- Quadratic voting
- Conviction voting
- Optimistic governance
- Off-chain voting with on-chain execution (Snapshot style)

---

## Concepts Practiced

- Complex state machines (proposal lifecycle)
- Time-based logic (voting period, execution window)
- Percentage calculations (quorum)
- Enumerated types (ProposalState)
- Nested mappings (hasVoted)
- View functions with computed state
- Treasury management
- Democratic coordination mechanisms
