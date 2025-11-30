#!/bin/bash

# Land Registry Deployment Script
# Usage: ./script/deploy.sh [network]
# Network options: localhost, sepolia, mainnet (or any Foundry network name)

set -e

NETWORK=${1:-localhost}
SCRIPT="script/DeployOrUpgrade.s.sol:DeployOrUpgrade"

echo "=========================================="
echo "Land Registry Deploy/Upgrade Script"
echo "=========================================="
echo "Network: $NETWORK"
echo ""

# Check if .env file exists
if [ ! -f .env ]; then
    echo "Error: .env file not found!"
    echo "Please copy .env.example to .env and fill in the values"
    exit 1
fi

# Load environment variables
source .env

# Validate required variables
if [ -z "$PRIVATE_KEY" ]; then
    echo "Error: PRIVATE_KEY not set in .env"
    exit 1
fi

if [ "$UPGRADE" != "true" ]; then
    # DEPLOY MODE
    if [ -z "$PAYMENT_TOKEN_ADDRESS" ]; then
        echo "Error: PAYMENT_TOKEN_ADDRESS not set in .env (required for deployment)"
        exit 1
    fi
    
    echo "Mode: DEPLOY"
    echo "Payment Token: $PAYMENT_TOKEN_ADDRESS"
    echo ""
    
    forge script $SCRIPT \
        --rpc-url $NETWORK \
        --broadcast \
        --verify \
        --etherscan-api-key $ETHERSCAN_API_KEY \
        -vvvv
    
elif [ "$UPGRADE" == "true" ]; then
    # UPGRADE MODE
    if [ -z "$PROXY_ADDRESS" ]; then
        echo "Error: PROXY_ADDRESS not set in .env (required for upgrade)"
        exit 1
    fi
    
    echo "Mode: UPGRADE"
    echo "Proxy Address: $PROXY_ADDRESS"
    echo ""
    
    forge script $SCRIPT \
        --rpc-url $NETWORK \
        --broadcast \
        --verify \
        --etherscan-api-key $ETHERSCAN_API_KEY \
        -vvvv
fi

echo ""
echo "=========================================="
echo "Done!"
echo "=========================================="

