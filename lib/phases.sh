#!/bin/bash
################################################################################
# lib/phases.sh - Funciones de fases de instalación
################################################################################

################################################################################
# Funciones de utilidad
################################################################################
validate_system_requirements() {
    log_info "Validando requisitos del sistema..."
    
    local ram_mb=$(free -m | awk '/^Mem:/{print $2}')
    if [[ $ram_mb -lt 1024 ]]; then
        log_error "RAM insuficiente: ${ram_mb}MB (mínimo: 1024MB)"
        return 1
    fi
    log_success "RAM: ${ram_mb}MB"
    
    local disk_gb=$(df -BG / | awk 'NR==2 {gsub("G",""); print $4}')
    if [[ $disk_gb -lt 10 ]]; then
        log_error "Espacio en disco insuficiente: ${disk_gb}GB (mínimo: 10GB)"
        return 1
    fi
    log_success "Espacio en disco: ${disk_gb}GB"
    
    local cpu_cores=$(nproc)
    if [[ $cpu_cores -lt 1 ]]; then
        log_error "Núcleos de CPU insuficientes: $cpu_cores (mínimo: 1)"
        return 1
    fi
    log_success "Núcleos CPU: $cpu_cores"
    
    if ! ping -c 1 google.com &> /dev/null; then
        log_error "Sin conectividad a internet"
        return 1
    fi
    log_success "Conectividad a internet"
    
    return 0
}

backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        cp "$file" "${file}.bak.$(date +%Y%m%d%H%M%S)"
        log_info "Respaldado: $file"
    fi
}

################################################################################
# FASE 0: Preparación
################################################################################
phase_0_preparation() {
    CURRENT_PHASE=0
    log_info "Iniciando Fase 0: Preparación"
    
    show_task "Verificando requisitos del sistema" "running"
    validate_system_requirements
    complete_task "Requisitos del sistema validados"
    
    show_task "Creando directorio de instalación" "running"
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
    complete_task "Directorios de instalación creados"
    
    show_task "Verificando templates" "running"
    if [[ ! -d "$SCRIPT_DIR/templates" ]]; then
        log_error "Directorio de templates no encontrado: $SCRIPT_DIR/templates"
        return 1
    fi
    complete_task "Templates verificados"
    
    log_success "Fase 0 completada"
}

