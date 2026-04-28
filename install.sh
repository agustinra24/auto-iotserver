#!/bin/bash
################################################################################
# Plataforma IoT con Seguridad Integrada - Instalador Automatizado v1.3
#
# Requisitos: Debian 13.x/Trixie o derivado basado en Trixie, acceso root/sudo
# Ejecución: sudo ./install.sh [--dry-run] [--resume]
#
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/ui.sh"
source "${SCRIPT_DIR}/lib/validation.sh"
source "${SCRIPT_DIR}/lib/secrets.sh"
source "${SCRIPT_DIR}/lib/phases.sh"

INSTALL_STATE_FILE="${SCRIPT_DIR}/.install-state"
CONFIG_FILE="${SCRIPT_DIR}/.config.env"
SECRETS_FILE="${HOME}/.iot-platform/.secrets"
LOG_FILE="${SCRIPT_DIR}/logs/install-$(date +%Y%m%d-%H%M%S).log"
DRY_RUN=false
RESUME_MODE=false
INTERNAL_RESUME=false  # Flag interno para continuación automática via runuser
ALLOW_LEGACY_PI4_MONGODB=false
RESOURCE_PROFILE="auto"
RESOURCE_PROFILE_SOURCE="auto"
COMPACT_STORAGE="auto"
COMPACT_STORAGE_SOURCE="auto"
SAFE_AUTOPURGE="auto"
SAFE_AUTOPURGE_SOURCE="auto"
STORAGE_ALERTS="true"
STORAGE_ALERTS_SOURCE="auto"
STORAGE_PURGE_MODE="none"
STORAGE_PURGE_MODE_SOURCE="auto"
DATA_RETENTION_DAYS="auto"
STORAGE_TOTAL_MB=0
STORAGE_USED_MB=0
STORAGE_AVAILABLE_MB=0

################################################################################
# Helper: aceptar confirmación s/S/y/Y
################################################################################
is_yes() {
    [[ "${1:-}" =~ ^[sSyY]$ ]]
}

