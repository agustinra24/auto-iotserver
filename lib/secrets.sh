#!/bin/bash
################################################################################
# lib/secrets.sh - Secret generation functions
################################################################################

# Generate all secrets
generate_all_secrets() {
    log_info "Generating secure secrets..."
    
    # Create secrets directory
    local secrets_dir=$(dirname "$SECRETS_FILE")
    mkdir -p "$secrets_dir"
    chmod 700 "$secrets_dir"
    
    # Generate passwords (32 bytes base64)
    export MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
    export MYSQL_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
    export REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
    export MONGO_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
    
    # Generate JWT secret key (64 chars hex)
    export SECRET_KEY=$(openssl rand -hex 32)
    
    # Generate device encryption keys
    export DEVICE_ENCRYPTION_KEY_ADMIN=$(openssl rand -hex 32)
    export DEVICE_ENCRYPTION_KEY_USER=$(openssl rand -hex 32)
    export DEVICE_ENCRYPTION_KEY_MANAGER=$(openssl rand -hex 32)
    export DEVICE_ENCRYPTION_KEY_DEVICE=$(openssl rand -hex 32)
    
    # Save to file
    cat > "$SECRETS_FILE" << EOF
# IoT Platform Secrets
# Generated: $(date)
# CRITICAL: Backup this file and keep it secure!

# Database Passwords
MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD"
MYSQL_PASSWORD="$MYSQL_PASSWORD"
REDIS_PASSWORD="$REDIS_PASSWORD"
MONGO_PASSWORD="$MONGO_PASSWORD"

# JWT Secret Key (HS256)
SECRET_KEY="$SECRET_KEY"

# Device Encryption Keys (32 bytes hex)
DEVICE_ENCRYPTION_KEY_ADMIN="$DEVICE_ENCRYPTION_KEY_ADMIN"
DEVICE_ENCRYPTION_KEY_USER="$DEVICE_ENCRYPTION_KEY_USER"
DEVICE_ENCRYPTION_KEY_MANAGER="$DEVICE_ENCRYPTION_KEY_MANAGER"
DEVICE_ENCRYPTION_KEY_DEVICE="$DEVICE_ENCRYPTION_KEY_DEVICE"

# Algorithms
ALGORITHM="HS256"
ACCESS_TOKEN_EXPIRE_MINUTES="60"
ACCESS_TOKEN_EXPIRE_MINUTES_DEVICE="1440"
EOF
    
    chmod 600 "$SECRETS_FILE"
    
    log_success "Secrets generated and saved to: $SECRETS_FILE"
    log_warning "BACKUP THIS FILE - You cannot recover passwords if lost!"
}

# Hash password with bcrypt (for test data)
hash_password() {
    local password=$1
    python3 -c "from passlib.hash import bcrypt; print(bcrypt.hash('$password'))"
}

# Generate bcrypt hashes for test users
generate_test_password_hashes() {
    log_info "Generating password hashes for test users..."
    
    # Install passlib if not available
    if ! python3 -c "import passlib" 2>/dev/null; then
        log_info "Installing passlib..."
        pip3 install --break-system-packages passlib bcrypt 2>&1 | tee -a "$LOG_FILE"
    fi
    
    # Generate hashes
    export ADMIN_PASSWORD_HASH=$(hash_password "admin123")
    export USER_PASSWORD_HASH=$(hash_password "user123")
    export MANAGER_PASSWORD_HASH=$(hash_password "manager123")
    
    log_success "Password hashes generated"
}

# Generate API key for device
generate_device_api_key() {
    local length=${1:-32}
    # Generate URL-safe base64 string
    openssl rand -base64 $length | tr -d "=+/" | cut -c1-$length
}

# Show secrets (masked)
show_secrets_summary() {
    echo ""
    echo "${BOLD}Generated Secrets:${RESET}"
    echo "──────────────────────────────────────────────────"
    echo "MySQL Root:    ${MYSQL_ROOT_PASSWORD:0:8}...${MYSQL_ROOT_PASSWORD: -4}"
    echo "MySQL User:    ${MYSQL_PASSWORD:0:8}...${MYSQL_PASSWORD: -4}"
    echo "Redis:         ${REDIS_PASSWORD:0:8}...${REDIS_PASSWORD: -4}"
    echo "JWT Secret:    ${SECRET_KEY:0:16}...${SECRET_KEY: -8}"
    echo ""
    echo "${YELLOW}Full secrets saved to: $SECRETS_FILE${RESET}"
    echo ""
}

# Validate secret strength
validate_secret_strength() {
    local secret=$1
    local min_length=${2:-32}
    
    if [[ ${#secret} -lt $min_length ]]; then
        log_error "Secret too short: ${#secret} chars (minimum: $min_length)"
        return 1
    fi
    
    return 0
}

# Export secrets to environment
export_secrets() {
    if [[ -f "$SECRETS_FILE" ]]; then
        source "$SECRETS_FILE"
        log_debug "Secrets loaded from $SECRETS_FILE"
    else
        log_error "Secrets file not found: $SECRETS_FILE"
        return 1
    fi
}
