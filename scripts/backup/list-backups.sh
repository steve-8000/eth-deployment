#!/usr/bin/env bash
set -euo pipefail

# List Available Backups
# Usage: ./list-backups.sh [environment]

ENV=${1:-mainnet}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BACKUP_DIR="$PROJECT_ROOT/data/backups/$ENV"

if [ ! -d "$BACKUP_DIR" ]; then
    echo "❌ No backups found for $ENV"
    exit 1
fi

echo "📦 Available backups for $ENV:"
echo ""

# List backups with details
for manifest in "$BACKUP_DIR"/*-manifest.txt; do
    if [ -f "$manifest" ]; then
        backup_name=$(basename "$manifest" -manifest.txt)
        echo "  📋 $backup_name"
        echo "     $(head -n 3 "$manifest" | tail -n 1)"
        echo ""
    fi
done

