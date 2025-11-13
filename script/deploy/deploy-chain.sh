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
# Load from env variable RPC_<CHAIN_ID>
RPC_VAR=$(eval echo \$RPC_${CHAIN_ID})

# Get the additional params from the config.toml file

#### ===== CONTRACT VERIFICATION ============
VERIFY_BOOL=$(awk -v id="$CHAIN_ID" '/^\['"$CHAIN_ID"'\.bool\]/{flag=1;next} /^\[/{flag=0} flag && /^verify =/{gsub(/"/, "", $3); print $3}' config.toml)
# Set verify flag based on VERIFY_BOOL
VERIFY_FLAG=""
if [ "$VERIFY_BOOL" = "true" ]; then
    VERIFY_FLAG="--verify"
fi

### ===== GAS SUFFIX ============
# Build gas suffix if the gas values are set in the config.toml file
# expected names under chainId.uint block are: base_gas_price and priority_gas_price
# there can only one (base but not priority) or both of them
BASE_GAS_PRICE=$(awk -v id="$CHAIN_ID" '/^\['"$CHAIN_ID"'\.uint\]/{flag=1;next} /^\[/{flag=0} flag && /^base_gas_price =/{gsub(/"/, "", $3); print $3}' config.toml)
PRIORITY_GAS_PRICE=$(awk -v id="$CHAIN_ID" '/^\['"$CHAIN_ID"'\.uint\]/{flag=1;next} /^\[/{flag=0} flag && /^priority_gas_price =/{gsub(/"/, "", $3); print $3}' config.toml)

if [ -z "$BASE_GAS_PRICE" ] && [ -z "$PRIORITY_GAS_PRICE" ]; then
    GAS_SUFFIX=""
elif [ -z "$PRIORITY_GAS_PRICE" ]; then
    GAS_SUFFIX="--with-gas-price ${BASE_GAS_PRICE}gwei"
elif [ -z "$BASE_GAS_PRICE" ]; then
    log_warning "Base gas price is not set in config.toml for chain $CHAIN_ID while priority gas price is set. Please set both or none."
    log_warning "Continuing with deployment without gas settings."
    GAS_SUFFIX=""
else
    GAS_SUFFIX="--with-gas-price ${BASE_GAS_PRICE}gwei --priority-gas-price ${PRIORITY_GAS_PRICE}gwei"
fi

# Build gas suffix for `cast send` because it uses --gas-price instead of --with-gas-price
# Replace --with-gas-price with --gas-price but keep everything else (like priority gas price)
GAS_SUFFIX_SEND=""
if [[ "$GAS_SUFFIX" == *"--with-gas-price"* ]]; then
    GAS_SUFFIX_SEND="${GAS_SUFFIX/--with-gas-price/--gas-price}"
else
    GAS_SUFFIX_SEND="$GAS_SUFFIX"
fi

#### ================= START DEPLOYMENT LOGIC =================

# STEP 1: Verify / Deploy prerequisites
echo "========================================================================"
log_info "STEP 1: Verifying / Deploying prerequisites for chain $CHAIN_ID"

CREATE2_FACTORY_SIZE=$(cast codesize --rpc-url $RPC_VAR 0x4e59b44847b379578588920ca78fbf26c0b4956c)
#printf "CREATE2 FACTORY Codesize: $CREATE2_FACTORY_SIZE\n"

if [ $CREATE2_FACTORY_SIZE -eq 0 ]; then
    printf "Create2 factory is not deployed, trying to deploy...\n"
    printf "Funding deployer...\n"
    cast send 0x3fAB184622Dc19b6109349B94811493BF2a45362 --rpc-url $RPC_VAR --private-key $PRIVATE_KEY --value 0.007ether $GAS_SUFFIX_SEND | grep 'status'
    printf "Deploying Create2 factory...\n"
    cast publish --rpc-url $RPC_VAR 0xf8a58085174876e800830186a08080b853604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222222222222222222222222222222222222222222222222222222222222 > /dev/null
    CREATE2_FACTORY_SIZE=$(cast codesize --rpc-url $RPC_VAR 0x4e59b44847b379578588920ca78fbf26c0b4956c)
    if [ $CREATE2_FACTORY_SIZE -eq 69 ]; then
        printf "Create2 factory deployed successfully\n"
    else
        printf "Create2 factory deployment failed\n"
        exit 1
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
    cast send 0x4e59b44847b379578588920ca78fbf26c0b4956c $EP_V07_DEPLOY_TX_DATA --rpc-url $RPC_VAR --private-key $PRIVATE_KEY $GAS_SUFFIX_SEND
    EP_V07_SIZE=$(cast codesize --rpc-url $RPC_VAR 0x0000000071727De22E5E9d8BAf0edAc6f37da032)
    if [ $EP_V07_SIZE -eq 0 ]; then
        printf "EP v0.7 deployment failed\n"
        exit 1 
    else
        printf "EP v0.7 deployed successfully\n"
    fi
