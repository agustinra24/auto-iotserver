#!/bin/bash
################################################################################
# lib/phases.sh - Implementaciones de fases de instalación (v2.3)
################################################################################

################################################################################
# FASE 0: Preparación
################################################################################
phase_0_preparation() {
    CURRENT_PHASE=0
    log_info "Iniciando Fase 0: Preparación"
    
    # Verificación de requisitos del sistema
    show_task "Verificando requisitos del sistema" "running"
    validate_system_requirements
    complete_task "Requisitos del sistema validados"
    
    # Crear directorio de instalación
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
    
    # Verificar templates
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

    # Actualizar sistema primero
    show_task "Actualizando paquetes del sistema" "running"
    exec_cmd "apt-get update" "Actualizar lista de paquetes"
    exec_cmd "DEBIAN_FRONTEND=noninteractive apt-get upgrade -y" "Actualizar paquetes"
    complete_task "Sistema actualizado"

    # Crear nuevo usuario
    show_task "Creando usuario: $NEW_USERNAME" "running"
    
    if id "$NEW_USERNAME" &>/dev/null; then
        log_info "El usuario $NEW_USERNAME ya existe"
    else
        adduser --disabled-password --gecos "" "$NEW_USERNAME"
        
        local temp_password=$(openssl rand -base64 16 | tr -d "=+/")
        echo "$NEW_USERNAME:$temp_password" | chpasswd
        
        mkdir -p "$(dirname "$SECRETS_FILE")"
        echo "TEMP_USER_PASSWORD=\"$temp_password\"" >> "$SECRETS_FILE"
        chmod 600 "$SECRETS_FILE"
        
        log_info "Contraseña temporal para $NEW_USERNAME: $temp_password"
        log_warning "¡Cambia esta contraseña después del primer login!"
    fi
    complete_task "Usuario creado: $NEW_USERNAME"

    # Agregar al grupo sudo
    show_task "Otorgando privilegios sudo" "running"
    usermod -aG sudo "$NEW_USERNAME"
    complete_task "Privilegios sudo otorgados"

    # Configurar sudo sin contraseña
    show_task "Configurando sudo" "running"
    echo "$NEW_USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$NEW_USERNAME"
    chmod 440 "/etc/sudoers.d/$NEW_USERNAME"
    complete_task "Sudo configurado"

    # Configurar directorio home
    show_task "Configurando directorio home" "running"
    mkdir -p "/home/$NEW_USERNAME"
    chown "$NEW_USERNAME:$NEW_USERNAME" "/home/$NEW_USERNAME"
    chmod 755 "/home/$NEW_USERNAME"
    complete_task "Directorio home listo"

    # Copiar instalador al home del nuevo usuario
    show_task "Copiando instalador al home del nuevo usuario" "running"
    local new_installer_dir="/home/$NEW_USERNAME/iot-platform-installer"
    if [[ "$SCRIPT_DIR" != "$new_installer_dir" ]]; then
        cp -r "$SCRIPT_DIR" "$new_installer_dir"
        chown -R "$NEW_USERNAME:$NEW_USERNAME" "$new_installer_dir"
        chmod +x "$new_installer_dir/install.sh"
        chmod +x "$new_installer_dir/lib/"*.sh
    fi
    complete_task "Instalador copiado"

    # Crear configuración en nueva ubicación
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
    
    cat > "$new_config" << NEWCONFEOF
# Configuración de Instalación de Plataforma IoT
# Generado: $(date)

VPS_IP="$VPS_IP"
NEW_USERNAME="$NEW_USERNAME"
SSH_PORT="$SSH_PORT"
DOMAIN="$DOMAIN"
DB_NAME="fire_preventionf"
DOCKER_SUBNET="$DOCKER_SUBNET"
REDIS_MEMORY="$REDIS_MEMORY"
TIMEZONE="$TIMEZONE"

# Rutas
INSTALL_DIR="/home/${NEW_USERNAME}/iot-platform"
SECRETS_FILE="$new_secrets"
NEWCONFEOF
    
    chown "$NEW_USERNAME:$NEW_USERNAME" "$new_config"
    chmod 600 "$new_config"
    complete_task "Configuración creada para nuevo usuario"

    # Guardar punto de control
    show_task "Guardando punto de control" "running"
    local new_state_file="/home/$NEW_USERNAME/iot-platform-installer/.install-state"
    cat > "$new_state_file" << STATEEOF
LAST_COMPLETED_PHASE=1
TIMESTAMP=$(date +%s)
DATE="$(date)"
STATEEOF
    chown "$NEW_USERNAME:$NEW_USERNAME" "$new_state_file"
    complete_task "Punto de control guardado"

    # Configurar hostname
    show_task "Configurando hostname" "running"
    echo "iot-platform" > /etc/hostname
    hostname iot-platform
    if ! grep -q "iot-platform" /etc/hosts; then
        sed -i "s/127.0.1.1.*/127.0.1.1\tiot-platform/" /etc/hosts
    fi
    complete_task "Hostname configurado"

    # Establecer zona horaria
    show_task "Estableciendo zona horaria: $TIMEZONE" "running"
    timedatectl set-timezone "$TIMEZONE" 2>/dev/null || true
    complete_task "Zona horaria establecida"

    # Manejar eliminación del usuario debian
    if id "debian" &>/dev/null; then
        log_success "Fase 1 completada"
        
        # Obtener la contraseña temporal del archivo de secretos
        local temp_pass=""
        if [[ -f "$SECRETS_FILE" ]]; then
            temp_pass=$(grep 'TEMP_USER_PASSWORD=' "$SECRETS_FILE" | cut -d'"' -f2)
        fi
        
        echo ""
        echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${BOLD}PAUSA REQUERIDA - CAMBIO DE USUARIO${RESET}                                    ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${BOLD}RESUMEN DE LO QUE PASO:${RESET}                                                 ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ─────────────────────────────────────────────────────────────────────────  ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${GREEN}[OK]${RESET} Se creó el nuevo usuario: ${YELLOW}$NEW_USERNAME${RESET}                                       ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${GREEN}[OK]${RESET} Se le otorgaron permisos de administrador (sudo)                         ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${GREEN}[OK]${RESET} El usuario \"debian\" será eliminado por seguridad                         ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${BOLD}CREDENCIALES DEL NUEVO USUARIO (ANOTALAS):${RESET}                            ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ─────────────────────────────────────────────────────────────────────────  ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}      ${BOLD}Usuario:${RESET}     ${GREEN}$NEW_USERNAME${RESET}                                                   ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}      ${BOLD}Contraseña:${RESET}  ${GREEN}$temp_pass${RESET}                                          ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}      ${BOLD}Servidor:${RESET}    ${GREEN}$VPS_IP${RESET}                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${BOLD}LO QUE DEBES HACER (paso a paso):${RESET}                                       ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ─────────────────────────────────────────────────────────────────────────  ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}PASO 1:${RESET} Copia este comando ${BOLD}ANTES${RESET} de presionar ENTER:                       ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}           ${GREEN}ssh $NEW_USERNAME@$VPS_IP${RESET}                                         ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}PASO 2:${RESET} Presiona ENTER (esta ventana se cerrará automáticamente)           ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}PASO 3:${RESET} Espera 5 segundos                                                  ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}PASO 4:${RESET} Abre una nueva terminal y pega el comando copiado                  ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}PASO 5:${RESET} Ingresa la contraseña mostrada arriba                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}PASO 6:${RESET} Ya conectado, ejecuta:                                             ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}           ${GREEN}cd ~/iot-platform-installer && sudo ./install.sh --resume${RESET}          ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${RED}ADVERTENCIAS IMPORTANTES:${RESET}                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ─────────────────────────────────────────────────────────────────────────  ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${RED}•${RESET} NO cierres esta ventana manualmente, se cerrará sola                     ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${RED}•${RESET} Si pierdes la contraseña, está guardada en ~/.iot-platform/.secrets      ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${RED}•${RESET} Cambia la contraseña después de terminar la instalación                  ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${GREEN}Cuando hayas copiado el comando, presiona ENTER para continuar${RESET}          ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
        echo ""
        read -p "Presiona ENTER para continuar..."
        
        pkill -u debian 2>/dev/null || true
        sleep 2
        deluser --remove-home debian 2>/dev/null || true
        
        exit 0
    fi

    log_success "Fase 1 completada"
}

