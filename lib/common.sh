#!/bin/bash
################################################################################
# lib/common.sh - Utilidades comunes y funciones de logging
################################################################################

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
BOLD='\033[1m'
RESET='\033[0m'

# Version de la plataforma (unico punto de cambio para codigo ejecutable)
PLATFORM_VERSION="1.3"

# MongoDB 4.4 is only kept as an explicit Raspberry Pi 4 lab escape hatch.
# It is EOL, so the installer must never select it silently.
DEFAULT_MONGO_IMAGE="mongo:7.0"
LEGACY_PI4_MONGO_IMAGE="mongo:4.4.30-focal"

# Perfiles de recursos. "auto" es el modo normal: el instalador decide desde
# RAM y disco reales; standard/low-resource quedan como overrides avanzados.
AUTO_RESOURCE_PROFILE="auto"
STANDARD_RESOURCE_PROFILE="standard"
LOW_RESOURCE_PROFILE="low-resource"
STANDARD_MIN_RAM_MB=3800
LOW_RESOURCE_MIN_RAM_MB=1800
STANDARD_MIN_DISK_MB=20480
LOW_RESOURCE_MIN_DISK_MB=20480
LOW_RESOURCE_RECOMMENDED_DISK_MB=32768
LOW_RESOURCE_SWAP_TRIGGER_RAM_MB=3072
LOW_RESOURCE_MIN_SWAP_MB=2048
COMPACT_STORAGE_MIN_TOTAL_MB=7000
COMPACT_STORAGE_MIN_AVAILABLE_MB=5120
COMPACT_STORAGE_RECOMMENDED_TOTAL_MB=15360
COMPACT_STORAGE_RECOMMENDED_AVAILABLE_MB=6144
COMPACT_STORAGE_SWAP_MB=1024
STANDARD_DOCKER_LOG_MAX_SIZE="10m"
STANDARD_DOCKER_LOG_MAX_FILE="3"
COMPACT_DOCKER_LOG_MAX_SIZE="5m"
COMPACT_DOCKER_LOG_MAX_FILE="2"
DOCKER_REGISTRY_HOST="registry-1.docker.io"
DOCKER_REGISTRY_URL="https://registry-1.docker.io/v2/"
DOCKER_DNS_PRIMARY="1.1.1.1"
DOCKER_DNS_SECONDARY="8.8.8.8"
STANDARD_HOST_LOG_MAX_SIZE="10M"
STANDARD_HOST_LOG_ROTATE="4"
COMPACT_HOST_LOG_MAX_SIZE="5M"
COMPACT_HOST_LOG_ROTATE="2"
DEFAULT_DATA_RETENTION_DAYS=30
COMPACT_DATA_RETENTION_DAYS=7
APT_LOCK_WAIT_TIMEOUT_SECONDS=600
APT_LOCK_WAIT_INTERVAL_SECONDS=5

# Funciones de logging
log_info() {
    echo -e "${BLUE}[INFO]${RESET} $1"
}

log_success() {
    echo -e "${GREEN}[ÉXITO]${RESET} $1"
}

log_warning() {
    echo -e "${YELLOW}[ADVERTENCIA]${RESET} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${RESET} $1" >&2
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${CYAN}[DEBUG]${RESET} $1"
    fi
}

escape_double_quoted_value() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\$/\\$/g' -e 's/`/\\`/g'
}

restore_sudo_password_requirement() {
    local username="${NEW_USERNAME:-}"
    local sudoers_file

    if [[ -z "$username" || "${DRY_RUN:-false}" == true ]]; then
        return 0
    fi

    sudoers_file="/etc/sudoers.d/$username"
    if [[ ! -f "$sudoers_file" ]]; then
        return 0
    fi

    if ! grep -q "NOPASSWD" "$sudoers_file" 2>/dev/null; then
        return 0
    fi

    if ! printf '%s ALL=(ALL:ALL) ALL\n' "$username" > "$sudoers_file" 2>/dev/null; then
        log_warning "No se pudo restaurar sudo con contraseña para $username"
        return 0
    fi

    chmod 440 "$sudoers_file" 2>/dev/null || true
    if command_exists visudo; then
        visudo -cf "$sudoers_file" >> "${LOG_FILE:-/dev/null}" 2>&1 || true
    fi

    log_warning "Sudo sin contraseña restaurado por seguridad para $username"
}

ensure_docker_user_chain() {
    if ! command_exists iptables; then
        log_warning "iptables no está disponible; no se pudo preparar DOCKER-USER"
        return 0
    fi

    iptables -N DOCKER-USER 2>/dev/null || true
    iptables -C DOCKER-USER -j RETURN 2>/dev/null || iptables -A DOCKER-USER -j RETURN
}

command_uses_apt_or_dpkg() {
    local cmd="$1"

    [[ "$cmd" == *"apt-get"* || "$cmd" == apt\ * || "$cmd" == *" apt "* || "$cmd" == dpkg\ * || "$cmd" == *" dpkg "* ]]
}

