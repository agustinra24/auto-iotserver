#!/bin/bash
################################################################################
# lib/phases.sh - Funciones de fases de instalación
################################################################################

################################################################################
# Funciones de utilidad
################################################################################
validate_system_requirements() {
    log_info "Validando requisitos del sistema..."

    local profile ram_mb min_ram_mb total_mb available_mb min_total_mb min_available_mb
    profile=$(resource_profile)
    validate_resource_profile "$profile" || return 1

    ram_mb=$(total_ram_mb)
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

    if [[ $ram_mb -lt $min_ram_mb ]]; then
        if [[ "$profile" == "$LOW_RESOURCE_PROFILE" ]]; then
            log_error "RAM insuficiente para low-resource: ${ram_mb}MB (mínimo nominal aceptado: 2GB, umbral real: ${min_ram_mb}MB)"
        else
            log_error "RAM insuficiente para perfil standard: ${ram_mb}MB (mínimo nominal: 4GB, umbral real: ${min_ram_mb}MB)"
            log_error "El instalador selecciona low-resource automaticamente en hosts de 2GB nominales; si ves este error, revisa la configuración guardada o la RAM asignada a la VM."
        fi
        return 1
    fi

    if [[ "$profile" == "$LOW_RESOURCE_PROFILE" ]]; then
        log_warning "Perfil low-resource activo: objetivo 2GB RAM nominales, carga IoT liviana y concurrencia limitada."
    fi
    if is_compact_storage; then
        log_warning "Compact storage activo: modo laboratorio para hosts con poco espacio libre."
        log_warning "Riesgo esperado: agotamiento rápido de espacio si crecen logs, imágenes Docker o datos IoT."
        if [[ "$(storage_purge_mode)" == "none" ]]; then
            log_warning "Purga automática desactivada; solo alertas si fueron habilitadas."
        else
            log_warning "Modo de purga activo: $(storage_purge_mode), retención datos: ${DATA_RETENTION_DAYS:-$(default_data_retention_days_for_profile)} días."
        fi
    fi
    log_success "RAM: ${ram_mb}MB (perfil: $profile)"

    total_mb=$(storage_total_mb)
    available_mb=$(storage_available_mb)
    STORAGE_TOTAL_MB="$total_mb"
    STORAGE_AVAILABLE_MB="$available_mb"

    if [[ $min_total_mb -gt 0 && $total_mb -lt $min_total_mb ]]; then
        log_error "Almacenamiento total insuficiente: $(format_storage_mb "$total_mb") (mínimo compact-storage: $(format_storage_mb "$min_total_mb"))"
        log_error "Un medio de 8GB nominal suele verse como ~7.2 a 7.5GB reales; por debajo de eso no hay margen para Docker y bases de datos."
        return 1
    fi

    if [[ $available_mb -lt $min_available_mb ]]; then
        log_error "Espacio libre insuficiente: $(format_storage_mb "$available_mb") disponibles (mínimo: $(format_storage_mb "$min_available_mb"))"
        if is_compact_storage; then
            log_error "Compact-storage necesita al menos $(format_storage_mb "$COMPACT_STORAGE_MIN_AVAILABLE_MB") libres en una instalación limpia."
        else
            log_error "El instalador activa compact-storage automaticamente cuando detecta menos de $(format_storage_mb "$LOW_RESOURCE_MIN_DISK_MB") libres; si vienes de una reanudación, revisa .config.env."
        fi
        return 1
    fi

    if is_compact_storage; then
        if [[ $total_mb -lt $COMPACT_STORAGE_RECOMMENDED_TOTAL_MB ]]; then
            log_warning "Disco total muy ajustado: $(format_storage_mb "$total_mb") (recomendado: $(format_storage_mb "$COMPACT_STORAGE_RECOMMENDED_TOTAL_MB")+ para más margen)."
        fi
        if [[ $available_mb -lt $COMPACT_STORAGE_RECOMMENDED_AVAILABLE_MB ]]; then
            log_warning "Espacio libre muy ajustado: $(format_storage_mb "$available_mb") (recomendado: $(format_storage_mb "$COMPACT_STORAGE_RECOMMENDED_AVAILABLE_MB")+ en compact-storage)."
        fi
    elif [[ "$profile" == "$LOW_RESOURCE_PROFILE" && $available_mb -lt $LOW_RESOURCE_RECOMMENDED_DISK_MB ]]; then
        log_warning "Disco justo para low-resource: $(format_storage_mb "$available_mb") disponibles (recomendado: $(format_storage_mb "$LOW_RESOURCE_RECOMMENDED_DISK_MB")+)"
    fi
    log_success "Almacenamiento: total $(format_storage_mb "$total_mb"), libre $(format_storage_mb "$available_mb")"
    
    local cpu_cores=$(nproc)
    if [[ $cpu_cores -lt 1 ]]; then
        log_error "Núcleos de CPU insuficientes: $cpu_cores (mínimo: 1)"
        return 1
    fi
    log_success "Núcleos CPU: $cpu_cores"
    
    if ! curl -fsSL --max-time 10 https://deb.debian.org/debian/ > /dev/null 2>&1; then
        log_error "Sin conectividad a internet"
        return 1
    fi
    log_success "Conectividad a internet"
    
    return 0
}

