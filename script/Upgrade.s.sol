// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {LandRegistryUpgradeable} from "../src/LandRegistryUpgradeable.sol";

/**
 * @title Upgrade
 * @notice Upgrades the Land Registry contract to a new implementation
 * @dev Uses UUPS (Universal Upgradeable Proxy Standard) upgrade pattern
 * 
 * @dev ENVIRONMENT VARIABLES:
 *      - PRIVATE_KEY: Deployer's private key (without 0x prefix) - REQUIRED
 *      - PROXY_ADDRESS: Address of the existing proxy contract - REQUIRED
 * 
 * @dev USAGE:
 *      forge script script/Upgrade.s.sol:Upgrade \
 *          --rpc-url $RPC_URL \
 *          --broadcast \
 *          --verify \
 *          --etherscan-api-key $ETHERSCAN_API_KEY \
 *          -vvvv
 * 
 * @dev EXAMPLE (Local):
 *      forge script script/Upgrade.s.sol:Upgrade \
 *          --rpc-url http://127.0.0.1:8545 \
 *          --broadcast \
 *          -vvvv
 * 
 * @dev EXAMPLE (Testnet - Base Sepolia):
 *      PROXY_ADDRESS=0x... forge script script/Upgrade.s.sol:Upgrade \
 *          --rpc-url $BASE_SEPOLIA_RPC_URL \
 *          --broadcast \
 *          --verify \
 *          --etherscan-api-key $BASESCAN_API_KEY \
 *          -vvvv
 * 
 * @dev IMPORTANT NOTES:
 *      - Only the owner can upgrade the contract (enforced by _authorizeUpgrade)
 *      - The proxy address must be the existing deployed proxy
 *      - Storage layout must be compatible with previous version
 *      - No re-initialization is performed (upgrade only, no initialize call)
 */
contract Upgrade is Script {
    function run() external returns (
        address newImplementationAddress,
        address proxyAddress
    ) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address ownerAddress = vm.addr(deployerPrivateKey);
        proxyAddress = vm.envAddress("PROXY_ADDRESS");
        
        console.log("\n==========================================");
        console.log("Upgrading Land Registry Contract");
        console.log("==========================================");
        console.log("Owner Address:", ownerAddress);
        console.log("Proxy Address:", proxyAddress);
        console.log("Network Chain ID:", block.chainid);
        console.log("");
        
        // Get current implementation address
        LandRegistryUpgradeable proxy = LandRegistryUpgradeable(payable(proxyAddress));
        address currentImplementation = _getImplementation(address(proxy));
        console.log("Current Implementation:", currentImplementation);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // ============ STEP 1: DEPLOY NEW IMPLEMENTATION ============
        console.log("Step 1: Deploying New Implementation...");
        LandRegistryUpgradeable newImplementation = new LandRegistryUpgradeable();
        newImplementationAddress = address(newImplementation);
        console.log("  New Implementation deployed at:", newImplementationAddress);
        console.log("");
        
        // ============ STEP 2: UPGRADE PROXY ============
        console.log("Step 2: Upgrading Proxy...");
        console.log("  Calling upgradeToAndCall on proxy...");
        
        // OpenZeppelin v5 UUPS uses upgradeToAndCall with empty bytes for upgrade-only
        // The proxy will delegatecall to the implementation's upgradeToAndCall function
        bytes memory upgradeData = "";
        proxy.upgradeToAndCall(newImplementationAddress, upgradeData);
        
        console.log("  Upgrade transaction sent!");
        console.log("");
        
        vm.stopBroadcast();
        
        // ============ VERIFICATION ============
        console.log("==========================================");
        console.log("Upgrade Verification");
        console.log("==========================================");
        
        // Verify new implementation is set
        address verifiedImplementation = _getImplementation(proxyAddress);
        console.log("Previous Implementation:", currentImplementation);
        console.log("New Implementation:", verifiedImplementation);
        console.log("Proxy Address:", proxyAddress);
        console.log("");
        
        // Verify the proxy still works correctly
        console.log("Proxy Configuration (after upgrade):");
        console.log("  Payment Token:", address(proxy.paymentToken()));
        console.log("  Owner:", proxy.owner());
        console.log("  Penalty Basis Points:", proxy.penaltyBasisPoints());
        console.log("  Next Land ID:", proxy.nextLandId());
        console.log("");
        
        // Verify upgrade was successful
        require(
            verifiedImplementation == newImplementationAddress,
            "Upgrade failed: implementation address mismatch"
        );
        if (currentImplementation != address(0)) {
            require(
                verifiedImplementation != currentImplementation,
                "Upgrade failed: implementation address unchanged"
            );
        }
        require(
            proxy.owner() == ownerAddress,
            "Upgrade failed: owner changed"
        );
        
        console.log("==========================================");
        console.log("Upgrade Successful!");
        console.log("==========================================");
        console.log("");
        console.log("NEXT STEPS:");
        console.log("1. Verify the new implementation contract on block explorer");
        console.log("2. Test key functions to ensure upgrade was successful");
        console.log("3. Monitor for any issues with existing functionality");
        console.log("");
        console.log("Implementation Address:", newImplementationAddress);
        console.log("Proxy Address:", proxyAddress);
        console.log("==========================================");
        
        return (newImplementationAddress, proxyAddress);
    }
    
    /**
     * @notice Gets the current implementation address from a proxy
     * @dev Uses ERC-1967 storage slot to read implementation address
     * @param proxy The proxy contract address
     * @return implementation The implementation contract address
     */
    function _getImplementation(address proxy) internal view returns (address implementation) {
        // ERC-1967 implementation storage slot
        // keccak256("eip1967.proxy.implementation") - 1
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 value = vm.load(proxy, slot);
        implementation = address(uint160(uint256(value)));
    }
}
