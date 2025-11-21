#!/usr/bin/env bash
set -euo pipefail

# Advanced Docker Compose Generator
# Generates complete docker-compose.yaml from selected components

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_DIR="$PROJECT_ROOT/config"
DOCKER_COMPOSE_DIR="$PROJECT_ROOT/docker/compose"
OUTPUT_FILE="$PROJECT_ROOT/docker-compose.generated.yaml"

# Source utilities
source "$SCRIPT_DIR/utils.sh"

# Load configuration
if [ ! -f "$CONFIG_DIR/.deployment" ]; then
    print_error "Configuration not found. Please run deploy.sh first."
    exit 1
fi

source "$CONFIG_DIR/.deployment"

# Validate required variables
if [ -z "${SELECTED_NETWORK:-}" ]; then
    print_error "SELECTED_NETWORK is not set"
    exit 1
fi

# Load environment variables from root .env file
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

# Export for docker compose
export ENV="${SELECTED_NETWORK}"
export PROJECT_ROOT="$PROJECT_ROOT"
export NETWORK="${SELECTED_NETWORK}"

# Start generating compose file
cat > "$OUTPUT_FILE" <<'EOF'
version: '3.8'

services:
EOF

# Helper function to merge service from overlay file
merge_service_from_file() {
    local overlay_file="$1"
    local service_name="$2"
    
    if [ ! -f "$overlay_file" ]; then
        print_warning "Overlay file not found: $overlay_file"
        return 1
    fi
    
    # Check if service exists in overlay file
    if ! grep -q "^  ${service_name}:" "$overlay_file"; then
        print_warning "Service '$service_name' not found in $overlay_file"
        return 1
    fi
    
    # Extract service definition (everything from service name to next service or end of services)
    local temp_output
    if ! temp_output=$(mktemp 2>/dev/null); then
        print_error "Failed to create temporary file"
        return 1
    fi
    
    if ! awk -v svc="$service_name" '
    /^  [a-zA-Z-]+:/ {
        if (found && !match($0, "^  " svc ":")) exit
        if (match($0, "^  " svc ":")) found=1
    }
    found {print}
    /^networks:/ {if (found) exit}
    /^volumes:/ {if (found) exit}
    ' "$overlay_file" > "$temp_output"; then
        rm -f "$temp_output"
        print_error "Failed to extract service '$service_name' from $overlay_file"
        return 1
    fi
    
    # Check if extraction was successful (file should not be empty)
    if [ ! -s "$temp_output" ]; then
        rm -f "$temp_output"
        print_error "Service '$service_name' extraction resulted in empty output"
        return 1
    fi
    
    # Append to output file
    cat "$temp_output" >> "$OUTPUT_FILE"
    rm -f "$temp_output"
    
    return 0
}

# Add Execution Client
if [ -n "$SELECTED_EC" ]; then
    case $SELECTED_EC in
        geth)
            echo "" >> "$OUTPUT_FILE"
            echo "  # Execution Client: Geth" >> "$OUTPUT_FILE"
            if ! merge_service_from_file "$DOCKER_COMPOSE_DIR/overlays/execution/geth.yaml" "geth"; then
                print_error "Failed to add Geth service"
                exit 1
            fi
            ;;
        nethermind)
            echo "" >> "$OUTPUT_FILE"
            echo "  # Execution Client: Nethermind" >> "$OUTPUT_FILE"
            if ! merge_service_from_file "$DOCKER_COMPOSE_DIR/overlays/execution/nethermind.yaml" "nethermind"; then
                print_error "Failed to add Nethermind service"
                exit 1
            fi
            ;;
        reth)
            echo "" >> "$OUTPUT_FILE"
            echo "  # Execution Client: Reth" >> "$OUTPUT_FILE"
            if ! merge_service_from_file "$DOCKER_COMPOSE_DIR/overlays/execution/reth.yaml" "reth"; then
                print_error "Failed to add Reth service"
                exit 1
            fi
            ;;
    esac
fi

