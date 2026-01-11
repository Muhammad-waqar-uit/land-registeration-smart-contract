#!/bin/bash

# Load environment variables from .env file
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Check required variables
if [ -z "$PRIVATE_KEY" ]; then
    echo "Error: PRIVATE_KEY not set"
    exit 1
fi

if [ -z "$PROXY_ADDRESS" ]; then
    echo "Error: PROXY_ADDRESS not set"
    exit 1
fi

if [ -z "$RPC_URL" ]; then
    echo "Error: RPC_URL not set"
    exit 1
fi

echo "Upgrading Land Registry Contract..."
echo "Proxy Address: $PROXY_ADDRESS"
echo "RPC URL: $RPC_URL"
echo ""

# Run upgrade script
forge script script/Upgrade.s.sol:Upgrade \
    --rpc-url "$RPC_URL" \
    --broadcast \
    --verify \
    --etherscan-api-key "$ETHERSCAN_API_KEY" \
    -vvvv