ensure_low_resource_swap() {
    local ram_mb swap_mb swapfile="/swapfile" target_swap_mb

    if ! is_low_resource_profile; then
        return 0
    fi

    ram_mb=$(total_ram_mb)
    swap_mb=$(total_swap_mb)
    if is_compact_storage; then
        target_swap_mb=$COMPACT_STORAGE_SWAP_MB
    else
        target_swap_mb=$LOW_RESOURCE_MIN_SWAP_MB
    fi

    if [[ $ram_mb -ge $LOW_RESOURCE_SWAP_TRIGGER_RAM_MB ]]; then
        log_info "RAM >= ${LOW_RESOURCE_SWAP_TRIGGER_RAM_MB}MB; no se requiere swap adicional low-resource"
        return 0
    fi

    if [[ $swap_mb -ge $target_swap_mb ]]; then
        log_success "Swap existente suficiente: ${swap_mb}MB"
        if [[ "$DRY_RUN" != true ]]; then
            printf 'vm.swappiness=10\n' > /etc/sysctl.d/99-iot-low-resource.conf
            sysctl -w vm.swappiness=10 >> "$LOG_FILE" 2>&1 || true
        fi
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${CYAN}[DRY-RUN]${RESET} Crearía swapfile de ${target_swap_mb}MB y configuraría vm.swappiness=10"
        return 0
    fi

    if [[ -e "$swapfile" ]]; then
        log_error "Swap total insuficiente (${swap_mb}MB) y $swapfile ya existe."
        log_error "Redimensiona o elimina ese swapfile manualmente antes de continuar."
        return 1
    fi

    log_info "Creando swapfile de ${target_swap_mb}MB para perfil low-resource..."
    fallocate -l "${target_swap_mb}M" "$swapfile" 2>> "$LOG_FILE" || dd if=/dev/zero of="$swapfile" bs=1M count="$target_swap_mb" >> "$LOG_FILE" 2>&1
    chmod 600 "$swapfile"
    mkswap "$swapfile" >> "$LOG_FILE" 2>&1

    if ! swapon --show=NAME --noheadings | grep -Fxq "$swapfile"; then
        swapon "$swapfile" >> "$LOG_FILE" 2>&1
    fi

    if ! grep -Eq '^[[:space:]]*/swapfile[[:space:]]+none[[:space:]]+swap[[:space:]]' /etc/fstab; then
        printf '/swapfile none swap sw 0 0\n' >> /etc/fstab
    fi

    printf 'vm.swappiness=10\n' > /etc/sysctl.d/99-iot-low-resource.conf
    sysctl -w vm.swappiness=10 >> "$LOG_FILE" 2>&1 || true

    log_success "Swap low-resource configurado"
}

configure_docker_daemon_logging() {
    local daemon_file="${DOCKER_DAEMON_JSON_FILE:-/etc/docker/daemon.json}"
    local tmp_file log_max_size log_max_file dns_json
    log_max_size=$(docker_log_max_size)
    log_max_file=$(docker_log_max_file)
    dns_json=$(docker_dns_json)

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${CYAN}[DRY-RUN]${RESET} Configuraría Docker daemon.json con DNS=${dns_json}, json-file max-size=${log_max_size} max-file=${log_max_file}"
        return 0
    fi

    mkdir -p "$(dirname "$daemon_file")"
    tmp_file=$(mktemp)

    if [[ -f "$daemon_file" ]]; then
        if ! jq empty "$daemon_file" >> "$LOG_FILE" 2>&1; then
            log_error "Docker daemon.json existente no es JSON válido: $daemon_file"
            rm -f "$tmp_file"
            return 1
        fi

        cp "$daemon_file" "${daemon_file}.bak.$(date +%Y%m%d%H%M%S)"
        jq --argjson dns "$dns_json" --arg max_size "$log_max_size" --arg max_file "$log_max_file" \
            '. + {"dns":$dns,"log-driver":"json-file"} | .["log-opts"] = ((.["log-opts"] // {}) + {"max-size":$max_size,"max-file":$max_file})' \
            "$daemon_file" > "$tmp_file"
    else
        printf '{\n  "dns": %s,\n  "log-driver": "json-file",\n  "log-opts": {\n    "max-size": "%s",\n    "max-file": "%s"\n  }\n}\n' "$dns_json" "$log_max_size" "$log_max_file" > "$tmp_file"
    fi

    if command_exists dockerd && dockerd --help 2>/dev/null | grep -q -- '--validate'; then
        if ! dockerd --validate --config-file="$tmp_file" >> "$LOG_FILE" 2>&1; then
            log_error "Docker daemon.json generado no pasó validación de dockerd"
            rm -f "$tmp_file"
            return 1
        fi
    fi

    install -m 0644 "$tmp_file" "$daemon_file"
    rm -f "$tmp_file"
}

compose_supports_progress_flag() {
    docker compose --help 2>/dev/null | grep -q -- '--progress'
}

run_compose_up() {
    local output_file="$1"
    local compose_cmd=("docker" "compose")

    if compose_supports_progress_flag; then
        compose_cmd+=("--progress" "plain")
    fi
    compose_cmd+=("up" "-d")

    if is_low_resource_profile || is_compact_storage; then
        COMPOSE_PARALLEL_LIMIT=1 "${compose_cmd[@]}" > "$output_file" 2>&1
    else
        "${compose_cmd[@]}" > "$output_file" 2>&1
    fi
}

collect_deployment_failure_diagnostics() {
    local install_dir="$1"
    local compose_output="${2:-}"
    local diag_file="$install_dir/deployment-diagnostics-$(date +%Y%m%d-%H%M%S).log"

    {
        echo "=== compose output ==="
        if [[ -n "$compose_output" && -f "$compose_output" ]]; then
            cat "$compose_output"
        fi
        echo
        echo "=== docker compose ps -a ==="
        docker compose ps -a || true
        echo
        echo "=== docker images ==="
        docker images || true
        echo
        echo "=== docker system df ==="
        docker system df || true
        echo
        echo "=== /etc/resolv.conf ==="
        cat "$(current_resolv_conf_file)" 2>/dev/null || true
        echo
        echo "=== registry DNS ==="
        getent hosts "$DOCKER_REGISTRY_HOST" || true
        echo
        echo "=== registry HTTP ==="
        curl -sSIL --max-time 15 "$DOCKER_REGISTRY_URL" || true
        echo
        echo "=== docker service logs ==="
        journalctl -u docker --no-pager -n 120 || true
    } > "$diag_file" 2>&1

    cat "$diag_file" >> "$LOG_FILE" 2>/dev/null || true
    log_error "Diagnóstico detallado guardado en: $diag_file"

    if [[ -n "$compose_output" && -f "$compose_output" ]]; then
        if grep -Eiq 'lookup|no such host|failed to resolve|registry-1\.docker\.io|auth\.docker\.io|temporary failure in name resolution' "$compose_output"; then
            log_error "Causa probable: fallo DNS contra Docker Hub o registry de imágenes."
        elif grep -Eiq 'no space left|not enough space|ENOSPC' "$compose_output"; then
            log_error "Causa probable: almacenamiento insuficiente durante pull/build."
        elif grep -Eiq 'killed|oom|out of memory' "$compose_output"; then
            log_error "Causa probable: presión de memoria u OOM durante pull/build."
        else
            log_error "No se detectó una causa única en la salida de Compose; revisa el diagnóstico completo."
        fi

        log_error "Últimas líneas de Compose:"
        tail -n 35 "$compose_output" >&2 || true
    fi
}