apt_dpkg_lock_details() {
    local locks=(
        "/var/lib/dpkg/lock-frontend"
        "/var/lib/dpkg/lock"
        "/var/cache/apt/archives/lock"
        "/var/lib/apt/lists/lock"
    )
    local lock=""
    local pids=""
    local pid=""
    local cmdline=""
    local found=false

    if command_exists fuser; then
        for lock in "${locks[@]}"; do
            [[ -e "$lock" ]] || continue

            pids=$(fuser "$lock" 2>/dev/null | tr -s ' ' '\n' | sed '/^$/d' | sort -u || true)
            [[ -n "$pids" ]] || continue

            while IFS= read -r pid; do
                [[ -n "$pid" ]] || continue
                found=true
                if [[ -r "/proc/$pid/cmdline" ]]; then
                    cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)
                else
                    cmdline=$(ps -p "$pid" -o command= 2>/dev/null || true)
                fi
                printf '%s pid=%s %s\n' "$lock" "$pid" "${cmdline:-comando no disponible}"
            done <<< "$pids"
        done
    else
        pids=$(pgrep -af 'apt-get|apt |dpkg|unattended-upgr' 2>/dev/null || true)
        [[ -n "$pids" ]] || return 1
        found=true
        while IFS= read -r cmdline; do
            [[ -n "$cmdline" ]] || continue
            printf 'proceso apt/dpkg activo: %s\n' "$cmdline"
        done <<< "$pids"
    fi

    [[ "$found" == true ]]
}

wait_for_apt_dpkg_locks() {
    local timeout="${1:-$APT_LOCK_WAIT_TIMEOUT_SECONDS}"
    local interval="${2:-$APT_LOCK_WAIT_INTERVAL_SECONDS}"
    local elapsed=0
    local details=""

    while true; do
        details=$(apt_dpkg_lock_details || true)
        if [[ -z "$details" ]]; then
            return 0
        fi

        if [[ $elapsed -eq 0 ]]; then
            log_warning "APT/DPKG está ocupado; esperando hasta ${timeout}s antes de continuar"
            while IFS= read -r line; do
                [[ -n "$line" ]] && log_info "$line"
            done <<< "$details"
        elif (( elapsed % 30 == 0 )); then
            log_info "APT/DPKG sigue ocupado (${elapsed}s/${timeout}s)"
        fi

        if (( elapsed >= timeout )); then
            log_error "APT/DPKG sigue bloqueado después de ${timeout}s"
            while IFS= read -r line; do
                [[ -n "$line" ]] && log_error "$line"
            done <<< "$details"
            log_error "Espera a que termine el proceso dueño del lock y reanuda con: sudo ./install.sh --resume"
            return 1
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
}

# Ejecutar comando con logging
exec_cmd() {
    local cmd="$1"
    local description="${2:-Ejecutando comando}"

    log_debug "Comando: $cmd"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${CYAN}[DRY-RUN]${RESET} Ejecutaría: $cmd"
        return 0
    fi

    if command_uses_apt_or_dpkg "$cmd"; then
        if ! wait_for_apt_dpkg_locks; then
            return 1
        fi
    fi
    
    if eval "$cmd" >> "$LOG_FILE" 2>&1; then
        log_success "$description"
        return 0
    else
        local exit_code=$?
        log_error "$description falló (código de salida: $exit_code)"
        log_error "Revisar archivo de log: $LOG_FILE"
        return $exit_code
    fi
}

# Manejador de errores
error_handler() {
    local line_num=$1
    log_error "Script falló en la línea $line_num"
    log_error "Último comando omitido para evitar filtrar secretos en logs"
    log_error "Revisar log: $LOG_FILE"
    
    if [[ -n "${CURRENT_PHASE:-}" ]]; then
        log_warning "Instalación interrumpida en la Fase $CURRENT_PHASE"
        log_info "Puedes reanudar después con: sudo ./install.sh --resume"
    fi

    restore_sudo_password_requirement
    
    exit 1
}

trap 'error_handler $LINENO' ERR

command_exists() {
    command -v "$1" &> /dev/null
}

apt_package_candidate() {
    local package="$1"
    apt-cache policy "$package" 2>/dev/null | awk '/Candidate:/ {print $2; exit}'
}

apt_package_available() {
    local package="$1"
    local candidate

    candidate=$(apt_package_candidate "$package")
    [[ -n "$candidate" && "$candidate" != "(none)" ]]
}

docker_dns_json() {
    printf '["%s","%s"]' "$DOCKER_DNS_PRIMARY" "$DOCKER_DNS_SECONDARY"
}

docker_public_resolver_block() {
    cat << DNSBLOCK
# Auto-IoT Installer: DNS público para resolver Docker Hub en redes NAT/VM
nameserver $DOCKER_DNS_PRIMARY
nameserver $DOCKER_DNS_SECONDARY
options timeout:2 attempts:2
DNSBLOCK
}

