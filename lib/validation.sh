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

# Validar subred CIDR
validate_subnet() {
    local subnet=$1
    
    # Formato: x.x.x.x/y
    if [[ ! $subnet =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        log_error "Formato de subred inválido: $subnet"
        log_error "Use formato CIDR: 172.20.0.0/16"
        return 1
    fi
    
    # Extraer IP y máscara
    local ip=${subnet%/*}
    local mask=${subnet#*/}
    
    # Validar IP
    validate_ip "$ip" || return 1
    
    # Validar máscara
    if [[ $mask -lt 8 ]] || [[ $mask -gt 30 ]]; then
        log_error "La máscara de subred debe estar entre 8 y 30"
        return 1
    fi
    
    return 0
}

# Validar dirección de correo electrónico
validate_email() {
    local email=$1
    
    # Verificar longitud mínima
    if [[ ${#email} -lt 5 ]]; then
        log_error "El correo electrónico es demasiado corto"
        return 1
    fi
    
    # Verificar longitud máxima (RFC 5321)
    if [[ ${#email} -gt 254 ]]; then
        log_error "El correo electrónico es demasiado largo (máximo 254 caracteres)"
        return 1
    fi
    
    # Regex básico para validar formato de email
    # Formato: parte_local@dominio.tld
    if [[ ! $email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        log_error "Formato de correo electrónico inválido: $email"
        log_error "Use formato: usuario@dominio.com"
        return 1
    fi
    
    return 0
}

# Validar contraseña (fortaleza básica)
validate_password() {
    local password=$1
    local min_length=${2:-8}
    
    # Verificar longitud mínima
    if [[ ${#password} -lt $min_length ]]; then
        log_error "La contraseña debe tener al menos $min_length caracteres"
        return 1
    fi
    
    # Verificar longitud máxima (para evitar problemas de hash)
    if [[ ${#password} -gt 128 ]]; then
        log_error "La contraseña es demasiado larga (máximo 128 caracteres)"
        return 1
    fi
    
    # Advertir si es muy simple (solo advertencia, no bloqueo)
    if [[ "$password" == "password" ]] || [[ "$password" == "12345678" ]] || [[ "$password" == "password123" ]]; then
        log_warning "La contraseña elegida es muy común y fácil de adivinar"
        log_warning "Se recomienda usar una contraseña más fuerte"
    fi
    
    return 0
}

# Validar que un archivo exista
validate_file_exists() {
    local filepath=$1
    
    if [[ ! -f "$filepath" ]]; then
        log_error "Archivo no encontrado: $filepath"
        return 1
    fi
    
    return 0
}

# Validar que un directorio exista
validate_dir_exists() {
    local dirpath=$1
    
    if [[ ! -d "$dirpath" ]]; then
        log_error "Directorio no encontrado: $dirpath"
        return 1
    fi
    
    return 0
}

# Validar comando disponible
validate_command() {
    local cmd=$1
    
    if ! command -v "$cmd" &> /dev/null; then
        log_error "Comando no encontrado: $cmd"
        return 1
    fi
    
    return 0
}
