#!/usr/bin/env bash
set -euo pipefail

# Maintenance Menu System
# Provides management options for deployed services

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.generated.yaml"

# Source utilities
if [ ! -f "$SCRIPT_DIR/utils.sh" ]; then
    echo "Error: utils.sh not found at $SCRIPT_DIR/utils.sh" >&2
    exit 1
fi
source "$SCRIPT_DIR/utils.sh"

if [ ! -f "$SCRIPT_DIR/state-manager.sh" ]; then
    echo "Error: state-manager.sh not found at $SCRIPT_DIR/state-manager.sh" >&2
    exit 1
fi
source "$SCRIPT_DIR/state-manager.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Print header
print_header() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     Ethereum Node Maintenance & Management              ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Show current deployment status
show_status() {
    print_header
    
    if [ ! -f "$COMPOSE_FILE" ]; then
        print_warning "No deployment found (docker-compose.generated.yaml not found)"
        return 1
    fi
    
    # Detect current configuration
    local current_config=$(detect_current_config)
    
    # Calculate running services count (same as main menu)
    local running_count=0
    if [ -f "$COMPOSE_FILE" ]; then
        # Use grep method as primary (more reliable)
        running_count=$(docker compose -f "$COMPOSE_FILE" ps --format "{{.State}}" 2>/dev/null | grep -c "^running$" 2>/dev/null || echo "0")
        
        # Ensure running_count is a valid number
        if [ -z "$running_count" ] || [ "$running_count" = "" ] || ! [[ "$running_count" =~ ^[0-9]+$ ]]; then
            running_count=0
        fi
    fi
    
    # Display status header (same format as main menu)
    if [ "$running_count" -gt 0 ]; then
        echo -e "${GREEN}Status: Running ($running_count services)${NC}"
    else
        echo -e "${YELLOW}Status: Stopped${NC}"
    fi
    echo ""
    
    # Parse current config to get service names
    local network=""
    local ec=""
    local cc=""
    local mev=""
    local vc=""
    local dvt=""
    
    if command_exists jq && echo "$current_config" | jq -e . >/dev/null 2>&1; then
        network=$(echo "$current_config" | jq -r '.network // ""')
        ec=$(echo "$current_config" | jq -r '.ec // ""')
        cc=$(echo "$current_config" | jq -r '.cc // ""')
        mev=$(echo "$current_config" | jq -r '.mev // ""')
        vc=$(echo "$current_config" | jq -r '.vc // ""')
        dvt=$(echo "$current_config" | jq -r '.dvt // ""')
    else
        network=$(echo "$current_config" | grep -o '"network":"[^"]*"' | cut -d'"' -f4 || echo "")
        ec=$(echo "$current_config" | grep -o '"ec":"[^"]*"' | cut -d'"' -f4 || echo "")
        cc=$(echo "$current_config" | grep -o '"cc":"[^"]*"' | cut -d'"' -f4 || echo "")
        mev=$(echo "$current_config" | grep -o '"mev":"[^"]*"' | cut -d'"' -f4 || echo "")
        vc=$(echo "$current_config" | grep -o '"vc":"[^"]*"' | cut -d'"' -f4 || echo "")
        dvt=$(echo "$current_config" | grep -o '"dvt":"[^"]*"' | cut -d'"' -f4 || echo "")
    fi
    
    # Display in Current Selection format (same as main menu)
    echo -e "  Network:     ${GREEN}${network:-not set}${NC}"
    
    # Execution Client
    if [ -n "$ec" ] && [ "$ec" != "none" ]; then
        local ec_info=$(get_container_info "execution-client")
        echo -e "  EC:          ${GREEN}${ec}${CYAN}${ec_info}${NC}"
    else
        echo -e "  EC:          ${GREEN}not set${NC}"
    fi
    
    # Consensus Client
    if [ -n "$cc" ] && [ "$cc" != "none" ]; then
        local cc_info=$(get_container_info "consensus-client")
        echo -e "  CC:          ${GREEN}${cc}${CYAN}${cc_info}${NC}"
    else
        echo -e "  CC:          ${GREEN}not set${NC}"
    fi
    
    # MEV
    if [ -n "$mev" ] && [ "$mev" != "none" ]; then
        local mev_display=""
        local mev_service=""
        case "$mev" in
            mevboost)
                mev_display="MEV-Boost"
                mev_service="mev-boost"
                ;;
            commitboost)
                mev_display="Commit Boost"
                mev_service="commit-boost"
                ;;
            both)
                mev_display="Both"
                mev_service="mev-boost"
                ;;
            *)
                mev_display="$mev"
                mev_service="mev-boost"
                ;;
        esac
        local mev_info=$(get_container_info "$mev_service")
        echo -e "  MEV:         ${GREEN}${mev_display}${CYAN}${mev_info}${NC}"
    else
        echo -e "  MEV:         ${GREEN}not set${NC}"
    fi
    
    # VC/DVT
    if [ -n "$vc" ] && [ "$vc" != "none" ]; then
        local vc_display=""
        local vc_service=""
        case "$vc" in
            lighthouse)
                vc_display="Lighthouse VC"
                vc_service="lighthouse-vc"
                ;;
            teku)
                vc_display="Teku VC"
                vc_service="teku-vc"
                ;;
            lodestar)
                vc_display="Lodestar VC"
                vc_service="lodestar-vc"
                ;;
            *)
                vc_display="$vc"
                vc_service="validator-client"
                ;;
        esac
        local vc_info=$(get_container_info "$vc_service")
        echo -e "  VC/DVT:      ${GREEN}${vc_display}${CYAN}${vc_info}${NC}"
    elif [ -n "$dvt" ] && [ "$dvt" != "none" ]; then
        local dvt_display=""
        local dvt_service=""
        case "$dvt" in
            obol)
                dvt_display="Obol DVT"
                dvt_service="charon"
                ;;
            ssv)
                dvt_display="SSV DVT"
                dvt_service="ssv-node"
                ;;
            *)
                dvt_display="$dvt"
                dvt_service="validator-client"
                ;;
        esac
        local dvt_info=$(get_container_info "$dvt_service")
        echo -e "  VC/DVT:      ${GREEN}${dvt_display}${CYAN}${dvt_info}${NC}"
    else
        echo -e "  VC/DVT:      ${GREEN}not set${NC}"
    fi
    
    echo ""
}

