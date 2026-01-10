// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

/// @title MultiSigWallet
/// @notice A simple on-chain multi-signature wallet for managing native ETH
/// @dev
/// - Supports dynamic owners and dynamic approval threshold
/// - All actions (ETH transfers and governance changes) require multi-signature approval
/// - No single owner has special privileges
/// - ETH-only: no arbitrary calls, no token support

/*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/

contract MultiSigWallet {
    enum State {
        Pending,
        Executed
    }

    enum TxType {
        Transfer,
        AddOwner,
        RemoveOwner,
        ChangeThreshold
    }

    struct Transaction {
        TxType txType;
        address destination;
        uint256 amount;
        uint256 approvalCount;
        State state;
    }

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    address[] public owners;
    mapping(address => bool) public isOwner;

    uint256 public threshold;

    Transaction[] public transactions;
    mapping(uint256 => mapping(address => bool)) public approved;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error thresholdTooHigh(uint256 maxThreshold);
    error thresholdTooLow(uint256 minThreshold);
    error notEnoughOwners();
    error invalidOwner();
    error notOwner();
    error invalidDestination();
    error idNotExists();
    error invalidState();
    error cannotVoteTwice();
    error noApprovalToRevoke();
    error notEnoughApprovals();
    error PaymentFailed();

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyOwner() {
        if (!isOwner[msg.sender]) revert notOwner();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                EVENT
    //////////////////////////////////////////////////////////////*/

    event TransactionProposed(
        uint256 txId,
        address indexed proposer,
        address indexed destination,
        uint256 amount
    );

    event TransactionApproved(uint256 txId, address indexed owner);
    event TransactionRevoked(uint256 txId, address indexed owner);
    event TransactionExecuted(
        uint256 txId,
        address indexed destination,
        uint256 amount
    );

    event NewOwnerProposed(
        uint256 txId,
        address indexed proposer,
        address indexed newOwner
    );
    event RemoveOwnerProposed(
        uint256 txId,
        address indexed proposer,
        address indexed newOwner
    );
    event OwnerAdded(address indexed newOwner);

    event OwnerRemoved(address indexed newOwner);

    event ThresholdChanged(uint256 oldThreshold, uint256 newThreshold);
    event ThresholdChangeProposed(
        uint256 txId,
        address indexed proposer,
        uint256 newThreshold
    );

    event Deposit(address indexed sender, uint256 amount, uint256 balance);

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address[] memory _owners, uint256 _threshold) {
        if (_owners.length == 0) revert notEnoughOwners();
        for (uint256 i = 0; i < _owners.length; i++) {
            address _owner = _owners[i];
            if (_owner == address(0) || isOwner[_owner] == true)
                revert invalidOwner();
            owners.push(_owner);
            isOwner[_owner] = true;
        }

        if (_threshold > owners.length) revert thresholdTooHigh(owners.length);
        if (_threshold < 1) revert thresholdTooLow(1);
        threshold = _threshold;
    }

    /*//////////////////////////////////////////////////////////////
                         PROPOSE TRANSACTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Proposes a new ETH transfer transaction
    /// @dev
    /// - The caller must be an owner
    /// - The proposer automatically counts as the first approval
    /// - The transaction starts in Pending state
    /// @param _destination Address that will receive ETH if executed
    /// @param _amount Amount of ETH to transfer

    function propose(address _destination, uint256 _amount) public onlyOwner {
        if (_destination == (address(0))) revert invalidDestination();

        transactions.push(
            Transaction(
                TxType.Transfer,
                _destination,
                _amount,
                1,
                State.Pending
            )
        );
        uint256 _txId = transactions.length - 1;
        approved[_txId][msg.sender] = true;

        emit TransactionProposed(_txId, msg.sender, _destination, _amount);
    }

    /*//////////////////////////////////////////////////////////////
                         APPROVE TRANSACTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Approves a pending transaction
    /// @dev
    /// - Each owner can approve a transaction only once
    /// - Reverts if the transaction is not pending
    /// @param _txId ID of the transaction to approve

    function approve(uint256 _txId) public onlyOwner {
        if (_txId >= transactions.length) revert idNotExists();
        Transaction storage transaction = transactions[_txId];
        if (transaction.state != State.Pending) revert invalidState();
        if (approved[_txId][msg.sender]) revert cannotVoteTwice();
        transaction.approvalCount += 1;
        approved[_txId][msg.sender] = true;

        emit TransactionApproved(_txId, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                        REVOKE TRANSACTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Revokes a previously given approval
    /// @dev
    /// - Can only be called while the transaction is still pending
    /// - Decreases the approval count
    /// @param _txId ID of the transaction to revoke approval from

    function revoke(uint256 _txId) public onlyOwner {
        if (_txId >= transactions.length) revert idNotExists();
        Transaction storage transaction = transactions[_txId];
        if (transaction.state != State.Pending) revert invalidState();
        if (!approved[_txId][msg.sender]) revert noApprovalToRevoke();
        transaction.approvalCount -= 1;
        approved[_txId][msg.sender] = false;

        emit TransactionRevoked(_txId, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                       PROPOSE NEW OWNER
    //////////////////////////////////////////////////////////////*/

    /// @notice Proposes the addition of a new owner
    /// @dev
    /// - New owner cannot be the zero address
    /// - Duplicate owners are not allowed
    /// - Uses the same multisig approval flow as other transactions
    /// @param newOwner Address to be added as owner

    function proposeAddOwner(address newOwner) public onlyOwner {
        if (newOwner == (address(0))) revert invalidOwner();
        if (isOwner[newOwner]) revert invalidOwner();
        transactions.push(
            Transaction(TxType.AddOwner, newOwner, 0, 1, State.Pending)
        );
        uint256 _txId = transactions.length - 1;
        approved[_txId][msg.sender] = true;

        emit NewOwnerProposed(_txId, msg.sender, newOwner);
    }

    /*//////////////////////////////////////////////////////////////
                       PROPOSE REMOVE OWNER
    //////////////////////////////////////////////////////////////*/

    /// @notice Proposes the removal of an existing owner
    /// @dev
    /// - Cannot remove the last remaining owner
    /// - Cannot remove an owner if it would break the threshold invariant
    /// - Removed owners lose all pending approvals upon execution
    /// @param owner Address of the owner to remove

    function proposeRemoveOwner(address owner) public onlyOwner {
        if (owner == (address(0))) revert invalidOwner();
        if (!isOwner[owner]) revert invalidOwner();
        // protects from risk threshold >= ownerCount
        if (threshold > owners.length - 1) revert notEnoughOwners();
        // protects from risk ownerCount < 1
        if (owners.length <= 1) revert notEnoughOwners();

        transactions.push(
            Transaction(TxType.RemoveOwner, owner, 0, 1, State.Pending)
        );

        uint256 _txId = transactions.length - 1;
        approved[_txId][msg.sender] = true;
        emit RemoveOwnerProposed(_txId, msg.sender, owner);
    }

    /*//////////////////////////////////////////////////////////////
                       PROPOSE NEW THRESHOLD 
    //////////////////////////////////////////////////////////////*/

    /// @notice Proposes a change to the approval threshold
    /// @dev
    /// - New threshold must be between 1 and the current owner count
    /// - Change is applied only after multisig approval and execution
    /// @param newThreshold The new approval threshold

    function proposeChangeThreshold(uint256 newThreshold) public onlyOwner {
        if (newThreshold < 1) revert thresholdTooLow(1);
        if (newThreshold > owners.length)
            revert thresholdTooHigh(owners.length);
        transactions.push(
            Transaction(
                TxType.ChangeThreshold,
                address(0),
                newThreshold,
                1,
                State.Pending
            )
        );

        uint256 _txId = transactions.length - 1;
        approved[_txId][msg.sender] = true;
        emit ThresholdChangeProposed(_txId, msg.sender, newThreshold);
    }

    /*//////////////////////////////////////////////////////////////
                       EXECUTE TRANSACTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Executes a transaction once enough approvals have been collected
    /// @dev
    /// - Can be called by any owner
    /// - Requires approvalCount >= threshold
    /// - Applies different logic based on transaction type:
    ///   - Transfer: sends ETH
    ///   - AddOwner: adds a new owner
    ///   - RemoveOwner: removes an existing owner and cleans up approvals
    ///   - ChangeThreshold: updates the approval threshold
    /// - Marks the transaction as Executed before performing external calls
    /// @param _txId ID of the transaction to execute

    function execute(uint256 _txId) public onlyOwner {
        if (_txId >= transactions.length) revert idNotExists();

        Transaction storage transaction = transactions[_txId];
        if (transaction.state != State.Pending) revert invalidState();
        if (transaction.approvalCount < threshold) revert notEnoughApprovals();

        if (transaction.txType == TxType.Transfer) {
            address _destination = transaction.destination;
            uint256 _amount = transaction.amount;
            transaction.state = State.Executed;
            if (address(this).balance < _amount) revert PaymentFailed();
            (bool success, ) = payable(_destination).call{value: _amount}("");
            if (!success) revert PaymentFailed();
            emit TransactionExecuted(_txId, _destination, _amount);
        } else if (transaction.txType == TxType.AddOwner) {
            address _newOwner = transaction.destination;
            if (_newOwner == (address(0))) revert invalidOwner();
            if (isOwner[_newOwner]) revert invalidOwner();
            transaction.state = State.Executed;
            isOwner[_newOwner] = true;

            owners.push(_newOwner);
            emit OwnerAdded(_newOwner);
        } else if (transaction.txType == TxType.RemoveOwner) {
            address _owner = transaction.destination;
            if (_owner == (address(0))) revert invalidOwner();
            if (!isOwner[_owner]) revert invalidOwner();
            // protects from risk threshold >= ownerCount
            if (threshold > owners.length - 1) revert notEnoughOwners();
            // protects from risk ownerCount < 1
            if (owners.length <= 1) revert notEnoughOwners();

            transaction.state = State.Executed;

            isOwner[_owner] = false;

            uint256 ownersLength = owners.length;
            for (uint256 i = 0; i < ownersLength; i++) {
                if (owners[i] == _owner) {
                    owners[i] = owners[ownersLength - 1];
                    owners.pop();
                    break;
                }
            }
            // Remove all pending approvals from the removed owner
            // to ensure approval counts remain consistent

            for (uint256 i = 0; i < transactions.length; i++) {
                if (
                    transactions[i].state == State.Pending &&
                    approved[i][_owner]
                ) {
                    approved[i][_owner] = false;
                    transactions[i].approvalCount -= 1;
                }
            }

            emit OwnerRemoved(_owner);
        } else if (transaction.txType == TxType.ChangeThreshold) {
            uint256 newThreshold = transaction.amount;

            if (newThreshold < 1) revert thresholdTooLow(1);
            if (newThreshold > owners.length)
                revert thresholdTooHigh(owners.length);

            transaction.state = State.Executed;

            uint256 oldThreshold = threshold;
            threshold = newThreshold;

            emit ThresholdChanged(oldThreshold, newThreshold);
        }
    }

    /*//////////////////////////////////////////////////////////////
                       RECEIVE DEPOSITS
    //////////////////////////////////////////////////////////////*/

    /// @notice Accepts incoming ETH deposits
    /// @dev Emits a Deposit event with sender, amount, and new balance

    receive() external payable {
        emit Deposit(msg.sender, msg.value, address(this).balance);
    }
}
