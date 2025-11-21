#!/usr/bin/env bash
set -euo pipefail

# Initialize Ethereum Node Infrastructure
# Usage: ./init.sh [environment]

ENV=${1:-mainnet}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "🚀 Initializing Ethereum Node Infrastructure for $ENV environment..."

# Create directory structure
echo "📁 Creating directory structure..."
mkdir -p "$PROJECT_ROOT/data/chains/$ENV"
mkdir -p "$PROJECT_ROOT/data/keys/$ENV"
mkdir -p "$PROJECT_ROOT/data/logs/$ENV"
mkdir -p "$PROJECT_ROOT/data/backups/$ENV"
mkdir -p "$PROJECT_ROOT/security/jwt/$ENV"
mkdir -p "$PROJECT_ROOT/security/keys/$ENV"
mkdir -p "$PROJECT_ROOT/config/environments/$ENV"

# Generate JWT if not exists
if [ ! -f "$PROJECT_ROOT/security/jwt/$ENV/jwt.hex" ]; then
    echo "🔐 Generating JWT secret..."
    openssl rand -hex 32 | tr -d "\n" > "$PROJECT_ROOT/security/jwt/$ENV/jwt.hex"
    chmod 600 "$PROJECT_ROOT/security/jwt/$ENV/jwt.hex"
    echo "✅ JWT secret generated"
else
    echo "ℹ️  JWT secret already exists"
fi

# Copy environment config if not exists
if [ ! -f "$PROJECT_ROOT/config/environments/$ENV/.env" ]; then
    echo "📋 Creating environment configuration..."
    cp "$PROJECT_ROOT/config/environments/.env.example" "$PROJECT_ROOT/config/environments/$ENV/.env"
    echo "⚠️  Please edit config/environments/$ENV/.env with your settings"
else
    echo "ℹ️  Environment configuration already exists"
fi

# Set permissions
echo "🔒 Setting permissions..."
chmod 700 "$PROJECT_ROOT/security"
chmod 600 "$PROJECT_ROOT/security/jwt/$ENV/jwt.hex" 2>/dev/null || true

echo "✅ Initialization complete!"
echo ""
echo "Next steps:"
echo "  1. Edit config/environments/$ENV/.env"
echo "  2. Run: make setup-keys"
echo "  3. Run: make deploy ENV=$ENV"

