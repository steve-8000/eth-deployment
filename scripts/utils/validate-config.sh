#!/usr/bin/env bash
set -euo pipefail

# Validate Configuration
# Usage: ./validate-config.sh [environment]

ENV=${1:-mainnet}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/config/environments/$ENV/.env"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Configuration file not found: $CONFIG_FILE"
    echo "   Run: make setup ENV=$ENV"
    exit 1
fi

# Source config
set -a
source "$CONFIG_FILE"
set +a

# Validate required variables
REQUIRED_VARS=(
    "NETWORK"
    "GETH_VERSION"
    "LIGHTHOUSE_VERSION"
    "TEKU_VERSION"
)

MISSING_VARS=()
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var:-}" ]; then
        MISSING_VARS+=("$var")
    fi
done

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    echo "❌ Missing required environment variables:"
    printf '   - %s\n' "${MISSING_VARS[@]}"
    exit 1
fi

# Validate JWT file
JWT_FILE="$PROJECT_ROOT/security/jwt/$ENV/jwt.hex"
if [ ! -f "$JWT_FILE" ]; then
    echo "❌ JWT file not found: $JWT_FILE"
    echo "   Run: make setup-jwt ENV=$ENV"
    exit 1
fi

echo "✅ Configuration validation passed"