docker_registry_http_probe() {
    local status

    status=$(curl -sSIL --max-time 15 -o /dev/null -w '%{http_code}' "$DOCKER_REGISTRY_URL" 2>> "${LOG_FILE:-/dev/null}" || true)
    [[ "$status" == "200" || "$status" == "401" ]]
}

docker_registry_host_probe() {
    getent hosts "$DOCKER_REGISTRY_HOST" >/dev/null 2>&1 && docker_registry_http_probe
}

docker_registry_pull_probe() {
    if ! docker pull hello-world:latest >> "${LOG_FILE:-/dev/null}" 2>&1; then
        docker image rm hello-world:latest >> "${LOG_FILE:-/dev/null}" 2>&1 || true
        return 1
    fi

    docker image rm hello-world:latest >> "${LOG_FILE:-/dev/null}" 2>&1 || true
    return 0
}

current_resolv_conf_file() {
    echo "${DNS_RESOLV_CONF_FILE:-/etc/resolv.conf}"
}

current_resolv_conf_head_file() {
    echo "${DNS_RESOLV_CONF_HEAD_FILE:-/etc/resolv.conf.head}"
}

current_systemd_resolved_dropin_dir() {
    echo "${SYSTEMD_RESOLVED_DROPIN_DIR:-/etc/systemd/resolved.conf.d}"
}

default_network_interface() {
    if ! command_exists ip; then
        return 0
    fi

    ip route show default 2>/dev/null | awk 'NR==1 {for (i=1; i<=NF; i++) if ($i == "dev") {print $(i+1); exit}}'
}

active_networkmanager_connection() {
    nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | awk -F: '$2 != "" && $2 != "lo" {print $1; exit}'
}

active_networkmanager_device() {
    nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | awk -F: '$2 != "" && $2 != "lo" {print $2; exit}'
}

dns_manager_type() {
    local resolv_conf
    resolv_conf=$(current_resolv_conf_file)

    if [[ -r "$resolv_conf" ]] && grep -qi 'Generated by dhcpcd' "$resolv_conf"; then
        echo "dhcpcd"
    elif systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        echo "systemd-resolved"
    elif systemctl is-active --quiet NetworkManager 2>/dev/null && command_exists nmcli; then
        echo "networkmanager"
    elif [[ -e "$resolv_conf" && ! -L "$resolv_conf" ]]; then
        echo "plain"
    else
        echo "unknown"
    fi
}

write_plain_resolv_conf_with_public_dns() {
    local resolv_conf
    resolv_conf=$(current_resolv_conf_file)

    if [[ -e "$resolv_conf" ]]; then
        backup_file "$resolv_conf"
    fi

    docker_public_resolver_block > "$resolv_conf"
}

repair_dhcpcd_dns_for_docker() {
    local resolv_conf resolv_head iface
    resolv_conf=$(current_resolv_conf_file)
    resolv_head=$(current_resolv_conf_head_file)
    iface=$(default_network_interface)

    backup_file "$resolv_head"
    docker_public_resolver_block > "$resolv_head"

    if command_exists dhcpcd && [[ -n "$iface" ]]; then
        dhcpcd -n "$iface" >> "${LOG_FILE:-/dev/null}" 2>&1 || true
    fi

    if ! grep -q "$DOCKER_DNS_PRIMARY" "$resolv_conf" 2>/dev/null; then
        write_plain_resolv_conf_with_public_dns
    fi
}

repair_systemd_resolved_dns_for_docker() {
    local dropin_dir
    dropin_dir=$(current_systemd_resolved_dropin_dir)
    local dropin_file="$dropin_dir/99-iot-platform-docker-registry.conf"

    mkdir -p "$dropin_dir"
    backup_file "$dropin_file"
    cat > "$dropin_file" << RESOLVEDEOF
[Resolve]
DNS=$DOCKER_DNS_PRIMARY $DOCKER_DNS_SECONDARY
FallbackDNS=1.0.0.1 8.8.4.4
RESOLVEDEOF

    systemctl restart systemd-resolved >> "${LOG_FILE:-/dev/null}" 2>&1
}

repair_networkmanager_dns_for_docker() {
    local connection device
    connection=$(active_networkmanager_connection)
    device=$(active_networkmanager_device)

    if [[ -z "$connection" ]]; then
        log_error "NetworkManager está activo, pero no se detectó conexión activa para reparar DNS."
        return 1
    fi

    nmcli connection modify "$connection" ipv4.dns "$DOCKER_DNS_PRIMARY $DOCKER_DNS_SECONDARY" ipv4.ignore-auto-dns yes >> "${LOG_FILE:-/dev/null}" 2>&1
    if [[ -n "$device" ]]; then
        nmcli device reapply "$device" >> "${LOG_FILE:-/dev/null}" 2>&1 || nmcli connection up "$connection" >> "${LOG_FILE:-/dev/null}" 2>&1
    else
        nmcli connection up "$connection" >> "${LOG_FILE:-/dev/null}" 2>&1
    fi
}

