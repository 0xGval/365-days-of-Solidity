// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

/// @title SimplePaymentSplitter
/// @notice A contract that receives ETH and distributes it proportionally among multiple payees.
/// @dev
/// - Payees and shares are fixed at deployment
/// - Pull-based payment pattern (payees withdraw their share)
/// - Anyone can trigger release for any payee
/// - Tracks total received as balance + already released
/// - CEI pattern used for all ETH transfers

contract SimplePaymentSplitter {
    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Array of all payee addresses.
    address[] private s_payees;

    /// @notice Share amount for each payee.
    mapping(address => uint256) private s_shares;

    /// @notice ETH already released to each payee.
    mapping(address => uint256) private s_released;

    /// @notice Sum of all shares (set once in constructor).
    uint256 public immutable TOTAL_SHARES;

    /// @notice Total ETH already distributed to all payees.
    uint256 private s_totalReleased;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Reverts when payees array is empty.
    error InvalidPayees();

    /// @notice Reverts when shares array is empty.
    error InvalidShares();

    /// @notice Reverts when payees and shares arrays have different lengths.
    error PayeesMustMatchShares();

    /// @notice Reverts when payee address is zero.
    error ZeroAddress();

    /// @notice Reverts when share amount is zero.
    error ZeroShares();

    /// @notice Reverts when same payee is added twice.
    error DuplicatePayee();

    /// @notice Reverts when account has no shares.
    error AccountHasNoShares();

    /// @notice Reverts when there is nothing to release.
    error NoPaymentDue();

    /// @notice Reverts when ETH transfer fails.
    error TransferFailed();

    /// @notice Reverts when index is out of bounds.
    error IndexOutOfBounds();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted for each payee added during construction.
    /// @param account Payee address.
    /// @param shares Share amount assigned.
    event PayeeAdded(address indexed account, uint256 shares);

    /// @notice Emitted when ETH is received.
    /// @param from Address that sent ETH.
    /// @param amount ETH amount received.
    event PaymentReceived(address indexed from, uint256 amount);

    /// @notice Emitted when ETH is released to a payee.
    /// @param to Payee address.
    /// @param amount ETH amount released.
    event PaymentReleased(address indexed to, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploys a new payment splitter with fixed payees and shares.
    /// @dev
    /// - Payees and shares arrays must have same length
    /// - No zero addresses allowed
    /// - No zero shares allowed
    /// - No duplicate payees allowed
    /// - Emits PayeeAdded for each payee
    /// @param _payees Array of payee addresses.
    /// @param _shares Array of share amounts (corresponding to payees).
    constructor(address[] memory _payees, uint256[] memory _shares) {
        if (_payees.length == 0) revert InvalidPayees();
        if (_shares.length == 0) revert InvalidShares();
        if (_payees.length != _shares.length) revert PayeesMustMatchShares();

        uint256 total = 0;
        for (uint256 i = 0; i < _payees.length; i++) {
            address payee = _payees[i];
            uint256 share = _shares[i];
            if (payee == address(0)) revert ZeroAddress();
            if (share == 0) revert ZeroShares();
            if (s_shares[payee] != 0) revert DuplicatePayee();
            s_payees.push(payee);
            s_shares[payee] = share;
            total += share;
            emit PayeeAdded(payee, share);
        }
        TOTAL_SHARES = total;
    }

    /*//////////////////////////////////////////////////////////////
                            RECEIVE
    //////////////////////////////////////////////////////////////*/

    /// @notice Accepts incoming ETH payments.
    /// @dev Emits PaymentReceived event.
    receive() external payable {
        emit PaymentReceived(msg.sender, msg.value);
    }

    /*//////////////////////////////////////////////////////////////
                        RELEASE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Releases pending payment to a payee.
    /// @dev
    /// - Anyone can call this for any payee
    /// - Calculates pending amount based on total received and shares
    /// - Uses CEI pattern: state updated before transfer
    /// - Reverts if account has no shares or nothing to release
    /// @param account Payee address to release funds to.
    function release(address payable account) external {
        if (s_shares[account] == 0) revert AccountHasNoShares();
        uint256 payment = releasable(account);
        if (payment == 0) revert NoPaymentDue();

        s_totalReleased += payment;
        s_released[account] += payment;

        (bool success, ) = account.call{value: payment}("");
        if (!success) revert TransferFailed();

        emit PaymentReleased(account, payment);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns total ETH ever received by the contract.
    /// @dev Formula: current balance + total already released.
    /// @return Total ETH received.
    function totalReceived() public view returns (uint256) {
        return address(this).balance + s_totalReleased;
    }

    /// @notice Returns total ETH already distributed.
    /// @return Total ETH released to all payees.
    function totalReleased() external view returns (uint256) {
        return s_totalReleased;
    }

    /// @notice Returns pending payment for a payee.
    /// @dev
    /// - Formula: (totalReceived * shares / totalShares) - released
    /// - Returns 0 if account has no shares
    /// @param account Payee address to check.
    /// @return Pending ETH amount.
    function releasable(address account) public view returns (uint256) {
        if (s_shares[account] == 0) return 0;
        uint256 totalAmount = totalReceived();
        uint256 alreadyReleased = s_released[account];
        uint256 entitled = (totalAmount * s_shares[account]) / TOTAL_SHARES;
        return entitled - alreadyReleased;
    }

    /// @notice Returns share amount for an account.
    /// @param account Address to check.
    /// @return Share amount (0 if not a payee).
    function getShares(address account) external view returns (uint256) {
        return s_shares[account];
    }

    /// @notice Returns ETH already released to an account.
    /// @param account Address to check.
    /// @return ETH already released.
    function getReleased(address account) external view returns (uint256) {
        return s_released[account];
    }

    /// @notice Returns array of all payee addresses.
    /// @return Array of payees.
    function getPayees() external view returns (address[] memory) {
        return s_payees;
    }

    /// @notice Returns payee address at specific index.
    /// @dev Reverts if index is out of bounds.
    /// @param index Index in payees array.
    /// @return Payee address.
    function getPayee(uint256 index) external view returns (address) {
        if (index >= s_payees.length) revert IndexOutOfBounds();
        return s_payees[index];
    }

    /// @notice Returns number of payees.
    /// @return Payee count.
    function getPayeeCount() external view returns (uint256) {
        return s_payees.length;
    }
}
