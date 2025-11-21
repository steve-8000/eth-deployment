#!/usr/bin/env bash
set -euo pipefail

# State Management System
# Manages deployment state, history, and current status

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_DIR="$PROJECT_ROOT/config"
STATE_DIR="$PROJECT_ROOT/.deploy"
LOG_FILE="$STATE_DIR/deployment.log"
CURRENT_STATE="$STATE_DIR/current.json"
HISTORY_DIR="$STATE_DIR/history"

# Source utilities
if [ ! -f "$SCRIPT_DIR/utils.sh" ]; then
    echo "Error: utils.sh not found at $SCRIPT_DIR/utils.sh" >&2
    exit 1
fi
source "$SCRIPT_DIR/utils.sh"

# Initialize state directory
init_state() {
    mkdir -p "$STATE_DIR"
    mkdir -p "$HISTORY_DIR"
    touch "$LOG_FILE"
}

# Log deployment action
log_deployment() {
    local action="$1"
    local config="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    init_state
    
    echo "[$timestamp] $action: $config" >> "$LOG_FILE"
    
    # Save to history with timestamp
    local history_file="$HISTORY_DIR/$(date '+%Y%m%d-%H%M%S')-${action}.json"
    echo "$config" > "$history_file"
}

# Save current deployment state
save_state() {
    local config_json="$1"
    
    init_state
    echo "$config_json" > "$CURRENT_STATE"
}

# Load current deployment state
load_state() {
    if [ -f "$CURRENT_STATE" ]; then
        cat "$CURRENT_STATE"
    else
        echo "{}"
    fi
}

# Get deployment history
get_history() {
    local limit="${1:-10}"
    
    if [ -d "$HISTORY_DIR" ]; then
        find "$HISTORY_DIR" -name "*.json" -type f | sort -r | head -n "$limit"
    fi
}

# Get last deployment config
get_last_deployment() {
    local last_file=$(get_history 1 | head -n 1)
    if [ -n "$last_file" ] && [ -f "$last_file" ]; then
        cat "$last_file"
    else
        echo "{}"
    fi
}

# Check if deployment exists
is_deployed() {
    local compose_file="$PROJECT_ROOT/docker-compose.generated.yaml"
    
    if [ ! -f "$compose_file" ]; then
        return 1
    fi
    
    # Check if any services are running
    if docker compose -f "$compose_file" ps --format json 2>/dev/null | grep -q '"State":"running"'; then
        return 0
    fi
    
    return 1
}

# Get running services info
get_running_services() {
    local compose_file="$PROJECT_ROOT/docker-compose.generated.yaml"
    
    if [ ! -f "$compose_file" ]; then
        echo "[]"
        return
    fi
    
    # Try jq first, fallback to plain docker ps
    if command_exists jq; then
        docker compose -f "$compose_file" ps --format json 2>/dev/null | \
        jq -s '[.[] | {name: .Name, service: .Service, state: .State, status: .Status}]' 2>/dev/null || echo "[]"
    else
        # Fallback: return formatted text
        docker compose -f "$compose_file" ps --format "{{.Name}}|{{.Service}}|{{.State}}|{{.Status}}" 2>/dev/null || echo ""
    fi
}

