#!/bin/bash
################################################################################
# IoT Fire Prevention Platform - Automated Installer v2.0
# 
# Description: Interactive installation script for complete platform setup
# Requirements: Fresh Debian 13 (Trixie), root/sudo access
# Execution: sudo ./install.sh [--dry-run] [--resume]
#
# Author: Based on GUIA_DEFINITIVA_2.0_COMPLETA.md
# Date: 2024-11-26
################################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Script directory (absolute path)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load libraries
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/ui.sh"
source "${SCRIPT_DIR}/lib/validation.sh"
source "${SCRIPT_DIR}/lib/secrets.sh"
source "${SCRIPT_DIR}/lib/phases.sh"

# Global variables
INSTALL_STATE_FILE="${SCRIPT_DIR}/.install-state"
CONFIG_FILE="${SCRIPT_DIR}/.config.env"
SECRETS_FILE="${HOME}/.iot-platform/.secrets"
LOG_FILE="${SCRIPT_DIR}/logs/install-$(date +%Y%m%d-%H%M%S).log"
DRY_RUN=false
RESUME_MODE=false

################################################################################
# Pre-flight Checks
################################################################################
preflight_checks() {
    log_info "Running pre-flight checks..."
    
    # Check if running as root or with sudo
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo"
        log_error "Usage: sudo ./install.sh"
        exit 1
    fi
    
    # Check OS version
    if [[ ! -f /etc/debian_version ]]; then
        log_error "This script requires Debian Linux"
        exit 1
    fi
    
    local debian_version=$(cat /etc/debian_version | cut -d. -f1)
    if [[ "$debian_version" != "13" ]] && [[ "$debian_version" != "trixie"* ]]; then
        log_warning "This script is designed for Debian 13 (Trixie)"
        log_warning "Your version: $(cat /etc/debian_version)"
        read -p "Continue anyway? [y/N]: " confirm
        [[ "$confirm" != "y" ]] && exit 1
    fi
    
    # Check required commands
    local required_cmds=("git" "curl" "openssl" "bc")
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command not found: $cmd"
            log_error "Please install: apt-get update && apt-get install -y $cmd"
            exit 1
        fi
    done
    
    # Check internet connectivity
    if ! curl -s --max-time 5 https://google.com > /dev/null 2>&1; then
        log_error "No internet connectivity detected"
        log_error "This script requires internet access to download packages"
        exit 1
    fi
    
    log_success "Pre-flight checks passed"
}

################################################################################
# Parse Command Line Arguments
################################################################################
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --resume)
                RESUME_MODE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

################################################################################
# Show Help
################################################################################
show_help() {
    cat << EOF
IoT Fire Prevention Platform - Automated Installer v2.0

USAGE:
    sudo ./install.sh [OPTIONS]

OPTIONS:
    --dry-run       Preview installation steps without executing any changes.
                    When this flag is used, the interactive menu is skipped
                    and the script proceeds directly to show the installation plan.
    --resume        Resume from last successful checkpoint
    -h, --help      Show this help message

EXAMPLES:
    # Normal installation (shows interactive menu)
    sudo ./install.sh

    # Preview installation steps (skips menu, no system changes)
    sudo ./install.sh --dry-run

    # Resume after interruption
    sudo ./install.sh --resume

REQUIREMENTS:
    - Fresh Debian 13 (Trixie) VPS
    - Root or sudo access
    - Internet connectivity
    - Minimum 4GB RAM, 20GB disk

For full documentation, see README.md
EOF
}

################################################################################
# Welcome Screen
################################################################################
show_welcome() {
    clear
    show_banner "IoT Fire Prevention Platform"
    
    echo -e "
${BLUE}═══════════════════════════════════════════════════════════════════${RESET}
${BOLD}              AUTOMATED INSTALLATION SYSTEM v2.0                   ${RESET}
${BLUE}═══════════════════════════════════════════════════════════════════${RESET}

${YELLOW}⚠️  WARNING - READ CAREFULLY ⚠️${RESET}

This script will:
  • Modify system configuration (firewall, SSH, users)
  • Install Docker, MySQL, Redis, Nginx, and application code
  • Change SSH port from 22 to custom port
  • Remove default 'debian' user (if present)
  • Configure production-grade security (5 layers)

${RED}CRITICAL REQUIREMENTS:${RESET}
  ✓ Fresh Debian 13 VPS (not production system)
  ✓ Stable internet connection
  ✓ ~3-4 hours of dedicated time
  ✓ VPS console access (in case SSH breaks)

${GREEN}WHAT YOU'LL GET:${RESET}
  ✓ Complete IoT platform with FastAPI backend
  ✓ 4 authentication types (User, Admin, Manager, Device)
  ✓ Cryptographic device authentication (AES-256 + HMAC)
  ✓ MySQL + Redis active, MongoDB reserved for future
  ✓ 5-layer security (nftables → Fail2Ban → Nginx → FastAPI → DB)
  ✓ Zero database exposure (internal Docker network only)
  ✓ Single session enforcement per user

${BLUE}═══════════════════════════════════════════════════════════════════${RESET}
"

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${CYAN}║  🔍 DRY-RUN MODE ACTIVE - No changes will be made to the system   ║${RESET}"
        echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${RESET}"
        echo ""
    fi
}

