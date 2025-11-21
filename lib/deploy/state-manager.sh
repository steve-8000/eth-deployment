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
    
    # Check Execution Clients (using unified service name)
    if grep -q "execution-client:" "$compose_file"; then
        # Check container_name or image to determine actual client
        if grep -q "container_name: geth-" "$compose_file" || grep -q "ethereum/client-go" "$compose_file"; then
            config+='"ec":"geth",'
        elif grep -q "container_name: nethermind-" "$compose_file" || grep -q "nethermind/nethermind" "$compose_file"; then
            config+='"ec":"nethermind",'
        elif grep -q "container_name: reth-" "$compose_file" || grep -q "paradigmxyz/reth" "$compose_file"; then
            config+='"ec":"reth",'
        fi
    fi
    
    # Check Consensus Clients (using unified service name)
    if grep -q "consensus-client:" "$compose_file"; then
        # Check container_name or image to determine actual client
        if grep -q "container_name: lighthouse-" "$compose_file" || grep -q "sigp/lighthouse" "$compose_file"; then
            config+='"cc":"lighthouse",'
        elif grep -q "container_name: teku-" "$compose_file" || grep -q "consensys/teku" "$compose_file"; then
            config+='"cc":"teku",'
        elif grep -q "container_name: prysm-" "$compose_file" || grep -q "prysmaticlabs/prysm" "$compose_file"; then
            config+='"cc":"prysm",'
        elif grep -q "container_name: lodestar-" "$compose_file" || grep -q "chainsafe/lodestar" "$compose_file"; then
            config+='"cc":"lodestar",'
        fi
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

