// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {LandRegistryUpgradeable} from "../src/LandRegistryUpgradeable.sol";
import {LandPaymentToken} from "../src/LandPaymentToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployBoth
 * @notice Deploys both Payment Token and Land Registry in one script
 * @dev Useful when deploying both contracts together
 * 
 * @dev ENVIRONMENT VARIABLES:
 *      - PRIVATE_KEY: Deployer's private key (without 0x prefix) - REQUIRED
 *      - TOKEN_NAME: Token name (default: "Land Payment Token")
 *      - TOKEN_SYMBOL: Token symbol (default: "LPT")
 *      - INITIAL_SUPPLY: Initial supply (default: 0)
 * 
 * @dev USAGE:
 *      forge script script/DeployBoth.s.sol:DeployBoth \
 *          --rpc-url $RPC_URL \
 *          --broadcast \
 *          --verify \
 *          --etherscan-api-key $ETHERSCAN_API_KEY \
 *          -vvvv
 */
contract DeployBoth is Script {
    function run() external returns (
        address tokenAddress,
        address registryProxyAddress,
        address registryImplementationAddress
    ) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address ownerAddress = vm.addr(deployerPrivateKey);
        
        string memory tokenName = vm.envOr("TOKEN_NAME", string("Land Payment Token"));
        string memory tokenSymbol = vm.envOr("TOKEN_SYMBOL", string("LPT"));
        uint256 initialSupply = vm.envOr("INITIAL_SUPPLY", uint256(0));
        
        console.log("\n==========================================");
        console.log("Deploying Payment Token & Land Registry");
        console.log("==========================================");
        console.log("Deployer Address:", ownerAddress);
        console.log("Token Name:", tokenName);
        console.log("Token Symbol:", tokenSymbol);
        console.log("Initial Supply:", initialSupply);
        console.log("Network:", block.chainid);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // ============ DEPLOY PAYMENT TOKEN ============
        console.log("Step 1: Deploying Payment Token...");
        LandPaymentToken token = new LandPaymentToken(
            tokenName,
            tokenSymbol,
            initialSupply
        );
        tokenAddress = address(token);
        console.log("Payment Token deployed at:", tokenAddress);
        
        // ============ DEPLOY LAND REGISTRY ============
        console.log("\nStep 2: Deploying Land Registry...");
        LandRegistryUpgradeable implementation = new LandRegistryUpgradeable();
        registryImplementationAddress = address(implementation);
        console.log("Implementation deployed at:", registryImplementationAddress);
        
        bytes memory initData = abi.encodeWithSelector(
            LandRegistryUpgradeable.initialize.selector,
            tokenAddress
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        registryProxyAddress = address(proxy);
        console.log("Proxy deployed at:", registryProxyAddress);
        
        // ============ WHITELIST LAND REGISTRY IN TOKEN ============
        console.log("\nStep 3: Whitelisting Land Registry in Payment Token...");
        token.setWhitelistedSpender(registryProxyAddress, true);
        console.log("Land Registry whitelisted!");
        
        // ============ VERIFY ============
        LandRegistryUpgradeable registry = LandRegistryUpgradeable(payable(registryProxyAddress));
        
        console.log("\n=== Verification ===");
        console.log("Payment Token:", address(registry.paymentToken()));
        console.log("Is Registry Whitelisted:", token.isWhitelistedSpender(registryProxyAddress));
        console.log("Registry Owner:", registry.owner());
        console.log("Penalty Basis Points:", registry.penaltyBasisPoints());
        
        require(
            address(registry.paymentToken()) == tokenAddress,
            "Payment token mismatch"
        );
        require(
            token.isWhitelistedSpender(registryProxyAddress),
            "Failed to whitelist Land Registry"
        );
        
        vm.stopBroadcast();
        
        // ============ SUMMARY ============
        console.log("\n==========================================");
        console.log("DEPLOYMENT COMPLETE");
        console.log("==========================================");
        console.log("Payment Token Address:", tokenAddress);
        console.log("Land Registry Proxy (USE THIS):", registryProxyAddress);
        console.log("Land Registry Implementation:", registryImplementationAddress);
        console.log("Owner Address:", ownerAddress);
        console.log("Chain ID:", block.chainid);
        console.log("\n=== SAVE THESE VALUES ===");
        console.log("PAYMENT_TOKEN_ADDRESS=", tokenAddress);
        console.log("LAND_REGISTRY_PROXY_ADDRESS=", registryProxyAddress);
        console.log("LAND_REGISTRY_IMPLEMENTATION_ADDRESS=", registryImplementationAddress);
        console.log("OWNER_ADDRESS=", ownerAddress);
        console.log("CHAIN_ID=", block.chainid);
        console.log("==========================================\n");
    }
}