################################################################################
# Verificaciones Previas
################################################################################
preflight_checks() {
    log_info "Ejecutando verificaciones previas..."
    
    if [[ $EUID -ne 0 ]]; then
        log_error "Este script debe ejecutarse como root o con sudo"
        log_error "Uso: sudo ./install.sh"
        exit 1
    fi
    
    if [[ ! -f /etc/debian_version ]] || [[ ! -f /etc/os-release ]]; then
        log_error "Este script requiere Debian Linux o un derivado Debian compatible"
        exit 1
    fi

    if [[ ("$INTERNAL_RESUME" == true || "$RESUME_MODE" == true) && -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi

    ensure_platform_supported
    resolve_installation_profiles || exit 1

    local required_cmds=("git" "curl" "openssl" "bc")
    local missing_cmds=()
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_cmds+=("$cmd")
        fi
    done

    if [[ ${#missing_cmds[@]} -gt 0 ]]; then
        log_warning "Dependencias minimas faltantes: ${missing_cmds[*]}"
        if [[ "$DRY_RUN" == true ]]; then
            log_info "[DRY-RUN] No se instalarán paquetes. En instalación real se ejecutaría apt-get update e instalación de: ca-certificates ${missing_cmds[*]}"
        else
            log_info "Instalando dependencias minimas de preflight..."
            DEBIAN_FRONTEND=noninteractive apt-get update >> "$LOG_FILE" 2>&1
            DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates "${missing_cmds[@]}" >> "$LOG_FILE" 2>&1
        fi
    fi

    if ! command -v curl &> /dev/null; then
        if [[ "$DRY_RUN" == true ]]; then
            log_warning "[DRY-RUN] curl no está instalado; se omite prueba de conectividad Docker y se reporta como acción pendiente."
            log_success "Verificaciones previas completadas"
            return 0
        fi
        log_error "curl no está disponible después de instalar dependencias mínimas"
        exit 1
    fi

    if ! curl -fsSL --max-time 10 https://download.docker.com > /dev/null 2>&1; then
        if [[ "$DRY_RUN" == true ]]; then
            log_warning "[DRY-RUN] No se pudo alcanzar https://download.docker.com; en instalación real se requiere conectividad antes de Docker."
            log_success "Verificaciones previas completadas"
            return 0
        fi
        log_error "No se detectó conectividad a internet"
        log_error "No se pudo alcanzar https://download.docker.com, requerido para instalar Docker Engine."
        exit 1
    fi
    
    log_success "Verificaciones previas completadas"
}

################################################################################
# Procesar Argumentos de Línea de Comandos
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
            --internal-resume)
                # Flag interno usado por runuser para continuación automática
                # No requiere archivo de estado - comienza desde fase 2
                INTERNAL_RESUME=true
                shift
                ;;
            --allow-legacy-pi4-mongodb)
                # Permite Raspberry Pi 4/400/CM4 con MongoDB 4.4 EOL.
                # Solo laboratorio/compatibilidad temporal, nunca default.
                ALLOW_LEGACY_PI4_MONGODB=true
                shift
                ;;
            --low-resource)
                # Override avanzado para pruebas reproducibles.
                RESOURCE_PROFILE="low-resource"
                RESOURCE_PROFILE_SOURCE="manual"
                shift
                ;;
            --compact-storage)
                # Override avanzado para pruebas reproducibles en almacenamiento pequeño.
                COMPACT_STORAGE=true
                COMPACT_STORAGE_SOURCE="manual"
                RESOURCE_PROFILE="low-resource"
                RESOURCE_PROFILE_SOURCE="manual"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Opción desconocida: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

################################################################################
# Mostrar Ayuda
################################################################################
show_help() {
    cat << EOF
Plataforma IoT con Seguridad Integrada - Instalador Automatizado v${PLATFORM_VERSION}

USO:
    sudo ./install.sh [OPCIONES]

OPCIONES:
    --dry-run       Vista previa de los pasos de instalación sin ejecutar cambios
    --resume        Reanudar desde el último punto de control exitoso
    -h, --help      Mostrar este mensaje de ayuda

OPCIONES AVANZADAS:
    --low-resource  Activar perfil optimizado para 2GB RAM nominales
                    manualmente. Normalmente se detecta solo.
    --compact-storage
                    Forzar perfil compacto para hosts con poco espacio libre.
                    Normalmente se detecta solo.
    --allow-legacy-pi4-mongodb
                    Permitir Raspberry Pi 4/400/CM4 usando MongoDB 4.4 EOL
                    sin prompt interactivo. Solo laboratorio o compatibilidad temporal.

EJEMPLOS:
    sudo ./install.sh              # Instalación normal con autodetección
    sudo ./install.sh --dry-run    # Vista previa sin cambios
    sudo ./install.sh --resume     # Reanudar después de interrupción

REQUISITOS:
    - Debian 13.x (Trixie) limpio o derivado basado en Trixie
    - Arquitectura amd64 o arm64
    - Raspberry Pi 4 se detecta automaticamente y pide confirmación para modo legacy
    - Acceso root o sudo
    - Conectividad a internet y acceso DNS/HTTPS a Docker Hub
    - Autodetección:
      standard: 4GB RAM nominales y 20GB libres
      low-resource: 2GB RAM nominales, 4 cores recomendados y 20GB libres
      compact-storage: 2GB RAM nominales, menos de 20GB libres y 5GB libres reales mínimos
    - En compact-storage se pregunta por alertas y modo de purga:
      system, data, both o none.
EOF
}

################################################################################
# Pantalla de Bienvenida
################################################################################
show_welcome() {
    clear
    show_banner "Plataforma IoT con Seguridad Integrada"
    local profile_label autopurge_label alerts_label total_display available_display
    profile_label=$(effective_profile_label)
    autopurge_label=$(autopurge_mode_label)
    alerts_label=$(alerts_mode_label)
    total_display=$(format_storage_mb "${STORAGE_TOTAL_MB:-0}")
    available_display=$(format_storage_mb "${STORAGE_AVAILABLE_MB:-0}")
    
    echo -e "
${BLUE}═══════════════════════════════════════════════════════════════════${RESET}
${BOLD}              SISTEMA DE INSTALACIÓN AUTOMATIZADO v${PLATFORM_VERSION}                   ${RESET}
${BLUE}═══════════════════════════════════════════════════════════════════${RESET}

${YELLOW}ADVERTENCIA - LEE CUIDADOSAMENTE${RESET}

Este script hará:
  • Modificar la configuración del sistema (firewall, SSH, usuarios)
  • Instalar Docker, MySQL, Redis, Nginx y código de aplicación
  • Cambiar el puerto SSH de 22 a un puerto personalizado
  • Eliminar el usuario 'debian' por defecto (al final de la instalación)
  • Configurar seguridad de grado producción (5 capas)

${RED}REQUISITOS CRÍTICOS:${RESET}
  - Debian 13.x/Trixie o derivado basado en Trixie (no sistema de producción)
  - Arquitectura amd64 o arm64
  - Conexión a internet estable
  - Acceso DNS/HTTPS a Docker Hub; el installer intentará reparar DNS común de VM/NAT
  - Perfil detectado: ${profile_label}
  - Almacenamiento detectado: ${total_display} total, ${available_display} libres
  - Alertas de almacenamiento: ${alerts_label}
  - Purga automática: ${autopurge_label}
  - 10 a 20 minutos en standard; en 2GB RAM o compact-storage puede tardar más
  - Acceso a consola local/proveedor (en caso de que SSH falle)

${GREEN}LO QUE OBTENDRÁS:${RESET}
  - Plataforma IoT completa con backend FastAPI
  - 4 tipos de autenticación (Usuario, Admin, Gerente, Dispositivo)
  - Autenticación criptográfica de dispositivos (AES-256 + HMAC)
  - MySQL + Redis activos + MongoDB
  - 5 capas de seguridad (nftables -> Fail2Ban -> Nginx -> FastAPI -> BD)
  - Cero exposición de bases de datos (solo red interna Docker)

${BLUE}═══════════════════════════════════════════════════════════════════${RESET}
"

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${CYAN}║  MODO DRY-RUN ACTIVO - No se harán cambios al sistema   ║${RESET}"
        echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${RESET}"
        echo ""
    fi
}

################################################################################
# Menú Principal
################################################################################
show_main_menu() {
    echo ""
    echo -e "${BOLD}Selecciona una opción:${RESET}"
    echo ""
    echo -e "  ${GREEN}1)${RESET} Iniciar Instalación ${RED}(modificará tu sistema)${RESET}"
    echo -e "  ${CYAN}2)${RESET} Dry-Run ${CYAN}(solo vista previa, sin cambios)${RESET}"
    echo -e "  ${YELLOW}3)${RESET} Reanudar desde punto de control"
    echo -e "  ${RED}4)${RESET} Salir"
    echo ""
    echo -e "  ${YELLOW}CONSEJO:${RESET} Usa la bandera ${CYAN}--dry-run${RESET} para omitir este menú."
    echo ""
    
    local choice
    read -p "Ingresa tu elección [1-4]: " choice
    
    case $choice in
        1)
            echo ""
            echo -e "${YELLOW}Estás a punto de iniciar una instalación REAL.${RESET}"
            echo -e "${YELLOW}   Esto modificará la configuración de tu sistema.${RESET}"
            read -p "¿Estás seguro? [s/N]: " confirm_install
            if ! is_yes "$confirm_install"; then
                log_info "Instalación cancelada"
                show_main_menu
                return
            fi
            DRY_RUN=false
            return 0
            ;;
        2)
            DRY_RUN=true
            log_info "Entrando en modo dry-run (no se harán cambios)..."
            return 0
            ;;
        3)
            if [[ ! -f "$INSTALL_STATE_FILE" ]]; then
                log_error "No se encontró punto de control. No se puede reanudar."
                log_error "Inicia una nueva instalación en su lugar."
                exit 1
            fi
            RESUME_MODE=true
            return 0
            ;;
        4)
            log_info "Instalación cancelada por el usuario"
            exit 0
            ;;
        *)
            log_error "Opción inválida"
            show_main_menu
            ;;
    esac
}

