# Plataforma IoT de Prevencion de Incendios - Instalador Automatizado v2.3

Plataforma IoT de prevencion de incendios de grado produccion con **4 tipos de autenticacion**, **puzzles criptograficos para dispositivos**, **datos de sensores en MongoDB** y **aplicacion de sesion unica**.

Construida con **FastAPI**, **MySQL**, **MongoDB**, **Redis**, **Nginx** y **nftables**.

---

## Arquitectura del Sistema

```
INTERNET
    |
    v
+-------------------------------------------------------------+
| CAPA 1: RED (nftables + Fail2Ban)                           |
| - Puertos: {{SSH_PORT}}(SSH), 80(HTTP), 443(HTTPS futuro)   |
| - Rate limiting: 10 req/s                                    |
| - Bloqueo automatico de IP despues de 5 fallos SSH          |
+-------------------------------------------------------------+
    |
    v
+-------------------------------------------------------------+
| CAPA 2: REVERSE PROXY (Nginx 1.25)                          |
| - Rate limiting: 10r/s API, 5r/m Auth                        |
| - Headers de seguridad (XSS, CSRF, Clickjacking)             |
| - Terminacion SSL (futuro)                                   |
+-------------------------------------------------------------+
    |
    v
+-------------------------------------------------------------+
| CAPA 3: APLICACION (FastAPI 0.110.0)                        |
| - 4 tipos de autenticacion + logout                          |
| - Puzzles criptograficos para dispositivos (AES-256 + HMAC-SHA256) |
| - Hashing de contrasenas con Argon2id                        |
| - Aplicacion de sesion unica via Redis                       |
| - Registro de sesiones en CSV                                |
+-------------------------------------------------------------+
    |
    +------------+------------+------------+
    v            v            v            v
+--------+  +--------+  +--------+  +--------+
| MySQL  |  | Redis  |  |MongoDB |  | Logs   |
| :3306* |  | :6379* |  |:27017* |  | /var/  |
| RBAC   |  |Sessions|  |Sensors |  | log/   |
| Users  |  | Cache  |  | ACTIVO |  |fastapi |
+--------+  +--------+  +--------+  +--------+

* Solo red interna de Docker (172.20.0.0/16) - NO expuesto al host
```

---

## Inicio Rapido

### Prerequisitos

```bash
# Requisitos
- VPS Debian 13 (Trixie) limpio
- Acceso root o sudo
- Minimo 4GB RAM, 20GB disco
- Conexion a internet estable
- 2-3 horas de tiempo disponible
- Acceso a consola VPS (respaldo si SSH falla)
```

### Instalacion

```bash
# 1. Descargar y extraer instalador
tar -xzf iot-installer-v2.3.tar.gz
cd iot-platform-installer

# 2. Hacer ejecutable
chmod +x install.sh lib/*.sh

# 3. Vista previa de instalacion (recomendado primero)
sudo ./install.sh --dry-run

# 4. Ejecutar instalacion
sudo ./install.sh
```

### Modos de Ejecucion

|Comando|Comportamiento|
|---|---|
|`sudo ./install.sh`|Menu interactivo con 4 opciones|
|`sudo ./install.sh --dry-run`|Vista previa de pasos, sin cambios al sistema|
|`sudo ./install.sh --resume`|Reanudar desde ultimo checkpoint|

---

## Sistema de Autenticacion (4 Tipos + Logout)

### 1. Autenticacion de Usuario

```bash
POST /api/v1/auth/login/user
Body: {"email": "user@fire.com", "password": "password123"}
Response: {"access_token": "...", "user_id": 1, "role": "user"}
TTL: 60 minutos
```

### 2. Autenticacion de Administrador

```bash
POST /api/v1/auth/login/admin
Body: {"email": "master@fire.com", "password": "password123"}
Response: {"access_token": "...", "admin_id": 1, "role": "admin_master"}
TTL: 60 minutos
```