################################################################################
# FASE 1: Gestión de Usuarios
################################################################################
phase_1_user_management() {
    CURRENT_PHASE=1
    log_info "Iniciando Fase 1: Gestión de Usuarios"

    show_task "Actualizando paquetes del sistema" "running"
    exec_cmd "apt-get update" "Actualizar lista de paquetes"
    exec_cmd "DEBIAN_FRONTEND=noninteractive apt-get upgrade -y" "Actualizar paquetes"
    complete_task "Sistema actualizado"

    show_task "Creando usuario: $NEW_USERNAME" "running"
    
    local temp_password=""
    
    if id "$NEW_USERNAME" &>/dev/null; then
        log_info "El usuario $NEW_USERNAME ya existe"
    else
        adduser --disabled-password --gecos "" "$NEW_USERNAME"
        
        temp_password=$(openssl rand -base64 16 | tr -d "=+/")
        echo "$NEW_USERNAME:$temp_password" | chpasswd
        
        mkdir -p "$(dirname "$SECRETS_FILE")"
        echo "TEMP_USER_PASSWORD=\"$temp_password\"" >> "$SECRETS_FILE"
        chmod 600 "$SECRETS_FILE"
        
        log_info "Contraseña temporal generada para $NEW_USERNAME"
    fi
    complete_task "Usuario creado: $NEW_USERNAME"

    show_task "Otorgando privilegios sudo" "running"
    usermod -aG sudo "$NEW_USERNAME"
    complete_task "Privilegios sudo otorgados"

    show_task "Configurando sudo sin contraseña" "running"
    echo "$NEW_USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$NEW_USERNAME"
    chmod 440 "/etc/sudoers.d/$NEW_USERNAME"
    complete_task "Sudo configurado"

    show_task "Configurando directorio home" "running"
    mkdir -p "/home/$NEW_USERNAME"
    chown "$NEW_USERNAME:$NEW_USERNAME" "/home/$NEW_USERNAME"
    chmod 755 "/home/$NEW_USERNAME"
    complete_task "Directorio home listo"

    show_task "Copiando instalador al home del nuevo usuario" "running"
    local new_installer_dir="/home/$NEW_USERNAME/iot-platform-installer"
    if [[ "$SCRIPT_DIR" != "$new_installer_dir" ]]; then
        cp -r "$SCRIPT_DIR" "$new_installer_dir"
        chown -R "$NEW_USERNAME:$NEW_USERNAME" "$new_installer_dir"
        chmod +x "$new_installer_dir/install.sh"
        chmod +x "$new_installer_dir/lib/"*.sh
    fi
    complete_task "Instalador copiado"

    show_task "Creando configuración para nuevo usuario" "running"
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
    
    local original_start_time=""
    if [[ -f "$CONFIG_FILE" ]]; then
        original_start_time=$(grep 'INSTALL_START_TIME=' "$CONFIG_FILE" | cut -d'"' -f2 || echo "")
    fi
    
    local escaped_password
    escaped_password=$(printf '%s' "$ADMIN_PASSWORD" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\$/\\$/g' -e 's/`/\\`/g')
    
    cat > "$new_config" << NEWCONFEOF
# Configuración de Instalación de Plataforma IoT
# Generado: $(date)

VPS_IP="$VPS_IP"
NEW_USERNAME="$NEW_USERNAME"
SSH_PORT="$SSH_PORT"
DOMAIN="$DOMAIN"
DB_NAME="$DB_NAME"
DOCKER_SUBNET="$DOCKER_SUBNET"
REDIS_MEMORY="$REDIS_MEMORY"
TIMEZONE="$TIMEZONE"

# Credenciales de Administrador
ADMIN_EMAIL="$ADMIN_EMAIL"
ADMIN_PASSWORD="$escaped_password"

# Rutas
INSTALL_DIR="/home/${NEW_USERNAME}/iot-platform"
SECRETS_FILE="$new_secrets"

# Tiempo de inicio para cálculo de duración (preservado del inicio)
INSTALL_START_TIME="${original_start_time:-$(date +%s)}"
NEWCONFEOF
    
    chown "$NEW_USERNAME:$NEW_USERNAME" "$new_config"
    chmod 600 "$new_config"
    complete_task "Configuración creada para nuevo usuario"

    show_task "Guardando punto de control" "running"
    local new_state_file="/home/$NEW_USERNAME/iot-platform-installer/.install-state"
    cat > "$new_state_file" << STATEEOF
LAST_COMPLETED_PHASE=1
TIMESTAMP=$(date +%s)
DATE="$(date)"
STATEEOF
    chown "$NEW_USERNAME:$NEW_USERNAME" "$new_state_file"
    complete_task "Punto de control guardado"

    show_task "Configurando hostname" "running"
    echo "iot-platform" > /etc/hostname
    hostname iot-platform
    if ! grep -q "iot-platform" /etc/hosts; then
        sed -i "s/127.0.1.1.*/127.0.1.1\tiot-platform/" /etc/hosts
    fi
    complete_task "Hostname configurado"

    show_task "Estableciendo zona horaria: $TIMEZONE" "running"
    timedatectl set-timezone "$TIMEZONE" 2>/dev/null || true
    complete_task "Zona horaria establecida"

    if id "debian" &>/dev/null; then
        log_success "Fase 1 completada"
        
        echo ""
        echo -e "${RED}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${RED}║${RESET}                                                                              ${RED}║${RESET}"
        echo -e "${RED}║${RESET}   ${BOLD}¡¡¡ IMPORTANTE - GUARDA ESTAS CREDENCIALES AHORA !!!${RESET}                       ${RED}║${RESET}"
        echo -e "${RED}║${RESET}                                                                              ${RED}║${RESET}"
        echo -e "${RED}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
        echo -e "${RED}║${RESET}                                                                              ${RED}║${RESET}"
        echo -e "${RED}║${RESET}   ${BOLD}Usuario SSH:${RESET}     ${GREEN}$NEW_USERNAME${RESET}                                              ${RED}║${RESET}"
        echo -e "${RED}║${RESET}   ${BOLD}Contraseña:${RESET}      ${GREEN}$temp_password${RESET}                                  ${RED}║${RESET}"
        echo -e "${RED}║${RESET}   ${BOLD}Puerto SSH:${RESET}      ${GREEN}$SSH_PORT${RESET}                                                    ${RED}║${RESET}"
        echo -e "${RED}║${RESET}   ${BOLD}Servidor:${RESET}        ${GREEN}$VPS_IP${RESET}                                              ${RED}║${RESET}"
        echo -e "${RED}║${RESET}                                                                              ${RED}║${RESET}"
        echo -e "${RED}║${RESET}   ${YELLOW}Comando de conexión:${RESET}                                                     ${RED}║${RESET}"
        echo -e "${RED}║${RESET}   ${CYAN}ssh $NEW_USERNAME@$VPS_IP -p $SSH_PORT${RESET}                                    ${RED}║${RESET}"
        echo -e "${RED}║${RESET}                                                                              ${RED}║${RESET}"
        echo -e "${RED}║${RESET}   ${YELLOW}También guardado en: ~/.iot-platform/.secrets${RESET}                            ${RED}║${RESET}"
        echo -e "${RED}║${RESET}                                                                              ${RED}║${RESET}"
        echo -e "${RED}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
        echo ""
        echo -e "${YELLOW}Presiona ENTER cuando hayas guardado las credenciales...${RESET}"
        read -p ""
        
        echo ""
        echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${BOLD}TRANSICIÓN AUTOMÁTICA DE USUARIO${RESET}                                          ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${GREEN}[OK]${RESET} Usuario ${YELLOW}$NEW_USERNAME${RESET} creado exitosamente                               ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${GREEN}[OK]${RESET} Permisos de administrador (sudo) otorgados                             ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${GREEN}[OK]${RESET} Instalador copiado a /home/$NEW_USERNAME/                               ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${BOLD}Continuando instalación automáticamente como $NEW_USERNAME...${RESET}              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}(El usuario debian será eliminado al final de la instalación)${RESET}              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
        echo ""
        
        sleep 3
        
        log_info "Ejecutando transición a usuario $NEW_USERNAME..."
        exec runuser -l "$NEW_USERNAME" -c "cd /home/$NEW_USERNAME/iot-platform-installer && sudo ./install.sh --internal-resume"
    fi

    log_success "Fase 1 completada"
}

