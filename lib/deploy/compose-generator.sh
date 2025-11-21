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
if [ ! -f "$SCRIPT_DIR/utils.sh" ]; then
    echo "Error: utils.sh not found at $SCRIPT_DIR/utils.sh" >&2
    exit 1
fi
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
            if ! merge_service_from_file "$DOCKER_COMPOSE_DIR/overlays/execution/geth.yaml" "execution-client"; then
                print_error "Failed to add Geth service"
                exit 1
            fi
            ;;
        nethermind)
            echo "" >> "$OUTPUT_FILE"
            echo "  # Execution Client: Nethermind" >> "$OUTPUT_FILE"
            if ! merge_service_from_file "$DOCKER_COMPOSE_DIR/overlays/execution/nethermind.yaml" "execution-client"; then
                print_error "Failed to add Nethermind service"
                exit 1
            fi
            ;;
        reth)
            echo "" >> "$OUTPUT_FILE"
            echo "  # Execution Client: Reth" >> "$OUTPUT_FILE"
            if ! merge_service_from_file "$DOCKER_COMPOSE_DIR/overlays/execution/reth.yaml" "execution-client"; then
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
            if ! merge_service_from_file "$DOCKER_COMPOSE_DIR/overlays/consensus/lighthouse.yaml" "consensus-client"; then
                print_error "Failed to add Lighthouse service"
                exit 1
            fi
            ;;
        teku)
            echo "" >> "$OUTPUT_FILE"
            echo "  # Consensus Client: Teku" >> "$OUTPUT_FILE"
            if ! merge_service_from_file "$DOCKER_COMPOSE_DIR/overlays/consensus/teku.yaml" "consensus-client"; then
                print_error "Failed to add Teku service"
                exit 1
            fi
            ;;
        prysm)
            echo "" >> "$OUTPUT_FILE"
            echo "  # Consensus Client: Prysm" >> "$OUTPUT_FILE"
            if ! merge_service_from_file "$DOCKER_COMPOSE_DIR/overlays/consensus/prysm.yaml" "consensus-client"; then
                print_error "Failed to add Prysm service"
                exit 1
            fi
            ;;
        lodestar)
            if [ -f "$DOCKER_COMPOSE_DIR/overlays/consensus/lodestar.yaml" ]; then
                echo "" >> "$OUTPUT_FILE"
                echo "  # Consensus Client: Lodestar" >> "$OUTPUT_FILE"
                if ! merge_service_from_file "$DOCKER_COMPOSE_DIR/overlays/consensus/lodestar.yaml" "consensus-client"; then
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
    echo "" >> "$OUTPUT_FILE"
    echo "  # MEV-Boost" >> "$OUTPUT_FILE"
    # Try docker-compose.yaml first (where mev-boost actually is)
    if [ -f "$DOCKER_COMPOSE_DIR/docker-compose.yaml" ]; then
        if ! merge_service_from_file "$DOCKER_COMPOSE_DIR/docker-compose.yaml" "mev-boost"; then
            print_warning "Failed to add MEV-Boost service from docker-compose.yaml, trying alternative..."
            # Fallback: try docker-compose.mev.yaml
            if [ -f "$DOCKER_COMPOSE_DIR/docker-compose.mev.yaml" ]; then
                if ! merge_service_from_file "$DOCKER_COMPOSE_DIR/docker-compose.mev.yaml" "mev-boost"; then
                    print_warning "Failed to add MEV-Boost service, continuing..."
                fi
            else
                print_warning "MEV-Boost service not found in any compose file"
            fi
        fi
    elif [ -f "$DOCKER_COMPOSE_DIR/docker-compose.mev.yaml" ]; then
        if ! merge_service_from_file "$DOCKER_COMPOSE_DIR/docker-compose.mev.yaml" "mev-boost"; then
            print_warning "Failed to add MEV-Boost service, continuing..."
        fi
    elif [ -f "$PROJECT_ROOT/docker-compose.yaml" ]; then
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