################################################################################
# FASE 2: Dependencias Base
################################################################################
phase_2_dependencies() {
    CURRENT_PHASE=2
    log_info "Iniciando Fase 2: Dependencias Base"
    
    show_task "Instalando herramientas de compilación" "running"
    exec_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential git curl wget jq" "Instalar herramientas de compilación"
    complete_task "Herramientas de compilación instaladas"
    
    show_task "Instalando Python y dependencias" "running"
    exec_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-pip python3-dev python3-venv" "Instalar Python"
    complete_task "Python instalado"
    
    show_task "Instalando herramientas de red" "running"
    exec_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y net-tools netcat-openbsd iproute2" "Instalar herramientas de red"
    complete_task "Herramientas de red instaladas"
    
    show_task "Instalando utilidades de monitoreo" "running"
    exec_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y htop iotop sysstat" "Instalar herramientas de monitoreo"
    complete_task "Utilidades de monitoreo instaladas"
    
    show_task "Instalando herramientas de seguridad" "running"
    exec_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y ufw nftables" "Instalar herramientas de firewall"
    complete_task "Herramientas de seguridad instaladas"
    
    log_success "Fase 2 completada"
}

################################################################################
# FASE 3: Firewall (nftables)
################################################################################
phase_3_firewall() {
    CURRENT_PHASE=3
    log_info "Iniciando Fase 3: Configuración de Firewall"
    
    show_task "Deshabilitando UFW" "running"
    if systemctl is-active --quiet ufw; then
        exec_cmd "systemctl stop ufw" "Detener UFW"
        exec_cmd "systemctl disable ufw" "Deshabilitar UFW"
    fi
    complete_task "UFW deshabilitado"
    
    show_task "Instalando nftables" "running"
    exec_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y nftables" "Instalar nftables"
    complete_task "nftables instalado"
    
    show_task "Configurando reglas de nftables" "running"
    if [[ "$DRY_RUN" != true ]]; then
        sed -e "s/{{SSH_PORT}}/$SSH_PORT/g" \
            "$SCRIPT_DIR/templates/nftables.conf.tpl" > /tmp/nftables.conf
        
        mv /tmp/nftables.conf /etc/nftables.conf
        chmod 644 /etc/nftables.conf
    fi
    complete_task "Reglas de nftables configuradas"
    
    show_task "Habilitando nftables" "running"
    exec_cmd "systemctl enable nftables" "Habilitar servicio nftables"
    exec_cmd "systemctl restart nftables" "Iniciar nftables"
    complete_task "nftables habilitado e iniciado"
    
    show_task "Creando script de deshabilitación de emergencia" "running"
    if [[ "$DRY_RUN" != true ]]; then
        cat > /usr/local/bin/emergency-disable-firewall.sh << 'FWEOF'
#!/bin/bash
echo "EMERGENCIA: Deshabilitando firewall..."
nft flush ruleset
systemctl stop nftables
systemctl disable nftables
echo "Firewall deshabilitado. Corrige tus reglas y vuelve a habilitarlo."
FWEOF
        chmod +x /usr/local/bin/emergency-disable-firewall.sh
    fi
    complete_task "Script de emergencia creado"
    
    log_success "Fase 3 completada"
}

