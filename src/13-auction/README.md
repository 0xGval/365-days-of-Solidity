# 13 – Simple Auction (English Auction)

A classic English auction where bidders compete by placing increasingly higher bids.
The highest bidder at the end of the auction wins the item.

This implementation introduces **competitive bidding mechanics**, **automatic refunds**,
and reinforces time-based state transitions learned in previous days.

---

## SimpleAuction

### Purpose

`SimpleAuction` models a basic ascending-price auction with:
- A reserve price (minimum starting bid)
- A fixed duration (deadline)
- Automatic outbid refunds
- Winner-takes-all resolution

The contract handles ETH custody, tracks the current highest bid,
and enforces bidding rules based on auction state.

---

### Roles

- **Seller**: deploys the contract, sets reserve price and duration, withdraws funds after auction ends
- **Bidders**: place bids during the auction, receive automatic refunds when outbid

---

### Functional Overview

- Seller deploys with a reserve price and auction duration
- Anyone can place a bid that meets the minimum requirements
- Each new bid must exceed the previous highest bid by at least 5%
- When a higher bid arrives, the previous highest bidder is automatically refunded
- After the deadline:
  - If there is a highest bidder: seller can withdraw the winning bid
  - If no valid bids: seller can cancel and close the auction
- The winner can claim their item (emit event, no actual item transfer in this version)

---

### State

The contract tracks:

- `i_seller`: auction creator (immutable)
- `i_reservePrice`: minimum acceptable bid (immutable)
- `i_endTime`: unix timestamp when auction ends (immutable)
- `highestBidder`: address of current highest bidder
- `highestBid`: current highest bid amount
- `ended`: whether auction has been finalized

---

### States (Implicit)

The auction has implicit states derived from conditions:

- **Active**: `block.timestamp < i_endTime && !ended`
- **Ended (Success)**: `block.timestamp >= i_endTime && highestBid >= i_reservePrice`
- **Ended (No Bids)**: `block.timestamp >= i_endTime && highestBid == 0`
- **Finalized**: `ended == true`

---

### Functions

#### bid()

- Accepts ETH as a bid
- Reverts if auction has ended (`block.timestamp >= i_endTime`)
- Reverts if auction is finalized (`ended == true`)
- Reverts if `msg.value < i_reservePrice` (first bid must meet reserve)
- Reverts if `msg.value < highestBid * 105 / 100` (must exceed by 5%)
- Refunds the previous highest bidder automatically
- Updates `highestBidder` and `highestBid`
- Emits `BidPlaced`

---

#### withdraw()

- Only callable by seller
- Only callable after `i_endTime`
- Reverts if no bids were placed (`highestBid == 0`)
- Reverts if already ended
- Sets `ended = true`
- Transfers `highestBid` to seller
- Emits `AuctionEnded`

---

#### cancel()

- Only callable by seller
- Only callable after `i_endTime`
- Only callable if no valid bids (`highestBid == 0`)
- Reverts if already ended
- Sets `ended = true`
- Emits `AuctionCancelled`

---

### Events

##### BidPlaced(address indexed bidder, uint256 amount)

- Emitted on every successful bid
- Includes the bid amount

##### BidRefunded(address indexed bidder, uint256 amount)

- Emitted when a bidder is outbid and refunded

##### AuctionEnded(address indexed winner, uint256 amount)

- Emitted when seller withdraws after successful auction

##### AuctionCancelled()

- Emitted when seller cancels after auction with no bids

---

### Design Constraints

- One auction per contract deployment
- ETH only (no NFT or item transfer logic)
- Fixed reserve price and duration (immutable)
- Minimum bid increment: 5% above current highest
- Push-based refunds (automatic when outbid)
- No bid retraction once placed
- No auction extension (anti-sniping not implemented)
- Seller cannot bid on their own auction

---

### Security Considerations

- Seller immutability prevents ownership hijacking
- Deadline immutability prevents rule changes mid-auction
- Refund before state update (CEI pattern)
- `ended` flag prevents double withdrawal
- Low-level call for ETH transfers with success check
- Seller exclusion from bidding prevents self-bidding attacks
- Integer overflow protected by Solidity 0.8+

---

### Concepts Practiced

- Time-based conditions (`block.timestamp`)
- Competitive state updates (highest bid tracking)
- Push payment pattern (automatic refunds)
- Percentage calculations in Solidity (5% increment)
- CEI pattern (Checks-Effects-Interactions)
- Immutable deployment parameters
- Implicit state derivation from conditions

---

### Test Scenarios to Cover

#### Constructor
- Reverts if reserve price is zero
- Reverts if duration is zero
- Sets seller, reserve price, and end time correctly

#### Bidding
- First bid must meet reserve price
- Subsequent bids must exceed highest by 5%
- Previous bidder receives automatic refund
- Seller cannot bid on own auction
- Cannot bid after deadline
- Cannot bid after auction ended

#### Withdrawal
- Only seller can withdraw
- Cannot withdraw before deadline
- Cannot withdraw if no bids
- Cannot withdraw twice
- Transfers correct amount to seller

#### Cancellation
- Only seller can cancel
- Cannot cancel before deadline
- Cannot cancel if there are bids
- Cannot cancel twice
- Emits correct event

#### Edge Cases
- Bid at exact deadline boundary
- Bid exactly 5% higher (minimum valid increment)
- Bid less than 5% higher (should revert)
- Multiple bidders competing

---

### Not Implemented (Future Learning)

- Anti-sniping: extend deadline if bid placed near end
- Reserve price reveal (hidden reserve)
- Multiple items / batch auctions
- NFT integration (ERC721 item transfer)
- Bid history tracking
- Minimum bid increment configuration
- Auction cancellation before deadline (with refunds)

---

## License

GPL-3.0
