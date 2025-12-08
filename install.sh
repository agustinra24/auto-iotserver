#!/bin/bash
################################################################################
# Plataforma IoT de Prevención de Incendios - Instalador Automatizado v2.0
# 
# Descripción: Script de instalación interactivo para configuración completa
# Requisitos: Debian 13 (Trixie) limpio, acceso root/sudo
# Ejecución: sudo ./install.sh [--dry-run] [--resume]
#
# Autor: Basado en GUIA_DEFINITIVA_2.0_COMPLETA.md
# Fecha: 2024-11-26
################################################################################

set -euo pipefail  # Salir en error, variables indefinidas, fallos en pipes

# Directorio del script (ruta absoluta)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cargar bibliotecas
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/ui.sh"
source "${SCRIPT_DIR}/lib/validation.sh"
source "${SCRIPT_DIR}/lib/secrets.sh"
source "${SCRIPT_DIR}/lib/phases.sh"

# Variables globales
INSTALL_STATE_FILE="${SCRIPT_DIR}/.install-state"
CONFIG_FILE="${SCRIPT_DIR}/.config.env"
SECRETS_FILE="${HOME}/.iot-platform/.secrets"
LOG_FILE="${SCRIPT_DIR}/logs/install-$(date +%Y%m%d-%H%M%S).log"
DRY_RUN=false
RESUME_MODE=false

################################################################################
# Verificaciones Previas
################################################################################
preflight_checks() {
    log_info "Ejecutando verificaciones previas..."
    
    # Verificar si se ejecuta como root o con sudo
    if [[ $EUID -ne 0 ]]; then
        log_error "Este script debe ejecutarse como root o con sudo"
        log_error "Uso: sudo ./install.sh"
        exit 1
    fi
    
    # Verificar versión del sistema operativo
    if [[ ! -f /etc/debian_version ]]; then
        log_error "Este script requiere Debian Linux"
        exit 1
    fi
    
    local debian_version=$(cat /etc/debian_version | cut -d. -f1)
    if [[ "$debian_version" != "13" ]] && [[ "$debian_version" != "trixie"* ]]; then
        log_warning "Este script está diseñado para Debian 13 (Trixie)"
        log_warning "Tu versión: $(cat /etc/debian_version)"
        read -p "¿Continuar de todos modos? [s/N]: " confirm
        [[ "$confirm" != "s" ]] && exit 1
    fi
    
    # Verificar comandos requeridos
    local required_cmds=("git" "curl" "openssl" "bc")
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Comando requerido no encontrado: $cmd"
            log_error "Por favor instala: apt-get update && apt-get install -y $cmd"
            exit 1
        fi
    done
    
    # Verificar conectividad a internet
    if ! curl -s --max-time 5 https://google.com > /dev/null 2>&1; then
        log_error "No se detectó conectividad a internet"
        log_error "Este script requiere acceso a internet para descargar paquetes"
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
Plataforma IoT de Prevención de Incendios - Instalador Automatizado v2.0

USO:
    sudo ./install.sh [OPCIONES]

OPCIONES:
    --dry-run       Vista previa de los pasos de instalación sin ejecutar cambios.
                    Cuando se usa esta bandera, el menú interactivo se omite
                    y el script procede directamente a mostrar el plan de instalación.
    --resume        Reanudar desde el último punto de control exitoso
    -h, --help      Mostrar este mensaje de ayuda

EJEMPLOS:
    # Instalación normal (muestra menú interactivo)
    sudo ./install.sh

    # Vista previa de pasos de instalación (omite menú, sin cambios al sistema)
    sudo ./install.sh --dry-run

    # Reanudar después de interrupción
    sudo ./install.sh --resume

REQUISITOS:
    - VPS Debian 13 (Trixie) limpio
    - Acceso root o sudo
    - Conectividad a internet
    - Mínimo 4GB RAM, 20GB disco

Para documentación completa, consulta README.md
EOF
}

