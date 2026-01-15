// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

/// @title SimpleStaking
/// @notice A staking contract where users lock ETH for a minimum period to earn rewards.
/// @dev
/// - Rewards are distributed from a pool funded by the contract owner
/// - Linear reward accrual based on amount and time staked
/// - One active stake per address
/// - CEI pattern used for all withdrawals

contract SimpleStaking {
    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Address that deployed the contract and can fund rewards.
    address public immutable i_owner;

    /// @notice Minimum seconds before unstaking is allowed.
    uint256 public immutable i_minLockPeriod;

    /// @notice Reward rate in wei per ETH per second.
    uint256 public immutable i_rewardRatePerSecond;

    /// @notice ETH available for reward distribution.
    uint256 public rewardPool;

    /// @notice Sum of all active stakes.
    uint256 public totalStaked;

    /// @notice Precision factor for reward calculations.
    uint256 constant PRECISION = 1e18;

    /// @notice Per-user stake information.
    struct Stake {
        uint256 amount; // ETH staked
        uint256 stakedAt; // timestamp when staked
        uint256 rewardsClaimed; // rewards already claimed
    }

    /// @notice Mapping of staker address to their stake info.
    mapping(address => Stake) public stakes;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Reverts when caller is not the owner.
    error NotOwner();

    /// @notice Reverts when lock period is zero.
    error InvalidLockPeriod();

    /// @notice Reverts when reward rate is zero.
    error InvalidRewardRate();

    /// @notice Reverts when depositing zero rewards.
    error InvalidDepositAmount();

    /// @notice Reverts when staking zero ETH.
    error InvalidStakeAmount();

    /// @notice Reverts when user already has an active stake.
    error AlreadyStaked();

    /// @notice Reverts when user has no active stake.
    error NoStake();

    /// @notice Reverts when trying to unstake before lock period ends.
    error MinLockNotPassed();

    /// @notice Reverts when claiming with no rewards available.
    error NoRewardsToClaim();

    /// @notice Reverts when ETH transfer fails.
    error TransferFailed();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when owner deposits ETH into the reward pool.
    /// @param owner Address that deposited rewards.
    /// @param amount ETH amount deposited.
    event RewardsDeposited(address indexed owner, uint256 amount);

    /// @notice Emitted when a user stakes ETH.
    /// @param staker Address that staked.
    /// @param amount ETH amount staked.
    event Staked(address indexed staker, uint256 amount);

    /// @notice Emitted when a user unstakes and withdraws.
    /// @param staker Address that unstaked.
    /// @param principal Original staked amount returned.
    /// @param rewards Reward amount claimed.
    event Unstaked(address indexed staker, uint256 principal, uint256 rewards);

    /// @notice Emitted when a user claims rewards without unstaking.
    /// @param staker Address that claimed.
    /// @param amount Reward amount claimed.
    event RewardsClaimed(address indexed staker, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Restricts function to owner only.
    modifier onlyOwner() {
        if (msg.sender != i_owner) revert NotOwner();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploys a new staking contract with fixed parameters.
    /// @dev Lock period and reward rate cannot be changed after deployment.
    /// @param minLockPeriod Minimum seconds before unstaking allowed.
    /// @param rewardRatePerSecond Reward rate in wei per ETH per second.
    constructor(uint256 minLockPeriod, uint256 rewardRatePerSecond) {
        if (minLockPeriod == 0) revert InvalidLockPeriod();
        if (rewardRatePerSecond == 0) revert InvalidRewardRate();

        i_minLockPeriod = minLockPeriod;
        i_rewardRatePerSecond = rewardRatePerSecond;
        i_owner = msg.sender;
    }

    /*//////////////////////////////////////////////////////////////
                            OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposits ETH into the reward pool.
    /// @dev
    /// - Only callable by owner
    /// - Deposit amount must be greater than zero
    function depositRewards() public payable onlyOwner {
        if (msg.value == 0) revert InvalidDepositAmount();
        rewardPool += msg.value;
        emit RewardsDeposited(msg.sender, msg.value);
    }

    /*//////////////////////////////////////////////////////////////
                            STAKER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Stakes ETH and starts the lock period.
    /// @dev
    /// - Only one active stake per address
    /// - Stake amount must be greater than zero
    function stake() public payable {
        if (msg.value == 0) revert InvalidStakeAmount();
        if (stakes[msg.sender].stakedAt != 0) revert AlreadyStaked();
        stakes[msg.sender] = Stake(msg.value, block.timestamp, 0);
        totalStaked += msg.value;
        emit Staked(msg.sender, msg.value);
    }

    /// @notice Unstakes ETH and claims all unclaimed rewards.
    /// @dev
    /// - Only callable after lock period ends
    /// - Returns principal plus unclaimed rewards
    /// - Rewards capped to available reward pool
    /// - Uses CEI pattern: state zeroed before transfer
    function unstake() public {
        if (stakes[msg.sender].stakedAt == 0) revert NoStake();

        uint256 _userStakedAt = stakes[msg.sender].stakedAt;
        uint256 _userStake = stakes[msg.sender].amount;
        uint256 _userStakingTime = block.timestamp - _userStakedAt;

        if (block.timestamp < _userStakedAt + i_minLockPeriod)
            revert MinLockNotPassed();

        // Calculate total rewards: amount × time × rate / PRECISION
        uint256 reward = (_userStake *
            _userStakingTime *
            i_rewardRatePerSecond) / PRECISION;
        uint256 unclaimedReward = reward - stakes[msg.sender].rewardsClaimed;

        // Cap rewards to available pool
        if (unclaimedReward > rewardPool) {
            unclaimedReward = rewardPool;
        }

        uint256 total = _userStake + unclaimedReward;

        // Effects: zero stake before transfer
        stakes[msg.sender].stakedAt = 0;
        stakes[msg.sender].amount = 0;
        stakes[msg.sender].rewardsClaimed = 0;

        totalStaked -= _userStake;
        rewardPool -= unclaimedReward;

        // Interactions: transfer ETH
        (bool success, ) = payable(msg.sender).call{value: total}("");
        if (!success) revert TransferFailed();

        emit Unstaked(msg.sender, _userStake, unclaimedReward);
    }

    /// @notice Claims accrued rewards without unstaking.
    /// @dev
    /// - Caller must have an active stake
    /// - Reverts if no rewards to claim
    /// - Rewards capped to available reward pool
    /// - Uses CEI pattern: rewardsClaimed updated before transfer
    function claimRewards() public {
        if (stakes[msg.sender].stakedAt == 0) revert NoStake();

        uint256 _userStakedAt = stakes[msg.sender].stakedAt;
        uint256 _userStake = stakes[msg.sender].amount;
        uint256 _userStakingTime = block.timestamp - _userStakedAt;

        // Calculate total rewards: amount × time × rate / PRECISION
        uint256 reward = (_userStake *
            _userStakingTime *
            i_rewardRatePerSecond) / PRECISION;
        uint256 unclaimedReward = reward - stakes[msg.sender].rewardsClaimed;

        if (unclaimedReward == 0) revert NoRewardsToClaim();

        // Cap rewards to available pool
        if (unclaimedReward > rewardPool) {
            unclaimedReward = rewardPool;
        }

        // Effects: update claimed rewards before transfer
        stakes[msg.sender].rewardsClaimed += unclaimedReward;
        rewardPool -= unclaimedReward;

        // Interactions: transfer ETH
        (bool success, ) = payable(msg.sender).call{value: unclaimedReward}("");
        if (!success) revert TransferFailed();

        emit RewardsClaimed(msg.sender, unclaimedReward);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns total rewards accrued for a staker.
    /// @dev Returns 0 if staker has no active stake.
    /// @param _staker Address to query.
    /// @return Total rewards accrued (including already claimed).
    function calculateRewards(address _staker) public view returns (uint256) {
        if (stakes[_staker].stakedAt == 0) return 0;

        uint256 _userStakedAt = stakes[_staker].stakedAt;
        uint256 _userStake = stakes[_staker].amount;
        uint256 _userStakingTime = block.timestamp - _userStakedAt;

        uint256 reward = (_userStake *
            _userStakingTime *
            i_rewardRatePerSecond) / PRECISION;

        return reward;
    }

    /// @notice Returns unclaimed rewards for a staker.
    /// @dev Returns 0 if staker has no active stake.
    /// @param _staker Address to query.
    /// @return Rewards accrued minus rewards already claimed.
    function getUnclaimedRewards(
        address _staker
    ) public view returns (uint256) {
        return calculateRewards(_staker) - stakes[_staker].rewardsClaimed;
    }

    /// @notice Returns stake information for a staker.
    /// @param staker Address to query.
    /// @return Stake struct with amount, stakedAt, and rewardsClaimed.
    function getStakeInfo(address staker) public view returns (Stake memory) {
        return stakes[staker];
    }

    /// @notice Checks if a staker can unstake (lock period passed).
    /// @dev Returns false if no stake or still locked.
    /// @param staker Address to query.
    /// @return True if lock period has passed, false otherwise.
    function canUnstake(address staker) public view returns (bool) {
        if (stakes[staker].stakedAt == 0) return false;
        return block.timestamp >= stakes[staker].stakedAt + i_minLockPeriod;
    }
}
