#!/bin/bash
################################################################################
# lib/common.sh - Common utilities and logging functions
################################################################################

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${RESET} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${RESET} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${RESET} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${RESET} $1" >&2
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${CYAN}[DEBUG]${RESET} $1"
    fi
}

# Execute command with logging
exec_cmd() {
    local cmd="$1"
    local description="${2:-Executing command}"
    
    log_debug "Command: $cmd"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${CYAN}[DRY-RUN]${RESET} Would execute: $cmd"
        return 0
    fi
    
    if eval "$cmd" >> "$LOG_FILE" 2>&1; then
        log_success "$description"
        return 0
    else
        local exit_code=$?
        log_error "$description failed (exit code: $exit_code)"
        log_error "Check log file: $LOG_FILE"
        return $exit_code
    fi
}

# Error handler
error_handler() {
    local line_num=$1
    log_error "Script failed at line $line_num"
    log_error "Last command: $BASH_COMMAND"
    log_error "Check log: $LOG_FILE"
    
    # Offer to save state
    if [[ -n "${CURRENT_PHASE:-}" ]]; then
        log_warning "Installation interrupted at Phase $CURRENT_PHASE"
        log_info "You can resume later with: sudo ./install.sh --resume"
    fi
    
    exit 1
}

# Set error trap
trap 'error_handler $LINENO' ERR

# Check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Wait for user confirmation
wait_for_confirmation() {
    local message="${1:-Press ENTER to continue}"
    read -p "$message: "
}

# Detect current user type (root, debian, other)
detect_current_user() {
    if [[ $EUID -eq 0 ]]; then
        echo "root"
    elif [[ "$USER" == "debian" ]]; then
        echo "debian"
    else
        echo "other"
    fi
}

# Check if service is running
is_service_running() {
    local service=$1
    systemctl is-active --quiet "$service"
}

# Backup file
backup_file() {
    local file=$1
    if [[ -f "$file" ]]; then
        local backup="${file}.backup-$(date +%Y%m%d-%H%M%S)"
        cp "$file" "$backup"
        log_info "Backed up: $file → $backup"
    fi
}

# Replace string in file
replace_in_file() {
    local file=$1
    local search=$2
    local replace=$3
    
    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        return 1
    fi
    
    sed -i "s|${search}|${replace}|g" "$file"
}

# Create directory with permissions
create_dir() {
    local dir=$1
    local perms=${2:-755}
    local owner=${3:-root:root}
    
    mkdir -p "$dir"
    chmod "$perms" "$dir"
    chown "$owner" "$dir"
}

# Download file with retry
download_file() {
    local url=$1
    local dest=$2
    local max_retries=${3:-3}
    
    for i in $(seq 1 $max_retries); do
        if curl -fsSL "$url" -o "$dest"; then
            log_success "Downloaded: $url"
            return 0
        else
            log_warning "Download attempt $i/$max_retries failed"
            sleep 2
        fi
    done
    
    log_error "Failed to download: $url"
    return 1
}

# Check port availability
is_port_available() {
    local port=$1
    ! ss -tlnp | grep -q ":${port} "
}

# Get system info
get_system_info() {
    cat << EOF
OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)
Kernel: $(uname -r)
CPU: $(nproc) cores
RAM: $(free -h | awk '/^Mem:/ {print $2}')
Disk: $(df -h / | awk 'NR==2 {print $4}') available
EOF
}

# Calculate progress percentage
calc_progress() {
    local current=$1
    local total=$2
    echo $(( (current * 100) / total ))
}

# Format duration
format_duration() {
    local seconds=$1
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))
    printf "%02d:%02d:%02d" $hours $minutes $secs
}

# Check system resources
check_system_resources() {
    local min_ram_mb=3072  # 3GB
    local min_disk_gb=15
    
    # Check RAM
    local total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_ram_mb=$((total_ram_kb / 1024))
    
    if [[ $total_ram_mb -lt $min_ram_mb ]]; then
        log_warning "Low RAM: ${total_ram_mb}MB (recommended: ${min_ram_mb}MB)"
        log_warning "Installation may be slow or fail"
    fi
    
    # Check disk space
    local avail_disk_gb=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    
    if [[ $avail_disk_gb -lt $min_disk_gb ]]; then
        log_error "Insufficient disk space: ${avail_disk_gb}GB (minimum: ${min_disk_gb}GB)"
        return 1
    fi
    
    return 0
}

# Generate random string
generate_random_string() {
    local length=${1:-32}
    openssl rand -base64 $length | tr -d "=+/" | cut -c1-$length
}

# Generate random hex
generate_random_hex() {
    local length=${1:-32}
    openssl rand -hex $length
}

# Check if running in Docker
is_docker() {
    [[ -f /.dockerenv ]] || grep -q docker /proc/1/cgroup 2>/dev/null
}

# Ensure not running in Docker
ensure_not_docker() {
    if is_docker; then
        log_error "This script cannot run inside a Docker container"
        log_error "Please run on the host system"
        exit 1
    fi
}