################################################################################
# Pantalla de Bienvenida
################################################################################
show_welcome() {
    clear
    show_banner "Plataforma IoT de Prevención de Incendios"
    
    echo -e "
${BLUE}═══════════════════════════════════════════════════════════════════${RESET}
${BOLD}              SISTEMA DE INSTALACIÓN AUTOMATIZADO v2.0                   ${RESET}
${BLUE}═══════════════════════════════════════════════════════════════════${RESET}

${YELLOW}ADVERTENCIA - LEE CUIDADOSAMENTE${RESET}

Este script hará:
  • Modificar la configuración del sistema (firewall, SSH, usuarios)
  • Instalar Docker, MySQL, Redis, Nginx y código de aplicación
  • Cambiar el puerto SSH de 22 a un puerto personalizado
  • Eliminar el usuario 'debian' por defecto (si existe)
  • Configurar seguridad de grado producción (5 capas)

${RED}REQUISITOS CRÍTICOS:${RESET}
  - VPS Debian 13 limpio (no sistema de producción)
  - Conexión a internet estable
  - ~3-4 horas de tiempo dedicado
  - Acceso a consola VPS (en caso de que SSH falle)

${GREEN}LO QUE OBTENDRÁS:${RESET}
  - Plataforma IoT completa con backend FastAPI
  - 4 tipos de autenticación (Usuario, Admin, Gerente, Dispositivo)
  - Autenticación criptográfica de dispositivos (AES-256 + HMAC)
  - MySQL + Redis activos, MongoDB reservado para futuro
  - 5 capas de seguridad (nftables -> Fail2Ban -> Nginx -> FastAPI -> BD)
  - Cero exposición de bases de datos (solo red interna Docker)
  - Aplicación de sesión única por usuario

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
    echo -e "  ${YELLOW}CONSEJO:${RESET} Usa la bandera ${CYAN}--dry-run${RESET} para omitir este menú y ver vista previa directamente."
    echo ""
    
    local choice
    read -p "Ingresa tu elección [1-4]: " choice
    
    case $choice in
        1)
            # Confirmar instalación real
            echo ""
            echo -e "${YELLOW}Estás a punto de iniciar una instalación REAL.${RESET}"
            echo -e "${YELLOW}   Esto modificará la configuración de tu sistema.${RESET}"
            read -p "¿Estás seguro? [s/N]: " confirm_install
            if [[ "$confirm_install" != "s" && "$confirm_install" != "S" ]]; then
                log_info "Instalación cancelada"
                show_main_menu
                return
            fi
            DRY_RUN=false  # Establecer explícitamente en false para instalación real
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
    
    # Mensaje informativo sobre valores por defecto
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
    local detected_ip=$(hostname -I | awk '{print $1}')
    
    # Dirección IP del VPS
    read -p "Dirección IP del VPS [${detected_ip}]: " VPS_IP
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
    read -p "Límite de memoria Redis [256MB]: " REDIS_MEMORY
    REDIS_MEMORY=${REDIS_MEMORY:-256MB}
    
    # Zona horaria (auto-detectar)
    local detected_tz=$(timedatectl show -p Timezone --value 2>/dev/null || echo "UTC")
    read -p "Zona horaria [${detected_tz}]: " TIMEZONE
    TIMEZONE=${TIMEZONE:-$detected_tz}
    
    echo ""
    log_success "Configuración recolectada"
}

################################################################################
# Generar Resumen de Configuración
################################################################################
show_configuration_summary() {
    echo ""
    show_section_header "Resumen de Configuración"
    
    echo -e "
${BOLD}Configuración del Sistema:${RESET}
  IP del VPS:        ${GREEN}${VPS_IP}${RESET}
  Nuevo Usuario:     ${GREEN}${NEW_USERNAME}${RESET}
  Puerto SSH:        ${GREEN}${SSH_PORT}${RESET}
  Dominio:           ${GREEN}${DOMAIN}${RESET}
  Zona Horaria:      ${GREEN}${TIMEZONE}${RESET}

${BOLD}Configuración de Base de Datos:${RESET}
  Nombre de BD:      ${GREEN}${DB_NAME}${RESET}
  Subred Docker:     ${GREEN}${DOCKER_SUBNET}${RESET}
  Memoria Redis:     ${GREEN}${REDIS_MEMORY}${RESET}

${BOLD}Secretos Auto-Generados:${RESET}
  Contraseña Root MySQL:   ${CYAN}[generada]${RESET}
  Contraseña Usuario MySQL: ${CYAN}[generada]${RESET}
  Contraseña Redis:         ${CYAN}[generada]${RESET}
  Clave Secreta JWT:        ${CYAN}[generada]${RESET}
  
${YELLOW}Los secretos se guardarán en: ${SECRETS_FILE}${RESET}
${YELLOW}¡DEBES respaldar este archivo después de la instalación!${RESET}
"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${CYAN}═══ MODO DRY-RUN: No se harán cambios ═══${RESET}"
        echo ""
    fi
    
    read -p "¿Proceder con la instalación? [s/N]: " confirm
    if [[ "$confirm" != "s" ]]; then log_info "Instalación cancelada"; exit 0; fi
}