repair_plain_dns_for_docker() {
    write_plain_resolv_conf_with_public_dns
}

restart_docker_after_dns_change() {
    systemctl restart docker >> "${LOG_FILE:-/dev/null}" 2>&1
}

print_docker_registry_diagnostics() {
    local manager resolv_conf
    manager=$(dns_manager_type)
    resolv_conf=$(current_resolv_conf_file)

    log_error "Diagnóstico Docker Registry:"
    log_error "  Host registry: $DOCKER_REGISTRY_HOST"
    log_error "  Gestor DNS detectado: $manager"
    log_error "  Resolver actual: $resolv_conf"
    if [[ -r "$resolv_conf" ]]; then
        sed 's/^/    /' "$resolv_conf" >&2 || true
    fi
    log_error "Comandos útiles:"
    log_error "  getent hosts $DOCKER_REGISTRY_HOST"
    log_error "  curl -sSIL $DOCKER_REGISTRY_URL"
    log_error "  docker pull hello-world"
}

repair_dns_for_docker_registry() {
    local manager
    manager=$(dns_manager_type)

    log_warning "Docker no pudo resolver o descargar desde Docker Hub. Gestor DNS detectado: $manager"
    case "$manager" in
        dhcpcd)
            log_info "Aplicando reparación DNS para dhcpcd mediante /etc/resolv.conf.head"
            repair_dhcpcd_dns_for_docker
            ;;
        systemd-resolved)
            log_info "Aplicando reparación DNS para systemd-resolved"
            repair_systemd_resolved_dns_for_docker
            ;;
        networkmanager)
            log_info "Aplicando reparación DNS para NetworkManager"
            repair_networkmanager_dns_for_docker
            ;;
        plain)
            log_warning "resolv.conf no parece gestionado por un servicio conocido; se escribirá DNS público con respaldo previo."
            repair_plain_dns_for_docker
            ;;
        *)
            print_docker_registry_diagnostics
            log_error "No se reconoce el gestor DNS. No se modificará la red a ciegas."
            return 1
            ;;
    esac

    restart_docker_after_dns_change
}

validate_docker_registry_access() {
    if [[ "${DRY_RUN:-false}" == true ]]; then
        echo -e "${CYAN}[DRY-RUN]${RESET} Validaría DNS host, HTTPS registry y docker pull hello-world contra $DOCKER_REGISTRY_HOST"
        return 0
    fi

    log_info "Validando resolución DNS del host para $DOCKER_REGISTRY_HOST..."
    if docker_registry_host_probe; then
        log_success "Host resuelve y alcanza Docker Registry"
    else
        log_warning "El host no pudo validar completamente $DOCKER_REGISTRY_URL"
    fi

    log_info "Validando Docker daemon con docker pull hello-world..."
    if docker_registry_pull_probe; then
        log_success "Docker daemon puede descargar desde Docker Hub"
        return 0
    fi

    repair_dns_for_docker_registry || return 1

    log_info "Reintentando validación Docker Registry después de reparar DNS..."
    if docker_registry_host_probe && docker_registry_pull_probe; then
        log_success "Docker Registry validado después de reparar DNS"
        return 0
    fi

    print_docker_registry_diagnostics
    log_error "No se pudo validar Docker Hub. Si la red bloquea DNS externo, TLS o requiere proxy, corrige la red antes de continuar."
    return 1
}

