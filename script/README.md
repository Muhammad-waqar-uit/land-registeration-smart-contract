# Deployment Script Documentation

This directory contains the Foundry deployment script for the Land Registry smart contracts.

## Contract Overview

### LandRegistryUpgradeable
- **Builder Registry**: Register builders with license information on-chain
- **Agreement Hash Storage**: Store signed agreement document hashes
- **Ownership Document Hash Storage**: Store final ownership certificate hashes
- All existing features (UUPS upgradeable, hybrid payments, dual approval, refunds)

### LandPaymentToken
- Standard ERC20 token with minting, batch minting, and burning capabilities
- 18 decimals (standard)
- Owner-controlled minting and burning

## Deployment Script

### Deploy.s.sol
Deploys both the Payment Token and Land Registry in one transaction.

**Environment Variables**:
- `PRIVATE_KEY` (required): Deployer's private key (without 0x prefix)
- `TOKEN_NAME` (optional): Token name (default: "Land Registry Payment Token")
- `TOKEN_SYMBOL` (optional): Token symbol (default: "LRT")
- `INITIAL_SUPPLY` (optional): Initial supply (default: 0)

**Usage**:
```bash
# Local deployment
forge script script/Deploy.s.sol:Deploy \
    --rpc-url http://127.0.0.1:8545 \
    --broadcast \
    -vvvv

# Testnet deployment (e.g., Base Sepolia)
export PRIVATE_KEY=your_private_key_here
export TOKEN_NAME="Test Land Token"
export TOKEN_SYMBOL="TLT"
export INITIAL_SUPPLY=1000000

forge script script/Deploy.s.sol:Deploy \
    --rpc-url $BASE_SEPOLIA_RPC_URL \
    --broadcast \
    --verify \
    --etherscan-api-key $BASESCAN_API_KEY \
    -vvvv
```

## Post-Deployment Steps

### 1. Update Backend Configuration

Add deployed addresses to your backend `.env` file:

```env
PAYMENT_TOKEN_ADDRESS=0x...
LAND_REGISTRY_ADDRESS=0x...
```

### 2. Register Builders (Optional)

If you need to register builders:

```solidity
// Grant builder role
registry.grantBuilderRole(builderAddress);

// Register builder with license
registry.registerBuilder(builderAddress, "LICENSE-123");
```

### 3. User Token Approval

Users need to approve the Land Registry to spend their tokens before making payments:

```solidity
token.approve(landRegistryAddress, amount);
```

Or use the backend to handle approvals on behalf of users.

### 4. Mint Tokens to Users

As the token owner, you can mint tokens to users:

```solidity
// Single mint
token.mint(userAddress, amount);

// Batch mint
address[] memory recipients = [user1, user2, user3];
uint256[] memory amounts = [1000e18, 2000e18, 3000e18];
token.mintBatch(recipients, amounts);
```

## Network-Specific Examples

### Base Sepolia Testnet

```bash
export PRIVATE_KEY=your_private_key
export BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
export BASESCAN_API_KEY=your_basescan_api_key

# Deploy both contracts
forge script script/DeployBothSimple.s.sol:DeployBothSimple \
    --rpc-url $BASE_SEPOLIA_RPC_URL \
    --broadcast \
    --verify \
    --etherscan-api-key $BASESCAN_API_KEY \
    -vvvv
```

### Ethereum Sepolia Testnet

```bash
export PRIVATE_KEY=your_private_key
export SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_INFURA_KEY
export ETHERSCAN_API_KEY=your_etherscan_api_key

forge script script/DeployBothSimple.s.sol:DeployBothSimple \
    --rpc-url $SEPOLIA_RPC_URL \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    -vvvv
```

### Polygon Mumbai Testnet

```bash
export PRIVATE_KEY=your_private_key
export MUMBAI_RPC_URL=https://rpc-mumbai.maticvigil.com
export POLYGONSCAN_API_KEY=your_polygonscan_api_key

forge script script/DeployBothSimple.s.sol:DeployBothSimple \
    --rpc-url $MUMBAI_RPC_URL \
    --broadcast \
    --verify \
    --etherscan-api-key $POLYGONSCAN_API_KEY \
    -vvvv
```

## What Gets Deployed

The deployment script deploys:

1. **LandPaymentToken**: The payment token contract
2. **LandRegistryUpgradeable Implementation**: The upgradeable implementation contract
3. **ERC1967Proxy**: The proxy contract that points to the implementation

**Important**: Always use the proxy address (`registryProxyAddress`) for interactions. The implementation address is only needed for upgrades.

## Troubleshooting

### "Invalid token" error
Ensure `PAYMENT_TOKEN_ADDRESS` is set correctly and is a valid ERC20 token.

### "Payment token mismatch" error
The Land Registry was not initialized with the correct token address. Redeploy.

### Verification fails
- Ensure you have the correct API key for the block explorer
- Check that the RPC URL matches the network you're deploying to
- Add `--verify` flag to enable verification
- Some networks may require additional time before verification succeeds

### Out of gas errors
Increase gas limit in your wallet or adjust gas price.

## New Features Usage

### Store Agreement Hash

After buyer and seller sign the agreement:

```solidity
registry.storeAgreementHash(
    landId,
    agreementHashBytes32,
    "QmIPFSHashOfAgreement"
);
```

### Store Ownership Document Hash

After ownership transfer:

```solidity
registry.storeOwnershipDocumentHash(
    landId,
    documentHashBytes32,
    "QmIPFSHashOfOwnershipDoc"
);
```

### Query Agreement/Ownership Hashes

```solidity
// Get agreement hash
(bytes32 hash, string memory ipfs, uint256 time, bool exists) 
    = registry.getAgreementHash(landId);

// Get ownership document hash
(bytes32 hash, string memory ipfs, uint256 time, bool exists) 
    = registry.getOwnershipDocumentHash(landId);
```

### Builder Information

```solidity
// Get builder info
(address addr, string memory license, bool registered, uint256 time) 
    = registry.getBuilderInfo(builderAddress);

// Check if license is registered
(bool registered, address builderAddr) 
    = registry.isLicenseRegistered("LICENSE-123");
```

## Security Notes

- **Private Keys**: Never commit private keys to version control
- **Environment Variables**: Use `.env` files (add to `.gitignore`)
- **Testnet First**: Always test on testnets before mainnet
- **Verify Contracts**: Always verify contracts on block explorers
- **Access Control**: Only the deployer gets admin/owner roles initially

## Support

For issues or questions:
1. Check contract documentation in `src/` directory
2. Review test files in `test/` directory
3. Check the main project README.md