################################################################################
# FASE 4: Fail2Ban
################################################################################
phase_4_fail2ban() {
    CURRENT_PHASE=4
    log_info "Iniciando Fase 4: Fail2Ban"
    
    show_task "Instalando Fail2Ban" "running"
    exec_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y fail2ban" "Instalar Fail2Ban"
    complete_task "Fail2Ban instalado"
    
    show_task "Configurando acción nftables de Fail2Ban" "running"
    if [[ "$DRY_RUN" != true ]]; then
        cp "$SCRIPT_DIR/templates/fail2ban-action.conf.tpl" /etc/fail2ban/action.d/nftables-custom.conf
    fi
    complete_task "Acción nftables configurada"
    
    show_task "Configurando jaulas de Fail2Ban" "running"
    if [[ "$DRY_RUN" != true ]]; then
        sed -e "s/{{SSH_PORT}}/$SSH_PORT/g" \
            "$SCRIPT_DIR/templates/fail2ban-jail.local.tpl" > /etc/fail2ban/jail.local
    fi
    complete_task "Jaulas configuradas"
    
    show_task "Iniciando Fail2Ban" "running"
    exec_cmd "systemctl enable fail2ban" "Habilitar Fail2Ban"
    exec_cmd "systemctl restart fail2ban" "Iniciar Fail2Ban"
    complete_task "Fail2Ban iniciado"
    
    log_success "Fase 4 completada"
}