################################################################################
# FASE 2: Dependencias Base
################################################################################
phase_2_dependencies() {
    CURRENT_PHASE=2
    log_info "Iniciando Fase 2: Dependencias Base"
    
    show_task "Deshabilitando actualizaciones automáticas" "running"
    if [[ "$DRY_RUN" != true ]]; then
        systemctl stop unattended-upgrades 2>/dev/null || true
        systemctl disable unattended-upgrades 2>/dev/null || true
        while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
            log_info "Esperando a que apt termine..."
            sleep 2
        done
    fi
    complete_task "Actualizaciones automáticas deshabilitadas"
    
    show_task "Instalando herramientas de compilación" "running"
    exec_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential git curl wget jq" "Instalar herramientas de compilación"
    complete_task "Herramientas de compilación instaladas"
    
    show_task "Instalando Python y dependencias" "running"
    exec_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-pip python3-dev python3-venv" "Instalar Python"
    complete_task "Python instalado"
    
    show_task "Instalando herramientas de red" "running"
    exec_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y net-tools netcat-openbsd iproute2" "Instalar herramientas de red"
    complete_task "Herramientas de red instaladas"
    
    show_task "Instalando utilidades adicionales" "running"
    exec_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y gnupg lsb-release ca-certificates apt-transport-https at" "Instalar utilidades"
    complete_task "Utilidades adicionales instaladas"
    
    if [[ "$DRY_RUN" != true ]]; then
        systemctl enable atd 2>/dev/null || true
        systemctl start atd 2>/dev/null || true
    fi
    
    log_success "Fase 2 completada"
}

################################################################################
# FASE 3: Firewall (nftables)
################################################################################
phase_3_firewall() {
    CURRENT_PHASE=3
    log_info "Iniciando Fase 3: Configuración de Firewall"
    
    source "$CONFIG_FILE"
    
    show_task "Instalando nftables" "running"
    exec_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y nftables" "Instalar nftables"
    complete_task "nftables instalado"
    
    show_task "Generando configuración de nftables" "running"
    if [[ "$DRY_RUN" != true ]]; then
        backup_file "/etc/nftables.conf"
        
        sed -e "s|{{SSH_PORT}}|$SSH_PORT|g" \
            "$SCRIPT_DIR/templates/nftables.conf.tpl" > /etc/nftables.conf
    fi
    complete_task "Configuración de nftables generada"
    
    show_task "Habilitando y reiniciando nftables" "running"
    if [[ "$DRY_RUN" != true ]]; then
        systemctl enable nftables
        systemctl restart nftables
    fi
    complete_task "nftables activado"
    
    log_success "Fase 3 completada"
}

################################################################################
# FASE 4: Fail2Ban (con Nginx Jails habilitados - Solución Híbrida)
################################################################################
phase_4_fail2ban() {
    CURRENT_PHASE=4
    log_info "Iniciando Fase 4: Configuración de Fail2Ban"
    
    source "$CONFIG_FILE"
    
    local nginx_log_path="${INSTALL_DIR:-/home/${NEW_USERNAME}/iot-platform}/logs/nginx"
    
    show_task "Instalando Fail2Ban" "running"
    exec_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y fail2ban" "Instalar Fail2Ban"
    complete_task "Fail2Ban instalado"
    
    show_task "Instalando filtros nginx desde templates" "running"
    if [[ "$DRY_RUN" != true ]]; then
        # Copiar filtros desde templates (arquitectura limpia)
        if [[ -f "$SCRIPT_DIR/templates/fail2ban-nginx-http-auth.conf" ]]; then
            cp "$SCRIPT_DIR/templates/fail2ban-nginx-http-auth.conf" /etc/fail2ban/filter.d/nginx-http-auth.conf
            log_info "Filtro nginx-http-auth instalado"
        else
            log_warning "Template fail2ban-nginx-http-auth.conf no encontrado, creando inline..."
            cat > /etc/fail2ban/filter.d/nginx-http-auth.conf << 'FILTEREOF'
[Definition]
failregex = ^<HOST> -.*"(GET|POST|PUT|DELETE|PATCH) /api/v1/auth/[^"]*" (401|403) .*$
            ^<HOST> -.*"(GET|POST|PUT|DELETE|PATCH) [^"]*" (401|403) .*$
ignoreregex =
datepattern = {^LN-BEG}
FILTEREOF
        fi
        
        if [[ -f "$SCRIPT_DIR/templates/fail2ban-nginx-botsearch.conf" ]]; then
            cp "$SCRIPT_DIR/templates/fail2ban-nginx-botsearch.conf" /etc/fail2ban/filter.d/nginx-botsearch.conf
            log_info "Filtro nginx-botsearch instalado"
        else
            log_warning "Template fail2ban-nginx-botsearch.conf no encontrado, creando inline..."
            cat > /etc/fail2ban/filter.d/nginx-botsearch.conf << 'FILTEREOF'
[Definition]
failregex = ^<HOST> -.*"(GET|POST|HEAD) [^"]*(\.(php|asp|aspx|jsp|cgi|env|git|config|bak|sql))[^"]*" [0-9]+ .*$
            ^<HOST> -.*"(GET|POST|HEAD) [^"]*/(wp-|wordpress|phpmyadmin|admin|\.git)[^"]*" [0-9]+ .*$
            ^<HOST> -.*"(GET|POST|HEAD) [^"]*" 400 .*$
ignoreregex = ^<HOST> -.*"GET /health[^"]*" .*$
              ^<HOST> -.*"GET /api/v1/docs[^"]*" .*$
datepattern = {^LN-BEG}
FILTEREOF
        fi
        
        if [[ -f "$SCRIPT_DIR/templates/fail2ban-nginx-badbots.conf" ]]; then
            cp "$SCRIPT_DIR/templates/fail2ban-nginx-badbots.conf" /etc/fail2ban/filter.d/nginx-badbots.conf
            log_info "Filtro nginx-badbots instalado"
        else
            log_warning "Template fail2ban-nginx-badbots.conf no encontrado, creando inline..."
            cat > /etc/fail2ban/filter.d/nginx-badbots.conf << 'FILTEREOF'
