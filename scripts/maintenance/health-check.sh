#!/usr/bin/env bash
set -euo pipefail

# Health Check Script
# Usage: ./health-check.sh [environment]

ENV=${1:-mainnet}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source environment config
CONFIG_FILE="$PROJECT_ROOT/config/environments/$ENV/.env"
if [ -f "$CONFIG_FILE" ]; then
    set -a
    source "$CONFIG_FILE"
    set +a
fi

echo "🏥 Running health checks for $ENV..."
echo ""

# Check Docker Compose services
echo "📊 Checking Docker services..."
if docker compose ps 2>/dev/null | grep -q "Up"; then
    echo "  ✅ Docker services are running"
    docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
else
    echo "  ⚠️  No Docker services found"
fi

echo ""

# Check ports
echo "🔌 Checking ports..."
PORTS=("${EC_PORT_HTTP:-8545}" "${CC_PORT_HTTP:-5052}" "${VC_PORT_HTTP:-5062}")
for port in "${PORTS[@]}"; do
    if nc -z localhost "$port" 2>/dev/null; then
        echo "  ✅ Port $port is open"
    else
        echo "  ❌ Port $port is closed"
    fi
done

echo ""

# Check disk space
echo "💾 Checking disk space..."
df -h "$PROJECT_ROOT/data" 2>/dev/null | tail -n 1 | awk '{print "  Available: " $4 " / " $2 " (" $5 " used)"}'

echo ""
echo "✅ Health check complete"