################################################################################
# Main Menu
################################################################################
show_main_menu() {
    echo ""
    echo -e "${BOLD}Select an option:${RESET}"
    echo ""
    echo -e "  ${GREEN}1)${RESET} Start Installation ${RED}(will modify your system)${RESET}"
    echo -e "  ${CYAN}2)${RESET} Dry-Run ${CYAN}(preview only, no changes)${RESET}"
    echo -e "  ${YELLOW}3)${RESET} Resume from checkpoint"
    echo -e "  ${RED}4)${RESET} Exit"
    echo ""
    echo -e "  ${YELLOW}TIP:${RESET} Use ${CYAN}--dry-run${RESET} flag to skip this menu and preview directly."
    echo ""
    
    local choice
    read -p "Enter choice [1-4]: " choice
    
    case $choice in
        1)
            # Confirm real installation
            echo ""
            echo -e "${YELLOW}⚠️  You are about to start a REAL installation.${RESET}"
            echo -e "${YELLOW}   This will modify your system configuration.${RESET}"
            read -p "Are you sure? [y/N]: " confirm_install
            if [[ "$confirm_install" != "y" && "$confirm_install" != "Y" ]]; then
                log_info "Installation cancelled"
                show_main_menu
                return
            fi
            DRY_RUN=false  # Explicitly set to false for real installation
            return 0
            ;;
        2)
            DRY_RUN=true
            log_info "Entering dry-run mode (no changes will be made)..."
            return 0
            ;;
        3)
            if [[ ! -f "$INSTALL_STATE_FILE" ]]; then
                log_error "No checkpoint found. Cannot resume."
                log_error "Start a new installation instead."
                exit 1
            fi
            RESUME_MODE=true
            return 0
            ;;
        4)
            log_info "Installation cancelled by user"
            exit 0
            ;;
        *)
            log_error "Invalid choice"
            show_main_menu
            ;;
    esac
}

################################################################################
# Collect User Inputs
################################################################################
collect_user_inputs() {
    log_info "Collecting configuration parameters..."
    echo ""
    
    # Auto-detect current IP
    local detected_ip=$(hostname -I | awk '{print $1}')
    
    # VPS IP Address
    read -p "VPS IP Address [${detected_ip}]: " VPS_IP
    VPS_IP=${VPS_IP:-$detected_ip}
    validate_ip "$VPS_IP" || { log_error "Invalid IP address"; exit 1; }
    
    # New username
    read -p "New username (will replace debian/root) [iotadmin]: " NEW_USERNAME
    NEW_USERNAME=${NEW_USERNAME:-iotadmin}
    validate_username "$NEW_USERNAME" || { log_error "Invalid username"; exit 1; }
    
    # SSH Port
    read -p "SSH Port [5259]: " SSH_PORT
    SSH_PORT=${SSH_PORT:-5259}
    validate_port "$SSH_PORT" || { log_error "Invalid port"; exit 1; }
    
    # Domain (optional)
    read -p "Domain name (optional, for future SSL) [none]: " DOMAIN
    DOMAIN=${DOMAIN:-none}
    
    # MySQL database name
    read -p "MySQL database name [iot_platform]: " DB_NAME
    DB_NAME=${DB_NAME:-iot_platform}
    validate_db_name "$DB_NAME" || { log_error "Invalid database name"; exit 1; }
    
    # Docker subnet
    read -p "Docker network subnet [172.20.0.0/16]: " DOCKER_SUBNET
    DOCKER_SUBNET=${DOCKER_SUBNET:-172.20.0.0/16}
    validate_subnet "$DOCKER_SUBNET" || { log_error "Invalid subnet"; exit 1; }
    
    # Redis memory limit
    read -p "Redis memory limit [256MB]: " REDIS_MEMORY
    REDIS_MEMORY=${REDIS_MEMORY:-256MB}
    
    # Timezone (auto-detect)
    local detected_tz=$(timedatectl show -p Timezone --value 2>/dev/null || echo "UTC")
    read -p "Timezone [${detected_tz}]: " TIMEZONE
    TIMEZONE=${TIMEZONE:-$detected_tz}
    
    echo ""
    log_success "Configuration collected"
}

