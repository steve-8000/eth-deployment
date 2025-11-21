#!/usr/bin/env bash
set -euo pipefail

# Environment Setup Script
# Automatically creates environment configuration from template

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_DIR="$PROJECT_ROOT/config"

source "$SCRIPT_DIR/utils.sh"

setup_environment() {
    local network="$1"
    local env_file="$PROJECT_ROOT/.env"
    
    print_info "Setting up environment for $network..."
    
    # Copy template if exists
    if [ -f "$PROJECT_ROOT/.env.example" ]; then
        if [ ! -f "$env_file" ]; then
            cp "$PROJECT_ROOT/.env.example" "$env_file"
            # Update NETWORK variable
            sed -i.bak "s/^NETWORK=.*/NETWORK=$network/" "$env_file" 2>/dev/null || \
            sed -i '' "s/^NETWORK=.*/NETWORK=$network/" "$env_file" 2>/dev/null || true
            rm -f "$env_file.bak" 2>/dev/null || true
            print_success "Created environment config from template: $env_file"
        else
            print_info "Environment config already exists: $env_file"
        fi
    else
        print_warning "Template not found. Creating minimal config..."
        cat > "$env_file" <<EOF
# Network Configuration
NETWORK=$network

# Client Versions
GETH_VERSION=v1.16.7
NETHERMIND_VERSION=1.35.2
RETH_VERSION=v1.9.1
LIGHTHOUSE_VERSION=v8.0.0
TEKU_VERSION=25.11.0
PRYSM_VERSION=v7.0.0
LODESTAR_VERSION=v1.36.0
WEB3SIGNER_VERSION=25.11.0
MEVBOOST_VERSION=v1.10.1
COMMITBOOST_VERSION=v0.9.0
CHARON_VERSION=v1.7.0
SSV_VERSION=v2.3.7
SSV_DKG_VERSION=v3.2.0

# Ports
EC_PORT_P2P=30303
EC_PORT_HTTP=8545
EC_PORT_WS=8546
EC_PORT_ENGINE=8551
EC_PORT_METRIC=6060

CC_PORT_P2P=9000
CC_PORT_QUIC=9001
CC_PORT_HTTP=5052
CC_PORT_METRICS=5054

VC_PORT_HTTP=5062
VC_PORT_METRICS=5064

# Network Endpoints
CC_EXECUTION_ENDPOINT=http://execution-client:8551
CC_CHECKPOINT_SYNC_URL=https://sync-mainnet.beaconcha.in
CC_SUGGESTED_FEE_RECIPIENT=0x0000000000000000000000000000000000000000
CC_MEV_BOOST_ADDRESS=http://mev-boost:18550

VC_BEACON_NODE_ADDRESS=http://consensus-client:5052
VC_SUGGESTED_FEE_RECIPIENT=0x0000000000000000000000000000000000000000
VC_DEFAULT_GRAFFITI=A41

# MEV Configuration
MEVBOOST_RELAYS=""
MEVBOOST_LOG_LEVEL=info
MEVBOOST_GETHEADER_TIMEOUT=1000
MEVBOOST_GETPAYLOAD_TIMEOUT=4000
MEVBOOST_REGVAL_TIMEOUT=3000
EOF
        print_success "Created minimal environment config"
    fi
    
    # Update network-specific settings (cross-platform sed)
    case $network in
        mainnet)
            if sed --version >/dev/null 2>&1; then
                # GNU sed (Linux)
                sed -i 's|CC_CHECKPOINT_SYNC_URL=.*|CC_CHECKPOINT_SYNC_URL=https://sync-mainnet.beaconcha.in|' "$env_file" 2>/dev/null || true
            else
                # BSD sed (macOS)
                sed -i '' 's|CC_CHECKPOINT_SYNC_URL=.*|CC_CHECKPOINT_SYNC_URL=https://sync-mainnet.beaconcha.in|' "$env_file" 2>/dev/null || true
            fi
            ;;
        sepolia)
            if sed --version >/dev/null 2>&1; then
                sed -i 's|CC_CHECKPOINT_SYNC_URL=.*|CC_CHECKPOINT_SYNC_URL=https://sync-sepolia.beaconcha.in|' "$env_file" 2>/dev/null || true
            else
                sed -i '' 's|CC_CHECKPOINT_SYNC_URL=.*|CC_CHECKPOINT_SYNC_URL=https://sync-sepolia.beaconcha.in|' "$env_file" 2>/dev/null || true
            fi
            ;;
        holesky)
            if sed --version >/dev/null 2>&1; then
                sed -i 's|CC_CHECKPOINT_SYNC_URL=.*|CC_CHECKPOINT_SYNC_URL=https://sync-holesky.beaconcha.in|' "$env_file" 2>/dev/null || true
            else
                sed -i '' 's|CC_CHECKPOINT_SYNC_URL=.*|CC_CHECKPOINT_SYNC_URL=https://sync-holesky.beaconcha.in|' "$env_file" 2>/dev/null || true
            fi
            ;;
    esac
    
    print_success "Environment setup complete: $env_file"
    print_info "Please review and edit the configuration file: $env_file"
}

# Main
if [ $# -eq 0 ]; then
    print_error "Usage: $0 <network>"
    exit 1
fi

setup_environment "$1"

