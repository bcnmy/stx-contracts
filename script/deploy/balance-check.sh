#!/bin/bash

# balance-check.sh
# Iterate target chains, query deployer balance on each, and flag low balances.
#
# Reads chain IDs from CLI args (or all chains in config.toml if none given).
# Reads RPC URLs from .env (RPC_<chain_id>).
# Deployer address: pass as first positional arg, or set DEPLOYER_ADDRESS env var.
#
# Usage:
#   bash balance-check.sh 0xDeployerAddress 84532 11155420 1 137
#   bash balance-check.sh 0xDeployerAddress               # uses all chains in config.toml
#   DEPLOYER_ADDRESS=0x... bash balance-check.sh         # via env var
#
# Output: chain | balance (eth) | status (OK / LOW / NO_RPC / UNREACHABLE)
#
# Tunables:
#   MIN_BALANCE_WEI  (default: 0.05 ETH) — below this triggers LOW
#   TIMEOUT_SEC      (default: 10) — per-RPC timeout

set -u

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Load env
ENV_FILE="$(cd "$(dirname "$0")/../.." && pwd)/.env"
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}.env not found at $ENV_FILE${NC}" >&2
    exit 1
fi
set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

# Parse args
DEPLOYER="${DEPLOYER_ADDRESS:-}"
if [[ "${1:-}" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
    DEPLOYER="$1"
    shift
fi
if [ -z "$DEPLOYER" ]; then
    echo -e "${RED}Deployer address required (first arg or DEPLOYER_ADDRESS env var)${NC}" >&2
    echo "Usage: bash balance-check.sh 0xDeployerAddress [chainId1] [chainId2] ..." >&2
    exit 1
fi

CHAIN_IDS=("$@")
if [ ${#CHAIN_IDS[@]} -eq 0 ]; then
    # Default: every chain id in config.toml
    while IFS= read -r line; do
        CHAIN_IDS+=("$line")
    done < <(grep -E '^\[[0-9]+\]$' "$(dirname "$0")/config.toml" | tr -d '[]')
fi

MIN_BALANCE_WEI="${MIN_BALANCE_WEI:-50000000000000000}"  # 0.05 ETH
TIMEOUT_SEC="${TIMEOUT_SEC:-10}"

# Portable timeout: gtimeout on macOS (brew install coreutils), timeout on Linux,
# or no timeout wrapper if neither is available. cast balance against public RPCs
# usually responds in <2s anyway.
TIMEOUT_CMD=""
if command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_CMD="gtimeout $TIMEOUT_SEC"
elif command -v timeout >/dev/null 2>&1; then
    TIMEOUT_CMD="timeout $TIMEOUT_SEC"
fi

echo -e "${BLUE}Deployer:${NC}        $DEPLOYER"
echo -e "${BLUE}Chains:${NC}          ${#CHAIN_IDS[@]}"
echo -e "${BLUE}Low threshold:${NC}   $(cast from-wei "$MIN_BALANCE_WEI") ETH"
echo ""
printf "%-12s %-22s %-32s %s\n" "CHAIN_ID" "NAME" "BALANCE (native)" "STATUS"
printf "%-12s %-22s %-32s %s\n" "--------" "----" "----------------" "------"

low_chains=()
unreachable_chains=()

for cid in "${CHAIN_IDS[@]}"; do
    # Chain name from config.toml. The toml uses nested sections like [1], [1.bool],
    # [1.string], etc., so we match any section whose top-level id is $cid.
    name=$(awk -v cid="$cid" '
        $0=="["cid"]" || $0=="["cid".bool]" || $0=="["cid".uint]" || $0=="["cid".string]" { in_block=1; next }
        /^\[/ { in_block=0 }
        in_block && /name = "/ {
            n=$0; sub(/.*name = "/,"",n); sub(/".*/,"",n); print n; exit
        }
    ' "$(dirname "$0")/config.toml")
    [ -z "$name" ] && name="(unknown)"

    rpc_var="RPC_${cid}"
    rpc_url="${!rpc_var:-}"
    if [ -z "$rpc_url" ]; then
        printf "%-12s %-22s %-32s ${YELLOW}NO_RPC${NC}\n" "$cid" "$name" "—"
        unreachable_chains+=("$cid:$name (no $rpc_var)")
        continue
    fi

    # Query balance with timeout. Capture stderr to a temp file so we can
    # surface a short diagnostic without leaking the full RPC URL.
    err_file=$(mktemp)
    bal_wei=$($TIMEOUT_CMD cast balance --rpc-url "$rpc_url" "$DEPLOYER" 2>"$err_file" || true)
    if [ -z "$bal_wei" ] || ! [[ "$bal_wei" =~ ^[0-9]+$ ]]; then
        # Try to summarize cause in <= 40 chars without exposing the URL.
        err_summary=$(head -c 400 "$err_file" | tr '\n' ' ' | sed -E 's|https?://[^[:space:]]+|<rpc>|g' | head -c 90)
        rm -f "$err_file"
        printf "%-12s %-22s %-32s ${RED}UNREACHABLE${NC}  %s\n" "$cid" "$name" "—" "$err_summary"
        unreachable_chains+=("$cid:$name -- $err_summary")
        continue
    fi
    rm -f "$err_file"

    bal_eth=$(cast from-wei "$bal_wei" 2>/dev/null || echo "?")
    if [ "$(echo "$bal_wei < $MIN_BALANCE_WEI" | bc 2>/dev/null || echo 0)" -eq 1 ]; then
        printf "%-12s %-22s %-32s ${YELLOW}LOW${NC}\n" "$cid" "$name" "$bal_eth"
        low_chains+=("$cid:$name ($bal_eth)")
    else
        printf "%-12s %-22s %-32s ${GREEN}OK${NC}\n" "$cid" "$name" "$bal_eth"
    fi
done

echo ""
if [ ${#low_chains[@]} -gt 0 ]; then
    echo -e "${YELLOW}Low-balance chains (need funding):${NC}"
    for c in "${low_chains[@]}"; do echo "  - $c"; done
fi
if [ ${#unreachable_chains[@]} -gt 0 ]; then
    echo -e "${RED}Unreachable / no RPC:${NC}"
    for c in "${unreachable_chains[@]}"; do echo "  - $c"; done
fi
if [ ${#low_chains[@]} -eq 0 ] && [ ${#unreachable_chains[@]} -eq 0 ]; then
    echo -e "${GREEN}All chains funded and reachable.${NC}"
fi
