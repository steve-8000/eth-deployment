#!/usr/bin/env bash
set -euo pipefail

# Backup Ethereum Node Data
# Usage: ./backup.sh [environment]

ENV=${1:-mainnet}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BACKUP_DIR="$PROJECT_ROOT/data/backups/$ENV"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME="backup-$TIMESTAMP"

mkdir -p "$BACKUP_DIR"

echo "💾 Creating backup: $BACKUP_NAME"

# Backup chain data
if [ -d "$PROJECT_ROOT/data/chains/$ENV" ]; then
    echo "  📦 Backing up chain data..."
    tar -czf "$BACKUP_DIR/$BACKUP_NAME-chains.tar.gz" \
        -C "$PROJECT_ROOT/data/chains" "$ENV" 2>/dev/null || true
fi

# Backup keys
if [ -d "$PROJECT_ROOT/data/keys/$ENV" ]; then
    echo "  🔐 Backing up keys..."
    tar -czf "$BACKUP_DIR/$BACKUP_NAME-keys.tar.gz" \
        -C "$PROJECT_ROOT/data/keys" "$ENV" 2>/dev/null || true
fi

# Backup configuration
if [ -f "$PROJECT_ROOT/config/environments/$ENV/.env" ]; then
    echo "  ⚙️  Backing up configuration..."
    cp "$PROJECT_ROOT/config/environments/$ENV/.env" \
       "$BACKUP_DIR/$BACKUP_NAME.env"
fi

# Create manifest
cat > "$BACKUP_DIR/$BACKUP_NAME-manifest.txt" <<EOF
Backup Information
==================
Environment: $ENV
Timestamp: $TIMESTAMP
Date: $(date)

Contents:
- Chain data: $BACKUP_NAME-chains.tar.gz
- Keys: $BACKUP_NAME-keys.tar.gz
- Configuration: $BACKUP_NAME.env
EOF

echo "✅ Backup complete: $BACKUP_DIR/$BACKUP_NAME-*"
echo "📋 Manifest: $BACKUP_DIR/$BACKUP_NAME-manifest.txt"

