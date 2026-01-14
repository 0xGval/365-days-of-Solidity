// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

contract SimpleAuction {
    uint256 public immutable i_reservePrice;
    uint256 public immutable i_deadline;
    address public immutable i_seller;

    address public highestBidder;
    uint256 public highestBid;

    bool public ended;

    error InvalidReservePrice();
    error InvalidDuration();
    error InvalidBuyer();
    error InvalidSeller();

    error AuctionAlreadyEnded();
    error AuctionNotEnded();
    error AuctionFinalized();
    error InvalidBid();
    error TransferFailed();
    error NoBidWasPlaced();
    error HasBids();

    event BidPlaced(address indexed bidder, uint256 amount);
    event BidRefunded(address indexed bidder, uint256 amount);
    event AuctionEnded(address indexed winner, uint256 amount);
    event AuctionCancelled();

    modifier onlyBuyer() {
        if (msg.sender == i_seller) revert InvalidBuyer();
        _;
    }

    modifier onlySeller() {
        if (msg.sender != i_seller) revert InvalidSeller();
        _;
    }

    modifier onlyLiveAuction() {
        if (block.timestamp >= i_deadline) revert AuctionAlreadyEnded();
        _;
    }

    modifier onlyNotEnded() {
        if (ended) revert AuctionFinalized();
        _;
    }

    modifier onlyAfterDeadline() {
        if (block.timestamp < i_deadline) revert AuctionNotEnded();
        _;
    }

    constructor(uint256 _reservePrice, uint256 _duration) {
        if (_reservePrice == 0) revert InvalidReservePrice();
        if (_duration == 0) revert InvalidDuration();

        i_seller = msg.sender;
        i_reservePrice = _reservePrice;
        i_deadline = block.timestamp + _duration;
    }

    function bid() public payable onlyBuyer onlyLiveAuction onlyNotEnded {
        if (msg.value < i_reservePrice) revert InvalidBid();
        if (msg.value < (highestBid * 105) / 100) revert InvalidBid();

        address previousBidder = highestBidder;
        uint256 previousBid = highestBid;

        // Effects
        highestBidder = msg.sender;
        highestBid = msg.value;

        // Interactions
        if (previousBidder != address(0)) {
            (bool success, ) = payable(previousBidder).call{value: previousBid}(
                ""
            );
            if (!success) revert TransferFailed();
            emit BidRefunded(previousBidder, previousBid);
        }

        emit BidPlaced(msg.sender, msg.value);
    }

    function withdraw() public onlySeller onlyAfterDeadline onlyNotEnded {
        if (highestBid == 0) revert NoBidWasPlaced();

        // Effects
        ended = true;

        // Interactions
        (bool success, ) = payable(i_seller).call{value: highestBid}("");
        if (!success) revert TransferFailed();

        emit AuctionEnded(highestBidder, highestBid);
    }

    function cancel() public onlySeller onlyAfterDeadline onlyNotEnded {
        if (highestBid != 0) revert HasBids();

        ended = true;

        emit AuctionCancelled();
    }
}
