# Land Registry Smart Contract

A comprehensive, upgradeable smart contract for managing land registration, ownership transfers, and payments on the blockchain.

## Features

- **Land Registration**: Admin can register land parcels with IPFS hash, document hash, and pricing
- **Exclusive Land Locking**: Buyers can lock land parcels to prevent race conditions
- **Flexible Payment System**: Support for installments via ERC-20 tokens
- **Hybrid Payments**: Both crypto (ERC-20) and bank transfer payments with on-chain verification
- **Dual Approval Mechanism**: Seller approval required for ownership transfers
- **Configurable Refunds**: Buyers can request refunds with configurable penalty
- **Role-Based Access Control**: Admin, Builder, Seller, and Buyer roles with proper access control
- **Upgradeable Contract**: Uses UUPS proxy pattern for future upgrades

## Contract Structure

- **Main Contract**: `src/LandRegistryUpgradeable.sol`
- **Tests**: `test/LandRegistry.t.sol` (unit tests) and `test/LandRegistryE2E.t.sol` (end-to-end tests)
- **Deployment Scripts**: `script/DeployLandRegistry.s.sol`, `script/UpgradeLandRegistry.s.sol`, `script/DeployOrUpgrade.s.sol`

## Deployed Contracts (Base Sepolia)

The contracts have been deployed to Base Sepolia testnet:

- **Land Registry Proxy**: `0xE75930E4b1386E60c15Ac7c0e4866509c0de73F6`
- **Land Registry Implementation**: `0x7C6B7f49b6D786a3Caf46fc704054802fCB5F87e`
- **Payment Token**: `0x4A8dFdD68Ec706C76F656bE09912E5345C6a55cc`

**Blockscout Explorer**: [https://base-sepolia.blockscout.com/](https://base-sepolia.blockscout.com/)

## Quick Start

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) installed
- Node.js (for dependencies)

### Installation

```bash
# Install dependencies
forge install

# Build
forge build

# Run tests
forge test

# Run tests with verbose output
forge test -vvv
```

### Deployment

1. Copy environment template:
```bash
cp env.example .env
```

2. Configure `.env` with your settings:
```
PRIVATE_KEY=your_private_key
RPC_URL=your_rpc_url
PAYMENT_TOKEN_ADDRESS=0x...
UPGRADE=false
PROXY_ADDRESS=0x... (if upgrading)
```

3. Deploy or upgrade:
```bash
# Using shell script
bash script/deploy.sh

# Or using forge directly
forge script script/DeployOrUpgrade.s.sol:DeployOrUpgrade --rpc-url $RPC_URL --broadcast --verify
```

## Test Coverage

The contract includes comprehensive test coverage:
- **26 Unit Tests**: Covering all individual functions and edge cases
- **7 E2E Tests**: Full workflow scenarios including:
  - Complete crypto payment workflow
  - Hybrid payment workflow
  - Refund workflows
  - Multiple lands scenarios
  - Admin bypass scenarios

## Contract Functions

### Land Management
- `registerLand()` - Register a new land parcel (Admin only)
- `lockLandToBuyer()` - Lock land to a buyer
- `adminUnlockLand()` - Admin can unlock land (Admin only)

### Payments
- `makePayment()` - Make ERC-20 token payment (installments supported)
- `submitBankPayment()` - Submit bank payment proof
- `verifyBankPayment()` - Verify bank payment (Builder/Admin only)

### Ownership Transfer
- `requestSellerApproval()` - Request seller approval for transfer
- `sellerApproveTransfer()` - Seller approves transfer
- `sellerRevokeApproval()` - Seller revokes approval
- `adminBypassSellerApproval()` - Admin bypass (emergency only)

### Refunds
- `requestRefund()` - Request refund with penalty

### Configuration
- `setPenaltyBasisPoints()` - Set refund penalty percentage (Admin only)
- `grantBuilderRole()` - Grant builder role (Admin only)
- `revokeBuilderRole()` - Revoke builder role (Admin only)

### View Functions
- `getPaymentBreakdown()` - Get payment details
- `getSellerApprovalStatus()` - Get seller approval status

## License

MIT
