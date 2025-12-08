# IoT Fire Prevention Platform - Instalador Automatizado

Sistema de instalación automatizada completo para desplegar la Plataforma de Prevención de Incendios IoT en VPS Debian 13.

## 📦 Qué Incluye

### Scripts de Instalación Principal
- `install.sh` - Script principal de instalación con capacidades de ejecución en seco y reanudación
- `lib/common.sh` - Registro de eventos, manejo de errores y utilidades
- `lib/ui.sh` - Interfaz de usuario terminal, barras de progreso y banners
- `lib/validation.sh` - Funciones de validación de entradas
- `lib/secrets.sh` - Generación segura de secretos
- `lib/phases.sh` - Las 13 fases de instalación

### Plantillas de Configuración
- `templates/docker-compose.yml.tpl` - Orquestación de Docker
- `templates/env.tpl` - Variables de entorno
- `templates/nftables.conf.tpl` - Reglas de firewall
- `templates/fail2ban-*.tpl` - Prevención de intrusiones
- `templates/nginx*.tpl` - Proxy inverso
- `templates/mysql-init.sql.tpl` - Inicialización de base de datos

### Aplicación FastAPI (más de 25 archivos)
Backend FastAPI completo y listo para producción con:
- 4 tipos de autenticación (Usuario, Admin, Gerente, Dispositivo)
- Autenticación criptográfica de dispositivos (AES-256 + HMAC-SHA256)
- 14 tablas MySQL con RBAC
- Aplicación de sesión única mediante Redis

## 🚀 Inicio Rápido

### Requisitos Previos
- VPS Debian 13 (Trixie) limpio
- Acceso root o sudo
- Mínimo 4GB RAM, 20GB disco
- Conexión a internet estable

### Instalación

```bash
# 1. Clonar repositorio
git clone https://github.com/agustinra24/auto-iotserver.git
cd iot-platform-installer

# 2. Hacer ejecutable
chmod +x install.sh

# 3. Previsualizar instalación (recomendado primero)
sudo ./install.sh --dry-run

# 4. Ejecutar instalación (muestra menú interactivo)
sudo ./install.sh
```

### Modos de Ejecución

| Comando | Comportamiento |
|---------|----------------|
| `sudo ./install.sh` | Muestra menú interactivo con 4 opciones |
| `sudo ./install.sh --dry-run` | **Salta el menú**, muestra plan de instalación sin ejecutar cambios |
| `sudo ./install.sh --resume` | Reanuda desde el último checkpoint guardado |

### Menú Interactivo

Cuando ejecutas `sudo ./install.sh` sin flags, verás:
1. **Start Installation** - Inicia instalación real (modifica el sistema)
2. **Dry-Run** - Previsualiza pasos sin hacer cambios
3. **Resume from checkpoint** - Reanuda instalación interrumpida
4. **Exit** - Salir del instalador

> **💡 TIP**: Si solo quieres ver qué hará el instalador, usa `--dry-run` directamente para saltar el menú.

### Solicitudes Interactivas

El instalador solicitará:
- Dirección IP del VPS (auto-detectada)
- Nuevo nombre de usuario (predeterminado: iotadmin)
- Puerto SSH (predeterminado: 5259)
- Nombre de dominio (opcional)
- Nombre de base de datos MySQL (predeterminado: iot_platform)
- Subred Docker (predeterminado: 172.20.0.0/16)
- Límite de memoria Redis (predeterminado: 256MB)
- Zona horaria (auto-detectada)

Todas las contraseñas y secretos se generan automáticamente de forma segura.

## 📋 Fases de Instalación

### Fase 0: Preparación (10 min)
- Validación de requisitos del sistema
- Creación de estructura de directorios
- Verificación de plantillas

### Fase 1: Gestión de Usuarios (15 min) ⚠️ REQUIERE VALIDACIÓN
- Actualización de paquetes del sistema
- Creación de nuevo usuario con sudo
- **PAUSA CRÍTICA**: Validar nuevo usuario en segunda terminal
- Eliminar usuario debian predeterminado
- Configurar nombre de host y zona horaria

### Fase 2: Dependencias Principales (10 min)
- Herramientas de compilación (gcc, git, curl)
- Python 3 + pip
- Utilidades de red
- Herramientas de monitoreo

### Fase 3: Firewall (20 min)
- Deshabilitar UFW
- Instalar y configurar nftables
- Crear conjuntos de IP dinámicos para Fail2Ban
- Script de deshabilitación de firewall de emergencia