################################################################################
# Recolectar Datos del Usuario
################################################################################
collect_user_inputs() {
    log_info "Recolectando parámetros de configuración..."
    echo ""
    
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║${RESET}  ${BOLD}INFORMACIÓN IMPORTANTE${RESET}                                            ${CYAN}║${RESET}"
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════════════════╣${RESET}"
    echo -e "${CYAN}║${RESET}                                                                        ${CYAN}║${RESET}"
    echo -e "${CYAN}║${RESET}  Los valores entre ${YELLOW}[corchetes]${RESET} son los valores por defecto o         ${CYAN}║${RESET}"
    echo -e "${CYAN}║${RESET}  auto-detectados por el sistema.                                       ${CYAN}║${RESET}"
    echo -e "${CYAN}║${RESET}                                                                        ${CYAN}║${RESET}"
    echo -e "${CYAN}║${RESET}  ${GREEN}Si deseas usar el valor por defecto: solo presiona ENTER${RESET}         ${CYAN}║${RESET}"
    echo -e "${CYAN}║${RESET}  ${GREEN}Si deseas cambiar el valor: escribe el nuevo valor y ENTER${RESET}       ${CYAN}║${RESET}"
    echo -e "${CYAN}║${RESET}                                                                        ${CYAN}║${RESET}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    
    # Auto-detectar IP actual
    local detected_ip
    detected_ip=$(hostname -I | awk '{print $1}')
    
    # Dirección IP del servidor
    read -p "Dirección IP del servidor [${detected_ip}]: " VPS_IP
    VPS_IP=${VPS_IP:-$detected_ip}
    validate_ip "$VPS_IP" || { log_error "Dirección IP inválida"; exit 1; }
    
    # Nuevo nombre de usuario
    read -p "Nuevo nombre de usuario (reemplazará debian/root) [iotadmin]: " NEW_USERNAME
    NEW_USERNAME=${NEW_USERNAME:-iotadmin}
    validate_username "$NEW_USERNAME" || { log_error "Nombre de usuario inválido"; exit 1; }
    
    # Puerto SSH
    read -p "Puerto SSH [5259]: " SSH_PORT
    SSH_PORT=${SSH_PORT:-5259}
    validate_port "$SSH_PORT" || { log_error "Puerto inválido"; exit 1; }
    
    # Dominio (opcional)
    read -p "Nombre de dominio (opcional, para SSL futuro) [ninguno]: " DOMAIN
    DOMAIN=${DOMAIN:-none}
    
    # Nombre de base de datos MySQL
    read -p "Nombre de base de datos MySQL [iot_platform]: " DB_NAME
    DB_NAME=${DB_NAME:-iot_platform}
    validate_db_name "$DB_NAME" || { log_error "Nombre de base de datos inválido"; exit 1; }
    
    # Subred Docker
    read -p "Subred de red Docker [172.20.0.0/16]: " DOCKER_SUBNET
    DOCKER_SUBNET=${DOCKER_SUBNET:-172.20.0.0/16}
    validate_subnet "$DOCKER_SUBNET" || { log_error "Subred inválida"; exit 1; }
    
    # Límite de memoria Redis
    resolve_installation_profiles || { log_error "No se pudo detectar el perfil de recursos"; exit 1; }
    validate_resource_profile "$RESOURCE_PROFILE" || { log_error "Perfil de recursos inválido"; exit 1; }

    echo ""
    local profile_label total_display available_display
    profile_label=$(effective_profile_label)
    total_display=$(format_storage_mb "${STORAGE_TOTAL_MB:-$(storage_total_mb)}")
    available_display=$(format_storage_mb "${STORAGE_AVAILABLE_MB:-$(storage_available_mb)}")
    echo -e "${YELLOW}Perfil detectado:${RESET} ${profile_label}"
    echo -e "${YELLOW}Almacenamiento detectado:${RESET} ${total_display} total, ${available_display} libres"
    if is_low_resource_profile; then
        log_warning "2GB RAM nominales es válido para laboratorio/carga IoT liviana, pero puede sentirse más lento."
    fi
    if is_compact_storage; then
        log_warning "Compact-storage permite hosts con poco espacio libre, pero el espacio se puede agotar rápido."
    fi
    echo ""
    echo "Alertas y purga de almacenamiento:"
    echo "  - Las alertas avisan cuando el disco cruza umbrales de riesgo."
    echo "  - La purga es una decisión separada: puedes purgar sistema, datos, ambos o nada."
    read -p "¿Activar alertas de almacenamiento por SSH/logs? [S/n]: " STORAGE_ALERTS_CONFIRM
    if [[ -z "${STORAGE_ALERTS_CONFIRM:-}" ]] || is_yes "$STORAGE_ALERTS_CONFIRM"; then
        STORAGE_ALERTS=true
    else
        STORAGE_ALERTS=false
    fi
    STORAGE_ALERTS_SOURCE="manual"

    echo ""
    echo "Modo de purga automática cuando el disco esté alto:"
    echo "  1) system: logs, caches Docker, imágenes colgantes y contenedores detenidos"
    echo "  2) data: datos históricos de MongoDB y MySQL según retención"
    echo "  3) both: system + data"
    echo "  4) none: no purgar automáticamente"
    read -p "Elige modo de purga [4]: " STORAGE_PURGE_CHOICE
    case "${STORAGE_PURGE_CHOICE:-4}" in
        1)
            STORAGE_PURGE_MODE="system"
            ;;
        2)
            STORAGE_PURGE_MODE="data"
            ;;
        3)
            STORAGE_PURGE_MODE="both"
            ;;
        4)
            STORAGE_PURGE_MODE="none"
            ;;
        *)
            log_error "Opción de purga inválida"
            exit 1
            ;;
    esac
    STORAGE_PURGE_MODE_SOURCE="manual"
    validate_storage_purge_mode "$STORAGE_PURGE_MODE" || exit 1

    if [[ "$STORAGE_PURGE_MODE" == "system" || "$STORAGE_PURGE_MODE" == "both" ]]; then
        SAFE_AUTOPURGE=true
    else
        SAFE_AUTOPURGE=false
    fi
    SAFE_AUTOPURGE_SOURCE="derived"

    if [[ "$STORAGE_PURGE_MODE" == "data" || "$STORAGE_PURGE_MODE" == "both" ]]; then
        local retention_default
        retention_default=$(default_data_retention_days_for_profile)
        echo ""
        log_warning "La purga de datos elimina datos históricos, no credenciales ni identidades."
        log_warning "MongoDB: sensor_readings, device_logs y alerts por timestamp."
        log_warning "MySQL: historial relacional antiguo y servicios cerrados; no usuarios, admins, dispositivos, roles ni passwords."
        read -p "Días de retención para purga de datos [${retention_default}]: " DATA_RETENTION_DAYS
        DATA_RETENTION_DAYS=${DATA_RETENTION_DAYS:-$retention_default}
        validate_retention_days "$DATA_RETENTION_DAYS" || exit 1
    else
        DATA_RETENTION_DAYS=$(default_data_retention_days_for_profile)
    fi

    local redis_default
    redis_default=$(default_redis_memory_for_profile)
    read -p "Límite de memoria Redis [${redis_default}]: " REDIS_MEMORY
    REDIS_MEMORY=${REDIS_MEMORY:-$redis_default}
    REDIS_MEMORY=$(printf '%s' "$REDIS_MEMORY" | tr '[:upper:]' '[:lower:]')
    validate_redis_memory "$REDIS_MEMORY" || { log_error "Límite Redis inválido"; exit 1; }

    MONGO_IMAGE=$(select_mongo_image)
    if [[ "$MONGO_IMAGE" == "$LEGACY_PI4_MONGO_IMAGE" ]]; then
        echo ""
        log_warning "Raspberry Pi 4 legacy mode activo."
        log_warning "Se usara ${MONGO_IMAGE}. MongoDB 4.4 esta EOL desde 2024-02-29."
        log_warning "No uses este modo para producción ni exposición pública."
    fi
    
    # Zona horaria (auto-detectar)
    local detected_tz
    detected_tz=$(timedatectl show -p Timezone --value 2>/dev/null || echo "UTC")
    read -p "Zona horaria [${detected_tz}]: " TIMEZONE
    TIMEZONE=${TIMEZONE:-$detected_tz}
    validate_timezone "$TIMEZONE" || { log_error "Zona horaria inválida"; exit 1; }
    
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║${RESET}  ${BOLD}CREDENCIALES DEL ADMINISTRADOR PRINCIPAL${RESET}                         ${CYAN}║${RESET}"
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════════════════╣${RESET}"
    echo -e "${CYAN}║${RESET}                                                                        ${CYAN}║${RESET}"
    echo -e "${CYAN}║${RESET}  Configura el correo y contraseña para el administrador principal.     ${CYAN}║${RESET}"
    echo -e "${CYAN}║${RESET}  Este usuario tendrá ${YELLOW}TODOS los permisos${RESET} del sistema.                 ${CYAN}║${RESET}"
    echo -e "${CYAN}║${RESET}                                                                        ${CYAN}║${RESET}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    
    # Email del administrador
    while true; do
        read -p "Correo del administrador [admin@example.com]: " ADMIN_EMAIL
        ADMIN_EMAIL=${ADMIN_EMAIL:-admin@example.com}
        if validate_email "$ADMIN_EMAIL"; then
            break
        fi
        log_warning "Por favor ingresa un correo electrónico válido"
    done
    
    # Contraseña del administrador
    while true; do
        read -sp "Contraseña del administrador (mín. 8 caracteres): " ADMIN_PASSWORD
        echo ""
        if validate_password "$ADMIN_PASSWORD" 8; then
            read -sp "Confirma la contraseña: " ADMIN_PASSWORD_CONFIRM
            echo ""
            if [[ "$ADMIN_PASSWORD" == "$ADMIN_PASSWORD_CONFIRM" ]]; then
                break
            else
                log_error "Las contraseñas no coinciden"
            fi
        fi
    done
    
    echo ""
    log_success "Configuración recolectada"
}

