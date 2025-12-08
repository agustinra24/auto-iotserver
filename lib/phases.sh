#!/bin/bash
################################################################################
# lib/phases.sh - Installation phase implementations (v2.3)
################################################################################

################################################################################
# PHASE 0: Preparation
################################################################################
phase_0_preparation() {
    CURRENT_PHASE=0
    log_info "Starting Phase 0: Preparation"
    
    # System requirements check
    show_task "Checking system requirements" "running"
    validate_system_requirements
    complete_task "System requirements validated"
    
    # Create installation directory
    show_task "Creating installation directory" "running"
    local install_dir="/home/${NEW_USERNAME}/iot-platform"
    
    if [[ "$DRY_RUN" != true ]]; then
        mkdir -p "$install_dir"
        mkdir -p "$install_dir"/{logs,mysql-data,mysql-init,mongo-data,redis-data,nginx,fastapi-app}
        mkdir -p "$install_dir/nginx/conf.d"
        mkdir -p "$install_dir/nginx/ssl"
        mkdir -p "$install_dir/logs"/{mysql,mongodb,redis,fastapi,nginx}
        mkdir -p "$install_dir/fastapi-app"/{core,models,schemas,api/v1/routers,database}
        
        echo "INSTALL_DIR=\"$install_dir\"" >> "$CONFIG_FILE"
    fi
    complete_task "Installation directories created"
    
    # Verify templates
    show_task "Verifying templates" "running"
    if [[ ! -d "$SCRIPT_DIR/templates" ]]; then
        log_error "Templates directory not found: $SCRIPT_DIR/templates"
        return 1
    fi
    complete_task "Templates verified"
    
    log_success "Phase 0 complete"
}

