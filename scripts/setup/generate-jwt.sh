#!/usr/bin/env bash
set -euo pipefail

# Generate JWT Secret
# Usage: ./generate-jwt.sh [environment]

ENV=${1:-mainnet}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
JWT_FILE="$PROJECT_ROOT/security/jwt/$ENV/jwt.hex"

if [ -f "$JWT_FILE" ]; then
    read -p "JWT file already exists. Overwrite? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

echo "🔐 Generating JWT secret for $ENV..."
openssl rand -hex 32 | tr -d "\n" > "$JWT_FILE"
chmod 600 "$JWT_FILE"
echo "✅ JWT secret generated: $JWT_FILE"