# Stop services
stop_services() {
    print_header
    show_status
    
    if [ ! -f "$COMPOSE_FILE" ]; then
        print_error "No deployment found"
        return 1
    fi
    
    echo -e "${YELLOW}This will stop all running services.${NC}"
    read -p "Continue? [y/N]: " confirm
    
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        print_info "Cancelled"
        return
    fi
    
    print_info "Stopping services..."
    docker compose -f "$COMPOSE_FILE" stop
    
    if [ $? -eq 0 ]; then
        print_success "Services stopped successfully"
        log_deployment "STOP" "$(detect_current_config)"
    else
        print_error "Failed to stop services"
        return 1
    fi
}

# Restart services
restart_services() {
    print_header
    show_status
    
    if [ ! -f "$COMPOSE_FILE" ]; then
        print_error "No deployment found"
        return 1
    fi
    
    echo -e "${YELLOW}This will restart all services.${NC}"
    read -p "Continue? [y/N]: " confirm
    
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        print_info "Cancelled"
        return
    fi
    
    print_info "Restarting services..."
    docker compose -f "$COMPOSE_FILE" restart
    
    if [ $? -eq 0 ]; then
        print_success "Services restarted successfully"
        log_deployment "RESTART" "$(detect_current_config)"
    else
        print_error "Failed to restart services"
        return 1
    fi
}

