#!/bin/bash

# check-verification.sh
# For a given chain (default 84532 Base Sepolia), checks Etherscan-API verification
# status of every v2.2.2 stx-contracts deployment address.
#
# Usage:
#   bash script/deploy/check-verification.sh                   # Base Sepolia, default
#   bash script/deploy/check-verification.sh 84532             # explicit
#   bash script/deploy/check-verification.sh 84532 0xAddr      # single address probe
#
# Requires $ETHERSCAN_API_KEY in .env. Reads $RPC_<chain_id> to corroborate
# on-chain codesize (so unverified-and-deployed is distinguishable from not-deployed).

set -u

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ENV_FILE="$(cd "$(dirname "$0")/../.." && pwd)/.env"
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}.env not found at $ENV_FILE${NC}" >&2
    exit 1
fi
set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

CHAIN_ID="${1:-84532}"
PROBE_ADDR="${2:-}"

if [ -z "${ETHERSCAN_API_KEY:-}" ]; then
    echo -e "${RED}ETHERSCAN_API_KEY not set in .env${NC}" >&2
    exit 1
fi

rpc_var="RPC_${CHAIN_ID}"
rpc_url="${!rpc_var:-}"

# v2.2.2 deterministic addresses
declare -a NAMES=(
    "K1MeeValidator"
    "Nexus"
    "NexusBootstrap"
    "NexusAccountFactory"
    "NexusProxy"
    "ComposableExecutionModule"
    "Storage"
    "EtherForwarder"
    "NodePaymasterFactory"
)
declare -a ADDRS=(
    "0x0000B1C0790E5a28293276C320d2B95D651dBaD6"
    "0x0000b1C0B95DA04652C1919667D1DCC14f46f62B"
    "0x0000B1c0A80cb7DD166a15e7390b8A4Ced4500C6"
    "0x0000B1c0dCFd64dfe8FeC844923B653DD0dfdB05"
    "0x51a5f8792Cd5a5E85e9ecE1D2f6c2cd7618a8365"
    "0x0000821108B5C9F3fe17E40811bE5b66DaF8f0e7"
    "0x00008211dea1Aca67ac55fc44AE3bF88CF41281d"
    "0x0000B1C0Fc7015Effa85892426FAEd8211B2d62E"
    "0x0000B1C059753ae6d1C135605377cE6487385960"
)

echo -e "${BLUE}Chain:${NC} $CHAIN_ID"
echo ""
printf "%-26s %-44s %-10s %s\n" "NAME" "ADDRESS" "CODESIZE" "VERIFIED"
printf "%-26s %-44s %-10s %s\n" "----" "-------" "--------" "--------"

for i in "${!NAMES[@]}"; do
    name="${NAMES[$i]}"
    addr="${ADDRS[$i]}"

    if [ -n "$PROBE_ADDR" ] && [ "${PROBE_ADDR,,}" != "${addr,,}" ]; then
        continue
    fi

    # codesize via RPC (skip if no RPC for this chain)
    cs="?"
    if [ -n "$rpc_url" ]; then
        cs=$(cast codesize --rpc-url "$rpc_url" "$addr" 2>/dev/null || echo "?")
    fi

    # verification via Etherscan v2 multichain API
    resp=$(curl -fsS --max-time 15 \
        "https://api.etherscan.io/v2/api?chainid=${CHAIN_ID}&module=contract&action=getsourcecode&address=${addr}&apikey=${ETHERSCAN_API_KEY}" 2>/dev/null)
    src_len=$(echo "$resp" | jq -r '.result[0].SourceCode // ""' | wc -c | awk '{print $1}')
    verified_name=$(echo "$resp" | jq -r '.result[0].ContractName // ""')
    if [ "$src_len" -gt 1 ]; then
        verified="${GREEN}YES${NC} (${verified_name})"
    else
        verified="${RED}NO${NC}"
    fi
    printf "%-26s %-44s %-10s %b\n" "$name" "$addr" "$cs" "$verified"
done