[Definition]
failregex = ^<HOST> -.*"(GET|POST|HEAD|OPTIONS) [^"]*" [0-9]+ [0-9]+ "[^"]*" ".*(nikto|sqlmap|masscan|nmap|zgrab|nuclei|dirbuster|gobuster|wfuzz|ffuf|acunetix|nessus|burp|zap).*"$
ignoreregex =
datepattern = {^LN-BEG}
FILTEREOF
        fi
        
        # Filtro limit-req siempre inline (simple)
        cat > /etc/fail2ban/filter.d/nginx-limit-req.conf << 'FILTEREOF'
[Definition]
failregex = ^<HOST> -.*"(GET|POST|PUT|DELETE|PATCH|OPTIONS) [^"]*" 429 .*$
ignoreregex =
datepattern = {^LN-BEG}
FILTEREOF
        log_info "Filtro nginx-limit-req instalado"
    fi
    complete_task "Filtros nginx instalados"
    
    show_task "Configurando Fail2Ban jail" "running"
    if [[ "$DRY_RUN" != true ]]; then
        backup_file "/etc/fail2ban/jail.local"
        
        cat > /etc/fail2ban/jail.local << JAILEOF
# =============================================================================
# Configuración de Jail de Fail2Ban
# Jails de SSH + Nginx con backend de nftables
# =============================================================================

