// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "../../src/13-auction/SimpleAuction.sol";

contract SimpleAuctionTest is Test {
    SimpleAuction auction;

    address seller = address(0x5E11E4);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address charlie = address(0xC4A411E);

    uint256 constant RESERVE_PRICE = 1 ether;
    uint256 constant DURATION = 7 days;

    event BidPlaced(address indexed bidder, uint256 amount);
    event BidRefunded(address indexed bidder, uint256 amount);
    event AuctionEnded(address indexed winner, uint256 amount);
    event AuctionCancelled();

    function setUp() public {
        vm.deal(seller, 10 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);

        vm.prank(seller);
        auction = new SimpleAuction(RESERVE_PRICE, DURATION);
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function testConstructorSetsValues() public view {
        assertEq(auction.i_seller(), seller);
        assertEq(auction.i_reservePrice(), RESERVE_PRICE);
        assertEq(auction.i_deadline(), block.timestamp + DURATION);
        assertEq(auction.highestBidder(), address(0));
        assertEq(auction.highestBid(), 0);
        assertEq(auction.ended(), false);
    }

    function testConstructorRevertsOnZeroReservePrice() public {
        vm.prank(seller);
        vm.expectRevert(SimpleAuction.InvalidReservePrice.selector);
        new SimpleAuction(0, DURATION);
    }

    function testConstructorRevertsOnZeroDuration() public {
        vm.prank(seller);
        vm.expectRevert(SimpleAuction.InvalidDuration.selector);
        new SimpleAuction(RESERVE_PRICE, 0);
    }

    /*//////////////////////////////////////////////////////////////
                            BID
    //////////////////////////////////////////////////////////////*/

    function testFirstBidMustMeetReserve() public {
        vm.prank(alice);
        auction.bid{value: RESERVE_PRICE}();

        assertEq(auction.highestBidder(), alice);
        assertEq(auction.highestBid(), RESERVE_PRICE);
    }

    function testFirstBidBelowReserveReverts() public {
        vm.prank(alice);
        vm.expectRevert(SimpleAuction.InvalidBid.selector);
        auction.bid{value: 0.5 ether}();
    }

    function testSubsequentBidMustExceedBy5Percent() public {
        vm.prank(alice);
        auction.bid{value: 1 ether}();

        // 5% of 1 ether = 0.05 ether, so minimum is 1.05 ether
        vm.prank(bob);
        auction.bid{value: 1.1 ether}();

        assertEq(auction.highestBidder(), bob);
        assertEq(auction.highestBid(), 1.1 ether);
    }

    function testBidExactly5PercentHigherSucceeds() public {
        vm.prank(alice);
        auction.bid{value: 1 ether}();

        // Exactly 5% higher = 1.05 ether
        vm.prank(bob);
        auction.bid{value: 1.05 ether}();

        assertEq(auction.highestBidder(), bob);
        assertEq(auction.highestBid(), 1.05 ether);
    }

    function testBidLessThan5PercentHigherReverts() public {
        vm.prank(alice);
        auction.bid{value: 1 ether}();

        // 4% higher = 1.04 ether (should fail)
        vm.prank(bob);
        vm.expectRevert(SimpleAuction.InvalidBid.selector);
        auction.bid{value: 1.04 ether}();
    }

    function testPreviousBidderIsRefunded() public {
        vm.prank(alice);
        auction.bid{value: 1 ether}();

        uint256 aliceBalanceBefore = alice.balance;

        vm.prank(bob);
        auction.bid{value: 1.1 ether}();

        assertEq(alice.balance, aliceBalanceBefore + 1 ether);
    }

    function testSellerCannotBid() public {
        vm.prank(seller);
        vm.expectRevert(SimpleAuction.InvalidBuyer.selector);
        auction.bid{value: 1 ether}();
    }

    function testCannotBidAfterDeadline() public {
        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(alice);
        vm.expectRevert(SimpleAuction.AuctionAlreadyEnded.selector);
        auction.bid{value: 1 ether}();
    }

    function testCannotBidAfterAuctionEnded() public {
        vm.prank(alice);
        auction.bid{value: 1 ether}();

        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(seller);
        auction.withdraw();

        // onlyLiveAuction modifier is checked before onlyNotEnded
        // so AuctionAlreadyEnded is thrown first
        vm.prank(bob);
        vm.expectRevert(SimpleAuction.AuctionAlreadyEnded.selector);
        auction.bid{value: 2 ether}();
    }

    function testBidEmitsBidPlacedEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit BidPlaced(alice, 1 ether);
        auction.bid{value: 1 ether}();
    }

    function testBidEmitsBidRefundedEvent() public {
        vm.prank(alice);
        auction.bid{value: 1 ether}();

        vm.prank(bob);
        vm.expectEmit(true, false, false, true);
        emit BidRefunded(alice, 1 ether);
        auction.bid{value: 1.1 ether}();
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAW
    //////////////////////////////////////////////////////////////*/

    function testWithdrawTransfersFundsToSeller() public {
        vm.prank(alice);
        auction.bid{value: 5 ether}();

        vm.warp(block.timestamp + DURATION + 1);

        uint256 sellerBalanceBefore = seller.balance;

        vm.prank(seller);
        auction.withdraw();

        assertEq(seller.balance, sellerBalanceBefore + 5 ether);
        assertEq(auction.ended(), true);
    }

    function testOnlySellerCanWithdraw() public {
        vm.prank(alice);
        auction.bid{value: 1 ether}();

        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(alice);
        vm.expectRevert(SimpleAuction.InvalidSeller.selector);
        auction.withdraw();
    }

    function testCannotWithdrawBeforeDeadline() public {
        vm.prank(alice);
        auction.bid{value: 1 ether}();

        vm.prank(seller);
        vm.expectRevert(SimpleAuction.AuctionNotEnded.selector);
        auction.withdraw();
    }

    function testCannotWithdrawIfNoBids() public {
        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(seller);
        vm.expectRevert(SimpleAuction.NoBidWasPlaced.selector);
        auction.withdraw();
    }

    function testCannotWithdrawTwice() public {
        vm.prank(alice);
        auction.bid{value: 1 ether}();

        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(seller);
        auction.withdraw();

        vm.prank(seller);
        vm.expectRevert(SimpleAuction.AuctionFinalized.selector);
        auction.withdraw();
    }

    function testWithdrawEmitsAuctionEndedEvent() public {
        vm.prank(alice);
        auction.bid{value: 1 ether}();

        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(seller);
        vm.expectEmit(true, false, false, true);
        emit AuctionEnded(alice, 1 ether);
        auction.withdraw();
    }

    /*//////////////////////////////////////////////////////////////
                            CANCEL
    //////////////////////////////////////////////////////////////*/

    function testCancelSucceedsWithNoBids() public {
        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(seller);
        auction.cancel();

        assertEq(auction.ended(), true);
    }

    function testOnlySellerCanCancel() public {
        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(alice);
        vm.expectRevert(SimpleAuction.InvalidSeller.selector);
        auction.cancel();
    }

    function testCannotCancelBeforeDeadline() public {
        vm.prank(seller);
        vm.expectRevert(SimpleAuction.AuctionNotEnded.selector);
        auction.cancel();
    }

    function testCannotCancelIfBidsExist() public {
        vm.prank(alice);
        auction.bid{value: 1 ether}();

        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(seller);
        vm.expectRevert(SimpleAuction.HasBids.selector);
        auction.cancel();
    }

    function testCannotCancelTwice() public {
        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(seller);
        auction.cancel();

        vm.prank(seller);
        vm.expectRevert(SimpleAuction.AuctionFinalized.selector);
        auction.cancel();
    }

    function testCancelEmitsAuctionCancelledEvent() public {
        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(seller);
        vm.expectEmit(false, false, false, false);
        emit AuctionCancelled();
        auction.cancel();
    }

    /*//////////////////////////////////////////////////////////////
                            EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function testBidAtExactDeadline() public {
        vm.warp(block.timestamp + DURATION);

        vm.prank(alice);
        vm.expectRevert(SimpleAuction.AuctionAlreadyEnded.selector);
        auction.bid{value: 1 ether}();
    }

    function testMultipleBiddersCompeting() public {
        vm.prank(alice);
        auction.bid{value: 1 ether}();

        vm.prank(bob);
        auction.bid{value: 1.1 ether}();

        vm.prank(charlie);
        auction.bid{value: 1.2 ether}();

        vm.prank(alice);
        auction.bid{value: 1.5 ether}();

        assertEq(auction.highestBidder(), alice);
        assertEq(auction.highestBid(), 1.5 ether);
    }

    function testSameBidderCanBidMultipleTimes() public {
        vm.prank(alice);
        auction.bid{value: 1 ether}();

        vm.prank(alice);
        auction.bid{value: 1.1 ether}();

        assertEq(auction.highestBidder(), alice);
        assertEq(auction.highestBid(), 1.1 ether);
        // Alice should have been refunded 1 ether
        assertEq(alice.balance, 100 ether - 1.1 ether);
    }

    function testContractHoldsCorrectBalance() public {
        vm.prank(alice);
        auction.bid{value: 1 ether}();

        assertEq(address(auction).balance, 1 ether);

        vm.prank(bob);
        auction.bid{value: 1.1 ether}();

        // Only highest bid should be held
        assertEq(address(auction).balance, 1.1 ether);
    }
}