# Complete removal (including data)
remove_all() {
    print_header
    show_status
    
    if [ ! -f "$COMPOSE_FILE" ]; then
        print_error "No deployment found"
        return 1
    fi
    
    echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                    WARNING: DESTRUCTIVE ACTION              ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${RED}This will:${NC}"
    echo "  1. Stop and remove all containers"
    echo "  2. Remove all volumes (including chain data)"
    echo "  3. Remove generated compose file"
    echo "  4. Remove deployment state"
    echo ""
    echo -e "${YELLOW}This action CANNOT be undone!${NC}"
    echo ""
    
    # First confirmation
    echo -e "${RED}First confirmation:${NC}"
    read -p "Are you sure you want to delete everything? [y/N]: " confirm1
    if [[ ! $confirm1 =~ ^[Yy]$ ]]; then
        print_info "Cancelled"
        return
    fi
    
    # Second confirmation
    echo ""
    echo -e "${RED}Second confirmation:${NC}"
    read -p "This will permanently delete all data. Continue? [y/N]: " confirm2
    if [[ ! $confirm2 =~ ^[Yy]$ ]]; then
        print_info "Cancelled"
        return
    fi
    
    # Third confirmation
    echo ""
    echo -e "${RED}Third confirmation:${NC}"
    read -p "Final confirmation - type 'yes' to proceed: " confirm3
    if [ "$confirm3" != "yes" ]; then
        print_info "Cancelled"
        return
    fi
    
    # Ask about backup
    echo ""
    read -p "Create backup before deletion? [y/N]: " backup_confirm
    
    if [[ $backup_confirm =~ ^[Yy]$ ]]; then
        print_info "Creating backup..."
        if [ -f "$PROJECT_ROOT/scripts/backup/backup.sh" ]; then
            local network="mainnet"
            local current_config=$(detect_current_config)
            if command_exists jq; then
                network=$(echo "$current_config" | jq -r '.network // "mainnet"')
            else
                # Fallback parsing without jq
                network=$(echo "$current_config" | grep -o '"network":"[^"]*"' | cut -d'"' -f4 || echo "mainnet")
            fi
            bash "$PROJECT_ROOT/scripts/backup/backup.sh" "$network"
        else
            print_warning "Backup script not found, skipping backup"
        fi
    fi
    
    # First, stop running services
    print_info "Stopping running services..."
    docker compose -f "$COMPOSE_FILE" stop 2>/dev/null || true
    
    # Then, remove containers, volumes, and networks
    print_info "Removing services, containers, volumes, and networks..."
    docker compose -f "$COMPOSE_FILE" down -v --remove-orphans
    
    print_info "Removing generated files..."
    rm -f "$COMPOSE_FILE"
    rm -f "$PROJECT_ROOT/.deploy/current.json"
    
    print_success "Complete removal finished"
    log_deployment "REMOVE_ALL" "$(detect_current_config)"
}

# Filter logs by level
filter_logs_by_level() {
    local level="$1"
    local service="${2:-}"
    
    case "$level" in
        error)
            if [ -n "$service" ]; then
                docker compose -f "$COMPOSE_FILE" logs --tail=1000 -f "$service" 2>&1 | grep -iE "(error|err|failed|failure|critical|fatal)" --color=always
            else
                docker compose -f "$COMPOSE_FILE" logs --tail=1000 -f 2>&1 | grep -iE "(error|err|failed|failure|critical|fatal)" --color=always
            fi
            ;;
        warn)
            if [ -n "$service" ]; then
                docker compose -f "$COMPOSE_FILE" logs --tail=1000 -f "$service" 2>&1 | grep -iE "(warn|warning|wrn)" --color=always
            else
                docker compose -f "$COMPOSE_FILE" logs --tail=1000 -f 2>&1 | grep -iE "(warn|warning|wrn)" --color=always
            fi
            ;;
        all|*)
            if [ -n "$service" ]; then
                docker compose -f "$COMPOSE_FILE" logs --tail=1000 -f "$service"
            else
                docker compose -f "$COMPOSE_FILE" logs --tail=1000 -f
            fi
            ;;
    esac
}

