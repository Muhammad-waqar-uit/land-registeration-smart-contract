// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {LandRegistryUpgradeable} from "../src/LandRegistryUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployOrUpgrade is Script {
    function run() external returns (address proxyAddress, address implementationAddress) {
        // Read environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address paymentTokenAddress = vm.envAddress("PAYMENT_TOKEN_ADDRESS");
        
        // Check if we should upgrade or deploy
        bool shouldUpgrade = vm.envOr("UPGRADE", false);
        address existingProxyAddress = vm.envOr("PROXY_ADDRESS", address(0));
        
        vm.startBroadcast(deployerPrivateKey);
        
        if (shouldUpgrade && existingProxyAddress != address(0)) {
            // UPGRADE PATH
            console.log("=== UPGRADE MODE ===");
            console.log("Proxy Address:", existingProxyAddress);
            console.log("Deployer:", vm.addr(deployerPrivateKey));
            
            LandRegistryUpgradeable proxy = LandRegistryUpgradeable(payable(existingProxyAddress));
            
            // Verify ownership
            address proxyOwner = proxy.owner();
            require(proxyOwner == vm.addr(deployerPrivateKey), "Not the owner of the proxy");
            console.log("Proxy owner verified:", proxyOwner);
            
            // Deploy new implementation
            LandRegistryUpgradeable newImplementation = new LandRegistryUpgradeable();
            console.log("New implementation deployed at:", address(newImplementation));
            implementationAddress = address(newImplementation);
            
            // Perform upgrade (OpenZeppelin v5 uses upgradeToAndCall with empty data)
            proxy.upgradeToAndCall(address(newImplementation), "");
            console.log("Upgrade successful!");
            
            proxyAddress = existingProxyAddress;
            
            console.log("\n=== Upgrade Complete ===");
            console.log("Proxy Address (unchanged):", proxyAddress);
            console.log("New Implementation Address:", implementationAddress);
            
        } else {
            // DEPLOY PATH
            console.log("=== DEPLOY MODE ===");
            console.log("Payment Token Address:", paymentTokenAddress);
            console.log("Deployer:", vm.addr(deployerPrivateKey));
            
            // Deploy implementation
            LandRegistryUpgradeable implementation = new LandRegistryUpgradeable();
            console.log("Implementation deployed at:", address(implementation));
            implementationAddress = address(implementation);
            
            // Prepare initialization data
            bytes memory initData = abi.encodeWithSelector(
                LandRegistryUpgradeable.initialize.selector,
                paymentTokenAddress
            );
            
            // Deploy proxy
            ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
            console.log("Proxy deployed at:", address(proxy));
            proxyAddress = address(proxy);
            
            // Verify initialization
            LandRegistryUpgradeable registry = LandRegistryUpgradeable(payable(address(proxy)));
            console.log("Registry paymentToken:", address(registry.paymentToken()));
            console.log("Registry penaltyBasisPoints:", registry.penaltyBasisPoints());
            console.log("Registry owner:", registry.owner());
            
            console.log("\n=== Deployment Complete ===");
            console.log("Proxy Address (use this):", proxyAddress);
            console.log("Implementation Address:", implementationAddress);
            console.log("\nTo upgrade later, set these env vars:");
            console.log("  export UPGRADE=true");
            console.log("  export PROXY_ADDRESS=", proxyAddress);
        }
        
        vm.stopBroadcast();
    }
}

