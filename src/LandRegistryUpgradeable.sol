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
 *      - Admin-only access control (backend-managed operations)
 *      - Hybrid payment system (ERC-20 crypto + bank transfers)
 *      - Dual approval mechanism (seller approval required for ownership transfer)
 *      - Configurable refund system with penalty
 * 
 * @dev WORKFLOW OVERVIEW:
 *      1. Admin (backend) registers land with details (IPFS hash, document hash, price, seller address)
 *      2. Admin locks land to buyer address (exclusive reservation)
 *      3. Admin processes payments on behalf of buyer (crypto installments or bank transfers)
 *      4. When fully paid, seller approval is requested
 *      5. Admin approves on behalf of seller → Ownership transfers to buyer
 *      6. Admin processes refund (with penalty) before ownership transfer
 * 
 * @dev BACKEND-MANAGED DESIGN:
 *      - All functions are admin-only (backend controls everything)
 *      - Addresses (buyer, seller) are passed as parameters
 *      - No msg.sender dependencies for user operations
 *      - Backend pays gas fees for all operations
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

    // ============ BUILDER REGISTRY ============
    
    /**
     * @notice Builder information structure
     * @dev Stores builder license information on-chain
     */
    struct BuilderInfo {
        address builderAddress;       // Builder's wallet address
        string licenseNumber;         // Builder's license number
        bool isRegistered;            // Whether builder is registered
        uint256 registeredAt;         // Block timestamp when registered
    }
    
    /// @notice Builder registry - maps builder address to BuilderInfo
    mapping(address => BuilderInfo) public builders;
    
    /// @notice License number to builder address mapping (for uniqueness check)
    mapping(string => address) public licenseToBuilder;

    // ============ AGREEMENT & OWNERSHIP DOCUMENT STORAGE ============
    
    /**
     * @notice Agreement hash structure
     * @dev Stores signed agreement document hashes separately from land document hash
     */
    struct AgreementHash {
        bytes32 agreementHash;        // SHA-256 hash of signed agreement
        string agreementIPFSHash;     // IPFS hash of agreement document
        uint256 storedAt;             // Block timestamp when stored
        bool exists;                  // Whether agreement hash exists
    }
    
    /**
     * @notice Ownership document hash structure
     * @dev Stores final ownership document hash (separate from initial agreement)
     */
    struct OwnershipDocumentHash {
        bytes32 documentHash;         // SHA-256 hash of ownership document
        string documentIPFSHash;      // IPFS hash of ownership document
        uint256 storedAt;             // Block timestamp when stored
        bool exists;                  // Whether ownership document hash exists
    }
    
    /// @notice Agreement hash registry - maps landId to AgreementHash
    mapping(uint256 => AgreementHash) public agreementHashes;
    
    /// @notice Ownership document hash registry - maps landId to OwnershipDocumentHash
    mapping(uint256 => OwnershipDocumentHash) public ownershipDocumentHashes;

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
    
    /// @notice Emitted when admin requests land update (document hash change requires seller approval)
    event LandUpdateRequested(uint256 indexed landId, address indexed seller, bytes32 newDocumentHash);
    
    /// @notice Emitted when seller approves land update
    event LandUpdateApproved(uint256 indexed landId, address indexed seller);
    
    /// @notice Emitted when seller revokes update approval
    event LandUpdateRevoked(uint256 indexed landId, address indexed seller);
    
    /// @notice Emitted when a builder is registered
    event BuilderRegistered(address indexed builder, string licenseNumber, uint256 registeredAt);
    
    /// @notice Emitted when agreement hash is stored
    event AgreementHashStored(uint256 indexed landId, bytes32 agreementHash, string agreementIPFSHash, uint256 storedAt);
    
    /// @notice Emitted when ownership document hash is stored
    event OwnershipDocumentHashStored(uint256 indexed landId, bytes32 documentHash, string documentIPFSHash, uint256 storedAt);

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

    /**
     * @notice Register a builder with license information (admin only)
     * @dev Stores builder license number on-chain for verification
     * @param builderAddress Builder's wallet address
     * @param licenseNumber Builder's unique license number
     * 
     * @dev REGISTRATION FLOW:
     *      1. Admin calls this function after verifying builder off-chain
     *      2. License number must be unique
     *      3. Builder address cannot be registered twice
     *      4. Stores builder info in builders mapping
     *      5. Stores license-to-builder mapping for uniqueness
     *      6. Emits BuilderRegistered event
     * 
     * @dev NOTE:
     *      - This is separate from grantBuilderRole()
     *      - grantBuilderRole() grants permissions
     *      - registerBuilder() stores license information
     *      - Both should be called when verifying a builder
     */
    function registerBuilder(address builderAddress, string memory licenseNumber) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(builderAddress != address(0), "Invalid builder address");
        require(bytes(licenseNumber).length > 0, "License number required");
        require(!builders[builderAddress].isRegistered, "Builder already registered");
        require(licenseToBuilder[licenseNumber] == address(0), "License number already registered");

        BuilderInfo storage builder = builders[builderAddress];
        builder.builderAddress = builderAddress;
        builder.licenseNumber = licenseNumber;
        builder.isRegistered = true;
        builder.registeredAt = block.timestamp;

        licenseToBuilder[licenseNumber] = builderAddress;

        emit BuilderRegistered(builderAddress, licenseNumber, block.timestamp);
    }

    /**
     * @notice Get builder information by address
     * @param builderAddress Builder's wallet address
     * @return builderAddress Builder's address
     * @return licenseNumber Builder's license number
     * @return isRegistered Whether builder is registered
     * @return registeredAt Block timestamp when registered
     */
    function getBuilderInfo(address builderAddress)
        external
        view
        returns (
            address,
            string memory,
            bool,
            uint256
        )
    {
        BuilderInfo storage builder = builders[builderAddress];
        return (
            builder.builderAddress,
            builder.licenseNumber,
            builder.isRegistered,
            builder.registeredAt
        );
    }

    /**
     * @notice Check if a license number is already registered
     * @param licenseNumber License number to check
     * @return registered Whether license is registered
     * @return builderAddress Address of builder with this license (address(0) if not registered)
     */
    function isLicenseRegistered(string memory licenseNumber)
        external
        view
        returns (bool registered, address builderAddress)
    {
        builderAddress = licenseToBuilder[licenseNumber];
        registered = builderAddress != address(0);
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

    // ============ LAND UPDATE ============

    /**
     * @notice Admin updates land information (with seller approval requirement for document changes)
     * @dev Only admin can call this function
     * @dev For document hash changes, requires seller approval (dual approval mechanism)
     * @param landId The land ID to update
     * @param _ipfsHash New IPFS hash (empty string to keep existing)
     * @param _documentHash New document hash (bytes32(0) to keep existing)
     * @param _totalPrice New total price (0 to keep existing)
     * 
     * @dev UPDATE FLOW:
     *      1. Admin calls updateLand() with new values
     *      2. If document hash changes:
     *         - Requires seller approval (sellerApprovalPending set to true)
     *         - Emits LandUpdateRequested event
     *         - Seller must call sellerApproveUpdate() to complete
     *      3. If only price or IPFS changes:
     *         - Updates immediately (no approval needed)
     * 
     * @dev DUAL APPROVAL MECHANISM:
     *      - Document hash changes require Admin + Seller approval
     *      - Price/IPFS changes only require Admin approval
     * 
     * @dev EXAMPLE:
     *      Admin updates land ID 1:
     *      - New document hash: 0xabc...
     *      - New price: 2000 tokens
     *      - Result: Price updated immediately, document hash requires seller approval
     */
    function updateLand(
        uint256 landId,
        string memory _ipfsHash,
        bytes32 _documentHash,
        uint256 _totalPrice
    ) external onlyRole(DEFAULT_ADMIN_ROLE) landExists(landId) {
        require(!isOwned[landId], "Cannot update sold land");
        
        Land storage land = lands[landId];
        
        // Update IPFS hash if provided (non-empty)
        if (bytes(_ipfsHash).length > 0) {
            land.ipfsHash = _ipfsHash;
        }
        
        // Update price if provided (non-zero)
        if (_totalPrice > 0) {
            land.totalPrice = _totalPrice;
        }
        
        // Update document hash if provided (non-zero)
        // This requires seller approval
        if (_documentHash != bytes32(0)) {
            // Check if document hash is actually changing
            if (land.documentHash != _documentHash) {
                // Require seller approval for document hash changes
                sellerApprovalPending[landId] = true;
                sellerApprovals[landId] = false;
                land.documentHash = _documentHash; // Store new hash (pending approval)
                emit LandUpdateRequested(landId, land.seller, _documentHash);
            }
        }
    }

    /**
     * @notice Admin approves land update on behalf of seller (for document hash changes)
     * @dev Only admin can call this function
     * @param landId The land ID
     * @param seller The seller address (must match land seller)
     * 
     * @dev APPROVAL FLOW:
     *      1. Admin calls updateLand() with new document hash
     *      2. Seller reviews the change (off-chain)
     *      3. Admin calls sellerApproveUpdate() on behalf of seller
     *      4. Update is finalized
     */
    function sellerApproveUpdate(uint256 landId, address seller) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE)
        landExists(landId) 
    {
        require(seller != address(0), "Invalid seller address");
        require(seller == lands[landId].seller, "Address must be the land seller");
        require(sellerApprovalPending[landId], "No update pending");
        require(!sellerApprovals[landId], "Already approved");
        
        sellerApprovals[landId] = true;
        sellerApprovalPending[landId] = false;
        
        emit LandUpdateApproved(landId, seller);
    }

    /**
     * @notice Admin revokes update approval on behalf of seller
     * @dev Only admin can call this function
     * @param landId The land ID
     * @param seller The seller address (must match land seller)
     */
    function sellerRevokeUpdateApproval(uint256 landId, address seller) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE)
        landExists(landId) 
    {
        require(seller != address(0), "Invalid seller address");
        require(seller == lands[landId].seller, "Address must be the land seller");
        require(sellerApprovalPending[landId], "No update pending");
        require(!isOwned[landId], "Cannot revoke after sale");
        
        sellerApprovalPending[landId] = false;
        sellerApprovals[landId] = false;
        
        emit LandUpdateRevoked(landId, seller);
    }

    // ============ LAND LOCKING ============

    /**
     * @notice Admin locks land to a buyer (backend-managed)
     * @dev Only admin can call this function
     * @dev Allows backend to lock land on behalf of users
     * @param landId The land ID to lock
     * @param buyer The buyer address to lock the land to
     * 
     * @dev LOCKING FLOW:
     *      1. Checks land exists and is not already sold
     *      2. Checks land is not already locked by another buyer
     *      3. Sets lockedTo to buyer address (exclusive lock)
     *      4. Emits LandLocked event
     * 
     * @dev USE CASE:
     *      - Backend calls this when buyer makes reservation
     *      - Backend pays gas fees
     *      - Users don't need to interact with blockchain directly
     * 
     * @dev EXAMPLE:
     *      Admin locks land ID 1 to buyer 0xABC
     *      - lands[1].lockedTo = 0xABC
     *      - Only payments from 0xABC will be accepted for land 1
     */
    function lockLandToBuyer(uint256 landId, address buyer) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
        landExists(landId) 
    {
        require(!isOwned[landId], "Land: Already sold");
        require(lands[landId].lockedTo == address(0), "Land: Already reserved");
        require(buyer != address(0), "Invalid buyer address");

        lands[landId].lockedTo = payable(buyer);
        emit LandLocked(landId, buyer);
    }

    // ============ CRYPTO PAYMENTS ============

    /**
     * @notice Admin processes ERC-20 token payment on behalf of buyer (installments supported)
     * @dev Only admin can call this function
     * @dev Transfers tokens from buyer to contract
     * @param landId The land ID to pay for
     * @param buyer The buyer address making the payment
     * @param amount Payment amount in tokens
     * 
     * @dev PAYMENT FLOW:
     *      1. Validates buyer is the locked buyer for this land
     *      2. Validates amount > 0
     *      3. Checks land is not already fully paid
     *      4. Checks payment doesn't exceed total price
     *      5. Transfers tokens from buyer to contract
     *      6. Updates amountPaid and cryptoAmountPaid
     *      7. Emits PaymentReceived event
     *      8. If fully paid, requests seller approval automatically
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
    function makePayment(uint256 landId, address buyer, uint256 amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        landExists(landId)
    {
        require(buyer != address(0), "Invalid buyer address");
        require(buyer == lands[landId].lockedTo, "Buyer must be the locked buyer");
        require(amount > 0, "Amount must be > 0");
        require(amountPaid[landId] < lands[landId].totalPrice, "Land: Already fully paid");
        require(amountPaid[landId] + amount <= lands[landId].totalPrice, "Payment exceeds total price");

        require(
            paymentToken.transferFrom(buyer, address(this), amount),
            "Token transfer failed"
        );

        amountPaid[landId] += amount;
        cryptoAmountPaid[landId] += amount;

        // Emit payment event
        emit PaymentReceived(landId, buyer, amount, false);

        // Check if fully paid and handle ownership transfer
        _checkAndTransferOwnership(landId);
    }

    // ============ BANK PAYMENTS ============

    /**
     * @notice Admin submits bank payment proof on behalf of buyer
     * @dev Only admin can call this function
     * @param landId The land ID to pay for
     * @param buyer The buyer address making the payment
     * @param amount Payment amount
     * @param proofHash IPFS hash of bank payment proof document
     * 
     * @dev BANK PAYMENT FLOW:
     *      1. Buyer makes bank transfer off-chain
     *      2. Backend submits proof (IPFS hash) via this function
     *      3. Backend verifies the payment off-chain
     *      4. Backend calls verifyBankPayment() to approve
     *      5. Payment is added to amountPaid
     *      6. If fully paid, ownership transfer process begins
     * 
     * @dev IMPORTANT:
     *      - Bank payments require manual verification
     *      - Previous unverified payment must be verified before submitting new one
     *      - Payment is not added to amountPaid until verified
     */
    function submitBankPayment(
        uint256 landId,
        address buyer,
        uint256 amount,
        string memory proofHash
    ) external onlyRole(DEFAULT_ADMIN_ROLE) landExists(landId) {
        require(buyer != address(0), "Invalid buyer address");
        require(buyer == lands[landId].lockedTo, "Buyer must be the locked buyer");
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

        emit BankPaymentSubmitted(landId, buyer, amount, proofHash);
    }

    /**
     * @notice Admin verifies/rejects bank payment
     * @dev Only admin can verify bank payments
     * @param landId The land ID
     * @param approved true to approve, false to reject
     * 
     * @dev VERIFICATION FLOW:
     *      1. Admin reviews bank payment proof off-chain
     *      2. If valid: calls verifyBankPayment(landId, true)
     *         - Payment added to amountPaid and bankAmountPaid
     *         - If fully paid, ownership transfer process begins
     *      3. If invalid: calls verifyBankPayment(landId, false)
     *         - Payment submission is reset
     *         - Can submit new proof
     */
    function verifyBankPayment(uint256 landId, bool approved) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE)
        landExists(landId) 
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
     * @notice Admin requests seller approval for ownership transfer
     * @dev Only admin can call this function
     * @dev Called automatically when payment is complete, but can be called manually if needed
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
     *      - Can be called manually by admin if needed
     */
    function requestSellerApproval(uint256 landId) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE)
        landExists(landId) 
    {
        require(amountPaid[landId] >= lands[landId].totalPrice, "Payment not complete");
        require(!isOwned[landId], "Already owned");
        require(!sellerApprovalPending[landId], "Approval already requested");

        sellerApprovalPending[landId] = true;
        emit SellerApprovalRequested(landId, lands[landId].lockedTo);
    }

    /**
     * @notice Admin approves ownership transfer on behalf of seller
     * @dev Only admin can call this function
     * @param landId The land ID
     * @param seller The seller address (must match land seller)
     * 
     * @dev APPROVAL FLOW:
     *      1. Seller reviews the transaction (off-chain)
     *      2. Admin calls sellerApproveTransfer() on behalf of seller
     *      3. Ownership immediately transfers to buyer
     *      4. Land is unlocked (lockedTo = address(0))
     *      5. OwnershipTransferred event is emitted
     */
    function sellerApproveTransfer(uint256 landId, address seller) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE)
        landExists(landId) 
    {
        require(seller != address(0), "Invalid seller address");
        require(seller == lands[landId].seller, "Address must be the land seller");
        require(amountPaid[landId] >= lands[landId].totalPrice, "Payment not complete");
        require(sellerApprovalPending[landId], "No approval requested");
        require(!sellerApprovals[landId], "Already approved");

        sellerApprovals[landId] = true;

        // Complete ownership transfer
        _completeOwnershipTransfer(landId);

        emit SellerApprovalGranted(landId, seller);
    }

    /**
     * @notice Admin revokes approval on behalf of seller (before transfer completes)
     * @dev Only admin can call this function
     * @param landId The land ID
     * @param seller The seller address (must match land seller)
     */
    function sellerRevokeApproval(uint256 landId, address seller) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE)
        landExists(landId) 
    {
        require(seller != address(0), "Invalid seller address");
        require(seller == lands[landId].seller, "Address must be the land seller");
        require(sellerApprovalPending[landId], "No approval pending");
        require(!isOwned[landId], "Transfer already completed");

        sellerApprovalPending[landId] = false;
        sellerApprovals[landId] = false;

        emit SellerApprovalRevoked(landId, seller);
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
     * @notice Admin processes refund on behalf of buyer (with penalty)
     * @dev Only admin can call this function
     * @param landId The land ID
     * @param buyer The buyer address (must match locked buyer)
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
    function requestRefund(uint256 landId, address buyer) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE)
        landExists(landId) 
    {
        require(buyer != address(0), "Invalid buyer address");
        require(buyer == lands[landId].lockedTo, "Buyer must be the locked buyer");
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

        // Process refund transfers
        _processRefundTransfers(buyer, totalPaid, refund, penalty, cryptoPaid);

        emit RefundProcessed(landId, buyer, refund, penalty);
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
     * @param buyer The buyer address to receive refund
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
    function _processRefundTransfers(
        address buyer, 
        uint256 totalPaid, 
        uint256 refund, 
        uint256 penalty, 
        uint256 cryptoPaid
    ) internal {
        if (cryptoPaid == 0) return;
        
        // Send refund (only crypto payments can be refunded on-chain)
        if (refund > 0) {
            uint256 cryptoRefund = (refund * cryptoPaid) / totalPaid;
            if (cryptoRefund > 0) {
                require(paymentToken.transfer(buyer, cryptoRefund), "Refund failed");
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

    // ============ AGREEMENT & OWNERSHIP DOCUMENT STORAGE ============

    /**
     * @notice Store agreement hash on blockchain (admin only)
     * @dev Stores signed agreement document hash separately from land document hash
     * @param landId The land ID
     * @param agreementHash SHA-256 hash of signed agreement document
     * @param agreementIPFSHash IPFS hash of signed agreement document
     * 
     * @dev AGREEMENT STORAGE FLOW:
     *      1. Builder creates agreement and both parties sign
     *      2. Signed agreement is uploaded to IPFS
     *      3. Admin calls this function to store hash on-chain
     *      4. Hash is stored in agreementHashes mapping
     *      5. Emits AgreementHashStored event
     * 
     * @dev USE CASE:
     *      - Stores initial signed agreement hash
     *      - Separate from ownership document hash
     *      - Immutable record of agreement terms
     *      - Can be stored before payment starts
     */
    function storeAgreementHash(
        uint256 landId,
        bytes32 agreementHash,
        string memory agreementIPFSHash
    ) external onlyRole(DEFAULT_ADMIN_ROLE) landExists(landId) {
        require(agreementHash != bytes32(0), "Invalid agreement hash");
        require(bytes(agreementIPFSHash).length > 0, "IPFS hash required");

        AgreementHash storage agreement = agreementHashes[landId];
        agreement.agreementHash = agreementHash;
        agreement.agreementIPFSHash = agreementIPFSHash;
        agreement.storedAt = block.timestamp;
        agreement.exists = true;

        emit AgreementHashStored(landId, agreementHash, agreementIPFSHash, block.timestamp);
    }

    /**
     * @notice Store ownership document hash on blockchain (admin only)
     * @dev Stores final ownership document hash (separate from agreement hash)
     * @param landId The land ID
     * @param documentHash SHA-256 hash of final ownership document
     * @param documentIPFSHash IPFS hash of ownership document
     * 
     * @dev OWNERSHIP DOCUMENT STORAGE FLOW:
     *      1. After full payment and seller approval
     *      2. Builder generates final ownership document
     *      3. Document is uploaded to IPFS
     *      4. Admin calls this function to store hash on-chain
     *      5. Hash is stored in ownershipDocumentHashes mapping
     *      6. Emits OwnershipDocumentHashStored event
     * 
     * @dev USE CASE:
     *      - Stores final ownership certificate hash
     *      - Separate from initial agreement hash
     *      - Immutable record of ownership transfer
     *      - Typically stored after ownership transfer completes
     * 
     * @dev NOTE:
     *      - This is separate from updateLand() documentHash
     *      - updateLand() updates the initial land document hash
     *      - This stores the final ownership document hash
     */
    function storeOwnershipDocumentHash(
        uint256 landId,
        bytes32 documentHash,
        string memory documentIPFSHash
    ) external onlyRole(DEFAULT_ADMIN_ROLE) landExists(landId) {
        require(documentHash != bytes32(0), "Invalid document hash");
        require(bytes(documentIPFSHash).length > 0, "IPFS hash required");

        OwnershipDocumentHash storage ownershipDoc = ownershipDocumentHashes[landId];
        ownershipDoc.documentHash = documentHash;
        ownershipDoc.documentIPFSHash = documentIPFSHash;
        ownershipDoc.storedAt = block.timestamp;
        ownershipDoc.exists = true;

        emit OwnershipDocumentHashStored(landId, documentHash, documentIPFSHash, block.timestamp);
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

    /**
     * @notice Get agreement hash for a land
     * @param landId The land ID
     * @return agreementHash SHA-256 hash of agreement
     * @return agreementIPFSHash IPFS hash of agreement
     * @return storedAt Block timestamp when stored
     * @return exists Whether agreement hash exists
     */
    function getAgreementHash(uint256 landId)
        external
        view
        landExists(landId)
        returns (
            bytes32 agreementHash,
            string memory agreementIPFSHash,
            uint256 storedAt,
            bool exists
        )
    {
        AgreementHash storage agreement = agreementHashes[landId];
        return (
            agreement.agreementHash,
            agreement.agreementIPFSHash,
            agreement.storedAt,
            agreement.exists
        );
    }

    /**
     * @notice Get ownership document hash for a land
     * @param landId The land ID
     * @return documentHash SHA-256 hash of ownership document
     * @return documentIPFSHash IPFS hash of ownership document
     * @return storedAt Block timestamp when stored
     * @return exists Whether ownership document hash exists
     */
    function getOwnershipDocumentHash(uint256 landId)
        external
        view
        landExists(landId)
        returns (
            bytes32 documentHash,
            string memory documentIPFSHash,
            uint256 storedAt,
            bool exists
        )
    {
        OwnershipDocumentHash storage ownershipDoc = ownershipDocumentHashes[landId];
        return (
            ownershipDoc.documentHash,
            ownershipDoc.documentIPFSHash,
            ownershipDoc.storedAt,
            ownershipDoc.exists
        );
    }
}