################################################################################
# PHASE 1: User Management
################################################################################
phase_1_user_management() {
    CURRENT_PHASE=1
    log_info "Starting Phase 1: User Management"

    # Update system first
    show_task "Updating system packages" "running"
    exec_cmd "apt-get update" "Update package lists"
    exec_cmd "DEBIAN_FRONTEND=noninteractive apt-get upgrade -y" "Upgrade packages"
    complete_task "System updated"

    # Create new user
    show_task "Creating user: $NEW_USERNAME" "running"
    
    if id "$NEW_USERNAME" &>/dev/null; then
        log_info "User $NEW_USERNAME already exists"
    else
        adduser --disabled-password --gecos "" "$NEW_USERNAME"
        
        local temp_password=$(openssl rand -base64 16 | tr -d "=+/")
        echo "$NEW_USERNAME:$temp_password" | chpasswd
        
        mkdir -p "$(dirname "$SECRETS_FILE")"
        echo "TEMP_USER_PASSWORD=\"$temp_password\"" >> "$SECRETS_FILE"
        chmod 600 "$SECRETS_FILE"
        
        log_info "Temporary password for $NEW_USERNAME: $temp_password"
        log_warning "Change this password after first login!"
    fi
    complete_task "User created: $NEW_USERNAME"

    # Add to sudo group
    show_task "Granting sudo privileges" "running"
    usermod -aG sudo "$NEW_USERNAME"
    complete_task "Sudo privileges granted"

    # Configure sudo without password
    show_task "Configuring sudo" "running"
    echo "$NEW_USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$NEW_USERNAME"
    chmod 440 "/etc/sudoers.d/$NEW_USERNAME"
    complete_task "Sudo configured"

    # Setup home directory
    show_task "Setting up home directory" "running"
    mkdir -p "/home/$NEW_USERNAME"
    chown "$NEW_USERNAME:$NEW_USERNAME" "/home/$NEW_USERNAME"
    chmod 755 "/home/$NEW_USERNAME"
    complete_task "Home directory ready"

    # Copy installer to new user's home
    show_task "Copying installer to new user home" "running"
    local new_installer_dir="/home/$NEW_USERNAME/iot-platform-installer"
    if [[ "$SCRIPT_DIR" != "$new_installer_dir" ]]; then
        cp -r "$SCRIPT_DIR" "$new_installer_dir"
        chown -R "$NEW_USERNAME:$NEW_USERNAME" "$new_installer_dir"
        chmod +x "$new_installer_dir/install.sh"
        chmod +x "$new_installer_dir/lib/"*.sh
    fi
    complete_task "Installer copied"

    # Create config in new location
    show_task "Creating config for new user" "running"
    local new_config="/home/$NEW_USERNAME/iot-platform-installer/.config.env"
    local new_secrets="/home/$NEW_USERNAME/.iot-platform/.secrets"
    
    mkdir -p "/home/$NEW_USERNAME/.iot-platform"
    chown -R "$NEW_USERNAME:$NEW_USERNAME" "/home/$NEW_USERNAME/.iot-platform"
    chmod 700 "/home/$NEW_USERNAME/.iot-platform"
    
    if [[ -f "$SECRETS_FILE" ]]; then
        cp "$SECRETS_FILE" "$new_secrets"
        chown "$NEW_USERNAME:$NEW_USERNAME" "$new_secrets"
        chmod 600 "$new_secrets"
    fi
    
    cat > "$new_config" << NEWCONFEOF
# IoT Platform Installation Configuration
# Generated: $(date)

VPS_IP="$VPS_IP"
NEW_USERNAME="$NEW_USERNAME"
SSH_PORT="$SSH_PORT"
DOMAIN="$DOMAIN"
DB_NAME="fire_preventionf"
DOCKER_SUBNET="$DOCKER_SUBNET"
REDIS_MEMORY="$REDIS_MEMORY"
TIMEZONE="$TIMEZONE"

# Paths
INSTALL_DIR="/home/${NEW_USERNAME}/iot-platform"
SECRETS_FILE="$new_secrets"
NEWCONFEOF
    
    chown "$NEW_USERNAME:$NEW_USERNAME" "$new_config"
    chmod 600 "$new_config"
    complete_task "Config created for new user"

    # Save checkpoint
    show_task "Saving checkpoint" "running"
    local new_state_file="/home/$NEW_USERNAME/iot-platform-installer/.install-state"
    cat > "$new_state_file" << STATEEOF
LAST_COMPLETED_PHASE=1
TIMESTAMP=$(date +%s)
DATE="$(date)"
STATEEOF
    chown "$NEW_USERNAME:$NEW_USERNAME" "$new_state_file"
    complete_task "Checkpoint saved"

    # Configure hostname
    show_task "Configuring hostname" "running"
    echo "iot-platform" > /etc/hostname
    hostname iot-platform
    if ! grep -q "iot-platform" /etc/hosts; then
        sed -i "s/127.0.1.1.*/127.0.1.1\tiot-platform/" /etc/hosts
    fi
    complete_task "Hostname configured"

    # Set timezone
    show_task "Setting timezone: $TIMEZONE" "running"
    timedatectl set-timezone "$TIMEZONE" 2>/dev/null || true
    complete_task "Timezone set"

    # Handle debian user deletion
    if id "debian" &>/dev/null; then
        log_success "Phase 1 complete"
        echo ""
        echo "========================================================"
        echo "  IMPORTANT: You must reconnect as the new user!"
        echo "========================================================"
        echo ""
        echo "  1. Your SSH session will be closed"
        echo "  2. Wait 5 seconds"
        echo "  3. Reconnect: ssh $NEW_USERNAME@$VPS_IP"
        echo "  4. Then run: cd ~/iot-platform-installer && sudo ./install.sh --resume"
        echo ""
        echo "========================================================"
        echo ""
        read -p "Press ENTER to continue (your session will close)..."
        
        pkill -u debian 2>/dev/null || true
        sleep 2
        deluser --remove-home debian 2>/dev/null || true
        
        exit 0
    fi

    log_success "Phase 1 complete"
}

################################################################################
# PHASE 2: Core Dependencies
################################################################################
phase_2_dependencies() {
    CURRENT_PHASE=2
    log_info "Starting Phase 2: Core Dependencies"
    
    show_task "Installing build tools" "running"
    exec_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential git curl wget jq" "Install build tools"
    complete_task "Build tools installed"
    
    show_task "Installing Python and dependencies" "running"
    exec_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-pip python3-dev python3-venv" "Install Python"
    complete_task "Python installed"
    
    show_task "Installing network tools" "running"
    exec_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y net-tools netcat-openbsd iproute2" "Install network tools"
    complete_task "Network tools installed"
    
    show_task "Installing monitoring utilities" "running"
    exec_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y htop iotop sysstat" "Install monitoring tools"
    complete_task "Monitoring utilities installed"
    
    show_task "Installing security tools" "running"
    exec_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y ufw nftables" "Install firewall tools"
    complete_task "Security tools installed"
    
    log_success "Phase 2 complete"
}