# Add Consensus Client
if [ -n "$SELECTED_CC" ]; then
    case $SELECTED_CC in
        lighthouse)
            echo "" >> "$OUTPUT_FILE"
            echo "  # Consensus Client: Lighthouse" >> "$OUTPUT_FILE"
            if ! merge_service_from_file "$DOCKER_COMPOSE_DIR/overlays/consensus/lighthouse.yaml" "lighthouse"; then
                print_error "Failed to add Lighthouse service"
                exit 1
            fi
            ;;
        teku)
            echo "" >> "$OUTPUT_FILE"
            echo "  # Consensus Client: Teku" >> "$OUTPUT_FILE"
            if ! merge_service_from_file "$DOCKER_COMPOSE_DIR/overlays/consensus/teku.yaml" "teku"; then
                print_error "Failed to add Teku service"
                exit 1
            fi
            ;;
        prysm)
            echo "" >> "$OUTPUT_FILE"
            echo "  # Consensus Client: Prysm" >> "$OUTPUT_FILE"
            if ! merge_service_from_file "$DOCKER_COMPOSE_DIR/overlays/consensus/prysm.yaml" "prysm"; then
                print_error "Failed to add Prysm service"
                exit 1
            fi
            ;;
        lodestar)
            if [ -f "$DOCKER_COMPOSE_DIR/overlays/consensus/lodestar.yaml" ]; then
                echo "" >> "$OUTPUT_FILE"
                echo "  # Consensus Client: Lodestar" >> "$OUTPUT_FILE"
                if ! merge_service_from_file "$DOCKER_COMPOSE_DIR/overlays/consensus/lodestar.yaml" "lodestar"; then
                    print_error "Failed to add Lodestar service"
                    exit 1
                fi
            else
                print_warning "Lodestar overlay file not found, skipping"
            fi
            ;;
    esac
fi

# Add MEV-Boost
if [ "$SELECTED_MEV" = "mevboost" ] || [ "$SELECTED_MEV" = "both" ]; then
    if [ -f "$DOCKER_COMPOSE_DIR/docker-compose.mev.yaml" ]; then
        echo "" >> "$OUTPUT_FILE"
        echo "  # MEV-Boost" >> "$OUTPUT_FILE"
        if ! merge_service_from_file "$DOCKER_COMPOSE_DIR/docker-compose.mev.yaml" "mev-boost"; then
            print_warning "Failed to add MEV-Boost service, continuing..."
        fi
    elif [ -f "$PROJECT_ROOT/docker-compose.yaml" ]; then
        echo "" >> "$OUTPUT_FILE"
        echo "  # MEV-Boost" >> "$OUTPUT_FILE"
        if ! merge_service_from_file "$PROJECT_ROOT/docker-compose.yaml" "mev-boost"; then
            print_warning "Failed to add MEV-Boost service, continuing..."
        fi
    else
        print_warning "MEV-Boost compose file not found"
    fi
fi

# Add Commit Boost
if [ "$SELECTED_MEV" = "commitboost" ] || [ "$SELECTED_MEV" = "both" ]; then
    if [ -f "$DOCKER_COMPOSE_DIR/docker-compose.mev.yaml" ]; then
        echo "" >> "$OUTPUT_FILE"
        echo "  # Commit Boost" >> "$OUTPUT_FILE"
        if ! merge_service_from_file "$DOCKER_COMPOSE_DIR/docker-compose.mev.yaml" "commit-boost"; then
            print_warning "Failed to add Commit Boost service, continuing..."
        fi
    else
        print_warning "MEV compose file not found for Commit Boost"
    fi
fi

# Add Validator Client
if [ -n "$SELECTED_VC" ] && [ "$SELECTED_VC" != "web3signer" ]; then
    case $SELECTED_VC in
        lighthouse)
            echo "" >> "$OUTPUT_FILE"
            echo "  # Validator Client: Lighthouse" >> "$OUTPUT_FILE"
            if ! merge_service_from_file "$DOCKER_COMPOSE_DIR/overlays/validator/lighthouse.yaml" "lighthouse-vc"; then
                print_error "Failed to add Lighthouse VC service"
                exit 1
            fi
            ;;
        teku)
            if [ -f "$DOCKER_COMPOSE_DIR/overlays/validator/teku.yaml" ]; then
                echo "" >> "$OUTPUT_FILE"
                echo "  # Validator Client: Teku" >> "$OUTPUT_FILE"
                if ! merge_service_from_file "$DOCKER_COMPOSE_DIR/overlays/validator/teku.yaml" "teku-vc"; then
                    print_error "Failed to add Teku VC service"
                    exit 1
                fi
            else
                print_warning "Teku VC overlay file not found"
            fi
            ;;
        lodestar)
            if [ -f "$DOCKER_COMPOSE_DIR/overlays/validator/lodestar.yaml" ]; then
                echo "" >> "$OUTPUT_FILE"
                echo "  # Validator Client: Lodestar" >> "$OUTPUT_FILE"
                if ! merge_service_from_file "$DOCKER_COMPOSE_DIR/overlays/validator/lodestar.yaml" "lodestar-vc"; then
                    print_error "Failed to add Lodestar VC service"
                    exit 1
                fi
            else
                print_warning "Lodestar VC overlay file not found"
            fi
            ;;
    esac
