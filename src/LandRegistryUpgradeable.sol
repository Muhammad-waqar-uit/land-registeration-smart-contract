// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title LandRegistryUpgradeable
 * @author Land Registry System
 * @notice A comprehensive, upgradeable smart contract for managing land registration, 
 *         ownership transfers, and hybrid payment systems on the blockchain.
 * 
 * @dev This contract implements:
 *      - UUPS (Universal Upgradeable Proxy Standard) pattern for upgradeability
 *      - Role-based access control (Admin, Builder, Seller, Buyer)
 *      - Hybrid payment system (ERC-20 crypto + bank transfers)
 *      - Dual approval mechanism (seller approval required for ownership transfer)
 *      - Configurable refund system with penalty
 * 
 * @dev WORKFLOW OVERVIEW:
 *      1. Admin registers land with details (IPFS hash, document hash, price)
 *      2. Buyer locks land to themselves (exclusive reservation)
 *      3. Buyer makes payments (crypto installments or bank transfers)
 *      4. When fully paid, seller approval is requested
 *      5. Seller approves → Ownership transfers to buyer
 *      6. Buyer can request refund (with penalty) before ownership transfer
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract LandRegistryUpgradeable is 
    Initializable, 
    OwnableUpgradeable, 
    AccessControlUpgradeable, 
    UUPSUpgradeable 
{
    // ============ STATE VARIABLES ============
    
    /// @notice ERC-20 token used for crypto payments
    IERC20 public paymentToken;

    // ============ ROLE DEFINITIONS ============
    
    /// @notice Builder role - can verify bank payments
    bytes32 public constant BUILDER_ROLE = keccak256("BUILDER_ROLE");
    
    /// @notice Seller role - used for seller-specific checks (not stored in AccessControl, checked via address)
    bytes32 public constant SELLER_ROLE = keccak256("SELLER_ROLE");

    // ============ DATA STRUCTURES ============
    
    /**
     * @notice Core land data structure
     * @dev Fields are stored in struct to reduce gas costs and maintain data integrity
     * @dev Some fields (amountPaid, flags) are stored separately to avoid "stack too deep" compiler errors
     */
    struct Land {
        address owner;                 // Current legal owner (seller until full payment + approval)
        address seller;                // Original seller address (for approval checks)
        string ipfsHash;               // IPFS CID for land documents
        bytes32 documentHash;          // SHA-256 hash of document for tamper-proof verification
        uint256 totalPrice;            // Total price in payment tokens
        address payable lockedTo;      // Currently reserved buyer (address(0) = available)
    }

    /**
     * @notice Bank payment tracking structure
     * @dev Used for off-chain bank transfers that need manual verification
     */
    struct BankPayment {
        bool submitted;                // Whether buyer has submitted payment proof
        bool verified;                 // Whether builder/admin has verified the payment
        address verifiedBy;            // Address of the verifier (builder or admin)
        uint256 amount;                // Payment amount
        string proofHash;              // IPFS hash of payment proof document
        uint256 submittedAt;           // Block timestamp when payment was submitted
        uint256 verifiedAt;            // Block timestamp when payment was verified (0 if not verified)
    }

    // ============ MAPPINGS ============
    
    /// @notice Main land registry - maps landId to Land struct
    mapping(uint256 => Land) public lands;
    
    /// @notice Bank payment registry - maps landId to BankPayment struct
    mapping(uint256 => BankPayment) public bankPayments;
    
    /// @notice Auto-incrementing land ID counter
    uint256 public nextLandId;

    // Payment tracking (stored separately to reduce struct size and avoid stack too deep errors)
    /// @notice Total amount paid (crypto + bank) for each land
    mapping(uint256 => uint256) public amountPaid;
    
    /// @notice Crypto (ERC-20) amount paid for each land
    mapping(uint256 => uint256) public cryptoAmountPaid;
    
    /// @notice Bank transfer amount paid for each land
    mapping(uint256 => uint256) public bankAmountPaid;

    // Status flags (stored separately to reduce struct size)
    /// @notice Whether land ownership has been transferred to buyer
    mapping(uint256 => bool) public isOwned;
    
    /// @notice Whether land has been registered
    mapping(uint256 => bool) public isRegistered;
    
    /// @notice Whether seller approval is pending for ownership transfer
    mapping(uint256 => bool) public sellerApprovalPending;
    
    /// @notice Whether seller has approved the ownership transfer
    mapping(uint256 => bool) public sellerApprovals;

    // ============ CONFIGURATION ============
    
    /**
     * @notice Refund penalty in basis points (10000 = 100%)
     * @dev Example: 1000 = 10% penalty, 500 = 5% penalty
     * @dev Can be updated by admin via setPenaltyBasisPoints()
     */
    uint16 public penaltyBasisPoints;

    // ============ EVENTS ============
    
    /// @notice Emitted when a buyer locks a land parcel
    event LandLocked(uint256 landId, address buyer);
    
    /// @notice Emitted when a payment is received (crypto or bank)
    event PaymentReceived(uint256 landId, address buyer, uint256 amount, bool isBankPayment);
    
    /// @notice Emitted when ownership is transferred from seller to buyer
    event OwnershipTransferred(uint256 landId, address oldOwner, address newOwner);
    
    /// @notice Emitted when a refund is processed
    event RefundProcessed(uint256 landId, address buyer, uint256 refundedAmount, uint256 penalty);
    
    /// @notice Emitted when penalty basis points are updated
    event PenaltyBasisPointsUpdated(uint16 oldPenalty, uint16 newPenalty);
    
    /// @notice Emitted when seller approval is requested for ownership transfer
    event SellerApprovalRequested(uint256 landId, address buyer);
    
    /// @notice Emitted when seller grants approval for ownership transfer
    event SellerApprovalGranted(uint256 landId, address seller);
    
    /// @notice Emitted when seller revokes approval
    event SellerApprovalRevoked(uint256 landId, address seller);
    
    /// @notice Emitted when buyer submits bank payment proof
    event BankPaymentSubmitted(uint256 landId, address buyer, uint256 amount, string proofHash);
    
    /// @notice Emitted when builder/admin verifies a bank payment
    event BankPaymentVerified(uint256 landId, address verifier, uint256 amount);
    
    /// @notice Emitted when builder/admin rejects a bank payment
    event BankPaymentRejected(uint256 landId, address verifier);

    // ============ CONSTRUCTOR ============
    
    /**
     * @notice Constructor disables initializers to prevent direct deployment
     * @dev This contract must be deployed via proxy pattern (UUPS)
     * @dev Prevents implementation contract from being initialized directly
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============ INITIALIZATION ============
    
    /**
     * @notice Initializes the contract (called once via proxy)
     * @dev Sets up payment token, default penalty (10%), and grants admin role to deployer
     * @param _tokenAddress Address of the ERC-20 token used for payments
     * 
     * @dev INITIALIZATION FLOW:
     *      1. Validates token address is not zero
     *      2. Initializes Ownable with deployer as owner
     *      3. Initializes AccessControl
     *      4. Sets payment token
     *      5. Sets default penalty to 10% (1000 basis points)
     *      6. Initializes nextLandId to 1
     *      7. Grants DEFAULT_ADMIN_ROLE to deployer
     */
    function initialize(address _tokenAddress) public initializer {
        require(_tokenAddress != address(0), "Invalid token");
        __Ownable_init(msg.sender);
        __AccessControl_init();
        // UUPSUpgradeable doesn't need initialization in v5 (stateless)
        
        paymentToken = IERC20(_tokenAddress);
        penaltyBasisPoints = 1000; // 10% default penalty
        nextLandId = 1;
        
        // Grant admin role to deployer
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // ============ MODIFIERS ============
    
    /**
     * @notice Ensures land exists (is registered)
     * @param landId The land ID to check
     */
    modifier landExists(uint256 landId) {
        require(isRegistered[landId], "Land: Not registered");
        _;
    }

    /**
     * @notice Ensures only the buyer who locked the land can perform the action
     * @param landId The land ID to check
     * @dev Used for payment and refund functions
     */
    modifier onlyLockedBuyer(uint256 landId) {
        require(
            msg.sender == lands[landId].lockedTo,
            "Payment: Only locked buyer can pay"
        );
        _;
    }

    /**
     * @notice Ensures only the seller of the land can perform the action
     * @param landId The land ID to check
     * @dev Used for seller approval functions
     */
    modifier onlySeller(uint256 landId) {
        require(
            msg.sender == lands[landId].seller,
            "Only seller can perform this action"
        );
        _;
    }

    /**
     * @notice Ensures only builder or admin can perform the action
     * @dev Used for bank payment verification
     */
    modifier onlyBuilderOrAdmin() {
        require(
            hasRole(BUILDER_ROLE, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "Only builder or admin can perform this action"
        );
        _;
    }

    // ============ UPGRADE AUTHORIZATION ============
    
    /**
     * @notice Authorizes contract upgrades (UUPS pattern)
     * @dev Only owner can authorize upgrades
     * @param newImplementation Address of the new implementation contract
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ============ ROLE MANAGEMENT ============

    /**
     * @notice Grants builder role to an address (admin only)
     * @dev Builders can verify bank payments
     * @param builder Address to grant builder role to
     * 
     * @dev USAGE:
     *      - Admin calls this to grant builder role
     *      - Builder can then verify bank payments via verifyBankPayment()
     */
    function grantBuilderRole(address builder) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(BUILDER_ROLE, builder);
    }

    /**
     * @notice Revokes builder role from an address (admin only)
     * @param builder Address to revoke builder role from
     */
    function revokeBuilderRole(address builder) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(BUILDER_ROLE, builder);
    }

    // ============ LAND REGISTRATION ============

    /**
     * @notice Admin registers a new land parcel
     * @dev Only admin (DEFAULT_ADMIN_ROLE) can register land
     * @param _owner Initial owner/seller address
     * @param _ipfsHash IPFS CID where land documents are stored
     * @param _documentHash SHA-256 hash of the land document for verification
     * @param _totalPrice Total price in payment tokens
     * 
     * @dev REGISTRATION FLOW:
     *      1. Auto-increments nextLandId to get unique land ID
     *      2. Stores all land data in Land struct
     *      3. Initializes payment tracking to zero
     *      4. Sets lockedTo to address(0) (available for locking)
     *      5. If price is 0, automatically marks as owned (free land)
     *      6. Marks land as registered
     *      7. Initializes approval flags to false
     * 
     * @dev EXAMPLE:
     *      Admin registers land with:
     *      - Owner: 0x123...
     *      - IPFS: "QmHash123"
     *      - Doc Hash: 0xabc...
     *      - Price: 1000 tokens
     *      
     *      Result: Land ID 1 is created and available for buyers to lock
     */
    function registerLand(
        address _owner,
        string memory _ipfsHash,
        bytes32 _documentHash,
        uint256 _totalPrice
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 id = nextLandId++;
        Land storage land = lands[id];
        land.owner = _owner;
        land.seller = _owner;
        land.ipfsHash = _ipfsHash;
        land.documentHash = _documentHash;
        land.totalPrice = _totalPrice;
        land.lockedTo = payable(address(0));
        amountPaid[id] = 0;
        cryptoAmountPaid[id] = 0;
        bankAmountPaid[id] = 0;
        isOwned[id] = _totalPrice == 0; // Free land is automatically owned
        isRegistered[id] = true;
        sellerApprovalPending[id] = false;
        sellerApprovals[id] = false;
    }

    // ============ LAND LOCKING ============

    /**
     * @notice Buyer locks land to themselves (exclusive reservation)
     * @dev Prevents race conditions by ensuring only one buyer can lock at a time
     * @param landId The land ID to lock
     * 
     * @dev LOCKING FLOW:
     *      1. Checks land exists and is not already sold
     *      2. Checks land is not already locked by another buyer
     *      3. Sets lockedTo to msg.sender (exclusive lock)
     *      4. Emits LandLocked event
     * 
     * @dev IMPORTANT:
     *      - Only one buyer can lock a land at a time
     *      - Locked land cannot be locked by another buyer until unlocked
     *      - Locked land can be unlocked by admin if buyer is inactive
     * 
     * @dev EXAMPLE:
     *      Buyer 0xABC locks land ID 1
     *      - lands[1].lockedTo = 0xABC
     *      - Only 0xABC can make payments for land 1
     *      - Other buyers cannot lock land 1 until it's unlocked
     */
    function lockLandToBuyer(uint256 landId) external landExists(landId) {
        require(!isOwned[landId], "Land: Already sold");
        require(lands[landId].lockedTo == address(0), "Land: Already reserved");

        lands[landId].lockedTo = payable(msg.sender);
        emit LandLocked(landId, msg.sender);
    }

    // ============ CRYPTO PAYMENTS ============

    /**
     * @notice Buyer makes ERC-20 token payment (installments supported)
     * @dev Only the buyer who locked the land can make payments
     * @param landId The land ID to pay for
     * @param amount Payment amount in tokens
     * 
     * @dev PAYMENT FLOW:
     *      1. Validates amount > 0
     *      2. Checks land is not already fully paid
     *      3. Checks payment doesn't exceed total price
     *      4. Transfers tokens from buyer to contract
     *      5. Updates amountPaid and cryptoAmountPaid
     *      6. Emits PaymentReceived event
     *      7. If fully paid, requests seller approval automatically
     * 
     * @dev INSTALLMENT SUPPORT:
     *      - Buyers can pay in multiple transactions
     *      - Example: Land costs 1000 tokens
     *        - Payment 1: 300 tokens (remaining: 700)
     *        - Payment 2: 400 tokens (remaining: 300)
     *        - Payment 3: 300 tokens (fully paid → approval requested)
     * 
     * @dev OWNERSHIP TRANSFER:
     *      - When payment is complete (amountPaid >= totalPrice):
     *        1. SellerApprovalRequested event is emitted
     *        2. sellerApprovalPending is set to true
     *        3. If seller already approved, ownership transfers immediately
     *        4. Otherwise, waits for seller approval
     */
    function makePayment(uint256 landId, uint256 amount)
        external
        landExists(landId)
        onlyLockedBuyer(landId)
    {
        require(amount > 0, "Amount must be > 0");
        require(amountPaid[landId] < lands[landId].totalPrice, "Land: Already fully paid");
        require(amountPaid[landId] + amount <= lands[landId].totalPrice, "Payment exceeds total price");

        require(
            paymentToken.transferFrom(msg.sender, address(this), amount),
            "Token transfer failed"
        );

        amountPaid[landId] += amount;
        cryptoAmountPaid[landId] += amount;

        // Emit payment event first
        emit PaymentReceived(landId, msg.sender, amount, false);

        // Check if fully paid and handle ownership transfer (may emit SellerApprovalRequested)
        _checkAndTransferOwnership(landId);
    }

    // ============ BANK PAYMENTS ============

    /**
     * @notice Buyer submits bank payment proof for verification
     * @dev Buyer provides IPFS hash of bank transfer receipt
     * @param landId The land ID to pay for
     * @param amount Payment amount
     * @param proofHash IPFS hash of bank payment proof document
     * 
     * @dev BANK PAYMENT FLOW:
     *      1. Buyer makes bank transfer off-chain
     *      2. Buyer submits proof (IPFS hash) via this function
     *      3. Builder/Admin verifies the payment off-chain
     *      4. Builder/Admin calls verifyBankPayment() to approve
     *      5. Payment is added to amountPaid
     *      6. If fully paid, ownership transfer process begins
     * 
     * @dev IMPORTANT:
     *      - Bank payments require manual verification
     *      - Previous unverified payment must be verified before submitting new one
     *      - Payment is not added to amountPaid until verified
     * 
     * @dev EXAMPLE:
     *      Buyer submits bank payment:
     *      - Amount: 500 tokens
     *      - Proof Hash: "QmBankProof123"
     *      - Status: Submitted (not yet verified)
     *      - Builder verifies → verifyBankPayment(landId, true)
     *      - Payment added to amountPaid
     */
    function submitBankPayment(
        uint256 landId,
        uint256 amount,
        string memory proofHash
    ) external landExists(landId) onlyLockedBuyer(landId) {
        require(amount > 0, "Amount must be > 0");
        require(amountPaid[landId] + amount <= lands[landId].totalPrice, "Payment exceeds total price");
        
        BankPayment storage bankPayment = bankPayments[landId];
        require(!bankPayment.submitted || bankPayment.verified, "Previous bank payment not verified");

        bankPayment.submitted = true;
        bankPayment.verified = false;
        bankPayment.verifiedBy = address(0);
        bankPayment.amount = amount;
        bankPayment.proofHash = proofHash;
        bankPayment.submittedAt = block.timestamp;
        bankPayment.verifiedAt = 0;

        emit BankPaymentSubmitted(landId, msg.sender, amount, proofHash);
    }

    /**
     * @notice Builder or Admin verifies/rejects bank payment
     * @dev Only builder or admin can verify bank payments
     * @param landId The land ID
     * @param approved true to approve, false to reject
     * 
     * @dev VERIFICATION FLOW:
     *      1. Builder/Admin reviews bank payment proof off-chain
     *      2. If valid: calls verifyBankPayment(landId, true)
     *         - Payment added to amountPaid and bankAmountPaid
     *         - If fully paid, ownership transfer process begins
     *      3. If invalid: calls verifyBankPayment(landId, false)
     *         - Payment submission is reset
     *         - Buyer can submit new proof
     * 
     * @dev SECURITY:
     *      - Only builder or admin can verify
     *      - Verification is one-time (cannot verify twice)
     *      - Rejection allows buyer to submit new proof
     */
    function verifyBankPayment(uint256 landId, bool approved) 
        external 
        landExists(landId) 
        onlyBuilderOrAdmin 
    {
        BankPayment storage bankPayment = bankPayments[landId];
        require(bankPayment.submitted, "No bank payment submitted");
        require(!bankPayment.verified, "Payment already verified");

        if (approved) {
            uint256 paymentAmount = bankPayment.amount;
            bankPayment.verified = true;
            bankPayment.verifiedBy = msg.sender;
            bankPayment.verifiedAt = block.timestamp;

            amountPaid[landId] += paymentAmount;
            bankAmountPaid[landId] += paymentAmount;

            // Check if fully paid and handle ownership transfer
            _checkAndTransferOwnership(landId);

            emit BankPaymentVerified(landId, msg.sender, paymentAmount);
        } else {
            // Reset submission on rejection
            bankPayment.submitted = false;
            emit BankPaymentRejected(landId, msg.sender);
        }
    }

    // ============ DUAL APPROVAL MECHANISM ============

    /**
     * @notice Request seller approval for ownership transfer
     * @dev Called automatically when payment is complete, but can be called manually
     * @param landId The land ID
     * 
     * @dev APPROVAL REQUEST FLOW:
     *      1. Payment must be complete (amountPaid >= totalPrice)
     *      2. Land must not already be owned
     *      3. Approval must not already be requested
     *      4. Sets sellerApprovalPending to true
     *      5. Emits SellerApprovalRequested event
     * 
     * @dev NOTE:
     *      - This is automatically called by _checkAndTransferOwnership() when payment completes
     *      - Can be called manually if needed
     */
    function requestSellerApproval(uint256 landId) external landExists(landId) {
        require(amountPaid[landId] >= lands[landId].totalPrice, "Payment not complete");
        require(!isOwned[landId], "Already owned");
        require(!sellerApprovalPending[landId], "Approval already requested");

        sellerApprovalPending[landId] = true;
        emit SellerApprovalRequested(landId, lands[landId].lockedTo);
    }

    /**
     * @notice Seller approves ownership transfer
     * @dev Only the seller can approve
     * @param landId The land ID
     * 
     * @dev APPROVAL FLOW:
     *      1. Seller reviews the transaction
     *      2. Seller calls sellerApproveTransfer(landId)
     *      3. Ownership immediately transfers to buyer
     *      4. Land is unlocked (lockedTo = address(0))
     *      5. OwnershipTransferred event is emitted
     * 
     * @dev SECURITY:
     *      - Only seller can approve
     *      - Payment must be complete
     *      - Approval must be pending
     *      - Cannot approve twice
     */
    function sellerApproveTransfer(uint256 landId) external landExists(landId) onlySeller(landId) {
        require(amountPaid[landId] >= lands[landId].totalPrice, "Payment not complete");
        require(sellerApprovalPending[landId], "No approval requested");
        require(!sellerApprovals[landId], "Already approved");

        sellerApprovals[landId] = true;

        // Complete ownership transfer
        _completeOwnershipTransfer(landId);

        emit SellerApprovalGranted(landId, msg.sender);
    }

    /**
     * @notice Seller revokes approval (before transfer completes)
     * @dev Seller can revoke if they change their mind before ownership transfer
     * @param landId The land ID
     * 
     * @dev REVOCATION FLOW:
     *      1. Seller calls sellerRevokeApproval(landId)
     *      2. Approval flags are reset
     *      3. SellerApprovalRevoked event is emitted
     *      4. Ownership transfer is blocked until seller approves again
     * 
     * @dev IMPORTANT:
     *      - Can only revoke before ownership transfer completes
     *      - Once ownership is transferred, revocation is not possible
     */
    function sellerRevokeApproval(uint256 landId) external landExists(landId) onlySeller(landId) {
        require(sellerApprovalPending[landId], "No approval pending");
        require(!isOwned[landId], "Transfer already completed");

        sellerApprovalPending[landId] = false;
        sellerApprovals[landId] = false;

        emit SellerApprovalRevoked(landId, msg.sender);
    }

    /**
     * @notice Admin bypasses seller approval (emergency only)
     * @dev Only admin can bypass, used in emergency situations
     * @param landId The land ID
     * 
     * @dev BYPASS FLOW:
     *      1. Admin calls adminBypassSellerApproval(landId)
     *      2. Seller approval is automatically granted
     *      3. Ownership transfers immediately
     * 
     * @dev SECURITY:
     *      - Only admin can bypass
     *      - Should only be used in emergency situations
     *      - Payment must be complete
     *      - Land must not already be owned
     */
    function adminBypassSellerApproval(uint256 landId) 
        external 
        landExists(landId) 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(amountPaid[landId] >= lands[landId].totalPrice, "Payment not complete");
        require(!isOwned[landId], "Already owned");

        sellerApprovals[landId] = true;
        _completeOwnershipTransfer(landId);
    }

    // ============ INTERNAL FUNCTIONS ============

    /**
     * @notice Checks if payment is complete and handles ownership transfer process
     * @dev Called automatically after each payment (crypto or bank)
     * @param landId The land ID
     * 
     * @dev INTERNAL FLOW:
     *      1. Checks if payment is complete (amountPaid >= totalPrice)
     *      2. If complete and not owned:
     *         - Requests seller approval (if not already requested)
     *         - If seller already approved, completes transfer immediately
     *      3. If not complete, does nothing
     * 
     * @dev AUTOMATIC TRIGGERS:
     *      - Called after makePayment() (crypto)
     *      - Called after verifyBankPayment() (bank, if approved)
     */
    function _checkAndTransferOwnership(uint256 landId) internal {
        if (amountPaid[landId] >= lands[landId].totalPrice && !isOwned[landId]) {
            // Request seller approval
            if (!sellerApprovalPending[landId]) {
                sellerApprovalPending[landId] = true;
                emit SellerApprovalRequested(landId, lands[landId].lockedTo);
            }

            // If seller already approved, complete transfer
            if (sellerApprovals[landId]) {
                _completeOwnershipTransfer(landId);
            }
        }
    }

    /**
     * @notice Completes ownership transfer after seller approval
     * @dev Internal function called when all conditions are met
     * @param landId The land ID
     * 
     * @dev TRANSFER FLOW:
     *      1. Validates payment is complete
     *      2. Validates seller approval is granted
     *      3. Updates owner to buyer (lockedTo address)
     *      4. Sets isOwned to true
     *      5. Unlocks land (lockedTo = address(0))
     *      6. Resets approval pending flag
     *      7. Emits OwnershipTransferred event
     * 
     * @dev FINAL STATE:
     *      - owner = buyer (was seller)
     *      - isOwned = true
     *      - lockedTo = address(0) (unlocked)
     *      - sellerApprovalPending = false
     */
    function _completeOwnershipTransfer(uint256 landId) internal {
        require(amountPaid[landId] >= lands[landId].totalPrice, "Payment not complete");
        require(sellerApprovals[landId], "Seller approval required");
        require(!isOwned[landId], "Already owned");

        address oldOwner = lands[landId].seller;
        address newOwner = lands[landId].lockedTo;

        isOwned[landId] = true;
        lands[landId].owner = newOwner;
        lands[landId].lockedTo = payable(address(0));
        sellerApprovalPending[landId] = false;

        emit OwnershipTransferred(landId, oldOwner, newOwner);
    }

    // ============ REFUNDS ============

    /**
     * @notice Buyer requests refund (with penalty)
     * @dev Only locked buyer can request refund
     * @param landId The land ID
     * 
     * @dev REFUND FLOW:
     *      1. Validates buyer is the locked buyer
     *      2. Validates there are payments to refund
     *      3. Validates ownership hasn't been transferred
     *      4. Calculates penalty: (totalPaid * penaltyBasisPoints) / 10000
     *      5. Calculates refund: totalPaid - penalty
     *      6. Resets land state (unlocks, clears payments)
     *      7. Transfers refund to buyer (only crypto portion)
     *      8. Transfers penalty to contract owner (admin)
     *      9. Emits RefundProcessed event
     * 
     * @dev REFUND CALCULATION:
     *      - Example: Paid 1000 tokens, penalty = 10% (1000 basis points)
     *      - Penalty: (1000 * 1000) / 10000 = 100 tokens
     *      - Refund: 1000 - 100 = 900 tokens to buyer
     *      - Penalty: 100 tokens to admin
     * 
     * @dev IMPORTANT:
     *      - Only crypto payments can be refunded on-chain
     *      - Bank payments cannot be refunded (handled off-chain)
     *      - Refund is proportional to crypto vs bank payments
     *      - Cannot refund after ownership transfer
     */
    function requestRefund(uint256 landId) external landExists(landId) {
        require(msg.sender == lands[landId].lockedTo, "Only locked buyer can refund");
        uint256 totalPaid = amountPaid[landId];
        require(totalPaid > 0, "No payments to refund");
        require(!isOwned[landId], "Cannot refund after ownership transfer");

        // Save crypto amount before resetting state
        uint256 cryptoPaid = cryptoAmountPaid[landId];

        // Calculate refund amounts
        uint256 penalty = (totalPaid * penaltyBasisPoints) / 10000;
        uint256 refund = totalPaid - penalty;

        // Reset land state first
        _resetLandState(landId);

        // Process refund transfers (pass cryptoPaid as parameter)
        _processRefundTransfers(totalPaid, refund, penalty, cryptoPaid);

        emit RefundProcessed(landId, msg.sender, refund, penalty);
    }

    /**
     * @notice Resets land state after refund
     * @dev Internal helper function
     * @param landId The land ID
     */
    function _resetLandState(uint256 landId) internal {
        amountPaid[landId] = 0;
        cryptoAmountPaid[landId] = 0;
        bankAmountPaid[landId] = 0;
        lands[landId].lockedTo = payable(address(0));
        sellerApprovalPending[landId] = false;
        sellerApprovals[landId] = false;

        // Reset bank payment if exists
        BankPayment storage bankPayment = bankPayments[landId];
        if (bankPayment.submitted && !bankPayment.verified) {
            bankPayment.submitted = false;
        }
    }

    /**
     * @notice Processes refund transfers (crypto only)
     * @dev Internal helper function
     * @param totalPaid Total amount paid
     * @param refund Refund amount to buyer
     * @param penalty Penalty amount to admin
     * @param cryptoPaid Crypto amount paid (for proportional refund)
     * 
     * @dev REFUND LOGIC:
     *      - Only crypto payments can be refunded on-chain
     *      - Refund is proportional: (refund * cryptoPaid) / totalPaid
     *      - Penalty is proportional: (penalty * cryptoPaid) / totalPaid
     *      - Example: Total 1000 (800 crypto, 200 bank), refund 900
     *        - Crypto refund: (900 * 800) / 1000 = 720 tokens
     *        - Penalty: (100 * 800) / 1000 = 80 tokens
     */
    function _processRefundTransfers(uint256 totalPaid, uint256 refund, uint256 penalty, uint256 cryptoPaid) internal {
        if (cryptoPaid == 0) return;
        
        // Send refund (only crypto payments can be refunded on-chain)
        if (refund > 0) {
            uint256 cryptoRefund = (refund * cryptoPaid) / totalPaid;
            if (cryptoRefund > 0) {
                require(paymentToken.transfer(msg.sender, cryptoRefund), "Refund failed");
            }
        }

        // Send penalty to owner (admin/platform)
        if (penalty > 0) {
            uint256 cryptoPenalty = (penalty * cryptoPaid) / totalPaid;
            if (cryptoPenalty > 0) {
                require(paymentToken.transfer(owner(), cryptoPenalty), "Penalty transfer failed");
            }
        }
    }

    // ============ ADMIN FUNCTIONS ============

    /**
     * @notice Admin can force-unlock land (e.g., buyer inactive for 90 days)
     * @dev Only admin can unlock
     * @param landId The land ID
     * 
     * @dev USE CASES:
     *      - Buyer becomes inactive
     *      - Buyer violates terms
     *      - Dispute resolution
     * 
     * @dev NOTE:
     *      - amountPaid is kept for record
     *      - Can be reset if needed in future upgrade
     */
    function adminUnlockLand(uint256 landId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(lands[landId].lockedTo != address(0), "Not locked");
        lands[landId].lockedTo = payable(address(0));
        // Note: amountPaid is kept for record, but can be reset if needed
    }

    /**
     * @notice Admin updates penalty percentage
     * @dev Only admin can update
     * @param _penaltyBasisPoints New penalty in basis points (10000 = 100%)
     * 
     * @dev EXAMPLES:
     *      - 1000 = 10% penalty
     *      - 500 = 5% penalty
     *      - 0 = No penalty
     *      - 10000 = 100% penalty (no refund)
     * 
     * @dev SECURITY:
     *      - Cannot exceed 100% (10000 basis points)
     *      - Emits event for transparency
     */
    function setPenaltyBasisPoints(uint16 _penaltyBasisPoints) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_penaltyBasisPoints <= 10000, "Penalty cannot exceed 100%");
        uint16 oldPenalty = penaltyBasisPoints;
        penaltyBasisPoints = _penaltyBasisPoints;
        emit PenaltyBasisPointsUpdated(oldPenalty, _penaltyBasisPoints);
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @notice Get payment breakdown for a land
     * @param landId The land ID
     * @return totalPaid Total amount paid (crypto + bank)
     * @return cryptoPaid Crypto (ERC-20) amount paid
     * @return bankPaid Bank transfer amount paid
     * @return remaining Remaining amount to be paid
     * 
     * @dev USAGE:
     *      - Frontend can display payment progress
     *      - Shows breakdown of payment methods
     *      - Calculates remaining balance
     */
    function getPaymentBreakdown(uint256 landId) 
        external 
        view 
        landExists(landId) 
        returns (
            uint256 totalPaid,
            uint256 cryptoPaid,
            uint256 bankPaid,
            uint256 remaining
        ) 
    {
        totalPaid = amountPaid[landId];
        cryptoPaid = cryptoAmountPaid[landId];
        bankPaid = bankAmountPaid[landId];
        uint256 price = lands[landId].totalPrice;
        remaining = price > totalPaid ? price - totalPaid : 0;
    }

    /**
     * @notice Get seller approval status
     * @param landId The land ID
     * @return approvalPending Whether approval is pending
     * @return approved Whether seller has approved
     * @return seller Seller address
     * 
     * @dev USAGE:
     *      - Frontend can show approval status
     *      - Seller can check if they need to approve
     *      - Buyer can track approval progress
     */
    function getSellerApprovalStatus(uint256 landId)
        external
        view
        landExists(landId)
        returns (
            bool approvalPending,
            bool approved,
            address seller
        )
    {
        approvalPending = sellerApprovalPending[landId];
        approved = sellerApprovals[landId];
        seller = lands[landId].seller;
    }
}