os_release_value() {
    local key="$1"
    awk -F= -v key="$key" '
        $1 == key {
            value = $2
            gsub(/^"/, "", value)
            gsub(/"$/, "", value)
            print value
            exit
        }
    ' /etc/os-release 2>/dev/null || true
}

detect_os_id() {
    os_release_value "ID"
}

detect_os_id_like() {
    os_release_value "ID_LIKE"
}

detect_os_codename() {
    local codename
    codename=$(os_release_value "VERSION_CODENAME")

    if [[ -z "$codename" ]] && command_exists lsb_release; then
        codename=$(lsb_release -cs 2>/dev/null || true)
    fi

    echo "$codename"
}

detect_debian_version_id() {
    os_release_value "VERSION_ID"
}

detect_debian_version_full() {
    os_release_value "DEBIAN_VERSION_FULL"
}

detect_debian_major_version() {
    local version_id version_full debian_version
    version_id=$(detect_debian_version_id)
    version_full=$(detect_debian_version_full)
    debian_version=$(cat /etc/debian_version 2>/dev/null || true)

    for value in "$version_id" "$version_full" "$debian_version"; do
        if [[ "$value" =~ ^([0-9]+) ]]; then
            echo "${BASH_REMATCH[1]}"
            return 0
        fi
    done

    echo ""
}

is_debian_13_family() {
    local codename major
    codename=$(detect_os_codename)
    major=$(detect_debian_major_version)

    [[ "$major" == "13" || "$codename" == "trixie" ]]
}

detect_architecture() {
    dpkg --print-architecture 2>/dev/null || uname -m
}

is_raspberry_pi_hardware() {
    local model_file="/proc/device-tree/model"
    [[ -r "$model_file" ]] && grep -qi "Raspberry Pi" "$model_file"
}

raspberry_pi_model() {
    local model_file="/proc/device-tree/model"
    if [[ -r "$model_file" ]]; then
        tr -d '\0' < "$model_file"
    fi
}

is_raspberry_pi4_family() {
    local model
    model=$(raspberry_pi_model)
    [[ "$model" =~ Raspberry\ Pi\ 4 ]] || \
        [[ "$model" =~ Raspberry\ Pi\ 400 ]] || \
        [[ "$model" =~ Compute\ Module\ 4 ]]
}

detect_ssh_service() {
    if systemctl list-unit-files ssh.service >/dev/null 2>&1; then
        echo "ssh"
    elif systemctl list-unit-files sshd.service >/dev/null 2>&1; then
        echo "sshd"
    else
        echo "ssh"
    fi
}

ensure_platform_supported() {
    local allow_legacy_pi4="${ALLOW_LEGACY_PI4_MONGODB:-false}"
    local os_id os_like codename arch version_id version_full debian_major
    os_id=$(detect_os_id)
    os_like=$(detect_os_id_like)
    codename=$(detect_os_codename)
    arch=$(detect_architecture)
    version_id=$(detect_debian_version_id)
    version_full=$(detect_debian_version_full)
    debian_major=$(detect_debian_major_version)

    if [[ "$os_id" != "debian" && "$os_id" != "raspbian" && "$os_like" != *"debian"* ]]; then
        log_error "Sistema no soportado: ID=${os_id:-desconocido}, ID_LIKE=${os_like:-desconocido}"
        log_error "v${PLATFORM_VERSION} soporta Debian y derivados Debian compatibles."
        return 1
    fi

    if ! is_debian_13_family; then
        log_error "Version Debian no soportada por v${PLATFORM_VERSION}: VERSION_ID=${version_id:-desconocido}, DEBIAN_VERSION_FULL=${version_full:-desconocido}, codename=${codename:-desconocido}"
        log_error "Este instalador soporta Debian 13.x / Trixie y derivados basados en Trixie."
        log_error "Debian 13.4 es valido porque pertenece a Debian 13 y usa codename trixie."
        return 1
    fi

    case "$arch" in
        amd64|arm64)
            ;;
        armhf)
            log_error "Arquitectura no soportada por el stack actual: armhf (32-bit)."
            log_error "Docker puede instalarse en armhf, pero MySQL/MongoDB oficiales del stack no son fiables o no estan disponibles para 32-bit."
            log_error "Usa Debian/Raspberry Pi OS 64-bit en hardware arm64."
            return 1
            ;;
        *)
            log_error "Arquitectura no soportada por v${PLATFORM_VERSION}: $arch"
            log_error "Arquitecturas soportadas: amd64 y arm64."
            return 1
            ;;
    esac

    if is_raspberry_pi4_family; then
        if [[ "$allow_legacy_pi4" == true ]]; then
            log_warning "Raspberry Pi 4/400/CM4 detectada: $(raspberry_pi_model)"
            log_warning "Modo legacy Pi 4 habilitado: se usara ${LEGACY_PI4_MONGO_IMAGE} en lugar de ${DEFAULT_MONGO_IMAGE}."
            log_warning "MongoDB 4.4 esta fuera de soporte. Usar solo para laboratorio, demo local o compatibilidad temporal."
        else
            log_warning "Raspberry Pi 4/400/CM4 detectada: $(raspberry_pi_model)"
            log_warning "MongoDB 7.0 no soporta Raspberry Pi 4 por requisito de CPU ARMv8.2-A o posterior."
            log_warning "La unica ruta v${PLATFORM_VERSION} para Pi 4 es modo laboratorio con ${LEGACY_PI4_MONGO_IMAGE}; no es producción porque MongoDB 4.4 esta EOL."

            if [[ "${DRY_RUN:-false}" == true ]]; then
                log_warning "Dry-run: se simulara el modo legacy Pi 4 para mostrar el plan completo."
                ALLOW_LEGACY_PI4_MONGODB=true
            elif [[ "${INTERNAL_RESUME:-false}" == true || "${RESUME_MODE:-false}" == true ]]; then
                log_error "La configuración guardada no habilita el modo legacy Pi 4. Repite la instalación inicial y confirma el modo de laboratorio."
                return 1
            else
                local confirm_legacy
                read -p "¿Continuar en modo laboratorio con MongoDB 4.4 EOL? [s/N]: " confirm_legacy
                if [[ "$confirm_legacy" =~ ^[sSyY]$ ]]; then
                    ALLOW_LEGACY_PI4_MONGODB=true
                    log_warning "Modo legacy Pi 4 confirmado por el usuario."
                else
                    log_error "Instalación cancelada: Raspberry Pi 4 no es compatible con MongoDB 7.0."
                    log_error "Soporte limpio de producción para Pi 4 requiere cambiar la capa de almacenamiento de sensores."
                    return 1
                fi
            fi
        fi
    fi

    log_info "Plataforma detectada: ID=${os_id:-desconocido}, Debian=${debian_major:-desconocido}, VERSION_ID=${version_id:-desconocido}, DEBIAN_VERSION_FULL=${version_full:-desconocido}, codename=${codename:-desconocido}, arch=$arch"
}

