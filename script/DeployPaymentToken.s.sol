// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {LandPaymentToken} from "../src/LandPaymentToken.sol";

/**
 * @title DeployPaymentToken
 * @notice Deployment script for LandPaymentToken contract
 * @dev Deploys the payment token with configurable name, symbol, and initial supply
 * 
 * @dev ENVIRONMENT VARIABLES REQUIRED:
 *      - PRIVATE_KEY: Deployer's private key (without 0x prefix)
 *      - TOKEN_NAME: Token name (e.g., "Land Payment Token")
 *      - TOKEN_SYMBOL: Token symbol (e.g., "LPT")
 *      - INITIAL_SUPPLY: Initial supply to mint to deployer (optional, default: 0)
 *      - LAND_REGISTRY_ADDRESS: Land Registry contract address to whitelist (optional)
 * 
 * @dev USAGE:
 *      forge script script/DeployPaymentToken.s.sol:DeployPaymentToken \
 *          --rpc-url $RPC_URL \
 *          --broadcast \
 *          --verify \
 *          --etherscan-api-key $ETHERSCAN_API_KEY \
 *          -vvvv
 */
contract DeployPaymentToken is Script {
    function run() external returns (
        address tokenAddress,
        address ownerAddress
    ) {
        // ============ READ ENVIRONMENT VARIABLES ============
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory tokenName = vm.envOr("TOKEN_NAME", string("Land Payment Token"));
        string memory tokenSymbol = vm.envOr("TOKEN_SYMBOL", string("LPT"));
        uint256 initialSupply = vm.envOr("INITIAL_SUPPLY", uint256(0));
        address landRegistryAddress = vm.envOr("LAND_REGISTRY_ADDRESS", address(0));
        
        ownerAddress = vm.addr(deployerPrivateKey);
        
        console.log("\n==========================================");
        console.log("Land Payment Token Deployment");
        console.log("==========================================");
        console.log("Deployer Address:", ownerAddress);
        console.log("Token Name:", tokenName);
        console.log("Token Symbol:", tokenSymbol);
        console.log("Initial Supply:", initialSupply);
        console.log("Network:", block.chainid);
        console.log("");
        
        // ============ VALIDATION ============
        require(deployerPrivateKey != 0, "PRIVATE_KEY cannot be zero");
        require(bytes(tokenName).length > 0, "TOKEN_NAME cannot be empty");
        require(bytes(tokenSymbol).length > 0, "TOKEN_SYMBOL cannot be empty");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // ============ DEPLOY TOKEN ============
        console.log("Deploying payment token contract...");
        LandPaymentToken token = new LandPaymentToken(
            tokenName,
            tokenSymbol,
            initialSupply
        );
        tokenAddress = address(token);
        console.log("Token deployed at:", tokenAddress);
        
        // ============ WHITELIST LAND REGISTRY (if provided) ============
        if (landRegistryAddress != address(0)) {
            console.log("Whitelisting Land Registry contract...");
            token.setWhitelistedSpender(landRegistryAddress, true);
            console.log("Land Registry whitelisted:", landRegistryAddress);
            
            // Verify whitelisting
            require(
                token.isWhitelistedSpender(landRegistryAddress),
                "Failed to whitelist Land Registry"
            );
        } else {
            console.log("Note: LAND_REGISTRY_ADDRESS not set, skipping whitelist");
            console.log("You can whitelist it later using:");
            console.log("  token.setWhitelistedSpender(registryAddress, true)");
        }
        
        // ============ VERIFY DEPLOYMENT ============
        console.log("\n=== Verification ===");
        console.log("Token Name:", token.name());
        console.log("Token Symbol:", token.symbol());
        console.log("Token Decimals:", token.decimals());
        console.log("Total Supply:", token.totalSupply());
        console.log("Owner:", token.owner());
        
        require(token.owner() == ownerAddress, "Owner mismatch");
        if (initialSupply > 0) {
            require(token.balanceOf(ownerAddress) == initialSupply, "Initial supply mismatch");
        }
        
        vm.stopBroadcast();
        
        // ============ DEPLOYMENT SUMMARY ============
        console.log("\n==========================================");
        console.log("DEPLOYMENT COMPLETE");
        console.log("==========================================");
        console.log("Token Address (USE THIS):", tokenAddress);
        console.log("Owner Address:", ownerAddress);
        console.log("Token Name:", tokenName);
        console.log("Token Symbol:", tokenSymbol);
        console.log("Chain ID:", block.chainid);
        if (landRegistryAddress != address(0)) {
            console.log("Land Registry (whitelisted):", landRegistryAddress);
        }
        console.log("\n=== SAVE THESE VALUES ===");
        console.log("PAYMENT_TOKEN_ADDRESS=", tokenAddress);
        console.log("TOKEN_OWNER_ADDRESS=", ownerAddress);
        console.log("TOKEN_NAME=", tokenName);
        console.log("TOKEN_SYMBOL=", tokenSymbol);
        console.log("CHAIN_ID=", block.chainid);
        if (landRegistryAddress != address(0)) {
            console.log("LAND_REGISTRY_ADDRESS=", landRegistryAddress);
        }
        console.log("\n=== NEXT STEPS ===");
        console.log("1. Deploy Land Registry contract");
        console.log("2. Whitelist Land Registry in token (if not done):");
        console.log("   token.setWhitelistedSpender(registryAddress, true)");
        console.log("3. Use PAYMENT_TOKEN_ADDRESS when deploying Land Registry");
        console.log("==========================================\n");
    }
}