### 3. Autenticacion de Gerente

```bash
POST /api/v1/auth/login/manager
Body: {"email": "gerente@fire.com", "password": "password123"}
Response: {"access_token": "...", "manager_id": 1, "role": "manager"}
TTL: 60 minutos
```

### 4. Autenticacion de Dispositivo (Puzzle Criptografico)

```bash
POST /api/v1/auth/device/login
Body: {
  "device_id": 1,
  "api_key": "TEST_DEVICE_API_KEY_32_CHARS_XX",
  "puzzle_response": {
    "id_origen": 1,
    "Random dispositivo": "base64...",
    "Parametro de identidad cifrado": {
      "ciphertext": "base64...",
      "iv": "base64..."
    }
  }
}
Response: {"access_token": "...", "device_id": 1}
TTL: 24 horas
```

### 5. Logout

```bash
POST /api/v1/auth/logout
Header: Authorization: Bearer <token>
Response: 204 No Content
```

### Aplicacion de Sesion Unica

```
Intento de login -> Verificar Redis -> Existe sesion?
    |                                      |
    |                      +---------------+---------------+
    |                      |                               |
    |                     SI                              NO
    |                      |                               |
    |                      v                               v
    |              409 Conflict                     Crear JWT
    |              "Ya existe                        con JTI
    |               sesion"                            |
    |                                                  v
    |                                        Almacenar en Redis
    |                                        session:{type}:{id}
    |                                                  |
    +--------------------------------------------------+
```

---

## Datos de Sensores en MongoDB (NUEVO en v2.3)

### Enviar Lecturas de Sensores (Dispositivo)

```bash
POST /api/v1/device/reading
Header: Authorization: Bearer <device_token>
Body: {
  "device_id": 1,
  "temperature": 25.5,
  "smoke_level": 3,
  "battery": 85,
  "location": "Main Hall"
}
Response: {
  "message": "Readings received and saved successfully",
  "readings_count": 3,
  "inserted_ids": ["...", "...", "..."]
}
```

### Consultar Historial de Sensores (Usuario/Admin)

```bash
GET /api/v1/devices/1/readings?sensor_type=temperature&limit=100
Header: Authorization: Bearer <user_token>
Response: {
  "device_id": 1,
  "readings_count": 100,
  "readings": [
    {"sensor_type": "temperature", "value": 25.5, "unit": "°C", ...}
  ]
}
```

### Colecciones de MongoDB

|Coleccion|Proposito|Indices|
|---|---|---|
|`sensor_readings`|Datos de sensores|device_id+timestamp, sensor_type|
|`device_logs`|Actividad de dispositivos|device_id+timestamp|
|`alerts`|Alertas de incendio|device_id+resolved, timestamp|

---

## Endpoints de Prueba (Para Demostraciones)

### Inicializar Clave de Cifrado del Dispositivo

```bash
POST /api/v1/auth/device/init-encryption-key?device_id=1
Response: {
  "message": "Encryption key generated and saved successfully",
  "device_id": 1,
  "key_length": 32,
  "api_key": "TEST_DEVICE_API_KEY_32_CHARS_XX"
}
```

### Generar Puzzle para Pruebas

```bash
POST /api/v1/auth/device/generate-puzzle-test?device_id=1
Response: {
  "message": "Puzzle generated successfully",
  "device_id": 1,
  "api_key": "...",
  "puzzle": {
    "id_origen": 1,
    "Random dispositivo": "...",
    "Parametro de identidad cifrado": {...}
  }
}
```

### Flujo de Pruebas

```
1. POST /device/init-encryption-key?device_id=1
   -> Genera clave de cifrado de 32 bytes

2. POST /device/generate-puzzle-test?device_id=1
   -> Genera puzzle (simula comportamiento del dispositivo)

3. POST /device/login
   -> Usar puzzle del paso 2 en puzzle_response
   -> Recibir token JWT

4. POST /device/reading
   -> Enviar datos de sensores con token del dispositivo
```

