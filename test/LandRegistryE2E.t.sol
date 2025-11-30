// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {LandRegistryUpgradeable} from "../src/LandRegistryUpgradeable.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract LandRegistryE2ETest is Test {
    LandRegistryUpgradeable public registry;
    MockERC20 public token;
    
    address public admin = address(0x1);
    address public seller = address(0x2);
    address public buyer = address(0x3);
    address public builder = address(0x4);
    
    uint256 public constant LAND_PRICE = 1000e18;
    
    function setUp() public {
        vm.startPrank(admin);
        token = new MockERC20("Land Token", "LAND");
        
        LandRegistryUpgradeable impl = new LandRegistryUpgradeable();
        bytes memory initData = abi.encodeWithSelector(
            LandRegistryUpgradeable.initialize.selector,
            address(token)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        registry = LandRegistryUpgradeable(payable(address(proxy)));
        registry.grantBuilderRole(builder);
        
        token.mint(buyer, 100000e18);
        token.mint(seller, 100000e18);
        vm.stopPrank();
        
        vm.prank(buyer);
        token.approve(address(registry), type(uint256).max);
    }
    
    // ============ E2E TEST: FULL WORKFLOW WITH CRYPTO PAYMENT ============
    
    function test_E2E_FullWorkflow_CryptoPayment() public {
        // 1. Admin registers land
        vm.prank(admin);
        registry.registerLand(seller, "QmHash123", keccak256("doc"), LAND_PRICE);
        uint256 landId = 1;
        
        // 2. Buyer locks the land
        vm.prank(buyer);
        registry.lockLandToBuyer(landId);
        (, , , , , address payable locked1) = registry.lands(landId);
        assertEq(locked1, buyer);
        
        // 3. Buyer makes installment payments
        vm.prank(buyer);
        registry.makePayment(landId, 300e18);
        assertEq(registry.amountPaid(landId), 300e18);
        
        vm.prank(buyer);
        registry.makePayment(landId, 400e18);
        assertEq(registry.amountPaid(landId), 700e18);
        
        vm.prank(buyer);
        registry.makePayment(landId, 300e18);
        assertEq(registry.amountPaid(landId), LAND_PRICE);
        
        // 4. Payment complete, approval requested
        assertTrue(registry.sellerApprovalPending(landId));
        
        // 5. Seller approves
        vm.prank(seller);
        registry.sellerApproveTransfer(landId);
        
        // 6. Ownership transferred
        (address owner, , , , , address payable locked2) = registry.lands(landId);
        assertTrue(registry.isOwned(landId));
        assertEq(owner, buyer);
        assertEq(locked2, address(0));
    }
    
    // ============ E2E TEST: FULL WORKFLOW WITH HYBRID PAYMENT ============
    
    function test_E2E_FullWorkflow_HybridPayment() public {
        // 1. Admin registers land
        vm.prank(admin);
        registry.registerLand(seller, "QmHash123", keccak256("doc"), LAND_PRICE);
        uint256 landId = 1;
        
        // 2. Buyer locks the land
        vm.prank(buyer);
        registry.lockLandToBuyer(landId);
        
        // 3. Buyer makes crypto payment
        vm.prank(buyer);
        registry.makePayment(landId, 600e18);
        
        // 4. Buyer submits bank payment proof
        vm.prank(buyer);
        registry.submitBankPayment(landId, 400e18, "QmBankProof123");
        
        // 5. Builder verifies bank payment
        vm.prank(builder);
        registry.verifyBankPayment(landId, true);
        
        assertEq(registry.amountPaid(landId), LAND_PRICE);
        assertEq(registry.cryptoAmountPaid(landId), 600e18);
        assertEq(registry.bankAmountPaid(landId), 400e18);
        
        // 6. Seller approves
        vm.prank(seller);
        registry.sellerApproveTransfer(landId);
        
        // 7. Ownership transferred
        (address owner, , , , , ) = registry.lands(landId);
        assertTrue(registry.isOwned(landId));
        assertEq(owner, buyer);
    }
    
    // ============ E2E TEST: REFUND WORKFLOW ============
    
    function test_E2E_RefundWorkflow() public {
        // 1. Register and lock
        vm.prank(admin);
        registry.registerLand(seller, "QmHash123", keccak256("doc"), LAND_PRICE);
        uint256 landId = 1;
        
        vm.prank(buyer);
        registry.lockLandToBuyer(landId);
        
        // 2. Make partial payments
        vm.prank(buyer);
        registry.makePayment(landId, 300e18);
        
        vm.prank(buyer);
        registry.makePayment(landId, 200e18);
        
        uint256 totalPaid = 500e18;
        uint256 buyerBalanceBefore = token.balanceOf(buyer);
        uint256 adminBalanceBefore = token.balanceOf(admin);
        
        // 3. Request refund
        vm.prank(buyer);
        registry.requestRefund(landId);
        
        // 4. Verify refund
        uint256 penalty = (totalPaid * 1000) / 10000; // 10%
        uint256 refund = totalPaid - penalty;
        
        assertEq(token.balanceOf(buyer), buyerBalanceBefore + refund);
        assertEq(token.balanceOf(admin), adminBalanceBefore + penalty);
        (, , , , , address payable locked) = registry.lands(landId);
        assertEq(registry.amountPaid(landId), 0);
        assertEq(locked, address(0));
    }
    
    // ============ E2E TEST: MULTIPLE LANDS ============
    
    function test_E2E_MultipleLands() public {
        // Register multiple lands
        vm.startPrank(admin);
        registry.registerLand(seller, "QmHash1", keccak256("doc1"), 1000e18);
        registry.registerLand(seller, "QmHash2", keccak256("doc2"), 2000e18);
        registry.registerLand(seller, "QmHash3", keccak256("doc3"), 3000e18);
        vm.stopPrank();
        
        // Buyer locks and pays for first land
        vm.prank(buyer);
        registry.lockLandToBuyer(1);
        vm.prank(buyer);
        registry.makePayment(1, 1000e18);
        
        // Buyer locks second land (different buyer could lock 1st after refund)
        vm.prank(buyer);
        registry.lockLandToBuyer(2);
        
        (, , , , , address payable locked1) = registry.lands(1);
        (, , , , , address payable locked2) = registry.lands(2);
        (, , , , , address payable locked3) = registry.lands(3);
        assertEq(locked1, buyer);
        assertEq(locked2, buyer);
        assertEq(locked3, address(0));
    }
    
    // ============ E2E TEST: ADMIN BYPASS ============
    
    function test_E2E_AdminBypassApproval() public {
        // Register, lock, and pay
        vm.prank(admin);
        registry.registerLand(seller, "QmHash123", keccak256("doc"), LAND_PRICE);
        uint256 landId = 1;
        
        vm.prank(buyer);
        registry.lockLandToBuyer(landId);
        vm.prank(buyer);
        registry.makePayment(landId, LAND_PRICE);
        
        // Admin bypasses seller approval (emergency case)
        vm.prank(admin);
        registry.adminBypassSellerApproval(landId);
        
        // Ownership transferred without seller approval
        (address owner, , , , , ) = registry.lands(landId);
        assertTrue(registry.isOwned(landId));
        assertEq(owner, buyer);
    }
    
    // ============ E2E TEST: BANK PAYMENT REJECTION ============
    
    function test_E2E_BankPaymentRejection() public {
        vm.prank(admin);
        registry.registerLand(seller, "QmHash123", keccak256("doc"), LAND_PRICE);
        uint256 landId = 1;
        
        vm.prank(buyer);
        registry.lockLandToBuyer(landId);
        
        // Submit bank payment
        vm.prank(buyer);
        registry.submitBankPayment(landId, 500e18, "invalid_proof");
        
        // Builder rejects
        vm.prank(builder);
        registry.verifyBankPayment(landId, false);
        
        (bool submitted1, bool verified1, , , , , ) = registry.bankPayments(landId);
        assertFalse(submitted1);
        assertFalse(verified1);
        
        // Buyer can resubmit
        vm.prank(buyer);
        registry.submitBankPayment(landId, 500e18, "valid_proof");
        (bool submitted2, , , , , , ) = registry.bankPayments(landId);
        assertTrue(submitted2);
    }
    
    // ============ E2E TEST: PENALTY CONFIGURATION ============
    
    function test_E2E_PenaltyConfiguration() public {
        // Change penalty to 5%
        vm.prank(admin);
        registry.setPenaltyBasisPoints(500);
        
        // Register, lock, and pay
        vm.prank(admin);
        registry.registerLand(seller, "QmHash123", keccak256("doc"), LAND_PRICE);
        uint256 landId = 1;
        
        vm.prank(buyer);
        registry.lockLandToBuyer(landId);
        vm.prank(buyer);
        registry.makePayment(landId, 500e18);
        
        uint256 buyerBalanceBefore = token.balanceOf(buyer);
        
        // Refund with new penalty rate
        vm.prank(buyer);
        registry.requestRefund(landId);
        
        uint256 penalty = (500e18 * 500) / 10000; // 5%
        uint256 refund = 500e18 - penalty;
        
        assertEq(token.balanceOf(buyer), buyerBalanceBefore + refund);
    }
}

