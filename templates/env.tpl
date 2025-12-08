# =============================================================================
# Plataforma IoT de Prevención de Incendios - Configuración de Entorno
# Generado por el instalador
# =============================================================================

# Configuración de MySQL
MYSQL_ROOT_PASSWORD={{MYSQL_ROOT_PASSWORD}}
MYSQL_DATABASE=fire_preventionf
MYSQL_USER=iot_user
MYSQL_PASSWORD={{MYSQL_PASSWORD}}
MYSQL_HOST=mysql
MYSQL_PORT=3306

# Configuración de MongoDB (ACTIVO - Datos de Sensores)
MONGO_PASSWORD={{MONGO_PASSWORD}}
MONGO_HOST=mongodb
MONGO_PORT=27017
MONGO_USER=admin
MONGO_DATABASE=iot_sensors
MONGO_AUTH_SOURCE=admin

# Configuración de Redis
REDIS_PASSWORD={{REDIS_PASSWORD}}
REDIS_HOST=redis
REDIS_PORT=6379

# Configuración de FastAPI
SECRET_KEY={{SECRET_KEY}}
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=60

# Aplicación
APP_ENV=production
TZ=America/Mexico_City

# Registro de Logs
LOGS_DIR=/var/log/fastapi

# URL de Base de Datos (construida)
DATABASE_URL=mysql+pymysql://${MYSQL_USER}:${MYSQL_PASSWORD}@${MYSQL_HOST}:${MYSQL_PORT}/${MYSQL_DATABASE}