---

## Esquema de Base de Datos

### Tablas MySQL (fire_preventionf)

```
+-------------+     +-------------+     +-------------+
|    rol      |     |   permiso   |     | rol_permiso |
|-------------|     |-------------|     |-------------|
| id          |<----|  id         |---->| role_id     |
| nombre      |     | name        |     | permiso_id  |
| description |     | description |     | created_at  |
+-------------+     +-------------+     +-------------+

+-------------+     +-------------+
|  pasadmin   |     |    admin    |
|-------------|     |-------------|
| id          |<----| id          |
| hashed_pass |     | nombre      |
| encrypt_key |     | email       |
+-------------+     | rol_id      |
                    | pasadmin_id |
                    +-------------+

+-------------+     +-------------+
| pasusuario  |     |   usuario   |
|-------------|     |-------------|
| id          |<----| id          |
| hashed_pass |     | nombre      |
| encrypt_key |     | email       |
+-------------+     | is_active   |
                    | rol_id      |
                    | pasusuario_ |
                    +-------------+

+-------------+     +-------------+
| pasgerente  |     |   gerente   |
|-------------|     |-------------|
| id          |<----| id          |
| hashed_pass |     | nombre      |
| encrypt_key |     | email       |
+-------------+     | admin_id    |
                    | pasgerente_ |
                    | rol_id      |
                    +-------------+

+--------------+    +-------------+
|pasdispositivo|    | dispositivo |
|--------------|    |-------------|
| id           |<---| id          |
| api_key      |    | nombre      |
| encrypt_key  |    | device_type |
+--------------+    | is_active   |
                    | admin_id    |
                    | pasdisp_id  |
                    +-------------+
```

### Roles y Permisos por Defecto

|Rol|Permisos|
|---|---|
|`admin_master`|TODOS (16 permisos)|
|`admin_normal`|create_service, assign_device, view_reports, view_all_users|
|`manager`|create_user, create_service, assign_device, view_reports, view_all_users|
|`user`|view_reports, view_all_users|

---

## Caracteristicas de Seguridad

### Hashing de Contrasenas (Argon2id)

```python
# Configuracion
argon2__memory_cost=102400  # 100 MB
argon2__time_cost=2
argon2__parallelism=8

# Formato del hash
$argon2id$v=19$m=102400,t=2,p=8$salt$hash
```

### Autenticacion Criptografica de Dispositivos

```
Fundamento Matematico:

K_HMAC = K_device || K_server
P2 = HMAC-SHA256(K_HMAC, R2)
P2c = AES-256-CBC(P2, K_device, IV)

El dispositivo demuestra posesion de K_device sin transmitirla.
```

### Gestion de Sesiones

```
Claves en Redis:
- session:user:{id} = "jti-uuid"     TTL: 3600s
- session:admin:{id} = "jti-uuid"    TTL: 3600s
- session:manager:{id} = "jti-uuid"  TTL: 3600s
- session:device:{id} = "jti-uuid"   TTL: 86400s
```

### Registro de Sesiones (CSV)

```
Ubicacion: /var/log/fastapi/sessions/sessions_history.csv

Columnas:
timestamp, event, user_id, user_type, email, jti,
ip_address, user_agent, expires_at, reason, endpoint

Eventos: login, login_rejected, logout, expired
```

---

## Estructura del Paquete