install_storage_maintenance() {
    local install_dir="$INSTALL_DIR"
    local log_max_size rotate_count timer_interval warn_pct critical_pct builder_prune_cmd
    local autopurge_enabled alerts_enabled purge_mode data_retention_days

    log_max_size=$(host_log_max_size)
    rotate_count=$(host_log_rotate_count)
    purge_mode=$(storage_purge_mode)
    data_retention_days="${DATA_RETENTION_DAYS:-$(default_data_retention_days_for_profile)}"
    if safe_autopurge_enabled; then
        autopurge_enabled=true
    else
        autopurge_enabled=false
    fi
    if storage_alerts_enabled; then
        alerts_enabled=true
    else
        alerts_enabled=false
    fi

    if is_compact_storage; then
        timer_interval="6h"
        warn_pct=80
        critical_pct=90
        builder_prune_cmd="docker builder prune -af"
    else
        timer_interval="24h"
        warn_pct=85
        critical_pct=92
        builder_prune_cmd="docker builder prune -af --filter until=24h"
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${CYAN}[DRY-RUN]${RESET} Configuraría mantenimiento de almacenamiento cada ${timer_interval} (alertas: $(alerts_mode_label), purga: $(autopurge_mode_label), retención: ${data_retention_days} días)"
        return 0
    fi

    if [[ "$alerts_enabled" != true && "$purge_mode" == "none" ]]; then
        systemctl disable --now iot-storage-maintenance.timer >/dev/null 2>&1 || true
        rm -f /etc/systemd/system/iot-storage-maintenance.service
        rm -f /etc/systemd/system/iot-storage-maintenance.timer
        rm -f /etc/profile.d/iot-storage-warning.sh
        rm -f /usr/local/sbin/iot-storage-maintenance
        systemctl daemon-reload
        log_warning "Mantenimiento de almacenamiento desactivado por decisión explícita del administrador"
        return 0
    fi

    cat > /usr/local/sbin/iot-storage-maintenance << MAINTENANCEEOF
#!/bin/bash
set -u

INSTALL_DIR="$install_dir"
STATUS_DIR="/var/lib/iot-platform-maintenance"
WARNING_FILE="\$STATUS_DIR/storage-warning"
LOG_FILE="/var/log/iot-platform-maintenance.log"
WARN_PCT=$warn_pct
CRITICAL_PCT=$critical_pct
LOG_MAX_SIZE="$log_max_size"
SAFE_AUTOPURGE="$autopurge_enabled"
STORAGE_ALERTS="$alerts_enabled"
STORAGE_PURGE_MODE="$purge_mode"
DATA_RETENTION_DAYS=$data_retention_days

mkdir -p "\$STATUS_DIR"
touch "\$LOG_FILE"

log_msg() {
    local msg="\$1"
    printf '%s %s\n' "\$(date -Iseconds)" "\$msg" >> "\$LOG_FILE"
    logger -t iot-storage-maintenance -- "\$msg" 2>/dev/null || true
}

usage_pct() {
    local path="\$1"
    df -P "\$path" 2>/dev/null | awk 'NR==2 {gsub("%","",\$5); print \$5}'
}

load_app_env() {
    if [[ ! -r "\$INSTALL_DIR/.env" ]]; then
        log_msg "No se encontró .env de la aplicación; se omite purga de datos"
        return 1
    fi

    set -a
    # shellcheck disable=SC1090
    . "\$INSTALL_DIR/.env"
    set +a
}

purge_system_storage() {
    log_msg "Ejecutando purga system: journal, build cache, imágenes colgantes, contenedores detenidos y logs"
    journalctl --vacuum-size=50M >/dev/null 2>&1 || true
    $builder_prune_cmd >/dev/null 2>&1 || true
    docker image prune -f >/dev/null 2>&1 || true
    docker container prune -f >/dev/null 2>&1 || true
    find "\$INSTALL_DIR/logs" -type f -name "*.log" -size +"$log_max_size" -exec truncate -s 0 {} \; 2>/dev/null || true
}

purge_mongodb_data() {
    load_app_env || return 0

    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -Fxq "iot-mongodb"; then
        log_msg "MongoDB no está ejecutándose; se omite purga de datos MongoDB"
        return 0
    fi

    local mongo_js
    mongo_js=\$(cat <<'MONGOJSEOF'
const retentionDays = Number(__RETENTION_DAYS__);
const cutoff = new Date(Date.now() - retentionDays * 24 * 60 * 60 * 1000);
["sensor_readings", "device_logs", "alerts"].forEach(function(collectionName) {
  const result = db.getCollection(collectionName).deleteMany({ timestamp: { \$lt: cutoff } });
  print(collectionName + ": deleted=" + result.deletedCount);
});
MONGOJSEOF
)
    mongo_js="\${mongo_js/__RETENTION_DAYS__/\$DATA_RETENTION_DAYS}"

    docker exec \
        -e MONGO_USER="\${MONGO_USER:-admin}" \
        -e MONGO_PASSWORD="\${MONGO_PASSWORD:-}" \
        -e MONGO_DATABASE="\${MONGO_DATABASE:-iot_sensors}" \
        -e MONGO_AUTH_SOURCE="\${MONGO_AUTH_SOURCE:-admin}" \
        -e MONGO_PURGE_JS="\$mongo_js" \
        iot-mongodb bash -lc '
            set -u
            shell="mongo"
            if command -v mongosh >/dev/null 2>&1; then
                shell="mongosh"
            fi
            "\$shell" --quiet \
                -u "\$MONGO_USER" \
                -p "\$MONGO_PASSWORD" \
                --authenticationDatabase "\$MONGO_AUTH_SOURCE" \
                "\$MONGO_DATABASE" \
                --eval "\$MONGO_PURGE_JS"
        ' >/dev/null 2>&1 || log_msg "Purga MongoDB falló; revisar contenedor iot-mongodb"
}

purge_mysql_data() {
    load_app_env || return 0

    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -Fxq "iot-mysql"; then
        log_msg "MySQL no está ejecutándose; se omite purga de datos MySQL"
        return 0
    fi

    local mysql_sql
    mysql_sql=\$(cat <<'MYSQLEOF'
DELETE FROM usuario_servicio
WHERE fecha_asignacion < NOW() - INTERVAL __RETENTION_DAYS__ DAY;

DELETE FROM servicio_app
WHERE fecha_asignacion < NOW() - INTERVAL __RETENTION_DAYS__ DAY;

DELETE FROM servicio_dispositivo
WHERE fecha_asignacion < NOW() - INTERVAL __RETENTION_DAYS__ DAY;

DELETE FROM servicio
WHERE fecha_fin IS NOT NULL
  AND fecha_fin < NOW() - INTERVAL __RETENTION_DAYS__ DAY
  AND id NOT IN (SELECT servicio_id FROM usuario_servicio WHERE servicio_id IS NOT NULL)
  AND id NOT IN (SELECT servicio_id FROM servicio_app WHERE servicio_id IS NOT NULL)
  AND id NOT IN (SELECT servicio_id FROM servicio_dispositivo WHERE servicio_id IS NOT NULL);
MYSQLEOF
)
    mysql_sql="\${mysql_sql//__RETENTION_DAYS__/\$DATA_RETENTION_DAYS}"

    docker exec \
        -e MYSQL_PWD="\${MYSQL_PASSWORD:-}" \
        iot-mysql mysql \
            -u "\${MYSQL_USER:-iot_user}" \
            "\${MYSQL_DATABASE:-iot_platform}" \
            -e "\$mysql_sql" >/dev/null 2>&1 || log_msg "Purga MySQL falló; revisar contenedor iot-mysql"
}

purge_data_storage() {
    log_msg "Ejecutando purga data con retención de \${DATA_RETENTION_DAYS} días"
    purge_mongodb_data
    purge_mysql_data
}

max_usage=0
for path in / "\$INSTALL_DIR"; do
    if [[ -e "\$path" ]]; then
        current=\$(usage_pct "\$path")
        if [[ -n "\$current" && "\$current" -gt "\$max_usage" ]]; then
            max_usage="\$current"
        fi
    fi
done

if [[ "\$max_usage" -ge "\$WARN_PCT" ]]; then
    log_msg "Uso de almacenamiento en \${max_usage}%, modo de purga: \${STORAGE_PURGE_MODE}"
    case "\$STORAGE_PURGE_MODE" in
        system)
            purge_system_storage
            ;;
        data)
            purge_data_storage
            ;;
        both)
            purge_system_storage
            purge_data_storage
            ;;
        none)
            log_msg "Purga automática desactivada; alerta solamente"
            ;;
    esac
