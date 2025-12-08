#!/bin/bash
################################################################################
# lib/validation.sh - Input validation functions
################################################################################

# Validate IP address
validate_ip() {
    local ip=$1
    
    # IPv4 regex
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        # Check each octet is 0-255
        local IFS='.'
        local -a octets=($ip)
        for octet in "${octets[@]}"; do
            if [[ $octet -gt 255 ]]; then
                log_error "Invalid IP address: $ip (octet > 255)"
                return 1
            fi
        done
        return 0
    else
        log_error "Invalid IP address format: $ip"
        return 1
    fi
}

# Validate username
validate_username() {
    local username=$1
    
    # Check length
    if [[ ${#username} -lt 3 ]] || [[ ${#username} -gt 32 ]]; then
        log_error "Username must be 3-32 characters"
        return 1
    fi
    
    # Check format (alphanumeric, underscore, hyphen)
    if [[ ! $username =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        log_error "Username must start with lowercase letter or underscore"
        log_error "Can only contain lowercase letters, numbers, underscore, hyphen"
        return 1
    fi
    
    # Check reserved names
    local reserved_names=("root" "admin" "administrator" "system" "daemon" "bin" "sys")
    for reserved in "${reserved_names[@]}"; do
        if [[ "$username" == "$reserved" ]]; then
            log_error "Username '$username' is reserved"
            return 1
        fi
    done
    
    return 0
}

# Validate port number
validate_port() {
    local port=$1
    
    if [[ ! $port =~ ^[0-9]+$ ]]; then
        log_error "Port must be a number"
        return 1
    fi
    
    if [[ $port -lt 1 ]] || [[ $port -gt 65535 ]]; then
        log_error "Port must be between 1 and 65535"
        return 1
    fi
    
    # Warn about common ports
    if [[ $port -eq 22 ]]; then
        log_warning "Port 22 is the default SSH port"
        log_warning "Recommend using a custom port like 5259"
    fi
    
    if [[ $port -lt 1024 ]]; then
        log_warning "Port $port is in privileged range (< 1024)"
    fi
    
    return 0
}

# Validate database name
validate_db_name() {
    local db_name=$1
    
    # Check length
    if [[ ${#db_name} -lt 1 ]] || [[ ${#db_name} -gt 64 ]]; then
        log_error "Database name must be 1-64 characters"
        return 1
    fi
    
    # Check format (alphanumeric and underscore only)
    if [[ ! $db_name =~ ^[a-zA-Z0-9_]+$ ]]; then
        log_error "Database name can only contain letters, numbers, and underscores"
        return 1
    fi
    
    # Cannot start with number
    if [[ $db_name =~ ^[0-9] ]]; then
        log_error "Database name cannot start with a number"
        return 1
    fi
    
    return 0
}

# Validate subnet
validate_subnet() {
    local subnet=$1
    
    # Check CIDR format
    if [[ ! $subnet =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        log_error "Invalid subnet format. Expected: x.x.x.x/y"
        return 1
    fi
    
    # Extract IP and mask
    local ip="${subnet%/*}"
    local mask="${subnet#*/}"
    
    # Validate IP part
    validate_ip "$ip" || return 1
    
    # Validate mask
    if [[ $mask -lt 8 ]] || [[ $mask -gt 32 ]]; then
        log_error "Subnet mask must be between /8 and /32"
        return 1
    fi
    
    return 0
}

# Validate domain name
validate_domain() {
    local domain=$1
    
    # Allow "none" or empty
    if [[ -z "$domain" ]] || [[ "$domain" == "none" ]]; then
        return 0
    fi
    
    # Check format
    if [[ ! $domain =~ ^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
        log_error "Invalid domain format"
        return 1
    fi
    
    return 0
}

# Validate memory size (e.g., 256MB, 1GB)
validate_memory_size() {
    local size=$1
    
    if [[ ! $size =~ ^[0-9]+[MG]B$ ]]; then
        log_error "Invalid memory size. Expected format: 256MB or 1GB"
        return 1
    fi
    
    return 0
}

# Validate timezone
validate_timezone() {
    local tz=$1
    
    if [[ ! -f "/usr/share/zoneinfo/$tz" ]]; then
        log_warning "Timezone '$tz' not found in system database"
        log_warning "Using UTC instead"
        return 1
    fi
    
    return 0
}

# Check if user exists
user_exists() {
    local username=$1
    id -u "$username" &>/dev/null
}

# Check if port is in use
port_in_use() {
    local port=$1
    ss -tlnp | grep -q ":${port} "
}

# Validate SSH access
validate_ssh_access() {
    local user=$1
    local host=$2
    local port=$3
    local timeout=${4:-5}
    
    log_info "Testing SSH access: $user@$host:$port"
    
    if timeout $timeout ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -p "$port" "$user@$host" "exit" 2>/dev/null; then
        log_success "SSH access validated"
        return 0
    else
        log_error "Cannot connect via SSH"
        return 1
    fi
}

# Validate system meets minimum requirements
validate_system_requirements() {
    local errors=0
    
    log_info "Validating system requirements..."
    
    # RAM check
    local total_ram_mb=$(free -m | awk '/^Mem:/ {print $2}')
    if [[ $total_ram_mb -lt 3072 ]]; then
        log_warning "RAM: ${total_ram_mb}MB (recommended: 4096MB)"
    else
        log_success "RAM: ${total_ram_mb}MB ✓"
    fi
    
    # Disk space check
    local avail_disk_gb=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $avail_disk_gb -lt 15 ]]; then
        log_error "Disk space: ${avail_disk_gb}GB (minimum: 20GB)"
        ((errors++))
    else
        log_success "Disk space: ${avail_disk_gb}GB ✓"
    fi
    
    # CPU check
    local cpu_cores=$(nproc)
    if [[ $cpu_cores -lt 2 ]]; then
        log_warning "CPU cores: $cpu_cores (recommended: 2+)"
    else
        log_success "CPU cores: $cpu_cores ✓"
    fi
    
    # Internet check
    if ! ping -c 1 8.8.8.8 &>/dev/null; then
        log_error "No internet connectivity"
        ((errors++))
    else
        log_success "Internet connectivity ✓"
    fi
    
    return $errors
}

# Validate configuration file
validate_config() {
    local config_file=$1
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi
    
    source "$config_file"
    
    local required_vars=(
        "VPS_IP"
        "NEW_USERNAME"
        "SSH_PORT"
        "DB_NAME"
        "DOCKER_SUBNET"
    )
    
    local errors=0
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            log_error "Missing required variable: $var"
            ((errors++))
        fi
    done
    
    return $errors
}

# Validate secrets file
validate_secrets() {
    local secrets_file=$1
    
    if [[ ! -f "$secrets_file" ]]; then
        log_error "Secrets file not found: $secrets_file"
        return 1
    fi
    
    source "$secrets_file"
    
    local required_secrets=(
        "MYSQL_ROOT_PASSWORD"
        "MYSQL_PASSWORD"
        "REDIS_PASSWORD"
        "SECRET_KEY"
    )
    
    local errors=0
    for secret in "${required_secrets[@]}"; do
        if [[ -z "${!secret}" ]]; then
            log_error "Missing secret: $secret"
            ((errors++))
        fi
    done
    
    # Check file permissions
    local perms=$(stat -c '%a' "$secrets_file")
    if [[ "$perms" != "600" ]]; then
        log_warning "Secrets file has insecure permissions: $perms"
        log_warning "Fixing permissions to 600"
        chmod 600 "$secrets_file"
    fi
    
    return $errors
}