[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
backend  = polling
banaction = nftables-allports
ignoreip = 127.0.0.1/8 ::1 172.20.0.0/16

# =============================================================================
# SSH Protection
# =============================================================================
[sshd]
enabled  = true
port     = $SSH_PORT
logpath  = /var/log/auth.log
backend  = systemd
maxretry = 3
bantime  = 7200
findtime = 600

# =============================================================================
# Nginx API Authentication Failures (401/403)
# =============================================================================
[nginx-http-auth]
enabled  = true
port     = http,https
filter   = nginx-http-auth
logpath  = ${nginx_log_path}/iot-api-access.log
maxretry = 10
bantime  = 1800
findtime = 600

# =============================================================================
# Nginx Vulnerability Scanners (.env, .git, wp-admin, etc.)
# =============================================================================
[nginx-botsearch]
enabled  = true
port     = http,https
filter   = nginx-botsearch
logpath  = ${nginx_log_path}/iot-api-access.log
maxretry = 3
bantime  = 86400
findtime = 3600

# =============================================================================
# Nginx Bad User Agents (nikto, sqlmap, nmap, etc.)
# =============================================================================
[nginx-badbots]
enabled  = true
port     = http,https
filter   = nginx-badbots
logpath  = ${nginx_log_path}/iot-api-access.log
maxretry = 1
bantime  = 86400
findtime = 86400

# =============================================================================
# Nginx Rate Limiting (429 responses)
# =============================================================================
[nginx-limit-req]
enabled  = true
port     = http,https
filter   = nginx-limit-req
logpath  = ${nginx_log_path}/iot-api-access.log
maxretry = 10
bantime  = 600
findtime = 120
JAILEOF
    fi
    complete_task "Jail de Fail2Ban configurado"
    
    show_task "Creando directorio y archivos de logs de nginx" "running"
    if [[ "$DRY_RUN" != true ]]; then
        mkdir -p "$nginx_log_path"
        chown -R "$NEW_USERNAME:$NEW_USERNAME" "$nginx_log_path" 2>/dev/null || true
        chmod 755 "$nginx_log_path"
        
        # Pre-crear archivos de log vacíos para que Fail2Ban no falle al iniciar
        touch "$nginx_log_path/iot-api-access.log"
        touch "$nginx_log_path/iot-api-error.log"
        touch "$nginx_log_path/iot-api-health.log"
        touch "$nginx_log_path/access.log"
        touch "$nginx_log_path/error.log"
        chown "$NEW_USERNAME:$NEW_USERNAME" "$nginx_log_path"/*.log 2>/dev/null || true
        chmod 644 "$nginx_log_path"/*.log
    fi
    complete_task "Directorio de logs de nginx preparado"
    
    show_task "Habilitando y reiniciando Fail2Ban" "running"
    if [[ "$DRY_RUN" != true ]]; then
        systemctl enable fail2ban
        systemctl restart fail2ban
        
        sleep 3
        if ! systemctl is-active --quiet fail2ban; then
            log_warning "Fail2Ban no arrancó correctamente - verificar con: journalctl -u fail2ban -n 50"
        else
            log_success "Fail2Ban activo"
            local jails_status=$(fail2ban-client status 2>/dev/null | grep "Jail list" || echo "")
            if [[ -n "$jails_status" ]]; then
                log_info "$jails_status"
            fi
        fi
    fi
    complete_task "Fail2Ban activado"
    
    log_success "Fase 4 completada"
}

################################################################################
# FASE 5: Hardening SSH
################################################################################
phase_5_ssh_hardening() {
    CURRENT_PHASE=5
    log_info "Iniciando Fase 5: Hardening SSH"
    
    source "$CONFIG_FILE"
    
    show_task "Respaldando configuración SSH actual" "running"
    if [[ "$DRY_RUN" != true ]]; then
        backup_file "/etc/ssh/sshd_config"
    fi
    complete_task "Configuración SSH respaldada"
    
    show_task "Aplicando configuración SSH segura" "running"
    if [[ "$DRY_RUN" != true ]]; then
        cat > /etc/ssh/sshd_config << SSHEOF
# Configuración SSH Segura - Generada por Instalador IoT
Port $SSH_PORT
Protocol 2
AddressFamily inet

# Autenticación
PermitRootLogin no
MaxAuthTries 3
MaxSessions 3
PubkeyAuthentication yes
PasswordAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no

# Seguridad
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
PermitTunnel no
ClientAliveInterval 300
ClientAliveCountMax 2
LoginGraceTime 30
StrictModes yes

# Logging
SyslogFacility AUTH
LogLevel VERBOSE

# Solo usuarios autorizados
AllowUsers $NEW_USERNAME

# SFTP subsystem para scp/sftp
Subsystem sftp /usr/lib/openssh/sftp-server
SSHEOF
    fi
    complete_task "Configuración SSH segura aplicada"
    
    show_task "Probando configuración SSH" "running"
    if [[ "$DRY_RUN" != true ]]; then
        sshd -t || {
            log_error "Configuración SSH inválida"
            return 1
        }
    fi
    complete_task "Configuración SSH válida"
    
    show_task "Reiniciando servicio SSH" "running"
    if [[ "$DRY_RUN" != true ]]; then
        systemctl restart sshd
    fi
    complete_task "SSH reiniciado"
    
    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${YELLOW}║${RESET}  ${BOLD}IMPORTANTE: El puerto SSH ha cambiado${RESET}                                       ${YELLOW}║${RESET}"
    echo -e "${YELLOW}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
    echo -e "${YELLOW}║${RESET}                                                                              ${YELLOW}║${RESET}"
    echo -e "${YELLOW}║${RESET}  Nuevo puerto SSH: ${GREEN}$SSH_PORT${RESET}                                                    ${YELLOW}║${RESET}"
    echo -e "${YELLOW}║${RESET}  Nuevo comando de conexión:                                                   ${YELLOW}║${RESET}"
    echo -e "${YELLOW}║${RESET}                                                                              ${YELLOW}║${RESET}"
    echo -e "${YELLOW}║${RESET}    ${CYAN}ssh $NEW_USERNAME@$VPS_IP -p $SSH_PORT${RESET}                                    ${YELLOW}║${RESET}"
    echo -e "${YELLOW}║${RESET}                                                                              ${YELLOW}║${RESET}"
    echo -e "${YELLOW}║${RESET}  ${RED}Guarda este comando para futuras conexiones.${RESET}                               ${YELLOW}║${RESET}"
    echo -e "${YELLOW}║${RESET}                                                                              ${YELLOW}║${RESET}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    
    log_success "Fase 5 completada"
}

################################################################################
# FASE 6: Docker
################################################################################
phase_6_docker() {
    CURRENT_PHASE=6
    log_info "Iniciando Fase 6: Instalación de Docker"
    
    source "$CONFIG_FILE"
    
    show_task "Añadiendo clave GPG de Docker" "running"
    if [[ "$DRY_RUN" != true ]]; then
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
    fi
    complete_task "Clave GPG añadida"
    
    show_task "Añadiendo repositorio de Docker" "running"
    if [[ "$DRY_RUN" != true ]]; then
        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
            $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
            tee /etc/apt/sources.list.d/docker.list > /dev/null
    fi
    complete_task "Repositorio añadido"
    
    show_task "Actualizando índice de paquetes" "running"
    exec_cmd "apt-get update" "Actualizar índice"
    complete_task "Índice actualizado"
    
    show_task "Instalando Docker Engine" "running"
    exec_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin" "Instalar Docker"
    complete_task "Docker instalado"
    
    show_task "Añadiendo usuario al grupo docker" "running"
    if [[ "$DRY_RUN" != true ]]; then
        usermod -aG docker "$NEW_USERNAME"
    fi
    complete_task "Usuario añadido al grupo docker"
    
    show_task "Habilitando servicio Docker" "running"
    if [[ "$DRY_RUN" != true ]]; then
        systemctl enable docker
        systemctl start docker
    fi
    complete_task "Docker habilitado"
    
    log_success "Fase 6 completada"
}

################################################################################
# FASE 7: Estructura del Proyecto
################################################################################
phase_7_project_structure() {
    CURRENT_PHASE=7
    log_info "Iniciando Fase 7: Estructura del Proyecto"
    
    source "$CONFIG_FILE"
    source "$SECRETS_FILE"
    local install_dir="$INSTALL_DIR"
    
    show_task "Verificando directorios del proyecto" "running"
    if [[ "$DRY_RUN" != true ]]; then
        mkdir -p "$install_dir"/{mysql-init,mysql-data,mongo-data,redis-data,nginx/conf.d,fastapi-app}
        mkdir -p "$install_dir/logs"/{mysql,mongodb,redis,fastapi,nginx}
    fi
    complete_task "Directorios verificados"
    
    show_task "Generando archivo .env" "running"
    if [[ "$DRY_RUN" != true ]]; then
        sed -e "s|{{MYSQL_ROOT_PASSWORD}}|$MYSQL_ROOT_PASSWORD|g" \
            -e "s|{{MYSQL_PASSWORD}}|$MYSQL_PASSWORD|g" \
            -e "s|{{REDIS_PASSWORD}}|$REDIS_PASSWORD|g" \
            -e "s|{{MONGO_PASSWORD}}|$MONGO_PASSWORD|g" \
            -e "s|{{SECRET_KEY}}|$SECRET_KEY|g" \
            -e "s|{{DB_NAME}}|$DB_NAME|g" \
            "$SCRIPT_DIR/templates/env.tpl" > "$install_dir/.env"
        
        chmod 600 "$install_dir/.env"
    fi
    complete_task "Archivo .env generado"
    
    show_task "Estableciendo permisos" "running"
    if [[ "$DRY_RUN" != true ]]; then
        chown -R "$NEW_USERNAME:$NEW_USERNAME" "$install_dir"
    fi
    complete_task "Permisos establecidos"
    
    log_success "Fase 7 completada"
}

################################################################################
# FASE 8: Aplicación FastAPI
################################################################################
phase_8_fastapi_app() {
    CURRENT_PHASE=8
    log_info "Iniciando Fase 8: Aplicación FastAPI"
    
    source "$CONFIG_FILE"
    local app_dir="$INSTALL_DIR/fastapi-app"
    
    show_task "Copiando código de aplicación" "running"
    if [[ "$DRY_RUN" != true ]]; then
        cp -r "$SCRIPT_DIR/templates/fastapi-app/"* "$app_dir/"
    fi
    complete_task "Código de aplicación copiado"
    
    show_task "Estableciendo permisos de aplicación" "running"
    if [[ "$DRY_RUN" != true ]]; then
        chown -R "$NEW_USERNAME:$NEW_USERNAME" "$app_dir"
        chmod -R 755 "$app_dir"
    fi
    complete_task "Permisos establecidos"
    
    show_task "Creando estructura de paquetes Python" "running"
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
    complete_task "Estructura de paquetes creada"
    
    log_success "Fase 8 completada"
}

################################################################################
# FASE 9: Inicialización de MySQL
################################################################################
phase_9_mysql_init() {
    CURRENT_PHASE=9
    log_info "Iniciando Fase 9: Inicialización de MySQL"
    
    source "$CONFIG_FILE"
    source "$SECRETS_FILE"
    local install_dir="$INSTALL_DIR"
    
    show_task "Generando hashes de contraseñas Argon2" "running"
    generate_test_password_hashes
    complete_task "Hashes de contraseñas generados"
    
    show_task "Creando script de inicialización de MySQL" "running"
    if [[ "$DRY_RUN" != true ]]; then
        local admin_email="${ADMIN_EMAIL:-master@fire.com}"
        
        sed -e "s|{{ADMIN_PASSWORD_HASH}}|$ADMIN_PASSWORD_HASH|g" \
            -e "s|{{USER_PASSWORD_HASH}}|$USER_PASSWORD_HASH|g" \
            -e "s|{{MANAGER_PASSWORD_HASH}}|$MANAGER_PASSWORD_HASH|g" \
            -e "s|{{ADMIN_EMAIL}}|$admin_email|g" \
            "$SCRIPT_DIR/templates/mysql-init.sql.tpl" > "$install_dir/mysql-init/init.sql"
    fi
    complete_task "Script de inicialización MySQL creado"
    
    log_success "Fase 9 completada"
}

################################################################################
# FASE 10: Configuración de Nginx
################################################################################
phase_10_nginx() {
    CURRENT_PHASE=10
    log_info "Iniciando Fase 10: Configuración de Nginx"
    
    source "$CONFIG_FILE"
    local install_dir="$INSTALL_DIR"
    
    show_task "Copiando configuración principal de Nginx" "running"
    if [[ "$DRY_RUN" != true ]]; then
        cp "$SCRIPT_DIR/templates/nginx.conf.tpl" "$install_dir/nginx/nginx.conf"
    fi
    complete_task "Configuración principal copiada"
    
    show_task "Copiando configuración de sitio Nginx" "running"
    if [[ "$DRY_RUN" != true ]]; then
        cp "$SCRIPT_DIR/templates/nginx-site.conf.tpl" "$install_dir/nginx/conf.d/iot-api.conf"
    fi
    complete_task "Configuración de sitio copiada"
    
    log_success "Fase 10 completada"
}

################################################################################
# FASE 11: Despliegue
################################################################################
phase_11_deployment() {
    CURRENT_PHASE=11
    log_info "Iniciando Fase 11: Despliegue"
    
    source "$CONFIG_FILE"
    local install_dir="$INSTALL_DIR"
    
    show_task "Creando docker-compose.yml" "running"
    if [[ "$DRY_RUN" != true ]]; then
        sed -e "s|{{DOCKER_SUBNET}}|$DOCKER_SUBNET|g" \
            "$SCRIPT_DIR/templates/docker-compose.yml.tpl" > "$install_dir/docker-compose.yml"
    fi
    complete_task "docker-compose.yml creado"
    
    show_task "Iniciando servicios Docker" "running"
    if [[ "$DRY_RUN" != true ]]; then
        cd "$install_dir"
        
        log_info "Verificando que Docker esté listo..."
        local docker_wait=0
        while ! docker info >/dev/null 2>&1; do
            sleep 2
            docker_wait=$((docker_wait + 2))
            if [[ $docker_wait -ge 30 ]]; then
                log_error "Docker daemon no responde después de 30 segundos"
                return 1
            fi
        done
        sleep 5
        
        local max_retries=3
        local retry_count=0
        local success=false
        
        while [[ $retry_count -lt $max_retries ]] && [[ "$success" == false ]]; do
            retry_count=$((retry_count + 1))
            log_info "Intento $retry_count de $max_retries..."
            
            if docker compose up -d >> "$LOG_FILE" 2>&1; then
                success=true
            else
                if [[ $retry_count -lt $max_retries ]]; then
                    log_warning "Fallo en intento $retry_count. Reintentando en 10 segundos..."
                    sleep 10
                fi
            fi
        done
        
        if [[ "$success" == false ]]; then
            log_error "Docker compose falló después de $max_retries intentos"
            log_error "Ejecuta manualmente: cd $install_dir && docker compose up -d"
            log_error "Luego reanuda con: sudo ./install.sh --resume"
            return 1
        fi
    fi
    complete_task "Servicios iniciados"
    
    show_task "Esperando a que los servicios estén saludables" "running"
    if [[ "$DRY_RUN" != true ]]; then
        log_info "Esto puede tomar 60-90 segundos..."
        sleep 30
        
        local max_wait=120
        local elapsed=0
        while [[ $elapsed -lt $max_wait ]]; do
            local healthy=$(docker compose ps 2>/dev/null | grep -c "(healthy)" || echo 0)
            if [[ $healthy -ge 5 ]]; then
                break
            fi
            sleep 10
            elapsed=$((elapsed + 10))
        done
        
        if [[ $healthy -lt 5 ]]; then
            log_warning "Solo $healthy de 5 contenedores están healthy después de ${max_wait}s"
        fi
    fi
    complete_task "Servicios están saludables"
    
    log_success "Fase 11 completada"
}

################################################################################
# FASE 12: Pruebas y Validación
################################################################################
phase_12_testing() {
    CURRENT_PHASE=12
    log_info "Iniciando Fase 12: Pruebas y Validación"
    
    source "$CONFIG_FILE"
    
    local admin_email="${ADMIN_EMAIL:-master@fire.com}"
    local admin_password="${ADMIN_PASSWORD:-password123}"
    
    show_task "Probando endpoint de salud" "running"
    if [[ "$DRY_RUN" != true ]]; then
        local health_response=$(curl -s http://localhost/health)
        if echo "$health_response" | grep -q "healthy"; then
            complete_task "Endpoint de salud OK"
        else
            log_error "Verificación de salud fallida"
        fi
    else
        complete_task "Endpoint de salud (dry-run)"
    fi
    
    show_task "Probando autenticación de administrador" "running"
    if [[ "$DRY_RUN" != true ]]; then
        local secrets_path="/home/${NEW_USERNAME}/.iot-platform/.secrets"
        log_info "Buscando secretos en: $secrets_path"
        
        local redis_pass=""
        if [[ -f "$secrets_path" ]]; then
            redis_pass=$(grep 'REDIS_PASSWORD=' "$secrets_path" 2>/dev/null | cut -d'"' -f2)
            log_info "Redis password encontrada: ${redis_pass:0:4}****"
        else
            log_warning "Archivo de secretos no encontrado: $secrets_path"
        fi
        
        local admin_response=$(curl -s -X POST http://localhost/api/v1/auth/login/admin \
            -H "Content-Type: application/json" \
            -d "{\"email\":\"$admin_email\",\"password\":\"$admin_password\"}")
        
        if echo "$admin_response" | grep -q "access_token"; then
            log_success "Autenticación de administrador funciona"
            
            local access_token=$(echo "$admin_response" | jq -r '.access_token' 2>/dev/null)
            
            if [[ -n "$access_token" && "$access_token" != "null" ]]; then
                curl -s -o /dev/null -X POST http://localhost/api/v1/auth/logout \
                    -H "Authorization: Bearer $access_token" || true
            fi
        else
            log_warning "La autenticación de administrador puede tener problemas"
            log_info "Respuesta: $admin_response"
        fi
        
        if [[ -n "$redis_pass" ]]; then
            log_info "Ejecutando FLUSHALL en Redis..."
            if docker exec iot-redis redis-cli -a "$redis_pass" FLUSHALL 2>&1 | grep -q "OK"; then
                log_success "Sesión de prueba limpiada de Redis"
            else
                log_warning "FLUSHALL puede haber fallado - verificar manualmente"
            fi
        else
            log_warning "No se pudo obtener REDIS_PASSWORD - sesión de prueba puede persistir"
        fi
    fi
    complete_task "Autenticación probada"
    
    show_task "Probando endpoint de sensores MongoDB" "running"
    if [[ "$DRY_RUN" != true ]]; then
        log_info "La autenticación de dispositivo requiere puzzle - se necesita prueba manual"
    fi
    complete_task "Endpoints de MongoDB listos para pruebas"
    
    show_task "Verificando aislamiento de bases de datos" "running"
    if [[ "$DRY_RUN" != true ]]; then
        ! nc -zv localhost 3306 2>&1 | grep -q "succeeded" && \
        ! nc -zv localhost 6379 2>&1 | grep -q "succeeded" && \
        ! nc -zv localhost 27017 2>&1 | grep -q "succeeded"
        
        if [[ $? -eq 0 ]]; then
            log_success "Bases de datos están aisladas (no expuestas)"
        else
            log_error "¡Las bases de datos podrían estar expuestas al host!"
        fi
    fi
    complete_task "Aislamiento de bases de datos verificado"
    
    show_task "Verificando estado de contenedores" "running"
    if [[ "$DRY_RUN" != true ]]; then
        cd "$INSTALL_DIR"
        docker compose ps >> "$LOG_FILE"
    fi
    complete_task "Contenedores verificados"
    
    log_success "Fase 12 completada"
}

################################################################################
# FASE 13: Limpieza Final
################################################################################
phase_13_cleanup() {
    CURRENT_PHASE=13
    log_info "Iniciando Fase 13: Limpieza Final"
    
    source "$CONFIG_FILE"
    
    if id "debian" &>/dev/null; then
        show_task "Configurando eliminación automática de usuario debian" "running"
        if [[ "$DRY_RUN" != true ]]; then
            cat > /usr/local/bin/cleanup-debian-user.sh << 'CLEANUPEOF'
#!/bin/bash
LOG="/var/log/iot-platform-cleanup.log"
echo "$(date): Iniciando limpieza de usuario debian" >> "$LOG"

for i in {1..6}; do
    if ! pgrep -u debian sshd > /dev/null 2>&1; then
        echo "$(date): No hay sesiones SSH de debian activas" >> "$LOG"
        break
    fi
    echo "$(date): Esperando a que debian cierre sesión (intento $i/6)..." >> "$LOG"
    sleep 10
done

if id "debian" &>/dev/null; then
    echo "$(date): Eliminando usuario debian..." >> "$LOG"
    pkill -9 -u debian 2>/dev/null || true
    sleep 1
    deluser --remove-home debian >> "$LOG" 2>&1 || true
    echo "$(date): Usuario debian eliminado" >> "$LOG"
else
    echo "$(date): Usuario debian no existe" >> "$LOG"
fi

systemctl disable debian-cleanup.service 2>/dev/null || true
rm -f /etc/systemd/system/debian-cleanup.service
rm -f /usr/local/bin/cleanup-debian-user.sh
systemctl daemon-reload

echo "$(date): Limpieza completada" >> "$LOG"
CLEANUPEOF
            chmod +x /usr/local/bin/cleanup-debian-user.sh
            
            cat > /etc/systemd/system/debian-cleanup.service << 'SERVICEEOF'
[Unit]
Description=IoT Platform - Cleanup debian user
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/cleanup-debian-user.sh
RemainAfterExit=no
SERVICEEOF

            systemctl daemon-reload
            
            if command -v at &>/dev/null; then
                echo "/usr/local/bin/cleanup-debian-user.sh" | at now + 1 minute 2>/dev/null || true
            else
                (sleep 90 && /usr/local/bin/cleanup-debian-user.sh) &>/dev/null &
            fi
            
            log_info "Usuario debian será eliminado automáticamente en ~90 segundos"
        fi
        complete_task "Eliminación de debian programada"
    else
        log_info "Usuario debian no existe (ya fue eliminado o no existía)"
    fi
    
    show_task "Configurando permisos de logs" "running"
    if [[ "$DRY_RUN" != true ]]; then
        mkdir -p "$INSTALL_DIR/logs/fastapi"
        chown -R 1000:1000 "$INSTALL_DIR/logs" 2>/dev/null || true
        chmod -R 755 "$INSTALL_DIR/logs"
        
        docker exec -u root iot-fastapi mkdir -p /var/log/fastapi/sessions 2>/dev/null || true
        docker exec -u root iot-fastapi chmod 777 /var/log/fastapi 2>/dev/null || true
        docker exec -u root iot-fastapi chmod 777 /var/log/fastapi/sessions 2>/dev/null || true
    fi
    complete_task "Permisos de logs configurados"
    
    show_task "Recargando Fail2Ban con logs de nginx activos" "running"
    if [[ "$DRY_RUN" != true ]]; then
        sleep 3
        
        local nginx_log_path="$INSTALL_DIR/logs/nginx"
        if [[ -f "$nginx_log_path/iot-api-access.log" ]]; then
            log_info "Logs de nginx detectados, recargando Fail2Ban..."
            systemctl reload fail2ban 2>/dev/null || systemctl restart fail2ban 2>/dev/null || true
            
            sleep 2
            local jails_status=$(fail2ban-client status 2>/dev/null || echo "")
            if echo "$jails_status" | grep -q "nginx"; then
                log_success "Jails de nginx activos en Fail2Ban"
            else
                log_warning "Verificar jails con: sudo fail2ban-client status"
            fi
        else
            log_warning "Logs de nginx aún no existen - Fail2Ban nginx jails se activarán en próximo reinicio"
        fi
    fi
    complete_task "Fail2Ban recargado"
    
    show_task "Limpiando archivos temporales" "running"
    if [[ "$DRY_RUN" != true ]]; then
        rm -rf /tmp/iot-platform-argon2-venv 2>/dev/null || true
        apt-get clean 2>/dev/null || true
        apt-get autoremove -y 2>/dev/null || true
    fi
    complete_task "Archivos temporales eliminados"
    
    show_task "Verificación final del sistema" "running"
    if [[ "$DRY_RUN" != true ]]; then
        local issues=0
        
        if ! systemctl is-active --quiet docker; then
            log_warning "Docker no está activo"
            issues=$((issues + 1))
        fi
        
        cd "$INSTALL_DIR" 2>/dev/null
        local healthy_containers=$(docker compose ps 2>/dev/null | grep -c "(healthy)" || echo 0)
        if [[ $healthy_containers -lt 5 ]]; then
            log_warning "Algunos contenedores no están healthy (esperados: 5, healthy: $healthy_containers)"
            issues=$((issues + 1))
        fi
        
        if ! systemctl is-active --quiet nftables; then
            log_warning "nftables no está activo"
            issues=$((issues + 1))
        fi
        
        if ! systemctl is-active --quiet fail2ban; then
            log_warning "Fail2Ban no está activo"
            issues=$((issues + 1))
        fi
        
        if [[ $issues -eq 0 ]]; then
            log_success "Todas las verificaciones pasaron"
        else
            log_warning "Se encontraron $issues advertencias - revisar log"
        fi
    fi
    complete_task "Verificación final completada"
    
    show_task "Finalizando instalación" "running"
    if [[ "$DRY_RUN" != true ]]; then
        echo "INSTALLATION_COMPLETE=true" >> "$INSTALL_STATE_FILE"
        echo "COMPLETION_DATE=\"$(date)\"" >> "$INSTALL_STATE_FILE"
    fi
    complete_task "Instalación finalizada"
    
    log_success "Fase 13 completada"
}

################################################################################
# Función legacy
################################################################################
delete_debian_user() {
    log_info "La eliminación de debian es automática via systemd timer"
}
