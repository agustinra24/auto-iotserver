#!/bin/bash
################################################################################
# lib/ui.sh - Terminal UI and display functions
################################################################################

# Show ASCII banner
show_banner() {
    local title="${1:-IoT Platform}"
    
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║               _____ _   _          ____  ______                   ║
║              |_   _| \ | |   /\   / __ \|  ____|                  ║
║                | | |  \| |  /  \ | |  | | |__                     ║
║                | | | . ` | / /\ \| |  | |  __|                    ║
║               _| |_| |\  |/ ____ \ |__| | |____                   ║
║              |_____|_| \_/_/    \_\____/|______|                  ║
║                                                                   ║
║              Fire Prevention Platform - Installer                 ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝
EOF
}

# Show section header
show_section_header() {
    local title="$1"
    local width=70
    
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BOLD}  $title${RESET}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
}

# Show phase header
show_phase_header() {
    local phase_num=$1
    local total_phases=$2
    local phase_name=$3
    
    # Extract friendly name from function name
    local friendly_name=$(echo "$phase_name" | sed 's/phase_[0-9]*_//' | tr '_' ' ' | sed 's/\b\(.\)/\u\1/g')
    
    local progress=$(calc_progress $phase_num $total_phases)
    
    clear
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${GREEN}║${RESET}  Phase $phase_num/$total_phases: $friendly_name"
    echo -e "${GREEN}║${RESET}  Progress: $(show_progress_bar $progress)"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

# Show progress bar
show_progress_bar() {
    local percent=$1
    local width=50
    local filled=$((percent * width / 100))
    local empty=$((width - filled))
    
    echo -n "["
    for i in $(seq 1 $filled); do echo -n "█"; done
    for i in $(seq 1 $empty); do echo -n "░"; done
    echo -n "] ${percent}%"
}

# Show phase complete
show_phase_complete() {
    local phase_num=$1
    
    echo ""
    echo -e "${GREEN}✓ Phase $phase_num completed successfully${RESET}"
    echo ""
    
    # Small delay for user to see completion
    sleep 1
}

# Show spinner
show_spinner() {
    local pid=$1
    local message="${2:-Processing...}"
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) %10 ))
        printf "\r${CYAN}${spin:$i:1}${RESET} $message"
        sleep 0.1
    done
    
    printf "\r${GREEN}✓${RESET} $message\n"
}

# Show task with status
show_task() {
    local task="$1"
    local status="${2:-running}"
    
    case $status in
        running)
            echo -n -e "  ${CYAN}⟳${RESET} $task..."
            ;;
        success)
            echo -e "\r  ${GREEN}✓${RESET} $task"
            ;;
        error)
            echo -e "\r  ${RED}✗${RESET} $task"
            ;;
        skip)
            echo -e "  ${YELLOW}○${RESET} $task (skipped)"
            ;;
    esac
}

# Complete current task
complete_task() {
    local task="$1"
    echo -e "\r  ${GREEN}✓${RESET} $task    "
}

# Show info box
show_info_box() {
    local title="$1"
    shift
    local lines=("$@")
    
    echo ""
    echo -e "${CYAN}┌─ $title ─────────────────────────────────────────┐${RESET}"
    for line in "${lines[@]}"; do
        echo -e "${CYAN}│${RESET} $line"
    done
    echo -e "${CYAN}└──────────────────────────────────────────────────┘${RESET}"
    echo ""
}

# Show warning box
show_warning_box() {
    local title="$1"
    shift
    local lines=("$@")
    
    echo ""
    echo -e "${YELLOW}┌─ ⚠️  $title ─────────────────────────────────────┐${RESET}"
    for line in "${lines[@]}"; do
        echo -e "${YELLOW}│${RESET} $line"
    done
    echo -e "${YELLOW}└──────────────────────────────────────────────────┘${RESET}"
    echo ""
}

# Show critical pause box
show_critical_pause() {
    local phase_name="$1"
    shift
    local instructions=("$@")
    
    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${RED}║${RESET}  ${BOLD}⚠️  CRITICAL VALIDATION REQUIRED - $phase_name${RESET}"
    echo -e "${RED}╠═══════════════════════════════════════════════════════════════════╣${RESET}"
    
    for instruction in "${instructions[@]}"; do
        echo -e "${RED}║${RESET}  $instruction"
    done
    
    echo -e "${RED}╠═══════════════════════════════════════════════════════════════════╣${RESET}"
    echo -e "${RED}║${RESET}  ${YELLOW}If ALL tests pass: Press ENTER to continue${RESET}"
    echo -e "${RED}║${RESET}  ${YELLOW}If ANY test fails: Press Ctrl+C to abort${RESET}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    
    read -p "Press ENTER when validated: "
}

# Show dry-run plan
show_dry_run_plan() {
    show_section_header "DRY-RUN: Installation Plan"
    
    echo -e "${BOLD}The following phases will be executed:${RESET}

${CYAN}[Phase 0]${RESET} Preparation
  • Verify system resources
  • Create installation directory
  • Setup logging

${CYAN}[Phase 1]${RESET} User Management ${RED}(REQUIRES VALIDATION)${RESET}
  • Create new user: $NEW_USERNAME
  • Grant sudo privileges
  • ${YELLOW}⚠️  PAUSE: Validate in second terminal${RESET}
  • Remove debian user

${CYAN}[Phase 2]${RESET} Core Dependencies
  • Update system packages
  • Install build tools, Python, network tools
  • Install monitoring utilities

${CYAN}[Phase 3]${RESET} Firewall (nftables)
  • Configure nftables rules
  • Create dynamic IP sets
  • Setup DROP policy with allowed ports

${CYAN}[Phase 4]${RESET} Fail2Ban
  • Install Fail2Ban
  • Configure SSH, Nginx jails
  • Integrate with nftables

${CYAN}[Phase 5]${RESET} SSH Hardening ${RED}(REQUIRES VALIDATION)${RESET}
  • Change SSH port: 22 → $SSH_PORT
  • ${YELLOW}⚠️  PAUSE: Test new port in second terminal${RESET}
  • Disable root login
  • Close port 22

${CYAN}[Phase 6]${RESET} Docker Installation
  • Add Docker repository
  • Install Docker + Docker Compose
  • Configure daemon
  • Add user to docker group

${CYAN}[Phase 7]${RESET} Project Structure
  • Create ~/iot-platform directory
  • Copy templates
  • Generate .env file

${CYAN}[Phase 8]${RESET} FastAPI Application
  • Create application files (25+ files)
  • Copy models, schemas, routers
  • Setup cryptographic device authentication
  • Build Docker image

${CYAN}[Phase 9]${RESET} MySQL Initialization
  • Create init.sql (14 tables)
  • Setup RBAC (roles, permissions)
  • Create test data

${CYAN}[Phase 10]${RESET} Nginx Configuration
  • Configure reverse proxy
  • Setup rate limiting
  • Add security headers

${CYAN}[Phase 11]${RESET} Deployment
  • Deploy with docker-compose
  • Wait for health checks
  • Verify all services running

${CYAN}[Phase 12]${RESET} Testing & Validation
  • Test authentication endpoints (4 types)
  • Verify session management
  • Test rate limiting
  • Validate database isolation

${BOLD}Estimated Total Time:${RESET} ~3 hours 15 minutes

${BOLD}Critical Pauses:${RESET}
  • Phase 1: User validation (manual test required)
  • Phase 5: SSH port validation (manual test required)

${BOLD}Generated Secrets:${RESET}
  All passwords and keys will be auto-generated and saved to:
  ${SECRETS_FILE}
"

    read -p "Proceed with actual installation? [y/N]: " proceed
    if [[ "$proceed" == "y" ]]; then return 0; else return 1; fi
}

# Show table
show_table() {
    local header=("$1")
    shift
    local rows=("$@")
    
    echo ""
    echo -e "${BOLD}$header${RESET}"
    echo "────────────────────────────────────────────────────────────────"
    for row in "${rows[@]}"; do
        echo "  $row"
    done
    echo ""
}

# Show checklist
show_checklist() {
    local title="$1"
    shift
    local items=("$@")
    
    echo ""
    echo -e "${BOLD}$title${RESET}"
    echo ""
    for item in "${items[@]}"; do
        echo -e "  ${GREEN}☐${RESET} $item"
    done
    echo ""
}

# Countdown timer
countdown() {
    local seconds=$1
    local message="${2:-Waiting...}"
    
    for i in $(seq $seconds -1 1); do
        echo -ne "\r$message ${i}s  "
        sleep 1
    done
    echo -e "\r$message Done!  "
}

# Confirm action
confirm_action() {
    local message="$1"
    local default="${2:-N}"
    
    local prompt
    if [[ "$default" == "Y" ]]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi
    
    read -p "$message $prompt: " response
    response=${response:-$default}
    
    [[ "$response" =~ ^[Yy]$ ]]
}
