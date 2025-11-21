#!/usr/bin/env bash
set -euo pipefail

# Version Information Checker
# Compares .env versions with latest Docker Hub versions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"

# Source utilities
if [ -f "$SCRIPT_DIR/utils.sh" ]; then
    source "$SCRIPT_DIR/utils.sh"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check if command exists (fallback if utils.sh not available)
if ! command_exists command_exists 2>/dev/null; then
    command_exists() {
        command -v "$1" >/dev/null 2>&1
    }
fi

# GitHub repository mappings for releases API
declare -A GITHUB_REPOS=(
    ["GETH_VERSION"]="ethereum/go-ethereum"
    ["NETHERMIND_VERSION"]="NethermindEth/nethermind"
    ["RETH_VERSION"]="paradigmxyz/reth"
    ["LIGHTHOUSE_VERSION"]="sigp/lighthouse"
    ["TEKU_VERSION"]="ConsenSys/teku"
    ["PRYSM_VERSION"]="prysmaticlabs/prysm"
    ["LODESTAR_VERSION"]="ChainSafe/lodestar"
    ["MEVBOOST_VERSION"]="flashbots/mev-boost"
    ["COMMITBOOST_VERSION"]="flashbots/commit-boost"
    ["CHARON_VERSION"]="ObolNetwork/charon"
    ["SSV_VERSION"]="bloxstaking/ssv-network"
    ["SSV_DKG_VERSION"]="bloxstaking/ssv-dkg"
)

# Docker Hub image mappings (fallback)
declare -A DOCKER_IMAGES=(
    ["GETH_VERSION"]="ethereum/client-go"
    ["NETHERMIND_VERSION"]="nethermind/nethermind"
    ["RETH_VERSION"]="ghcr.io/paradigmxyz/reth"
    ["LIGHTHOUSE_VERSION"]="sigp/lighthouse"
    ["TEKU_VERSION"]="consensys/teku"
    ["PRYSM_VERSION"]="gcr.io/prysmaticlabs/prysm"
    ["LODESTAR_VERSION"]="chainsafe/lodestar"
    ["WEB3SIGNER_VERSION"]="consensys/web3signer"
    ["MEVBOOST_VERSION"]="flashbots/mev-boost"
    ["COMMITBOOST_VERSION"]="flashbots/commit-boost"
    ["CHARON_VERSION"]="obolnetwork/charon"
    ["SSV_VERSION"]="ssvlabs/ssv-node"
    ["SSV_DKG_VERSION"]="bloxstaking/ssv-dkg"
    ["STAKEWISE_VERSION"]="stakewise/oracle"
)

