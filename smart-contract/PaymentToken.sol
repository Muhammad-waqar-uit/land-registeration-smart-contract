// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PaymentToken
 * @author Land Registry System
 * @notice ERC20 payment token for Land Registration System
 * @dev Standard ERC20 token using OpenZeppelin implementation
 * @dev Supports minting by owner for token distribution
 * @dev Initial supply can be minted to deployer or specific address
 * 
 * @dev DEPLOYMENT INSTRUCTIONS:
 *      1. Deploy this contract
 *      2. Deploy LandRegistryUpgradeable contract
 *      3. Initialize LandRegistryUpgradeable with this token address
 *      4. Add token address to backend .env as PAYMENT_TOKEN_ADDRESS
 * 
 * @dev TOKEN DETAILS:
 *      - Name: Land Registry Payment Token
 *      - Symbol: LRT (or customize)
 *      - Decimals: 18 (standard, matches backend assumptions)
 *      - Initial Supply: Minted to deployer (or customize in constructor)
 *      - Mintable: Yes (by owner only)
 */

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PaymentToken is ERC20, Ownable {
    /**
     * @notice Constructor initializes the token
     * @param _name Token name (e.g., "Land Registry Payment Token")
     * @param _symbol Token symbol (e.g., "LRT")
     * @param _initialSupply Initial supply to mint to deployer (in base units, e.g., 1000000 * 10^18 for 1M tokens)
     * 
     * @dev EXAMPLES:
     *      - 1,000,000 tokens: _initialSupply = 1000000 * 10**18
     *      - 10,000,000 tokens: _initialSupply = 10000000 * 10**18
     *      - 100,000,000 tokens: _initialSupply = 100000000 * 10**18
     *      - No initial supply: _initialSupply = 0 (mint later with mint())
     */
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        // Mint initial supply to deployer if specified
        if (_initialSupply > 0) {
            _mint(msg.sender, _initialSupply);
        }
    }

    /**
     * @notice Mint new tokens (owner only)
     * @param to Address to mint tokens to
     * @param amount Amount to mint (in base units, e.g., 1000 * 10^18 for 1000 tokens)
     * 
     * @dev USAGE:
     *      - Owner can mint tokens to any address
     *      - Use for token distribution, airdrops, etc.
     *      - Amount should be in base units (accounting for 18 decimals)
     * 
     * @dev EXAMPLE:
     *      mint(0x123..., 1000 * 10**18) mints 1000 tokens to address 0x123...
     */
    function mint(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Cannot mint to zero address");
        require(amount > 0, "Amount must be > 0");
        _mint(to, amount);
    }

    /**
     * @notice Mint tokens to multiple addresses (owner only)
     * @param recipients Array of recipient addresses
     * @param amounts Array of amounts to mint (in base units)
     * 
     * @dev USAGE:
     *      - Useful for bulk distribution
     *      - Arrays must have same length
     *      - Each amount should be in base units (accounting for 18 decimals)
     */
    function mintBatch(address[] memory recipients, uint256[] memory amounts) external onlyOwner {
        require(recipients.length == amounts.length, "Arrays length mismatch");
        require(recipients.length > 0, "Empty arrays");

        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "Cannot mint to zero address");
            require(amounts[i] > 0, "Amount must be > 0");
            _mint(recipients[i], amounts[i]);
        }
    }

    /**
     * @notice Burn tokens (owner only, for reducing supply)
     * @param amount Amount to burn from owner's balance (in base units)
     * 
     * @dev USAGE:
     *      - Owner can burn their own tokens
     *      - Useful for token supply management
     *      - Amount should be in base units
     */
    function burn(uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be > 0");
        require(balanceOf(owner()) >= amount, "Insufficient balance");
        _burn(owner(), amount);
    }

    /**
     * @notice Get token decimals (always 18 for this token)
     * @return uint8 Always returns 18
     * 
     * @dev This matches backend assumptions (backend multiplies by 10^18)
     */
    function decimals() public pure override returns (uint8) {
        return 18;
    }

    /**
     * @notice Get total supply
     * @return uint256 Total tokens in circulation
     */
    function totalSupply() public view override returns (uint256) {
        return super.totalSupply();
    }

    /**
     * @notice Get balance of an address
     * @param account Address to check balance for
     * @return uint256 Token balance (in base units)
     */
    function balanceOf(address account) public view override returns (uint256) {
        return super.balanceOf(account);
    }

    /**
     * @notice Transfer tokens (standard ERC20)
     * @param to Recipient address
     * @param amount Amount to transfer (in base units)
     * @return bool Success status
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        return super.transfer(to, amount);
    }

    /**
     * @notice Approve spender (standard ERC20)
     * @param spender Address to approve
     * @param amount Amount to approve (in base units)
     * @return bool Success status
     * 
     * @dev USAGE:
     *      - Users approve LandRegistry contract to spend tokens
     *      - Backend handles approval before payments
     */
    function approve(address spender, uint256 amount) public override returns (bool) {
        return super.approve(spender, amount);
    }

    /**
     * @notice Get allowance (standard ERC20)
     * @param owner Token owner address
     * @param spender Spender address
     * @return uint256 Approved amount (in base units)
     */
    function allowance(address owner, address spender) public view override returns (uint256) {
        return super.allowance(owner, spender);
    }

    /**
     * @notice Transfer from (standard ERC20)
     * @param from Source address
     * @param to Recipient address
     * @param amount Amount to transfer (in base units)
     * @return bool Success status
     * 
     * @dev USAGE:
     *      - LandRegistry contract uses this to transfer tokens from buyers
     *      - Requires prior approval from token owner
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        return super.transferFrom(from, to, amount);
    }
}