# Add Validator Client (optional - continue even if fails)
if [ -n "$SELECTED_VC" ] && [ "$SELECTED_VC" != "web3signer" ]; then
    case $SELECTED_VC in
        lighthouse)
            echo "" >> "$OUTPUT_FILE"
            echo "  # Validator Client: Lighthouse" >> "$OUTPUT_FILE"
            if ! merge_service_from_file "$DOCKER_COMPOSE_DIR/overlays/validator/lighthouse.yaml" "lighthouse-vc"; then
                print_warning "Failed to add Lighthouse VC service, continuing without validator..."
            fi
            ;;
        teku)
            if [ -f "$DOCKER_COMPOSE_DIR/overlays/validator/teku.yaml" ]; then
                echo "" >> "$OUTPUT_FILE"
                echo "  # Validator Client: Teku" >> "$OUTPUT_FILE"
                if ! merge_service_from_file "$DOCKER_COMPOSE_DIR/overlays/validator/teku.yaml" "teku-vc"; then
                    print_warning "Failed to add Teku VC service, continuing without validator..."
                fi
            else
                print_warning "Teku VC overlay file not found, continuing without validator..."
            fi
            ;;
        lodestar)
            if [ -f "$DOCKER_COMPOSE_DIR/overlays/validator/lodestar.yaml" ]; then
                echo "" >> "$OUTPUT_FILE"
                echo "  # Validator Client: Lodestar" >> "$OUTPUT_FILE"
                if ! merge_service_from_file "$DOCKER_COMPOSE_DIR/overlays/validator/lodestar.yaml" "lodestar-vc"; then
                    print_warning "Failed to add Lodestar VC service, continuing without validator..."
                fi
            else
                print_warning "Lodestar VC overlay file not found, continuing without validator..."
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

# Add DVT (optional - continue even if fails)
if [ -n "$SELECTED_DVT" ]; then
    if [ -f "$DOCKER_COMPOSE_DIR/docker-compose.dvt.yaml" ]; then
        case $SELECTED_DVT in
            obol)
                echo "" >> "$OUTPUT_FILE"
                echo "  # Obol DVT (Charon)" >> "$OUTPUT_FILE"
                if ! merge_service_from_file "$DOCKER_COMPOSE_DIR/docker-compose.dvt.yaml" "charon"; then
                    print_warning "Failed to add Charon service, continuing without DVT..."
                else
                    # Also add lighthouse/lodestar DVT if needed (optional)
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
                fi
                ;;
            ssv)
                echo "" >> "$OUTPUT_FILE"
                echo "  # SSV Network DVT" >> "$OUTPUT_FILE"
                if ! merge_service_from_file "$DOCKER_COMPOSE_DIR/docker-compose.dvt.yaml" "ssv-node"; then
                    print_warning "Failed to add SSV node service, continuing without DVT..."
                else
                    if [ -n "${SSV_DKG_ENABLED:-}" ]; then
                        if ! merge_service_from_file "$DOCKER_COMPOSE_DIR/docker-compose.dvt.yaml" "ssv-dkg"; then
                            print_warning "Failed to add SSV DKG service, continuing..."
                        fi
                    fi
                fi
                ;;
        esac
    else
        print_warning "DVT compose file not found, continuing without DVT..."
    fi
fi

# Add networks (only if not already present)
if ! grep -q "^networks:" "$OUTPUT_FILE"; then
    cat >> "$OUTPUT_FILE" <<'EOF'

networks:
  ethnode:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
EOF
else
    # Ensure networks section has content
    if ! grep -A 5 "^networks:" "$OUTPUT_FILE" | grep -q "ethnode:"; then
        print_warning "networks section exists but is empty, adding content..."
        # Remove empty networks section
        sed -i '/^networks:$/,$d' "$OUTPUT_FILE"
        # Add proper networks section
        cat >> "$OUTPUT_FILE" <<'EOF'