select_mongo_image() {
    if [[ "${ALLOW_LEGACY_PI4_MONGODB:-false}" == true ]] && is_raspberry_pi4_family; then
        echo "$LEGACY_PI4_MONGO_IMAGE"
    else
        echo "$DEFAULT_MONGO_IMAGE"
    fi
}

resource_profile() {
    local profile="${RESOURCE_PROFILE:-$STANDARD_RESOURCE_PROFILE}"
    if [[ "$profile" == "$AUTO_RESOURCE_PROFILE" ]]; then
        echo "$STANDARD_RESOURCE_PROFILE"
    else
        echo "$profile"
    fi
}

is_low_resource_profile() {
    [[ "$(resource_profile)" == "$LOW_RESOURCE_PROFILE" ]]
}

is_compact_storage() {
    [[ "${COMPACT_STORAGE:-false}" == true ]]
}

effective_profile_label() {
    if is_compact_storage; then
        echo "compact-storage"
    else
        resource_profile
    fi
}

safe_autopurge_enabled() {
    [[ "$(storage_purge_mode)" == "system" || "$(storage_purge_mode)" == "both" ]]
}

storage_alerts_enabled() {
    [[ "${STORAGE_ALERTS:-true}" == true ]]
}

storage_purge_mode() {
    local mode="${STORAGE_PURGE_MODE:-none}"
    case "$mode" in
        system|data|both|none)
            echo "$mode"
            ;;
        *)
            echo "none"
            ;;
    esac
}

data_purge_enabled() {
    [[ "$(storage_purge_mode)" == "data" || "$(storage_purge_mode)" == "both" ]]
}

autopurge_mode_label() {
    storage_purge_mode
}

alerts_mode_label() {
    if storage_alerts_enabled; then
        echo "enabled"
    else
        echo "disabled"
    fi
}

default_data_retention_days_for_profile() {
    if is_compact_storage; then
        echo "$COMPACT_DATA_RETENTION_DAYS"
    else
        echo "$DEFAULT_DATA_RETENTION_DAYS"
    fi
}

default_redis_memory_for_profile() {
    if is_low_resource_profile; then
        echo "128mb"
    else
        echo "256mb"
    fi
}

docker_log_max_size() {
    if is_compact_storage; then
        echo "$COMPACT_DOCKER_LOG_MAX_SIZE"
    else
        echo "$STANDARD_DOCKER_LOG_MAX_SIZE"
    fi
}

docker_log_max_file() {
    if is_compact_storage; then
        echo "$COMPACT_DOCKER_LOG_MAX_FILE"
    else
        echo "$STANDARD_DOCKER_LOG_MAX_FILE"
    fi
}

host_log_max_size() {
    if is_compact_storage; then
        echo "$COMPACT_HOST_LOG_MAX_SIZE"
    else
        echo "$STANDARD_HOST_LOG_MAX_SIZE"
    fi
}

host_log_rotate_count() {
    if is_compact_storage; then
        echo "$COMPACT_HOST_LOG_ROTATE"
    else
        echo "$STANDARD_HOST_LOG_ROTATE"
    fi
}

total_ram_mb() {
    awk '/^MemTotal:/ {print int($2 / 1024)}' /proc/meminfo
}

total_swap_mb() {
    awk '/^SwapTotal:/ {print int($2 / 1024)}' /proc/meminfo
}

storage_total_mb() {
    df -Pm / | awk 'NR==2 {print $2}'
}

storage_used_mb() {
    df -Pm / | awk 'NR==2 {print $3}'
}

storage_available_mb() {
    df -Pm / | awk 'NR==2 {print $4}'
}

format_storage_mb() {
    local mb="${1:-0}"
    awk -v mb="$mb" 'BEGIN {printf "%.1fGB", mb / 1024}'
}

available_root_disk_gb() {
    local available_mb
    available_mb=$(storage_available_mb)
    echo $((available_mb / 1024))
}

