// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {LandRegistryUpgradeable} from "../src/LandRegistryUpgradeable.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract LandRegistryTest is Test {
    LandRegistryUpgradeable public registry;
    LandRegistryUpgradeable public implementation;
    MockERC20 public token;
    
    address public admin = address(0x1);
    address public seller = address(0x2);
    address public buyer = address(0x3);
    address public builder = address(0x4);
    address public randomUser = address(0x5);
    
    uint256 public constant LAND_PRICE = 1000e18;
    string public constant IPFS_HASH = "QmTestHash123";
    bytes32 public constant DOCUMENT_HASH = keccak256("document_hash_test");
    
    event LandLocked(uint256 landId, address buyer);
    event PaymentReceived(uint256 landId, address buyer, uint256 amount, bool isBankPayment);
    event OwnershipTransferred(uint256 landId, address oldOwner, address newOwner);
    event RefundProcessed(uint256 landId, address buyer, uint256 refundedAmount, uint256 penalty);
    event SellerApprovalRequested(uint256 landId, address buyer);
    event SellerApprovalGranted(uint256 landId, address seller);
    event BankPaymentSubmitted(uint256 landId, address buyer, uint256 amount, string proofHash);
    event BankPaymentVerified(uint256 landId, address verifier, uint256 amount);
    event LandUpdateRequested(uint256 indexed landId, address indexed seller, bytes32 newDocumentHash);
    event LandUpdateApproved(uint256 indexed landId, address indexed seller);
    event LandUpdateRevoked(uint256 indexed landId, address indexed seller);
    
    function setUp() public {
        // Setup accounts
        vm.startPrank(admin);
        
        // Deploy mock ERC20 token
        token = new MockERC20("Land Token", "LAND");
        
        // Deploy implementation
        implementation = new LandRegistryUpgradeable();
        
        // Deploy proxy with initialization
        bytes memory initData = abi.encodeWithSelector(
            LandRegistryUpgradeable.initialize.selector,
            address(token)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        registry = LandRegistryUpgradeable(payable(address(proxy)));
        
        // Setup builder role
        registry.grantBuilderRole(builder);
        
        // Mint tokens to buyer
        token.mint(buyer, 100000e18);
        token.mint(seller, 100000e18);
        
        vm.stopPrank();
        
        // Approve tokens
        vm.prank(buyer);
        token.approve(address(registry), type(uint256).max);
    }
    
    // ============ HELPER FUNCTIONS ============
    
    function registerLand(
        address _seller,
        uint256 _price
    ) internal returns (uint256) {
        vm.prank(admin);
        registry.registerLand(_seller, IPFS_HASH, DOCUMENT_HASH, _price);
        return registry.nextLandId() - 1;
    }
    
    
    // ============ TEST: LAND REGISTRATION ============
    
    function test_RegisterLand() public {
        vm.prank(admin);
        registry.registerLand(seller, IPFS_HASH, DOCUMENT_HASH, LAND_PRICE);
        
        uint256 landId = 1;
        
        (address owner, address sellerAddr, string memory ipfs, bytes32 docHash, uint256 price, ) = registry.lands(landId);
        
        assertEq(owner, seller);
        assertEq(sellerAddr, seller);
        assertEq(ipfs, IPFS_HASH);
        assertEq(docHash, DOCUMENT_HASH);
        assertEq(price, LAND_PRICE);
        assertTrue(registry.isRegistered(landId));
    }
    
    function test_RegisterLand_OnlyAdmin() public {
        vm.prank(buyer);
        vm.expectRevert();
        registry.registerLand(seller, IPFS_HASH, DOCUMENT_HASH, LAND_PRICE);
    }
    
    // ============ TEST: LAND LOCKING ============
    
    function test_LockLandToBuyer() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(admin);
        registry.lockLandToBuyer(landId, buyer);
        
        (, , , , , address payable locked) = registry.lands(landId);
        
        assertEq(locked, buyer);
        assertFalse(registry.isOwned(landId));
    }
    
    function test_LockLand_AlreadyLocked() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(admin);
        registry.lockLandToBuyer(landId, buyer);
        
        vm.prank(admin);
        vm.expectRevert("Land: Already reserved");
        registry.lockLandToBuyer(landId, randomUser);
    }
    
    function test_LockLand_AlreadyOwned() public {
        uint256 landId = registerLand(seller, 0); // Free land
        
        vm.expectRevert("Land: Already sold");
        vm.prank(admin);
        registry.lockLandToBuyer(landId, buyer);
    }
    
    function test_LockLand_OnlyAdmin() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(buyer);
        vm.expectRevert();
        registry.lockLandToBuyer(landId, buyer);
    }
    
    // ============ TEST: CRYPTO PAYMENTS ============
    
    function test_MakePayment() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(admin);
        registry.lockLandToBuyer(landId, buyer);
        
        uint256 paymentAmount = 500e18;
        vm.prank(admin);
        
        // Payment doesn't complete total, so only PaymentReceived event
        // Use less strict event matching - check data only
        vm.expectEmit(false, false, false, true);
        emit PaymentReceived(landId, buyer, paymentAmount, false);
        
        registry.makePayment(landId, buyer, paymentAmount);
        
        assertEq(registry.amountPaid(landId), paymentAmount);
        assertEq(registry.cryptoAmountPaid(landId), paymentAmount);
        assertEq(token.balanceOf(address(registry)), paymentAmount);
    }
    
    function test_MakePayment_Installments() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(admin);
        registry.lockLandToBuyer(landId, buyer);
        
        // First payment
        vm.prank(admin);
        registry.makePayment(landId, buyer, 300e18);
        assertEq(registry.amountPaid(landId), 300e18);
        
        // Second payment
        vm.prank(admin);
        registry.makePayment(landId, buyer, 400e18);
        assertEq(registry.amountPaid(landId), 700e18);
        
        // Final payment
        vm.prank(admin);
        registry.makePayment(landId, buyer, 300e18);
        assertEq(registry.amountPaid(landId), LAND_PRICE);
    }
    
    function test_MakePayment_OnlyLockedBuyer() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(admin);
        registry.lockLandToBuyer(landId, buyer);
        
        vm.prank(admin);
        vm.expectRevert("Buyer must be the locked buyer");
        registry.makePayment(landId, randomUser, 100e18);
    }
    
    function test_MakePayment_ExceedsTotalPrice() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(admin);
        registry.lockLandToBuyer(landId, buyer);
        
        vm.prank(admin);
        vm.expectRevert("Payment exceeds total price");
        registry.makePayment(landId, buyer, LAND_PRICE + 1);
    }
    
    function test_MakePayment_OnlyAdmin() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(admin);
        registry.lockLandToBuyer(landId, buyer);
        
        vm.prank(buyer);
        vm.expectRevert();
        registry.makePayment(landId, buyer, 100e18);
    }
    
    // ============ TEST: BANK PAYMENTS ============
    
    function test_SubmitBankPayment() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(admin);
        registry.lockLandToBuyer(landId, buyer);
        
        uint256 bankAmount = 500e18;
        string memory proofHash = "QmBankProof123";
        
        vm.prank(admin);
        // Use less strict event matching - check data only
        vm.expectEmit(false, false, false, true);
        emit BankPaymentSubmitted(landId, buyer, bankAmount, proofHash);
        
        registry.submitBankPayment(landId, buyer, bankAmount, proofHash);
        
        (bool submitted, , , uint256 amount, string memory hash, , ) = registry.bankPayments(landId);
        assertTrue(submitted);
        assertEq(amount, bankAmount);
        assertEq(hash, proofHash);
    }
    
    function test_VerifyBankPayment() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(admin);
        registry.lockLandToBuyer(landId, buyer);
        
        uint256 bankAmount = 500e18;
        vm.prank(admin);
        registry.submitBankPayment(landId, buyer, bankAmount, "proof");
        
        vm.prank(admin);
        // Bank payment verification doesn't complete total, so only BankPaymentVerified event
        // Use less strict matching
        vm.expectEmit(false, false, false, true);
        emit BankPaymentVerified(landId, admin, bankAmount);
        
        registry.verifyBankPayment(landId, true);
        
        (, bool verified, address verifiedBy, , , , ) = registry.bankPayments(landId);
        assertTrue(verified);
        assertEq(verifiedBy, admin);
        assertEq(registry.bankAmountPaid(landId), bankAmount);
        assertEq(registry.amountPaid(landId), bankAmount);
    }
    
    function test_VerifyBankPayment_Reject() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(admin);
        registry.lockLandToBuyer(landId, buyer);
        
        vm.prank(admin);
        registry.submitBankPayment(landId, buyer, 500e18, "proof");
        
        vm.prank(admin);
        registry.verifyBankPayment(landId, false);
        
        (bool submitted, bool verified, , , , , ) = registry.bankPayments(landId);
        assertFalse(submitted);
        assertFalse(verified);
    }
    
    function test_SubmitBankPayment_OnlyAdmin() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(admin);
        registry.lockLandToBuyer(landId, buyer);
        
        vm.prank(buyer);
        vm.expectRevert();
        registry.submitBankPayment(landId, buyer, 500e18, "proof");
    }
    
    function test_VerifyBankPayment_OnlyAdmin() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(admin);
        registry.lockLandToBuyer(landId, buyer);
        
        vm.prank(admin);
        registry.submitBankPayment(landId, buyer, 500e18, "proof");
        
        vm.prank(builder);
        vm.expectRevert();
        registry.verifyBankPayment(landId, true);
    }
    
    // ============ TEST: DUAL APPROVAL ============
    
    function test_OwnershipTransfer_WithSellerApproval() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        // Buyer locks and pays
        vm.prank(admin);
        registry.lockLandToBuyer(landId, buyer);
        
        vm.prank(admin);
        // Payment completes total, so both PaymentReceived and SellerApprovalRequested are emitted
        // Use less strict matching - just check data, not topics
        vm.expectEmit(false, false, false, true);
        emit PaymentReceived(landId, buyer, LAND_PRICE, false);
        vm.expectEmit(false, false, false, true);
        emit SellerApprovalRequested(landId, buyer);
        registry.makePayment(landId, buyer, LAND_PRICE);
        
        // Payment complete, approval requested
        assertTrue(registry.sellerApprovalPending(landId));
        assertFalse(registry.sellerApprovals(landId));
        
        // Admin approves on behalf of seller
        vm.prank(admin);
        // Use less strict matching
        vm.expectEmit(false, false, false, true);
        emit OwnershipTransferred(landId, seller, buyer);
        
        registry.sellerApproveTransfer(landId, seller);
        
        (address newOwner, , , , , address payable locked) = registry.lands(landId);
        assertTrue(registry.isOwned(landId));
        assertEq(newOwner, buyer);
        assertEq(locked, address(0));
    }
    
    function test_SellerApproval_OnlyAdmin() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(admin);
        registry.lockLandToBuyer(landId, buyer);
        vm.prank(admin);
        registry.makePayment(landId, buyer, LAND_PRICE);
        
        vm.prank(buyer);
        vm.expectRevert();
        registry.sellerApproveTransfer(landId, seller);
    }
    
    function test_SellerApproval_WrongSeller() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(admin);
        registry.lockLandToBuyer(landId, buyer);
        vm.prank(admin);
        registry.makePayment(landId, buyer, LAND_PRICE);
        
        vm.prank(admin);
        vm.expectRevert("Address must be the land seller");
        registry.sellerApproveTransfer(landId, randomUser);
    }
    
    function test_SellerRevokeApproval() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(admin);
        registry.lockLandToBuyer(landId, buyer);
        vm.prank(admin);
        registry.makePayment(landId, buyer, LAND_PRICE);
        
        // Approval is pending but not yet approved
        assertTrue(registry.sellerApprovalPending(landId));
        assertFalse(registry.sellerApprovals(landId));
        
        // Admin revokes on behalf of seller before approving (can revoke when pending)
        vm.prank(admin);
        registry.sellerRevokeApproval(landId, seller);
        
        assertFalse(registry.sellerApprovalPending(landId));
        assertFalse(registry.sellerApprovals(landId));
        
        // Now try to revoke again - should fail
        vm.prank(admin);
        vm.expectRevert("No approval pending");
        registry.sellerRevokeApproval(landId, seller);
    }
    
    function test_AdminBypassSellerApproval() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(admin);
        registry.lockLandToBuyer(landId, buyer);
        vm.prank(admin);
        registry.makePayment(landId, buyer, LAND_PRICE);
        
        vm.prank(admin);
        registry.adminBypassSellerApproval(landId);
        
        (address owner, , , , , ) = registry.lands(landId);
        assertTrue(registry.isOwned(landId));
        assertEq(owner, buyer);
    }
    
    // ============ TEST: REFUNDS ============
    
    function test_RequestRefund() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(admin);
        registry.lockLandToBuyer(landId, buyer);
        
        uint256 paymentAmount = 500e18;
        vm.prank(admin);
        registry.makePayment(landId, buyer, paymentAmount);
        
        uint256 buyerBalanceBefore = token.balanceOf(buyer);
        uint256 adminBalanceBefore = token.balanceOf(admin);
        
        vm.prank(admin);
        registry.requestRefund(landId, buyer);
        
        uint256 penalty = (paymentAmount * 1000) / 10000; // 10%
        uint256 refund = paymentAmount - penalty;
        
        assertEq(token.balanceOf(buyer), buyerBalanceBefore + refund);
        assertEq(token.balanceOf(admin), adminBalanceBefore + penalty);
        (, , , , , address payable locked) = registry.lands(landId);
        assertEq(registry.amountPaid(landId), 0);
        assertEq(locked, address(0));
    }
    
    function test_RequestRefund_OnlyLockedBuyer() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(admin);
        registry.lockLandToBuyer(landId, buyer);
        vm.prank(admin);
        registry.makePayment(landId, buyer, 500e18);
        
        vm.prank(admin);
        vm.expectRevert("Buyer must be the locked buyer");
        registry.requestRefund(landId, randomUser);
    }
    
    function test_RequestRefund_OnlyAdmin() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(admin);
        registry.lockLandToBuyer(landId, buyer);
        vm.prank(admin);
        registry.makePayment(landId, buyer, 500e18);
        
        vm.prank(buyer);
        vm.expectRevert();
        registry.requestRefund(landId, buyer);
    }
    
    // ============ TEST: HYBRID PAYMENTS ============
    
    function test_HybridPayment_CryptoAndBank() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(admin);
        registry.lockLandToBuyer(landId, buyer);
        
        // Crypto payment
        vm.prank(admin);
        registry.makePayment(landId, buyer, 600e18);
        
        // Bank payment
        vm.prank(admin);
        registry.submitBankPayment(landId, buyer, 400e18, "proof");
        
        vm.prank(admin);
        registry.verifyBankPayment(landId, true);
        
        (uint256 totalPaid, uint256 cryptoPaid, uint256 bankPaid, uint256 remaining) = 
            registry.getPaymentBreakdown(landId);
        
        assertEq(totalPaid, LAND_PRICE);
        assertEq(cryptoPaid, 600e18);
        assertEq(bankPaid, 400e18);
        assertEq(remaining, 0);
    }
    
    // ============ TEST: ROLE MANAGEMENT ============
    
    function test_GrantBuilderRole() public {
        vm.prank(admin);
        registry.grantBuilderRole(randomUser);
        
        assertTrue(registry.hasRole(registry.BUILDER_ROLE(), randomUser));
    }
    
    function test_GrantBuilderRole_OnlyAdmin() public {
        vm.prank(buyer);
        vm.expectRevert();
        registry.grantBuilderRole(randomUser);
    }
    
    // ============ TEST: PENALTY CONFIGURATION ============
    
    function test_SetPenaltyBasisPoints() public {
        vm.prank(admin);
        registry.setPenaltyBasisPoints(500); // 5%
        
        assertEq(registry.penaltyBasisPoints(), 500);
    }
    
    function test_SetPenaltyBasisPoints_Exceeds100() public {
        vm.prank(admin);
        vm.expectRevert("Penalty cannot exceed 100%");
        registry.setPenaltyBasisPoints(10001);
    }
    
    // ============ TEST: VIEW FUNCTIONS ============
    
    function test_GetPaymentBreakdown() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(admin);
        registry.lockLandToBuyer(landId, buyer);
        vm.prank(admin);
        registry.makePayment(landId, buyer, 300e18);
        
        (uint256 totalPaid, uint256 cryptoPaid, uint256 bankPaid, uint256 remaining) = 
            registry.getPaymentBreakdown(landId);
        
        assertEq(totalPaid, 300e18);
        assertEq(cryptoPaid, 300e18);
        assertEq(bankPaid, 0);
        assertEq(remaining, 700e18);
    }
    
    function test_GetSellerApprovalStatus() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(admin);
        registry.lockLandToBuyer(landId, buyer);
        vm.prank(admin);
        registry.makePayment(landId, buyer, LAND_PRICE);
        
        (bool pending, bool approved, address sellerAddr) = registry.getSellerApprovalStatus(landId);
        
        assertTrue(pending);
        assertFalse(approved);
        assertEq(sellerAddr, seller);
    }
    
    // ============ TEST: ADMIN FUNCTIONS ============
    
    function test_AdminUnlockLand() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(admin);
        registry.lockLandToBuyer(landId, buyer);
        
        vm.prank(admin);
        registry.adminUnlockLand(landId);
        
        (, , , , , address payable locked) = registry.lands(landId);
        assertEq(locked, address(0));
    }
    
    // ============ TEST: LAND UPDATE ============
    
    function test_UpdateLand_PriceOnly() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(admin);
        registry.updateLand(landId, "", bytes32(0), 2000e18);
        
        (, , , , uint256 newPrice, ) = registry.lands(landId);
        assertEq(newPrice, 2000e18);
    }
    
    function test_UpdateLand_IPFSOnly() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        string memory newIPFS = "QmNewHash456";
        vm.prank(admin);
        registry.updateLand(landId, newIPFS, bytes32(0), 0);
        
        (, , string memory ipfs, , , ) = registry.lands(landId);
        assertEq(ipfs, newIPFS);
    }
    
    function test_UpdateLand_DocumentHash_RequiresApproval() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        bytes32 newDocHash = keccak256("new_document");
        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit LandUpdateRequested(landId, seller, newDocHash);
        registry.updateLand(landId, "", newDocHash, 0);
        
        assertTrue(registry.sellerApprovalPending(landId));
        assertFalse(registry.sellerApprovals(landId));
        
        // Admin approves on behalf of seller
        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit LandUpdateApproved(landId, seller);
        registry.sellerApproveUpdate(landId, seller);
        
        assertFalse(registry.sellerApprovalPending(landId));
        assertTrue(registry.sellerApprovals(landId));
    }
    
    function test_UpdateLand_OnlyAdmin() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(buyer);
        vm.expectRevert();
        registry.updateLand(landId, "new", bytes32(0), 0);
    }
    
    function test_UpdateLand_CannotUpdateSoldLand() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(admin);
        registry.lockLandToBuyer(landId, buyer);
        vm.prank(admin);
        registry.makePayment(landId, buyer, LAND_PRICE);
        vm.prank(admin);
        registry.sellerApproveTransfer(landId, seller);
        
        vm.prank(admin);
        vm.expectRevert("Cannot update sold land");
        registry.updateLand(landId, "new", bytes32(0), 0);
    }
    
    function test_SellerRevokeUpdateApproval() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        bytes32 newDocHash = keccak256("new_document");
        vm.prank(admin);
        registry.updateLand(landId, "", newDocHash, 0);
        
        assertTrue(registry.sellerApprovalPending(landId));
        
        // Admin revokes on behalf of seller
        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit LandUpdateRevoked(landId, seller);
        registry.sellerRevokeUpdateApproval(landId, seller);
        
        assertFalse(registry.sellerApprovalPending(landId));
        assertFalse(registry.sellerApprovals(landId));
    }
}