################################################################################
# Generate Configuration Summary
################################################################################
show_configuration_summary() {
    echo ""
    show_section_header "Configuration Summary"
    
    echo -e "
${BOLD}System Configuration:${RESET}
  VPS IP:           ${GREEN}${VPS_IP}${RESET}
  New Username:     ${GREEN}${NEW_USERNAME}${RESET}
  SSH Port:         ${GREEN}${SSH_PORT}${RESET}
  Domain:           ${GREEN}${DOMAIN}${RESET}
  Timezone:         ${GREEN}${TIMEZONE}${RESET}

${BOLD}Database Configuration:${RESET}
  Database Name:    ${GREEN}${DB_NAME}${RESET}
  Docker Subnet:    ${GREEN}${DOCKER_SUBNET}${RESET}
  Redis Memory:     ${GREEN}${REDIS_MEMORY}${RESET}

${BOLD}Auto-Generated Secrets:${RESET}
  MySQL Root Password:   ${CYAN}[generated]${RESET}
  MySQL User Password:   ${CYAN}[generated]${RESET}
  Redis Password:        ${CYAN}[generated]${RESET}
  JWT Secret Key:        ${CYAN}[generated]${RESET}
  
${YELLOW}Secrets will be saved to: ${SECRETS_FILE}${RESET}
${YELLOW}You MUST backup this file after installation!${RESET}
"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${CYAN}═══ DRY-RUN MODE: No changes will be made ═══${RESET}"
        echo ""
    fi
    
    read -p "Proceed with installation? [y/N]: " confirm
    if [[ "$confirm" != "y" ]]; then log_info "Installation cancelled"; exit 0; fi
}

################################################################################
# Save Configuration
################################################################################
save_configuration() {
    log_info "Saving configuration..."
    
    # Create config file
    cat > "$CONFIG_FILE" << EOF
# IoT Platform Installation Configuration
# Generated: $(date)

VPS_IP="$VPS_IP"
NEW_USERNAME="$NEW_USERNAME"
SSH_PORT="$SSH_PORT"
DOMAIN="$DOMAIN"
DB_NAME="$DB_NAME"
DOCKER_SUBNET="$DOCKER_SUBNET"
REDIS_MEMORY="$REDIS_MEMORY"
TIMEZONE="$TIMEZONE"

# Paths
INSTALL_DIR="/home/${NEW_USERNAME}/iot-platform"
SCRIPT_DIR="$SCRIPT_DIR"
SECRETS_FILE="$SECRETS_FILE"
EOF
    
    chmod 600 "$CONFIG_FILE"
    log_success "Configuration saved to $CONFIG_FILE"
}

