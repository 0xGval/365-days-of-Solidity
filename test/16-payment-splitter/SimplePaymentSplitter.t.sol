// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test} from "lib/forge-std/src/Test.sol";
import {SimplePaymentSplitter} from "../../src/16-payment-splitter/SimplePaymentSplitter.sol";

contract SimplePaymentSplitterTest is Test {
    SimplePaymentSplitter splitter;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address charlie = address(0xC0C);
    address outsider = address(0x0DD);

    address[] payees;
    uint256[] shares;

    event PayeeAdded(address indexed account, uint256 shares);
    event PaymentReceived(address indexed from, uint256 amount);
    event PaymentReleased(address indexed to, uint256 amount);

    function setUp() public {
        // Default: 3 payees with 50/30/20 split
        payees = new address[](3);
        payees[0] = alice;
        payees[1] = bob;
        payees[2] = charlie;

        shares = new uint256[](3);
        shares[0] = 50;
        shares[1] = 30;
        shares[2] = 20;

        splitter = new SimplePaymentSplitter(payees, shares);
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function testConstructorSetsPayees() public view {
        assertEq(splitter.getPayee(0), alice);
        assertEq(splitter.getPayee(1), bob);
        assertEq(splitter.getPayee(2), charlie);
    }

    function testConstructorSetsShares() public view {
        assertEq(splitter.getShares(alice), 50);
        assertEq(splitter.getShares(bob), 30);
        assertEq(splitter.getShares(charlie), 20);
    }

    function testConstructorSetsTotalShares() public view {
        assertEq(splitter.TOTAL_SHARES(), 100);
    }

    function testConstructorSetsPayeeCount() public view {
        assertEq(splitter.getPayeeCount(), 3);
    }

    function testConstructorEmitsPayeeAddedEvents() public {
        address[] memory newPayees = new address[](2);
        newPayees[0] = alice;
        newPayees[1] = bob;

        uint256[] memory newShares = new uint256[](2);
        newShares[0] = 60;
        newShares[1] = 40;

        vm.expectEmit(true, false, false, true);
        emit PayeeAdded(alice, 60);
        vm.expectEmit(true, false, false, true);
        emit PayeeAdded(bob, 40);

        new SimplePaymentSplitter(newPayees, newShares);
    }

    function testConstructorRevertsIfPayeesEmpty() public {
        address[] memory emptyPayees = new address[](0);
        uint256[] memory emptyShares = new uint256[](0);

        vm.expectRevert(SimplePaymentSplitter.InvalidPayees.selector);
        new SimplePaymentSplitter(emptyPayees, emptyShares);
    }

    function testConstructorRevertsIfSharesEmpty() public {
        address[] memory newPayees = new address[](1);
        newPayees[0] = alice;
        uint256[] memory emptyShares = new uint256[](0);

        vm.expectRevert(SimplePaymentSplitter.InvalidShares.selector);
        new SimplePaymentSplitter(newPayees, emptyShares);
    }

    function testConstructorRevertsIfArrayLengthsMismatch() public {
        address[] memory newPayees = new address[](2);
        newPayees[0] = alice;
        newPayees[1] = bob;

        uint256[] memory newShares = new uint256[](1);
        newShares[0] = 100;

        vm.expectRevert(SimplePaymentSplitter.PayeesMustMatchShares.selector);
        new SimplePaymentSplitter(newPayees, newShares);
    }

    function testConstructorRevertsIfPayeeIsZeroAddress() public {
        address[] memory newPayees = new address[](2);
        newPayees[0] = alice;
        newPayees[1] = address(0);

        uint256[] memory newShares = new uint256[](2);
        newShares[0] = 50;
        newShares[1] = 50;

        vm.expectRevert(SimplePaymentSplitter.ZeroAddress.selector);
        new SimplePaymentSplitter(newPayees, newShares);
    }

    function testConstructorRevertsIfShareIsZero() public {
        address[] memory newPayees = new address[](2);
        newPayees[0] = alice;
        newPayees[1] = bob;

        uint256[] memory newShares = new uint256[](2);
        newShares[0] = 100;
        newShares[1] = 0;

        vm.expectRevert(SimplePaymentSplitter.ZeroShares.selector);
        new SimplePaymentSplitter(newPayees, newShares);
    }

    function testConstructorRevertsIfDuplicatePayee() public {
        address[] memory newPayees = new address[](2);
        newPayees[0] = alice;
        newPayees[1] = alice;

        uint256[] memory newShares = new uint256[](2);
        newShares[0] = 50;
        newShares[1] = 50;

        vm.expectRevert(SimplePaymentSplitter.DuplicatePayee.selector);
        new SimplePaymentSplitter(newPayees, newShares);
    }

    /*//////////////////////////////////////////////////////////////
                            RECEIVE ETH
    //////////////////////////////////////////////////////////////*/

    function testReceiveAcceptsETH() public {
        vm.deal(outsider, 1 ether);
        vm.prank(outsider);
        (bool success,) = address(splitter).call{value: 1 ether}("");

        assertTrue(success);
        assertEq(address(splitter).balance, 1 ether);
    }

    function testReceiveEmitsPaymentReceivedEvent() public {
        vm.deal(outsider, 1 ether);

        vm.expectEmit(true, false, false, true);
        emit PaymentReceived(outsider, 1 ether);

        vm.prank(outsider);
        (bool success,) = address(splitter).call{value: 1 ether}("");
        assertTrue(success);
    }

    function testReceiveFromAnySender() public {
        vm.deal(alice, 1 ether);
        vm.deal(outsider, 1 ether);

        vm.prank(alice);
        (bool success1,) = address(splitter).call{value: 0.5 ether}("");
        assertTrue(success1);

        vm.prank(outsider);
        (bool success2,) = address(splitter).call{value: 0.5 ether}("");
        assertTrue(success2);

        assertEq(address(splitter).balance, 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            TOTAL RECEIVED
    //////////////////////////////////////////////////////////////*/

    function testTotalReceivedReturnsZeroInitially() public view {
        assertEq(splitter.totalReceived(), 0);
    }

    function testTotalReceivedReturnsBalance() public {
        vm.deal(outsider, 1 ether);
        vm.prank(outsider);
        (bool success,) = address(splitter).call{value: 1 ether}("");
        assertTrue(success);

        assertEq(splitter.totalReceived(), 1 ether);
    }

    function testTotalReceivedIncludesReleased() public {
        vm.deal(outsider, 1 ether);
        vm.prank(outsider);
        (bool success,) = address(splitter).call{value: 1 ether}("");
        assertTrue(success);

        // Release Alice's share (50%)
        splitter.release(payable(alice));

        // totalReceived should still be 1 ether
        assertEq(splitter.totalReceived(), 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            RELEASABLE
    //////////////////////////////////////////////////////////////*/

    function testReleasableReturnsZeroForNonPayee() public view {
        assertEq(splitter.releasable(outsider), 0);
    }

    function testReleasableReturnsZeroWhenNothingReceived() public view {
        assertEq(splitter.releasable(alice), 0);
    }

    function testReleasableReturnsCorrectAmount() public {
        vm.deal(outsider, 1 ether);
        vm.prank(outsider);
        (bool success,) = address(splitter).call{value: 1 ether}("");
        assertTrue(success);

        // Alice: 50%, Bob: 30%, Charlie: 20%
        assertEq(splitter.releasable(alice), 0.5 ether);
        assertEq(splitter.releasable(bob), 0.3 ether);
        assertEq(splitter.releasable(charlie), 0.2 ether);
    }

    function testReleasableAccountsForAlreadyReleased() public {
        vm.deal(outsider, 1 ether);
        vm.prank(outsider);
        (bool success,) = address(splitter).call{value: 1 ether}("");
        assertTrue(success);

        // Release Alice's share
        splitter.release(payable(alice));

        // Alice should have 0 releasable now
        assertEq(splitter.releasable(alice), 0);
    }

    function testReleasableAfterMultipleDeposits() public {
        // First deposit: 1 ether
        vm.deal(outsider, 2 ether);
        vm.prank(outsider);
        (bool success1,) = address(splitter).call{value: 1 ether}("");
        assertTrue(success1);

        // Alice releases her 0.5 ether
        splitter.release(payable(alice));
        assertEq(splitter.releasable(alice), 0);

        // Second deposit: 1 ether more
        vm.prank(outsider);
        (bool success2,) = address(splitter).call{value: 1 ether}("");
        assertTrue(success2);

        // Alice should have 0.5 ether releasable (50% of new deposit)
        assertEq(splitter.releasable(alice), 0.5 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            RELEASE
    //////////////////////////////////////////////////////////////*/

    function testReleaseTransfersCorrectAmount() public {
        vm.deal(outsider, 1 ether);
        vm.prank(outsider);
        (bool success,) = address(splitter).call{value: 1 ether}("");
        assertTrue(success);

        uint256 aliceBalanceBefore = alice.balance;

        splitter.release(payable(alice));

        assertEq(alice.balance, aliceBalanceBefore + 0.5 ether);
    }

    function testReleaseUpdatesReleasedMapping() public {
        vm.deal(outsider, 1 ether);
        vm.prank(outsider);
        (bool success,) = address(splitter).call{value: 1 ether}("");
        assertTrue(success);

        splitter.release(payable(alice));

        assertEq(splitter.getReleased(alice), 0.5 ether);
    }

    function testReleaseUpdatesTotalReleased() public {
        vm.deal(outsider, 1 ether);
        vm.prank(outsider);
        (bool success,) = address(splitter).call{value: 1 ether}("");
        assertTrue(success);

        splitter.release(payable(alice));

        assertEq(splitter.totalReleased(), 0.5 ether);
    }

    function testReleaseEmitsPaymentReleasedEvent() public {
        vm.deal(outsider, 1 ether);
        vm.prank(outsider);
        (bool success,) = address(splitter).call{value: 1 ether}("");
        assertTrue(success);

        vm.expectEmit(true, false, false, true);
        emit PaymentReleased(alice, 0.5 ether);

        splitter.release(payable(alice));
    }

    function testReleaseRevertsForNonPayee() public {
        vm.deal(outsider, 1 ether);
        vm.prank(outsider);
        (bool success,) = address(splitter).call{value: 1 ether}("");
        assertTrue(success);

        vm.expectRevert(SimplePaymentSplitter.AccountHasNoShares.selector);
        splitter.release(payable(outsider));
    }

    function testReleaseRevertsWhenNothingDue() public {
        // No ETH received
        vm.expectRevert(SimplePaymentSplitter.NoPaymentDue.selector);
        splitter.release(payable(alice));
    }

    function testReleaseRevertsOnDoubleRelease() public {
        vm.deal(outsider, 1 ether);
        vm.prank(outsider);
        (bool success,) = address(splitter).call{value: 1 ether}("");
        assertTrue(success);

        splitter.release(payable(alice));

        // Try to release again immediately
        vm.expectRevert(SimplePaymentSplitter.NoPaymentDue.selector);
        splitter.release(payable(alice));
    }

    function testAnyoneCanCallRelease() public {
        vm.deal(outsider, 1 ether);
        vm.prank(outsider);
        (bool success,) = address(splitter).call{value: 1 ether}("");
        assertTrue(success);

        uint256 aliceBalanceBefore = alice.balance;

        // Outsider calls release for Alice
        vm.prank(outsider);
        splitter.release(payable(alice));

        assertEq(alice.balance, aliceBalanceBefore + 0.5 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        MULTI-PAYEE SCENARIOS
    //////////////////////////////////////////////////////////////*/

    function testTwoPayeesEqualShares() public {
        address[] memory newPayees = new address[](2);
        newPayees[0] = alice;
        newPayees[1] = bob;

        uint256[] memory newShares = new uint256[](2);
        newShares[0] = 50;
        newShares[1] = 50;

        SimplePaymentSplitter equalSplitter = new SimplePaymentSplitter(newPayees, newShares);

        vm.deal(outsider, 1 ether);
        vm.prank(outsider);
        (bool success,) = address(equalSplitter).call{value: 1 ether}("");
        assertTrue(success);

        assertEq(equalSplitter.releasable(alice), 0.5 ether);
        assertEq(equalSplitter.releasable(bob), 0.5 ether);
    }

    function testThreePayeesUnequalShares() public {
        vm.deal(outsider, 1 ether);
        vm.prank(outsider);
        (bool success,) = address(splitter).call{value: 1 ether}("");
        assertTrue(success);

        // Release all
        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;
        uint256 charlieBefore = charlie.balance;

        splitter.release(payable(alice));
        splitter.release(payable(bob));
        splitter.release(payable(charlie));

        assertEq(alice.balance - aliceBefore, 0.5 ether);
        assertEq(bob.balance - bobBefore, 0.3 ether);
        assertEq(charlie.balance - charlieBefore, 0.2 ether);
    }

    function testMultipleDepositsOverTime() public {
        vm.deal(outsider, 3 ether);

        // First deposit
        vm.prank(outsider);
        (bool success1,) = address(splitter).call{value: 1 ether}("");
        assertTrue(success1);

        // Alice releases
        splitter.release(payable(alice));
        assertEq(splitter.getReleased(alice), 0.5 ether);

        // Second deposit
        vm.prank(outsider);
        (bool success2,) = address(splitter).call{value: 1 ether}("");
        assertTrue(success2);

        // Bob releases (gets 30% of 2 ether total)
        splitter.release(payable(bob));
        assertEq(splitter.getReleased(bob), 0.6 ether);

        // Third deposit
        vm.prank(outsider);
        (bool success3,) = address(splitter).call{value: 1 ether}("");
        assertTrue(success3);

        // Everyone releases remaining
        splitter.release(payable(alice));
        splitter.release(payable(bob));
        splitter.release(payable(charlie));

        // Total: 3 ether distributed as 50/30/20
        assertEq(splitter.getReleased(alice), 1.5 ether);
        assertEq(splitter.getReleased(bob), 0.9 ether);
        assertEq(splitter.getReleased(charlie), 0.6 ether);
    }

    function testPartialReleases() public {
        vm.deal(outsider, 1 ether);
        vm.prank(outsider);
        (bool success,) = address(splitter).call{value: 1 ether}("");
        assertTrue(success);

        // Only Alice releases
        splitter.release(payable(alice));

        // Bob and Charlie haven't released
        assertEq(splitter.getReleased(bob), 0);
        assertEq(splitter.getReleased(charlie), 0);

        // They can still release later
        assertEq(splitter.releasable(bob), 0.3 ether);
        assertEq(splitter.releasable(charlie), 0.2 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function testGetSharesReturnsZeroForNonPayee() public view {
        assertEq(splitter.getShares(outsider), 0);
    }

    function testGetReleasedReturnsZeroInitially() public view {
        assertEq(splitter.getReleased(alice), 0);
    }

    function testGetPayeesReturnsFullArray() public view {
        address[] memory result = splitter.getPayees();

        assertEq(result.length, 3);
        assertEq(result[0], alice);
        assertEq(result[1], bob);
        assertEq(result[2], charlie);
    }

    function testGetPayeeReturnsCorrectAddress() public view {
        assertEq(splitter.getPayee(0), alice);
        assertEq(splitter.getPayee(1), bob);
        assertEq(splitter.getPayee(2), charlie);
    }

    function testGetPayeeRevertsOnInvalidIndex() public {
        vm.expectRevert(SimplePaymentSplitter.IndexOutOfBounds.selector);
        splitter.getPayee(3);

        vm.expectRevert(SimplePaymentSplitter.IndexOutOfBounds.selector);
        splitter.getPayee(100);
    }

    function testGetPayeeCountReturnsCorrectCount() public view {
        assertEq(splitter.getPayeeCount(), 3);
    }

    /*//////////////////////////////////////////////////////////////
                            EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function testSinglePayee() public {
        address[] memory newPayees = new address[](1);
        newPayees[0] = alice;

        uint256[] memory newShares = new uint256[](1);
        newShares[0] = 100;

        SimplePaymentSplitter singleSplitter = new SimplePaymentSplitter(newPayees, newShares);

        vm.deal(outsider, 1 ether);
        vm.prank(outsider);
        (bool success,) = address(singleSplitter).call{value: 1 ether}("");
        assertTrue(success);

        // Alice gets 100%
        assertEq(singleSplitter.releasable(alice), 1 ether);

        singleSplitter.release(payable(alice));
        assertEq(alice.balance, 1 ether);
    }

    function testVerySmallPayment() public {
        vm.deal(outsider, 100 wei);
        vm.prank(outsider);
        (bool success,) = address(splitter).call{value: 100 wei}("");
        assertTrue(success);

        // 50% of 100 = 50 wei
        assertEq(splitter.releasable(alice), 50);
        // 30% of 100 = 30 wei
        assertEq(splitter.releasable(bob), 30);
        // 20% of 100 = 20 wei
        assertEq(splitter.releasable(charlie), 20);
    }

    function testIntegerDivisionRounding() public {
        // Create splitter with shares that don't divide evenly
        address[] memory newPayees = new address[](3);
        newPayees[0] = alice;
        newPayees[1] = bob;
        newPayees[2] = charlie;

        uint256[] memory newShares = new uint256[](3);
        newShares[0] = 33;
        newShares[1] = 33;
        newShares[2] = 34;

        SimplePaymentSplitter oddSplitter = new SimplePaymentSplitter(newPayees, newShares);

        vm.deal(outsider, 100 wei);
        vm.prank(outsider);
        (bool success,) = address(oddSplitter).call{value: 100 wei}("");
        assertTrue(success);

        // 33/100 * 100 = 33 wei each for alice and bob
        // 34/100 * 100 = 34 wei for charlie
        assertEq(oddSplitter.releasable(alice), 33);
        assertEq(oddSplitter.releasable(bob), 33);
        assertEq(oddSplitter.releasable(charlie), 34);
    }

    function testReleaseWhenBalanceIsZeroButTotalReceivedPositive() public {
        vm.deal(outsider, 1 ether);
        vm.prank(outsider);
        (bool success,) = address(splitter).call{value: 1 ether}("");
        assertTrue(success);

        // Release all
        splitter.release(payable(alice));
        splitter.release(payable(bob));
        splitter.release(payable(charlie));

        // Balance is now 0
        assertEq(address(splitter).balance, 0);
        // But totalReceived is still 1 ether
        assertEq(splitter.totalReceived(), 1 ether);

        // Try to release again - should revert
        vm.expectRevert(SimplePaymentSplitter.NoPaymentDue.selector);
        splitter.release(payable(alice));
    }

    function testLargeNumberOfPayees() public {
        uint256 numPayees = 10;
        address[] memory manyPayees = new address[](numPayees);
        uint256[] memory manyShares = new uint256[](numPayees);

        for (uint256 i = 0; i < numPayees; i++) {
            manyPayees[i] = address(uint160(i + 1));
            manyShares[i] = 10; // Equal 10% each
        }

        SimplePaymentSplitter largeSplitter = new SimplePaymentSplitter(manyPayees, manyShares);

        vm.deal(outsider, 10 ether);
        vm.prank(outsider);
        (bool success,) = address(largeSplitter).call{value: 10 ether}("");
        assertTrue(success);

        // Each payee should get 1 ether (10%)
        for (uint256 i = 0; i < numPayees; i++) {
            assertEq(largeSplitter.releasable(manyPayees[i]), 1 ether);
        }
    }

    function testZeroValueTransfer() public {
        vm.deal(outsider, 1 ether);

        // Send 0 wei - should work (receive has no minimum)
        vm.prank(outsider);
        (bool success,) = address(splitter).call{value: 0}("");
        assertTrue(success);

        // No ETH received
        assertEq(splitter.totalReceived(), 0);
    }
}