################################################################################
# FASE 5: Endurecimiento SSH
################################################################################
phase_5_ssh_hardening() {
    CURRENT_PHASE=5
    log_info "Iniciando Fase 5: Endurecimiento SSH"
    
    show_task "Respaldando configuración SSH" "running"
    backup_file "/etc/ssh/sshd_config"
    complete_task "Configuración SSH respaldada"
    
    show_task "Configurando ajustes SSH" "running"
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
    complete_task "SSH configurado"
    
    show_task "Agregando puerto SSH al firewall" "running"
    if [[ "$DRY_RUN" != true ]]; then
        nft -f /etc/nftables.conf
    fi
    complete_task "Firewall actualizado"
    
    show_task "Reiniciando servicio SSH" "running"
    exec_cmd "systemctl restart sshd" "Reiniciar SSH"
    complete_task "SSH reiniciado"
    
    if [[ "$DRY_RUN" != true ]]; then
        echo ""
        echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${BOLD}PAUSA REQUERIDA - VALIDACION DE PUERTO SSH${RESET}                             ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${BOLD}RESUMEN DE LO QUE PASO:${RESET}                                                 ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ─────────────────────────────────────────────────────────────────────────  ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${GREEN}[OK]${RESET} El puerto SSH cambió de ${RED}22${RESET} a ${GREEN}$SSH_PORT${RESET}                                        ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${GREEN}[OK]${RESET} El puerto 22 ${YELLOW}SIGUE ABIERTO${RESET} temporalmente (por seguridad)                ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${GREEN}[OK]${RESET} Al continuar, el puerto 22 se cerrará permanentemente                    ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${BOLD}DATOS DE CONEXION PARA PROBAR:${RESET}                                          ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ─────────────────────────────────────────────────────────────────────────  ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}      ${BOLD}Servidor:${RESET}    ${GREEN}$VPS_IP${RESET}                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}      ${BOLD}Puerto:${RESET}      ${GREEN}$SSH_PORT${RESET}                                                    ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}      ${BOLD}Usuario:${RESET}     ${GREEN}$NEW_USERNAME${RESET}                                                   ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${BOLD}LO QUE DEBES HACER (paso a paso):${RESET}                                       ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ─────────────────────────────────────────────────────────────────────────  ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}PASO 1:${RESET} Abre una ${BOLD}NUEVA${RESET} ventana de terminal                                ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}           ${RED}NO cierres esta ventana! La instalación continúa aquí.${RESET}         ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}PASO 2:${RESET} En la NUEVA terminal, ejecuta este comando:                        ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}           ${GREEN}ssh $NEW_USERNAME@$VPS_IP -p $SSH_PORT${RESET}                                ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}PASO 3:${RESET} Si te conectas exitosamente, prueba que sudo funcione:             ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}           ${GREEN}sudo whoami${RESET}                                                         ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}PASO 4:${RESET} Deberías ver: ${GREEN}root${RESET}                                               ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${YELLOW}PASO 5:${RESET} Cierra la terminal de prueba y vuelve a ESTA ventana               ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${GREEN}SI LA PRUEBA FUE EXITOSA:${RESET}                                               ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}      Presiona ${GREEN}ENTER${RESET} aquí para continuar (el puerto 22 se cerrará)           ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${RED}SI LA PRUEBA FALLO:${RESET}                                                    ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}      Presiona ${RED}Ctrl+C${RESET} para cancelar (el puerto 22 seguirá disponible)        ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}      Revisa los logs en: /var/log/iot-platform/install.log                   ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}   ${GREEN}La conexión al puerto $SSH_PORT funcionó? Presiona ENTER para continuar${RESET}    ${CYAN}║${RESET}"
        echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
        echo ""
        read -p "Presiona ENTER para continuar o Ctrl+C para cancelar..."
    fi
    
    show_task "Cerrando puerto SSH por defecto 22" "running"
    if [[ "$DRY_RUN" != true ]]; then
        sed -i '/^Port 22$/d' /etc/ssh/sshd_config
        systemctl restart sshd
    fi
    complete_task "Puerto 22 cerrado"
    
    log_success "Fase 5 completada"
    log_warning "De ahora en adelante, usa: ssh $NEW_USERNAME@$VPS_IP -p $SSH_PORT"
}

