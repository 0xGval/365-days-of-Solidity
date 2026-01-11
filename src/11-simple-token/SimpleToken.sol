// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

/// @title SimpleToken
/// @notice A minimal fungible token with owner-controlled minting and ERC20-style allowances.
/// @dev
/// - Fixed maximum supply enforced at mint time
/// - No burn functionality
/// - No permit (EIP-2612) signatures
/// - Owner is immutable and set at deployment

contract SimpleToken {
    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Address authorized to mint new tokens.
    address public immutable owner;

    /// @notice Human-readable token name.
    string public name;

    /// @notice Human-readable token symbol.
    string public symbol;

    /// @notice Maximum tokens that can ever exist.
    uint256 public immutable maxSupply;

    /// @notice Decimal places for display purposes.
    uint8 public immutable decimals;

    /// @notice Current circulating supply.
    uint256 public totalSupply;

    /// @notice Per-address token balances.
    mapping(address => uint256) public balances;

    /// @notice Nested mapping of owner → spender → allowed amount.
    mapping(address => mapping(address => uint256)) public allowances;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Reverts when name or symbol is empty.
    error invalidString();

    /// @notice Reverts when maxSupply is zero.
    error invalidMaxSupply();

    /// @notice Reverts when caller is not the owner.
    error notOwner();

    /// @notice Reverts when destination address is zero.
    error invalidDestination();

    /// @notice Reverts when amount is zero or exceeds maxSupply.
    error invalidAmount();

    /// @notice Reverts when sender has insufficient balance.
    error notEnoughBalance();

    /// @notice Reverts when spender has insufficient allowance.
    error notEnoughAllowance();

    /// @notice Reverts when spender address is zero.
    error invalidSpender();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted on transfer, transferFrom, and mint.
    /// @dev For minting, `from` is address(0).
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @notice Emitted when allowance is set or modified.
    /// @dev `amount` is the new total allowance, not the delta.
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 amount
    );

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Restricts function to owner only.
    modifier onlyOwner() {
        if (msg.sender != owner) revert notOwner();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploys the token with fixed metadata and supply cap.
    /// @param _name Token name (cannot be empty).
    /// @param _symbol Token symbol (cannot be empty).
    /// @param _maxSupply Maximum mintable supply (must be > 0).
    /// @param _decimals Decimal places for display.
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _maxSupply,
        uint8 _decimals
    ) {
        if (bytes(_name).length == 0 || bytes(_symbol).length == 0)
            revert invalidString();

        if (!(_maxSupply > 0)) revert invalidMaxSupply();
        name = _name;
        symbol = _symbol;
        maxSupply = _maxSupply;
        owner = msg.sender;
        decimals = _decimals;
    }

    /*//////////////////////////////////////////////////////////////
                            MINTING
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates new tokens and assigns them to an address.
    /// @dev
    /// - Only callable by owner
    /// - Cannot exceed maxSupply
    /// - Emits Transfer from address(0)
    /// @param to Recipient of minted tokens.
    /// @param amount Number of tokens to mint.
    function mint(address to, uint256 amount) public onlyOwner {
        if (to == address(0)) revert invalidDestination();
        if (amount == 0) revert invalidAmount();
        if ((totalSupply + amount) > maxSupply) revert invalidAmount();
        totalSupply += amount;
        balances[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            TRANSFERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Transfers tokens from caller to another address.
    /// @dev
    /// - Reverts if caller has insufficient balance
    /// - Reverts if recipient is zero address
    /// - Reverts if amount is zero
    /// @param to Recipient address.
    /// @param amount Number of tokens to transfer.
    /// @return True on success.
    function transfer(address to, uint256 amount) public returns (bool) {
        if (to == address(0)) revert invalidDestination();
        if (amount == 0) revert invalidAmount();
        if (balances[msg.sender] < amount) revert notEnoughBalance();
        balances[msg.sender] -= amount;
        balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    /// @notice Transfers tokens on behalf of another address.
    /// @dev
    /// - Requires sufficient allowance from `from` to caller
    /// - Decreases allowance by amount spent
    /// - Reverts if insufficient balance or allowance
    /// @param from Address to transfer from.
    /// @param to Recipient address.
    /// @param amount Number of tokens to transfer.
    /// @return True on success.
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public returns (bool) {
        if (from == address(0) || to == address(0)) revert invalidDestination();
        if (amount == 0) revert invalidAmount();
        if (balances[from] < amount) revert notEnoughBalance();
        if (allowances[from][msg.sender] < amount) revert notEnoughAllowance();

        allowances[from][msg.sender] -= amount;
        balances[from] -= amount;
        balances[to] += amount;

        emit Transfer(from, to, amount);
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                            ALLOWANCES
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets exact allowance for a spender.
    /// @dev
    /// - Overwrites any existing allowance
    /// - Use increaseAllowance/decreaseAllowance for safer modifications
    /// @param spender Address authorized to spend.
    /// @param amount Maximum amount spender can transfer.
    /// @return True on success.
    function approve(address spender, uint256 amount) public returns (bool) {
        if (spender == address(0)) revert invalidSpender();
        allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @notice Increases allowance for a spender.
    /// @dev Safer than approve for incremental allowance changes.
    /// @param spender Address authorized to spend.
    /// @param addedValue Amount to add to current allowance.
    /// @return True on success.
    function increaseAllowance(
        address spender,
        uint256 addedValue
    ) public returns (bool) {
        if (spender == address(0)) revert invalidSpender();
        allowances[msg.sender][spender] += addedValue;

        emit Approval(msg.sender, spender, allowances[msg.sender][spender]);
        return true;
    }

    /// @notice Decreases allowance for a spender.
    /// @dev Reverts if decrease exceeds current allowance.
    /// @param spender Address authorized to spend.
    /// @param subtractedValue Amount to subtract from current allowance.
    /// @return True on success.
    function decreaseAllowance(
        address spender,
        uint256 subtractedValue
    ) public returns (bool) {
        if (spender == address(0)) revert invalidSpender();
        uint256 currentAllowance = allowances[msg.sender][spender];

        if (subtractedValue > currentAllowance) revert notEnoughAllowance();

        allowances[msg.sender][spender] -= subtractedValue;

        emit Approval(msg.sender, spender, allowances[msg.sender][spender]);
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns token balance of an account.
    /// @param account Address to query.
    /// @return Token balance.
    function balanceOf(address account) public view returns (uint256) {
        return balances[account];
    }

    /// @notice Returns allowance granted by owner to spender.
    /// @param _owner Address that granted allowance.
    /// @param spender Address authorized to spend.
    /// @return Remaining allowance.
    function allowance(
        address _owner,
        address spender
    ) public view returns (uint256) {
        return allowances[_owner][spender];
    }
}