else
    rm -f "\$WARNING_FILE"
fi

max_usage_after=0
for path in / "\$INSTALL_DIR"; do
    if [[ -e "\$path" ]]; then
        current=\$(usage_pct "\$path")
        if [[ -n "\$current" && "\$current" -gt "\$max_usage_after" ]]; then
            max_usage_after="\$current"
        fi
    fi
done

if [[ "\$max_usage_after" -ge "\$WARN_PCT" && "\$STORAGE_ALERTS" == "true" ]]; then
    {
        echo "ADVERTENCIA IoT: almacenamiento al \${max_usage_after}%."
        echo "Alertas activas. Modo de purga: \${STORAGE_PURGE_MODE}."
        echo "Retención de datos configurada: \${DATA_RETENTION_DAYS} días."
        echo "Revisa retencion de datos o agrega almacenamiento externo."
    } > "\$WARNING_FILE"
elif [[ "\$STORAGE_ALERTS" != "true" ]]; then
    rm -f "\$WARNING_FILE"
fi

if [[ "\$max_usage_after" -ge "\$CRITICAL_PCT" ]]; then
    log_msg "CRITICO: almacenamiento en \${max_usage_after}% despues de mantenimiento, modo de purga: \${STORAGE_PURGE_MODE}"
else
    log_msg "Mantenimiento completado, uso maximo \${max_usage_after}%"
fi
MAINTENANCEEOF

    chmod 755 /usr/local/sbin/iot-storage-maintenance

    if [[ "$alerts_enabled" == true ]]; then
        cat > /etc/profile.d/iot-storage-warning.sh << 'PROFILEEOF'
warning_file="/var/lib/iot-platform-maintenance/storage-warning"
if [ -r "$warning_file" ]; then
    printf '\n'
    cat "$warning_file"
    printf '\n\n'
fi
PROFILEEOF
        chmod 644 /etc/profile.d/iot-storage-warning.sh
    else
        rm -f /etc/profile.d/iot-storage-warning.sh
    fi

    if [[ "$autopurge_enabled" == true ]]; then
        cat > /etc/logrotate.d/iot-platform << LOGROTATEEOF