################################################################################
# Generar Resumen de Configuración
################################################################################
show_configuration_summary() {
    echo ""
    show_section_header "Resumen de Configuración"
    local profile_label autopurge_label alerts_label total_display available_display
    profile_label=$(effective_profile_label)
    autopurge_label=$(autopurge_mode_label)
    alerts_label=$(alerts_mode_label)
    total_display=$(format_storage_mb "${STORAGE_TOTAL_MB:-$(storage_total_mb)}")
    available_display=$(format_storage_mb "${STORAGE_AVAILABLE_MB:-$(storage_available_mb)}")
    
    echo -e "
${BOLD}Configuración del Sistema:${RESET}
  IP del Servidor:   ${GREEN}${VPS_IP}${RESET}
  Nuevo Usuario:     ${GREEN}${NEW_USERNAME}${RESET}
  Puerto SSH:        ${GREEN}${SSH_PORT}${RESET}
  Dominio:           ${GREEN}${DOMAIN}${RESET}
  Zona Horaria:      ${GREEN}${TIMEZONE}${RESET}
  Perfil Detectado:  ${GREEN}${profile_label}${RESET}
  Compact Storage:   ${GREEN}${COMPACT_STORAGE}${RESET}
  Almacenamiento:    ${GREEN}${total_display} total, ${available_display} libres${RESET}
  Alertas Storage:   ${GREEN}${alerts_label}${RESET}
  Modo de Purga:     ${GREEN}${autopurge_label}${RESET}
  Retención Datos:   ${GREEN}${DATA_RETENTION_DAYS} días${RESET}

${BOLD}Configuración de Base de Datos:${RESET}
  Nombre de BD:      ${GREEN}${DB_NAME}${RESET}
  Subred Docker:     ${GREEN}${DOCKER_SUBNET}${RESET}
  Memoria Redis:     ${GREEN}${REDIS_MEMORY}${RESET}
  Imagen MongoDB:    ${GREEN}${MONGO_IMAGE:-$DEFAULT_MONGO_IMAGE}${RESET}

${BOLD}Administrador Principal:${RESET}
  Email:             ${GREEN}${ADMIN_EMAIL}${RESET}
  Contraseña:        ${CYAN}[configurada]${RESET}

${BOLD}Secretos de Instalación:${RESET}
  Contraseña Root MySQL:   ${CYAN}[generada]${RESET}
  Contraseña Usuario MySQL: ${CYAN}[generada]${RESET}
  Contraseña Redis:         ${CYAN}[generada]${RESET}
  Clave Secreta JWT:        ${CYAN}[generada]${RESET}
  
${YELLOW}Los secretos se guardarán en: ${SECRETS_FILE}${RESET}
${YELLOW}¡DEBES respaldar este archivo después de la instalación!${RESET}
"

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${CYAN}En dry-run no se generará ni escribirá el archivo de secretos.${RESET}"
        echo ""
    fi

    if is_low_resource_profile; then
        log_warning "Perfil 2GB RAM: instalación soportada para laboratorio/carga liviana; espera menor margen y posible lentitud."
    fi
    if is_compact_storage; then
        log_warning "Compact-storage: el host tiene almacenamiento pequeño; vigila retención de datos y crecimiento de Docker."
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${CYAN}═══ MODO DRY-RUN: No se harán cambios ═══${RESET}"
        echo ""
    fi
    
    read -p "¿Proceder con la instalación? [s/N]: " confirm
    if ! is_yes "$confirm"; then
        log_info "Instalación cancelada"
        exit 0
    fi
}

