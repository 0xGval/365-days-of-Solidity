// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title SimpleDAO
/// @notice A minimal on-chain governance system with ETH-based voting power
/// @dev Day 19 of 365 Days of Solidity
contract SimpleDAO {
    // Configuration (immutable)
    uint256 public immutable votingPeriod; // Duration in seconds
    uint256 public immutable executionWindow; // Time to execute after voting
    uint256 public immutable quorumPercentage; // 1-100, percentage of total power needed
    uint256 public immutable proposalThreshold; // Min ETH to create proposal (1 ether)

    uint256 public totalVotingPower; // Sum of all member balances
    uint256 public proposalCount; // Auto-incrementing ID

    struct Member {
        uint256 balance; // ETH deposited (= voting power)
        uint256 joinedAt; // Timestamp when joined
    }

    struct Proposal {
        uint256 id; // Unique identifier
        address proposer; // Who created it
        address recipient; // Who receives ETH if executed
        uint256 amount; // ETH amount to transfer
        string description; // What this proposal does
        uint256 createdAt; // Timestamp
        uint256 forVotes; // Total voting power in favor
        uint256 againstVotes; // Total voting power against
        bool executed; // Whether executed
        bool canceled; // Whether canceled by proposer
    }

    enum ProposalState {
        Pending, // Created but voting not started (not used in simple version)
        Active, // Voting is open
        Canceled, // Proposer canceled
        Defeated, // Voting ended, did not pass
        Succeeded, // Voting ended, passed, awaiting execution
        Expired, // Passed but execution window closed
        Executed // Successfully executed
    }

    mapping(address => Member) public members;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted; // proposalId => voter => voted
    mapping(uint256 => mapping(address => bool)) public voteChoice; // proposalId => voter => true=for

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
    event Voted(
        uint256 indexed proposalId,
        address indexed voter,
        bool support,
        uint256 weight
    );
    event ProposalExecuted(uint256 indexed proposalId);

    constructor(
        uint256 _votingPeriod,
        uint256 _executionWindow,
        uint256 _quorumPercentage,
        uint256 _proposalThreshold
    ) {
        votingPeriod = _votingPeriod;
        executionWindow = _executionWindow;
        quorumPercentage = _quorumPercentage;
        proposalThreshold = _proposalThreshold;
    }

    // Membership Functions

    /// @notice Join the DAO by depositing ETH
    /// @dev Increases sender's voting power by msg.value
    function join() external payable {
        if (msg.value == 0) revert ZeroAmount();
        if (members[msg.sender].joinedAt != 0) revert AlreadyAMember();
        members[msg.sender] = Member(msg.value, block.timestamp);
        totalVotingPower += msg.value;
        emit MemberJoined(msg.sender, msg.value);
    }

    /// @notice Add more ETH to increase voting power
    function addFunds() external payable {
        if (msg.value == 0) revert ZeroAmount();
        if (members[msg.sender].joinedAt == 0) revert NotAMember();
        members[msg.sender].balance += msg.value;
        totalVotingPower += msg.value;
        emit FundsAdded(msg.sender, msg.value);
    }

    /// @notice Withdraw ETH and reduce voting power
    /// @param amount ETH to withdraw
    function withdraw(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (members[msg.sender].joinedAt == 0) revert NotAMember();
        if (members[msg.sender].balance < amount) revert InsufficientBalance();
        members[msg.sender].balance -= amount;
        totalVotingPower -= amount;
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) revert TransferFailed();
        emit FundsWithdrawn(msg.sender, amount);
    }

    // Proposals Functions

    /// @notice Create a new proposal to send ETH
    /// @param recipient Address to receive ETH if proposal passes
    /// @param amount ETH amount to send
    /// @param description Human-readable description
    /// @return proposalId The ID of the created proposal
    function propose(
        address recipient,
        uint256 amount,
        string calldata description
    ) external returns (uint256 proposalId) {
        if (amount == 0) revert ZeroAmount();
        if (members[msg.sender].joinedAt == 0) revert NotAMember();
        if (recipient == address(0)) revert InvalidRecipient();
        if (amount > address(this).balance) revert InsufficientTreasury();
        if (members[msg.sender].balance < proposalThreshold)
            revert BelowProposalThreshold();
        proposalCount += 1;
        uint256 _proposalId = proposalCount;
        proposals[_proposalId] = Proposal(
            _proposalId,
            msg.sender,
            recipient,
            amount,
            description,
            block.timestamp,
            0,
            0,
            false,
            false
        );
        emit ProposalCreated(
            _proposalId,
            msg.sender,
            recipient,
            amount,
            description
        );
        return _proposalId;
    }

    /// @notice Cancel a proposal (only proposer, only during voting)
    /// @param proposalId The proposal to cancel
    function cancel(uint256 proposalId) external {
        if (members[msg.sender].joinedAt == 0) revert NotAMember();
        if (proposals[proposalId].proposer != msg.sender) revert OnlyProposer();
        if (proposals[proposalId].canceled == true) revert ProposalNotActive();
        if (proposals[proposalId].executed == true)
            revert ProposalAlreadyExecuted();

        if (block.timestamp > proposals[proposalId].createdAt + votingPeriod)
            revert ProposalNotActive();

        proposals[proposalId].canceled = true;

        emit ProposalCanceled(proposalId);
    }

    /// @notice Cast a vote on an active proposal
    /// @param proposalId The proposal to vote on
    /// @param support True = FOR, False = AGAINST
    function vote(uint256 proposalId, bool support) external {
        if (members[msg.sender].joinedAt == 0) revert NotAMember();
        if (proposals[proposalId].canceled == true) revert ProposalNotActive();

        if (proposals[proposalId].executed == true)
            revert ProposalAlreadyExecuted();

        if (block.timestamp > proposals[proposalId].createdAt + votingPeriod)
            revert ProposalNotActive();

        if (hasVoted[proposalId][msg.sender] == true) revert AlreadyVoted();
        uint256 voteWeight = members[msg.sender].balance;
        if (voteWeight == 0) revert InsufficientVotingPower();
        hasVoted[proposalId][msg.sender] = true;
        voteChoice[proposalId][msg.sender] = support;

        if (support == true) {
            proposals[proposalId].forVotes += voteWeight;
        } else {
            proposals[proposalId].againstVotes += voteWeight;
        }

        emit Voted(proposalId, msg.sender, support, voteWeight);
    }

    /// @notice Execute a succeeded proposal
    /// @param proposalId The proposal to execute
    function execute(uint256 proposalId) external {
        if (getProposalState(proposalId) != ProposalState.Succeeded)
            revert ProposalNotSucceeded();
        proposals[proposalId].executed = true;

        uint256 amount = proposals[proposalId].amount;
        address recipient = proposals[proposalId].recipient;
        (bool success, ) = payable(recipient).call{value: amount}("");
        if (!success) revert TransferFailed();

        emit ProposalExecuted(proposalId);
    }

    // View Functions

    /// @notice Check if quorum was reached for a proposal
    /// @param proposalId The proposal to check
    /// @return True if total votes >= quorum threshold
    function quorumReached(uint256 proposalId) public view returns (bool) {
        Proposal storage p = proposals[proposalId];
        uint256 totalVotes = p.forVotes + p.againstVotes;
        // quorum = (totalVotes * 100) >= (totalVotingPower * quorumPercentage)
        // Rearranged to avoid division: totalVotes * 100 >= totalVotingPower * quorumPercentage
        return totalVotes * 100 >= totalVotingPower * quorumPercentage;
    }

    /// @notice Check if a proposal succeeded (quorum + majority)
    /// @param proposalId The proposal to check
    /// @return True if quorum reached AND forVotes > againstVotes
    function proposalSucceeded(uint256 proposalId) public view returns (bool) {
        Proposal storage p = proposals[proposalId];
        return quorumReached(proposalId) && p.forVotes > p.againstVotes;
    }

    /// @notice Get the current state of a proposal
    /// @param proposalId The proposal to check
    /// @return The current ProposalState
    function getProposalState(
        uint256 proposalId
    ) public view returns (ProposalState) {
        Proposal storage p = proposals[proposalId];

        // Check stored states first (irreversible actions)
        if (p.executed) {
            return ProposalState.Executed;
        }
        if (p.canceled) {
            return ProposalState.Canceled;
        }

        // Check if proposal exists (createdAt == 0 means not created)
        if (p.createdAt == 0) {
            return ProposalState.Pending;
        }

        uint256 votingEnd = p.createdAt + votingPeriod;

        // Still in voting period
        if (block.timestamp <= votingEnd) {
            return ProposalState.Active;
        }

        // Voting ended - check result
        if (!proposalSucceeded(proposalId)) {
            return ProposalState.Defeated;
        }

        // Succeeded - check execution window
        uint256 executionDeadline = votingEnd + executionWindow;
        if (block.timestamp > executionDeadline) {
            return ProposalState.Expired;
        }

        return ProposalState.Succeeded;
    }
}
