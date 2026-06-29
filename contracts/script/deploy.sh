#!/bin/bash

# Deploy script for MockDistributionManager and AutomationBase contracts

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Deploying Mock Automation Contracts${NC}"
echo -e "${GREEN}======================================${NC}"

# Check if PRIVATE_KEY is set
if [ -z "$PRIVATE_KEY" ]; then
    echo -e "${YELLOW}Warning: PRIVATE_KEY not set. Using default anvil key...${NC}"
    export PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
fi

# Check if RPC_URL is set
if [ -z "$RPC_URL" ]; then
    echo -e "${YELLOW}Warning: RPC_URL not set. Using default local anvil...${NC}"
    export RPC_URL="http://localhost:8545"
fi

# Function to deploy contracts
deploy() {
    echo -e "\n${GREEN}Building contracts...${NC}"
    forge build
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Build failed!${NC}"
        exit 1
    fi
    
    echo -e "\n${GREEN}Deploying to $RPC_URL...${NC}"
    forge script script/DeployMockAutomation.s.sol:DeployMockAutomation \
        --rpc-url $RPC_URL \
        --broadcast \
        -vvv
    
    if [ $? -eq 0 ]; then
        echo -e "\n${GREEN}Deployment successful!${NC}"
        echo -e "${GREEN}======================================${NC}"
        echo -e "${GREEN}Contracts Deployed:${NC}"
        echo -e "${GREEN}1. MockDistributionManager: Returns true every 200 blocks${NC}"
        echo -e "${GREEN}2. ChainlinkAutomation: Chainlink Keeper compatible${NC}"
        echo -e "${GREEN}3. GelatoAutomation: Gelato Network compatible${NC}"
        echo -e "${GREEN}======================================${NC}"
    else
        echo -e "${RED}Deployment failed!${NC}"
        exit 1
    fi
}

# Function to verify contracts (optional)
verify() {
    if [ -z "$ETHERSCAN_API_KEY" ]; then
        echo -e "${YELLOW}Skipping verification: ETHERSCAN_API_KEY not set${NC}"
        return
    fi
    
    echo -e "\n${GREEN}Verifying contracts...${NC}"
    forge verify-contract \
        --chain-id $(cast chain-id --rpc-url $RPC_URL) \
        --compiler-version v0.8.20 \
        $1 \
        src/modules/automation/MockDistributionManager.sol:MockDistributionManager
}

# Main execution
case "${1:-deploy}" in
    deploy)
        deploy
        ;;
    verify)
        if [ -z "$2" ]; then
            echo -e "${RED}Please provide contract address to verify${NC}"
            exit 1
        fi
        verify $2
        ;;
    *)
        echo "Usage: $0 {deploy|verify <address>}"
        exit 1
        ;;
esac