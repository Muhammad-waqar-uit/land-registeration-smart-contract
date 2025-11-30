// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {LandRegistryUpgradeable} from "../src/LandRegistryUpgradeable.sol";

contract UpgradeLandRegistry is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");
        
        console.log("Upgrading LandRegistry...");
        console.log("Proxy Address:", proxyAddress);
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Get current implementation
        LandRegistryUpgradeable proxy = LandRegistryUpgradeable(payable(proxyAddress));
        console.log("Current owner:", proxy.owner());
        
        // Deploy new implementation
        LandRegistryUpgradeable newImplementation = new LandRegistryUpgradeable();
        console.log("New implementation deployed at:", address(newImplementation));
        
        // Upgrade proxy to new implementation (OpenZeppelin v5 uses upgradeToAndCall with empty data)
        proxy.upgradeToAndCall(address(newImplementation), "");
        console.log("Proxy upgraded successfully!");
        
        // Verify upgrade
        // Note: We can't directly read the implementation, but we can verify functionality
        console.log("Registry still owned by:", proxy.owner());
        console.log("Penalty basis points:", proxy.penaltyBasisPoints());
        
        vm.stopBroadcast();
        
        console.log("\n=== Upgrade Complete ===");
        console.log("New Implementation Address:", address(newImplementation));
        console.log("Proxy Address (unchanged):", proxyAddress);
    }
}