else 
    printf "Entry point has already been deployed\n"
fi

# STEP 2: Identify the contracts to deploy
echo "========================================================================"
log_info "STEP 2: Identifying contracts to deploy for chain $CHAIN_ID"

# Create temporary file for logs
TEMP_LOG="deploy-logs/precalc-log-$CHAIN_ID.log"
TEMP_LOG_ERRORS="deploy-logs/precalc-log-$CHAIN_ID-errors.log"

# Run dry run and capture output
{
    forge script ./DeployStxContracts.s.sol:DeployStxContracts  \
    --sig "run(uint256, bool)" "$CHAIN_ID" "false" 1> "$TEMP_LOG" 2> "$TEMP_LOG_ERRORS"
} || {
    log_error "Failed to define contracts to deploy for chain $CHAIN_ID, see logs for more details"
    exit 1
}

# Parse the log file to find contracts with 0 bytes (not deployed)
# Extract contract names from lines like: "ContractName  is  0  bytes at 0x... on chain:  1"
CONTRACTS=$(grep " is 0 bytes" "$TEMP_LOG" | awk '{print $1}')
CONTRACT_ADDRESSES=$(grep " is 0 bytes" "$TEMP_LOG" | awk '{print $3}')

# Build bash array of contract names
CONTRACT_ARRAY=()
for contract_name in $CONTRACTS; do
    CONTRACT_ARRAY+=("$contract_name")
done

# Build bash array of contract addresses
CONTRACT_ADDRESSES_ARRAY=()
for contract_address in $CONTRACT_ADDRESSES; do
    CONTRACT_ADDRESSES_ARRAY+=("$contract_address")
done

# Special flow for the Disperse contract
## Verify if CreateX is present
CREATEX_SIZE=$(cast codesize --rpc-url $RPC_VAR $CREATEX_ADDRESS)
if [ $CREATEX_SIZE -eq 0 ]; then
    log_warning "CreateX is not deployed on chain $CHAIN_ID. Deploying it..." 
    { 
        # estimate the gas cost of the CreateX deployment transaction
        CREATEX_GAS_ESTIMATE=$(cast estimate --rpc-url $RPC_VAR --create $(cat script/deploy/util/createx-hex/contract-createx-bytescode.json | jq -r))
        CREATEX_DEPLOY_PRESIGNED_TX="" 
        if [ $CREATEX_GAS_ESTIMATE -lt 3000000 ]; then # 3M gas
            CREATEX_DEPLOY_PRESIGNED_TX=$(cat script/deploy/util/createx-hex/signed_serialised_transaction_gaslimit_3000000_.json | jq -r)
        elif [ $CREATEX_GAS_ESTIMATE -lt 25000000 ]; then # 25M gas
            CREATEX_DEPLOY_PRESIGNED_TX=$(cat script/deploy/util/createx-hex/signed_serialised_transaction_gaslimit_25000000_ | jq -r)
        elif [ $CREATEX_GAS_ESTIMATE -lt 45000000 ]; then # 45M gas
            CREATEX_DEPLOY_PRESIGNED_TX=$(cat script/deploy/util/createx-hex/signed_serialised_transaction_gaslimit_45000000_.json | jq -r)
        else
            log_warning "CreateX deployment transaction gas cost is too high. Disperse contract will not be deployed."
            log_warning "Continuing with deployment without CreateX." 
        fi
        if [ -z "$CREATEX_DEPLOY_PRESIGNED_TX" ]; then
            # no presigned transaction found, we do not try to deploy CreateX
            log_warning "Disperse contract will not be deployed."
        else
            # try to deploy CreateX 
            {
                # fund the deployer address 0xeD456e05CaAb11d66C4c797dD6c1D6f9A7F352b5
                cast send --rpc-url $RPC_VAR 0xeD456e05CaAb11d66C4c797dD6c1D6f9A7F352b5 --private-key $PRIVATE_KEY --value 0.3ether $GAS_SUFFIX_SEND
                # publish the CreateX deployment transaction
                cast publish $CREATEX_DEPLOY_PRESIGNED_TX --rpc-url $RPC_VAR
                CREATEX_SIZE=$(cast codesize --rpc-url $RPC_VAR $CREATEX_ADDRESS)
                if [ $CREATEX_SIZE -eq 0 ]; then
                    # failed to deploy CreateX
                    log_warning "CreateX deployment failed. Disperse contract will not be deployed."
                else
                    # successfully deployed CreateX
                    # if no createx => no disperse at an expected address
                    CONTRACT_ARRAY+=("Disperse")
                    CONTRACT_ADDRESSES_ARRAY+=($EXPECTED_DISPERSE_ADDRESS)
                fi
            } || {
                # failed to deploy CreateX
                log_warning "CreateX deployment failed. Disperse contract will not be deployed."
            }
        fi
    } || {
        log_warning "Failed to estimate the gas cost of the CreateX deployment transaction"
        log_warning "Continuing with deployment without CreateX."
        log_warning "Disperse contract will not be deployed."  
    } 