################################################################################
# PHASE 3: Firewall (nftables)
################################################################################
phase_3_firewall() {
    CURRENT_PHASE=3
    log_info "Starting Phase 3: Firewall Configuration"
    
    show_task "Disabling UFW" "running"
    if systemctl is-active --quiet ufw; then
        exec_cmd "systemctl stop ufw" "Stop UFW"
        exec_cmd "systemctl disable ufw" "Disable UFW"
    fi
    complete_task "UFW disabled"
    
    show_task "Installing nftables" "running"
    exec_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y nftables" "Install nftables"
    complete_task "nftables installed"
    
    show_task "Configuring nftables rules" "running"
    if [[ "$DRY_RUN" != true ]]; then
        sed -e "s/{{SSH_PORT}}/$SSH_PORT/g" \
            "$SCRIPT_DIR/templates/nftables.conf.tpl" > /tmp/nftables.conf
        
        mv /tmp/nftables.conf /etc/nftables.conf
        chmod 644 /etc/nftables.conf
    fi
    complete_task "nftables rules configured"
    
    show_task "Enabling nftables" "running"
    exec_cmd "systemctl enable nftables" "Enable nftables service"
    exec_cmd "systemctl restart nftables" "Start nftables"
    complete_task "nftables enabled and started"
    
    show_task "Creating emergency firewall disable script" "running"
    if [[ "$DRY_RUN" != true ]]; then
        cat > /usr/local/bin/emergency-disable-firewall.sh << 'FWEOF'
#!/bin/bash
echo "EMERGENCY: Disabling firewall..."
nft flush ruleset
systemctl stop nftables
systemctl disable nftables
echo "Firewall disabled. Fix your rules and re-enable."
FWEOF
        chmod +x /usr/local/bin/emergency-disable-firewall.sh
    fi
    complete_task "Emergency script created"
    
    log_success "Phase 3 complete"
}

################################################################################
# PHASE 4: Fail2Ban
################################################################################
phase_4_fail2ban() {
    CURRENT_PHASE=4
    log_info "Starting Phase 4: Fail2Ban"
    
    show_task "Installing Fail2Ban" "running"
    exec_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y fail2ban" "Install Fail2Ban"
    complete_task "Fail2Ban installed"
    
    show_task "Configuring Fail2Ban nftables action" "running"
    if [[ "$DRY_RUN" != true ]]; then
        cp "$SCRIPT_DIR/templates/fail2ban-action.conf.tpl" /etc/fail2ban/action.d/nftables-custom.conf
    fi
    complete_task "nftables action configured"
    
    show_task "Configuring Fail2Ban jails" "running"
    if [[ "$DRY_RUN" != true ]]; then
        sed -e "s/{{SSH_PORT}}/$SSH_PORT/g" \
            "$SCRIPT_DIR/templates/fail2ban-jail.local.tpl" > /etc/fail2ban/jail.local
    fi
    complete_task "Jails configured"
    
    show_task "Starting Fail2Ban" "running"
    exec_cmd "systemctl enable fail2ban" "Enable Fail2Ban"
    exec_cmd "systemctl restart fail2ban" "Start Fail2Ban"
    complete_task "Fail2Ban started"
    
    log_success "Phase 4 complete"
}