fi

# Add Web3Signer (includes all related services)
if [ "$SELECTED_VC" = "web3signer" ]; then
    if [ -f "$DOCKER_COMPOSE_DIR/docker-compose.external-signer.yaml" ]; then
        echo "" >> "$OUTPUT_FILE"
        echo "  # Web3Signer and related services" >> "$OUTPUT_FILE"
        # Extract all services from external-signer compose
        if ! awk '/^services:/{flag=1} flag{print} /^networks:/{if(flag) exit}' "$DOCKER_COMPOSE_DIR/docker-compose.external-signer.yaml" | tail -n +2 >> "$OUTPUT_FILE"; then
            print_warning "Failed to extract Web3Signer services"
        fi
    else
        print_warning "Web3Signer compose file not found"
    fi
fi

# Add DVT
if [ -n "$SELECTED_DVT" ]; then
    if [ -f "$DOCKER_COMPOSE_DIR/docker-compose.dvt.yaml" ]; then
        case $SELECTED_DVT in
            obol)
                echo "" >> "$OUTPUT_FILE"
                echo "  # Obol DVT (Charon)" >> "$OUTPUT_FILE"
                if ! merge_service_from_file "$DOCKER_COMPOSE_DIR/docker-compose.dvt.yaml" "charon"; then
                    print_error "Failed to add Charon service"
                    exit 1
                fi
                # Also add lighthouse/lodestar DVT if needed
                if [ -n "$SELECTED_CC" ]; then
                    case $SELECTED_CC in
                        lighthouse)
                            merge_service_from_file "$DOCKER_COMPOSE_DIR/docker-compose.dvt.yaml" "lighthouse-dvt" || print_warning "Failed to add lighthouse-dvt service"
                            ;;
                        lodestar)
                            merge_service_from_file "$DOCKER_COMPOSE_DIR/docker-compose.dvt.yaml" "lodestar-dvt" || print_warning "Failed to add lodestar-dvt service"
                            ;;
                    esac
                fi
                ;;
            ssv)
                echo "" >> "$OUTPUT_FILE"
                echo "  # SSV Network DVT" >> "$OUTPUT_FILE"
                if ! merge_service_from_file "$DOCKER_COMPOSE_DIR/docker-compose.dvt.yaml" "ssv-node"; then
                    print_error "Failed to add SSV node service"
                    exit 1
                fi
                if [ -n "${SSV_DKG_ENABLED:-}" ]; then
                    if ! merge_service_from_file "$DOCKER_COMPOSE_DIR/docker-compose.dvt.yaml" "ssv-dkg"; then
                        print_warning "Failed to add SSV DKG service, continuing..."
                    fi
                fi
                ;;
        esac
    else
        print_warning "DVT compose file not found"
    fi
fi

# Add networks and volumes
cat >> "$OUTPUT_FILE" <<'EOF'

networks:
  ethnode:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16

volumes:
  chain-data:
  keys:
  logs:
EOF

# Validate generated compose file
if [ ! -s "$OUTPUT_FILE" ]; then
    print_error "Generated compose file is empty"
    exit 1
fi

# Check if file has at least services section
if ! grep -q "^services:" "$OUTPUT_FILE"; then
    print_error "Generated compose file is missing services section"
    exit 1
fi

# Validate YAML syntax if yq or python is available
if command_exists yq; then
    if ! yq eval '.' "$OUTPUT_FILE" >/dev/null 2>&1; then
        print_warning "YAML validation failed (yq), but continuing..."
    fi
elif command_exists python3; then
    if ! python3 -c "import yaml; yaml.safe_load(open('$OUTPUT_FILE'))" 2>/dev/null; then
        print_warning "YAML validation failed (python), but continuing..."
    fi
fi

print_success "Generated: $OUTPUT_FILE"
