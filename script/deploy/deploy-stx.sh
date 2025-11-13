#!/bin/bash

# Comprehensive deployment testing script for multiple chains
# This script deploys contracts, configures LayerZero, and funds signers
#
# Usage: bash deploy-stx.sh [chain_id1] [chain_id2] ...
#
# Examples:
#   bash deploy-stx.sh                    # Deploy to all chains in config.toml
#   bash deploy-stx.sh 84532              # Deploy only to Base Sepolia
#   bash deploy-stx.sh 84532 11155420     # Deploy to Base Sepolia and Optimism Sepolia
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

# Function to show a spinner animation
spinner() {
    local pid=$1
    local message=$2
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    
    # Hide cursor
    tput civis
    
    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr:i++%${#spinstr}:1}
        printf "\r${GREEN}[%s]${NC} %s" "$temp" "$message"
        sleep 0.1
    done
    
    # Show cursor again
    tput cnorm
    printf "\r"
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

# Function to get all chain IDs from config.toml
get_all_chains() {
    grep '^\[' config.toml | grep -v '\.' | sed 's/\[//g' | sed 's/\]//g'
}

# Parse command-line arguments
REQUESTED_CHAINS=()
if [ $# -gt 0 ]; then
    # User provided specific chain IDs to deploy to
    REQUESTED_CHAINS=("$@")
    log_info "Requested deployment for chain IDs: ${REQUESTED_CHAINS[*]}"
else
    # Get all chains from config.toml
    REQUESTED_CHAINS=($(get_all_chains))
    log_info "No specific chains requested, will deploy to all chains in config.toml: ${REQUESTED_CHAINS[*]}"
fi

# Start deployment process
log_info "Starting comprehensive deployment test"
if [ ${#REQUESTED_CHAINS[@]} -gt 0 ]; then
    log_info "Deploying to chains: ${REQUESTED_CHAINS[*]}"
fi
echo "========================================================================"

# Step 1: Load environment variables
log_info "Loading environment variables from .env"
if [ ! -f ../../.env ]; then
    log_error ".env file not found!"
    exit 1
fi

source ../../.env

# Step 2: Validate required environment variables
log_info "Validating required environment variables"

if [ -z "$MAINNET_PRIVATE_KEY" ]; then
    log_error "MAINNET_PRIVATE_KEY is not set in .env"
    exit 1
fi

if [ -z "$TESTNET_PRIVATE_KEY" ]; then
    log_error "TESTNET_PRIVATE_KEY is not set in .env"
    exit 1
fi

# Check RPC URLs for requested chains
for chain_id in "${REQUESTED_CHAINS[@]}"; do
    RPC_VAR="RPC_${chain_id}"
    if [ -z "${!RPC_VAR}" ]; then
        log_error "$RPC_VAR is not set in .env for chain $chain_id"
        log_info "Please set $RPC_VAR in your .env file"
        exit 1
    fi
done

# Check if CREATEX_ADDRESS is set in .env
if [ -z "$CREATEX_ADDRESS" ]; then
    log_error "CREATEX_ADDRESS is not set in .env"
    exit 1
fi

# Check if EXPECTED_DISPERSE_ADDRESS is set in .env (0xd15fE25eD0Dba12fE05e7029C88b10C25e8880E3)
if [ -z "$EXPECTED_DISPERSE_ADDRESS" ]; then
    log_error "EXPECTED_DISPERSE_ADDRESS is not set in .env"
    exit 1
fi

# Check if we have to recompile the artifacts
export FOUNDRY_PROFILE="via-ir"
read -r -p "Do you want to rebuild Stx-contracts artifacts from your local sources? (y/n): " proceed
if [ $proceed = "y" ]; then
    ### BUILD ARTIFACTS ###
    printf "Building Stx-contracts artifacts\n"
    { (forge build --sizes 1> ./deploy-logs/build/forge-build.log 2> ./deploy-logs/build/forge-build-errors.log) } || {
        printf "Build failed\n See logs for more details\n"
        exit 1
    }
    printf "Copying Stx-contracts artifacts\n"
    
    mkdir -p ./artifacts/K1MeeValidator
    mkdir -p ./artifacts/Nexus
    mkdir -p ./artifacts/NexusBootstrap
    mkdir -p ./artifacts/NexusAccountFactory
    mkdir -p ./artifacts/NexusProxy
    mkdir -p ./artifacts/ComposableExecutionModule
    mkdir -p ./artifacts/ComposableStorage
    mkdir -p ./artifacts/EtherForwarder
    mkdir -p ./artifacts/NodePaymasterFactory
    
    cp ../../out/K1MeeValidator.sol/K1MeeValidator.json ./artifacts/K1MeeValidator/.
    cp ../../out/Nexus.sol/Nexus.json ./artifacts/Nexus/.
    cp ../../out/NexusBootstrap.sol/NexusBootstrap.json ./artifacts/NexusBootstrap/.
    cp ../../out/NexusAccountFactory.sol/NexusAccountFactory.json ./artifacts/NexusAccountFactory/.
    cp ../../out/NexusProxy.sol/NexusProxy.json ./artifacts/NexusProxy/.
    cp ../../out/ComposableExecutionModule.sol/ComposableExecutionModule.json ./artifacts/ComposableExecutionModule/.
    cp ../../out/ComposableStorage.sol/ComposableStorage.json ./artifacts/ComposableStorage/.
    cp ../../out/EtherForwarder.sol/EtherForwarder.json ./artifacts/EtherForwarder/.
    cp ../../out/NodePaymasterFactory.sol/NodePaymasterFactory.json ./artifacts/NodePaymasterFactory/.
    
    printf "Artifacts copied\n"

    ### CREATE VERIFICATION ARTIFACTS ###
    printf "Creating verification artifacts\n"
    forge verify-contract --show-standard-json-input $(cast address-zero) K1MeeValidator > ./artifacts/K1MeeValidator/verify.json    
    forge verify-contract --show-standard-json-input $(cast address-zero) Nexus > ./artifacts/Nexus/verify.json
    forge verify-contract --show-standard-json-input $(cast address-zero) NexusBootstrap > ./artifacts/NexusBootstrap/verify.json
    forge verify-contract --show-standard-json-input $(cast address-zero) NexusAccountFactory > ./artifacts/NexusAccountFactory/verify.json
    forge verify-contract --show-standard-json-input $(cast address-zero) NexusProxy > ./artifacts/NexusProxy/verify.json
    forge verify-contract --show-standard-json-input $(cast address-zero) ComposableExecutionModule > ./artifacts/ComposableExecutionModule/verify.json
    forge verify-contract --show-standard-json-input $(cast address-zero) ComposableStorage > ./artifacts/ComposableStorage/verify.json
    forge verify-contract --show-standard-json-input $(cast address-zero) EtherForwarder > ./artifacts/EtherForwarder/verify.json
    forge verify-contract --show-standard-json-input $(cast address-zero) NodePaymasterFactory > ./artifacts/NodePaymasterFactory/verify.json
    
    log_info "Artifacts created"
else 
    log_info "Using precompiled artifacts"
fi

CHAIN_ARRAY="["
for i in "${!REQUESTED_CHAINS[@]}"; do
    if [ $i -gt 0 ]; then
        CHAIN_ARRAY="${CHAIN_ARRAY},"
    fi
    CHAIN_ARRAY="${CHAIN_ARRAY}${REQUESTED_CHAINS[$i]}"
done
CHAIN_ARRAY="${CHAIN_ARRAY}]"

# Check the expected addresses for the contracts and record the bytecode hashes
log_info "Getting expected addresses for the contracts..."
{ 
    forge script ./DeployStxContracts.s.sol:DeployStxContracts  \
    --sig "run(uint256, bool)" "${REQUESTED_CHAINS[0]}" "true" 1> ./deploy-logs/00dry-run.log 2> ./deploy-logs/00dry-run-errors.log
} &

# Capture the PID of the background process
forge_pid=$!
spinner $forge_pid "Computing expected addresses..."
wait $forge_pid
forge_status=$?

if [ $forge_status -ne 0 ]; then
    log_error "Failed to get expected addresses for the contracts, see logs for more details"
    exit 1
fi

# display the addresses from above log file
cat ./deploy-logs/00dry-run.log | grep "bytes at" | awk '{print $6, $1}'

# Request if the user wants to proceed with the deployment
read -r -p "Do you want to proceed with the addresses above? (y/n): " proceed
if [ $proceed = "n" ]; then
    log_info "Deployment cancelled"
    exit 0
fi

# For every chain in the REQUESTED_CHAINS array, deploy the Stx contracts
# by callig the deploy-chain.sh script and logging the output to a file
for chain_id in "${REQUESTED_CHAINS[@]}"; do
    chain_name=$(awk -v id="$chain_id" '/^\['"$chain_id"'\.string\]/{flag=1;next} /^\[/{flag=0} flag && /^name =/{gsub(/"/, "", $3); print $3}' config.toml)
    
    # Temporarily disable exit on error to handle deployment failures gracefully
    set +e
    bash deploy-chain.sh $chain_id 1> ./deploy-logs/$chain_name-$chain_id-deploy.log 2> ./deploy-logs/$chain_name-$chain_id-deploy-errors.log &
    deploy_pid=$!
    spinner $deploy_pid "Deploying Stx contracts to chain $chain_id ($chain_name)..."
    wait $deploy_pid
    deploy_status=$?
    set -e
    
    if [ $deploy_status -eq 0 ]; then
        log_info "Stx contracts deployed to chain $chain_id ($chain_name) successfully"
    elif [ $deploy_status -eq 2 ]; then
        log_warning "Stx contracts deployed to chain $chain_id ($chain_name) successfully, but verification failed"
        log_warning "See logs for more details"
        log_info "Continuing with deployment for next chain if present"
    else
        log_error "Failed to deploy Stx contracts to chain $chain_id ($chain_name)"
        log_error "See logs for more details"
        log_info "Continuing with deployment for next chain if present"
    fi
done