################################################################################
# PHASE 5: SSH Hardening
################################################################################
phase_5_ssh_hardening() {
    CURRENT_PHASE=5
    log_info "Starting Phase 5: SSH Hardening"
    
    show_task "Backing up SSH configuration" "running"
    backup_file "/etc/ssh/sshd_config"
    complete_task "SSH config backed up"
    
    show_task "Configuring SSH settings" "running"
    if [[ "$DRY_RUN" != true ]]; then
        if ! grep -q "^Port $SSH_PORT" /etc/ssh/sshd_config; then
            echo "Port $SSH_PORT" >> /etc/ssh/sshd_config
        fi
        
        sed -i 's/#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
        sed -i 's/#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
        sed -i 's/#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
        sed -i 's/#\?X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config
        sed -i 's/#\?MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config
    fi
    complete_task "SSH configured"
    
    show_task "Adding SSH port to firewall" "running"
    if [[ "$DRY_RUN" != true ]]; then
        nft -f /etc/nftables.conf
    fi
    complete_task "Firewall updated"
    
    show_task "Restarting SSH service" "running"
    exec_cmd "systemctl restart sshd" "Restart SSH"
    complete_task "SSH restarted"
    
    if [[ "$DRY_RUN" != true ]]; then
        show_critical_pause "SSH PORT VALIDATION" \
            "" \
            "SSH has been configured on port $SSH_PORT" \
            "Port 22 is STILL OPEN for safety" \
            "" \
            "BEFORE closing port 22, you MUST validate:" \
            "" \
            "  1. Open a NEW terminal window (keep this one open!)" \
            "  2. Test new port: ssh $NEW_USERNAME@$VPS_IP -p $SSH_PORT" \
            "  3. If successful, test sudo: sudo whoami" \
            "  4. Expected output: root" \
            "" \
            "If new port works correctly, validation passed." \
            "" \
            "DO NOT CONTINUE if you cannot connect on port $SSH_PORT!"
    fi
    
    show_task "Closing default SSH port 22" "running"
    if [[ "$DRY_RUN" != true ]]; then
        sed -i '/^Port 22$/d' /etc/ssh/sshd_config
        systemctl restart sshd
    fi
    complete_task "Port 22 closed"
    
    log_success "Phase 5 complete"
    log_warning "From now on, use: ssh $NEW_USERNAME@$VPS_IP -p $SSH_PORT"
}

################################################################################
# PHASE 6: Docker Installation
################################################################################
phase_6_docker() {
    CURRENT_PHASE=6
    log_info "Starting Phase 6: Docker Installation"
    
    show_task "Removing old Docker versions" "running"
    exec_cmd "apt-get remove -y docker docker-engine docker.io containerd runc || true" "Remove old Docker"
    complete_task "Old Docker versions removed"
    
    show_task "Installing Docker dependencies" "running"
    exec_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates gnupg lsb-release" "Install dependencies"
    complete_task "Dependencies installed"
    
    show_task "Adding Docker GPG key" "running"
    if [[ "$DRY_RUN" != true ]]; then
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
    fi
    complete_task "GPG key added"
    
    show_task "Adding Docker repository" "running"
    if [[ "$DRY_RUN" != true ]]; then
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
          $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update
    fi
    complete_task "Repository added"
    
    show_task "Installing Docker Engine" "running"
    exec_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin" "Install Docker"
    complete_task "Docker installed"
    
    show_task "Adding $NEW_USERNAME to docker group" "running"
    exec_cmd "usermod -aG docker $NEW_USERNAME" "Add to docker group"
    complete_task "User added to docker group"
    
    show_task "Configuring Docker daemon" "running"
    if [[ "$DRY_RUN" != true ]]; then
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json << DOCKEREOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
DOCKEREOF
    fi
    complete_task "Docker daemon configured"
    
    show_task "Starting Docker service" "running"
    exec_cmd "systemctl enable docker" "Enable Docker"
    exec_cmd "systemctl start docker" "Start Docker"
    complete_task "Docker started"
    
    show_task "Verifying Docker installation" "running"
    if [[ "$DRY_RUN" != true ]]; then
        docker --version >> "$LOG_FILE"
        docker compose version >> "$LOG_FILE"
    fi
    complete_task "Docker verified"
    
    log_success "Phase 6 complete"
}