```
iot-platform-installer-v2.3/
├── install.sh                    # Instalador principal
├── README.md                     # Este archivo
├── lib/
│   ├── common.sh                 # Logging, utilidades
│   ├── ui.sh                     # Barras de progreso, banners
│   ├── validation.sh             # Validacion de entrada
│   ├── secrets.sh                # Generacion de hash Argon2
│   └── phases.sh                 # 13 fases de instalacion
├── templates/
│   ├── docker-compose.yml.tpl    # Orquestacion Docker
│   ├── env.tpl                   # Variables de entorno
│   ├── mysql-init.sql.tpl        # Esquema de base de datos
│   ├── nftables.conf.tpl         # Reglas de firewall
│   ├── nginx.conf.tpl            # Configuracion principal de Nginx
│   ├── nginx-site.conf.tpl       # Configuracion de sitio Nginx
│   ├── fail2ban-*.tpl            # Configuraciones de Fail2Ban
│   └── fastapi-app/              # Aplicacion FastAPI completa
│       ├── app.py
│       ├── Dockerfile
│       ├── requirements.txt
│       ├── database.py
│       ├── core/
│       │   ├── config.py         # Settings + RedisManager
│       │   ├── security.py       # Argon2 + JWT
│       │   ├── crypto_new.py     # Puzzles de dispositivo
│       │   ├── services.py       # Servicios de Auth + Session
│       │   ├── session_logger.py # Registro CSV
│       │   ├── decorators.py     # Decoradores de validacion
│       │   ├── validators.py     # Validadores regex
│       │   └── utils.py          # ResponseFormatter
│       ├── database/
│       │   ├── __init__.py       # Configuracion SQLAlchemy
│       │   └── mongo.py          # Manager de MongoDB
│       ├── models/               # 14 modelos SQLAlchemy
│       ├── schemas/              # 5 schemas Pydantic
│       └── api/
│           ├── deps.py           # Dependencias de autenticacion
│           └── v1/routers/
│               ├── auth.py       # Login/logout + pruebas
│               ├── users.py      # Gestion de usuarios
│               ├── devices.py    # Gestion de dispositivos
│               ├── sensors.py    # Datos de sensores MongoDB
│               └── alerts.py     # Placeholder
└── logs/                         # Logs de ejecucion
```

---

## Pruebas Post-Instalacion

### 1. Health Check

```bash
curl http://localhost/health
# Esperado: {"status":"healthy"}
```

### 2. Login de Administrador

```bash
curl -X POST http://localhost/api/v1/auth/login/admin \
  -H "Content-Type: application/json" \
  -d '{"email":"master@fire.com","password":"password123"}'
# Esperado: {"access_token":"...","admin_id":1,"role":"admin_master"}
```

### 3. Prueba de Sesion Unica

```bash
# Segundo intento de login (deberia fallar)
curl -X POST http://localhost/api/v1/auth/login/admin \
  -H "Content-Type: application/json" \
  -d '{"email":"master@fire.com","password":"password123"}'
# Esperado: {"detail":"Active session exists..."}
```

### 4. Logout

```bash
curl -X POST http://localhost/api/v1/auth/logout \
  -H "Authorization: Bearer <token>"
# Esperado: 204 No Content
```

### 5. Flujo de Autenticacion de Dispositivo

```bash
# Paso 1: Inicializar clave del dispositivo
curl -X POST "http://localhost/api/v1/auth/device/init-encryption-key?device_id=1"

# Paso 2: Generar puzzle
curl -X POST "http://localhost/api/v1/auth/device/generate-puzzle-test?device_id=1"
# Copiar el objeto puzzle

# Paso 3: Login con puzzle
curl -X POST http://localhost/api/v1/auth/device/login \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": 1,
    "api_key": "TEST_DEVICE_API_KEY_32_CHARS_XX",
    "puzzle_response": <PEGAR_PUZZLE_AQUI>
  }'

# Paso 4: Enviar datos de sensores
curl -X POST http://localhost/api/v1/device/reading \
  -H "Authorization: Bearer <device_token>" \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": 1,
    "temperature": 25.5,
    "smoke_level": 3,
    "battery": 85,
    "location": "Main Hall"
  }'
```

### 6. Aislamiento de Base de Datos

```bash
# Todos deberian FALLAR (conexion rechazada)
nc -zv localhost 3306   # MySQL
nc -zv localhost 6379   # Redis
nc -zv localhost 27017  # MongoDB
```

