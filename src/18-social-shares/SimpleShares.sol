// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

/// @title FriendTechV2
/// @author 365 Days of Solidity
/// @notice A Friend.tech-inspired social trading contract where users buy and sell shares of registered subjects
/// @dev Implements a quadratic bonding curve (price = supply²) with dual fee system (subject + protocol)
contract FriendTechv2 {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The protocol owner who receives protocol fees
    address public immutable i_owner;

    /// @notice Fee percentage paid to the subject on each trade (in basis points, e.g., 500 = 5%)
    uint256 public immutable i_subjectFeePercent;

    /// @notice Fee percentage paid to the protocol on each trade (in basis points, e.g., 500 = 5%)
    uint256 public immutable i_protocolFeePercent;

    /// @notice Multiplier used in the bonding curve price calculation
    /// @dev 1 ether / 16000 provides a reasonable price curve growth
    uint256 public constant PRICE_MULTIPLIER = 1 ether / 16000;

    /// @notice Denominator for percentage calculations (10000 = 100%)
    uint256 public constant BASIS_POINTS = 10000;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Stores metadata and statistics for each registered subject
    /// @param registeredAt Timestamp when the subject signed up
    /// @param totalVolume Cumulative trading volume in wei
    /// @param totalFeesEarned Total subject fees earned in wei
    /// @param username Display name chosen by the subject
    struct SubjectInfo {
        uint256 registeredAt;
        uint256 totalVolume;
        uint256 totalFeesEarned;
        string username;
    }

    /*//////////////////////////////////////////////////////////////
                                MAPPINGS
    //////////////////////////////////////////////////////////////*/

    /// @notice Tracks whether an address has registered as a subject
    mapping(address => bool) public isRegistered;

    /// @notice Total shares outstanding for each subject
    mapping(address => uint256) public sharesSupply;

    /// @notice Shares balance: sharesBalance[subject][holder] = amount
    mapping(address => mapping(address => uint256)) public sharesBalance;

    /// @notice Metadata for each registered subject
    mapping(address => SubjectInfo) public subjectData;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when an address tries to register but is already registered
    error AlreadyRegistered();

    /// @notice Thrown when an unregistered address tries to perform a registered-only action
    error NotRegistered();

    /// @notice Thrown when a subject tries to buy first share but already has shares
    error AlreadyHasShares();

    /// @notice Thrown when username is empty
    error InvalidUsername();

    /// @notice Thrown when amount parameter is zero
    error InvalidAmount();

    /// @notice Thrown when subject address is zero address
    error InvalidSubject();

    /// @notice Thrown when trying to buy shares of an unregistered subject
    error SubjectNotRegistered();

    /// @notice Thrown when trying to buy shares before subject has bought their first share
    error SubjectNotActive();

    /// @notice Thrown when msg.value is less than the required payment
    error InsufficientPayment();

    /// @notice Thrown when an ETH transfer fails
    error TransferFailed();

    /// @notice Thrown when trying to sell more shares than owned
    error InsufficientShares();

    /// @notice Thrown when non-subject tries to sell shares that would reduce supply to zero
    error CannotSellLastShare();

    /// @notice Thrown when fee percentage exceeds maximum allowed (50%)
    error FeeTooHigh();
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new subject registers
    /// @param user The address that registered
    event Registered(address indexed user);

    /// @notice Emitted on every share trade (buy or sell)
    /// @param user The trader's address
    /// @param target The subject whose shares were traded
    /// @param firstBuy True if this was the subject's first share purchase
    event Trade(address indexed user, address indexed target, bool firstBuy);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploys the FriendTechv2 contract with specified fee percentages
    /// @dev Reverts if any fee exceeds 50% (5000 basis points)
    /// @param _subjectFeePercent Fee percentage for subject (in basis points, max 5000)
    /// @param _protocolFeePercent Fee percentage for protocol (in basis points, max 5000)
    constructor(uint256 _subjectFeePercent, uint256 _protocolFeePercent) {
        if (_subjectFeePercent > 5000) revert FeeTooHigh();
        if (_protocolFeePercent > 5000) revert FeeTooHigh();

        i_subjectFeePercent = _subjectFeePercent;
        i_protocolFeePercent = _protocolFeePercent;
        i_owner = msg.sender;
    }

    /*//////////////////////////////////////////////////////////////
                          REGISTRATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Register as a subject to enable share trading
    /// @dev Must be called before buyFirstShare(). Username cannot be empty.
    /// @param _username Display name for the subject
    function signUp(string memory _username) public {
        if (bytes(_username).length == 0) revert InvalidUsername();
        if (isRegistered[msg.sender]) revert AlreadyRegistered();

        isRegistered[msg.sender] = true;
        sharesSupply[msg.sender] = 0;

        subjectData[msg.sender] = SubjectInfo(block.timestamp, 0, 0, _username);

        emit Registered(msg.sender);
    }

    /// @notice Subject buys their own first share to activate trading
    /// @dev Only the subject can buy their first share (prevents squatting).
    ///      First share is free (price at supply 0 = 0).
    function buyFirstShare() public {
        if (!isRegistered[msg.sender]) revert NotRegistered();
        if (sharesSupply[msg.sender] > 0) revert AlreadyHasShares();

        sharesSupply[msg.sender] = 1;
        sharesBalance[msg.sender][msg.sender] = 1;

        emit Trade(msg.sender, msg.sender, true);
    }

    /*//////////////////////////////////////////////////////////////
                            TRADING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Buy shares of a registered and active subject
    /// @dev Subject must have called buyFirstShare() first. Caller must send enough ETH.
    /// @param subject The address whose shares to buy
    /// @param amount Number of shares to buy
    function buyShares(address subject, uint256 amount) external payable {
        if (subject == address(0)) revert InvalidSubject();
        if (amount == 0) revert InvalidAmount();
        if (!isRegistered[subject]) revert SubjectNotRegistered();
        if (sharesSupply[subject] == 0) revert SubjectNotActive();

        uint256 price = getBuyPrice(subject, amount); // questa è public, ok
        uint256 subjectFee = (price * i_subjectFeePercent) / BASIS_POINTS;
        uint256 protocolFee = (price * i_protocolFeePercent) / BASIS_POINTS;
        uint256 totalCost = price + subjectFee + protocolFee;

        if (msg.value < totalCost) revert InsufficientPayment();

        sharesBalance[subject][msg.sender] += amount;
        sharesSupply[subject] += amount;
        subjectData[subject].totalVolume += totalCost;
        subjectData[subject].totalFeesEarned += subjectFee;

        (bool success, ) = payable(subject).call{value: subjectFee}("");
        if (!success) revert TransferFailed();

        (bool success1, ) = payable(i_owner).call{value: protocolFee}("");
        if (!success1) revert TransferFailed();

        if (msg.value > totalCost) {
            (bool success2, ) = payable(msg.sender).call{
                value: msg.value - totalCost
            }("");
            if (!success2) revert TransferFailed();
        }

        emit Trade(msg.sender, subject, false);
    }

    /// @notice Sell shares of a subject back to the contract
    /// @dev Caller receives proceeds minus fees. Non-subjects cannot sell the last share.
    /// @param subject The address whose shares to sell
    /// @param amount Number of shares to sell
    function sellShares(address subject, uint256 amount) external {
        if (amount == 0) revert InvalidAmount();
        if (sharesBalance[subject][msg.sender] < amount)
            revert InsufficientShares();
        if (sharesSupply[subject] - amount == 0 && subject != msg.sender)
            revert CannotSellLastShare();

        uint256 price = getSellPrice(subject, amount);
        uint256 subjectFee = (price * i_subjectFeePercent) / BASIS_POINTS;
        uint256 protocolFee = (price * i_protocolFeePercent) / BASIS_POINTS;
        uint256 proceed = price - subjectFee - protocolFee;

        sharesBalance[subject][msg.sender] -= amount;
        sharesSupply[subject] -= amount;
        subjectData[subject].totalVolume += proceed;
        subjectData[subject].totalFeesEarned += subjectFee;

        (bool success, ) = payable(subject).call{value: subjectFee}("");
        if (!success) revert TransferFailed();

        (bool success1, ) = payable(i_owner).call{value: protocolFee}("");
        if (!success1) revert TransferFailed();

        (bool success2, ) = payable(msg.sender).call{value: proceed}("");
        if (!success2) revert TransferFailed();

        emit Trade(msg.sender, subject, false);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculate sum of squares from 0 to n using the mathematical formula
    /// @dev Uses formula: n(n+1)(2n+1)/6 to avoid loops and save gas
    /// @param n Upper bound of the sum
    /// @return Sum of squares from 0² to n²
    function sumOfSquares(uint256 n) internal pure returns (uint256) {
        return (n * (n + 1) * (2 * n + 1)) / 6;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculate the base price for a given amount of shares at a given supply
    /// @dev Uses quadratic bonding curve: price = Σ(i²) × PRICE_MULTIPLIER
    ///      where i ranges from supply to supply + amount - 1
    /// @param supply Current supply of shares
    /// @param amount Number of shares to price
    /// @return Total price in wei (excluding fees)
    function getPrice(
        uint256 supply,
        uint256 amount
    ) public pure returns (uint256) {
        if (amount == 0) return 0;

        uint256 sum1 = supply == 0 ? 0 : sumOfSquares(supply - 1);
        uint256 sum2 = sumOfSquares(supply + amount - 1);

        uint256 summation = sum2 - sum1;

        return summation * PRICE_MULTIPLIER;
    }

    /// @notice Get the price to buy a specific amount of shares (excluding fees)
    /// @param subject The subject whose shares to price
    /// @param amount Number of shares to buy
    /// @return Price in wei (excluding fees)
    function getBuyPrice(
        address subject,
        uint256 amount
    ) public view returns (uint256) {
        return getPrice(sharesSupply[subject], amount);
    }

    /// @notice Get the total cost to buy shares including all fees
    /// @param subject The subject whose shares to buy
    /// @param amount Number of shares to buy
    /// @return Total cost in wei (price + subject fee + protocol fee)
    function getBuyPriceAfterFee(
        address subject,
        uint256 amount
    ) external view returns (uint256) {
        uint256 price = getBuyPrice(subject, amount);
        uint256 subjectFee = (price * i_subjectFeePercent) / BASIS_POINTS;
        uint256 protocolFee = (price * i_protocolFeePercent) / BASIS_POINTS;
        return price + subjectFee + protocolFee;
    }

    /// @notice Get the price received for selling a specific amount of shares (excluding fees)
    /// @param subject The subject whose shares to sell
    /// @param amount Number of shares to sell
    /// @return Price in wei (excluding fees), or 0 if supply < amount
    function getSellPrice(
        address subject,
        uint256 amount
    ) public view returns (uint256) {
        uint256 supply = sharesSupply[subject];
        if (supply < amount) return 0;

        return getPrice(supply - amount, amount);
    }

    /// @notice Get the net proceeds from selling shares after all fees
    /// @param subject The subject whose shares to sell
    /// @param amount Number of shares to sell
    /// @return Net proceeds in wei (price - subject fee - protocol fee)
    function getSellPriceAfterFee(
        address subject,
        uint256 amount
    ) external view returns (uint256) {
        uint256 price = getSellPrice(subject, amount);
        uint256 subjectFee = (price * i_subjectFeePercent) / BASIS_POINTS;
        uint256 protocolFee = (price * i_protocolFeePercent) / BASIS_POINTS;
        return price - subjectFee - protocolFee;
    }

    /// @notice Check if a subject is active (registered and has bought first share)
    /// @param subject The address to check
    /// @return True if subject is registered AND has supply > 0
    function isSubjectActive(address subject) external view returns (bool) {
        return isRegistered[subject] && sharesSupply[subject] > 0;
    }
}