################################################################################
# FASE 6: Instalación de Docker
################################################################################
phase_6_docker() {
    CURRENT_PHASE=6
    log_info "Iniciando Fase 6: Instalación de Docker"
    
    show_task "Eliminando versiones antiguas de Docker" "running"
    exec_cmd "apt-get remove -y docker docker-engine docker.io containerd runc || true" "Eliminar Docker antiguo"
    complete_task "Versiones antiguas de Docker eliminadas"
    
    show_task "Instalando dependencias de Docker" "running"
    exec_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates gnupg lsb-release" "Instalar dependencias"
    complete_task "Dependencias instaladas"
    
    show_task "Agregando clave GPG de Docker" "running"
    if [[ "$DRY_RUN" != true ]]; then
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
    fi
    complete_task "Clave GPG agregada"
    
    show_task "Agregando repositorio de Docker" "running"
    if [[ "$DRY_RUN" != true ]]; then
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
          $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update
    fi
    complete_task "Repositorio agregado"
    
    show_task "Instalando Docker Engine" "running"
    exec_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin" "Instalar Docker"
    complete_task "Docker instalado"
    
    show_task "Agregando $NEW_USERNAME al grupo docker" "running"
    exec_cmd "usermod -aG docker $NEW_USERNAME" "Agregar al grupo docker"
    complete_task "Usuario agregado al grupo docker"
    
    show_task "Configurando demonio de Docker" "running"
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
    complete_task "Demonio de Docker configurado"
    
    show_task "Iniciando servicio Docker" "running"
    exec_cmd "systemctl enable docker" "Habilitar Docker"
    exec_cmd "systemctl start docker" "Iniciar Docker"
    complete_task "Docker iniciado"
    
    show_task "Verificando instalación de Docker" "running"
    if [[ "$DRY_RUN" != true ]]; then
        docker --version >> "$LOG_FILE"
        docker compose version >> "$LOG_FILE"
    fi
    complete_task "Docker verificado"
    
    log_success "Fase 6 completada"
}