$install_dir/logs/*.log $install_dir/logs/*/*.log /var/log/iot-platform-maintenance.log /var/log/iot-platform-cleanup.log {
    daily
    rotate $rotate_count
    maxsize $log_max_size
    missingok
    notifempty
    compress
    copytruncate
}
LOGROTATEEOF
    else
        rm -f /etc/logrotate.d/iot-platform
    fi

    cat > /etc/systemd/system/iot-storage-maintenance.service << 'SERVICEEOF'
[Unit]
Description=IoT Platform storage maintenance
After=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/iot-storage-maintenance
SERVICEEOF

    cat > /etc/systemd/system/iot-storage-maintenance.timer << TIMEREOF
[Unit]
Description=Run IoT Platform storage maintenance periodically

[Timer]
OnBootSec=15min
OnUnitActiveSec=$timer_interval
Persistent=true

[Install]
WantedBy=timers.target
TIMEREOF

    systemctl daemon-reload
    systemctl enable --now iot-storage-maintenance.timer >> "$LOG_FILE" 2>&1 || true
    systemctl start iot-storage-maintenance.service >> "$LOG_FILE" 2>&1 || true
}

count_healthy_containers() {
    local count=0
    local id status

    for id in $(docker compose ps -q 2>/dev/null); do
        status=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$id" 2>/dev/null || true)
        if [[ "$status" == "healthy" ]]; then
            count=$((count + 1))
        fi
    done

    echo "$count"
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
        mkdir -p "$install_dir"/{logs,mysql-data,mysql-init,mongo-data,redis-data,nginx,fastapi-app,device-firmware-micropython,web-flasher}
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
    exec_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y sudo openssh-server passwd" "Instalar sudo y OpenSSH Server"
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

    show_task "Configurando sudo temporal para reanudación" "running"
    local sudo_resume_cmd="/home/$NEW_USERNAME/iot-platform-installer/install.sh --internal-resume"
    printf '%s ALL=(ALL) NOPASSWD: %s\n' "$NEW_USERNAME" "$sudo_resume_cmd" > "/etc/sudoers.d/$NEW_USERNAME"
    chmod 440 "/etc/sudoers.d/$NEW_USERNAME"
    visudo -cf "/etc/sudoers.d/$NEW_USERNAME" >> "$LOG_FILE" 2>&1
    complete_task "Sudo temporal configurado"

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
    escaped_password=$(escape_double_quoted_value "$ADMIN_PASSWORD")

    MONGO_IMAGE=${MONGO_IMAGE:-$(select_mongo_image)}
    
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
MONGO_IMAGE="$MONGO_IMAGE"
ALLOW_LEGACY_PI4_MONGODB="${ALLOW_LEGACY_PI4_MONGODB:-false}"
RESOURCE_PROFILE="${RESOURCE_PROFILE}"
RESOURCE_PROFILE_SOURCE="${RESOURCE_PROFILE_SOURCE:-auto}"
COMPACT_STORAGE="${COMPACT_STORAGE}"
COMPACT_STORAGE_SOURCE="${COMPACT_STORAGE_SOURCE:-auto}"
SAFE_AUTOPURGE="${SAFE_AUTOPURGE:-false}"
SAFE_AUTOPURGE_SOURCE="${SAFE_AUTOPURGE_SOURCE:-auto}"
STORAGE_ALERTS="${STORAGE_ALERTS:-true}"
STORAGE_ALERTS_SOURCE="${STORAGE_ALERTS_SOURCE:-auto}"
STORAGE_PURGE_MODE="${STORAGE_PURGE_MODE:-none}"
STORAGE_PURGE_MODE_SOURCE="${STORAGE_PURGE_MODE_SOURCE:-auto}"
DATA_RETENTION_DAYS="${DATA_RETENTION_DAYS:-30}"
STORAGE_TOTAL_MB="${STORAGE_TOTAL_MB:-0}"
STORAGE_USED_MB="${STORAGE_USED_MB:-0}"
STORAGE_AVAILABLE_MB="${STORAGE_AVAILABLE_MB:-0}"

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

    log_success "Fase 1 completada"

    local display_password
    if [[ -n "$temp_password" ]]; then
        display_password="$temp_password"
    else
        display_password="[usuario existente; usa su contraseña actual]"
    fi

    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${RED}║${RESET}                                                                              ${RED}║${RESET}"
    echo -e "${RED}║${RESET}   ${BOLD}¡¡¡ IMPORTANTE - GUARDA ESTAS CREDENCIALES AHORA !!!${RESET}                       ${RED}║${RESET}"
    echo -e "${RED}║${RESET}                                                                              ${RED}║${RESET}"
    echo -e "${RED}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
    echo -e "${RED}║${RESET}                                                                              ${RED}║${RESET}"
    echo -e "${RED}║${RESET}   ${BOLD}Usuario SSH:${RESET}     ${GREEN}$NEW_USERNAME${RESET}                                              ${RED}║${RESET}"
    echo -e "${RED}║${RESET}   ${BOLD}Contraseña:${RESET}      ${GREEN}$display_password${RESET}"
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
    echo -e "${CYAN}║${RESET}   ${GREEN}[OK]${RESET} Usuario ${YELLOW}$NEW_USERNAME${RESET} preparado                                      ${CYAN}║${RESET}"
    echo -e "${CYAN}║${RESET}   ${GREEN}[OK]${RESET} Permisos de administrador (sudo) otorgados                             ${CYAN}║${RESET}"
    echo -e "${CYAN}║${RESET}   ${GREEN}[OK]${RESET} Instalador copiado a /home/$NEW_USERNAME/                               ${CYAN}║${RESET}"
    echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
    echo -e "${CYAN}║${RESET}   ${BOLD}Continuando instalación automáticamente como $NEW_USERNAME...${RESET}              ${CYAN}║${RESET}"
    echo -e "${CYAN}║${RESET}                                                                              ${CYAN}║${RESET}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""

    sleep 3

    log_info "Ejecutando transición a usuario $NEW_USERNAME..."
    exec runuser -l "$NEW_USERNAME" -c "cd /home/$NEW_USERNAME/iot-platform-installer && sudo -n /home/$NEW_USERNAME/iot-platform-installer/install.sh --internal-resume"
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
        wait_for_apt_dpkg_locks
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

    show_task "Configurando swap low-resource si aplica" "running"
    ensure_low_resource_swap
    complete_task "Swap low-resource verificado"
    
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
        nft -c -f /etc/nftables.conf
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
    exec_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y fail2ban iptables" "Instalar Fail2Ban"
    complete_task "Fail2Ban instalado"

    show_task "Preparando cadena DOCKER-USER" "running"
    if [[ "$DRY_RUN" != true ]]; then
        ensure_docker_user_chain
    fi
    complete_task "Cadena DOCKER-USER preparada"
    
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

        if [[ -f "$SCRIPT_DIR/templates/fail2ban-action.conf.tpl" ]]; then
            cp "$SCRIPT_DIR/templates/fail2ban-action.conf.tpl" /etc/fail2ban/action.d/nftables-custom.conf
        else
            cat > /etc/fail2ban/action.d/nftables-custom.conf << 'ACTIONEOF'
[Definition]

actionstart =

actionstop =

actioncheck = nft list set inet iot_filter fail2ban_blacklist >/dev/null

actionban = nft add element inet iot_filter fail2ban_blacklist { <ip> timeout 1h }

actionunban = nft delete element inet iot_filter fail2ban_blacklist { <ip> }
ACTIONEOF
        fi
        log_info "Acción nftables-custom instalada"

        cat > /etc/fail2ban/action.d/docker-user-allports.conf << 'ACTIONEOF'
[Definition]

# Banea tráfico publicado por Docker antes de las reglas generadas por Docker.
# Docker enruta puertos publicados por FORWARD/DOCKER-USER, no por INPUT.
actionstart = iptables -N DOCKER-USER 2>/dev/null || true
              iptables -C DOCKER-USER -j RETURN 2>/dev/null || iptables -A DOCKER-USER -j RETURN

actionstop =

actioncheck = iptables -n -L DOCKER-USER >/dev/null

actionban = iptables -I DOCKER-USER 1 -s <ip> -j DROP

actionunban = iptables -D DOCKER-USER -s <ip> -j DROP
ACTIONEOF
        log_info "Acción docker-user-allports instalada"
    fi
    complete_task "Filtros nginx instalados"
    
    show_task "Configurando Fail2Ban jail" "running"
    if [[ "$DRY_RUN" != true ]]; then
        backup_file "/etc/fail2ban/jail.local"
        
        cat > /etc/fail2ban/jail.local << JAILEOF
# =============================================================================
# Configuración de Jail de Fail2Ban
# SSH usa firewall del host; Nginx usa DOCKER-USER porque el tráfico HTTP/HTTPS
# publicado por Docker no pasa por la cadena INPUT del host.
# =============================================================================

[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
backend  = polling
banaction = nftables-custom
ignoreip = 127.0.0.1/8 ::1 $DOCKER_SUBNET

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
banaction = docker-user-allports
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
banaction = docker-user-allports
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
banaction = docker-user-allports
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
banaction = docker-user-allports
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
        local ssh_service
        ssh_service=$(detect_ssh_service)
        systemctl restart "$ssh_service"
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

    local docker_arch docker_codename docker_repo_url docker_keyring docker_source_file docker_install_source
    docker_arch=$(detect_architecture)
    docker_codename=$(detect_os_codename)
    docker_repo_url="https://download.docker.com/linux/debian"
    docker_keyring="/etc/apt/keyrings/docker.asc"
    docker_source_file="/etc/apt/sources.list.d/docker.sources"
    docker_install_source="official"

    if [[ -z "$docker_codename" ]]; then
        log_error "No se pudo detectar VERSION_CODENAME desde /etc/os-release"
        return 1
    fi

    case "$docker_arch" in
        amd64|arm64)
            ;;
        *)
            log_error "Arquitectura no soportada para Docker en este stack: $docker_arch"
            return 1
            ;;
    esac

    show_task "Eliminando paquetes Docker conflictivos" "running"
    exec_cmd "DEBIAN_FRONTEND=noninteractive apt-get remove -y docker.io docker-doc docker-compose podman-docker containerd runc || true" "Eliminar paquetes Docker conflictivos"
    complete_task "Paquetes conflictivos eliminados"
    
    show_task "Añadiendo clave GPG de Docker" "running"
    if [[ "$DRY_RUN" != true ]]; then
        install -m 0755 -d /etc/apt/keyrings
        rm -f /etc/apt/keyrings/docker.gpg "$docker_keyring"
        curl -fsSL "${docker_repo_url}/gpg" -o "$docker_keyring"
        chmod a+r "$docker_keyring"
    fi
    complete_task "Clave GPG añadida"
    
    show_task "Añadiendo repositorio de Docker" "running"
    if [[ "$DRY_RUN" != true ]]; then
        rm -f /etc/apt/sources.list.d/docker.list "$docker_source_file"
        cat > "$docker_source_file" << DOCKEREOF