# Version comparison function for sorting
version_compare() {
    local v1="$1"
    local v2="$2"
    
    # Remove 'v' prefix
    v1=$(echo "$v1" | sed 's/^v//')
    v2=$(echo "$v2" | sed 's/^v//')
    
    # Split version into parts
    IFS='.' read -r -a v1_parts <<< "$v1"
    IFS='.' read -r -a v2_parts <<< "$v2"
    
    # Compare each part
    local max_len=${#v1_parts[@]}
    if [ ${#v2_parts[@]} -gt $max_len ]; then
        max_len=${#v2_parts[@]}
    fi
    
    for ((i=0; i<max_len; i++)); do
        local v1_part=${v1_parts[$i]:-0}
        local v2_part=${v2_parts[$i]:-0}
        
        if [ "$v1_part" -gt "$v2_part" ]; then
            echo "1"
            return
        elif [ "$v1_part" -lt "$v2_part" ]; then
            echo "-1"
            return
        fi
    done
    
    echo "0"
}

# Get latest version from Docker Hub (more reliable for Docker images)
get_latest_version_dockerhub() {
    local image="$1"
    local latest=""
    
    # Get all tags from Docker Hub (multiple pages if needed)
    # Collect all version tags first, then sort properly
    local all_versions=""
    local page=1
    local has_more=true
    
    while [ "$has_more" = true ] && [ $page -le 10 ]; do
        local tags_json=$(curl -s "https://hub.docker.com/v2/repositories/${image}/tags?page_size=100&page=${page}&ordering=-last_updated" 2>/dev/null)
        
        if [ -z "$tags_json" ] || ! echo "$tags_json" | grep -q "results"; then
            break
        fi
        
        if command_exists jq && echo "$tags_json" | jq -e . >/dev/null 2>&1; then
            # Extract version tags from this page
            # Match: v1.2.3, 1.2.3, 25.11.0 formats
            local page_versions=$(echo "$tags_json" | jq -r '.results[] | select(.name | test("^v?[0-9]+\\.[0-9]+\\.[0-9]+$")) | .name' 2>/dev/null | grep -vE '(-rc|-alpha|-beta|-dev|-snapshot|latest|develop|SNAPSHOT)' || echo "")
            
            if [ -n "$page_versions" ]; then
                all_versions="${all_versions}${page_versions}"$'\n'
            fi
            
            # Check if there are more pages
            has_more=$(echo "$tags_json" | jq -r '.next != null' 2>/dev/null)
        else
            # Fallback: extract version tags
            local page_versions=$(echo "$tags_json" | grep -o '"name":"[^"]*"' | grep -E '"name":"v?[0-9]+\.[0-9]+\.[0-9]+"' | grep -vE '(-rc|-alpha|-beta|-dev|-snapshot|latest|develop|SNAPSHOT)' | cut -d'"' -f4)
            if [ -n "$page_versions" ]; then
                all_versions="${all_versions}${page_versions}"$'\n'
            fi
            
            # Check if there are more pages
            has_more=$(echo "$tags_json" | grep -q '"next"' && echo "true" || echo "false")
        fi
        
        page=$((page + 1))
    done
    
    if [ -z "$all_versions" ]; then
        echo ""
        return
    fi
    
    # Sort all versions by version number (descending) and get the latest
    # Use sort -V for proper version sorting
    if command_exists sort; then
        # Remove 'v' prefix, sort by version number, get highest
        latest=$(echo "$all_versions" | grep -v '^$' | sed 's/^v//' | sort -V -r | head -1)
    else
        # Fallback: use first version
        latest=$(echo "$all_versions" | grep -v '^$' | head -1 | sed 's/^v//')
    fi
    
    echo "$latest"
}

# Get latest version for Geth
get_latest_geth() {
    local api_response=$(curl -s --connect-timeout 5 --max-time 10 -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/ethereum/go-ethereum/releases/latest" 2>/dev/null)
    if [ -n "$api_response" ] && echo "$api_response" | grep -q "tag_name" && ! echo "$api_response" | grep -qE '("message"|"Not Found"|"rate limit")'; then
        if command_exists jq && echo "$api_response" | jq -e . >/dev/null 2>&1; then
            local tag_name=$(echo "$api_response" | jq -r '.tag_name // empty' 2>/dev/null)
            if [ -n "$tag_name" ] && [ "$tag_name" != "null" ]; then
                echo "$tag_name" | sed 's/^v//'
                return
            fi
        fi
    fi
    # Fallback to Docker Hub
    get_latest_version_dockerhub "ethereum/client-go"
}

# Get latest version for Nethermind
get_latest_nethermind() {
    local api_response=$(curl -s --connect-timeout 5 --max-time 10 -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/NethermindEth/nethermind/releases/latest" 2>/dev/null)
    if [ -n "$api_response" ] && echo "$api_response" | grep -q "tag_name" && ! echo "$api_response" | grep -qE '("message"|"Not Found"|"rate limit")'; then
        if command_exists jq && echo "$api_response" | jq -e . >/dev/null 2>&1; then
            local tag_name=$(echo "$api_response" | jq -r '.tag_name // empty' 2>/dev/null)
            if [ -n "$tag_name" ] && [ "$tag_name" != "null" ]; then
                echo "$tag_name" | sed 's/^v//'
                return
            fi
        fi
    fi
    # Fallback to Docker Hub
    get_latest_version_dockerhub "nethermind/nethermind"
}

# Get latest version for Reth
get_latest_reth() {
    # Try GitHub releases list (more reliable than /latest endpoint)
    local api_response=$(curl -s --connect-timeout 5 --max-time 10 -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/paradigmxyz/reth/releases?per_page=10" 2>/dev/null)
    if [ -n "$api_response" ] && echo "$api_response" | grep -q "tag_name" && ! echo "$api_response" | grep -qE '("message"|"Not Found"|"rate limit")'; then
        if command_exists jq && echo "$api_response" | jq -e . >/dev/null 2>&1; then
            local tag_name=$(echo "$api_response" | jq -r '.[0].tag_name // empty' 2>/dev/null)
            if [ -n "$tag_name" ] && [ "$tag_name" != "null" ]; then
                echo "$tag_name" | sed 's/^v//'
                return
            fi
        fi
    fi
    # Reth uses ghcr.io, but try Docker Hub as fallback
    local docker_latest=$(get_latest_version_dockerhub "paradigmxyz/reth")
    if [ -n "$docker_latest" ] && [ "$docker_latest" != "null" ] && [ "$docker_latest" != "" ]; then
        echo "$docker_latest"
        return
    fi
    echo ""
}

# Get latest version for Lighthouse
get_latest_lighthouse() {
    local api_response=$(curl -s --connect-timeout 5 --max-time 10 -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/sigp/lighthouse/releases/latest" 2>/dev/null)
    if [ -n "$api_response" ] && echo "$api_response" | grep -q "tag_name" && ! echo "$api_response" | grep -qE '("message"|"Not Found"|"rate limit")'; then
        if command_exists jq && echo "$api_response" | jq -e . >/dev/null 2>&1; then
            local tag_name=$(echo "$api_response" | jq -r '.tag_name // empty' 2>/dev/null)
            if [ -n "$tag_name" ] && [ "$tag_name" != "null" ]; then
                echo "$tag_name" | sed 's/^v//'
                return
            fi
        fi
    fi
    # Fallback to Docker Hub
    get_latest_version_dockerhub "sigp/lighthouse"
}

# Get latest version for Teku
get_latest_teku() {
    # Try GitHub releases list first (more reliable)
    local api_response=$(curl -s --connect-timeout 5 --max-time 10 -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/ConsenSys/teku/releases?per_page=10" 2>/dev/null)
    if [ -n "$api_response" ] && echo "$api_response" | grep -q "tag_name" && ! echo "$api_response" | grep -qE '("message"|"Not Found"|"rate limit")'; then
        if command_exists jq && echo "$api_response" | jq -e . >/dev/null 2>&1; then
            local tag_name=$(echo "$api_response" | jq -r '.[0].tag_name // empty' 2>/dev/null)
            if [ -n "$tag_name" ] && [ "$tag_name" != "null" ]; then
                echo "$tag_name" | sed 's/^v//'
                return
            fi
        fi
    fi
    # Fallback to Docker Hub (Teku uses Docker Hub)
    local docker_latest=$(get_latest_version_dockerhub "consensys/teku")
    if [ -n "$docker_latest" ] && [ "$docker_latest" != "null" ] && [ "$docker_latest" != "" ]; then
        echo "$docker_latest"
        return
    fi
    echo ""
}

# Get latest version for Prysm (check non-prerelease)
get_latest_prysm() {
    local api_response=$(curl -s --connect-timeout 5 --max-time 10 -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/prysmaticlabs/prysm/releases?per_page=50" 2>/dev/null)
    if [ -n "$api_response" ] && echo "$api_response" | grep -q "tag_name" && ! echo "$api_response" | grep -qE '("message"|"Not Found"|"rate limit")'; then
        if command_exists jq && echo "$api_response" | jq -e . >/dev/null 2>&1; then
            local tag_name=$(echo "$api_response" | jq -r '.[] | select(.prerelease == false) | .tag_name' 2>/dev/null | head -1)
            if [ -n "$tag_name" ] && [ "$tag_name" != "null" ]; then
                echo "$tag_name" | sed 's/^v//'
                return
            fi
        fi
    fi
    # Prysm uses gcr.io, but try Docker Hub equivalent (may not exist)
    local docker_latest=$(get_latest_version_dockerhub "prysmaticlabs/prysm-beacon-chain")
    if [ -n "$docker_latest" ] && [ "$docker_latest" != "null" ] && [ "$docker_latest" != "" ]; then
        echo "$docker_latest"
        return
    fi
    echo ""
}

# Get latest version for Lodestar
get_latest_lodestar() {
    local api_response=$(curl -s --connect-timeout 5 --max-time 10 -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/ChainSafe/lodestar/releases/latest" 2>/dev/null)
    if [ -n "$api_response" ] && echo "$api_response" | grep -q "tag_name" && ! echo "$api_response" | grep -qE '("message"|"Not Found"|"rate limit")'; then
        if command_exists jq && echo "$api_response" | jq -e . >/dev/null 2>&1; then
            local tag_name=$(echo "$api_response" | jq -r '.tag_name // empty' 2>/dev/null)
            if [ -n "$tag_name" ] && [ "$tag_name" != "null" ]; then
                echo "$tag_name" | sed 's/^v//'
                return
            fi
        fi
    fi
    # Fallback to Docker Hub
    get_latest_version_dockerhub "chainsafe/lodestar"
}

# Get latest version for MEV-Boost
get_latest_mevboost() {
    # Try GitHub releases first
    local api_response=$(curl -s --connect-timeout 5 --max-time 10 -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/flashbots/mev-boost/releases/latest" 2>/dev/null)
    if [ -n "$api_response" ] && echo "$api_response" | grep -q "tag_name" && ! echo "$api_response" | grep -qE '("message"|"Not Found"|"rate limit")'; then
        if command_exists jq && echo "$api_response" | jq -e . >/dev/null 2>&1; then
            local tag_name=$(echo "$api_response" | jq -r '.tag_name // empty' 2>/dev/null)
            if [ -n "$tag_name" ] && [ "$tag_name" != "null" ]; then
                echo "$tag_name" | sed 's/^v//'
                return
            fi
        fi
    fi
    # Fallback to Docker Hub (MEV-Boost uses Docker Hub)
    local docker_latest=$(get_latest_version_dockerhub "flashbots/mev-boost")
    if [ -n "$docker_latest" ] && [ "$docker_latest" != "null" ] && [ "$docker_latest" != "" ]; then
        echo "$docker_latest"
        return
    fi
    echo ""
}

# Get latest version for Commit Boost
get_latest_commitboost() {
    # Try Docker Hub first
    local docker_latest=$(get_latest_version_dockerhub "flashbots/commit-boost")
    if [ -n "$docker_latest" ] && [ "$docker_latest" != "null" ] && [ "$docker_latest" != "" ]; then
        echo "$docker_latest"
        return
    fi
    # Fallback to GitHub releases
    local api_response=$(curl -s --connect-timeout 5 --max-time 10 -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/flashbots/commit-boost/releases?per_page=10" 2>/dev/null)
    if [ -n "$api_response" ] && echo "$api_response" | grep -q "tag_name"; then
        if command_exists jq && echo "$api_response" | jq -e . >/dev/null 2>&1; then
            local tag_name=$(echo "$api_response" | jq -r '.[0].tag_name // empty' 2>/dev/null)
            if [ -n "$tag_name" ] && [ "$tag_name" != "null" ]; then
                echo "$tag_name" | sed 's/^v//'
                return
            fi
        fi
    fi
    echo ""
}

# Get latest version for Web3Signer (Docker Hub is more accurate)
get_latest_web3signer() {
    # Docker Hub has more accurate version tags for Web3Signer
    local docker_latest=$(get_latest_version_dockerhub "consensys/web3signer")
    if [ -n "$docker_latest" ] && [ "$docker_latest" != "null" ] && [ "$docker_latest" != "" ]; then
        echo "$docker_latest"
        return
    fi
    # Fallback to GitHub releases
    local api_response=$(curl -s --connect-timeout 5 --max-time 10 -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/ConsenSys/web3signer/releases?per_page=20" 2>/dev/null)
    if [ -n "$api_response" ] && echo "$api_response" | grep -q "tag_name"; then
        if command_exists jq && echo "$api_response" | jq -e . >/dev/null 2>&1; then
            local tag_name=$(echo "$api_response" | jq -r '.[] | select(.prerelease == false) | .tag_name' 2>/dev/null | head -1)
            if [ -n "$tag_name" ] && [ "$tag_name" != "null" ]; then
                echo "$tag_name" | sed 's/^v//'
                return
            fi
        fi
    fi
    echo ""
}

# Get latest version for Charon (Obol DVT)
get_latest_charon() {
    local api_response=$(curl -s --connect-timeout 5 --max-time 10 -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/ObolNetwork/charon/releases/latest" 2>/dev/null)
    if [ -n "$api_response" ] && echo "$api_response" | grep -q "tag_name" && ! echo "$api_response" | grep -qE '("message"|"Not Found"|"rate limit")'; then
        if command_exists jq && echo "$api_response" | jq -e . >/dev/null 2>&1; then
            local tag_name=$(echo "$api_response" | jq -r '.tag_name // empty' 2>/dev/null)
            if [ -n "$tag_name" ] && [ "$tag_name" != "null" ]; then
                echo "$tag_name" | sed 's/^v//'
                return
            fi
        fi
    fi
    # Fallback to Docker Hub
    get_latest_version_dockerhub "obolnetwork/charon"
}

# Get latest version for SSV Network
get_latest_ssv() {
    local api_response=$(curl -s --connect-timeout 5 --max-time 10 -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/bloxstaking/ssv-network/releases/latest" 2>/dev/null)
    if [ -n "$api_response" ] && echo "$api_response" | grep -q "tag_name" && ! echo "$api_response" | grep -qE '("message"|"Not Found"|"rate limit")'; then
        if command_exists jq && echo "$api_response" | jq -e . >/dev/null 2>&1; then
            local tag_name=$(echo "$api_response" | jq -r '.tag_name // empty' 2>/dev/null)
            if [ -n "$tag_name" ] && [ "$tag_name" != "null" ]; then
                echo "$tag_name" | sed 's/^v//'
                return
            fi
        fi
    fi
    # Fallback to Docker Hub (ssvlabs/ssv-node is the correct image name)
    get_latest_version_dockerhub "ssvlabs/ssv-node"
}

# Get latest version for SSV DKG
get_latest_ssv_dkg() {
    local api_response=$(curl -s --connect-timeout 5 --max-time 10 -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/bloxstaking/ssv-dkg/releases/latest" 2>/dev/null)
    if [ -n "$api_response" ] && echo "$api_response" | grep -q "tag_name" && ! echo "$api_response" | grep -qE '("message"|"Not Found"|"rate limit")'; then
        if command_exists jq && echo "$api_response" | jq -e . >/dev/null 2>&1; then
            local tag_name=$(echo "$api_response" | jq -r '.tag_name // empty' 2>/dev/null)
            if [ -n "$tag_name" ] && [ "$tag_name" != "null" ]; then
                echo "$tag_name" | sed 's/^v//'
                return
            fi
        fi
    fi
    # Fallback to Docker Hub
    get_latest_version_dockerhub "ssvlabs/ssv-dkg"
}

# Get latest version for Stakewise
get_latest_stakewise() {
    # Stakewise uses Docker Hub/GCR, check Docker Hub first
    get_latest_version_dockerhub "stakewise/oracle"
}

# Get latest version - dispatcher function
get_latest_version() {
    local version_var="$1"
    local latest=""
    
    case "$version_var" in
        "GETH_VERSION")
            latest=$(get_latest_geth)
            ;;
        "NETHERMIND_VERSION")
            latest=$(get_latest_nethermind)
            ;;
        "RETH_VERSION")
            latest=$(get_latest_reth)
            ;;
        "LIGHTHOUSE_VERSION")
            latest=$(get_latest_lighthouse)
            ;;
        "TEKU_VERSION")
            latest=$(get_latest_teku)
            ;;
        "PRYSM_VERSION")
            latest=$(get_latest_prysm)
            ;;
        "LODESTAR_VERSION")
            latest=$(get_latest_lodestar)
            ;;
        "MEVBOOST_VERSION")
            latest=$(get_latest_mevboost)
            ;;
        "COMMITBOOST_VERSION")
            latest=$(get_latest_commitboost)
            ;;
        "WEB3SIGNER_VERSION")
            latest=$(get_latest_web3signer)
            ;;
        "CHARON_VERSION")
            latest=$(get_latest_charon)
            ;;
        "SSV_VERSION")
            latest=$(get_latest_ssv)
            ;;
        "SSV_DKG_VERSION")
            latest=$(get_latest_ssv_dkg)
            ;;
        "STAKEWISE_VERSION")
            latest=$(get_latest_stakewise)
            ;;
        *)
            # Fallback to generic method
            if [ -n "${GITHUB_REPOS[$version_var]:-}" ]; then
                local repo="${GITHUB_REPOS[$version_var]}"
                local api_response=$(curl -s --connect-timeout 5 --max-time 10 -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null)
                if [ -n "$api_response" ] && echo "$api_response" | grep -q "tag_name" && ! echo "$api_response" | grep -qE '("message"|"Not Found"|"rate limit")'; then
                    if command_exists jq && echo "$api_response" | jq -e . >/dev/null 2>&1; then
                        local tag_name=$(echo "$api_response" | jq -r '.tag_name // empty' 2>/dev/null)
                        if [ -n "$tag_name" ] && [ "$tag_name" != "null" ]; then
                            latest=$(echo "$tag_name" | sed 's/^v//')
                        fi
                    fi
                fi
            fi
            # Also try Docker Hub if available
            if [ -z "$latest" ] || [ "$latest" = "null" ] || [ "$latest" = "" ]; then
                if [ -n "${DOCKER_IMAGES[$version_var]:-}" ]; then
                    local docker_image="${DOCKER_IMAGES[$version_var]}"
                    if [[ ! "$docker_image" =~ ^(gcr.io|ghcr.io) ]]; then
                        local docker_latest=$(get_latest_version_dockerhub "$docker_image")
                        if [ -n "$docker_latest" ] && [ "$docker_latest" != "null" ] && [ "$docker_latest" != "" ]; then
                            latest="$docker_latest"
                        fi
                    fi
                fi
            fi
            ;;
    esac
    
    echo "$latest"
}

# Compare versions
compare_versions() {
    local current="$1"
    local latest="$2"
    
    if [ -z "$latest" ] || [ "$latest" = "null" ] || [ "$latest" = "" ]; then
        echo "unknown"
        return
    fi
    
    # Remove 'v' prefix if present
    current=$(echo "$current" | sed 's/^v//')
    latest=$(echo "$latest" | sed 's/^v//')
    
    if [ "$current" = "$latest" ]; then
        echo "up-to-date"
    elif [ "$current" = "latest" ]; then
        echo "latest-tag"
    else
        # Simple version comparison (works for semantic versions)
        local current_num=$(echo "$current" | sed 's/[^0-9.]//g')
        local latest_num=$(echo "$latest" | sed 's/[^0-9.]//g')
        
        if [ "$current_num" = "$latest_num" ]; then
            echo "up-to-date"
        else
            echo "outdated"
        fi
    fi
}

# Load .env file
load_env() {
    if [ ! -f "$ENV_FILE" ]; then
        echo -e "${RED}Error: .env file not found${NC}"
        return 1
    fi
    
    # Source .env file
    set -a
    source "$ENV_FILE" 2>/dev/null || true
    set +a
}

# Show version information
show_version_info() {
    load_env || return 1
    
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}              ${BLUE}Upgrade Version Information${NC}                    ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Checking latest versions from Docker Hub...${NC}"
    echo ""
    
    # Execution Clients
    echo -e "${GREEN}Execution Clients:${NC}"
    echo -e "${YELLOW}───────────────────────────────────────────────────────────────${NC}"
    
    if [ -n "${GETH_VERSION:-}" ]; then
        local current="${GETH_VERSION}"
        local latest=$(get_latest_version "GETH_VERSION")
        local status=$(compare_versions "$current" "$latest")
        
        case "$status" in
            "up-to-date")
                echo -e "  ${GREEN}✓${NC} Geth:        ${GREEN}${current}${NC} (Latest: ${GREEN}${latest:-N/A}${NC})"
                ;;
            "latest-tag")
                echo -e "  ${CYAN}○${NC} Geth:        ${CYAN}${current}${NC} (Using 'latest' tag)"
                ;;
            "outdated")
                echo -e "  ${YELLOW}⚠${NC} Geth:        ${YELLOW}${current}${NC} → Latest: ${GREEN}${latest}${NC}"
                ;;
            *)
                echo -e "  ${BLUE}?${NC} Geth:        ${current} (Latest: ${latest:-Unable to fetch})"
                ;;
        esac
    fi
    
    if [ -n "${NETHERMIND_VERSION:-}" ]; then
        local current="${NETHERMIND_VERSION}"
        local latest=$(get_latest_version "NETHERMIND_VERSION")
        local status=$(compare_versions "$current" "$latest")
        
        case "$status" in
            "up-to-date")
                echo -e "  ${GREEN}✓${NC} Nethermind:  ${GREEN}${current}${NC} (Latest: ${GREEN}${latest:-N/A}${NC})"
                ;;
            "latest-tag")
                echo -e "  ${CYAN}○${NC} Nethermind:  ${CYAN}${current}${NC} (Using 'latest' tag)"
                ;;
            "outdated")
                echo -e "  ${YELLOW}⚠${NC} Nethermind:  ${YELLOW}${current}${NC} → Latest: ${GREEN}${latest}${NC}"
                ;;
            *)
                echo -e "  ${BLUE}?${NC} Nethermind:  ${current} (Latest: ${latest:-Unable to fetch})"
                ;;
        esac
    fi
    
    if [ -n "${RETH_VERSION:-}" ]; then
        local current="${RETH_VERSION}"
        local latest=$(get_latest_version "RETH_VERSION")
        local status=$(compare_versions "$current" "$latest")
        
        case "$status" in
            "up-to-date")
                echo -e "  ${GREEN}✓${NC} Reth:        ${GREEN}${current}${NC} (Latest: ${GREEN}${latest:-N/A}${NC})"
                ;;
            "latest-tag")
                echo -e "  ${CYAN}○${NC} Reth:        ${CYAN}${current}${NC} (Using 'latest' tag)"
                ;;
            "outdated")
                echo -e "  ${YELLOW}⚠${NC} Reth:        ${YELLOW}${current}${NC} → Latest: ${GREEN}${latest}${NC}"
                ;;
            *)
                echo -e "  ${BLUE}?${NC} Reth:        ${current} (Latest: ${latest:-Unable to fetch})"
                ;;
        esac
    fi
    
    echo ""
    
    # Consensus Clients
    echo -e "${GREEN}Consensus Clients:${NC}"
    echo -e "${YELLOW}───────────────────────────────────────────────────────────────${NC}"
    
    if [ -n "${LIGHTHOUSE_VERSION:-}" ]; then
        local current="${LIGHTHOUSE_VERSION}"
        local latest=$(get_latest_version "LIGHTHOUSE_VERSION")
        local status=$(compare_versions "$current" "$latest")
        
        case "$status" in
            "up-to-date")
                echo -e "  ${GREEN}✓${NC} Lighthouse:  ${GREEN}${current}${NC} (Latest: ${GREEN}${latest:-N/A}${NC})"
                ;;
            "latest-tag")
                echo -e "  ${CYAN}○${NC} Lighthouse:  ${CYAN}${current}${NC} (Using 'latest' tag)"
                ;;
            "outdated")
                echo -e "  ${YELLOW}⚠${NC} Lighthouse:  ${YELLOW}${current}${NC} → Latest: ${GREEN}${latest}${NC}"
                ;;
            *)
                echo -e "  ${BLUE}?${NC} Lighthouse:  ${current} (Latest: ${latest:-Unable to fetch})"
                ;;
        esac
    fi
    
    if [ -n "${TEKU_VERSION:-}" ]; then
        local current="${TEKU_VERSION}"
        local latest=$(get_latest_version "TEKU_VERSION")
        local status=$(compare_versions "$current" "$latest")
        
        case "$status" in
            "up-to-date")
                echo -e "  ${GREEN}✓${NC} Teku:        ${GREEN}${current}${NC} (Latest: ${GREEN}${latest:-N/A}${NC})"
                ;;
            "latest-tag")
                echo -e "  ${CYAN}○${NC} Teku:        ${CYAN}${current}${NC} (Using 'latest' tag)"
                ;;
            "outdated")
                echo -e "  ${YELLOW}⚠${NC} Teku:        ${YELLOW}${current}${NC} → Latest: ${GREEN}${latest}${NC}"
                ;;
            *)
                echo -e "  ${BLUE}?${NC} Teku:        ${current} (Latest: ${latest:-Unable to fetch})"
                ;;
        esac
    fi
    
    if [ -n "${PRYSM_VERSION:-}" ]; then
        local current="${PRYSM_VERSION}"
        local latest=$(get_latest_version "PRYSM_VERSION")
        local status=$(compare_versions "$current" "$latest")
        
        case "$status" in
            "up-to-date")
                echo -e "  ${GREEN}✓${NC} Prysm:       ${GREEN}${current}${NC} (Latest: ${GREEN}${latest:-N/A}${NC})"
                ;;
            "latest-tag")
                echo -e "  ${CYAN}○${NC} Prysm:       ${CYAN}${current}${NC} (Using 'latest' tag)"
                ;;
            "outdated")
                echo -e "  ${YELLOW}⚠${NC} Prysm:       ${YELLOW}${current}${NC} → Latest: ${GREEN}${latest}${NC}"
                ;;
            *)
                echo -e "  ${BLUE}?${NC} Prysm:       ${current} (Latest: ${latest:-Unable to fetch})"
                ;;
        esac
    fi
    
    if [ -n "${LODESTAR_VERSION:-}" ]; then
        local current="${LODESTAR_VERSION}"
        local latest=$(get_latest_version "LODESTAR_VERSION")
        local status=$(compare_versions "$current" "$latest")
        
        case "$status" in
            "up-to-date")
                echo -e "  ${GREEN}✓${NC} Lodestar:    ${GREEN}${current}${NC} (Latest: ${GREEN}${latest:-N/A}${NC})"
                ;;
            "latest-tag")
                echo -e "  ${CYAN}○${NC} Lodestar:    ${CYAN}${current}${NC} (Using 'latest' tag)"
                ;;
            "outdated")
                echo -e "  ${YELLOW}⚠${NC} Lodestar:    ${YELLOW}${current}${NC} → Latest: ${GREEN}${latest}${NC}"
                ;;
            *)
                echo -e "  ${BLUE}?${NC} Lodestar:    ${current} (Latest: ${latest:-Unable to fetch})"
                ;;
        esac
    fi
    
    echo ""
    
    # MEV & Other Services
    echo -e "${GREEN}MEV & Other Services:${NC}"
    echo -e "${YELLOW}───────────────────────────────────────────────────────────────${NC}"
    
    if [ -n "${MEVBOOST_VERSION:-}" ]; then
        local current="${MEVBOOST_VERSION}"
        # If using 'latest' tag, don't check version
        if [ "$current" = "latest" ]; then
            echo -e "  ${CYAN}○${NC} MEV-Boost:   ${CYAN}${current}${NC} (Using 'latest' tag)"
        else
            local latest=$(get_latest_version "MEVBOOST_VERSION")
            local status=$(compare_versions "$current" "$latest")
            
            case "$status" in
                "up-to-date")
                    echo -e "  ${GREEN}✓${NC} MEV-Boost:   ${GREEN}${current}${NC} (Latest: ${GREEN}${latest:-N/A}${NC})"
                    ;;
                "latest-tag")
                    echo -e "  ${CYAN}○${NC} MEV-Boost:   ${CYAN}${current}${NC} (Using 'latest' tag)"
                    ;;
                "outdated")
                    echo -e "  ${YELLOW}⚠${NC} MEV-Boost:   ${YELLOW}${current}${NC} → Latest: ${GREEN}${latest}${NC}"
                    ;;
                *)
                    echo -e "  ${BLUE}?${NC} MEV-Boost:   ${current} (Latest: ${latest:-Unable to fetch})"
                    ;;
            esac
        fi
    fi
    
    if [ -n "${COMMITBOOST_VERSION:-}" ]; then
        local current="${COMMITBOOST_VERSION}"
        local latest=$(get_latest_version "COMMITBOOST_VERSION")
        local status=$(compare_versions "$current" "$latest")
        
        case "$status" in
            "up-to-date")
                echo -e "  ${GREEN}✓${NC} Commit Boost: ${GREEN}${current}${NC} (Latest: ${GREEN}${latest:-N/A}${NC})"
                ;;
            "latest-tag")
                echo -e "  ${CYAN}○${NC} Commit Boost: ${CYAN}${current}${NC} (Using 'latest' tag)"
                ;;
            "outdated")
                echo -e "  ${YELLOW}⚠${NC} Commit Boost: ${YELLOW}${current}${NC} → Latest: ${GREEN}${latest}${NC}"
                ;;
            *)
                echo -e "  ${BLUE}?${NC} Commit Boost: ${current} (Latest: ${latest:-Unable to fetch})"
                ;;
        esac
    fi
    
    if [ -n "${WEB3SIGNER_VERSION:-}" ]; then
        local current="${WEB3SIGNER_VERSION}"
        local latest=$(get_latest_version "WEB3SIGNER_VERSION")
        local status=$(compare_versions "$current" "$latest")
        
        case "$status" in
            "up-to-date")
                echo -e "  ${GREEN}✓${NC} Web3Signer:  ${GREEN}${current}${NC} (Latest: ${GREEN}${latest:-N/A}${NC})"
                ;;
            "latest-tag")
                echo -e "  ${CYAN}○${NC} Web3Signer:  ${CYAN}${current}${NC} (Using 'latest' tag)"
                ;;
            "outdated")
                echo -e "  ${YELLOW}⚠${NC} Web3Signer:  ${YELLOW}${current}${NC} → Latest: ${GREEN}${latest}${NC}"
                ;;
            *)
                echo -e "  ${BLUE}?${NC} Web3Signer:  ${current} (Latest: ${latest:-Unable to fetch})"
                ;;
        esac
    fi
    
    echo ""
    
    # DVT & Other Services
    echo -e "${GREEN}DVT & Other Services:${NC}"
    echo -e "${YELLOW}───────────────────────────────────────────────────────────────${NC}"
    
    if [ -n "${CHARON_VERSION:-}" ]; then
        local current="${CHARON_VERSION}"
        local latest=$(get_latest_version "CHARON_VERSION")
        local status=$(compare_versions "$current" "$latest")
        
        case "$status" in
            "up-to-date")
                echo -e "  ${GREEN}✓${NC} Charon:      ${GREEN}${current}${NC} (Latest: ${GREEN}${latest:-N/A}${NC})"
                ;;
            "latest-tag")
                echo -e "  ${CYAN}○${NC} Charon:      ${CYAN}${current}${NC} (Using 'latest' tag)"
                ;;
            "outdated")
                echo -e "  ${YELLOW}⚠${NC} Charon:      ${YELLOW}${current}${NC} → Latest: ${GREEN}${latest}${NC}"
                ;;
            *)
                echo -e "  ${BLUE}?${NC} Charon:      ${current} (Latest: ${latest:-Unable to fetch})"
                ;;
        esac
    fi
    
    if [ -n "${SSV_VERSION:-}" ]; then
        local current="${SSV_VERSION}"
        local latest=$(get_latest_version "SSV_VERSION")
        local status=$(compare_versions "$current" "$latest")
        
        case "$status" in
            "up-to-date")
                echo -e "  ${GREEN}✓${NC} SSV:         ${GREEN}${current}${NC} (Latest: ${GREEN}${latest:-N/A}${NC})"
                ;;
            "latest-tag")
                echo -e "  ${CYAN}○${NC} SSV:         ${CYAN}${current}${NC} (Using 'latest' tag)"
                ;;
            "outdated")
                echo -e "  ${YELLOW}⚠${NC} SSV:         ${YELLOW}${current}${NC} → Latest: ${GREEN}${latest}${NC}"
                ;;
            *)
                echo -e "  ${BLUE}?${NC} SSV:         ${current} (Latest: ${latest:-Unable to fetch})"
                ;;
        esac
    fi
    
    if [ -n "${SSV_DKG_VERSION:-}" ]; then
        local current="${SSV_DKG_VERSION}"
        local latest=$(get_latest_version "SSV_DKG_VERSION")
        local status=$(compare_versions "$current" "$latest")
        
        case "$status" in
            "up-to-date")
                echo -e "  ${GREEN}✓${NC} SSV DKG:     ${GREEN}${current}${NC} (Latest: ${GREEN}${latest:-N/A}${NC})"
                ;;
            "latest-tag")
                echo -e "  ${CYAN}○${NC} SSV DKG:     ${CYAN}${current}${NC} (Using 'latest' tag)"
                ;;
            "outdated")
                echo -e "  ${YELLOW}⚠${NC} SSV DKG:     ${YELLOW}${current}${NC} → Latest: ${GREEN}${latest}${NC}"
                ;;
            *)
                echo -e "  ${BLUE}?${NC} SSV DKG:     ${current} (Latest: ${latest:-Unable to fetch})"
                ;;
        esac
    fi
    
    if [ -n "${STAKEWISE_VERSION:-}" ]; then
        local current="${STAKEWISE_VERSION}"
        local latest=$(get_latest_version "STAKEWISE_VERSION")
        local status=$(compare_versions "$current" "$latest")
        
        case "$status" in
            "up-to-date")
                echo -e "  ${GREEN}✓${NC} Stakewise:   ${GREEN}${current}${NC} (Latest: ${GREEN}${latest:-N/A}${NC})"
                ;;
            "latest-tag")
                echo -e "  ${CYAN}○${NC} Stakewise:   ${CYAN}${current}${NC} (Using 'latest' tag)"
                ;;
            "outdated")
                echo -e "  ${YELLOW}⚠${NC} Stakewise:   ${YELLOW}${current}${NC} → Latest: ${GREEN}${latest}${NC}"
                ;;
            *)
                echo -e "  ${BLUE}?${NC} Stakewise:   ${current} (Latest: ${latest:-Unable to fetch})"
                ;;
        esac
    fi
    
    echo ""
    echo -e "${CYAN}Legend:${NC}"
    echo -e "  ${GREEN}✓${NC} Up to date"
    echo -e "  ${YELLOW}⚠${NC} Update available"
    echo -e "  ${CYAN}○${NC} Using 'latest' tag"
    echo -e "  ${BLUE}?${NC} Unable to check"
    echo ""
    read -p "Press Enter to continue..."
}

# Run if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    show_version_info
fi

