#!/bin/bash
################################################################################
# lib/ui.sh - Funciones de UI y visualización en terminal
################################################################################

# Mostrar banner ASCII
show_banner() {
    local title="${1:-Plataforma IoT}"
    
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
    echo -e "${GREEN}║${RESET}  Fase $phase_num/$total_phases: $friendly_name"
    echo -e "${GREEN}║${RESET}  Progreso: $(show_progress_bar $progress)"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

# Mostrar barra de progreso
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

# Mostrar fase completada
show_phase_complete() {
    local phase_num=$1
    
    echo ""
    echo -e "${GREEN}Fase $phase_num completada exitosamente${RESET}"
    echo ""
    
    # Pequeña pausa para que el usuario vea la finalización
    sleep 1
}

# Mostrar spinner
show_spinner() {
    local pid=$1
    local message="${2:-Procesando...}"
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) %10 ))
        printf "\r${CYAN}${spin:$i:1}${RESET} $message"
        sleep 0.1
    done
    
    printf "\r${GREEN}[OK]${RESET} $message\n"
}

# Mostrar tarea con estado
show_task() {
    local task="$1"
    local status="${2:-running}"
    
    case $status in
        running)
            echo -n -e "  ${CYAN}[...]${RESET} $task..."
            ;;
        success)
            echo -e "\r  ${GREEN}[OK]${RESET} $task"
            ;;
        error)
            echo -e "\r  ${RED}[ERROR]${RESET} $task"
            ;;
        skip)
            echo -e "  ${YELLOW}[SKIP]${RESET} $task (omitido)"
            ;;
    esac
}

# Completar tarea actual
complete_task() {
    local task="$1"
    echo -e "\r  ${GREEN}[OK]${RESET} $task    "
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
    echo -e "${YELLOW}┌─ [ADVERTENCIA] $title ─────────────────────────────────────┐${RESET}"
    for line in "${lines[@]}"; do
        echo -e "${YELLOW}│${RESET} $line"
    done
    echo -e "${YELLOW}└──────────────────────────────────────────────────┘${RESET}"
    echo ""
}

# Mostrar caja de pausa crítica
show_critical_pause() {
    local phase_name="$1"
    shift
    local instructions=("$@")
    
    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${RED}║${RESET}  ${BOLD}VALIDACION CRITICA REQUERIDA - $phase_name${RESET}"
    echo -e "${RED}╠═══════════════════════════════════════════════════════════════════╣${RESET}"
    
    for instruction in "${instructions[@]}"; do
        echo -e "${RED}║${RESET}  $instruction"
    done
    
    echo -e "${RED}╠═══════════════════════════════════════════════════════════════════╣${RESET}"
    echo -e "${RED}║${RESET}  ${YELLOW}Si TODAS las pruebas pasan: Presiona ENTER para continuar${RESET}"
    echo -e "${RED}║${RESET}  ${YELLOW}Si ALGUNA prueba falla: Presiona Ctrl+C para abortar${RESET}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    
    read -p "Presiona ENTER cuando hayas validado: "
}

