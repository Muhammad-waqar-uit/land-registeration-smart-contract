// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {LandRegistryUpgradeable} from "../src/LandRegistryUpgradeable.sol";
import {LandPaymentToken} from "../src/LandPaymentToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title Deploy
 * @notice Deploys both Payment Token and Land Registry contracts in one script
 * @dev Deploys the complete Land Registry system
 * 
 * @dev ENVIRONMENT VARIABLES:
 *      - PRIVATE_KEY: Deployer's private key (without 0x prefix) - REQUIRED
 *      - TOKEN_NAME: Token name (default: "Land Registry Payment Token")
 *      - TOKEN_SYMBOL: Token symbol (default: "LRT")
 *      - INITIAL_SUPPLY: Initial supply (default: 0)
 * 
 * @dev USAGE:
 *      forge script script/Deploy.s.sol:Deploy \
 *          --rpc-url $RPC_URL \
 *          --broadcast \
 *          --verify \
 *          --etherscan-api-key $ETHERSCAN_API_KEY \
 *          -vvvv
 * 
 * @dev EXAMPLE (Local):
 *      forge script script/Deploy.s.sol:Deploy \
 *          --rpc-url http://127.0.0.1:8545 \
 *          --broadcast \
 *          -vvvv
 * 
 * @dev EXAMPLE (Testnet - Base Sepolia):
 *      forge script script/Deploy.s.sol:Deploy \
 *          --rpc-url $BASE_SEPOLIA_RPC_URL \
 *          --broadcast \
 *          --verify \
 *          --etherscan-api-key $BASESCAN_API_KEY \
 *          -vvvv
 */
contract Deploy is Script {
    function run() external returns (
        address tokenAddress,
        address registryProxyAddress,
        address registryImplementationAddress
    ) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address ownerAddress = vm.addr(deployerPrivateKey);
        
        string memory tokenName = vm.envOr("TOKEN_NAME", string("Land Registry Payment Token"));
        string memory tokenSymbol = vm.envOr("TOKEN_SYMBOL", string("LRT"));
        uint256 initialSupply = vm.envOr("INITIAL_SUPPLY", uint256(0));
        
        console.log("\n==========================================");
        console.log("Deploying Payment Token & Land Registry");
        console.log("==========================================");
        console.log("Deployer Address:", ownerAddress);
        console.log("Token Name:", tokenName);
        console.log("Token Symbol:", tokenSymbol);
        console.log("Initial Supply:", initialSupply);
        console.log("Network Chain ID:", block.chainid);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // ============ STEP 1: DEPLOY PAYMENT TOKEN ============
        console.log("Step 1: Deploying Payment Token...");
        LandPaymentToken token = new LandPaymentToken(
            tokenName,
            tokenSymbol,
            initialSupply
        );
        tokenAddress = address(token);
        console.log("  Payment Token deployed at:", tokenAddress);
        console.log("");
        
        // ============ STEP 2: DEPLOY LAND REGISTRY IMPLEMENTATION ============
        console.log("Step 2: Deploying Land Registry Implementation...");
        LandRegistryUpgradeable implementation = new LandRegistryUpgradeable();
        registryImplementationAddress = address(implementation);
        console.log("  Implementation deployed at:", registryImplementationAddress);
        console.log("");
        
        // ============ STEP 3: DEPLOY PROXY AND INITIALIZE ============
        console.log("Step 3: Deploying Proxy and Initializing...");
        bytes memory initData = abi.encodeWithSelector(
            LandRegistryUpgradeable.initialize.selector,
            tokenAddress
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        registryProxyAddress = address(proxy);
        console.log("  Proxy deployed at:", registryProxyAddress);
        console.log("");
        
        vm.stopBroadcast();
        
        // ============ VERIFICATION ============
        console.log("==========================================");
        console.log("Deployment Verification");
        console.log("==========================================");
        
        LandRegistryUpgradeable registry = LandRegistryUpgradeable(payable(registryProxyAddress));
        
        console.log("Token Address:", tokenAddress);
        console.log("Registry Proxy:", registryProxyAddress);
        console.log("Registry Implementation:", registryImplementationAddress);
        console.log("");
        console.log("Registry Configuration:");
        console.log("  Payment Token:", address(registry.paymentToken()));
        console.log("  Owner:", registry.owner());
        console.log("  Penalty Basis Points:", registry.penaltyBasisPoints());
        console.log("  Next Land ID:", registry.nextLandId());
        console.log("");
        console.log("Token Configuration:");
        console.log("  Name:", token.name());
        console.log("  Symbol:", token.symbol());
        console.log("  Decimals:", token.decimals());
        console.log("  Total Supply:", token.totalSupply());
        console.log("  Owner Balance:", token.balanceOf(ownerAddress));
        console.log("");
        
        // Verify integration
        require(
            address(registry.paymentToken()) == tokenAddress,
            "Payment token mismatch"
        );
        require(
            registry.owner() == ownerAddress,
            "Owner mismatch"
        );
        require(
            registry.nextLandId() == 1,
            "Next land ID should be 1"
        );
        
        console.log("==========================================");
        console.log("Deployment Successful!");
        console.log("==========================================");
        console.log("");
        console.log("NEXT STEPS:");
        console.log("1. Add these addresses to your backend .env file:");
        console.log("   PAYMENT_TOKEN_ADDRESS=", tokenAddress);
        console.log("   LAND_REGISTRY_ADDRESS=", registryProxyAddress);
        console.log("");
        console.log("2. Users need to approve the Land Registry to spend tokens:");
        console.log("   token.approve(landRegistryAddress, amount)");
        console.log("");
        console.log("3. Register builders (if needed):");
        console.log("   registry.grantBuilderRole(builderAddress)");
        console.log("   registry.registerBuilder(builderAddress, licenseNumber)");
        console.log("");
        console.log("4. Start registering land parcels!");
        console.log("==========================================");
        
        return (tokenAddress, registryProxyAddress, registryImplementationAddress);
    }
}
