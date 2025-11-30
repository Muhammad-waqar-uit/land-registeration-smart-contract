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
        
        vm.prank(buyer);
        registry.lockLandToBuyer(landId);
        
        (, , , , , address payable locked) = registry.lands(landId);
        
        assertEq(locked, buyer);
        assertFalse(registry.isOwned(landId));
    }
    
    function test_LockLand_AlreadyLocked() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(buyer);
        registry.lockLandToBuyer(landId);
        
        vm.prank(randomUser);
        vm.expectRevert("Land: Already reserved");
        registry.lockLandToBuyer(landId);
    }
    
    function test_LockLand_AlreadyOwned() public {
        uint256 landId = registerLand(seller, 0); // Free land
        
        vm.expectRevert("Land: Already sold");
        vm.prank(buyer);
        registry.lockLandToBuyer(landId);
    }
    
    // ============ TEST: CRYPTO PAYMENTS ============
    
    function test_MakePayment() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(buyer);
        registry.lockLandToBuyer(landId);
        
        uint256 paymentAmount = 500e18;
        vm.prank(buyer);
        
        // Payment doesn't complete total, so only PaymentReceived event
        // Use less strict event matching - check data only
        vm.expectEmit(false, false, false, true);
        emit PaymentReceived(landId, buyer, paymentAmount, false);
        
        registry.makePayment(landId, paymentAmount);
        
        assertEq(registry.amountPaid(landId), paymentAmount);
        assertEq(registry.cryptoAmountPaid(landId), paymentAmount);
        assertEq(token.balanceOf(address(registry)), paymentAmount);
    }
    
    function test_MakePayment_Installments() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(buyer);
        registry.lockLandToBuyer(landId);
        
        // First payment
        vm.prank(buyer);
        registry.makePayment(landId, 300e18);
        assertEq(registry.amountPaid(landId), 300e18);
        
        // Second payment
        vm.prank(buyer);
        registry.makePayment(landId, 400e18);
        assertEq(registry.amountPaid(landId), 700e18);
        
        // Final payment
        vm.prank(buyer);
        registry.makePayment(landId, 300e18);
        assertEq(registry.amountPaid(landId), LAND_PRICE);
    }
    
    function test_MakePayment_OnlyLockedBuyer() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(randomUser);
        vm.expectRevert("Payment: Only locked buyer can pay");
        registry.makePayment(landId, 100e18);
    }
    
    function test_MakePayment_ExceedsTotalPrice() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(buyer);
        registry.lockLandToBuyer(landId);
        
        vm.prank(buyer);
        vm.expectRevert("Payment exceeds total price");
        registry.makePayment(landId, LAND_PRICE + 1);
    }
    
    // ============ TEST: BANK PAYMENTS ============
    
    function test_SubmitBankPayment() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(buyer);
        registry.lockLandToBuyer(landId);
        
        uint256 bankAmount = 500e18;
        string memory proofHash = "QmBankProof123";
        
        vm.prank(buyer);
        // Use less strict event matching - check data only
        vm.expectEmit(false, false, false, true);
        emit BankPaymentSubmitted(landId, buyer, bankAmount, proofHash);
        
        registry.submitBankPayment(landId, bankAmount, proofHash);
        
        (bool submitted, , , uint256 amount, string memory hash, , ) = registry.bankPayments(landId);
        assertTrue(submitted);
        assertEq(amount, bankAmount);
        assertEq(hash, proofHash);
    }
    
    function test_VerifyBankPayment() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(buyer);
        registry.lockLandToBuyer(landId);
        
        uint256 bankAmount = 500e18;
        vm.prank(buyer);
        registry.submitBankPayment(landId, bankAmount, "proof");
        
        vm.prank(builder);
        // Bank payment verification doesn't complete total, so only BankPaymentVerified event
        // Use less strict matching
        vm.expectEmit(false, false, false, true);
        emit BankPaymentVerified(landId, builder, bankAmount);
        
        registry.verifyBankPayment(landId, true);
        
        (, bool verified, address verifiedBy, , , , ) = registry.bankPayments(landId);
        assertTrue(verified);
        assertEq(verifiedBy, builder);
        assertEq(registry.bankAmountPaid(landId), bankAmount);
        assertEq(registry.amountPaid(landId), bankAmount);
    }
    
    function test_VerifyBankPayment_Reject() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(buyer);
        registry.lockLandToBuyer(landId);
        
        vm.prank(buyer);
        registry.submitBankPayment(landId, 500e18, "proof");
        
        vm.prank(builder);
        registry.verifyBankPayment(landId, false);
        
        (bool submitted, bool verified, , , , , ) = registry.bankPayments(landId);
        assertFalse(submitted);
        assertFalse(verified);
    }
    
    // ============ TEST: DUAL APPROVAL ============
    
    function test_OwnershipTransfer_WithSellerApproval() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        // Buyer locks and pays
        vm.prank(buyer);
        registry.lockLandToBuyer(landId);
        
        vm.prank(buyer);
        // Payment completes total, so both PaymentReceived and SellerApprovalRequested are emitted
        // Use less strict matching - just check data, not topics
        vm.expectEmit(false, false, false, true);
        emit PaymentReceived(landId, buyer, LAND_PRICE, false);
        vm.expectEmit(false, false, false, true);
        emit SellerApprovalRequested(landId, buyer);
        registry.makePayment(landId, LAND_PRICE);
        
        // Payment complete, approval requested
        assertTrue(registry.sellerApprovalPending(landId));
        assertFalse(registry.sellerApprovals(landId));
        
        // Seller approves
        vm.prank(seller);
        // Use less strict matching
        vm.expectEmit(false, false, false, true);
        emit OwnershipTransferred(landId, seller, buyer);
        
        registry.sellerApproveTransfer(landId);
        
        (address newOwner, , , , , address payable locked) = registry.lands(landId);
        assertTrue(registry.isOwned(landId));
        assertEq(newOwner, buyer);
        assertEq(locked, address(0));
    }
    
    function test_SellerApproval_OnlySeller() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(buyer);
        registry.lockLandToBuyer(landId);
        vm.prank(buyer);
        registry.makePayment(landId, LAND_PRICE);
        
        vm.prank(buyer);
        vm.expectRevert("Only seller can perform this action");
        registry.sellerApproveTransfer(landId);
    }
    
    function test_SellerRevokeApproval() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(buyer);
        registry.lockLandToBuyer(landId);
        vm.prank(buyer);
        registry.makePayment(landId, LAND_PRICE);
        
        // Approval is pending but not yet approved
        assertTrue(registry.sellerApprovalPending(landId));
        assertFalse(registry.sellerApprovals(landId));
        
        // Seller revokes before approving (can revoke when pending)
        vm.prank(seller);
        registry.sellerRevokeApproval(landId);
        
        assertFalse(registry.sellerApprovalPending(landId));
        assertFalse(registry.sellerApprovals(landId));
        
        // Now try to revoke again - should fail
        vm.prank(seller);
        vm.expectRevert("No approval pending");
        registry.sellerRevokeApproval(landId);
    }
    
    function test_AdminBypassSellerApproval() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(buyer);
        registry.lockLandToBuyer(landId);
        vm.prank(buyer);
        registry.makePayment(landId, LAND_PRICE);
        
        vm.prank(admin);
        registry.adminBypassSellerApproval(landId);
        
        (address owner, , , , , ) = registry.lands(landId);
        assertTrue(registry.isOwned(landId));
        assertEq(owner, buyer);
    }
    
    // ============ TEST: REFUNDS ============
    
    function test_RequestRefund() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(buyer);
        registry.lockLandToBuyer(landId);
        
        uint256 paymentAmount = 500e18;
        vm.prank(buyer);
        registry.makePayment(landId, paymentAmount);
        
        uint256 buyerBalanceBefore = token.balanceOf(buyer);
        uint256 adminBalanceBefore = token.balanceOf(admin);
        
        vm.prank(buyer);
        registry.requestRefund(landId);
        
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
        
        vm.prank(buyer);
        registry.lockLandToBuyer(landId);
        vm.prank(buyer);
        registry.makePayment(landId, 500e18);
        
        vm.prank(randomUser);
        vm.expectRevert("Only locked buyer can refund");
        registry.requestRefund(landId);
    }
    
    // ============ TEST: HYBRID PAYMENTS ============
    
    function test_HybridPayment_CryptoAndBank() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(buyer);
        registry.lockLandToBuyer(landId);
        
        // Crypto payment
        vm.prank(buyer);
        registry.makePayment(landId, 600e18);
        
        // Bank payment
        vm.prank(buyer);
        registry.submitBankPayment(landId, 400e18, "proof");
        
        vm.prank(builder);
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
        
        vm.prank(buyer);
        registry.lockLandToBuyer(landId);
        vm.prank(buyer);
        registry.makePayment(landId, 300e18);
        
        (uint256 totalPaid, uint256 cryptoPaid, uint256 bankPaid, uint256 remaining) = 
            registry.getPaymentBreakdown(landId);
        
        assertEq(totalPaid, 300e18);
        assertEq(cryptoPaid, 300e18);
        assertEq(bankPaid, 0);
        assertEq(remaining, 700e18);
    }
    
    function test_GetSellerApprovalStatus() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(buyer);
        registry.lockLandToBuyer(landId);
        vm.prank(buyer);
        registry.makePayment(landId, LAND_PRICE);
        
        (bool pending, bool approved, address sellerAddr) = registry.getSellerApprovalStatus(landId);
        
        assertTrue(pending);
        assertFalse(approved);
        assertEq(sellerAddr, seller);
    }
    
    // ============ TEST: ADMIN FUNCTIONS ============
    
    function test_AdminUnlockLand() public {
        uint256 landId = registerLand(seller, LAND_PRICE);
        
        vm.prank(buyer);
        registry.lockLandToBuyer(landId);
        
        vm.prank(admin);
        registry.adminUnlockLand(landId);
        
        (, , , , , address payable locked) = registry.lands(landId);
        assertEq(locked, address(0));
    }
}