################################################################################
# Guardar Configuración
################################################################################
save_configuration() {
    log_info "Guardando configuración..."
    
    # Guardar tiempo de inicio para cálculo correcto de duración
    local start_time
    start_time=$(date +%s)
    
    # Escapar caracteres especiales en contraseña para evitar inyección
    # Escapa: \ → \\, " → \", $ → \$, ` → \`
    local escaped_password
    escaped_password=$(escape_double_quoted_value "$ADMIN_PASSWORD")

    MONGO_IMAGE=${MONGO_IMAGE:-$(select_mongo_image)}
    SAFE_AUTOPURGE=${SAFE_AUTOPURGE:-false}
    if [[ "$SAFE_AUTOPURGE" == "auto" ]]; then
        SAFE_AUTOPURGE=false
    fi
    STORAGE_ALERTS=${STORAGE_ALERTS:-true}
    STORAGE_PURGE_MODE=${STORAGE_PURGE_MODE:-none}
    DATA_RETENTION_DAYS=${DATA_RETENTION_DAYS:-$(default_data_retention_days_for_profile)}
    validate_storage_purge_mode "$STORAGE_PURGE_MODE" || exit 1
    validate_retention_days "$DATA_RETENTION_DAYS" || exit 1
    STORAGE_TOTAL_MB=${STORAGE_TOTAL_MB:-$(storage_total_mb)}
    STORAGE_USED_MB=${STORAGE_USED_MB:-$(storage_used_mb)}
    STORAGE_AVAILABLE_MB=${STORAGE_AVAILABLE_MB:-$(storage_available_mb)}
    
    cat > "$CONFIG_FILE" << EOF
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
MONGO_IMAGE="$MONGO_IMAGE"
ALLOW_LEGACY_PI4_MONGODB="$ALLOW_LEGACY_PI4_MONGODB"
RESOURCE_PROFILE="$RESOURCE_PROFILE"
RESOURCE_PROFILE_SOURCE="$RESOURCE_PROFILE_SOURCE"
COMPACT_STORAGE="$COMPACT_STORAGE"
COMPACT_STORAGE_SOURCE="$COMPACT_STORAGE_SOURCE"
SAFE_AUTOPURGE="$SAFE_AUTOPURGE"
SAFE_AUTOPURGE_SOURCE="$SAFE_AUTOPURGE_SOURCE"
STORAGE_ALERTS="$STORAGE_ALERTS"
STORAGE_ALERTS_SOURCE="$STORAGE_ALERTS_SOURCE"
STORAGE_PURGE_MODE="$STORAGE_PURGE_MODE"
STORAGE_PURGE_MODE_SOURCE="$STORAGE_PURGE_MODE_SOURCE"
DATA_RETENTION_DAYS="$DATA_RETENTION_DAYS"
STORAGE_TOTAL_MB="$STORAGE_TOTAL_MB"
STORAGE_USED_MB="$STORAGE_USED_MB"
STORAGE_AVAILABLE_MB="$STORAGE_AVAILABLE_MB"

# Credenciales de Administrador
ADMIN_EMAIL="$ADMIN_EMAIL"
ADMIN_PASSWORD="$escaped_password"

# Tiempo de inicio para cálculo de duración
INSTALL_START_TIME="$start_time"
EOF
    
    chmod 600 "$CONFIG_FILE"
    log_success "Configuración guardada en $CONFIG_FILE"
}