resolve_installation_profiles() {
    local requested_profile requested_compact ram_mb total_mb used_mb available_mb
    local profile_source compact_source

    requested_profile="${RESOURCE_PROFILE:-$AUTO_RESOURCE_PROFILE}"
    requested_compact="${COMPACT_STORAGE:-auto}"
    profile_source="${RESOURCE_PROFILE_SOURCE:-auto}"
    compact_source="${COMPACT_STORAGE_SOURCE:-auto}"

    case "$requested_profile" in
        "$AUTO_RESOURCE_PROFILE"|"$STANDARD_RESOURCE_PROFILE"|"$LOW_RESOURCE_PROFILE")
            ;;
        *)
            log_error "Perfil de recursos inválido: $requested_profile"
            log_error "Valores permitidos: auto, standard, low-resource"
            return 1
            ;;
    esac

    case "$requested_compact" in
        auto|true|false)
            ;;
        *)
            log_error "Valor inválido para compact storage: $requested_compact"
            log_error "Valores permitidos: auto, true, false"
            return 1
            ;;
    esac

    ram_mb=$(total_ram_mb)
    total_mb=$(storage_total_mb)
    used_mb=$(storage_used_mb)
    available_mb=$(storage_available_mb)

    STORAGE_TOTAL_MB="$total_mb"
    STORAGE_USED_MB="$used_mb"
    STORAGE_AVAILABLE_MB="$available_mb"

    if [[ "$requested_profile" == "$AUTO_RESOURCE_PROFILE" ]]; then
        if [[ $ram_mb -lt $STANDARD_MIN_RAM_MB ]]; then
            RESOURCE_PROFILE="$LOW_RESOURCE_PROFILE"
        else
            RESOURCE_PROFILE="$STANDARD_RESOURCE_PROFILE"
        fi
        RESOURCE_PROFILE_SOURCE="auto"
    else
        RESOURCE_PROFILE="$requested_profile"
        RESOURCE_PROFILE_SOURCE="$profile_source"
    fi

    if [[ "$requested_compact" == "auto" ]]; then
        if [[ $available_mb -lt $LOW_RESOURCE_MIN_DISK_MB ]]; then
            COMPACT_STORAGE=true
            RESOURCE_PROFILE="$LOW_RESOURCE_PROFILE"
        else
            COMPACT_STORAGE=false
        fi
        COMPACT_STORAGE_SOURCE="auto"
    else
        COMPACT_STORAGE="$requested_compact"
        COMPACT_STORAGE_SOURCE="$compact_source"
    fi

    if [[ "$COMPACT_STORAGE" == true ]]; then
        RESOURCE_PROFILE="$LOW_RESOURCE_PROFILE"
    fi

    log_info "Perfil detectado: $(effective_profile_label) (recursos=${RESOURCE_PROFILE}, origen=${RESOURCE_PROFILE_SOURCE}; compact-storage=${COMPACT_STORAGE}, origen=${COMPACT_STORAGE_SOURCE}), RAM=${ram_mb}MB, disco total=$(format_storage_mb "$total_mb"), libre=$(format_storage_mb "$available_mb")"
}

set_resource_tuning_defaults() {
    local profile
    profile=$(resource_profile)

    case "$profile" in
        "$LOW_RESOURCE_PROFILE")
            MYSQL_COMMAND='["mysqld","--innodb-buffer-pool-size=128M","--max-connections=40","--performance-schema=OFF","--table-open-cache=400","--thread-cache-size=4"]'
            MYSQL_INNODB_BUFFER_POOL="128M"
            MYSQL_MAX_CONNECTIONS="40"
            MYSQL_MEM_LIMIT="384M"
            MYSQL_MEM_RESERVATION="256M"
            MYSQL_CPUS="0.75"

            MONGO_COMMAND='["mongod","--wiredTigerCacheSizeGB","0.25"]'
            MONGO_WIREDTIGER_CACHE="0.25"
            MONGO_MEM_LIMIT="512M"
            MONGO_MEM_RESERVATION="384M"
            MONGO_CPUS="0.75"

            REDIS_MEM_LIMIT="160M"
            REDIS_MEM_RESERVATION="96M"
            REDIS_CPUS="0.25"

            FASTAPI_COMMAND='["uvicorn","app:app","--host","0.0.0.0","--port","5000","--workers","1","--proxy-headers"]'
            FASTAPI_WORKERS="1"
            FASTAPI_MEM_LIMIT="384M"
            FASTAPI_MEM_RESERVATION="256M"
            FASTAPI_CPUS="0.75"

            NGINX_MEM_LIMIT="96M"
            NGINX_MEM_RESERVATION="32M"
            NGINX_CPUS="0.25"
            ;;
        *)
            MYSQL_COMMAND='["mysqld"]'
            MYSQL_INNODB_BUFFER_POOL="default"
            MYSQL_MAX_CONNECTIONS="default"
            MYSQL_MEM_LIMIT="512M"
            MYSQL_MEM_RESERVATION="256M"
            MYSQL_CPUS="1.0"

            MONGO_COMMAND='["mongod"]'
            MONGO_WIREDTIGER_CACHE="default"
            MONGO_MEM_LIMIT="512M"
            MONGO_MEM_RESERVATION="256M"
            MONGO_CPUS="1.0"

            REDIS_MEM_LIMIT="256M"
            REDIS_MEM_RESERVATION="128M"
            REDIS_CPUS="0.5"

            FASTAPI_COMMAND='["uvicorn","app:app","--host","0.0.0.0","--port","5000","--workers","2","--proxy-headers"]'
            FASTAPI_WORKERS="2"
            FASTAPI_MEM_LIMIT="1G"
            FASTAPI_MEM_RESERVATION="512M"
            FASTAPI_CPUS="1.5"

            NGINX_MEM_LIMIT="128M"
            NGINX_MEM_RESERVATION="64M"
            NGINX_CPUS="0.5"
            ;;
    esac
}