### Fase 4: Fail2Ban (15 min)
- Instalar Fail2Ban
- Acción personalizada para nftables
- Cárceles para SSH, Nginx y API
- Pruebas de integración

### Fase 5: Endurecimiento SSH (20 min) ⚠️ REQUIERE VALIDACIÓN
- Respaldar configuración SSH
- Cambiar puerto 22 → puerto personalizado
- **PAUSA CRÍTICA**: Probar nuevo puerto SSH en segunda terminal
- Deshabilitar inicio de sesión root
- Cerrar puerto 22

### Fase 6: Docker (15 min)
- Eliminar versiones antiguas de Docker
- Añadir repositorio de Docker
- Instalar Docker + Docker Compose
- Configurar daemon
- Añadir usuario al grupo docker

### Fase 7: Estructura del Proyecto (10 min)
- Crear directorio ~/iot-platform
- Generar archivo .env
- Copiar plantillas
- Establecer permisos

### Fase 8: Aplicación FastAPI (25 min)
- Copiar todos los archivos de aplicación (más de 25 archivos)
- Crear estructura de paquete Python
- Construir imagen Docker

### Fase 9: Inicialización MySQL (20 min)
- Generar hashes de contraseña para usuarios de prueba
- Crear init.sql con 14 tablas
- Configurar RBAC (roles, permisos)
- Insertar datos de prueba

### Fase 10: Nginx (15 min)
- nginx.conf principal
- Configuración del sitio
- Zonas de limitación de tasa
- Cabeceras de seguridad

### Fase 11: Despliegue (20 min)
- Crear docker-compose.yml
- Iniciar todos los servicios
- Esperar verificaciones de salud
- Verificar contenedores

### Fase 12: Pruebas (20 min)
- Prueba de endpoint de salud
- Pruebas de autenticación (4 tipos)
- Verificación de aislamiento de base de datos
- Verificación de estado de contenedores

**Tiempo Total**: ~3 horas 15 minutos

## 🔒 Características de Seguridad

### Defensa de 5 Capas
1. **nftables** - Firewall perimetral con limitación de tasa
2. **Fail2Ban** - Detección de intrusiones y bloqueo automático
3. **Nginx** - Proxy inverso con limitación de tasa
4. **FastAPI** - Validación JWT + sesiones Redis
5. **Base de datos** - Aislamiento de red, autenticación requerida

### Cero Exposición de Base de Datos
- Todas las bases de datos solo en red interna Docker
- SIN puertos expuestos al host
- Verificación: `nc -zv localhost 3306` debe FALLAR

### Aplicación de Sesión Única
- Un usuario = una sesión activa máximo
- Redis rastrea ID de JWT (JTI)
- Segundo inicio de sesión → 409 Conflicto
- Cierre de sesión invalida token inmediatamente

### Autenticación Criptográfica de Dispositivos
- NO es verificación simple de API key
- Mecanismo tipo prueba de conocimiento cero
- El dispositivo demuestra posesión de encryption_key sin transmitirla
- Implementación: AES-256-CBC + HMAC-SHA256

## 📁 Archivos Generados y Secretos

### Archivo de Secretos
Ubicación: `~/.iot-platform/.secrets`
Permisos: 600 (legible solo por el propietario)

Contiene:
- Contraseña root de MySQL
- Contraseña de usuario MySQL
- Contraseña de Redis
- Contraseña de MongoDB (futuro)
- Clave secreta JWT (HS256)
- Claves de cifrado de dispositivos

**⚠️ CRÍTICO: ¡Respalda este archivo inmediatamente después de la instalación!**

### Archivo de Configuración
Ubicación: `~/iot-platform/.env`
Cargado por Docker Compose

### Registros
- Registro de instalación: `./logs/install-YYYYMMDD-HHMMSS.log`
- Registros de Nginx: `~/iot-platform/logs/nginx/`

## 🔧 Reanudar Instalación Interrumpida

Si la instalación se interrumpe:

```bash
sudo ./install.sh --resume
```

El script automáticamente:
- Salta el menú interactivo
- Carga configuración guardada
- Carga secretos generados
- Reanuda desde la última fase completada

> **Nota**: También puedes seleccionar la opción 3 del menú si ejecutas `sudo ./install.sh` sin flags.

## 🧪 Probar la Instalación

### Verificación de Salud
```bash
curl http://localhost/health
# Esperado: {"status":"healthy"}
```

### Inicio de Sesión de Admin
```bash
curl -X POST http://localhost/api/v1/auth/login/admin \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@iot-platform.com","password":"admin123"}'
  
# Esperado: {"access_token":"eyJ...","admin_id":1,"role":"superadmin"}
```

