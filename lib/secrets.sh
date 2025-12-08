#!/bin/bash
################################################################################
# lib/secrets.sh - Funciones de generación de secretos (soporte Argon2)
################################################################################

# Generar todos los secretos
generate_all_secrets() {
    log_info "Generando secretos seguros..."
    
    # Crear directorio de secretos
    local secrets_dir=$(dirname "$SECRETS_FILE")
    mkdir -p "$secrets_dir"
    chmod 700 "$secrets_dir"
    
    # Generar contraseñas (32 bytes base64)
    export MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
    export MYSQL_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
    export REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
    export MONGO_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
    
    # Generar clave secreta JWT (64 caracteres hex)
    export SECRET_KEY=$(openssl rand -hex 32)
    
    # Generar claves de cifrado de dispositivo
    export DEVICE_ENCRYPTION_KEY=$(openssl rand -hex 32)
    
    # Guardar en archivo
    cat > "$SECRETS_FILE" << EOF
# Secretos de Plataforma IoT
# Generado: $(date)
# CRÍTICO: ¡Respalda este archivo y manténlo seguro!

# Contraseñas de Base de Datos
MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD"
MYSQL_PASSWORD="$MYSQL_PASSWORD"
REDIS_PASSWORD="$REDIS_PASSWORD"
MONGO_PASSWORD="$MONGO_PASSWORD"

# Clave Secreta JWT (HS256)
SECRET_KEY="$SECRET_KEY"

# Clave de Cifrado de Dispositivo (32 bytes hex)
DEVICE_ENCRYPTION_KEY="$DEVICE_ENCRYPTION_KEY"

# Algoritmos
ALGORITHM="HS256"
ACCESS_TOKEN_EXPIRE_MINUTES="60"
EOF
    
    chmod 600 "$SECRETS_FILE"
    
    log_success "Secretos generados y guardados en: $SECRETS_FILE"
    log_warning "¡RESPALDA ESTE ARCHIVO - No puedes recuperar las contraseñas si se pierde!"
}

# Generar hash Argon2 (para datos de prueba)
hash_password_argon2() {
    local password=$1
    python3 -c "
from passlib.context import CryptContext
pwd_context = CryptContext(
    schemes=['argon2'],
    deprecated='auto',
    argon2__memory_cost=102400,
    argon2__time_cost=2,
    argon2__parallelism=8
)
print(pwd_context.hash('$password'))
"
}

# Generar hashes Argon2 para usuarios de prueba
generate_test_password_hashes() {
    log_info "Generando hashes de contraseña Argon2 para usuarios de prueba..."
    
    # Instalar argon2-cffi si no está disponible
    if ! python3 -c "import argon2" 2>/dev/null; then
        log_info "Instalando argon2-cffi..."
        pip3 install --break-system-packages argon2-cffi passlib 2>&1 | tee -a "$LOG_FILE"
    fi
    
    # Generar hashes con Argon2
    # Admin Master: password123
    export ADMIN_PASSWORD_HASH=$(hash_password_argon2 "password123")
    
    # Gerente: password123
    export MANAGER_PASSWORD_HASH=$(hash_password_argon2 "password123")
    
    # Usuario: password123
    export USER_PASSWORD_HASH=$(hash_password_argon2 "password123")
    
    log_success "Hashes de contraseña Argon2 generados"
}

# Generar API key para dispositivo
generate_device_api_key() {
    local length=${1:-32}
    openssl rand -base64 $length | tr -d "=+/" | cut -c1-$length
}

# Mostrar secretos (enmascarados)
show_secrets_summary() {
    echo ""
    echo -e "${BOLD}Secretos Generados:${RESET}"
    echo "──────────────────────────────────────────────────"
    echo "MySQL Root:    ${MYSQL_ROOT_PASSWORD:0:8}...${MYSQL_ROOT_PASSWORD: -4}"
    echo "MySQL User:    ${MYSQL_PASSWORD:0:8}...${MYSQL_PASSWORD: -4}"
    echo "Redis:         ${REDIS_PASSWORD:0:8}...${REDIS_PASSWORD: -4}"
    echo "MongoDB:       ${MONGO_PASSWORD:0:8}...${MONGO_PASSWORD: -4}"
    echo "JWT Secret:    ${SECRET_KEY:0:16}...${SECRET_KEY: -8}"
    echo ""
    echo -e "${YELLOW}Secretos completos guardados en: $SECRETS_FILE${RESET}"
    echo ""
}

# Validar fortaleza del secreto
validate_secret_strength() {
    local secret=$1
    local min_length=${2:-32}
    
    if [[ ${#secret} -lt $min_length ]]; then
        log_error "Secreto muy corto: ${#secret} caracteres (mínimo: $min_length)"
        return 1
    fi
    
    return 0
}

# Exportar secretos al entorno
export_secrets() {
    if [[ -f "$SECRETS_FILE" ]]; then
        source "$SECRETS_FILE"
        log_debug "Secretos cargados desde $SECRETS_FILE"
    else
        log_error "Archivo de secretos no encontrado: $SECRETS_FILE"
        return 1
    fi
}
