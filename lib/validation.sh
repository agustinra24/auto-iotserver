#!/bin/bash
################################################################################
# lib/validation.sh - Funciones de validación de entrada
################################################################################

# Validar dirección IP
validate_ip() {
    local ip=$1
    
    # Regex IPv4
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        # Verificar que cada octeto sea 0-255
        local IFS='.'
        local -a octets=($ip)
        for octet in "${octets[@]}"; do
            if [[ $octet -gt 255 ]]; then
                log_error "Dirección IP inválida: $ip (octeto > 255)"
                return 1
            fi
        done
        return 0
    else
        log_error "Formato de dirección IP inválido: $ip"
        return 1
    fi
}

# Validar nombre de usuario
validate_username() {
    local username=$1
    
    # Verificar longitud
    if [[ ${#username} -lt 3 ]] || [[ ${#username} -gt 32 ]]; then
        log_error "El nombre de usuario debe tener 3-32 caracteres"
        return 1
    fi
    
    # Verificar formato (alfanumérico, guión bajo, guión)
    if [[ ! $username =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        log_error "El nombre de usuario debe comenzar con letra minúscula o guión bajo"
        log_error "Solo puede contener letras minúsculas, números, guión bajo, guión"
        return 1
    fi
    
    # Verificar nombres reservados
    local reserved_names=("root" "admin" "administrator" "system" "daemon" "bin" "sys")
    for reserved in "${reserved_names[@]}"; do
        if [[ "$username" == "$reserved" ]]; then
            log_error "El nombre de usuario '$username' está reservado"
            return 1
        fi
    done
    
    return 0
}

# Validar número de puerto
validate_port() {
    local port=$1
    
    if [[ ! $port =~ ^[0-9]+$ ]]; then
        log_error "El puerto debe ser un número"
        return 1
    fi
    
    if [[ $port -lt 1 ]] || [[ $port -gt 65535 ]]; then
        log_error "El puerto debe estar entre 1 y 65535"
        return 1
    fi
    
    # Advertir sobre puertos comunes
    if [[ $port -eq 22 ]]; then
        log_warning "El puerto 22 es el puerto SSH por defecto"
        log_warning "Se recomienda usar un puerto personalizado como 5259"
    fi
    
    if [[ $port -lt 1024 ]]; then
        log_warning "El puerto $port está en el rango privilegiado (< 1024)"
    fi
    
    return 0
}

# Validar nombre de base de datos
validate_db_name() {
    local db_name=$1
    
    # Verificar longitud
    if [[ ${#db_name} -lt 1 ]] || [[ ${#db_name} -gt 64 ]]; then
        log_error "El nombre de base de datos debe tener 1-64 caracteres"
        return 1
    fi
    
    # Verificar formato (solo alfanumérico y guión bajo)
    if [[ ! $db_name =~ ^[a-zA-Z0-9_]+$ ]]; then
        log_error "El nombre de base de datos solo puede contener letras, números y guiones bajos"
        return 1
    fi
    
    # No puede comenzar con número
    if [[ $db_name =~ ^[0-9] ]]; then
        log_error "El nombre de base de datos no puede comenzar con un número"
        return 1
    fi
    
    return 0
}

# Validar subred
validate_subnet() {
    local subnet=$1
    
    # Verificar formato CIDR
    if [[ ! $subnet =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        log_error "Formato de subred inválido. Esperado: x.x.x.x/y"
        return 1
    fi
    
    # Extraer IP y máscara
    local ip="${subnet%/*}"
    local mask="${subnet#*/}"
    
    # Validar parte de IP
    validate_ip "$ip" || return 1
    
    # Validar máscara
    if [[ $mask -lt 8 ]] || [[ $mask -gt 32 ]]; then
        log_error "La máscara de subred debe estar entre /8 y /32"
        return 1
    fi
    
    return 0
}

# Validar nombre de dominio
validate_domain() {
    local domain=$1
    
    # Permitir "none" o vacío
    if [[ -z "$domain" ]] || [[ "$domain" == "none" ]]; then
        return 0
    fi
    
    # Verificar formato
    if [[ ! $domain =~ ^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
        log_error "Formato de dominio inválido"
        return 1
    fi
    
    return 0
}

# Validar tamaño de memoria (ej: 256MB, 1GB)
validate_memory_size() {
    local size=$1
    
    if [[ ! $size =~ ^[0-9]+[MG]B$ ]]; then
        log_error "Tamaño de memoria inválido. Formato esperado: 256MB o 1GB"
        return 1
    fi
    
    return 0
}

# Validar zona horaria
validate_timezone() {
    local tz=$1
    
    if [[ ! -f "/usr/share/zoneinfo/$tz" ]]; then
        log_warning "Zona horaria '$tz' no encontrada en la base de datos del sistema"
        log_warning "Usando UTC en su lugar"
        return 1
    fi
    
    return 0
}

# Verificar si el usuario existe
user_exists() {
    local username=$1
    id -u "$username" &>/dev/null
}

# Verificar si el puerto está en uso
port_in_use() {
    local port=$1
    ss -tlnp | grep -q ":${port} "
}

# Validar acceso SSH
validate_ssh_access() {
    local user=$1
    local host=$2
    local port=$3
    local timeout=${4:-5}
    
    log_info "Probando acceso SSH: $user@$host:$port"
    
    if timeout $timeout ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -p "$port" "$user@$host" "exit" 2>/dev/null; then
        log_success "Acceso SSH validado"
        return 0
    else
        log_error "No se puede conectar vía SSH"
        return 1
    fi
}

# Validar que el sistema cumple los requisitos mínimos
validate_system_requirements() {
    local errors=0
    
    log_info "Validando requisitos del sistema..."
    
    # Verificar RAM
    local total_ram_mb=$(free -m | awk '/^Mem:/ {print $2}')
    if [[ $total_ram_mb -lt 3072 ]]; then
        log_warning "RAM: ${total_ram_mb}MB (recomendado: 4096MB)"
    else
        log_success "RAM: ${total_ram_mb}MB"
    fi
    
    # Verificar espacio en disco
    local avail_disk_gb=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $avail_disk_gb -lt 15 ]]; then
        log_error "Espacio en disco: ${avail_disk_gb}GB (mínimo: 20GB)"
        ((errors++))
    else
        log_success "Espacio en disco: ${avail_disk_gb}GB"
    fi
    
    # Verificar CPU
    local cpu_cores=$(nproc)
    if [[ $cpu_cores -lt 2 ]]; then
        log_warning "Núcleos CPU: $cpu_cores (recomendado: 2+)"
    else
        log_success "Núcleos CPU: $cpu_cores"
    fi
    
    # Verificar internet
    if ! ping -c 1 8.8.8.8 &>/dev/null; then
        log_error "Sin conectividad a internet"
        ((errors++))
    else
        log_success "Conectividad a internet"
    fi
    
    return $errors
}

# Validar archivo de configuración
validate_config() {
    local config_file=$1
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Archivo de configuración no encontrado: $config_file"
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
            log_error "Variable requerida faltante: $var"
            ((errors++))
        fi
    done
    
    return $errors
}

# Validar archivo de secretos
validate_secrets() {
    local secrets_file=$1
    
    if [[ ! -f "$secrets_file" ]]; then
        log_error "Archivo de secretos no encontrado: $secrets_file"
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
            log_error "Secreto faltante: $secret"
            ((errors++))
        fi
    done
    
    # Verificar permisos del archivo
    local perms=$(stat -c '%a' "$secrets_file")
    if [[ "$perms" != "600" ]]; then
        log_warning "El archivo de secretos tiene permisos inseguros: $perms"
        log_warning "Corrigiendo permisos a 600"
        chmod 600 "$secrets_file"
    fi
    
    return $errors
}