################################################################################
# Guardar Configuración
################################################################################
save_configuration() {
    log_info "Guardando configuración..."
    
    # Crear archivo de configuración
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

# Rutas
INSTALL_DIR="/home/${NEW_USERNAME}/iot-platform"
SCRIPT_DIR="$SCRIPT_DIR"
SECRETS_FILE="$SECRETS_FILE"
EOF
    
    chmod 600 "$CONFIG_FILE"
    log_success "Configuración guardada en $CONFIG_FILE"
}

################################################################################
# Ejecutar Fases de Instalación
################################################################################
execute_installation() {
    local start_phase=0
    
    # Cargar punto de control si se reanuda
    if [[ "$RESUME_MODE" == true ]]; then
        source "$INSTALL_STATE_FILE"
        start_phase=$((LAST_COMPLETED_PHASE + 1))
        log_info "Reanudando desde la Fase $start_phase"
    fi
    
    # Cargar configuración
    [[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"
    
    # Generar secretos si no se reanuda
    if [[ "$start_phase" -eq 0 && "$DRY_RUN" != true ]]; then
        generate_all_secrets
    else
        # Cargar secretos existentes
        mkdir -p "$(dirname "$SECRETS_FILE")"
        [[ -f "$SECRETS_FILE" ]] && source "$SECRETS_FILE"
    fi
    
    # Mostrar plan de instalación
    show_section_header "Plan de Instalación"
    echo ""
    echo "Total de fases: 13 (FASE 0 - FASE 12)"
    echo "Tiempo estimado: ~3 horas 15 minutos"
    echo "Iniciando desde: Fase $start_phase"
    echo ""
    
    if [[ "$DRY_RUN" == true ]]; then
        show_dry_run_plan
        if [[ $? -eq 0 ]]; then
            DRY_RUN=false
        else
            return 0
        fi
    fi
    
    # Ejecutar fases
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
        
        # Ejecutar fase
        $phase_func
        
        # Guardar punto de control
        save_checkpoint "$phase_num"
        
        show_phase_complete "$phase_num"
    done
    
    # Instalación completada
    show_installation_complete
}

################################################################################
# Guardar Punto de Control
################################################################################
save_checkpoint() {
    local phase_num=$1
    
    cat > "$INSTALL_STATE_FILE" << EOF
LAST_COMPLETED_PHASE=$phase_num
TIMESTAMP=$(date +%s)
DATE="$(date)"
EOF
    
    log_info "Punto de control guardado (Fase $phase_num)"
}

################################################################################
# Mostrar Instalación Completada
################################################################################
show_installation_complete() {
    clear
    show_banner "Instalacion Completada"
    
    echo -e "
${GREEN}+===================================================================+
|                                                                   |
|            INSTALACION COMPLETADA EXITOSAMENTE                    |
|                                                                   |
+===================================================================+${RESET}

  Duracion total:     $(calculate_duration)
  Fases completadas:  13 de 13
  Estado:             ${GREEN}EXITO${RESET}


${RED}+-------------------------------------------------------------------+
|  ACCION INMEDIATA REQUERIDA                                       |
+-------------------------------------------------------------------+${RESET}

  El archivo de secretos contiene TODAS las contrasenas generadas.
  Si pierdes este archivo, perderas acceso a la base de datos.

  Ubicacion:  ${BOLD}${SECRETS_FILE}${RESET}

  Ejecuta AHORA para ver y respaldar tus secretos:

    ${CYAN}cat ${SECRETS_FILE}${RESET}

  Guarda este archivo en un lugar seguro fuera del servidor.


${YELLOW}+-------------------------------------------------------------------+
|  CREDENCIALES POR DEFECTO - CAMBIAR INMEDIATAMENTE                |
+-------------------------------------------------------------------+${RESET}

  Las siguientes cuentas de prueba fueron creadas con contrasenas
  temporales. Debes cambiarlas antes de usar el sistema en produccion.

  ${BOLD}Cuenta${RESET}                              ${BOLD}Contrasena temporal${RESET}
  ------------------------------------  --------------------
    admin@iot-platform.com                password123
    user@iot-platform.com                 password123
    manager@iot-platform.com              password123


${BLUE}+-------------------------------------------------------------------+
|  COMO ACCEDER A TU PLATAFORMA                                     |
+-------------------------------------------------------------------+${RESET}

  ${BOLD}Conexion SSH (administracion del servidor):${RESET}

    ssh ${NEW_USERNAME}@${VPS_IP} -p ${SSH_PORT}

  ${BOLD}API REST (integracion de aplicaciones):${RESET}

    Endpoint base:    http://${VPS_IP}/api/v1
    Verificar estado: http://${VPS_IP}/health

  ${BOLD}Probar autenticacion:${RESET}

    curl -X POST http://${VPS_IP}/api/v1/auth/login/admin \\
      -H \"Content-Type: application/json\" \\
      -d '{\"email\":\"admin@iot-platform.com\",\"password\":\"password123\"}'


${CYAN}+-------------------------------------------------------------------+
|  PROXIMOS PASOS RECOMENDADOS                                      |
+-------------------------------------------------------------------+${RESET}

  1. Respaldar el archivo de secretos (ver arriba)
  2. Cambiar las contrasenas por defecto usando la API
  3. Configurar certificado SSL/TLS para conexiones seguras
  4. Configurar sistema de monitoreo y alertas
  5. Revisar y ajustar reglas del firewall segun tus necesidades


${WHITE}+-------------------------------------------------------------------+
|  DOCUMENTACION Y SOPORTE                                          |
+-------------------------------------------------------------------+${RESET}

  Log de instalacion:  ${LOG_FILE}
  Guia completa:       GUIA_DEFINITIVA_2.0_COMPLETA.md


${GREEN}====================================================================${RESET}
${BOLD}          Gracias por usar el instalador de Plataforma IoT          ${RESET}
${GREEN}====================================================================${RESET}
"
}

################################################################################
# Calcular Duración
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
# Ejecución Principal
################################################################################
main() {
    # Configurar logging
    mkdir -p "$(dirname "$LOG_FILE")"
    exec > >(tee -a "$LOG_FILE")
    exec 2>&1
    
    # Procesar argumentos
    parse_arguments "$@"
    
    # Verificaciones previas
    preflight_checks
    
    # Mostrar bienvenida y menú (omitir menú si --dry-run fue pasado por CLI)
    if [[ "$RESUME_MODE" != true ]]; then
        show_welcome
        
        # Si la bandera --dry-run fue pasada, omitir el menú completamente
        if [[ "$DRY_RUN" == true ]]; then
            log_info "Modo dry-run activado vía bandera --dry-run. Omitiendo menú..."
            echo ""
        else
            show_main_menu
        fi
    fi
    
    # Recolectar datos o cargar configuración
    if [[ "$RESUME_MODE" == true ]]; then
        if [[ ! -f "$CONFIG_FILE" ]]; then
            log_error "Archivo de configuración no encontrado. No se puede reanudar."
            exit 1
        fi
        log_info "Cargando configuración guardada..."
        [[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"
    else
        collect_user_inputs
        show_configuration_summary
        [[ "$DRY_RUN" != true ]] && save_configuration
    fi
    
    # Ejecutar instalación
    execute_installation
}

# Ejecutar función principal
main "$@"
