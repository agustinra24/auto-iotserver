# =============================================================================
# IoT Fire Prevention Platform - Docker Compose
# MongoDB ACTIVE for sensor data
# =============================================================================

networks:
  iot-network:
    driver: bridge
    ipam:
      config:
        - subnet: {{DOCKER_SUBNET}}

services:
  # ==========================================================================
  # MySQL - Relational Database
  # ==========================================================================
  mysql:
    image: mysql:8.0
    container_name: iot-mysql
    restart: unless-stopped
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
      iot-network:
        ipv4_address: 172.20.0.10
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "root", "-p$${MYSQL_ROOT_PASSWORD}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 512M

  # ==========================================================================
  # MongoDB - Sensor Data (ACTIVE)
  # ==========================================================================
  mongodb:
    image: mongo:7.0
    container_name: iot-mongodb
    restart: unless-stopped
    environment:
      MONGO_INITDB_ROOT_USERNAME: ${MONGO_USER}
      MONGO_INITDB_ROOT_PASSWORD: ${MONGO_PASSWORD}
      MONGO_INITDB_DATABASE: ${MONGO_DATABASE}
      TZ: ${TZ:-America/Mexico_City}
    volumes:
      - ./mongo-data:/data/db
      - ./logs/mongodb:/var/log/mongodb
    networks:
      iot-network:
        ipv4_address: 172.20.0.11
    healthcheck:
      test: ["CMD", "mongosh", "--eval", "db.adminCommand('ping')"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 512M

  # ==========================================================================
  # Redis - Sessions & Cache
  # ==========================================================================
  redis:
    image: redis:7-alpine
    container_name: iot-redis
    restart: unless-stopped
    command: >
      redis-server
      --requirepass ${REDIS_PASSWORD}
      --appendonly yes
      --appendfilename "appendonly.aof"
      --maxmemory 256mb
      --maxmemory-policy allkeys-lru
    volumes:
      - ./redis-data:/data
      - ./logs/redis:/var/log/redis
    networks:
      iot-network:
        ipv4_address: 172.20.0.12
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 256M

  # ==========================================================================
  # FastAPI - Application
  # ==========================================================================
  fastapi:
    build:
      context: ./fastapi-app
      dockerfile: Dockerfile
    container_name: iot-fastapi
    restart: unless-stopped
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
      iot-network:
        ipv4_address: 172.20.0.20
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
          cpus: '1.5'
          memory: 1G

  # ==========================================================================
  # Nginx - Reverse Proxy
  # ==========================================================================
  nginx:
    image: nginx:1.25-alpine
    container_name: iot-nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./nginx/ssl:/etc/nginx/ssl:ro
      - ./logs/nginx:/var/log/nginx
    networks:
      iot-network:
        ipv4_address: 172.20.0.30
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
          cpus: '0.5'
          memory: 128M
