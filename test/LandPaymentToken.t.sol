// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {LandPaymentToken} from "../src/LandPaymentToken.sol";

contract LandPaymentTokenTest is Test {
    LandPaymentToken public token;
    
    address public owner = address(0x1);
    address public user = address(0x2);
    address public landRegistry = address(0x3);
    address public randomSpender = address(0x4);
    
    uint256 public constant INITIAL_SUPPLY = 1000000e18;
    uint256 public constant MINT_AMOUNT = 1000e18;
    
    function setUp() public {
        vm.prank(owner);
        token = new LandPaymentToken("Land Payment Token", "LPT", INITIAL_SUPPLY);
        
        // Whitelist Land Registry
        vm.prank(owner);
        token.setWhitelistedSpender(landRegistry, true);
    }
    
    // ============ TEST: DEPLOYMENT ============
    
    function test_Deployment() public {
        assertEq(token.name(), "Land Payment Token");
        assertEq(token.symbol(), "LPT");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY);
        assertEq(token.owner(), owner);
    }
    
    // ============ TEST: MINTING ============
    
    function test_Mint() public {
        vm.prank(owner);
        token.mint(user, MINT_AMOUNT);
        
        assertEq(token.balanceOf(user), MINT_AMOUNT);
        assertEq(token.totalSupply(), INITIAL_SUPPLY + MINT_AMOUNT);
    }
    
    function test_Mint_OnlyOwner() public {
        vm.prank(user);
        vm.expectRevert();
        token.mint(user, MINT_AMOUNT);
    }
    
    function test_Mint_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("Cannot mint to zero address");
        token.mint(address(0), MINT_AMOUNT);
    }
    
    // ============ TEST: MINT AND APPROVE ============
    
    function test_MintAndApprove() public {
        vm.prank(owner);
        token.mintAndApprove(user, MINT_AMOUNT, landRegistry);
        
        assertEq(token.balanceOf(user), MINT_AMOUNT);
        assertEq(token.allowance(user, landRegistry), MINT_AMOUNT);
    }
    
    function test_MintAndApprove_NotWhitelisted() public {
        vm.prank(owner);
        vm.expectRevert("Spender must be whitelisted");
        token.mintAndApprove(user, MINT_AMOUNT, randomSpender);
    }
    
    // ============ TEST: WHITELIST ============
    
    function test_SetWhitelistedSpender() public {
        vm.prank(owner);
        token.setWhitelistedSpender(randomSpender, true);
        
        assertTrue(token.isWhitelistedSpender(randomSpender));
    }
    
    function test_SetWhitelistedSpender_Remove() public {
        vm.prank(owner);
        token.setWhitelistedSpender(landRegistry, false);
        
        assertFalse(token.isWhitelistedSpender(landRegistry));
    }
    
    function test_SetWhitelistedSpender_OnlyOwner() public {
        vm.prank(user);
        vm.expectRevert();
        token.setWhitelistedSpender(randomSpender, true);
    }
    
    // ============ TEST: AUTO-APPROVAL TRANSFER ============
    
    function test_TransferFrom_WhitelistedSpender_WithoutApproval() public {
        // Mint tokens to user
        vm.prank(owner);
        token.mint(user, MINT_AMOUNT);
        
        // Land Registry (whitelisted) can transfer without approval
        vm.prank(landRegistry);
        token.transferFrom(user, landRegistry, MINT_AMOUNT);
        
        assertEq(token.balanceOf(user), 0);
        assertEq(token.balanceOf(landRegistry), MINT_AMOUNT);
        // Allowance should still be 0 (no approval needed)
        assertEq(token.allowance(user, landRegistry), 0);
    }
    
    function test_TransferFrom_WhitelistedSpender_InsufficientBalance() public {
        vm.prank(owner);
        token.mint(user, MINT_AMOUNT);
        
        vm.prank(landRegistry);
        vm.expectRevert("ERC20: insufficient balance");
        token.transferFrom(user, landRegistry, MINT_AMOUNT + 1);
    }
    
    function test_TransferFrom_NonWhitelisted_RequiresApproval() public {
        vm.prank(owner);
        token.mint(user, MINT_AMOUNT);
        
        // Random spender needs approval
        vm.prank(randomSpender);
        vm.expectRevert();
        token.transferFrom(user, randomSpender, MINT_AMOUNT);
        
        // After approval, it works
        vm.prank(user);
        token.approve(randomSpender, MINT_AMOUNT);
        
        vm.prank(randomSpender);
        token.transferFrom(user, randomSpender, MINT_AMOUNT);
        
        assertEq(token.balanceOf(user), 0);
        assertEq(token.balanceOf(randomSpender), MINT_AMOUNT);
    }
    
    // ============ TEST: STANDARD ERC20 ============
    
    function test_Transfer() public {
        vm.prank(owner);
        token.transfer(user, MINT_AMOUNT);
        
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - MINT_AMOUNT);
        assertEq(token.balanceOf(user), MINT_AMOUNT);
    }
    
    function test_Approve() public {
        vm.prank(user);
        token.approve(landRegistry, MINT_AMOUNT);
        
        assertEq(token.allowance(user, landRegistry), MINT_AMOUNT);
    }
    
    // ============ TEST: E2E PAYMENT FLOW ============
    
    function test_E2E_PaymentFlow_WithAutoApproval() public {
        // 1. Admin mints tokens to user with auto-approval
        vm.prank(owner);
        token.mintAndApprove(user, MINT_AMOUNT, landRegistry);
        
        assertEq(token.balanceOf(user), MINT_AMOUNT);
        assertEq(token.allowance(user, landRegistry), MINT_AMOUNT);
        
        // 2. Land Registry can immediately deduct payment
        uint256 paymentAmount = 500e18;
        vm.prank(landRegistry);
        token.transferFrom(user, landRegistry, paymentAmount);
        
        assertEq(token.balanceOf(user), MINT_AMOUNT - paymentAmount);
        assertEq(token.balanceOf(landRegistry), paymentAmount);
    }
    
    function test_E2E_PaymentFlow_Whitelisted_NoApprovalNeeded() public {
        // 1. Admin mints tokens to user (no approval)
        vm.prank(owner);
        token.mint(user, MINT_AMOUNT);
        
        assertEq(token.balanceOf(user), MINT_AMOUNT);
        assertEq(token.allowance(user, landRegistry), 0); // No approval
        
        // 2. Land Registry can still deduct (whitelisted)
        uint256 paymentAmount = 500e18;
        vm.prank(landRegistry);
        token.transferFrom(user, landRegistry, paymentAmount);
        
        assertEq(token.balanceOf(user), MINT_AMOUNT - paymentAmount);
        assertEq(token.balanceOf(landRegistry), paymentAmount);
    }
}