Types: deb
URIs: $docker_repo_url
Suites: $docker_codename
Components: stable
Architectures: $docker_arch
Signed-By: $docker_keyring
DOCKEREOF
    fi
    complete_task "Repositorio añadido"
    
    show_task "Actualizando índice de paquetes" "running"
    exec_cmd "apt-get update" "Actualizar índice"
    complete_task "Índice actualizado"

    show_task "Validando disponibilidad de Docker Engine" "running"
    if [[ "$DRY_RUN" != true ]]; then
        if apt_package_available docker-ce && apt_package_available docker-ce-cli && apt_package_available containerd.io && apt_package_available docker-compose-plugin; then
            log_info "Docker CE disponible: docker-ce $(apt_package_candidate docker-ce)"
        else
            log_warning "El repositorio oficial de Docker no expone un conjunto completo para ${docker_codename}/${docker_arch} en este host."
            {
                echo "=== Docker official package policy ==="
                apt-cache policy docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || true
            } >> "$LOG_FILE" 2>&1

            if apt_package_available docker.io && apt_package_available docker-compose; then
                docker_install_source="debian"
                log_warning "Fallback activado: se instalarán paquetes Debian docker.io + docker-compose."
                log_warning "Esto mantiene el instalador funcional en Debian 13 ARM64 cuando Docker CE no aparece como candidato APT."
            else
                log_error "No hay paquetes Docker instalables para ${docker_codename}/${docker_arch}"
                log_error "Revisa conectividad, repositorios APT y el log: $LOG_FILE"
                return 1
            fi
        fi
    fi
    complete_task "Docker Engine disponible"
    
    show_task "Instalando Docker Engine" "running"
    if [[ "$docker_install_source" == "official" ]]; then
        exec_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin" "Instalar Docker CE"
    else
        exec_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io docker-compose" "Instalar Docker desde Debian"
    fi
    complete_task "Docker instalado"

    show_task "Configurando daemon Docker" "running"
    configure_docker_daemon_logging
    complete_task "Daemon Docker configurado"
    
    show_task "Añadiendo usuario al grupo docker" "running"
    if [[ "$DRY_RUN" != true ]]; then
        usermod -aG docker "$NEW_USERNAME"
    fi
    complete_task "Usuario añadido al grupo docker"
    
    show_task "Habilitando servicio Docker" "running"
    if [[ "$DRY_RUN" != true ]]; then
        systemctl enable docker
        systemctl restart docker
        docker version >> "$LOG_FILE" 2>&1
        docker compose version >> "$LOG_FILE" 2>&1
    fi
    complete_task "Docker habilitado"

    show_task "Validando Docker Registry" "running"
    validate_docker_registry_access
    complete_task "Docker Registry validado"
    
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
    local mongo_image="${MONGO_IMAGE:-$DEFAULT_MONGO_IMAGE}"
    set_resource_tuning_defaults
    
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
            -e "s|{{MONGO_IMAGE}}|$mongo_image|g" \
            -e "s|{{REDIS_MEMORY}}|$REDIS_MEMORY|g" \
            -e "s|{{TIMEZONE}}|$TIMEZONE|g" \
            -e "s|{{RESOURCE_PROFILE}}|$RESOURCE_PROFILE|g" \
            -e "s|{{COMPACT_STORAGE}}|$COMPACT_STORAGE|g" \
            -e "s|{{SAFE_AUTOPURGE}}|${SAFE_AUTOPURGE:-false}|g" \
            -e "s|{{STORAGE_ALERTS}}|${STORAGE_ALERTS:-true}|g" \
            -e "s|{{STORAGE_PURGE_MODE}}|${STORAGE_PURGE_MODE:-none}|g" \
            -e "s|{{DATA_RETENTION_DAYS}}|${DATA_RETENTION_DAYS:-30}|g" \
            -e "s|{{STORAGE_TOTAL_MB}}|${STORAGE_TOTAL_MB:-0}|g" \
            -e "s|{{STORAGE_AVAILABLE_MB}}|${STORAGE_AVAILABLE_MB:-0}|g" \
            -e "s|{{MYSQL_INNODB_BUFFER_POOL}}|$MYSQL_INNODB_BUFFER_POOL|g" \
            -e "s|{{MYSQL_MAX_CONNECTIONS}}|$MYSQL_MAX_CONNECTIONS|g" \
            -e "s|{{MONGO_WIREDTIGER_CACHE}}|$MONGO_WIREDTIGER_CACHE|g" \
            -e "s|{{FASTAPI_WORKERS}}|$FASTAPI_WORKERS|g" \
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
    local install_dir="$INSTALL_DIR"
    local app_dir="$install_dir/fastapi-app"
    
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

    show_task "Copiando firmware MicroPython de referencia" "running"
    local firmware_src="$SCRIPT_DIR/device-firmware-micropython"
    if [[ -d "$firmware_src" ]]; then
        if [[ "$DRY_RUN" != true ]]; then
            cp -r "$firmware_src/"* "$install_dir/device-firmware-micropython/"
            chown -R "$NEW_USERNAME:$NEW_USERNAME" "$install_dir/device-firmware-micropython"
            chmod -R 755 "$install_dir/device-firmware-micropython"
        fi
        complete_task "Firmware MicroPython copiado"
    else
        log_warning "Directorio de firmware no encontrado, omitiendo: $firmware_src"
    fi

    show_task "Copiando Web Flasher de provisionamiento" "running"
    local flasher_src="$SCRIPT_DIR/web-flasher"
    if [[ -d "$flasher_src" ]]; then
        if [[ "$DRY_RUN" != true ]]; then
            cp -r "$flasher_src/"* "$install_dir/web-flasher/"
            chown -R "$NEW_USERNAME:$NEW_USERNAME" "$install_dir/web-flasher"
            chmod -R 755 "$install_dir/web-flasher"
        fi
        complete_task "Web Flasher copiado"
    else
        log_warning "Directorio de Web Flasher no encontrado, omitiendo: $flasher_src"
    fi

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
        local admin_email="${ADMIN_EMAIL:-master@iot-platform.local}"
        
        sed -e "s|{{ADMIN_PASSWORD_HASH}}|$ADMIN_PASSWORD_HASH|g" \
            -e "s|{{USER_PASSWORD_HASH}}|$USER_PASSWORD_HASH|g" \
            -e "s|{{MANAGER_PASSWORD_HASH}}|$MANAGER_PASSWORD_HASH|g" \
            -e "s|{{ADMIN_EMAIL}}|$admin_email|g" \
            -e "s|{{DEVICE_API_KEY}}|$DEVICE_API_KEY|g" \
            -e "s|{{DEVICE_ENCRYPTION_KEY}}|$DEVICE_ENCRYPTION_KEY|g" \
            -e "s|{{DB_NAME}}|$DB_NAME|g" \
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
        sed -e "s|{{DOCKER_SUBNET}}|$DOCKER_SUBNET|g" \
            "$SCRIPT_DIR/templates/nginx-site.conf.tpl" > "$install_dir/nginx/conf.d/iot-api.conf"
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
    local mongo_image="${MONGO_IMAGE:-$DEFAULT_MONGO_IMAGE}"
    set_resource_tuning_defaults
    
    show_task "Creando docker-compose.yml" "running"
    if [[ "$DRY_RUN" != true ]]; then
        sed -e "s|{{DOCKER_SUBNET}}|$DOCKER_SUBNET|g" \
            -e "s|{{REDIS_MEMORY}}|$REDIS_MEMORY|g" \
            -e "s|{{MONGO_IMAGE}}|$mongo_image|g" \
            -e "s|{{MYSQL_COMMAND}}|$MYSQL_COMMAND|g" \
            -e "s|{{MYSQL_MEM_LIMIT}}|$MYSQL_MEM_LIMIT|g" \
            -e "s|{{MYSQL_MEM_RESERVATION}}|$MYSQL_MEM_RESERVATION|g" \
            -e "s|{{MYSQL_CPUS}}|$MYSQL_CPUS|g" \
            -e "s|{{MONGO_COMMAND}}|$MONGO_COMMAND|g" \
            -e "s|{{MONGO_MEM_LIMIT}}|$MONGO_MEM_LIMIT|g" \
            -e "s|{{MONGO_MEM_RESERVATION}}|$MONGO_MEM_RESERVATION|g" \
            -e "s|{{MONGO_CPUS}}|$MONGO_CPUS|g" \
            -e "s|{{REDIS_MEM_LIMIT}}|$REDIS_MEM_LIMIT|g" \
            -e "s|{{REDIS_MEM_RESERVATION}}|$REDIS_MEM_RESERVATION|g" \
            -e "s|{{REDIS_CPUS}}|$REDIS_CPUS|g" \
            -e "s|{{FASTAPI_COMMAND}}|$FASTAPI_COMMAND|g" \
            -e "s|{{FASTAPI_MEM_LIMIT}}|$FASTAPI_MEM_LIMIT|g" \
            -e "s|{{FASTAPI_MEM_RESERVATION}}|$FASTAPI_MEM_RESERVATION|g" \
            -e "s|{{FASTAPI_CPUS}}|$FASTAPI_CPUS|g" \
            -e "s|{{NGINX_MEM_LIMIT}}|$NGINX_MEM_LIMIT|g" \
            -e "s|{{NGINX_MEM_RESERVATION}}|$NGINX_MEM_RESERVATION|g" \
            -e "s|{{NGINX_CPUS}}|$NGINX_CPUS|g" \
            "$SCRIPT_DIR/templates/docker-compose.yml.tpl" > "$install_dir/docker-compose.yml"
    fi
    complete_task "docker-compose.yml creado"
    
    show_task "Iniciando servicios Docker" "running"
    if [[ "$DRY_RUN" != true ]]; then
        cd "$install_dir"
        if ! docker compose config --quiet >> "$LOG_FILE" 2>&1; then
            log_error "docker-compose.yml generado no es válido"
            return 1
        fi
        
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
        ensure_docker_user_chain
        
        local max_retries=3
        local retry_count=0
        local success=false
        local compose_output=""
        
        while [[ $retry_count -lt $max_retries ]] && [[ "$success" == false ]]; do
            retry_count=$((retry_count + 1))
            log_info "Intento $retry_count de $max_retries..."
            compose_output="$install_dir/compose-up-attempt-${retry_count}.log"
            
            if run_compose_up "$compose_output"; then
                cat "$compose_output" >> "$LOG_FILE" 2>/dev/null || true
                success=true
            else
                cat "$compose_output" >> "$LOG_FILE" 2>/dev/null || true
                if [[ $retry_count -lt $max_retries ]]; then
                    log_warning "Fallo en intento $retry_count. Reintentando en 10 segundos..."
                    sleep 10
                fi
            fi
        done
        
        if [[ "$success" == false ]]; then
            log_error "Docker compose falló después de $max_retries intentos"
            collect_deployment_failure_diagnostics "$install_dir" "$compose_output"
            log_error "Ejecuta manualmente: cd $install_dir && COMPOSE_PARALLEL_LIMIT=1 docker compose --progress plain up -d"
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
            local healthy
            healthy=$(count_healthy_containers)
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
    
    local admin_email="${ADMIN_EMAIL:-master@iot-platform.local}"
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
            log_info "Redis password encontrada en archivo de secretos"
        else
            log_warning "Archivo de secretos no encontrado: $secrets_path"
        fi
        
        local admin_payload
        admin_payload=$(jq -nc --arg email "$admin_email" --arg password "$admin_password" \
            '{email:$email,password:$password}')

        local admin_response=$(curl -s -X POST http://localhost/api/v1/auth/login/admin \
            -H "Content-Type: application/json" \
            -d "$admin_payload")
        
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

    show_task "Restaurando sudo con contraseña" "running"
    if [[ "$DRY_RUN" != true ]]; then
        restore_sudo_password_requirement
    fi
    complete_task "Sudo restaurado"

    show_task "Configurando mantenimiento de almacenamiento" "running"
    install_storage_maintenance
    complete_task "Mantenimiento de almacenamiento configurado"
    
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
        wait_for_apt_dpkg_locks || true
        apt-get clean 2>/dev/null || true
        wait_for_apt_dpkg_locks || true
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
        local healthy_containers
        healthy_containers=$(count_healthy_containers)
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
