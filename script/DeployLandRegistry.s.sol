// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {LandRegistryUpgradeable} from "../src/LandRegistryUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployLandRegistry is Script {
    function run() external returns (address proxyAddress, address implementationAddress) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address paymentTokenAddress = vm.envAddress("PAYMENT_TOKEN_ADDRESS");
        
        console.log("Deploying LandRegistry...");
        console.log("Payment Token Address:", paymentTokenAddress);
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        
        vm.startBroadcast(deployerPrivateKey);
        
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
        
        vm.stopBroadcast();
        
        console.log("\n=== Deployment Complete ===");
        console.log("Proxy Address (use this):", proxyAddress);
        console.log("Implementation Address:", implementationAddress);
    }
}