networks:
  ethnode:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
EOF
    fi
fi

# Note: volumes section removed - using bind mounts instead
# Data is stored in ${PROJECT_ROOT}/data/{client}/{network}/
# No need for Docker volumes

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

# Check for duplicate keys (networks, volumes)
networks_count=$(grep -c "^networks:" "$OUTPUT_FILE" 2>/dev/null || echo "0")
volumes_count=$(grep -c "^volumes:" "$OUTPUT_FILE" 2>/dev/null || echo "0")

# Ensure counts are integers (remove any whitespace)
networks_count=$(echo "$networks_count" | tr -d '[:space:]' || echo "0")
volumes_count=$(echo "$volumes_count" | tr -d '[:space:]' || echo "0")

# Default to 0 if empty or not a number
if [ -z "$networks_count" ] || ! [[ "$networks_count" =~ ^[0-9]+$ ]]; then
    networks_count=0
fi
if [ -z "$volumes_count" ] || ! [[ "$volumes_count" =~ ^[0-9]+$ ]]; then
    volumes_count=0
fi

if [ "$networks_count" -gt 1 ]; then
    print_warning "Duplicate 'networks:' sections found. Removing duplicates..."
    # Keep only the last networks section
    temp_file="${OUTPUT_FILE}.tmp"
    if awk '/^networks:/{if(++count>1)skip=1} skip && /^[a-zA-Z]/ && !/^  /{skip=0} !skip' "$OUTPUT_FILE" > "$temp_file" 2>/dev/null; then
        if [ -s "$temp_file" ]; then
            mv "$temp_file" "$OUTPUT_FILE"
        else
            rm -f "$temp_file"
            print_warning "Failed to remove duplicate networks, keeping original"
        fi
    else
        rm -f "$temp_file"
        print_warning "Failed to process duplicate networks, keeping original"
    fi
fi

# Ensure networks section is not empty and has proper content
if grep -q "^networks:" "$OUTPUT_FILE"; then
    # Check if networks section has content (not just "networks:")
    if ! grep -A 5 "^networks:" "$OUTPUT_FILE" | grep -q "ethnode:"; then
        print_warning "networks section is empty or incomplete, fixing..."
        # Remove empty networks section
        sed -i '/^networks:$/,$d' "$OUTPUT_FILE"
        # Add proper networks section
        cat >> "$OUTPUT_FILE" <<'EOF'

networks:
  ethnode:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
EOF
    fi
fi

if [ "$volumes_count" -gt 1 ]; then
    print_warning "Duplicate 'volumes:' sections found. Removing duplicates..."
    # Keep only the last volumes section
    temp_file="${OUTPUT_FILE}.tmp"
    if awk '/^volumes:/{if(++count>1)skip=1} skip && /^[a-zA-Z]/ && !/^  /{skip=0} !skip' "$OUTPUT_FILE" > "$temp_file" 2>/dev/null; then
        if [ -s "$temp_file" ]; then
            mv "$temp_file" "$OUTPUT_FILE"
        else
            rm -f "$temp_file"
            print_warning "Failed to remove duplicate volumes, keeping original"
        fi
    else
        rm -f "$temp_file"
        print_warning "Failed to process duplicate volumes, keeping original"
    fi
fi

# Validate YAML syntax if yq or python is available
if command_exists yq; then
    if ! yq eval '.' "$OUTPUT_FILE" >/dev/null 2>&1; then
        print_error "YAML validation failed (yq). Please check the generated file."
        exit 1
    fi
elif command_exists python3; then
    if ! python3 -c "import yaml; yaml.safe_load(open('$OUTPUT_FILE'))" 2>/dev/null; then
        print_error "YAML validation failed (python). Please check the generated file."
        exit 1
    fi
fi

print_success "Generated: $OUTPUT_FILE"
