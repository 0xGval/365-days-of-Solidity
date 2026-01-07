// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

/**
 * @title SimpleVault
 * @notice Time-locked vault that allows users to deposit ETH with a mandatory
 *         lock period. Early withdrawals incur a penalty fee.
 * @dev Each user has their own independent vault. No owner or admin role.
 */
contract SimpleVault {
    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Per-user vault state.
    struct Vault {
        uint256 balance;
        uint256 unlockTime;
    }

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Address that receives early withdrawal fees.
    address public feeCollector;

    /// @notice Early withdrawal penalty in basis points (e.g., 1000 = 10%).
    uint256 public earlyWithdrawFeeBps;

    /// @notice Lock duration in seconds applied to each deposit.
    uint256 public lockDuration;

    /// @notice Per-user vault storage.
    mapping(address => Vault) public depositorToVault;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Reverts when user has no deposit.
    error NoDeposit();

    /// @notice Reverts when amount is zero or invalid.
    error InvalidAmount();

    /// @notice Reverts when withdrawal attempted before unlock time.
    error StillLocked();

    /// @notice Reverts when partial withdrawal exceeds balance.
    error InsufficientBalance();

    /// @notice Reverts when lock extension is zero.
    error InvalidExtension();

    /// @notice Reverts when fee collector address is zero.
    error InvalidFeeCollector();

    /// @notice Reverts when ETH transfer fails.
    error TransferFailed();

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Allows execution only if lock has expired.
    modifier lockIsExpired() {
        if (depositorToVault[msg.sender].unlockTime > block.timestamp)
            revert StillLocked();
        _;
    }

    /// @notice Allows execution only if user has a deposit.
    modifier hasDeposit() {
        if (depositorToVault[msg.sender].balance == 0) revert NoDeposit();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a user deposits ETH.
    event Deposited(address indexed user, uint256 amount, uint256 unlockTime);

    /// @notice Emitted when a user withdraws ETH.
    event Withdrawn(address indexed user, uint256 amount);

    /// @notice Emitted when a user performs an early withdrawal.
    event EmergencyWithdrawn(
        address indexed user,
        uint256 amountReceived,
        uint256 feePaid
    );

    /// @notice Emitted when a user extends their lock period.
    event LockExtended(address indexed user, uint256 newUnlockTime);

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploys the vault with fixed configuration.
    /// @param _feeCollector Address to receive early withdrawal fees.
    /// @param _earlyWithdrawFeeBps Penalty in basis points.
    /// @param _lockDuration Lock duration in seconds.
    constructor(
        address _feeCollector,
        uint256 _earlyWithdrawFeeBps,
        uint256 _lockDuration
    ) {
        if (_feeCollector == address(0)) revert InvalidFeeCollector();
        feeCollector = _feeCollector;
        earlyWithdrawFeeBps = _earlyWithdrawFeeBps;
        lockDuration = _lockDuration;
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSITS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposits ETH into the caller's vault.
    /// @dev Each deposit adds to balance and resets the unlock time.
    function deposit() public payable {
        if (msg.value == 0) revert InvalidAmount();

        uint256 _unlockTime = block.timestamp + lockDuration;
        uint256 _currentBalance = depositorToVault[msg.sender].balance;
        uint256 _newBalance = msg.value + _currentBalance;

        depositorToVault[msg.sender] = Vault(_newBalance, _unlockTime);
        emit Deposited(msg.sender, msg.value, _unlockTime);
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAWALS
    //////////////////////////////////////////////////////////////*/

    /// @notice Withdraws entire balance after lock expires.
    /// @dev Uses CEI pattern to prevent reentrancy.
    function withdraw() public lockIsExpired hasDeposit {
        uint256 _currentBalance = depositorToVault[msg.sender].balance;

        depositorToVault[msg.sender] = Vault(0, 0);

        (bool success, ) = payable(msg.sender).call{value: _currentBalance}("");
        require(success, "ETH transfer failed");

        emit Withdrawn(msg.sender, _currentBalance);
    }

    /// @notice Withdraws a partial amount after lock expires.
    /// @dev Preserves unlock time for remaining balance.
    /// @param _amount Amount of ETH to withdraw.
    function withdrawPartial(uint256 _amount) public lockIsExpired hasDeposit {
        if (_amount == 0) revert InvalidAmount();
        uint256 _currentBalance = depositorToVault[msg.sender].balance;

        if (_currentBalance < _amount) revert InsufficientBalance();

        uint256 _newBalance = _currentBalance - _amount;

        uint256 _currentUnlockTime = depositorToVault[msg.sender].unlockTime;
        depositorToVault[msg.sender] = Vault(_newBalance, _currentUnlockTime);

        (bool success, ) = payable(msg.sender).call{value: _amount}("");
        require(success, "Withdraw failed");

        emit Withdrawn(msg.sender, _amount);
    }

    /*//////////////////////////////////////////////////////////////
                        EMERGENCY WITHDRAWAL
    //////////////////////////////////////////////////////////////*/

    /// @notice Withdraws entire balance with penalty if still locked.
    /// @dev No penalty applied if lock has already expired.
    function emergencyWithdraw() public hasDeposit {
        uint256 _currentBalance = depositorToVault[msg.sender].balance;

        uint256 _penalty = 0;

        if (depositorToVault[msg.sender].unlockTime > block.timestamp) {
            _penalty = (_currentBalance * earlyWithdrawFeeBps) / 10000;
        }

        uint256 _balanceAfterPenalty = _currentBalance - _penalty;
        depositorToVault[msg.sender] = Vault(0, 0);

        (bool penaltySuccess, ) = payable(feeCollector).call{value: _penalty}(
            ""
        );
        require(penaltySuccess, "Penalty transfer failed");

        (bool transferSuccess, ) = payable(msg.sender).call{
            value: _balanceAfterPenalty
        }("");
        require(transferSuccess, "Withdraw failed");

        emit EmergencyWithdrawn(msg.sender, _balanceAfterPenalty, _penalty);
    }

    /*//////////////////////////////////////////////////////////////
                        LOCK MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Extends the lock period by additional seconds.
    /// @param extraSeconds Additional time to add to unlock time.
    function extendLock(uint256 extraSeconds) public hasDeposit {
        if (extraSeconds == 0) revert InvalidExtension();
        uint256 _currentUnlockTime = depositorToVault[msg.sender].unlockTime;
        uint256 _newUnlockTime = _currentUnlockTime + extraSeconds;
        depositorToVault[msg.sender].unlockTime = _newUnlockTime;
        emit LockExtended(msg.sender, _newUnlockTime);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns vault info for a user.
    /// @param _depositor Address to query.
    /// @return Vault struct containing balance and unlock time.
    function getVaultInfo(
        address _depositor
    ) public view returns (Vault memory) {
        if (depositorToVault[_depositor].balance == 0) revert NoDeposit();
        return depositorToVault[_depositor];
    }

    /// @notice Checks if a user's vault is unlocked.
    /// @param _depositor Address to query.
    /// @return True if user can withdraw without penalty.
    function isUnlocked(address _depositor) public view returns (bool) {
        if (depositorToVault[_depositor].balance == 0) revert NoDeposit();
        return depositorToVault[_depositor].unlockTime <= block.timestamp;
    }

    /// @notice Returns seconds until unlock.
    /// @param _depositor Address to query.
    /// @return Seconds remaining until unlock (0 if already unlocked).
    function timeUntilUnlock(address _depositor) public view returns (uint256) {
        if (depositorToVault[_depositor].balance == 0) revert NoDeposit();

        uint256 unlockTime = depositorToVault[_depositor].unlockTime;
        if (unlockTime <= block.timestamp) return 0;

        return unlockTime - block.timestamp;
    }

    /// @notice Calculates penalty for emergency withdrawal.
    /// @param _depositor Address to query.
    /// @return Fee amount that would be charged (0 if unlocked).
    function calculatePenalty(
        address _depositor
    ) public view returns (uint256) {
        uint256 _currentBalance = depositorToVault[_depositor].balance;

        uint256 _penalty = 0;

        if (depositorToVault[_depositor].unlockTime > block.timestamp) {
            _penalty = (_currentBalance * earlyWithdrawFeeBps) / 10000;
        }

        return _penalty;
    }
}
