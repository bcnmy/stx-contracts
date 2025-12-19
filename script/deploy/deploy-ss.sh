#!/bin/bash

# Smart Session deployment script
# Deploys SmartSession contracts via SafeSingletonDeployer
#
# Usage: bash deploy-ss.sh <chain_id>
#
# Examples:
#   bash deploy-ss.sh 84532        # Deploy to Base Sepolia
#   bash deploy-ss.sh 1            # Deploy to Ethereum Mainnet

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_summary() {
    echo -e "${BLUE}[SUMMARY]${NC} $1"
}

# Parse command-line arguments
if [ $# -ne 1 ]; then
    log_error "Usage: bash deploy-ss.sh <chain_id>"
    exit 1
fi

CHAIN_ID=$1

# Load environment variables
log_info "Loading environment variables from .env"
if [ ! -f ../../.env ]; then
    log_error ".env file not found!"
    exit 1
fi

source ../../.env

# Validate required environment variables
log_info "Validating required environment variables"

if [ -z "$MAINNET_PRIVATE_KEY" ]; then
    log_error "MAINNET_PRIVATE_KEY is not set in .env"
    exit 1
fi

if [ -z "$TESTNET_PRIVATE_KEY" ]; then
    log_error "TESTNET_PRIVATE_KEY is not set in .env"
    exit 1
fi

# Get chain configuration from config.toml
log_info "Looking up chain configuration for chain ID: $CHAIN_ID"

# Check if chain exists in config.toml
if ! grep -q "^\[$CHAIN_ID\]" config.toml; then
    log_error "Chain ID $CHAIN_ID not found in config.toml"
    exit 1
fi

# Get RPC URL variable name and resolve it
RPC_VAR_NAME=$(awk -v id="$CHAIN_ID" '/^\['"$CHAIN_ID"'\]/{flag=1;next} /^\[/{flag=0} flag && /^endpoint_url =/{gsub(/endpoint_url = /, ""); gsub(/"/, ""); gsub(/\$\{/, ""); gsub(/\}/, ""); print; exit}' config.toml)
RPC_VAR="RPC_${CHAIN_ID}"
RPC_URL="${!RPC_VAR}"

if [ -z "$RPC_URL" ]; then
    log_error "$RPC_VAR is not set in .env for chain $CHAIN_ID"
    exit 1
fi

log_info "RPC URL found for chain $CHAIN_ID"

# Get chain name
CHAIN_NAME=$(awk -v id="$CHAIN_ID" '/^\['"$CHAIN_ID"'\.string\]/{flag=1;next} /^\[/{flag=0} flag && /^name =/{sub(/^name = /, ""); gsub(/"/, ""); print; exit}' config.toml)
log_info "Chain name: $CHAIN_NAME"

# Identify testnet or mainnet and set the according private key
IS_TESTNET=$(awk -v id="$CHAIN_ID" '/^\['"$CHAIN_ID"'\.bool\]/{flag=1;next} /^\[/{flag=0} flag && /^is_testnet =/{gsub(/"/, "", $3); print $3}' config.toml)
if [ "$IS_TESTNET" = "true" ]; then
    PRIVATE_KEY=$TESTNET_PRIVATE_KEY
    log_info "Using TESTNET_PRIVATE_KEY (is_testnet=true)"
else
    PRIVATE_KEY=$MAINNET_PRIVATE_KEY
    log_info "Using MAINNET_PRIVATE_KEY (is_testnet=false)"
fi

# Get verification flag
VERIFY_BOOL=$(awk -v id="$CHAIN_ID" '/^\['"$CHAIN_ID"'\.bool\]/{flag=1;next} /^\[/{flag=0} flag && /^verify =/{gsub(/"/, "", $3); print $3}' config.toml)
VERIFY_FLAG=""
if [ "$VERIFY_BOOL" = "true" ]; then
    VERIFY_FLAG="--verify"
fi

# Get gas settings
BASE_GAS_PRICE=$(awk -v id="$CHAIN_ID" '/^\['"$CHAIN_ID"'\.uint\]/{flag=1;next} /^\[/{flag=0} flag && /^base_gas_price =/{gsub(/"/, "", $3); print $3}' config.toml)
PRIORITY_GAS_PRICE=$(awk -v id="$CHAIN_ID" '/^\['"$CHAIN_ID"'\.uint\]/{flag=1;next} /^\[/{flag=0} flag && /^priority_gas_price =/{gsub(/"/, "", $3); print $3}' config.toml)

if [ -z "$BASE_GAS_PRICE" ] && [ -z "$PRIORITY_GAS_PRICE" ]; then
    GAS_SUFFIX=""
elif [ -z "$PRIORITY_GAS_PRICE" ]; then
    GAS_SUFFIX="--with-gas-price ${BASE_GAS_PRICE}gwei"
elif [ -z "$BASE_GAS_PRICE" ]; then
    log_warning "Base gas price is not set in config.toml for chain $CHAIN_ID while priority gas price is set. Continuing without gas settings."
    GAS_SUFFIX=""
else
    GAS_SUFFIX="--with-gas-price ${BASE_GAS_PRICE}gwei --priority-gas-price ${PRIORITY_GAS_PRICE}gwei"
fi

# Get gas estimate multiplier
GAS_ESTIMATE_MULTIPLY=$(awk -v id="$CHAIN_ID" '/^\['"$CHAIN_ID"'\.uint\]/{flag=1;next} /^\[/{flag=0} flag && /^gas_estimate_multiply =/{gsub(/"/, "", $3); print $3}' config.toml)
if [ -z "$GAS_ESTIMATE_MULTIPLY" ]; then
    GAS_ESTIMATE_MULTIPLY_SUFFIX=""
else
    GAS_ESTIMATE_MULTIPLY_SUFFIX="--gas-estimate-multiplier ${GAS_ESTIMATE_MULTIPLY}"
fi

# Setup log directory for this chain
CHAIN_NAME_SANITIZED=$(echo "$CHAIN_NAME" | tr ' ' '-')
LOG_DIR="deploy-logs/ss/ss-${CHAIN_NAME_SANITIZED}-${CHAIN_ID}"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/deploy-ss.log"
ERROR_LOG_FILE="$LOG_DIR/deploy-ss-errors.log"
log_info "Logs will be written to $LOG_DIR"

# Parse contracts from deploy-ss.toml
log_info "Parsing contracts from deploy-ss.toml"

# Extract contract names from deploy-ss.toml
# Format: [deployments.singleton.ContractName]
CONTRACT_NAMES=($(grep '^\[deployments\.singleton\.' deploy-ss.toml | sed 's/\[deployments\.singleton\.//' | sed 's/\]//'))

if [ ${#CONTRACT_NAMES[@]} -eq 0 ]; then
    log_error "No contracts found in deploy-ss.toml"
    exit 1
fi

log_info "Found ${#CONTRACT_NAMES[@]} contracts to process"

# Arrays to track deployment results
declare -a DEPLOYED_CONTRACTS=()
declare -a DEPLOYED_ADDRESSES=()
declare -a SKIPPED_CONTRACTS=()
declare -a SKIPPED_ADDRESSES=()
declare -a FAILED_CONTRACTS=()
declare -a FAILED_ADDRESSES=()

echo "========================================================================"
log_info "Starting Smart Session deployment to chain $CHAIN_ID ($CHAIN_NAME)"
echo "========================================================================"

# Process each contract
for contract_name in "${CONTRACT_NAMES[@]}"; do
    echo "------------------------------------------------------------------------"
    log_info "Processing contract: $contract_name"

    # Extract contract details from deploy-ss.toml
    # Use awk to parse the TOML section
    FILE=$(awk -v name="$contract_name" '
        /^\[deployments\.singleton\.'"$contract_name"'\]/{flag=1;next}
        /^\[/{flag=0}
        flag && /^file =/{gsub(/file = /, ""); gsub(/"/, ""); print; exit}
    ' deploy-ss.toml)

    SALT=$(awk -v name="$contract_name" '
        /^\[deployments\.singleton\.'"$contract_name"'\]/{flag=1;next}
        /^\[/{flag=0}
        flag && /^salt =/{gsub(/salt = /, ""); gsub(/"/, ""); print; exit}
    ' deploy-ss.toml)

    EXPECTED_ADDRESS=$(awk -v name="$contract_name" '
        /^\[deployments\.singleton\.'"$contract_name"'\]/{flag=1;next}
        /^\[/{flag=0}
        flag && /^expected_address=/{gsub(/expected_address=/, ""); gsub(/"/, ""); print; exit}
    ' deploy-ss.toml)

    if [ -z "$FILE" ] || [ -z "$SALT" ] || [ -z "$EXPECTED_ADDRESS" ]; then
        log_error "Missing configuration for $contract_name (file=$FILE, salt=$SALT, expected_address=$EXPECTED_ADDRESS)"
        FAILED_CONTRACTS+=("$contract_name")
        FAILED_ADDRESSES+=("$EXPECTED_ADDRESS")
        continue
    fi

    log_info "  File: $FILE"
    log_info "  Salt: $SALT"
    log_info "  Expected address: $EXPECTED_ADDRESS"

    # Step a) Check if code exists at expected address
    log_info "Checking if contract is already deployed..."
    CODE=$(cast code --rpc-url "$RPC_URL" "$EXPECTED_ADDRESS" 2>/dev/null || echo "0x")

    if [ "$CODE" != "0x" ] && [ -n "$CODE" ]; then
        log_info "$contract_name is already deployed at $EXPECTED_ADDRESS on chain $CHAIN_ID"
        SKIPPED_CONTRACTS+=("$contract_name")
        SKIPPED_ADDRESSES+=("$EXPECTED_ADDRESS")
        continue
    fi

    # Step b) Deploy using DeployViaSafeDeployer.s.sol
    log_info "No code found at $EXPECTED_ADDRESS. Deploying $contract_name..."

    # Temporarily disable exit on error for deployment
    set +e

    forge script ./util/DeployViaSafeDeployer.s.sol:DeployViaSafeDeployer \
        --sig "run(address,string,bytes32,string)" \
        "$EXPECTED_ADDRESS" \
        "$FILE" \
        "$SALT" \
        "$contract_name" \
        --rpc-url "$RPC_URL" \
        --private-key "$PRIVATE_KEY" \
        $VERIFY_FLAG \
        $GAS_SUFFIX \
        $GAS_ESTIMATE_MULTIPLY_SUFFIX \
        -vv --broadcast \
        1>> "$LOG_FILE" 2>> "$ERROR_LOG_FILE"

    DEPLOY_STATUS=$?
    set -e

    # Step c) Validate script execution
    if [ $DEPLOY_STATUS -ne 0 ]; then
        log_warning "Forge script returned non-zero status for $contract_name. Checking deployment status..."
    fi

    # Step d) Verify code is now present at expected address
    log_info "Verifying deployment..."
    CODE_AFTER=$(cast code --rpc-url "$RPC_URL" "$EXPECTED_ADDRESS" 2>/dev/null || echo "0x")

    if [ "$CODE_AFTER" != "0x" ] && [ -n "$CODE_AFTER" ]; then
        log_info "Successfully deployed $contract_name at $EXPECTED_ADDRESS"
        DEPLOYED_CONTRACTS+=("$contract_name")
        DEPLOYED_ADDRESSES+=("$EXPECTED_ADDRESS")
    else
        log_error "Failed to deploy $contract_name - no code at $EXPECTED_ADDRESS after deployment attempt"
        FAILED_CONTRACTS+=("$contract_name")
        FAILED_ADDRESSES+=("$EXPECTED_ADDRESS")
    fi
done

# Step 4) Print summary
echo ""
echo "========================================================================"
log_summary "DEPLOYMENT SUMMARY for chain $CHAIN_ID ($CHAIN_NAME)"
echo "========================================================================"

if [ ${#DEPLOYED_CONTRACTS[@]} -gt 0 ]; then
    echo ""
    log_info "Successfully deployed (${#DEPLOYED_CONTRACTS[@]} contracts):"
    for i in "${!DEPLOYED_CONTRACTS[@]}"; do
        echo -e "  ${GREEN}${NC} ${DEPLOYED_CONTRACTS[$i]} -> ${DEPLOYED_ADDRESSES[$i]}"
    done
fi

if [ ${#SKIPPED_CONTRACTS[@]} -gt 0 ]; then
    echo ""
    log_info "Already deployed / Skipped (${#SKIPPED_CONTRACTS[@]} contracts):"
    for i in "${!SKIPPED_CONTRACTS[@]}"; do
        echo -e "  ${YELLOW}�${NC} ${SKIPPED_CONTRACTS[$i]} -> ${SKIPPED_ADDRESSES[$i]}"
    done
fi

if [ ${#FAILED_CONTRACTS[@]} -gt 0 ]; then
    echo ""
    log_error "Failed to deploy (${#FAILED_CONTRACTS[@]} contracts):"
    for i in "${!FAILED_CONTRACTS[@]}"; do
        echo -e "  ${RED}${NC} ${FAILED_CONTRACTS[$i]} -> ${FAILED_ADDRESSES[$i]}"
    done
    echo ""
    exit 1
fi

echo ""
log_info "Deployment complete!"