################################################################################
# Ejecutar Instalación
################################################################################
execute_installation() {
    local start_phase=0
    
    # Si es continuación interna via runuser, comenzar desde fase 2
    if [[ "$INTERNAL_RESUME" == true ]]; then
        start_phase=2
        log_info "Continuación automática desde Fase 2 (como ${USER})"
        # Cargar configuración
        if [[ -f "$CONFIG_FILE" ]]; then
            source "$CONFIG_FILE"
            resolve_installation_profiles || exit 1
        else
            log_error "Archivo de configuración no encontrado"
            exit 1
        fi
    # Cargar punto de control si está reanudando manualmente
    elif [[ "$RESUME_MODE" == true ]] && [[ -f "$INSTALL_STATE_FILE" ]]; then
        source "$INSTALL_STATE_FILE"
        start_phase=$((LAST_COMPLETED_PHASE + 1))
        log_info "Reanudando desde la Fase $start_phase"
    fi

    local profile_label autopurge_label alerts_label total_display available_display
    profile_label=$(effective_profile_label)
    autopurge_label=$(autopurge_mode_label)
    alerts_label=$(alerts_mode_label)
    total_display=$(format_storage_mb "${STORAGE_TOTAL_MB:-$(storage_total_mb)}")
    available_display=$(format_storage_mb "${STORAGE_AVAILABLE_MB:-$(storage_available_mb)}")
    
    # Mostrar plan de instalación
    show_section_header "Plan de Instalación"
    echo "
Total de fases: 14 (FASE 0 - FASE 13)
Tiempo estimado: 10 a 20 minutos en standard; low-resource o compact-storage puede tardar más
Iniciando desde: Fase $start_phase
Perfil detectado: ${profile_label}
Compact storage: ${COMPACT_STORAGE}
Almacenamiento: ${total_display} total, ${available_display} libres
Alertas storage: ${alerts_label}
Modo de purga: ${autopurge_label}
Retención datos: ${DATA_RETENTION_DAYS:-$(default_data_retention_days_for_profile)} días
"
    
    # Generar secretos si no existen
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] No se generarán ni escribirán secretos"
    elif [[ ! -f "$SECRETS_FILE" ]]; then
        generate_all_secrets
    fi
    
    # Lista de funciones de fase actualizada (14 fases: 0-13)
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
        "phase_13_cleanup"
    )
    
    # Ejecutar fases
    for i in "${!phases[@]}"; do
        if [[ $i -lt $start_phase ]]; then
            continue
        fi
        
        show_phase_header $i 14 "${phases[$i]}"
        
        if [[ "$DRY_RUN" == true ]]; then
            log_info "[DRY-RUN] Omitiendo ${phases[$i]}"
        else
            ${phases[$i]}
            
            # Si phase_1 retornó código especial 42, significa que hizo exec runuser
            # y este código nunca se ejecutará (el proceso fue reemplazado)
        fi
        
        # Guardar punto de control
        if [[ "$DRY_RUN" != true ]]; then
            echo "LAST_COMPLETED_PHASE=$i" > "$INSTALL_STATE_FILE"
            echo "TIMESTAMP=$(date +%s)" >> "$INSTALL_STATE_FILE"
            log_info "Punto de control guardado (Fase $i)"
        fi
        
        echo ""
        echo -e "${GREEN}Fase $i completada exitosamente${RESET}"
        echo ""
    done
    
    # Mostrar mensaje de finalización
    if [[ "$DRY_RUN" == true ]]; then
        show_dry_run_plan
    else
        show_completion_message
    fi
}