# Save logs to file
save_logs() {
    print_header
    
    if [ ! -f "$COMPOSE_FILE" ]; then
        print_error "No deployment found"
        return 1
    fi
    
    echo -e "${CYAN}Save Logs (Last 1000 lines)${NC}"
    echo ""
    
    # Get services
    local services
    if command_exists jq; then
        services=$(docker compose -f "$COMPOSE_FILE" ps --format json 2>/dev/null | \
            jq -r '.[] | "\(.Service)"' 2>/dev/null | sort -u)
    else
        services=$(docker compose -f "$COMPOSE_FILE" ps --format "{{.Service}}" 2>/dev/null | sort -u)
    fi
    
    if [ -z "$services" ]; then
        print_warning "No services found"
        return 1
    fi
    
    local service_list=($services)
    local i=1
    for service in "${service_list[@]}"; do
        echo "  $i) $service"
        i=$((i + 1))
    done
    echo "  0) All services"
    echo ""
    
    read -p "Select service [0-$((i-1))]: " choice
    
    # Validate input
    if [ -z "$choice" ]; then
        print_error "No selection made"
        return 1
    fi
    
    local selected_service=""
    if [ "$choice" = "0" ]; then
        selected_service=""
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#service_list[@]}" ]; then
        selected_service="${service_list[$((choice-1))]}"
    else
        print_error "Invalid selection: $choice"
        return 1
    fi
    
    # Create logs directory
    local logs_dir="$PROJECT_ROOT/logs"
    mkdir -p "$logs_dir"
    
    # Generate filename
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local log_file
    if [ -n "$selected_service" ]; then
        log_file="$logs_dir/${selected_service}_${timestamp}.log"
    else
        log_file="$logs_dir/all_services_${timestamp}.log"
    fi
    
    print_info "Saving last 1000 lines to: $log_file"
    
    if [ -n "$selected_service" ]; then
        docker compose -f "$COMPOSE_FILE" logs --tail=1000 "$selected_service" > "$log_file" 2>&1
    else
        docker compose -f "$COMPOSE_FILE" logs --tail=1000 > "$log_file" 2>&1
    fi
    
    if [ $? -eq 0 ]; then
        local line_count=$(wc -l < "$log_file" | tr -d ' ')
        print_success "Logs saved successfully ($line_count lines)"
        echo ""
        echo "File location: $log_file"
        echo ""
        read -p "Press Enter to continue..."
    else
        print_error "Failed to save logs"
        return 1
    fi
}