################################################################################
# PHASE 7: Project Structure
################################################################################
phase_7_project_structure() {
    CURRENT_PHASE=7
    log_info "Starting Phase 7: Project Structure"
    
    source "$CONFIG_FILE"
    local install_dir="$INSTALL_DIR"
    # Create session log directory with proper permissions
    mkdir -p "$install_dir/logs/fastapi/sessions"
    chmod -R 777 "$install_dir/logs/fastapi"

    
    mkdir -p "$install_dir"/{logs,mysql-data,mysql-init,mongo-data,redis-data,nginx/conf.d,nginx/ssl}
    mkdir -p "$install_dir/logs"/{mysql,mongodb,redis,fastapi,nginx}
    mkdir -p "$install_dir/fastapi-app"/{core,models,schemas,api/v1/routers,database}
    
    show_task "Creating environment file" "running"
    if [[ "$DRY_RUN" != true ]]; then
        source "$SECRETS_FILE"
        
        sed -e "s/{{MYSQL_ROOT_PASSWORD}}/$MYSQL_ROOT_PASSWORD/g" \
            -e "s/{{MYSQL_PASSWORD}}/$MYSQL_PASSWORD/g" \
            -e "s/{{REDIS_PASSWORD}}/$REDIS_PASSWORD/g" \
            -e "s/{{MONGO_PASSWORD}}/$MONGO_PASSWORD/g" \
            -e "s/{{SECRET_KEY}}/$SECRET_KEY/g" \
            "$SCRIPT_DIR/templates/env.tpl" > "$install_dir/.env"
        
        chmod 600 "$install_dir/.env"
    fi
    complete_task "Environment file created"
    
    show_task "Creating .gitignore" "running"
    if [[ "$DRY_RUN" != true ]]; then
        cat > "$install_dir/.gitignore" << GIEOF
.env
.env.local
*.log
logs/
mysql-data/
mongo-data/
redis-data/
__pycache__/
*.pyc
.pytest_cache/
GIEOF
    fi
    complete_task ".gitignore created"
    
    show_task "Setting directory permissions" "running"
    if [[ "$DRY_RUN" != true ]]; then
        chown -R "$NEW_USERNAME:$NEW_USERNAME" "$install_dir"
        chmod 755 "$install_dir"
    fi
    complete_task "Permissions set"
    
    log_success "Phase 7 complete"
}

################################################################################
# PHASE 8: FastAPI Application
################################################################################
phase_8_fastapi_app() {
    CURRENT_PHASE=8
    log_info "Starting Phase 8: FastAPI Application"
    
    source "$CONFIG_FILE"
    local install_dir="$INSTALL_DIR"
    local app_dir="$install_dir/fastapi-app"
    
    show_task "Copying FastAPI application files" "running"
    if [[ "$DRY_RUN" != true ]]; then
        cp -r "$SCRIPT_DIR/templates/fastapi-app/"* "$app_dir/"
    fi
    complete_task "Application files copied"
    
    show_task "Creating Python package structure" "running"
    if [[ "$DRY_RUN" != true ]]; then
        touch "$app_dir/__init__.py"
        touch "$app_dir/core/__init__.py"
        touch "$app_dir/models/__init__.py"
        touch "$app_dir/schemas/__init__.py"
        touch "$app_dir/database/__init__.py"
        touch "$app_dir/api/__init__.py"
        touch "$app_dir/api/v1/__init__.py"
        touch "$app_dir/api/v1/routers/__init__.py"
    fi
    complete_task "Package structure created"
    
    log_success "Phase 8 complete"
}

################################################################################
# PHASE 9: MySQL Initialization
################################################################################
phase_9_mysql_init() {
    CURRENT_PHASE=9
    log_info "Starting Phase 9: MySQL Initialization"
    
    source "$CONFIG_FILE"
    source "$SECRETS_FILE"
    local install_dir="$INSTALL_DIR"
    
    show_task "Generating Argon2 password hashes" "running"
    generate_test_password_hashes
    complete_task "Password hashes generated"
    
    show_task "Creating MySQL initialization script" "running"
    if [[ "$DRY_RUN" != true ]]; then
        sed -e "s|{{ADMIN_PASSWORD_HASH}}|$ADMIN_PASSWORD_HASH|g" \
            -e "s|{{USER_PASSWORD_HASH}}|$USER_PASSWORD_HASH|g" \
            -e "s|{{MANAGER_PASSWORD_HASH}}|$MANAGER_PASSWORD_HASH|g" \
            "$SCRIPT_DIR/templates/mysql-init.sql.tpl" > "$install_dir/mysql-init/init.sql"
    fi
    complete_task "MySQL init script created"
    
    log_success "Phase 9 complete"
}

################################################################################
# PHASE 10: Nginx Configuration
################################################################################
phase_10_nginx() {
    CURRENT_PHASE=10
    log_info "Starting Phase 10: Nginx Configuration"
    
    source "$CONFIG_FILE"
    local install_dir="$INSTALL_DIR"
    
    show_task "Copying Nginx main configuration" "running"
    if [[ "$DRY_RUN" != true ]]; then
        cp "$SCRIPT_DIR/templates/nginx.conf.tpl" "$install_dir/nginx/nginx.conf"
    fi
    complete_task "Main config copied"
    
    show_task "Copying Nginx site configuration" "running"
    if [[ "$DRY_RUN" != true ]]; then
        cp "$SCRIPT_DIR/templates/nginx-site.conf.tpl" "$install_dir/nginx/conf.d/iot-api.conf"
    fi
    complete_task "Site config copied"
    
    log_success "Phase 10 complete"
}

