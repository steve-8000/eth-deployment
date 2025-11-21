#!/usr/bin/env bash
# Utility functions for deployment scripts

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Print colored message
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Export for use in other scripts
export -f command_exists

# Check Docker
check_docker() {
    if ! command_exists docker; then
        print_error "Docker is not installed"
        return 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker daemon is not running"
        return 1
    fi
    
    return 0
}

# Check Docker Compose
check_docker_compose() {
    if ! command_exists docker; then
        print_error "Docker is not installed"
        return 1
    fi
    
    if ! docker compose version >/dev/null 2>&1; then
        print_error "Docker Compose is not available"
        return 1
    fi
    
    return 0
}

# Validate configuration
validate_config() {
    local config_file="$1"
    
    if [ ! -f "$config_file" ]; then
        print_error "Configuration file not found: $config_file"
        return 1
    fi
    
    # Check required variables (NETWORK is always required)
    local required_vars=("NETWORK")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if ! grep -q "^${var}=" "$config_file"; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        print_error "Missing required variables: ${missing_vars[*]}"
        return 1
    fi
    
    # Check if at least one client version is set
    if ! grep -qE "^(GETH_VERSION|NETHERMIND_VERSION|RETH_VERSION)=" "$config_file" && \
       ! grep -qE "^(LIGHTHOUSE_VERSION|TEKU_VERSION|PRYSM_VERSION|LODESTAR_VERSION)=" "$config_file"; then
        print_warning "No client versions found in config file. Some services may fail to start."
    fi
    
    return 0
}

# Generate JWT if not exists
ensure_jwt() {
    local jwt_file="$1"
    
    if [ ! -f "$jwt_file" ]; then
        print_info "Generating JWT secret..."
        mkdir -p "$(dirname "$jwt_file")"
        
        if ! command_exists openssl; then
            print_error "openssl is not installed. Cannot generate JWT secret."
            return 1
        fi
        
        if ! openssl rand -hex 32 | tr -d "\n" > "$jwt_file"; then
            print_error "Failed to generate JWT secret"
            return 1
        fi
        
        chmod 600 "$jwt_file"
        print_success "JWT secret generated"
    else
        print_info "JWT secret already exists"
    fi
    
    return 0
}

# Wait for service to be healthy
wait_for_service() {
    local service_name="$1"
    local compose_file="${2:-docker-compose.generated.yaml}"
    local max_wait="${3:-300}"
    local interval="${4:-5}"
    local waited=0
    
    if [ ! -f "$compose_file" ]; then
        print_error "Compose file not found: $compose_file"
        return 1
    fi
    
    print_info "Waiting for $service_name to be healthy..."
    
    while [ $waited -lt $max_wait ]; do
        if docker compose -f "$compose_file" ps "$service_name" 2>/dev/null | grep -q "healthy\|Up"; then
            print_success "$service_name is healthy"
            return 0
        fi
        
        sleep $interval
        waited=$((waited + interval))
        echo -n "."
    done
    
    echo ""
    print_warning "$service_name did not become healthy within ${max_wait}s"
    return 1
}

# Extract service from compose file
extract_service() {
    local compose_file="$1"
    local service_name="$2"
    
    if [ ! -f "$compose_file" ]; then
        return 1
    fi
    
    # Extract service block
    awk "/^  ${service_name}:/{flag=1} flag{print} /^  [a-zA-Z-]+:/{if(flag && !/^  ${service_name}:/){exit}} flag && /^  [a-zA-Z-]+:/ && !/^  ${service_name}:/{exit}" "$compose_file"
}