################################################################################
# Execute Installation Phases
################################################################################
execute_installation() {
    local start_phase=0
    
    # Load checkpoint if resuming
    if [[ "$RESUME_MODE" == true ]]; then
        source "$INSTALL_STATE_FILE"
        start_phase=$((LAST_COMPLETED_PHASE + 1))
        log_info "Resuming from Phase $start_phase"
    fi
    
    # Load configuration
    [[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"
    
    # Generate secrets if not resuming
    if [[ "$start_phase" -eq 0 && "$DRY_RUN" != true ]]; then
        generate_all_secrets
    else
        # Load existing secrets
        mkdir -p "$(dirname "$SECRETS_FILE")"
        [[ -f "$SECRETS_FILE" ]] && source "$SECRETS_FILE"
    fi
    
    # Show installation plan
    show_section_header "Installation Plan"
    echo ""
    echo "Total phases: 13 (FASE 0 - FASE 12)"
    echo "Estimated time: ~3 hours 15 minutes"
    echo "Starting from: Phase $start_phase"
    echo ""
    
    if [[ "$DRY_RUN" == true ]]; then
        show_dry_run_plan
        if [[ $? -eq 0 ]]; then
            DRY_RUN=false
        else
            return 0
        fi
    fi
    
    # Execute phases
    local phases=(
        "phase_0_preparation"
        "phase_1_user_management"
        "phase_2_dependencies"
        "phase_3_firewall"
        "phase_4_fail2ban"
        "phase_5_ssh_hardening"
        "phase_6_docker"
        "phase_7_project_structure"
        "phase_8_fastapi_app"
        "phase_9_mysql_init"
        "phase_10_nginx"
        "phase_11_deployment"
        "phase_12_testing"
    )
    
    local total_phases=${#phases[@]}
    
    for i in $(seq $start_phase $((total_phases - 1))); do
        local phase_func="${phases[$i]}"
        local phase_num=$i
        
        show_phase_header "$phase_num" "$total_phases" "${phase_func}"
        
        # Execute phase
        $phase_func
        
        # Save checkpoint
        save_checkpoint "$phase_num"
        
        show_phase_complete "$phase_num"
    done
    
    # Installation complete
    show_installation_complete
}

################################################################################
# Save Checkpoint
################################################################################
save_checkpoint() {
    local phase_num=$1
    
    cat > "$INSTALL_STATE_FILE" << EOF
LAST_COMPLETED_PHASE=$phase_num
TIMESTAMP=$(date +%s)
DATE="$(date)"
EOF
    
    log_info "Checkpoint saved (Phase $phase_num)"
}

################################################################################
# Show Installation Complete
################################################################################
show_installation_complete() {
    clear
    show_banner "Installation Complete!"
    
    echo -e "
${GREEN}╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║          ✓ IoT PLATFORM INSTALLED SUCCESSFULLY                    ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝${RESET}

${BOLD}Installation Summary:${RESET}
  Duration:         $(calculate_duration)
  Phases Completed: 13/13
  Status:           ${GREEN}SUCCESS${RESET}

${BOLD}Access Information:${RESET}
  SSH Access:       ${CYAN}ssh $NEW_USERNAME@$VPS_IP -p $SSH_PORT${RESET}
  API Endpoint:     ${CYAN}http://$VPS_IP/api/v1${RESET}
  Health Check:     ${CYAN}http://$VPS_IP/health${RESET}

${BOLD}Default Credentials (CHANGE IMMEDIATELY):${RESET}
  Admin:            ${YELLOW}admin@iot-platform.com / admin123${RESET}
  User:             ${YELLOW}user@iot-platform.com / user123${RESET}
  Manager:          ${YELLOW}manager@iot-platform.com / manager123${RESET}

${BOLD}Secrets Location:${RESET}
  ${RED}${SECRETS_FILE}${RESET}
  
  ${YELLOW}⚠️  CRITICAL: Backup this file NOW! ⚠️${RESET}
  
  Run: ${CYAN}cat ${SECRETS_FILE}${RESET}

${BOLD}Next Steps:${RESET}
  1. Backup secrets file
  2. Change default passwords via API
  3. Test authentication: curl http://$VPS_IP/api/v1/auth/login/admin
  4. Setup SSL/TLS (recommended)
  5. Configure monitoring

${BOLD}Documentation:${RESET}
  Installation log: ${LOG_FILE}
  Full guide:       GUIA_DEFINITIVA_2.0_COMPLETA.md

${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}
"
}

################################################################################
# Calculate Duration
################################################################################
calculate_duration() {
    if [[ -f "$INSTALL_STATE_FILE" ]]; then
        source "$INSTALL_STATE_FILE"
        local start_time=$TIMESTAMP
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        local hours=$((duration / 3600))
        local minutes=$(((duration % 3600) / 60))
        local seconds=$((duration % 60))
        
        printf "%02d:%02d:%02d" $hours $minutes $seconds
    else
        echo "N/A"
    fi
}

################################################################################
# Main Execution
################################################################################
main() {
    # Setup logging
    mkdir -p "$(dirname "$LOG_FILE")"
    exec > >(tee -a "$LOG_FILE")
    exec 2>&1
    
    # Parse arguments
    parse_arguments "$@"
    
    # Pre-flight checks
    preflight_checks
    
    # Show welcome and menu (skip menu if --dry-run was passed via CLI)
    if [[ "$RESUME_MODE" != true ]]; then
        show_welcome
        
        # If --dry-run flag was passed, skip the menu entirely
        if [[ "$DRY_RUN" == true ]]; then
            log_info "Dry-run mode activated via --dry-run flag. Skipping menu..."
            echo ""
        else
            show_main_menu
        fi
    fi
    
    # Collect inputs or load config
    if [[ "$RESUME_MODE" == true ]]; then
        if [[ ! -f "$CONFIG_FILE" ]]; then
            log_error "Configuration file not found. Cannot resume."
            exit 1
        fi
        log_info "Loading saved configuration..."
        [[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"
    else
        collect_user_inputs
        show_configuration_summary
        [[ "$DRY_RUN" != true ]] && save_configuration
    fi
    
    # Execute installation
    execute_installation
}

# Run main function
main "$@"
