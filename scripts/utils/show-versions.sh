#!/usr/bin/env bash
set -euo pipefail

# Show Client Versions
# Usage: ./show-versions.sh [environment]

ENV=${1:-mainnet}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/config/environments/$ENV/.env"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Source config
set -a
source "$CONFIG_FILE"
set +a

echo "📦 Client Versions for $ENV:"
echo ""
echo "Execution Clients:"
echo "  Geth:        ${GETH_VERSION:-not set}"
echo "  Nethermind:  ${NETHERMIND_VERSION:-not set}"
echo "  Reth:        ${RETH_VERSION:-not set}"
echo ""
echo "Consensus Clients:"
echo "  Lighthouse:  ${LIGHTHOUSE_VERSION:-not set}"
echo "  Teku:        ${TEKU_VERSION:-not set}"
echo "  Prysm:       ${PRYSM_VERSION:-not set}"
echo "  Lodestar:    ${LODESTAR_VERSION:-not set}"
echo ""
echo "Validator Clients & Tools:"
echo "  Web3Signer:  ${WEB3SIGNER_VERSION:-not set}"
echo "  MEV-Boost:   ${MEVBOOST_VERSION:-not set}"
echo "  Commit Boost: ${COMMITBOOST_VERSION:-not set}"
echo ""
echo "DVT Clients:"
echo "  Charon:      ${CHARON_VERSION:-not set}"
echo "  SSV:         ${SSV_VERSION:-not set}"
echo "  SSV DKG:     ${SSV_DKG_VERSION:-not set}"
echo ""
echo "Other Services:"
echo "  Stakewise:   ${STAKEWISE_VERSION:-not set}"