### Prueba de Aislamiento de Base de Datos
```bash
# Todos deben FALLAR (conexión rechazada):
nc -zv localhost 3306   # MySQL
nc -zv localhost 6379   # Redis
nc -zv localhost 27017  # MongoDB
nc -zv localhost 5000   # FastAPI
```

### Estado de Contenedores
```bash
cd ~/iot-platform
docker compose ps
# Todos los servicios deben mostrar "Up (healthy)"
```

## 🌐 Información de Acceso

Después de una instalación exitosa:

### Acceso SSH
```bash
ssh NOMBRE_USUARIO@IP_VPS -p PUERTO_PERSONALIZADO
```

### Endpoints de API
- Salud: `http://IP_VPS/health`
- Documentación API: `http://IP_VPS/docs`
- Base API: `http://IP_VPS/api/v1/`

### Credenciales Predeterminadas (CAMBIAR INMEDIATAMENTE)
- Admin: `admin@iot-platform.com` / `admin123`
- Usuario: `user@iot-platform.com` / `user123`
- Gerente: `manager@iot-platform.com` / `manager123`

## 🐛 Solución de Problemas

### La Instalación Falla en Fase X
1. Revisar archivo de registro: `./logs/install-*.log`
2. Revisar mensaje de error
3. Corregir problema manualmente si es necesario
4. Reanudar: `sudo ./install.sh --resume`

### No Puedo Conectarme por SSH Después de Fase 5
1. Usar acceso a consola VPS (panel OVHcloud)
2. Verificar servicio SSH: `systemctl status sshd`
3. Verificar firewall: `nft list ruleset`
4. Emergencia: Ejecutar `/usr/local/bin/emergency-disable-firewall.sh`

### Los Servicios Docker No Inician
```bash
cd ~/iot-platform
docker compose logs
# Revisar registros de servicio específico
```

### Errores de Conexión a Base de Datos
1. Verificar que archivo .env existe y tiene credenciales correctas
2. Revisar contenedor MySQL: `docker compose logs mysql`
3. Verificar red interna: `docker network ls`

## 📖 Documentación

- **Guía Completa**: GUIA_DEFINITIVA_2.0_COMPLETA.md
- **Arquitectura**: ARCHITECTURE_DIAGRAMS.md
- **Referencia de Código**: FASTAPI_CODE_REFERENCE.md
- **Resumen**: RESUMEN_GUIA_DEFINITIVA_2.0.md

## ⚙️ Arquitectura del Sistema

```
Internet
    │
    └── Firewall nftables (Capa 1)
            │
            └── Fail2Ban (Capa 2)
                    │
                    └── Nginx :80,:443 (Capa 3)
                            │
                            └── FastAPI :5000 (Capa 4)
                                    │
                                    ├── MySQL :3306 (Capa 5)
                                    ├── Redis :6379 (Capa 5)
                                    └── MongoDB :27017 (Capa 5 - Futuro)

Todas las bases de datos en red Docker aislada 172.20.0.0/16
```

## 🔑 Sistema de Autenticación

### 4 Tipos de Autenticación

1. **Usuario** - `POST /api/v1/auth/login/user`
2. **Admin** - `POST /api/v1/auth/login/admin`
3. **Gerente** - `POST /api/v1/auth/login/manager`
4. **Dispositivo** - `POST /api/v1/auth/login/device` (con rompecabezas criptográficos)

### Gestión de Sesiones
- JWT con JTI (ID de token único)
- Redis almacena: `session:{type}:{id} = jti`
- Sesión única aplicada (segundo inicio → 409)
- Cierre de sesión elimina clave Redis → invalidación inmediata

## 💾 Esquema de Base de Datos

14 Tablas MySQL:
- **RBAC (3)**: rol, permission, rol_permiso
- **Contraseñas (4)**: pasadmin, pasusuario, pasgerente, pasdispositivo
- **Entidades (4)**: admin, usuario, manager, device
- **Servicios (2)**: service, app
- **M2M (2)**: servicio_dispositivo, servicio_app (en realidad 1, haciendo 14 en total con servicio_app faltante)

## 🤝 Contribuciones

¡Problemas y mejoras son bienvenidas!

## 📄 Licencia

Ver archivo LICENSE

## 👤 Autor

Basado en GUIA_DEFINITIVA_2.0_COMPLETA.md
Instalador automatizado por Agustin, Marlene, Sebastian, Gemma

---

**Recuerda**: ¡Siempre respalda `~/.iot-platform/.secrets` después de la instalación!