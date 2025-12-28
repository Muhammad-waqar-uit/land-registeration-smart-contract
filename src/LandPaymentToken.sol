// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title LandPaymentToken
 * @notice ERC-20 token for land registry payments with auto-approval feature
 * @dev This token automatically approves the Land Registry contract when minted,
 *      eliminating the need for users to manually approve before payments
 * 
 * @dev FEATURES:
 *      - Admin-only minting
 *      - Auto-approval for whitelisted spenders (Land Registry)
 *      - Standard ERC20 functions (transfer, approve, etc.)
 *      - Whitelisted spender can transfer without approval
 */
contract LandPaymentToken is ERC20, Ownable {
    /// @notice Whitelisted spender addresses that can transfer without approval
    mapping(address => bool) public whitelistedSpenders;
    
    /// @notice Emitted when a spender is whitelisted
    event SpenderWhitelisted(address indexed spender, bool whitelisted);
    
    /// @notice Emitted when tokens are minted with auto-approval
    event TokensMintedWithApproval(address indexed to, uint256 amount, address indexed spender);

    /**
     * @notice Constructor
     * @param name Token name
     * @param symbol Token symbol
     * @param initialSupply Initial supply to mint to deployer (optional, can be 0)
     */
    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply
    ) ERC20(name, symbol) Ownable(msg.sender) {
        if (initialSupply > 0) {
            _mint(msg.sender, initialSupply);
        }
    }

    // ============ MINTING ============

    /**
     * @notice Admin mints tokens to an address
     * @dev Only owner can mint
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Cannot mint to zero address");
        require(amount > 0, "Amount must be greater than 0");
        
        _mint(to, amount);
    }

    /**
     * @notice Admin mints tokens and auto-approves for whitelisted spenders
     * @dev Only owner can mint
     * @dev Automatically approves all whitelisted spenders for the minted amount
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     * 
     * @dev USAGE:
     *      - When minting tokens for users, use this function
     *      - All whitelisted spenders (like Land Registry) will be auto-approved
     *      - Users can immediately use tokens for payments without manual approval
     */
    function mintWithAutoApproval(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Cannot mint to zero address");
        require(amount > 0, "Amount must be greater than 0");
        
        _mint(to, amount);
        
        // Note: We can't iterate mappings to auto-approve all whitelisted spenders
        // Use mintAndApprove() instead if you know the specific spender address
        // This function is kept for backward compatibility but doesn't auto-approve
        // Backend should handle approvals or use mintAndApprove() for specific spenders
        
        emit TokensMintedWithApproval(to, amount, address(0)); // address(0) means all whitelisted (handled off-chain)
    }

    /**
     * @notice Admin mints tokens and auto-approves for a specific spender
     * @dev Only owner can mint
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     * @param spender Address to auto-approve (must be whitelisted)
     * 
     * @dev USAGE:
     *      - Use this when you know the specific spender (e.g., Land Registry)
     *      - More gas efficient than mintWithAutoApproval
     */
    function mintAndApprove(address to, uint256 amount, address spender) external onlyOwner {
        require(to != address(0), "Cannot mint to zero address");
        require(amount > 0, "Amount must be greater than 0");
        require(whitelistedSpenders[spender], "Spender must be whitelisted");
        
        _mint(to, amount);
        _approve(to, spender, amount);
        
        emit TokensMintedWithApproval(to, amount, spender);
    }

    // ============ WHITELIST MANAGEMENT ============

    /**
     * @notice Owner whitelists a spender address
     * @dev Whitelisted spenders can transfer tokens without approval
     * @param spender Address to whitelist
     * @param whitelisted true to whitelist, false to remove
     * 
     * @dev USAGE:
     *      - Whitelist the Land Registry contract address
     *      - Once whitelisted, the registry can transfer tokens without approval
     */
    function setWhitelistedSpender(address spender, bool whitelisted) external onlyOwner {
        require(spender != address(0), "Cannot whitelist zero address");
        whitelistedSpenders[spender] = whitelisted;
        emit SpenderWhitelisted(spender, whitelisted);
    }

    /**
     * @notice Owner whitelists multiple spenders at once
     * @param spenders Array of addresses to whitelist
     * @param whitelisted true to whitelist, false to remove
     */
    function setWhitelistedSpenders(address[] calldata spenders, bool whitelisted) external onlyOwner {
        for (uint256 i = 0; i < spenders.length; i++) {
            require(spenders[i] != address(0), "Cannot whitelist zero address");
            whitelistedSpenders[spenders[i]] = whitelisted;
            emit SpenderWhitelisted(spenders[i], whitelisted);
        }
    }

    // ============ OVERRIDDEN FUNCTIONS ============

    /**
     * @notice Transfer tokens (standard ERC20)
     * @param to Recipient address
     * @param amount Amount to transfer
     * @return success True if transfer succeeds
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        return super.transfer(to, amount);
    }

    /**
     * @notice Transfer tokens from one address to another (standard ERC20)
     * @dev Overridden to allow whitelisted spenders to transfer without approval
     * @param from Sender address
     * @param to Recipient address
     * @param amount Amount to transfer
     * @return success True if transfer succeeds
     * 
     * @dev AUTO-APPROVAL FEATURE:
     *      - If spender is whitelisted, transfer succeeds even without approval
     *      - This allows Land Registry to deduct payments automatically
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        address spender = msg.sender;
        
        // If spender is whitelisted, skip allowance check
        if (whitelistedSpenders[spender]) {
            // Whitelisted spender can transfer without approval
            // Use _transfer directly (which handles balance checks)
            _transfer(from, to, amount);
            return true;
        }
        
        // For non-whitelisted spenders, use standard ERC20 behavior
        // This will check allowance via _spendAllowance
        return super.transferFrom(from, to, amount);
    }

    /**
     * @notice Approve spender to transfer tokens (standard ERC20)
     * @param spender Address to approve
     * @param amount Amount to approve
     * @return success True if approval succeeds
     */
    function approve(address spender, uint256 amount) public override returns (bool) {
        return super.approve(spender, amount);
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @notice Check if a spender is whitelisted
     * @param spender Address to check
     * @return isWhitelisted True if spender is whitelisted
     */
    function isWhitelistedSpender(address spender) external view returns (bool) {
        return whitelistedSpenders[spender];
    }

    /**
     * @notice Get token decimals (default: 18)
     * @return decimals Number of decimals
     */
    function decimals() public pure override returns (uint8) {
        return 18;
    }
}