################################################################################
# Mensaje de Finalización
################################################################################
show_completion_message() {
    source "$CONFIG_FILE"
    
    local duration
    duration=$(calculate_duration)
    local profile_label autopurge_label alerts_label total_display available_display summary_file
    local final_total_mb final_available_mb
    profile_label=$(effective_profile_label)
    autopurge_label=$(autopurge_mode_label)
    alerts_label=$(alerts_mode_label)
    final_total_mb=$(storage_total_mb 2>/dev/null || echo "${STORAGE_TOTAL_MB:-0}")
    final_available_mb=$(storage_available_mb 2>/dev/null || echo "${STORAGE_AVAILABLE_MB:-0}")
    [[ "$final_total_mb" =~ ^[0-9]+$ ]] || final_total_mb="${STORAGE_TOTAL_MB:-0}"
    [[ "$final_available_mb" =~ ^[0-9]+$ ]] || final_available_mb="${STORAGE_AVAILABLE_MB:-0}"
    total_display=$(format_storage_mb "$final_total_mb")
    available_display=$(format_storage_mb "$final_available_mb")
    summary_file="${INSTALL_DIR:-$SCRIPT_DIR}/INSTALLATION-SUMMARY.txt"

    if [[ -d "${INSTALL_DIR:-}" ]]; then
        cat > "$summary_file" << SUMMARYEOF
Auto-IoTServer v${PLATFORM_VERSION} - Resumen de instalación
Fecha: $(date -Iseconds)

Estado: EXITO
Duración total: $duration
Fases completadas: 14 de 14
Perfil detectado: $profile_label
Compact storage: $COMPACT_STORAGE
  Almacenamiento actual: $total_display total, $available_display libres
Alertas storage: $alerts_label
Modo de purga: $autopurge_label
Retención datos: ${DATA_RETENTION_DAYS:-N/A} días

SSH:
ssh ${NEW_USERNAME}@${VPS_IP} -p ${SSH_PORT}

API:
Base: http://${VPS_IP}/api/v1
Health: http://${VPS_IP}/health

Secretos:
$SECRETS_FILE

Administrador:
Email: ${ADMIN_EMAIL}
Contraseña: la que configuraste durante la instalación.

Post-instalación recomendada:
1. Respaldar el archivo de secretos.
2. Cambiar la contraseña del usuario ${NEW_USERNAME}.
3. Eliminar usuarios de prueba si esto no es laboratorio.
4. Configurar SSL/TLS antes de producción.
5. Verificar que los contenedores sigan healthy tras reboot.

Log de instalación:
$LOG_FILE
SUMMARYEOF
        chown "$NEW_USERNAME:$NEW_USERNAME" "$summary_file" 2>/dev/null || true
        chmod 600 "$summary_file" 2>/dev/null || true
    fi
    
    show_banner "Plataforma IoT con Seguridad Integrada"

    printf '%b\n' "${GREEN}+===================================================================+${RESET}"
    printf '%b\n' "${GREEN}|            INSTALACION COMPLETADA EXITOSAMENTE                    |${RESET}"
    printf '%b\n' "${GREEN}+===================================================================+${RESET}"
    printf '\n'
    printf '  Duracion total:     %s\n' "$duration"
    printf '  Fases completadas:  14 de 14\n'
    printf '  Estado:             EXITO\n'
    printf '  Perfil detectado:   %s\n' "$profile_label"
    printf '  Compact storage:    %s\n' "$COMPACT_STORAGE"
    printf '  Almacenamiento:     %s total, %s libres (actual)\n' "$total_display" "$available_display"
    printf '  Alertas storage:    %s\n' "$alerts_label"
    printf '  Modo de purga:      %s\n' "$autopurge_label"
    printf '  Retencion datos:    %s dias\n' "${DATA_RETENTION_DAYS:-N/A}"
    printf '  Nota recursos:      2GB RAM puede ir mas lento; 8GB total puede agotarse rapido\n'
    printf '\n'
    printf '%b\n' "${YELLOW}+-------------------------------------------------------------------+${RESET}"
    printf '%b\n' "${YELLOW}|  ACCESO Y SECRETOS                                                |${RESET}"
    printf '%b\n' "${YELLOW}+-------------------------------------------------------------------+${RESET}"
    printf '  SSH:        ssh %s@%s -p %s\n' "$NEW_USERNAME" "$VPS_IP" "$SSH_PORT"
    printf '  API:        http://%s/api/v1\n' "$VPS_IP"
    printf '  Health:     http://%s/health\n' "$VPS_IP"
    printf '  Secretos:   %s\n' "$SECRETS_FILE"
    printf '  Resumen:    %s\n' "$summary_file"
    printf '\n'
    printf '%b\n' "${RED}+-------------------------------------------------------------------+${RESET}"
    printf '%b\n' "${RED}|  RESPALDAR SECRETOS                                               |${RESET}"
    printf '%b\n' "${RED}+-------------------------------------------------------------------+${RESET}"
    printf '  Ejecuta:    cat %s\n' "$SECRETS_FILE"
    printf '  Sin ese archivo no podras recuperar las credenciales generadas.\n'
    printf '\n'
    printf '%b\n' "${CYAN}+-------------------------------------------------------------------+${RESET}"
    printf '%b\n' "${CYAN}|  PROXIMOS PASOS                                                   |${RESET}"
    printf '%b\n' "${CYAN}+-------------------------------------------------------------------+${RESET}"
    printf '  1. Cambiar la contrasena del usuario %s.\n' "$NEW_USERNAME"
    printf '  2. Eliminar usuarios de prueba si no es laboratorio.\n'
    printf '  3. Configurar SSL/TLS antes de produccion.\n'
    printf '  4. Verificar tras reboot: docker compose ps y curl -s http://localhost/health.\n'
    printf '  5. Verificar eliminacion de debian: id debian.\n'
    printf '\n'
    printf '  Log de instalacion: %s\n' "$LOG_FILE"
    printf '%b\n' "${GREEN}+===================================================================+${RESET}"
}