else
    # createx has already been deployed
    log_info "CreateX is already deployed on chain $CHAIN_ID"
    DISPERSE_SIZE=$(cast codesize --rpc-url $RPC_VAR $EXPECTED_DISPERSE_ADDRESS)
    # if disperse size is 0, schedule it for deployment
    if [ $DISPERSE_SIZE -eq 0 ]; then
        CONTRACT_ARRAY+=("Disperse")
        CONTRACT_ADDRESSES_ARRAY+=($EXPECTED_DISPERSE_ADDRESS)
    fi

# Convert bash array to JSON array format for forge script
CONTRACT_NAMES="["
for i in "${!CONTRACT_ARRAY[@]}"; do
    if [ $i -eq 0 ]; then
        CONTRACT_NAMES="${CONTRACT_NAMES}\"${CONTRACT_ARRAY[$i]}\""
    else
        CONTRACT_NAMES="${CONTRACT_NAMES},\"${CONTRACT_ARRAY[$i]}\""
    fi
done
CONTRACT_NAMES="${CONTRACT_NAMES}]"

# Clean up temp files
rm -f "$TEMP_LOG"
rm -f "$TEMP_LOG_ERRORS"

# Log every contract with an address on a new line
printf "Contracts to deploy on chain $CHAIN_ID:\n"
for i in "${!CONTRACT_ARRAY[@]}"; do
    contract_name="${CONTRACT_ARRAY[$i]}"
    contract_address="${CONTRACT_ADDRESSES_ARRAY[$i]}"
    printf "$contract_name\n"
done

# STEP 3: Deploy Stx contracts
echo "========================================================================"
log_info "STEP 3: Deploying Stx contracts for chain $CHAIN_ID"

# Check if there are any contracts to deploy
if [ "$CONTRACT_NAMES" = "[]" ]; then
    log_info "All contracts are already deployed on chain $CHAIN_ID. Skipping deployment."
    exit 0
fi

# Try to deploy and verify the contracts
# If the script has been run successfully, exit with code 0
# If the script has failed, there are two options:
# 1. The script failed because the contracts were not deployed
# 2. The script failed because the contracts were deployed but verification failed
# We check this by checking the sizes of the expected contracts addresses from CONTRACT_ADDRESSES_ARRAY via cast codesize
# if all the expected contract address are deployed, but the script failed, that means only verification failed
# if at least one contract is not deployed, that means the deployment failed completely
# If the deployment failed completely, exit with code 1
# If only verification failed, exit with code 2
if forge script ./DeployStxContracts.s.sol:DeployStxContracts  \
    --sig "run(uint256,string[])" "$CHAIN_ID" "$CONTRACT_NAMES" \
    --private-key $PRIVATE_KEY \
    $VERIFY_FLAG \
    $GAS_SUFFIX \
    -vv --broadcast --slow; then
    # successfully deployed and verified
    log_info "Deployment and verification completed successfully for chain $CHAIN_ID"
    exit 0
else
    # forge script failed
    log_warning "Forge script failed. Checking if contracts were deployed..."
    # Check if all contracts are deployed by verifying their codesize
    ALL_DEPLOYED=true
    for contract_address in "${CONTRACT_ADDRESSES_ARRAY[@]}"; do
        echo "Checking codesize for $contract_address"
        CODE_SIZE=$(cast codesize --rpc-url $RPC_VAR $contract_address)
        echo "CODE_SIZE: $CODE_SIZE"
        if ! [[ "$CODE_SIZE" =~ ^[0-9]+$ ]]; then
            log_error "Failed to get codesize for $contract_address: $CODE_SIZE"
            ALL_DEPLOYED=false
        elif [ "$CODE_SIZE" -eq 0 ]; then
            log_error "Contract at $contract_address was not deployed (codesize: 0)"
            ALL_DEPLOYED=false
        fi
    done

    if [ "$ALL_DEPLOYED" = true ]; then
        log_warning "All contracts are deployed but script failed - verification likely failed"
        exit 2
    else
        log_error "Deployment failed - at least one contract was not deployed"
        exit 1
    fi
fi
