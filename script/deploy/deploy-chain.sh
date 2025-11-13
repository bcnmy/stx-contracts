#!/bin/bash

# Comprehensive deployment testing script for multiple chains
# This script deploys contracts, configures LayerZero, and funds signers
#
# Usage: bash deploy-chain.sh [chain_id]
#
# Examples:
#   bash deploy-chain.sh 84532              # Deploy only to Base Sepolia
#   bash deploy-chain.sh 11155420           # Deploy only to Optimism Sepolia
# etc

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check if a command succeeded
check_success() {
    if [ $? -eq 0 ]; then
        log_info "$1 succeeded"
    else
        log_error "$1 failed"
        exit 1
    fi  
}

# Parse command-line arguments
# Exit if no chain ID is provided ot more than one chain ID is provided
if [ $# -ne 1 ]; then
    log_error "Usage: bash deploy-chain.sh [chain_id]"
    exit 1
fi

CHAIN_ID=$1

# Identify testnet or mainnet and set the according private key
# parse config.toml to find the is_testnet = true or false for the given chain ID
IS_TESTNET=$(awk -v id="$CHAIN_ID" '/^\['"$CHAIN_ID"'\.bool\]/{flag=1;next} /^\[/{flag=0} flag && /^is_testnet =/{gsub(/"/, "", $3); print $3}' config.toml)
if [ $IS_TESTNET = true ]; then
    PRIVATE_KEY=$TESTNET_PRIVATE_KEY
else
    PRIVATE_KEY=$MAINNET_PRIVATE_KEY
fi

# Find the RPC URL for the given chain ID
# We have validated that the RPC_VAR is set in the .env file in the deploy-stx.sh script
RPC_VAR="RPC_${CHAIN_ID}"

# STEP 1: Verify / Deploy prerequisites
log_info "STEP 1: Verifying / Deploying prerequisites for chain $CHAIN_ID"
echo "========================================================================"

CREATE2_FACTORY_SIZE=$(cast codesize --rpc-url $RPC_VAR 0x4e59b44847b379578588920ca78fbf26c0b4956c)
#printf "CREATE2 FACTORY Codesize: $CREATE2_FACTORY_SIZE\n"

if [ $CREATE2_FACTORY_SIZE -eq 0 ]; then
    printf "Create2 factory is not deployed, trying to deploy...\n"
    printf "Funding deployer...\n"
    cast send 0x3fAB184622Dc19b6109349B94811493BF2a45362 --rpc-url $RPC_VAR --private-key $PRIVATE_KEY --value 0.007ether | grep 'status'
    printf "Deploying Create2 factory...\n"
    cast publish --rpc-url $RPC_VAR 0xf8a58085174876e800830186a08080b853604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222222222222222222222222222222222222222222222222222222222222 > /dev/null
    CREATE2_FACTORY_SIZE=$(cast codesize --rpc-url $RPC_VAR 0x4e59b44847b379578588920ca78fbf26c0b4956c)
    if [ $CREATE2_FACTORY_SIZE -eq 69 ]; then
        printf "Create2 factory deployed successfully\n"
    else
        printf "Create2 factory deployment failed\n"
        exit 64
    fi
else
    printf "Create2 factory has already been deployed\n"
fi

### Entry Point ###

EP_V07_SIZE=$(cast codesize --rpc-url $RPC_VAR 0x0000000071727De22E5E9d8BAf0edAc6f37da032)
#printf "EP Codesize: $EP_V07_SIZE\n"

if [ $EP_V07_SIZE -eq 0 ]; then
    printf "Entry point is not deployed, trying to deploy...\n"
    # Validate that EP_V07_DEPLOY_TX_DATA is set in the .env file
    if [ -z "$EP_V07_DEPLOY_TX_DATA" ]; then
        log_error "EP_V07_DEPLOY_TX_DATA is not set in .env"
        exit 1
    fi
    cast send --rpc-url $RPC_VAR 0x4e59b44847b379578588920ca78fbf26c0b4956c --private-key $PRIVATE_KEY $EP_V07_DEPLOY_TX_DATA
    EP_V07_SIZE=$(cast codesize --rpc-url $RPC_VAR 0x0000000071727De22E5E9d8BAf0edAc6f37da032)
    if [ $EP_V07_SIZE -eq 0 ]; then
        printf "EP v0.7 deployment failed\n"
        exit 64 
    else
        printf "EP v0.7 deployed successfully\n"
    fi
else 
    printf "Entry point has already been deployed\n"
fi

# STEP 2: Identify the contracts to deploy



# STEP 3: Deploy Stx contracts
log_info "STEP 2: Deploying Stx contracts for chain $CHAIN_ID"
echo "========================================================================"

VERIFY_BOOL=$(awk -v id="$CHAIN_ID" '/^\['"$CHAIN_ID"'\.bool\]/{flag=1;next} /^\[/{flag=0} flag && /^verify =/{gsub(/"/, "", $3); print $3}' config.toml)

# Set verify flag based on VERIFY_BOOL
VERIFY_FLAG=""
if [ "$VERIFY_BOOL" = "true" ]; then
    VERIFY_FLAG="--verify"
fi

forge script ./DeployStxContracts.s.sol:DeployStxContracts  \
--sig "run(uint256,string[])" "$CHAIN_ID" "$CONTRACT_NAMES" \
--private-key $PRIVATE_KEY \
$VERIFY_FLAG \
$GAS_SUFFIX \
-vv --broadcast --slow 
