// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {Test} from "lib/forge-std/src/Test.sol";
import {FriendTechv2} from "../../src/18-social-shares/SimpleShares.sol";

contract FriendTechv2Test is Test {
    FriendTechv2 ft;

    address owner = address(this);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address charlie = address(0xC0C);

    uint256 constant SUBJECT_FEE = 500; // 5%
    uint256 constant PROTOCOL_FEE = 500; // 5%
    uint256 constant BASIS_POINTS = 10000;

    event Registered(address indexed user);
    event Trade(address indexed user, address indexed target, bool firstBuy);

    // Allow test contract to receive ETH (as protocol fee recipient)
    receive() external payable {}

    function setUp() public {
        ft = new FriendTechv2(SUBJECT_FEE, PROTOCOL_FEE);

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
        vm.deal(owner, 100 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function testConstructorSetsOwner() public view {
        assertEq(ft.i_owner(), owner);
    }

    function testConstructorSetsSubjectFee() public view {
        assertEq(ft.i_subjectFeePercent(), SUBJECT_FEE);
    }

    function testConstructorSetsProtocolFee() public view {
        assertEq(ft.i_protocolFeePercent(), PROTOCOL_FEE);
    }

    function testConstructorRevertsIfSubjectFeeTooHigh() public {
        vm.expectRevert(FriendTechv2.FeeTooHigh.selector);
        new FriendTechv2(5001, PROTOCOL_FEE);
    }

    function testConstructorRevertsIfProtocolFeeTooHigh() public {
        vm.expectRevert(FriendTechv2.FeeTooHigh.selector);
        new FriendTechv2(SUBJECT_FEE, 5001);
    }

    function testConstructorAllowsMaxFee() public {
        FriendTechv2 ftMax = new FriendTechv2(5000, 5000);
        assertEq(ftMax.i_subjectFeePercent(), 5000);
        assertEq(ftMax.i_protocolFeePercent(), 5000);
    }

    /*//////////////////////////////////////////////////////////////
                            SIGNUP TESTS
    //////////////////////////////////////////////////////////////*/

    function testSignUpSucceeds() public {
        vm.prank(alice);
        ft.signUp("alice");

        assertTrue(ft.isRegistered(alice));
        assertEq(ft.sharesSupply(alice), 0);
    }

    function testSignUpSetsSubjectData() public {
        vm.prank(alice);
        ft.signUp("alice_user");

        (uint256 registeredAt, uint256 totalVolume, uint256 totalFeesEarned, string memory username) =
            ft.subjectData(alice);

        assertEq(registeredAt, block.timestamp);
        assertEq(totalVolume, 0);
        assertEq(totalFeesEarned, 0);
        assertEq(username, "alice_user");
    }

    function testSignUpEmitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit Registered(alice);

        vm.prank(alice);
        ft.signUp("alice");
    }

    function testSignUpRevertsIfAlreadyRegistered() public {
        vm.prank(alice);
        ft.signUp("alice");

        vm.prank(alice);
        vm.expectRevert(FriendTechv2.AlreadyRegistered.selector);
        ft.signUp("alice2");
    }

    function testSignUpRevertsIfUsernameEmpty() public {
        vm.prank(alice);
        vm.expectRevert(FriendTechv2.InvalidUsername.selector);
        ft.signUp("");
    }

    function testMultipleUsersCanSignUp() public {
        vm.prank(alice);
        ft.signUp("alice");

        vm.prank(bob);
        ft.signUp("bob");

        assertTrue(ft.isRegistered(alice));
        assertTrue(ft.isRegistered(bob));
    }

    /*//////////////////////////////////////////////////////////////
                        BUY FIRST SHARE TESTS
    //////////////////////////////////////////////////////////////*/

    function testBuyFirstShareSucceeds() public {
        vm.prank(alice);
        ft.signUp("alice");

        vm.prank(alice);
        ft.buyFirstShare();

        assertEq(ft.sharesSupply(alice), 1);
        assertEq(ft.sharesBalance(alice, alice), 1);
    }

    function testBuyFirstShareEmitsEvent() public {
        vm.prank(alice);
        ft.signUp("alice");

        vm.expectEmit(true, true, false, true);
        emit Trade(alice, alice, true);

        vm.prank(alice);
        ft.buyFirstShare();
    }

    function testBuyFirstShareRevertsIfNotRegistered() public {
        vm.prank(alice);
        vm.expectRevert(FriendTechv2.NotRegistered.selector);
        ft.buyFirstShare();
    }

    function testBuyFirstShareRevertsIfAlreadyHasShares() public {
        vm.prank(alice);
        ft.signUp("alice");

        vm.prank(alice);
        ft.buyFirstShare();

        vm.prank(alice);
        vm.expectRevert(FriendTechv2.AlreadyHasShares.selector);
        ft.buyFirstShare();
    }

    function testIsSubjectActiveAfterFirstShare() public {
        vm.prank(alice);
        ft.signUp("alice");

        assertFalse(ft.isSubjectActive(alice));

        vm.prank(alice);
        ft.buyFirstShare();

        assertTrue(ft.isSubjectActive(alice));
    }

    /*//////////////////////////////////////////////////////////////
                        BUY SHARES TESTS
    //////////////////////////////////////////////////////////////*/

    function testBuySharesSucceeds() public {
        _setupActiveSubject(alice, "alice");

        uint256 price = ft.getBuyPrice(alice, 1);
        uint256 totalCost = _getTotalCost(price);

        vm.prank(bob);
        ft.buyShares{value: totalCost}(alice, 1);

        assertEq(ft.sharesBalance(alice, bob), 1);
        assertEq(ft.sharesSupply(alice), 2); // 1 first + 1 bought
    }

    function testBuyMultipleShares() public {
        _setupActiveSubject(alice, "alice");

        uint256 price = ft.getBuyPrice(alice, 5);
        uint256 totalCost = _getTotalCost(price);

        vm.prank(bob);
        ft.buyShares{value: totalCost}(alice, 5);

        assertEq(ft.sharesBalance(alice, bob), 5);
        assertEq(ft.sharesSupply(alice), 6);
    }

    function testBuySharesTransfersSubjectFee() public {
        _setupActiveSubject(alice, "alice");

        uint256 aliceBalanceBefore = alice.balance;
        uint256 price = ft.getBuyPrice(alice, 1);
        uint256 subjectFee = (price * SUBJECT_FEE) / BASIS_POINTS;
        uint256 totalCost = _getTotalCost(price);

        vm.prank(bob);
        ft.buyShares{value: totalCost}(alice, 1);

        assertEq(alice.balance, aliceBalanceBefore + subjectFee);
    }

    function testBuySharesTransfersProtocolFee() public {
        _setupActiveSubject(alice, "alice");

        uint256 ownerBalanceBefore = owner.balance;
        uint256 price = ft.getBuyPrice(alice, 1);
        uint256 protocolFee = (price * PROTOCOL_FEE) / BASIS_POINTS;
        uint256 totalCost = _getTotalCost(price);

        vm.prank(bob);
        ft.buyShares{value: totalCost}(alice, 1);

        assertEq(owner.balance, ownerBalanceBefore + protocolFee);
    }

    function testBuySharesRefundsExcess() public {
        _setupActiveSubject(alice, "alice");

        uint256 price = ft.getBuyPrice(alice, 1);
        uint256 totalCost = _getTotalCost(price);
        uint256 excess = 1 ether;

        uint256 bobBalanceBefore = bob.balance;

        vm.prank(bob);
        ft.buyShares{value: totalCost + excess}(alice, 1);

        assertEq(bob.balance, bobBalanceBefore - totalCost);
    }

    function testBuySharesEmitsEvent() public {
        _setupActiveSubject(alice, "alice");

        uint256 price = ft.getBuyPrice(alice, 1);
        uint256 totalCost = _getTotalCost(price);

        vm.expectEmit(true, true, false, true);
        emit Trade(bob, alice, false);

        vm.prank(bob);
        ft.buyShares{value: totalCost}(alice, 1);
    }

    function testBuySharesUpdatesVolume() public {
        _setupActiveSubject(alice, "alice");

        uint256 price = ft.getBuyPrice(alice, 1);
        uint256 totalCost = _getTotalCost(price);

        vm.prank(bob);
        ft.buyShares{value: totalCost}(alice, 1);

        (, uint256 totalVolume,,) = ft.subjectData(alice);
        assertEq(totalVolume, totalCost);
    }

    function testBuySharesUpdatesFeeEarned() public {
        _setupActiveSubject(alice, "alice");

        uint256 price = ft.getBuyPrice(alice, 1);
        uint256 subjectFee = (price * SUBJECT_FEE) / BASIS_POINTS;
        uint256 totalCost = _getTotalCost(price);

        vm.prank(bob);
        ft.buyShares{value: totalCost}(alice, 1);

        (,, uint256 totalFeesEarned,) = ft.subjectData(alice);
        assertEq(totalFeesEarned, subjectFee);
    }

    function testBuySharesRevertsIfAmountZero() public {
        _setupActiveSubject(alice, "alice");

        vm.prank(bob);
        vm.expectRevert(FriendTechv2.InvalidAmount.selector);
        ft.buyShares{value: 1 ether}(alice, 0);
    }

    function testBuySharesRevertsIfSubjectNotRegistered() public {
        vm.prank(bob);
        vm.expectRevert(FriendTechv2.SubjectNotRegistered.selector);
        ft.buyShares{value: 1 ether}(alice, 1);
    }

    function testBuySharesRevertsIfSubjectNotActive() public {
        vm.prank(alice);
        ft.signUp("alice");

        vm.prank(bob);
        vm.expectRevert(FriendTechv2.SubjectNotActive.selector);
        ft.buyShares{value: 1 ether}(alice, 1);
    }

    function testBuySharesRevertsIfInsufficientPayment() public {
        _setupActiveSubject(alice, "alice");

        uint256 price = ft.getBuyPrice(alice, 1);
        uint256 totalCost = _getTotalCost(price);

        vm.prank(bob);
        vm.expectRevert(FriendTechv2.InsufficientPayment.selector);
        ft.buyShares{value: totalCost - 1}(alice, 1);
    }

    function testBuySharesRevertsIfZeroAddress() public {
        vm.prank(bob);
        vm.expectRevert(FriendTechv2.InvalidSubject.selector);
        ft.buyShares{value: 1 ether}(address(0), 1);
    }

    /*//////////////////////////////////////////////////////////////
                        SELL SHARES TESTS
    //////////////////////////////////////////////////////////////*/

    function testSellSharesSucceeds() public {
        _setupActiveSubject(alice, "alice");
        _buyShares(bob, alice, 2);

        uint256 bobBalanceBefore = bob.balance;
        uint256 price = ft.getSellPrice(alice, 1);
        uint256 proceeds = _getProceeds(price);

        vm.prank(bob);
        ft.sellShares(alice, 1);

        assertEq(ft.sharesBalance(alice, bob), 1);
        assertEq(ft.sharesSupply(alice), 2); // 1 first + 2 bought - 1 sold
        assertEq(bob.balance, bobBalanceBefore + proceeds);
    }

    function testSellMultipleShares() public {
        _setupActiveSubject(alice, "alice");
        _buyShares(bob, alice, 5);

        vm.prank(bob);
        ft.sellShares(alice, 3);

        assertEq(ft.sharesBalance(alice, bob), 2);
        assertEq(ft.sharesSupply(alice), 3); // 1 + 5 - 3
    }

    function testSellSharesTransfersFees() public {
        _setupActiveSubject(alice, "alice");
        _buyShares(bob, alice, 2);

        uint256 aliceBalanceBefore = alice.balance;
        uint256 ownerBalanceBefore = owner.balance;

        uint256 price = ft.getSellPrice(alice, 1);
        uint256 subjectFee = (price * SUBJECT_FEE) / BASIS_POINTS;
        uint256 protocolFee = (price * PROTOCOL_FEE) / BASIS_POINTS;

        vm.prank(bob);
        ft.sellShares(alice, 1);

        assertEq(alice.balance, aliceBalanceBefore + subjectFee);
        assertEq(owner.balance, ownerBalanceBefore + protocolFee);
    }

    function testSellSharesEmitsEvent() public {
        _setupActiveSubject(alice, "alice");
        _buyShares(bob, alice, 1);

        vm.expectEmit(true, true, false, true);
        emit Trade(bob, alice, false);

        vm.prank(bob);
        ft.sellShares(alice, 1);
    }

    function testSellSharesRevertsIfAmountZero() public {
        _setupActiveSubject(alice, "alice");
        _buyShares(bob, alice, 1);

        vm.prank(bob);
        vm.expectRevert(FriendTechv2.InvalidAmount.selector);
        ft.sellShares(alice, 0);
    }

    function testSellSharesRevertsIfInsufficientShares() public {
        _setupActiveSubject(alice, "alice");
        _buyShares(bob, alice, 1);

        vm.prank(bob);
        vm.expectRevert(FriendTechv2.InsufficientShares.selector);
        ft.sellShares(alice, 2);
    }

    function testSellSharesRevertsIfLastShareByNonSubject() public {
        _setupActiveSubject(alice, "alice");
        _buyShares(bob, alice, 1);

        // Sell bob's share (supply goes from 2 to 1)
        vm.prank(bob);
        ft.sellShares(alice, 1);

        // Now only alice has 1 share (first share)
        // Bob cannot sell alice's last share (he has 0 shares anyway)
        // Let's test with alice transferring to bob scenario:
        // Actually, bob has 0 shares now. Let's setup differently

        // Create fresh scenario
        FriendTechv2 ft2 = new FriendTechv2(SUBJECT_FEE, PROTOCOL_FEE);

        vm.prank(alice);
        ft2.signUp("alice");
        vm.prank(alice);
        ft2.buyFirstShare();

        // Alice sells her first share to bob (not possible directly, so bob buys 1)
        uint256 price = ft2.getBuyPrice(alice, 1);
        uint256 totalCost = _getTotalCostFor(ft2, price);
        vm.prank(bob);
        ft2.buyShares{value: totalCost}(alice, 1);

        // Now supply = 2, bob has 1, alice has 1
        // If bob tries to sell 2 shares (which he doesn't have), it fails for InsufficientShares
        // Let's test: alice sells her 1, then bob tries to sell his 1 (which would make supply = 0)

        // Alice sells her share
        vm.prank(alice);
        ft2.sellShares(alice, 1);

        // Now supply = 1, only bob has 1 share
        // Bob tries to sell but he's not the subject
        vm.prank(bob);
        vm.expectRevert(FriendTechv2.CannotSellLastShare.selector);
        ft2.sellShares(alice, 1);
    }

    function testSubjectCanSellLastShare() public {
        _setupActiveSubject(alice, "alice");

        // Alice has 1 share (first share), supply = 1
        // Alice can sell her last share
        vm.prank(alice);
        ft.sellShares(alice, 1);

        assertEq(ft.sharesSupply(alice), 0);
        assertEq(ft.sharesBalance(alice, alice), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        PRICE CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetPriceZeroAmount() public view {
        assertEq(ft.getPrice(0, 0), 0);
        assertEq(ft.getPrice(10, 0), 0);
    }

    function testGetPriceFirstShare() public view {
        // First share (supply=0, amount=1) should be very cheap (0² = 0)
        uint256 price = ft.getPrice(0, 1);
        assertEq(price, 0);
    }

    function testGetPriceIncreases() public view {
        uint256 price1 = ft.getPrice(1, 1);
        uint256 price2 = ft.getPrice(2, 1);
        uint256 price3 = ft.getPrice(3, 1);

        assertTrue(price2 > price1);
        assertTrue(price3 > price2);
    }

    function testGetBuyPrice() public {
        _setupActiveSubject(alice, "alice");

        uint256 supply = ft.sharesSupply(alice);
        uint256 expected = ft.getPrice(supply, 1);
        uint256 actual = ft.getBuyPrice(alice, 1);

        assertEq(actual, expected);
    }

    function testGetSellPrice() public {
        _setupActiveSubject(alice, "alice");
        _buyShares(bob, alice, 5);

        uint256 supply = ft.sharesSupply(alice);
        uint256 expected = ft.getPrice(supply - 2, 2);
        uint256 actual = ft.getSellPrice(alice, 2);

        assertEq(actual, expected);
    }

    function testGetSellPriceReturnsZeroIfSupplyTooLow() public {
        _setupActiveSubject(alice, "alice");

        // Supply is 1, trying to sell 5
        uint256 price = ft.getSellPrice(alice, 5);
        assertEq(price, 0);
    }

    function testGetBuyPriceAfterFee() public {
        _setupActiveSubject(alice, "alice");

        uint256 price = ft.getBuyPrice(alice, 1);
        uint256 subjectFee = (price * SUBJECT_FEE) / BASIS_POINTS;
        uint256 protocolFee = (price * PROTOCOL_FEE) / BASIS_POINTS;
        uint256 expected = price + subjectFee + protocolFee;

        uint256 actual = ft.getBuyPriceAfterFee(alice, 1);
        assertEq(actual, expected);
    }

    function testGetSellPriceAfterFee() public {
        _setupActiveSubject(alice, "alice");
        _buyShares(bob, alice, 2);

        uint256 price = ft.getSellPrice(alice, 1);
        uint256 subjectFee = (price * SUBJECT_FEE) / BASIS_POINTS;
        uint256 protocolFee = (price * PROTOCOL_FEE) / BASIS_POINTS;
        uint256 expected = price - subjectFee - protocolFee;

        uint256 actual = ft.getSellPriceAfterFee(alice, 1);
        assertEq(actual, expected);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////*/

    function testIsSubjectActiveFalseForUnregistered() public view {
        assertFalse(ft.isSubjectActive(alice));
    }

    function testIsSubjectActiveFalseForRegisteredNoFirstShare() public {
        vm.prank(alice);
        ft.signUp("alice");

        assertFalse(ft.isSubjectActive(alice));
    }

    function testIsSubjectActiveTrueAfterFirstShare() public {
        _setupActiveSubject(alice, "alice");
        assertTrue(ft.isSubjectActive(alice));
    }

    function testSharesBalanceReturnsCorrectAmount() public {
        _setupActiveSubject(alice, "alice");
        _buyShares(bob, alice, 3);

        assertEq(ft.sharesBalance(alice, alice), 1);
        assertEq(ft.sharesBalance(alice, bob), 3);
        assertEq(ft.sharesBalance(alice, charlie), 0);
    }

    function testSharesSupplyReturnsCorrectAmount() public {
        _setupActiveSubject(alice, "alice");
        assertEq(ft.sharesSupply(alice), 1);

        _buyShares(bob, alice, 5);
        assertEq(ft.sharesSupply(alice), 6);
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION SCENARIOS
    //////////////////////////////////////////////////////////////*/

    function testFullBuySellCycle() public {
        // 1. Alice signs up and activates
        _setupActiveSubject(alice, "alice");

        // 2. Bob buys shares
        uint256 buyPrice = ft.getBuyPrice(alice, 3);
        uint256 buyCost = _getTotalCost(buyPrice);
        vm.prank(bob);
        ft.buyShares{value: buyCost}(alice, 3);

        assertEq(ft.sharesBalance(alice, bob), 3);
        assertEq(ft.sharesSupply(alice), 4);

        // 3. Charlie buys shares (price should be higher)
        uint256 charliePrice = ft.getBuyPrice(alice, 2);
        assertTrue(charliePrice > buyPrice); // Price increased

        uint256 charlieCost = _getTotalCost(charliePrice);
        vm.prank(charlie);
        ft.buyShares{value: charlieCost}(alice, 2);

        assertEq(ft.sharesSupply(alice), 6);

        // 4. Bob sells some shares
        uint256 bobBalanceBefore = bob.balance;
        vm.prank(bob);
        ft.sellShares(alice, 2);

        assertTrue(bob.balance > bobBalanceBefore);
        assertEq(ft.sharesBalance(alice, bob), 1);
    }

    function testMultipleSubjectsIndependent() public {
        _setupActiveSubject(alice, "alice");
        _setupActiveSubject(bob, "bob");

        // Buy alice's shares
        _buyShares(charlie, alice, 5);

        // Buy bob's shares
        _buyShares(charlie, bob, 3);

        // Verify independent supplies
        assertEq(ft.sharesSupply(alice), 6);
        assertEq(ft.sharesSupply(bob), 4);

        // Verify independent balances
        assertEq(ft.sharesBalance(alice, charlie), 5);
        assertEq(ft.sharesBalance(bob, charlie), 3);
    }

    function testFeeAccumulation() public {
        _setupActiveSubject(alice, "alice");

        uint256 aliceFeesBefore = 0;

        // Multiple trades
        for (uint256 i = 0; i < 3; i++) {
            _buyShares(bob, alice, 1);
        }

        (,, uint256 totalFeesEarned,) = ft.subjectData(alice);
        assertTrue(totalFeesEarned > aliceFeesBefore);
    }

    function testSubjectBuysOwnShares() public {
        _setupActiveSubject(alice, "alice");

        // Alice can buy more of her own shares
        uint256 price = ft.getBuyPrice(alice, 2);
        uint256 totalCost = _getTotalCost(price);

        vm.prank(alice);
        ft.buyShares{value: totalCost}(alice, 2);

        assertEq(ft.sharesBalance(alice, alice), 3); // 1 first + 2 bought
    }

    function testPriceConsistencyAfterBuySell() public {
        _setupActiveSubject(alice, "alice");

        // Record initial state
        uint256 initialSupply = ft.sharesSupply(alice);
        uint256 initialPrice = ft.getBuyPrice(alice, 1);

        // Buy and sell
        _buyShares(bob, alice, 3);
        vm.prank(bob);
        ft.sellShares(alice, 3);

        // Price should return to same level
        assertEq(ft.sharesSupply(alice), initialSupply);
        assertEq(ft.getBuyPrice(alice, 1), initialPrice);
    }

    /*//////////////////////////////////////////////////////////////
                            EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function testBuyExactPayment() public {
        _setupActiveSubject(alice, "alice");

        uint256 price = ft.getBuyPrice(alice, 1);
        uint256 exactCost = _getTotalCost(price);
        uint256 bobBalanceBefore = bob.balance;

        vm.prank(bob);
        ft.buyShares{value: exactCost}(alice, 1);

        // No refund, exact amount deducted
        assertEq(bob.balance, bobBalanceBefore - exactCost);
    }

    function testSellAllOwnedShares() public {
        _setupActiveSubject(alice, "alice");
        _buyShares(bob, alice, 5);

        vm.prank(bob);
        ft.sellShares(alice, 5);

        assertEq(ft.sharesBalance(alice, bob), 0);
    }

    function testLargeAmountBuy() public {
        _setupActiveSubject(alice, "alice");

        uint256 price = ft.getBuyPrice(alice, 100);
        uint256 totalCost = _getTotalCost(price);

        vm.deal(bob, totalCost + 1 ether);

        vm.prank(bob);
        ft.buyShares{value: totalCost}(alice, 100);

        assertEq(ft.sharesBalance(alice, bob), 100);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    function _setupActiveSubject(address subject, string memory username) internal {
        vm.prank(subject);
        ft.signUp(username);

        vm.prank(subject);
        ft.buyFirstShare();
    }

    function _buyShares(address buyer, address subject, uint256 amount) internal {
        uint256 price = ft.getBuyPrice(subject, amount);
        uint256 totalCost = _getTotalCost(price);

        vm.prank(buyer);
        ft.buyShares{value: totalCost}(subject, amount);
    }

    function _getTotalCost(uint256 price) internal pure returns (uint256) {
        uint256 subjectFee = (price * SUBJECT_FEE) / BASIS_POINTS;
        uint256 protocolFee = (price * PROTOCOL_FEE) / BASIS_POINTS;
        return price + subjectFee + protocolFee;
    }

    function _getTotalCostFor(FriendTechv2 _ft, uint256 price) internal view returns (uint256) {
        uint256 subjectFee = (price * _ft.i_subjectFeePercent()) / BASIS_POINTS;
        uint256 protocolFee = (price * _ft.i_protocolFeePercent()) / BASIS_POINTS;
        return price + subjectFee + protocolFee;
    }

    function _getProceeds(uint256 price) internal pure returns (uint256) {
        uint256 subjectFee = (price * SUBJECT_FEE) / BASIS_POINTS;
        uint256 protocolFee = (price * PROTOCOL_FEE) / BASIS_POINTS;
        return price - subjectFee - protocolFee;
    }
}