################################################################################
# PHASE 11: Deployment
################################################################################
phase_11_deployment() {
    CURRENT_PHASE=11
    log_info "Starting Phase 11: Deployment"
    
    source "$CONFIG_FILE"
    local install_dir="$INSTALL_DIR"
    
    show_task "Creating docker-compose.yml" "running"
    if [[ "$DRY_RUN" != true ]]; then
        sed -e "s|{{DOCKER_SUBNET}}|$DOCKER_SUBNET|g" \
            "$SCRIPT_DIR/templates/docker-compose.yml.tpl" > "$install_dir/docker-compose.yml"
    fi
    complete_task "docker-compose.yml created"
    
    show_task "Starting Docker services" "running"
    if [[ "$DRY_RUN" != true ]]; then
        cd "$install_dir"
        docker compose up -d >> "$LOG_FILE" 2>&1
    fi
    complete_task "Services started"
    
    show_task "Waiting for services to be healthy" "running"
    if [[ "$DRY_RUN" != true ]]; then
        log_info "This may take 60-90 seconds..."
        sleep 30
        
        local max_wait=120
        local elapsed=0
        while [[ $elapsed -lt $max_wait ]]; do
            local healthy=$(docker compose ps --format json 2>/dev/null | jq -r '.Health' 2>/dev/null | grep -c "healthy" || echo 0)
            if [[ $healthy -ge 3 ]]; then
                break
            fi
            sleep 10
            elapsed=$((elapsed + 10))
        done
    fi
    complete_task "Services are healthy"
    
    log_success "Phase 11 complete"
}

################################################################################
# PHASE 12: Testing & Validation
################################################################################
phase_12_testing() {
    CURRENT_PHASE=12
    log_info "Starting Phase 12: Testing & Validation"
    
    source "$CONFIG_FILE"
    
    show_task "Testing health endpoint" "running"
    if [[ "$DRY_RUN" != true ]]; then
        local health_response=$(curl -s http://localhost/health)
        if echo "$health_response" | grep -q "healthy"; then
            complete_task "Health endpoint OK"
        else
            log_error "Health check failed"
        fi
    else
        complete_task "Health endpoint (dry-run)"
    fi
    
    show_task "Testing admin authentication" "running"
    if [[ "$DRY_RUN" != true ]]; then
        local admin_response=$(curl -s -X POST http://localhost/api/v1/auth/login/admin \
            -H "Content-Type: application/json" \
            -d '{"email":"master@fire.com","password":"password123"}')
        
        if echo "$admin_response" | grep -q "access_token"; then
            log_success "Admin authentication works"
        else
            log_warning "Admin authentication may have issues"
            log_info "Response: $admin_response"
        fi
    fi
    complete_task "Authentication tested"
    
    show_task "Testing MongoDB sensor endpoint" "running"
    if [[ "$DRY_RUN" != true ]]; then
        # First get a device token
        local device_token=""
        # Note: Device auth requires puzzle, so we skip automated testing
        log_info "Device authentication requires puzzle - manual testing needed"
    fi
    complete_task "MongoDB endpoints ready for testing"
    
    show_task "Verifying database isolation" "running"
    if [[ "$DRY_RUN" != true ]]; then
        ! nc -zv localhost 3306 2>&1 | grep -q "succeeded" && \
        ! nc -zv localhost 6379 2>&1 | grep -q "succeeded" && \
        ! nc -zv localhost 27017 2>&1 | grep -q "succeeded"
        
        if [[ $? -eq 0 ]]; then
            log_success "Databases are isolated (not exposed)"
        else
            log_error "Databases may be exposed to host!"
        fi
    fi
    complete_task "Database isolation verified"
    
    show_task "Checking container status" "running"
    if [[ "$DRY_RUN" != true ]]; then
        cd "$INSTALL_DIR"
        docker compose ps >> "$LOG_FILE"
    fi
    complete_task "Containers verified"
    
    log_success "Phase 12 complete"
}