# Detect current deployment configuration
detect_current_config() {
    local compose_file="$PROJECT_ROOT/docker-compose.generated.yaml"
    
    if [ ! -f "$compose_file" ]; then
        echo "{}"
        return
    fi
    
    # Extract service names and infer configuration
    local config="{"
    
    # Check Execution Clients
    if grep -q "geth:" "$compose_file"; then
        config+='"ec":"geth",'
    elif grep -q "nethermind:" "$compose_file"; then
        config+='"ec":"nethermind",'
    elif grep -q "reth:" "$compose_file"; then
        config+='"ec":"reth",'
    fi
    
    # Check Consensus Clients
    if grep -q "lighthouse:" "$compose_file" && ! grep -q "lighthouse-vc:" "$compose_file"; then
        config+='"cc":"lighthouse",'
    elif grep -q "teku:" "$compose_file" && ! grep -q "teku-vc:" "$compose_file"; then
        config+='"cc":"teku",'
    elif grep -q "prysm:" "$compose_file"; then
        config+='"cc":"prysm",'
    elif grep -q "lodestar:" "$compose_file" && ! grep -q "lodestar-vc:" "$compose_file"; then
        config+='"cc":"lodestar",'
    fi
    
    # Check MEV
    if grep -q "mev-boost:" "$compose_file"; then
        config+='"mev":"mevboost",'
    fi
    if grep -q "commit-boost:" "$compose_file"; then
        if [[ "$config" == *"mevboost"* ]]; then
            config=$(echo "$config" | sed 's/"mev":"mevboost",/"mev":"both",/')
        else
            config+='"mev":"commitboost",'
        fi
    fi
    
    # Check Validator Clients / DVT
    if grep -q "lighthouse-vc:" "$compose_file"; then
        config+='"vc":"lighthouse",'
    elif grep -q "teku-vc:" "$compose_file"; then
        config+='"vc":"teku",'
    elif grep -q "lodestar-vc:" "$compose_file"; then
        config+='"vc":"lodestar",'
    elif grep -q "charon:" "$compose_file"; then
        config+='"dvt":"obol",'
    elif grep -q "ssv-node:" "$compose_file"; then
        config+='"dvt":"ssv",'
    elif grep -q "web3signer:" "$compose_file"; then
        config+='"vc":"web3signer",'
    fi
    
    # Extract network from environment variable, compose file, or config
    local network="mainnet"
    
    # Try to get from environment variable first
    if [ -n "${NETWORK:-}" ]; then
        network="$NETWORK"
    elif [ -n "${ENV:-}" ]; then
        network="$ENV"
    # Try to get from .env file
    elif [ -f "$PROJECT_ROOT/.env" ]; then
        local env_network=$(grep -E "^NETWORK=" "$PROJECT_ROOT/.env" 2>/dev/null | head -1 | cut -d'=' -f2 | tr -d '"' | tr -d "'" | tr -d ' ' || echo "")
        if [ -n "$env_network" ]; then
            network="$env_network"
        fi
    # Try to get from deployment config
    elif [ -f "$CONFIG_DIR/.deployment" ]; then
        local config_network=$(grep -E "^SELECTED_NETWORK=" "$CONFIG_DIR/.deployment" 2>/dev/null | head -1 | cut -d'=' -f2 | tr -d '"' | tr -d "'" | tr -d ' ' || echo "")
        if [ -n "$config_network" ]; then
            network="$config_network"
        fi
    # Last resort: try to extract from compose file
    else
        local compose_network=$(grep -E "NETWORK=|network=" "$compose_file" 2>/dev/null | head -1 | sed -E 's/.*NETWORK=|.*network=([^ ]+).*/\1/' | tr -d '"' | tr -d "'" || echo "")
        if [ -n "$compose_network" ]; then
            network="$compose_network"
        fi
    fi
    
    # Remove trailing comma if exists before adding network
    config="${config%,}"
    config+=",\"network\":\"${network}\""
    
    config+="}"
    echo "$config"
}

# Format deployment info for display
format_deployment_info() {
    local config_json="$1"
    
    if [ "$config_json" = "{}" ] || [ -z "$config_json" ]; then
        echo "No deployment found"
        return
    fi
    
    # Try jq first, fallback to grep/sed
    if command_exists jq; then
        local network=$(echo "$config_json" | jq -r '.network // "unknown"')
        local ec=$(echo "$config_json" | jq -r '.ec // "none"')
        local cc=$(echo "$config_json" | jq -r '.cc // "none"')
        local mev=$(echo "$config_json" | jq -r '.mev // "none"')
        local vc=$(echo "$config_json" | jq -r '.vc // "none"')
        local dvt=$(echo "$config_json" | jq -r '.dvt // "none"')
    else
        # Fallback parsing
        local network=$(echo "$config_json" | grep -o '"network":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
        local ec=$(echo "$config_json" | grep -o '"ec":"[^"]*"' | cut -d'"' -f4 || echo "none")
        local cc=$(echo "$config_json" | grep -o '"cc":"[^"]*"' | cut -d'"' -f4 || echo "none")
        local mev=$(echo "$config_json" | grep -o '"mev":"[^"]*"' | cut -d'"' -f4 || echo "none")
        local vc=$(echo "$config_json" | grep -o '"vc":"[^"]*"' | cut -d'"' -f4 || echo "none")
        local dvt=$(echo "$config_json" | grep -o '"dvt":"[^"]*"' | cut -d'"' -f4 || echo "none")
    fi
    
    echo "Network:     ${network:-unknown}"
    echo "EC:          ${ec:-none}"
    echo "CC:          ${cc:-none}"
    echo "MEV:         ${mev:-none}"
    if [ "${vc:-none}" != "none" ] && [ -n "${vc}" ]; then
        echo "VC:          $vc"
    fi
    if [ "${dvt:-none}" != "none" ] && [ -n "${dvt}" ]; then
        echo "DVT:         $dvt"
    fi
}

