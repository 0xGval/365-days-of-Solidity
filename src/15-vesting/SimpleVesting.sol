// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

/// @title SimpleVesting
/// @notice A token vesting contract that releases tokens gradually to a beneficiary over time.
/// @dev
/// - Supports cliff period where no tokens are released
/// - Linear vesting after cliff until full release
/// - Optional revocability by owner
/// - Single beneficiary per contract instance
/// - CEI pattern used for all token transfers

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract SimpleVesting {
    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice ERC20 token being vested.
    IERC20 public immutable i_token;

    /// @notice Address that deployed the contract and can deposit/revoke.
    address public immutable i_owner;

    /// @notice Address that receives vested tokens.
    address public immutable i_beneficiary;

    /// @notice Seconds before any tokens vest (cliff period).
    uint256 public immutable i_cliffDuration;

    /// @notice Total vesting period in seconds (includes cliff).
    uint256 public immutable i_vestingDuration;

    /// @notice Whether owner can revoke the vesting.
    bool public immutable i_revocable;

    /// @notice Total tokens deposited for vesting.
    uint256 public totalAmount;

    /// @notice Timestamp when vesting started (set on deposit).
    uint256 public startTime;

    /// @notice Tokens already released to beneficiary.
    uint256 public released;

    /// @notice Whether vesting has been revoked.
    bool public revoked;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Reverts when token address is zero.
    error InvalidTokenAddress();

    /// @notice Reverts when beneficiary address is zero.
    error InvalidBeneficiary();

    /// @notice Reverts when cliff duration exceeds vesting duration.
    error InvalidCliff();

    /// @notice Reverts when vesting duration is zero.
    error InvalidVesting();

    /// @notice Reverts when caller is not the owner.
    error NotOwner();

    /// @notice Reverts when deposit amount is zero.
    error InvalidAmount();

    /// @notice Reverts when vesting has already started.
    error AlreadyStarted();

    /// @notice Reverts when tokens have already been deposited.
    error AlreadyDeposited();

    /// @notice Reverts when token transfer fails.
    error TransferFailed();

    /// @notice Reverts when trying to revoke a non-revocable vesting.
    error NotRevocable();

    /// @notice Reverts when vesting has already been revoked.
    error AlreadyRevoked();

    /// @notice Reverts when vesting has not started yet.
    error VestingNotStarted();

    /// @notice Reverts when caller is not the beneficiary.
    error NotBeneficiary();

    /// @notice Reverts when there are no tokens to release.
    error NothingToRelease();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when owner deposits tokens to start vesting.
    /// @param owner Address that deposited tokens.
    /// @param amount Token amount deposited.
    event TokensDeposited(address indexed owner, uint256 amount);

    /// @notice Emitted when owner revokes vesting.
    /// @param owner Address that revoked.
    /// @param amountRevoked Unvested tokens returned to owner.
    event VestingRevoked(address indexed owner, uint256 amountRevoked);

    /// @notice Emitted when beneficiary releases vested tokens.
    /// @param beneficiary Address that received tokens.
    /// @param amount Token amount released.
    event TokensReleased(address indexed beneficiary, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Restricts function to owner only.
    modifier onlyOwner() {
        if (msg.sender != i_owner) revert NotOwner();
        _;
    }

    /// @notice Restricts function to beneficiary only.
    modifier onlyBeneficiary() {
        if (msg.sender != i_beneficiary) revert NotBeneficiary();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploys a new vesting contract with fixed parameters.
    /// @dev All parameters except revocable cannot be changed after deployment.
    /// @param tokenAddress ERC20 token to vest.
    /// @param beneficiary Address that will receive vested tokens.
    /// @param cliffDuration Seconds before any tokens vest.
    /// @param vestingDuration Total vesting period in seconds (includes cliff).
    /// @param revocable Whether owner can revoke and recover unvested tokens.
    constructor(
        address tokenAddress,
        address beneficiary,
        uint256 cliffDuration,
        uint256 vestingDuration,
        bool revocable
    ) {
        if (tokenAddress == address(0)) revert InvalidTokenAddress();
        if (beneficiary == address(0)) revert InvalidBeneficiary();
        if (cliffDuration > vestingDuration) revert InvalidCliff();
        if (vestingDuration == 0) revert InvalidVesting();

        i_token = IERC20(tokenAddress);
        i_owner = msg.sender;
        i_beneficiary = beneficiary;
        i_cliffDuration = cliffDuration;
        i_vestingDuration = vestingDuration;
        i_revocable = revocable;
    }

    /*//////////////////////////////////////////////////////////////
                            OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposits tokens to start the vesting schedule.
    /// @dev
    /// - Only callable by owner
    /// - Can only be called once
    /// - Requires prior token approval
    /// - Sets startTime to current block timestamp
    /// @param amount Number of tokens to vest.
    function deposit(uint256 amount) external onlyOwner {
        if (amount == 0) revert InvalidAmount();
        if (startTime != 0) revert AlreadyStarted();
        if (i_token.balanceOf(address(this)) != 0) revert AlreadyDeposited();

        totalAmount = amount;
        startTime = block.timestamp;

        bool success = i_token.transferFrom(i_owner, address(this), amount);
        if (!success) revert TransferFailed();

        emit TokensDeposited(msg.sender, amount);
    }

    /// @notice Revokes vesting and recovers unvested tokens.
    /// @dev
    /// - Only callable by owner
    /// - Only if contract is revocable
    /// - Beneficiary keeps already vested tokens
    /// - Uses CEI pattern: state updated before transfer
    function revoke() external onlyOwner {
        if (!i_revocable) revert NotRevocable();
        if (revoked) revert AlreadyRevoked();
        if (startTime == 0) revert VestingNotStarted();

        uint256 vested = vestedAmount();
        uint256 unvested = totalAmount - vested;

        totalAmount = vested;
        revoked = true;

        bool success = i_token.transfer(i_owner, unvested);
        if (!success) revert TransferFailed();

        emit VestingRevoked(i_owner, unvested);
    }

    /*//////////////////////////////////////////////////////////////
                        BENEFICIARY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Releases vested tokens to beneficiary.
    /// @dev
    /// - Only callable by beneficiary
    /// - Releases all currently releasable tokens
    /// - Reverts if nothing to release
    /// - Uses CEI pattern: released updated before transfer
    function release() external onlyBeneficiary {
        uint256 amount = releasable();
        if (amount == 0) revert NothingToRelease();

        released += amount;

        bool success = i_token.transfer(i_beneficiary, amount);
        if (!success) revert TransferFailed();

        emit TokensReleased(i_beneficiary, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns total tokens vested up to current timestamp.
    /// @dev
    /// - Returns 0 if vesting not started
    /// - Returns 0 if still in cliff period
    /// - Returns totalAmount if vesting complete or revoked
    /// - Linear interpolation between cliff and end
    /// @return Total tokens vested.
    function vestedAmount() public view returns (uint256) {
        if (startTime == 0) return 0;
        if (block.timestamp < startTime + i_cliffDuration) return 0;
        if (block.timestamp >= startTime + i_vestingDuration) return totalAmount;
        if (revoked) return totalAmount;

        uint256 elapsed = block.timestamp - startTime;
        return (totalAmount * elapsed) / i_vestingDuration;
    }

    /// @notice Returns tokens available to release now.
    /// @dev Formula: vestedAmount - released
    /// @return Tokens that can be released.
    function releasable() public view returns (uint256) {
        return vestedAmount() - released;
    }

    /// @notice Returns timestamp when cliff period ends.
    /// @dev Returns 0 if vesting not started.
    /// @return Cliff end timestamp.
    function getCliffEnd() external view returns (uint256) {
        if (startTime == 0) return 0;
        return startTime + i_cliffDuration;
    }

    /// @notice Returns timestamp when vesting completes.
    /// @dev Returns 0 if vesting not started.
    /// @return Vesting end timestamp.
    function getVestingEnd() external view returns (uint256) {
        if (startTime == 0) return 0;
        return startTime + i_vestingDuration;
    }

    /// @notice Returns full vesting schedule information.
    /// @return beneficiary Address receiving tokens.
    /// @return token Token being vested.
    /// @return totalAmount_ Total tokens in vesting.
    /// @return released_ Tokens already released.
    /// @return startTime_ Vesting start timestamp.
    /// @return cliffDuration_ Cliff duration in seconds.
    /// @return vestingDuration_ Total vesting duration in seconds.
    /// @return revocable_ Whether vesting is revocable.
    /// @return revoked_ Whether vesting has been revoked.
    function getVestingInfo()
        external
        view
        returns (
            address beneficiary,
            address token,
            uint256 totalAmount_,
            uint256 released_,
            uint256 startTime_,
            uint256 cliffDuration_,
            uint256 vestingDuration_,
            bool revocable_,
            bool revoked_
        )
    {
        return (
            i_beneficiary,
            address(i_token),
            totalAmount,
            released,
            startTime,
            i_cliffDuration,
            i_vestingDuration,
            i_revocable,
            revoked
        );
    }
}
