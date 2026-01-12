// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

/// @title SimpleCrowdfunding
/// @notice A crowdfunding contract where contributors pledge ETH toward a goal
/// @dev
/// - If goal is reached before deadline, creator can withdraw all funds
/// - If goal is NOT reached after deadline, contributors can claim refunds
/// - Pull-based refund pattern for safety
/// - One campaign per contract deployment

contract SimpleCrowdfunding {
    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Address that deployed the contract and can withdraw funds.
    address public immutable i_creator;

    /// @notice Minimum ETH required for campaign success.
    uint256 public immutable i_goal;

    /// @notice Unix timestamp after which contributions are closed.
    uint256 public immutable i_deadline;

    /// @notice Total ETH contributed so far.
    uint256 public totalRaised;

    /// @notice Whether creator has already withdrawn funds.
    bool public withdrawn;

    /// @notice Per-address contribution amounts.
    mapping(address => uint256) public contributions;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Reverts when deadline is in the past.
    error invalidDeadline();

    /// @notice Reverts when funding goal is zero.
    error invalidFundingGoal();

    /// @notice Reverts when contributing after deadline.
    error CampaignEnded();

    /// @notice Reverts when withdrawing/refunding before deadline.
    error CampaignNotEnded();

    /// @notice Reverts when withdrawing but goal was not reached.
    error GoalNotReached();

    /// @notice Reverts when refunding but goal was reached.
    error GoalAlreadyReached();

    /// @notice Reverts when caller is not the creator.
    error NotCreator();

    /// @notice Reverts when refunding with zero contribution.
    error NoContribution();

    /// @notice Reverts when creator tries to withdraw twice.
    error AlreadyWithdrawn();

    /// @notice Reverts when contributor tries to refund twice.
    error AlreadyRefunded();

    /// @notice Reverts when ETH transfer fails.
    error TransferFailed();

    /// @notice Reverts when contributing zero ETH.
    error ZeroContribution();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a contribution is received.
    /// @param contributor Address that contributed.
    /// @param amount ETH amount contributed.
    /// @param totalRaised New total raised after contribution.
    event ContributionReceived(
        address indexed contributor,
        uint256 amount,
        uint256 totalRaised
    );

    /// @notice Emitted when creator withdraws funds after successful campaign.
    /// @param creator Address that received the funds.
    /// @param amount Total ETH withdrawn.
    event FundsWithdrawn(address indexed creator, uint256 amount);

    /// @notice Emitted when a contributor claims their refund.
    /// @param contributor Address that received the refund.
    /// @param amount ETH amount refunded.
    event RefundClaimed(address indexed contributor, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Restricts function to before deadline.
    modifier onlyActiveCampaign() {
        if (block.timestamp > i_deadline) revert CampaignEnded();
        _;
    }

    /// @notice Restricts function to after deadline.
    modifier onlyEndedCampaign() {
        if (block.timestamp < i_deadline) revert CampaignNotEnded();
        _;
    }

    /// @notice Restricts function to successful campaigns (goal reached).
    modifier onlyGoalReached() {
        if (i_goal > totalRaised) revert GoalNotReached();
        _;
    }

    /// @notice Restricts function to failed campaigns (goal not reached).
    modifier onlyGoalNotReached() {
        if (i_goal <= totalRaised) revert GoalAlreadyReached();
        _;
    }

    /// @notice Restricts function to creator only.
    modifier onlyCreator() {
        if (msg.sender != i_creator) revert NotCreator();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploys a new crowdfunding campaign.
    /// @dev Deadline must be in the future, goal must be greater than zero.
    /// @param _goal Minimum ETH to raise for success.
    /// @param _deadline Unix timestamp when campaign ends.
    constructor(uint256 _goal, uint256 _deadline) {
        if (_deadline < block.timestamp) revert invalidDeadline();
        if (_goal == 0) revert invalidFundingGoal();
        i_deadline = _deadline;
        i_goal = _goal;
        i_creator = msg.sender;
    }

    /*//////////////////////////////////////////////////////////////
                            CONTRIBUTE
    //////////////////////////////////////////////////////////////*/

    /// @notice Contribute ETH to the campaign.
    /// @dev
    /// - Only callable before deadline
    /// - Contribution must be greater than zero
    /// - Multiple contributions from same address accumulate
    function contribute() public payable onlyActiveCampaign {
        if (msg.value == 0) revert ZeroContribution();
        contributions[msg.sender] += msg.value;
        totalRaised += msg.value;
        emit ContributionReceived(msg.sender, msg.value, totalRaised);
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAW
    //////////////////////////////////////////////////////////////*/

    /// @notice Creator withdraws all funds after successful campaign.
    /// @dev
    /// - Only callable by creator
    /// - Only callable after deadline
    /// - Only callable if goal was reached
    /// - Can only be called once
    function withdraw() public onlyCreator onlyEndedCampaign onlyGoalReached {
        if (withdrawn) revert AlreadyWithdrawn();

        uint256 amount = address(this).balance;
        withdrawn = true;

        (bool success, ) = payable(i_creator).call{value: amount}("");
        if (!success) revert TransferFailed();

        emit FundsWithdrawn(i_creator, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            REFUND
    //////////////////////////////////////////////////////////////*/

    /// @notice Contributor claims refund after failed campaign.
    /// @dev
    /// - Only callable after deadline
    /// - Only callable if goal was NOT reached
    /// - Caller must have contributed
    /// - Uses pull pattern: each contributor claims their own refund
    /// - Sets contribution to zero before transfer (CEI pattern)
    function refund() public onlyGoalNotReached onlyEndedCampaign {
        if (contributions[msg.sender] == 0) revert NoContribution();

        uint256 contribution = contributions[msg.sender];
        contributions[msg.sender] = 0;

        (bool success, ) = payable(msg.sender).call{value: contribution}("");
        if (!success) revert TransferFailed();

        emit RefundClaimed(msg.sender, contribution);
    }
}
