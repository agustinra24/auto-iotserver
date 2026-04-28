# =============================================================================
# Plataforma IoT con Seguridad Integrada - Docker Compose
# MongoDB ACTIVO para datos de sensores
# =============================================================================

networks:
  iot-network:
    driver: bridge
    ipam:
      config:
        - subnet: {{DOCKER_SUBNET}}

services:
  # ==========================================================================
  # MySQL - Base de Datos Relacional
  # ==========================================================================
  mysql:
    image: mysql:8.0
    container_name: iot-mysql
    restart: unless-stopped
    command: {{MYSQL_COMMAND}}
    mem_limit: {{MYSQL_MEM_LIMIT}}
    mem_reservation: {{MYSQL_MEM_RESERVATION}}
    cpus: "{{MYSQL_CPUS}}"
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: ${MYSQL_DATABASE}
      MYSQL_USER: ${MYSQL_USER}
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
      TZ: ${TZ:-America/Mexico_City}
    volumes:
      - ./mysql-data:/var/lib/mysql
      - ./mysql-init:/docker-entrypoint-initdb.d:ro
      - ./logs/mysql:/var/log/mysql
    networks:
      - iot-network
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "root", "-p$${MYSQL_ROOT_PASSWORD}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    deploy:
      resources:
        limits:
          cpus: '{{MYSQL_CPUS}}'
          memory: {{MYSQL_MEM_LIMIT}}

  # ==========================================================================
  # MongoDB - Datos de Sensores (ACTIVO)
  # ==========================================================================
  mongodb:
    image: {{MONGO_IMAGE}}
    container_name: iot-mongodb
    restart: unless-stopped
    command: {{MONGO_COMMAND}}
    mem_limit: {{MONGO_MEM_LIMIT}}
    mem_reservation: {{MONGO_MEM_RESERVATION}}
    cpus: "{{MONGO_CPUS}}"
    environment:
      MONGO_INITDB_ROOT_USERNAME: ${MONGO_USER}
      MONGO_INITDB_ROOT_PASSWORD: ${MONGO_PASSWORD}
      MONGO_INITDB_DATABASE: ${MONGO_DATABASE}
      TZ: ${TZ:-America/Mexico_City}
    volumes:
      - ./mongo-data:/data/db
      - ./logs/mongodb:/var/log/mongodb
    networks:
      - iot-network
    healthcheck:
      test: ["CMD-SHELL", "if command -v mongosh >/dev/null 2>&1; then mongosh --quiet --eval \"db.adminCommand('ping').ok\"; else mongo --quiet --eval \"db.adminCommand('ping').ok\"; fi"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    deploy:
      resources:
        limits:
          cpus: '{{MONGO_CPUS}}'
          memory: {{MONGO_MEM_LIMIT}}

  # ==========================================================================
  # Redis - Sesiones y Caché
  # ==========================================================================
  redis:
    image: redis:7-alpine
    container_name: iot-redis
    restart: unless-stopped
    mem_limit: {{REDIS_MEM_LIMIT}}
    mem_reservation: {{REDIS_MEM_RESERVATION}}
    cpus: "{{REDIS_CPUS}}"
    command: >
      redis-server
      --requirepass ${REDIS_PASSWORD}
      --appendonly yes
      --appendfilename "appendonly.aof"
      --maxmemory {{REDIS_MEMORY}}
      --maxmemory-policy allkeys-lru
    volumes:
      - ./redis-data:/data
      - ./logs/redis:/var/log/redis
    networks:
      - iot-network
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    deploy:
      resources:
        limits:
          cpus: '{{REDIS_CPUS}}'
          memory: {{REDIS_MEM_LIMIT}}

  # ==========================================================================
  # FastAPI - Aplicación
  # ==========================================================================
  fastapi:
    build:
      context: ./fastapi-app
      dockerfile: Dockerfile
    container_name: iot-fastapi
    restart: unless-stopped
    command: {{FASTAPI_COMMAND}}
    mem_limit: {{FASTAPI_MEM_LIMIT}}
    mem_reservation: {{FASTAPI_MEM_RESERVATION}}
    cpus: "{{FASTAPI_CPUS}}"
    environment:
      - MYSQL_HOST=mysql
      - MYSQL_PORT=3306
      - MYSQL_USER=${MYSQL_USER}
      - MYSQL_PASSWORD=${MYSQL_PASSWORD}
      - MYSQL_DATABASE=${MYSQL_DATABASE}
      - DATABASE_URL=mysql+pymysql://${MYSQL_USER}:${MYSQL_PASSWORD}@mysql:3306/${MYSQL_DATABASE}
      - MONGO_HOST=mongodb
      - MONGO_PORT=27017
      - MONGO_USER=${MONGO_USER}
      - MONGO_PASSWORD=${MONGO_PASSWORD}
      - MONGO_DATABASE=${MONGO_DATABASE}
      - MONGO_AUTH_SOURCE=admin
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - REDIS_PASSWORD=${REDIS_PASSWORD}
      - SECRET_KEY=${SECRET_KEY}
      - ALGORITHM=${ALGORITHM}
      - ACCESS_TOKEN_EXPIRE_MINUTES=${ACCESS_TOKEN_EXPIRE_MINUTES}
      - LOGS_DIR=/var/log/fastapi
      - TZ=${TZ:-America/Mexico_City}
    expose:
      - "5000"
    volumes:
      - ./fastapi-app:/app:ro
      - ./logs/fastapi:/var/log/fastapi
    networks:
      - iot-network
    depends_on:
      mysql:
        condition: service_healthy
      mongodb:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    deploy:
      resources:
        limits:
          cpus: '{{FASTAPI_CPUS}}'
          memory: {{FASTAPI_MEM_LIMIT}}

  # ==========================================================================
  # Nginx - Proxy Inverso
  # ==========================================================================
  nginx:
    image: nginx:1.25-alpine
    container_name: iot-nginx
    restart: unless-stopped
    mem_limit: {{NGINX_MEM_LIMIT}}
    mem_reservation: {{NGINX_MEM_RESERVATION}}
    cpus: "{{NGINX_CPUS}}"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./nginx/ssl:/etc/nginx/ssl:ro
      - ./web-flasher:/usr/share/nginx/web-flasher:ro
      - ./logs/nginx:/var/log/nginx
    networks:
      - iot-network
    depends_on:
      fastapi:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    deploy:
      resources:
        limits:
          cpus: '{{NGINX_CPUS}}'
          memory: {{NGINX_MEM_LIMIT}}
