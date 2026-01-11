// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {LandPaymentToken} from "../src/LandPaymentToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

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
    
    // ============ TEST: BATCH MINTING ============
    
    function test_MintBatch() public {
        address[] memory recipients = new address[](3);
        recipients[0] = user;
        recipients[1] = landRegistry;
        recipients[2] = randomSpender;
        
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100e18;
        amounts[1] = 200e18;
        amounts[2] = 300e18;
        
        vm.prank(owner);
        token.mintBatch(recipients, amounts);
        
        assertEq(token.balanceOf(user), 100e18);
        assertEq(token.balanceOf(landRegistry), 200e18);
        assertEq(token.balanceOf(randomSpender), 300e18);
    }
    
    function test_MintBatch_OnlyOwner() public {
        address[] memory recipients = new address[](1);
        recipients[0] = user;
        
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = MINT_AMOUNT;
        
        vm.prank(user);
        vm.expectRevert();
        token.mintBatch(recipients, amounts);
    }
    
    function test_MintBatch_ArrayLengthMismatch() public {
        address[] memory recipients = new address[](2);
        recipients[0] = user;
        recipients[1] = landRegistry;
        
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = MINT_AMOUNT;
        
        vm.prank(owner);
        vm.expectRevert("Arrays length mismatch");
        token.mintBatch(recipients, amounts);
    }
    
    // ============ TEST: BURNING ============
    
    function test_Burn() public {
        uint256 burnAmount = 100e18;
        vm.prank(owner);
        token.burn(burnAmount);
        
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - burnAmount);
        assertEq(token.totalSupply(), INITIAL_SUPPLY - burnAmount);
    }
    
    function test_Burn_OnlyOwner() public {
        vm.prank(user);
        vm.expectRevert();
        token.burn(100e18);
    }
    
    function test_Burn_InsufficientBalance() public {
        vm.prank(owner);
        vm.expectRevert("Insufficient balance");
        token.burn(INITIAL_SUPPLY + 1e18);
    }
    
    // ============ TEST: STANDARD TRANSFER FROM ============
    
    function test_TransferFrom_RequiresApproval() public {
        vm.prank(owner);
        token.mint(user, MINT_AMOUNT);
        
        // Spender needs approval
        vm.prank(landRegistry);
        vm.expectRevert();
        token.transferFrom(user, landRegistry, MINT_AMOUNT);
        
        // After approval, it works
        vm.prank(user);
        token.approve(landRegistry, MINT_AMOUNT);
        
        vm.prank(landRegistry);
        token.transferFrom(user, landRegistry, MINT_AMOUNT);
        
        assertEq(token.balanceOf(user), 0);
        assertEq(token.balanceOf(landRegistry), MINT_AMOUNT);
    }
    
    function test_TransferFrom_InsufficientBalance() public {
        vm.prank(owner);
        token.mint(user, MINT_AMOUNT);
        
        vm.prank(user);
        token.approve(landRegistry, MINT_AMOUNT + 1);
        
        vm.prank(landRegistry);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                user,
                MINT_AMOUNT,
                MINT_AMOUNT + 1
            )
        );
        token.transferFrom(user, landRegistry, MINT_AMOUNT + 1);
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
    
    function test_E2E_PaymentFlow() public {
        // 1. Admin mints tokens to user
        vm.prank(owner);
        token.mint(user, MINT_AMOUNT);
        
        assertEq(token.balanceOf(user), MINT_AMOUNT);
        assertEq(token.allowance(user, landRegistry), 0);
        
        // 2. User approves Land Registry to spend tokens
        vm.prank(user);
        token.approve(landRegistry, MINT_AMOUNT);
        
        assertEq(token.allowance(user, landRegistry), MINT_AMOUNT);
        
        // 3. Land Registry deducts payment
        uint256 paymentAmount = 500e18;
        vm.prank(landRegistry);
        token.transferFrom(user, landRegistry, paymentAmount);
        
        assertEq(token.balanceOf(user), MINT_AMOUNT - paymentAmount);
        assertEq(token.balanceOf(landRegistry), paymentAmount);
        assertEq(token.allowance(user, landRegistry), MINT_AMOUNT - paymentAmount);
    }
}