---

## Stack Tecnologico

|Componente|Version|Proposito|
|---|---|---|
|**SO**|Debian 13 (Trixie)|Base del servidor|
|**Framework**|FastAPI 0.110.0|API asincrona|
|**ORM**|SQLAlchemy 2.0.25|ORM para MySQL|
|**RDBMS**|MySQL 8.0|Datos relacionales|
|**NoSQL**|MongoDB 7.0|Datos de sensores (ACTIVO)|
|**Cache**|Redis 7|Sesiones + cache|
|**Proxy**|Nginx 1.25|Reverse proxy|
|**Firewall**|nftables|Control de trafico|
|**IDS**|Fail2Ban|Proteccion SSH|
|**Hashing**|Argon2id|Hashing de contrasenas|
|**Cifrado**|AES-256-CBC|Claves de dispositivos|
|**HMAC**|SHA-256|Puzzles de dispositivos|

---

## Solucion de Problemas

### Problema: "Argon2 hash verification failed"

**Causa**: La contrasena fue hasheada con bcrypt, no con Argon2

**Solucion**:

```bash
# Regenerar hash de contrasena
python3 -c "
from passlib.context import CryptContext
ctx = CryptContext(schemes=['argon2'])
print(ctx.hash('password123'))
"
# Actualizar en MySQL
```

### Problema: "MongoDB connection failed"

**Causa**: MongoDB no esta saludable o problemas de autenticacion

**Solucion**:

```bash
docker logs iot-mongodb
# Verificar errores de autenticacion
# Verificar que MONGO_PASSWORD en .env coincida
```

### Problema: "Session invalid or closed"

**Causa**: El token fue invalidado (logout) o expiro

**Solucion**:

```bash
# Hacer login nuevamente para obtener nuevo token
curl -X POST http://localhost/api/v1/auth/login/admin ...
```

### Problema: "Device puzzle verification failed"

**Causa**: Discrepancia en encryption_key o server_key cambio

**Solucion**:

```bash
# Reinicializar clave del dispositivo
curl -X POST "http://localhost/api/v1/auth/device/init-encryption-key?device_id=1"
# Generar nuevo puzzle e intentar de nuevo
```

---

## Lista de Verificacion Post-Instalacion

### Inmediato

- Cambiar contrasenas por defecto (master@fire.com, etc.)
- Probar los 4 tipos de autenticacion
- Verificar aplicacion de sesion unica
- Probar endpoint de sensores del dispositivo
- Respaldar archivo de secretos

### Corto Plazo

- Configurar SSL/TLS (Let's Encrypt)
- Configurar respaldos automatizados
- Configurar monitoreo
- Revisar logs de sesiones
- Crear runbook operacional

### Mediano Plazo

- Implementar alertas (Prometheus/Grafana)
- Configurar agregacion de logs
- Pruebas de rendimiento
- Auditoria de seguridad
- Plan de recuperacion ante desastres

---

## Credenciales por Defecto

**CAMBIAR INMEDIATAMENTE DESPUES DE LA INSTALACION**

|Entidad|Email|Contrasena|
|---|---|---|
|Admin Master|master@fire.com|password123|
|Gerente|gerente@fire.com|password123|
|Usuario|user@fire.com|password123|
|Dispositivo|sensor-test-001|API Key: TEST_DEVICE_API_KEY_32_CHARS_XX|

---

## Licencia

Ver archivo LICENSE.

---

## Autores

Basado en los requisitos de la Plataforma de Prevencion de Incendios. Instalador automatizado por el equipo de desarrollo Agustin, Marlene, Sebas, Gemma

---

**Version del Paquete:** 2.3
**Fecha de Lanzamiento:** Diciembre 2025  
**Compatibilidad:** Debian 13 (Trixie)

**Preguntas? Comenzar con el log de instalacion:** `./logs/install-*.log`