################################################################################
# Calcular Duración (Usa INSTALL_START_TIME del config)
################################################################################
calculate_duration() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        
        # Usar INSTALL_START_TIME si existe, sino usar timestamp del state file
        local start_time="${INSTALL_START_TIME:-}"
        
        if [[ -z "$start_time" ]] && [[ -f "$INSTALL_STATE_FILE" ]]; then
            source "$INSTALL_STATE_FILE"
            start_time="${TIMESTAMP:-}"
        fi
        
        if [[ -n "$start_time" ]]; then
            local end_time
            end_time=$(date +%s)
            local duration=$((end_time - start_time))
            
            local hours=$((duration / 3600))
            local minutes=$(((duration % 3600) / 60))
            local seconds=$((duration % 60))
            
            printf "%02d:%02d:%02d" $hours $minutes $seconds
            return
        fi
    fi
    
    echo "N/A"
}

################################################################################
# Ejecución Principal
################################################################################
main() {
    parse_arguments "$@"

    if [[ "$DRY_RUN" == true ]]; then
        LOG_FILE="${TMPDIR:-/tmp}/auto-iotserver-dry-run-$(date +%Y%m%d-%H%M%S).log"
    fi

    mkdir -p "$(dirname "$LOG_FILE")"
    exec > >(tee -a "$LOG_FILE")
    exec 2>&1
    
    preflight_checks
    
    # Si es internal-resume, cargar config y continuar directamente
    if [[ "$INTERNAL_RESUME" == true ]]; then
        if [[ ! -f "$CONFIG_FILE" ]]; then
            log_error "Archivo de configuración no encontrado para continuación interna"
            exit 1
        fi
        log_info "Modo de continuación interna activado"
        source "$CONFIG_FILE"
        execute_installation
        exit 0
    fi
    
    if [[ "$RESUME_MODE" != true ]]; then
        show_welcome
        
        if [[ "$DRY_RUN" == true ]]; then
            log_info "Modo dry-run activado vía bandera --dry-run. Omitiendo menú..."
            echo ""
        else
            show_main_menu
        fi
    fi
    
    if [[ "$RESUME_MODE" == true ]]; then
        if [[ ! -f "$CONFIG_FILE" ]]; then
            log_error "Archivo de configuración no encontrado. No se puede reanudar."
            exit 1
        fi
        log_info "Cargando configuración guardada..."
        [[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"
        resolve_installation_profiles || exit 1
        validate_resource_profile "$RESOURCE_PROFILE" || exit 1
    else
        collect_user_inputs
        show_configuration_summary
        
        if [[ "$DRY_RUN" != true ]]; then
            save_configuration
        else
            log_info "[DRY-RUN] No se guardará .config.env ni se escribirán secretos"
        fi
    fi
    
    execute_installation
}

main "$@"