# View logs with real-time interface
view_logs() {
    print_header
    
    if [ ! -f "$COMPOSE_FILE" ]; then
        print_error "No deployment found"
        return 1
    fi
    
    echo -e "${CYAN}Select service to view logs:${NC}"
    echo ""
    
    local services
    if command_exists jq; then
        services=$(docker compose -f "$COMPOSE_FILE" ps --format json 2>/dev/null | \
            jq -r '.[] | "\(.Service)"' 2>/dev/null | sort -u)
    else
        services=$(docker compose -f "$COMPOSE_FILE" ps --format "{{.Service}}" 2>/dev/null | sort -u)
    fi
    
    if [ -z "$services" ]; then
        print_warning "No services found"
        return 1
    fi
    
    local service_list=($services)
    local i=1
    for service in "${service_list[@]}"; do
        echo "  $i) $service"
        i=$((i + 1))
    done
    echo "  0) All services"
    echo ""
    
    read -p "Select service [0-$((i-1))]: " choice
    
    # Validate input
    if [ -z "$choice" ]; then
        print_error "No selection made"
        return 1
    fi
    
    local selected_service=""
    if [ "$choice" = "0" ]; then
        selected_service=""
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#service_list[@]}" ]; then
        selected_service="${service_list[$((choice-1))]}"
    else
        print_error "Invalid selection: $choice"
        return 1
    fi
    
    # Select log level or save
    clear
    print_header
    echo -e "${CYAN}Select log level or save:${NC}"
    echo ""
    if [ -n "$selected_service" ]; then
        echo -e "  Service: ${GREEN}$selected_service${NC}"
    else
        echo -e "  Service: ${GREEN}All services${NC}"
    fi
    echo ""
    echo "  1) All logs"
    echo "  2) Error level only"
    echo "  3) Warning level only"
    echo "  4) Save logs (Last 1000 lines)"
    echo "  0) Back"
    echo ""
    read -p "Select option [1-4, 0]: " level_choice
    
    case "$level_choice" in
        1)
            clear
            echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
            echo -e "${GREEN}  Real-time Logs: ${selected_service:-All services} - All levels${NC}"
            echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
            echo -e "${YELLOW}Press Ctrl+C to exit${NC}"
            echo ""
            filter_logs_by_level "all" "$selected_service"
            ;;
        2)
            clear
            echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
            echo -e "${RED}  Real-time Logs: ${selected_service:-All services} - Error level${NC}"
            echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
            echo -e "${YELLOW}Press Ctrl+C to exit${NC}"
            echo ""
            filter_logs_by_level "error" "$selected_service"
            ;;
        3)
            clear
            echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
            echo -e "${YELLOW}  Real-time Logs: ${selected_service:-All services} - Warning level${NC}"
            echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
            echo -e "${YELLOW}Press Ctrl+C to exit${NC}"
            echo ""
            filter_logs_by_level "warn" "$selected_service"
            ;;
        4)
            # Save logs for selected service
            clear
            print_header
            
            # Create logs directory
            local logs_dir="$PROJECT_ROOT/logs"
            mkdir -p "$logs_dir"
            
            # Generate filename
            local timestamp=$(date +"%Y%m%d_%H%M%S")
            local log_file
            if [ -n "$selected_service" ]; then
                log_file="$logs_dir/${selected_service}_${timestamp}.log"
            else
                log_file="$logs_dir/all_services_${timestamp}.log"
            fi
            
            print_info "Saving last 1000 lines to: $log_file"
            
            if [ -n "$selected_service" ]; then
                docker compose -f "$COMPOSE_FILE" logs --tail=1000 "$selected_service" > "$log_file" 2>&1
            else
                docker compose -f "$COMPOSE_FILE" logs --tail=1000 > "$log_file" 2>&1
            fi
            
            if [ $? -eq 0 ]; then
                local line_count=$(wc -l < "$log_file" | tr -d ' ')
                print_success "Logs saved successfully ($line_count lines)"
                echo ""
                echo "File location: $log_file"
                echo ""
                read -p "Press Enter to continue..."
            else
                print_error "Failed to save logs"
                sleep 2
            fi
            ;;
        0)
            return
            ;;
        *)
            print_error "Invalid selection"
            sleep 1
            ;;
    esac
}

# Show deployment history
show_history() {
    print_header
    
    echo -e "${CYAN}Deployment History:${NC}"
    echo -e "${YELLOW}────────────────────────────────────────────────────────────${NC}"
    echo ""
    
    if [ -f "$LOG_FILE" ]; then
        tail -n 20 "$LOG_FILE" | while IFS= read -r line; do
            echo "  $line"
        done
    else
        print_info "No deployment history found"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# Main maintenance menu
main_menu() {
    while true; do
        print_header
        show_status
        
        echo -e "${BLUE}Maintenance Menu:${NC}"
        echo ""
        echo "  1) Stop Services"
        echo "  2) Restart Services"
        echo "  3) View Deployment History"
        echo "  4) Complete Removal (including data)"
        echo ""
        echo "  0) Back to Main Menu"
        echo ""
        read -p "Select option [0-4]: " choice
        
        # Validate input
        if [ -z "$choice" ]; then
            print_error "No selection made"
            sleep 1
            continue
        fi
        
        case $choice in
            1) stop_services; sleep 2; ;;
            2) restart_services; sleep 2; ;;
            3) show_history; ;;
            4) remove_all; sleep 2; ;;
            0) return 0; ;;
            *) print_error "Invalid selection"; sleep 1; ;;
        esac
    done
}

# Run if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main_menu
fi