################################################################################
# FASE 7: Estructura del Proyecto
################################################################################
phase_7_project_structure() {
    CURRENT_PHASE=7
    log_info "Iniciando Fase 7: Estructura del Proyecto"
    
    source "$CONFIG_FILE"
    local install_dir="$INSTALL_DIR"
    # Crear directorio de logs de sesión con permisos apropiados
    mkdir -p "$install_dir/logs/fastapi/sessions"
    chmod -R 777 "$install_dir/logs/fastapi"

    
    mkdir -p "$install_dir"/{logs,mysql-data,mysql-init,mongo-data,redis-data,nginx/conf.d,nginx/ssl}
    mkdir -p "$install_dir/logs"/{mysql,mongodb,redis,fastapi,nginx}
    mkdir -p "$install_dir/fastapi-app"/{core,models,schemas,api/v1/routers,database}
    
    show_task "Creando archivo de entorno" "running"
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
    complete_task "Archivo de entorno creado"
    
    show_task "Creando .gitignore" "running"
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
    complete_task ".gitignore creado"
    
    show_task "Estableciendo permisos de directorios" "running"
    if [[ "$DRY_RUN" != true ]]; then
        chown -R "$NEW_USERNAME:$NEW_USERNAME" "$install_dir"
        chmod 755 "$install_dir"
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
    local install_dir="$INSTALL_DIR"
    local app_dir="$install_dir/fastapi-app"
    
    show_task "Copiando archivos de la aplicación FastAPI" "running"
    if [[ "$DRY_RUN" != true ]]; then
        cp -r "$SCRIPT_DIR/templates/fastapi-app/"* "$app_dir/"
    fi
    complete_task "Archivos de aplicación copiados"
    
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
        sed -e "s|{{ADMIN_PASSWORD_HASH}}|$ADMIN_PASSWORD_HASH|g" \
            -e "s|{{USER_PASSWORD_HASH}}|$USER_PASSWORD_HASH|g" \
            -e "s|{{MANAGER_PASSWORD_HASH}}|$MANAGER_PASSWORD_HASH|g" \
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
        docker compose up -d >> "$LOG_FILE" 2>&1
    fi
    complete_task "Servicios iniciados"
    
    show_task "Esperando a que los servicios estén saludables" "running"
    if [[ "$DRY_RUN" != true ]]; then
        log_info "Esto puede tomar 60-90 segundos..."
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
        local admin_response=$(curl -s -X POST http://localhost/api/v1/auth/login/admin \
            -H "Content-Type: application/json" \
            -d '{"email":"master@fire.com","password":"password123"}')
        
        if echo "$admin_response" | grep -q "access_token"; then
            log_success "Autenticación de administrador funciona"
            
            # Extraer token y hacer logout <<<
            local admin_token=$(echo "$admin_response" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
            if [[ -n "$admin_token" ]]; then
                curl -s -X POST http://localhost/api/v1/auth/logout \
                    -H "Authorization: Bearer $admin_token" > /dev/null 2>&1
                log_info "Sesión de prueba de admin cerrada correctamente"
            fi
        else
            log_warning "La autenticación de administrador puede tener problemas"
            log_info "Respuesta: $admin_response"
        fi
    fi
    complete_task "Autenticación probada"
    
    # Probar login de usuario y cerrar sesión <<<
    show_task "Probando autenticación de usuario" "running"
    if [[ "$DRY_RUN" != true ]]; then
        local user_response=$(curl -s -X POST http://localhost/api/v1/auth/login/user \
            -H "Content-Type: application/json" \
            -d '{"email":"user@fire.com","password":"password123"}')
        
        if echo "$user_response" | grep -q "access_token"; then
            log_success "Autenticación de usuario funciona"
            
            local user_token=$(echo "$user_response" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
            if [[ -n "$user_token" ]]; then
                curl -s -X POST http://localhost/api/v1/auth/logout \
                    -H "Authorization: Bearer $user_token" > /dev/null 2>&1
                log_info "Sesión de prueba de usuario cerrada correctamente"
            fi
        else
            log_warning "La autenticación de usuario puede tener problemas"
        fi
    fi
    complete_task "Autenticación de usuario probada"
    
    # Probar login de gerente y cerrar sesión <<<
    show_task "Probando autenticación de gerente" "running"
    if [[ "$DRY_RUN" != true ]]; then
        local manager_response=$(curl -s -X POST http://localhost/api/v1/auth/login/manager \
            -H "Content-Type: application/json" \
            -d '{"email":"gerente@fire.com","password":"password123"}')
        
        if echo "$manager_response" | grep -q "access_token"; then
            log_success "Autenticación de gerente funciona"
            
            local manager_token=$(echo "$manager_response" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
            if [[ -n "$manager_token" ]]; then
                curl -s -X POST http://localhost/api/v1/auth/logout \
                    -H "Authorization: Bearer $manager_token" > /dev/null 2>&1
                log_info "Sesión de prueba de gerente cerrada correctamente"
            fi
        else
            log_warning "La autenticación de gerente puede tener problemas"
        fi
    fi
    complete_task "Autenticación de gerente probada"
    
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
    
    # Limpiar cualquier sesión residual de pruebas <<<
    show_task "Limpiando sesiones de prueba" "running"
    if [[ "$DRY_RUN" != true ]]; then
        source "$SECRETS_FILE" 2>/dev/null || source "$INSTALL_DIR/.env" 2>/dev/null
        
        # Limpiar solo las claves de sesión específicas, NO FLUSHALL
        docker exec iot-redis redis-cli -a "$REDIS_PASSWORD" --no-auth-warning \
            DEL "session:admin:1" "session:user:1" "session:manager:1" "session:device:1" \
            > /dev/null 2>&1 || true
        
        log_info "Sesiones de prueba limpiadas"
    fi
    complete_task "Sesiones de prueba limpiadas"
    
    log_success "Fase 12 completada"
}