wait_for_confirmation() {
    local message="${1:-Presiona ENTER para continuar}"
    read -p "$message: "
}

detect_current_user() {
    if [[ $EUID -eq 0 ]]; then
        echo "root"
    elif [[ "$USER" == "debian" ]]; then
        echo "debian"
    else
        echo "otro"
    fi
}

is_service_running() {
    local service=$1
    systemctl is-active --quiet "$service"
}

backup_file() {
    local file=$1
    if [[ -f "$file" ]]; then
        local backup="${file}.backup-$(date +%Y%m%d-%H%M%S)"
        cp "$file" "$backup"
        log_info "Respaldado: $file → $backup"
    fi
}

replace_in_file() {
    local file=$1
    local search=$2
    local replace=$3
    
    if [[ ! -f "$file" ]]; then
        log_error "Archivo no encontrado: $file"
        return 1
    fi
    
    sed -i "s|${search}|${replace}|g" "$file"
}

create_dir() {
    local dir=$1
    local perms=${2:-755}
    local owner=${3:-root:root}
    
    mkdir -p "$dir"
    chmod "$perms" "$dir"
    chown "$owner" "$dir"
}

download_file() {
    local url=$1
    local dest=$2
    local max_retries=${3:-3}
    
    for i in $(seq 1 $max_retries); do
        if curl -fsSL "$url" -o "$dest"; then
            log_success "Descargado: $url"
            return 0
        else
            log_warning "Intento de descarga $i/$max_retries falló"
            sleep 2
        fi
    done
    
    log_error "Falló al descargar: $url"
    return 1
}

is_port_available() {
    local port=$1
    ! ss -tlnp | grep -q ":${port} "
}

get_system_info() {
    cat << EOF
SO: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)
Kernel: $(uname -r)
CPU: $(nproc) núcleos
RAM: $(free -h | awk '/^Mem:/ {print $2}')
Disco: $(df -h / | awk 'NR==2 {print $2 " total, " $4 " libre"}')
EOF
}

calc_progress() {
    local current=$1
    local total=$2
    echo $(( (current * 100) / total ))
}

format_duration() {
    local seconds=$1
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))
    printf "%02d:%02d:%02d" $hours $minutes $secs
}

check_system_resources() {
    local profile min_ram_mb min_total_mb min_available_mb
    profile=$(resource_profile)

    if is_compact_storage; then
        min_ram_mb=$LOW_RESOURCE_MIN_RAM_MB
        min_total_mb=$COMPACT_STORAGE_MIN_TOTAL_MB
        min_available_mb=$COMPACT_STORAGE_MIN_AVAILABLE_MB
    elif [[ "$profile" == "$LOW_RESOURCE_PROFILE" ]]; then
        min_ram_mb=$LOW_RESOURCE_MIN_RAM_MB
        min_total_mb=0
        min_available_mb=$LOW_RESOURCE_MIN_DISK_MB
    else
        min_ram_mb=$STANDARD_MIN_RAM_MB
        min_total_mb=0
        min_available_mb=$STANDARD_MIN_DISK_MB
    fi
    
    local ram_mb
    ram_mb=$(total_ram_mb)
    
    if [[ $ram_mb -lt $min_ram_mb ]]; then
        log_warning "RAM baja: ${ram_mb}MB (mínimo para $profile: ${min_ram_mb}MB)"
    fi
    
    local total_mb available_mb
    total_mb=$(storage_total_mb)
    available_mb=$(storage_available_mb)
    
    if [[ $min_total_mb -gt 0 && $total_mb -lt $min_total_mb ]]; then
        log_error "Disco total insuficiente: $(format_storage_mb "$total_mb") (mínimo compact-storage: $(format_storage_mb "$min_total_mb"))"
        return 1
    fi

    if [[ $available_mb -lt $min_available_mb ]]; then
        log_error "Espacio en disco insuficiente: $(format_storage_mb "$available_mb") disponible (mínimo: $(format_storage_mb "$min_available_mb"))"
        return 1
    fi
    
    return 0
}

generate_random_string() {
    local length=${1:-32}
    openssl rand -base64 $length | tr -d "=+/" | cut -c1-$length
}

generate_random_hex() {
    local length=${1:-32}
    openssl rand -hex $length
}

is_docker() {
    [[ -f /.dockerenv ]] || grep -q docker /proc/1/cgroup 2>/dev/null
}

ensure_not_docker() {
    if is_docker; then
        log_error "Este script no puede ejecutarse dentro de un contenedor Docker"
        exit 1
    fi
}
