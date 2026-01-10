// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "../../src/10-MultiSigWallet/MultiSigWallet.sol";

contract MultiSigWalletTest is Test {
    MultiSigWallet wallet;

    address owner1 = address(0xA11CE);
    address owner2 = address(0xB0B);
    address owner3 = address(0xCAFE);
    address attacker = address(0xBAD);
    address recipient = address(0xDEAD);

    // Events (redeclared for testing)
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
        address indexed owner
    );
    event OwnerAdded(address indexed newOwner);
    event OwnerRemoved(address indexed owner);
    event ThresholdChanged(uint256 oldThreshold, uint256 newThreshold);
    event ThresholdChangeProposed(
        uint256 txId,
        address indexed proposer,
        uint256 newThreshold
    );
    event Deposit(address indexed sender, uint256 amount, uint256 balance);

    function setUp() public {
        address[] memory owners = new address[](3);
        owners[0] = owner1;
        owners[1] = owner2;
        owners[2] = owner3;

        wallet = new MultiSigWallet(owners, 2);

        // Fund the wallet
        vm.deal(address(wallet), 10 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    function _proposeTransfer() internal returns (uint256) {
        vm.prank(owner1);
        wallet.propose(recipient, 1 ether);
        return 0;
    }

    function _proposeAndApprove() internal returns (uint256) {
        uint256 txId = _proposeTransfer();
        vm.prank(owner2);
        wallet.approve(txId);
        return txId;
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function testConstructorSetsOwnersCorrectly() public view {
        assertTrue(wallet.isOwner(owner1));
        assertTrue(wallet.isOwner(owner2));
        assertTrue(wallet.isOwner(owner3));
        assertFalse(wallet.isOwner(attacker));
    }

    function testConstructorSetsThreshold() public view {
        assertEq(wallet.threshold(), 2);
    }

    function testConstructorRevertsWithNoOwners() public {
        address[] memory emptyOwners = new address[](0);
        vm.expectRevert(MultiSigWallet.notEnoughOwners.selector);
        new MultiSigWallet(emptyOwners, 1);
    }

    function testConstructorRevertsWithZeroAddressOwner() public {
        address[] memory owners = new address[](2);
        owners[0] = owner1;
        owners[1] = address(0);

        vm.expectRevert(MultiSigWallet.invalidOwner.selector);
        new MultiSigWallet(owners, 1);
    }

    function testConstructorRevertsWithDuplicateOwner() public {
        address[] memory owners = new address[](2);
        owners[0] = owner1;
        owners[1] = owner1;

        vm.expectRevert(MultiSigWallet.invalidOwner.selector);
        new MultiSigWallet(owners, 1);
    }

    function testConstructorRevertsWithThresholdTooHigh() public {
        address[] memory owners = new address[](2);
        owners[0] = owner1;
        owners[1] = owner2;

        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.thresholdTooHigh.selector, 2));
        new MultiSigWallet(owners, 3);
    }

    function testConstructorRevertsWithZeroThreshold() public {
        address[] memory owners = new address[](2);
        owners[0] = owner1;
        owners[1] = owner2;

        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.thresholdTooLow.selector, 1));
        new MultiSigWallet(owners, 0);
    }

    /*//////////////////////////////////////////////////////////////
                            PROPOSE TRANSFER
    //////////////////////////////////////////////////////////////*/

    function testProposeCreatesTransaction() public {
        vm.prank(owner1);
        wallet.propose(recipient, 1 ether);

        (
            MultiSigWallet.TxType txType,
            address destination,
            uint256 amount,
            uint256 approvalCount,
            MultiSigWallet.State state
        ) = wallet.transactions(0);

        assertEq(uint256(txType), uint256(MultiSigWallet.TxType.Transfer));
        assertEq(destination, recipient);
        assertEq(amount, 1 ether);
        assertEq(approvalCount, 1); // proposer auto-approves
        assertEq(uint256(state), uint256(MultiSigWallet.State.Pending));
    }

    function testProposeAutoApprovesForProposer() public {
        vm.prank(owner1);
        wallet.propose(recipient, 1 ether);

        assertTrue(wallet.approved(0, owner1));
    }

    function testOnlyOwnerCanPropose() public {
        vm.prank(attacker);
        vm.expectRevert(MultiSigWallet.notOwner.selector);
        wallet.propose(recipient, 1 ether);
    }

    function testCannotProposeToZeroAddress() public {
        vm.prank(owner1);
        vm.expectRevert(MultiSigWallet.invalidDestination.selector);
        wallet.propose(address(0), 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            APPROVE
    //////////////////////////////////////////////////////////////*/

    function testOwnerCanApprove() public {
        _proposeTransfer();

        vm.prank(owner2);
        wallet.approve(0);

        assertTrue(wallet.approved(0, owner2));

        (, , , uint256 approvalCount, ) = wallet.transactions(0);
        assertEq(approvalCount, 2);
    }

    function testOnlyOwnerCanApprove() public {
        _proposeTransfer();

        vm.prank(attacker);
        vm.expectRevert(MultiSigWallet.notOwner.selector);
        wallet.approve(0);
    }

    function testCannotApproveNonExistentTx() public {
        vm.prank(owner1);
        vm.expectRevert(MultiSigWallet.idNotExists.selector);
        wallet.approve(999);
    }

    function testCannotApproveTwice() public {
        _proposeTransfer();

        vm.prank(owner1); // proposer already approved
        vm.expectRevert(MultiSigWallet.cannotVoteTwice.selector);
        wallet.approve(0);
    }

    function testCannotApproveExecutedTx() public {
        uint256 txId = _proposeAndApprove();

        vm.prank(owner1);
        wallet.execute(txId);

        vm.prank(owner3);
        vm.expectRevert(MultiSigWallet.invalidState.selector);
        wallet.approve(txId);
    }

    /*//////////////////////////////////////////////////////////////
                            REVOKE
    //////////////////////////////////////////////////////////////*/

    function testOwnerCanRevoke() public {
        _proposeTransfer();

        vm.prank(owner1);
        wallet.revoke(0);

        assertFalse(wallet.approved(0, owner1));

        (, , , uint256 approvalCount, ) = wallet.transactions(0);
        assertEq(approvalCount, 0);
    }

    function testOnlyOwnerCanRevoke() public {
        _proposeTransfer();

        vm.prank(attacker);
        vm.expectRevert(MultiSigWallet.notOwner.selector);
        wallet.revoke(0);
    }

    function testCannotRevokeWithoutApproval() public {
        _proposeTransfer();

        vm.prank(owner2); // owner2 never approved
        vm.expectRevert(MultiSigWallet.noApprovalToRevoke.selector);
        wallet.revoke(0);
    }

    function testCannotRevokeExecutedTx() public {
        uint256 txId = _proposeAndApprove();

        vm.prank(owner1);
        wallet.execute(txId);

        vm.prank(owner1);
        vm.expectRevert(MultiSigWallet.invalidState.selector);
        wallet.revoke(txId);
    }

    /*//////////////////////////////////////////////////////////////
                            EXECUTE TRANSFER
    //////////////////////////////////////////////////////////////*/

    function testExecuteTransfer() public {
        uint256 txId = _proposeAndApprove();
        uint256 recipientBalanceBefore = recipient.balance;

        vm.prank(owner1);
        wallet.execute(txId);

        assertEq(recipient.balance, recipientBalanceBefore + 1 ether);

        (, , , , MultiSigWallet.State state) = wallet.transactions(txId);
        assertEq(uint256(state), uint256(MultiSigWallet.State.Executed));
    }

    function testOnlyOwnerCanExecute() public {
        _proposeAndApprove();

        vm.prank(attacker);
        vm.expectRevert(MultiSigWallet.notOwner.selector);
        wallet.execute(0);
    }

    function testCannotExecuteWithoutEnoughApprovals() public {
        _proposeTransfer(); // only 1 approval, threshold is 2

        vm.prank(owner1);
        vm.expectRevert(MultiSigWallet.notEnoughApprovals.selector);
        wallet.execute(0);
    }

    function testCannotExecuteTwice() public {
        uint256 txId = _proposeAndApprove();

        vm.prank(owner1);
        wallet.execute(txId);

        vm.prank(owner1);
        vm.expectRevert(MultiSigWallet.invalidState.selector);
        wallet.execute(txId);
    }

    function testCannotExecuteWithInsufficientBalance() public {
        vm.prank(owner1);
        wallet.propose(recipient, 100 ether); // more than wallet balance

        vm.prank(owner2);
        wallet.approve(0);

        vm.prank(owner1);
        vm.expectRevert(MultiSigWallet.PaymentFailed.selector);
        wallet.execute(0);
    }

    /*//////////////////////////////////////////////////////////////
                            ADD OWNER
    //////////////////////////////////////////////////////////////*/

    function testProposeAddOwner() public {
        address newOwner = address(0x1234);

        vm.prank(owner1);
        wallet.proposeAddOwner(newOwner);

        (
            MultiSigWallet.TxType txType,
            address destination,
            ,
            uint256 approvalCount,
            MultiSigWallet.State state
        ) = wallet.transactions(0);

        assertEq(uint256(txType), uint256(MultiSigWallet.TxType.AddOwner));
        assertEq(destination, newOwner);
        assertEq(approvalCount, 1);
        assertEq(uint256(state), uint256(MultiSigWallet.State.Pending));
    }

    function testExecuteAddOwner() public {
        address newOwner = address(0x1234);

        vm.prank(owner1);
        wallet.proposeAddOwner(newOwner);

        vm.prank(owner2);
        wallet.approve(0);

        vm.prank(owner1);
        wallet.execute(0);

        assertTrue(wallet.isOwner(newOwner));
    }

    function testCannotAddZeroAddressOwner() public {
        vm.prank(owner1);
        vm.expectRevert(MultiSigWallet.invalidOwner.selector);
        wallet.proposeAddOwner(address(0));
    }

    function testCannotAddExistingOwner() public {
        vm.prank(owner1);
        vm.expectRevert(MultiSigWallet.invalidOwner.selector);
        wallet.proposeAddOwner(owner2);
    }

    /*//////////////////////////////////////////////////////////////
                            REMOVE OWNER
    //////////////////////////////////////////////////////////////*/

    function testProposeRemoveOwner() public {
        vm.prank(owner1);
        wallet.proposeRemoveOwner(owner3);

        (
            MultiSigWallet.TxType txType,
            address destination,
            ,
            ,
            MultiSigWallet.State state
        ) = wallet.transactions(0);

        assertEq(uint256(txType), uint256(MultiSigWallet.TxType.RemoveOwner));
        assertEq(destination, owner3);
        assertEq(uint256(state), uint256(MultiSigWallet.State.Pending));
    }

    function testExecuteRemoveOwner() public {
        vm.prank(owner1);
        wallet.proposeRemoveOwner(owner3);

        vm.prank(owner2);
        wallet.approve(0);

        vm.prank(owner1);
        wallet.execute(0);

        assertFalse(wallet.isOwner(owner3));
    }

    function testCannotRemoveNonOwner() public {
        vm.prank(owner1);
        vm.expectRevert(MultiSigWallet.invalidOwner.selector);
        wallet.proposeRemoveOwner(attacker);
    }

    function testCannotRemoveIfWouldBreakThreshold() public {
        // threshold is 2, owners are 3. If we remove 2, threshold > owners
        // First need to have only 2 owners
        address[] memory owners = new address[](2);
        owners[0] = owner1;
        owners[1] = owner2;

        MultiSigWallet smallWallet = new MultiSigWallet(owners, 2);

        vm.prank(owner1);
        vm.expectRevert(MultiSigWallet.notEnoughOwners.selector);
        smallWallet.proposeRemoveOwner(owner2);
    }

    function testRemovedOwnerLosesPendingApprovals() public {
        // owner3 proposes a transfer
        vm.prank(owner3);
        wallet.propose(recipient, 1 ether);

        // owner1 proposes to remove owner3
        vm.prank(owner1);
        wallet.proposeRemoveOwner(owner3);

        // owner2 approves removal
        vm.prank(owner2);
        wallet.approve(1);

        // Execute removal
        vm.prank(owner1);
        wallet.execute(1);

        // Check that owner3's approval on tx 0 was removed
        (, , , uint256 approvalCount, ) = wallet.transactions(0);
        assertEq(approvalCount, 0);
    }

    /*//////////////////////////////////////////////////////////////
                            CHANGE THRESHOLD
    //////////////////////////////////////////////////////////////*/

    function testProposeChangeThreshold() public {
        vm.prank(owner1);
        wallet.proposeChangeThreshold(1);

        (
            MultiSigWallet.TxType txType,
            ,
            uint256 amount,
            ,
            MultiSigWallet.State state
        ) = wallet.transactions(0);

        assertEq(uint256(txType), uint256(MultiSigWallet.TxType.ChangeThreshold));
        assertEq(amount, 1); // new threshold stored in amount field
        assertEq(uint256(state), uint256(MultiSigWallet.State.Pending));
    }

    function testExecuteChangeThreshold() public {
        vm.prank(owner1);
        wallet.proposeChangeThreshold(1);

        vm.prank(owner2);
        wallet.approve(0);

        vm.prank(owner1);
        wallet.execute(0);

        assertEq(wallet.threshold(), 1);
    }

    function testCannotSetThresholdTooLow() public {
        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.thresholdTooLow.selector, 1));
        wallet.proposeChangeThreshold(0);
    }

    function testCannotSetThresholdTooHigh() public {
        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSelector(MultiSigWallet.thresholdTooHigh.selector, 3));
        wallet.proposeChangeThreshold(4);
    }

    /*//////////////////////////////////////////////////////////////
                            RECEIVE ETH
    //////////////////////////////////////////////////////////////*/

    function testReceiveETH() public {
        uint256 balanceBefore = address(wallet).balance;

        vm.deal(attacker, 1 ether);
        vm.prank(attacker);
        (bool success, ) = address(wallet).call{value: 1 ether}("");

        assertTrue(success);
        assertEq(address(wallet).balance, balanceBefore + 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    function testTransactionProposedEventEmitted() public {
        vm.expectEmit(true, true, true, true);
        emit TransactionProposed(0, owner1, recipient, 1 ether);

        vm.prank(owner1);
        wallet.propose(recipient, 1 ether);
    }

    function testTransactionApprovedEventEmitted() public {
        _proposeTransfer();

        vm.expectEmit(true, true, false, true);
        emit TransactionApproved(0, owner2);

        vm.prank(owner2);
        wallet.approve(0);
    }

    function testTransactionRevokedEventEmitted() public {
        _proposeTransfer();

        vm.expectEmit(true, true, false, true);
        emit TransactionRevoked(0, owner1);

        vm.prank(owner1);
        wallet.revoke(0);
    }

    function testTransactionExecutedEventEmitted() public {
        _proposeAndApprove();

        vm.expectEmit(true, true, false, true);
        emit TransactionExecuted(0, recipient, 1 ether);

        vm.prank(owner1);
        wallet.execute(0);
    }

    function testOwnerAddedEventEmitted() public {
        address newOwner = address(0x1234);

        vm.prank(owner1);
        wallet.proposeAddOwner(newOwner);

        vm.prank(owner2);
        wallet.approve(0);

        vm.expectEmit(true, false, false, false);
        emit OwnerAdded(newOwner);

        vm.prank(owner1);
        wallet.execute(0);
    }

    function testOwnerRemovedEventEmitted() public {
        vm.prank(owner1);
        wallet.proposeRemoveOwner(owner3);

        vm.prank(owner2);
        wallet.approve(0);

        vm.expectEmit(true, false, false, false);
        emit OwnerRemoved(owner3);

        vm.prank(owner1);
        wallet.execute(0);
    }

    function testThresholdChangedEventEmitted() public {
        vm.prank(owner1);
        wallet.proposeChangeThreshold(1);

        vm.prank(owner2);
        wallet.approve(0);

        vm.expectEmit(false, false, false, true);
        emit ThresholdChanged(2, 1);

        vm.prank(owner1);
        wallet.execute(0);
    }

    function testDepositEventEmitted() public {
        vm.deal(attacker, 1 ether);

        vm.expectEmit(true, false, false, true);
        emit Deposit(attacker, 1 ether, address(wallet).balance + 1 ether);

        vm.prank(attacker);
        (bool success, ) = address(wallet).call{value: 1 ether}("");
        assertTrue(success);
    }
}