# Mostrar plan de dry-run
show_dry_run_plan() {
    show_section_header "DRY-RUN: Plan de Instalación"
    
    echo -e "${BOLD}Las siguientes fases serán ejecutadas:${RESET}

${CYAN}[Fase 0]${RESET} Preparación
  • Verificar recursos del sistema
  • Crear directorio de instalación
  • Configurar logging

${CYAN}[Fase 1]${RESET} Gestión de Usuarios ${RED}(REQUIERE VALIDACIÓN)${RESET}
  • Crear nuevo usuario: $NEW_USERNAME
  • Otorgar privilegios sudo
  • ${YELLOW}PAUSA: Validar en segunda terminal${RESET}
  • Eliminar usuario debian

${CYAN}[Fase 2]${RESET} Dependencias Base
  • Actualizar paquetes del sistema
  • Instalar herramientas de compilación, Python, herramientas de red
  • Instalar utilidades de monitoreo

${CYAN}[Fase 3]${RESET} Firewall (nftables)
  • Configurar reglas de nftables
  • Crear conjuntos de IP dinámicos
  • Configurar política DROP con puertos permitidos

${CYAN}[Fase 4]${RESET} Fail2Ban
  • Instalar Fail2Ban
  • Configurar jails para SSH, Nginx
  • Integrar con nftables

${CYAN}[Fase 5]${RESET} Hardening SSH ${RED}(REQUIERE VALIDACIÓN)${RESET}
  • Cambiar puerto SSH: 22 -> $SSH_PORT
  • ${YELLOW}PAUSA: Probar nuevo puerto en segunda terminal${RESET}
  • Deshabilitar login de root
  • Cerrar puerto 22

${CYAN}[Fase 6]${RESET} Instalación de Docker
  • Agregar repositorio de Docker
  • Instalar Docker + Docker Compose
  • Configurar daemon
  • Agregar usuario al grupo docker

${CYAN}[Fase 7]${RESET} Estructura del Proyecto
  • Crear directorio ~/iot-platform
  • Copiar templates
  • Generar archivo .env

${CYAN}[Fase 8]${RESET} Aplicación FastAPI
  • Crear archivos de aplicación (25+ archivos)
  • Copiar modelos, schemas, routers
  • Configurar autenticación criptográfica de dispositivos
  • Construir imagen Docker

${CYAN}[Fase 9]${RESET} Inicialización de MySQL
  • Crear init.sql (14 tablas)
  • Configurar RBAC (roles, permisos)
  • Crear datos de prueba

${CYAN}[Fase 10]${RESET} Configuración de Nginx
  • Configurar proxy reverso
  • Configurar rate limiting
  • Agregar headers de seguridad

${CYAN}[Fase 11]${RESET} Despliegue
  • Desplegar con docker-compose
  • Esperar health checks
  • Verificar que todos los servicios estén corriendo

${CYAN}[Fase 12]${RESET} Pruebas y Validación
  • Probar endpoints de autenticación (4 tipos)
  • Verificar gestión de sesiones
  • Probar rate limiting
  • Validar aislamiento de base de datos

${BOLD}Tiempo Total Estimado:${RESET} ~3 horas 15 minutos

${BOLD}Pausas Críticas:${RESET}
  • Fase 1: Validación de usuario (prueba manual requerida)
  • Fase 5: Validación de puerto SSH (prueba manual requerida)

${BOLD}Secretos Generados:${RESET}
  Todas las contraseñas y claves serán auto-generadas y guardadas en:
  ${SECRETS_FILE}
"

    read -p "¿Proceder con la instalación real? [s/N]: " proceed
    if [[ "$proceed" == "s" ]]; then return 0; else return 1; fi
}

# Mostrar tabla
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

# Mostrar lista de verificación
show_checklist() {
    local title="$1"
    shift
    local items=("$@")
    
    echo ""
    echo -e "${BOLD}$title${RESET}"
    echo ""
    for item in "${items[@]}"; do
        echo -e "  ${GREEN}[ ]${RESET} $item"
    done
    echo ""
}

# Temporizador de cuenta regresiva
countdown() {
    local seconds=$1
    local message="${2:-Esperando...}"
    
    for i in $(seq $seconds -1 1); do
        echo -ne "\r$message ${i}s  "
        sleep 1
    done
    echo -e "\r$message ¡Listo!  "
}

# Confirmar acción
confirm_action() {
    local message="$1"
    local default="${2:-N}"
    
    local prompt
    if [[ "$default" == "Y" ]]; then
        prompt="[S/n]"
    else
        prompt="[s/N]"
    fi
    
    read -p "$message $prompt: " response
    response=${response:-$default}
    
    [[ "$response" =~ ^[SsYy]$ ]]
}
