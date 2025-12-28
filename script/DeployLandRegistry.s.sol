// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {LandRegistryUpgradeable} from "../src/LandRegistryUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployLandRegistry
 * @notice Deployment script for LandRegistryUpgradeable contract
 * @dev Deploys implementation and proxy, initializes the contract
 * 
 * @dev ENVIRONMENT VARIABLES:
 *      - PRIVATE_KEY: Deployer's private key (without 0x prefix) - REQUIRED
 *      - PAYMENT_TOKEN_ADDRESS: Address of ERC-20 payment token - OPTIONAL (can pass as param)
 * 
 * @dev USAGE:
 *      # Option 1: Pass token address via env var
 *      export PAYMENT_TOKEN_ADDRESS=0x...
 *      forge script script/DeployLandRegistry.s.sol:DeployLandRegistry --rpc-url $RPC_URL --broadcast -vvvv
 * 
 *      # Option 2: Pass token address as parameter (using cast)
 *      forge script script/DeployLandRegistry.s.sol:DeployLandRegistry \
 *          --sig "run(address)" 0x... \
 *          --rpc-url $RPC_URL --broadcast -vvvv
 * 
 *      # Option 3: Use vm.envOr for optional env var
 *      forge script script/DeployLandRegistry.s.sol:DeployLandRegistry --rpc-url $RPC_URL --broadcast -vvvv
 */
contract DeployLandRegistry is Script {
    function run() external returns (
        address proxyAddress,
        address implementationAddress,
        address ownerAddress
    ) {
        return run(vm.envOr("PAYMENT_TOKEN_ADDRESS", address(0)));
    }
    
    function run(address paymentTokenAddress) public returns (
        address proxyAddress,
        address implementationAddress,
        address ownerAddress
    ) {
        // ============ READ ENVIRONMENT VARIABLES ============
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        ownerAddress = vm.addr(deployerPrivateKey);
        
        console.log("\n==========================================");
        console.log("Land Registry Deployment");
        console.log("==========================================");
        console.log("Deployer Address:", ownerAddress);
        console.log("Payment Token:", paymentTokenAddress);
        console.log("Network:", block.chainid);
        console.log("");
        
        // ============ VALIDATION ============
        require(paymentTokenAddress != address(0), "PAYMENT_TOKEN_ADDRESS is required. Set it via env var or pass as parameter");
        require(deployerPrivateKey != 0, "PRIVATE_KEY cannot be zero");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // ============ DEPLOY IMPLEMENTATION ============
        console.log("Deploying implementation contract...");
        LandRegistryUpgradeable implementation = new LandRegistryUpgradeable();
        implementationAddress = address(implementation);
        console.log("Implementation deployed at:", implementationAddress);
        
        // ============ PREPARE INITIALIZATION DATA ============
        bytes memory initData = abi.encodeWithSelector(
            LandRegistryUpgradeable.initialize.selector,
            paymentTokenAddress
        );
        
        // ============ DEPLOY PROXY ============
        console.log("Deploying proxy contract...");
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        proxyAddress = address(proxy);
        console.log("Proxy deployed at:", proxyAddress);
        
        // ============ VERIFY INITIALIZATION ============
        LandRegistryUpgradeable registry = LandRegistryUpgradeable(payable(proxyAddress));
        
        console.log("\n=== Verification ===");
        console.log("Payment Token:", address(registry.paymentToken()));
        console.log("Penalty Basis Points:", registry.penaltyBasisPoints());
        console.log("Owner:", registry.owner());
        console.log("Next Land ID:", registry.nextLandId());
        
        require(
            address(registry.paymentToken()) == paymentTokenAddress,
            "Payment token mismatch"
        );
        require(registry.owner() == ownerAddress, "Owner mismatch");
        require(registry.penaltyBasisPoints() == 1000, "Default penalty should be 10%");
        
        vm.stopBroadcast();
        
        // ============ DEPLOYMENT SUMMARY ============
        console.log("\n==========================================");
        console.log("DEPLOYMENT COMPLETE");
        console.log("==========================================");
        console.log("Proxy Address (USE THIS):", proxyAddress);
        console.log("Implementation Address:", implementationAddress);
        console.log("Owner Address:", ownerAddress);
        console.log("Payment Token:", paymentTokenAddress);
        console.log("Chain ID:", block.chainid);
        console.log("\n=== SAVE THESE VALUES ===");
        console.log("PROXY_ADDRESS=", proxyAddress);
        console.log("IMPLEMENTATION_ADDRESS=", implementationAddress);
        console.log("OWNER_ADDRESS=", ownerAddress);
        console.log("PAYMENT_TOKEN_ADDRESS=", paymentTokenAddress);
        console.log("CHAIN_ID=", block.chainid);
        console.log("==========================================\n");
    }
}