# Get container info (version and status)
get_container_info() {
    local service_name="$1"
    local compose_file="$PROJECT_ROOT/docker-compose.generated.yaml"
    
    if [ ! -f "$compose_file" ]; then
        echo ""
        return
    fi
    
    # Get container name from compose file or use service name
    local container_name=""
    if command_exists docker; then
        # Try to find running container by service name
        container_name=$(docker compose -f "$compose_file" ps --format "{{.Name}}" "$service_name" 2>/dev/null | head -1)
        
        if [ -z "$container_name" ]; then
            # Try alternative: find by service name pattern
            container_name=$(docker ps --filter "label=com.docker.compose.service=$service_name" --format "{{.Names}}" 2>/dev/null | head -1)
        fi
        
        if [ -z "$container_name" ]; then
            # Try to find by unified container name pattern
            case "$service_name" in
                execution-client)
                    container_name=$(docker ps --filter "name=execution-client-" --format "{{.Names}}" 2>/dev/null | head -1)
                    ;;
                consensus-client)
                    container_name=$(docker ps --filter "name=consensus-client-" --format "{{.Names}}" 2>/dev/null | head -1)
                    ;;
                mev-boost)
                    container_name=$(docker ps --filter "name=mev-boost-" --format "{{.Names}}" 2>/dev/null | head -1)
                    ;;
                validator-client|*-vc)
                    container_name=$(docker ps --filter "name=validator-client-" --format "{{.Names}}" 2>/dev/null | head -1)
                    ;;
            esac
        fi
    fi
    
    if [ -z "$container_name" ]; then
        echo ""
        return
    fi
    
    # Get container info
    local container_info=$(docker inspect "$container_name" 2>/dev/null)
    if [ -z "$container_info" ]; then
        echo ""
        return
    fi
    
    # Extract uptime
    local started_at=""
    local image_version=""
    
    if command_exists jq && echo "$container_info" | jq -e . >/dev/null 2>&1; then
        started_at=$(echo "$container_info" | jq -r '.[0].State.StartedAt' 2>/dev/null)
        image_version=$(echo "$container_info" | jq -r '.[0].Config.Image' 2>/dev/null)
    else
        # Fallback without jq
        started_at=$(echo "$container_info" | grep -o '"StartedAt":"[^"]*"' | cut -d'"' -f4 2>/dev/null)
        image_version=$(echo "$container_info" | grep -o '"Image":"[^"]*"' | cut -d'"' -f4 2>/dev/null)
    fi
    
    # Calculate uptime
    local uptime_str=""
    if [ -n "$started_at" ] && [ "$started_at" != "null" ] && [ "$started_at" != "0001-01-01T00:00:00Z" ]; then
        # Parse ISO 8601 timestamp and calculate uptime
        if date -d "$started_at" >/dev/null 2>&1; then
            # GNU date (Linux)
            local started_epoch=$(date -d "$started_at" +%s 2>/dev/null)
        elif date -j -f "%Y-%m-%dT%H:%M:%S" "${started_at%Z}" +%s >/dev/null 2>&1; then
            # BSD date (macOS)
            local started_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${started_at%Z}" +%s 2>/dev/null)
        else
            # Fallback: try to parse with date command
            local started_epoch=$(date +%s -d "$started_at" 2>/dev/null || echo "")
        fi
        
        if [ -n "$started_epoch" ]; then
            local current_epoch=$(date +%s)
            local uptime_seconds=$((current_epoch - started_epoch))
            
            if [ $uptime_seconds -gt 0 ]; then
                local days=$((uptime_seconds / 86400))
                local hours=$(((uptime_seconds % 86400) / 3600))
                local minutes=$(((uptime_seconds % 3600) / 60))
                
                if [ $days -gt 0 ]; then
                    uptime_str="${days}d ${hours}h"
                elif [ $hours -gt 0 ]; then
                    uptime_str="${hours}h ${minutes}m"
                else
                    uptime_str="${minutes}m"
                fi
            fi
        fi
    fi
    
    # Extract version from image (e.g., "nethermind/nethermind:1.35.2" -> "1.35.2")
    local version=""
    if [ -n "$image_version" ] && [ "$image_version" != "null" ]; then
        version=$(echo "$image_version" | sed 's/.*://' | sed 's/^v//')
    fi
    
    # Get container status from docker compose ps
    local status=""
    if [ -n "$container_name" ]; then
        status=$(docker compose -f "$compose_file" ps --format "{{.Status}}" "$service_name" 2>/dev/null | head -1)
        if [ -z "$status" ]; then
            # Try alternative method
            status=$(docker ps --filter "name=$container_name" --format "{{.Status}}" 2>/dev/null | head -1)
        fi
    fi
    
    # Parse status to extract health status and uptime
    local health_status=""
    local status_uptime=""
    
    if [ -n "$status" ]; then
        # Extract health status (healthy, unhealthy, starting, etc.)
        if echo "$status" | grep -q "healthy"; then
            health_status="healthy"
        elif echo "$status" | grep -q "unhealthy"; then
            health_status="unhealthy"
        elif echo "$status" | grep -q "starting"; then
            health_status="starting"
        elif echo "$status" | grep -q "Restarting"; then
            health_status="restarting"
        elif echo "$status" | grep -q "Exited"; then
            health_status="exited"
        elif echo "$status" | grep -q "Up"; then
            health_status="running"
        else
            health_status="unknown"
        fi
        
        # Extract uptime from status if available (e.g., "Up 5 minutes", "Up 2 hours")
        # Handle formats like "Up 3 minutes (health: starting)" -> extract only "3 minutes"
        if echo "$status" | grep -qE "Up [0-9]+"; then
            # Extract uptime: match "Up X minutes" or "Up X hours" or "Up X seconds" before any parentheses
            if echo "$status" | grep -qE "Up [0-9]+ (seconds|minutes|hours|days)"; then
                status_uptime=$(echo "$status" | sed -E 's/.*Up ([0-9]+ (seconds?|minutes?|hours?|days?)).*/\1/' | head -1)
            else
                # Fallback: extract just the number and unit if format is different
                status_uptime=$(echo "$status" | sed -E 's/.*Up ([0-9]+[^ (]*).*/\1/' | sed 's/ (health:.*//' | sed 's/ (unhealthy.*//' | head -1)
            fi
            # Clean up: remove any trailing spaces
            status_uptime=$(echo "$status_uptime" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        fi
    fi
    
    # Use status uptime if available, otherwise use calculated uptime
    local display_uptime="${status_uptime:-${uptime_str}}"
    
    # Format output: "Version: 1.35.2 | STATUS: healthy(1m)"
    local output=""
    
    if [ -n "$version" ] && [ -n "$health_status" ]; then
        if [ -n "$display_uptime" ]; then
            output="Version: ${version} | STATUS: ${health_status}(${display_uptime})"
        else
            output="Version: ${version} | STATUS: ${health_status}"
        fi
    elif [ -n "$version" ]; then
        if [ -n "$display_uptime" ]; then
            output="Version: ${version} | Uptime: ${display_uptime}"
        else
            output="Version: ${version}"
        fi
    elif [ -n "$health_status" ]; then
        if [ -n "$display_uptime" ]; then
            output="STATUS: ${health_status}(${display_uptime})"
        else
            output="STATUS: ${health_status}"
        fi
    elif [ -n "$display_uptime" ]; then
        output="Uptime: ${display_uptime}"
    fi
    
    if [ -n "$output" ]; then
        echo " (${output})"
    else
        echo ""
    fi
}

