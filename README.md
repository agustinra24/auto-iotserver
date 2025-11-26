# IoT Fire Prevention Platform - Automated Installer

Complete automated installation system for deploying the IoT Fire Prevention Platform on Debian 13 VPS.

## 📦 What's Included

### Core Installation Scripts
- `install.sh` - Main installation script with dry-run and resume capabilities
- `lib/common.sh` - Logging, error handling, utilities
- `lib/ui.sh` - Terminal UI, progress bars, banners
- `lib/validation.sh` - Input validation functions
- `lib/secrets.sh` - Secure secret generation
- `lib/phases.sh` - All 13 installation phases

### Configuration Templates
- `templates/docker-compose.yml.tpl` - Docker orchestration
- `templates/env.tpl` - Environment variables
- `templates/nftables.conf.tpl` - Firewall rules
- `templates/fail2ban-*.tpl` - Intrusion prevention
- `templates/nginx*.tpl` - Reverse proxy
- `templates/mysql-init.sql.tpl` - Database initialization

### FastAPI Application (25+ files)
Complete production-ready FastAPI backend with:
- 4 authentication types (User, Admin, Manager, Device)
- Cryptographic device authentication (AES-256 + HMAC-SHA256)
- 14 MySQL tables with RBAC
- Single session enforcement via Redis

## 🚀 Quick Start

### Prerequisites
- Fresh Debian 13 (Trixie) VPS
- Root or sudo access
- Minimum 4GB RAM, 20GB disk
- Stable internet connection

### Installation

```bash
# 1. Clone repository
git clone https://github.com/user/iot-platform-installer
cd iot-platform-installer

# 2. Make executable
chmod +x install.sh

# 3. Preview installation (recommended)
sudo ./install.sh --dry-run

# 4. Run installation
sudo ./install.sh
```

### Interactive Prompts

The installer will ask for:
- VPS IP address (auto-detected)
- New username (default: iotadmin)
- SSH port (default: 5259)
- Domain name (optional)
- MySQL database name (default: iot_platform)
- Docker subnet (default: 172.20.0.0/16)
- Redis memory limit (default: 256MB)
- Timezone (auto-detected)

All passwords and secrets are auto-generated securely.

## 📋 Installation Phases

### Phase 0: Preparation (10 min)
- System requirements validation
- Directory structure creation
- Template verification

### Phase 1: User Management (15 min) ⚠️ REQUIRES VALIDATION
- System package updates
- New user creation with sudo
- **CRITICAL PAUSE**: Validate new user in second terminal
- Remove default debian user
- Configure hostname and timezone

### Phase 2: Core Dependencies (10 min)
- Build tools (gcc, git, curl)
- Python 3 + pip
- Network utilities
- Monitoring tools

### Phase 3: Firewall (20 min)
- Disable UFW
- Install and configure nftables
- Create dynamic IP sets for Fail2Ban
- Emergency firewall disable script

### Phase 4: Fail2Ban (15 min)
- Install Fail2Ban
- Custom nftables action
- SSH, Nginx, and API jails
- Integration testing

### Phase 5: SSH Hardening (20 min) ⚠️ REQUIRES VALIDATION
- Backup SSH config
- Change port 22 → custom port
- **CRITICAL PAUSE**: Test new SSH port in second terminal
- Disable root login
- Close port 22

### Phase 6: Docker (15 min)
- Remove old Docker versions
- Add Docker repository
- Install Docker + Docker Compose
- Configure daemon
- Add user to docker group

### Phase 7: Project Structure (10 min)
- Create ~/iot-platform directory
- Generate .env file
- Copy templates
- Set permissions

### Phase 8: FastAPI Application (25 min)
- Copy all application files (25+ files)
- Create Python package structure
- Build Docker image

### Phase 9: MySQL Initialization (20 min)
- Generate password hashes for test users
- Create init.sql with 14 tables
- Setup RBAC (roles, permissions)
- Insert test data

### Phase 10: Nginx (15 min)
- Main nginx.conf
- Site configuration
- Rate limiting zones
- Security headers

### Phase 11: Deployment (20 min)
- Create docker-compose.yml
- Start all services
- Wait for health checks
- Verify containers

### Phase 12: Testing (20 min)
- Health endpoint test
- Authentication tests (4 types)
- Database isolation verification
- Container status check

**Total Time**: ~3 hours 15 minutes

## 🔒 Security Features

### 5-Layer Defense
1. **nftables** - Perimeter firewall with rate limiting
2. **Fail2Ban** - Intrusion detection and auto-ban
3. **Nginx** - Reverse proxy with rate limiting
4. **FastAPI** - JWT validation + Redis sessions
5. **Database** - Network isolated, authentication required

### Zero Database Exposure
- All databases on internal Docker network only
- NO ports exposed to host
- Verification: `nc -zv localhost 3306` must FAIL

### Single Session Enforcement
- One user = one active session maximum
- Redis tracks JWT ID (JTI)
- Second login → 409 Conflict
- Logout invalidates token immediately

### Cryptographic Device Authentication
- NOT simple API key verification
- Zero-knowledge proof-like mechanism
- Device proves possession of encryption_key without transmitting it
- Implementation: AES-256-CBC + HMAC-SHA256

## 📁 Generated Files & Secrets

### Secrets File
Location: `~/.iot-platform/.secrets`
Permissions: 600 (readable only by owner)

Contains:
- MySQL root password
- MySQL user password
- Redis password
- MongoDB password (future)
- JWT secret key (HS256)
- Device encryption keys

**⚠️ CRITICAL: Backup this file immediately after installation!**

### Configuration File
Location: `~/iot-platform/.env`
Loaded by Docker Compose

### Logs
- Installation log: `./logs/install-YYYYMMDD-HHMMSS.log`
- Nginx logs: `~/iot-platform/logs/nginx/`

## 🔧 Resuming Interrupted Installation

If installation is interrupted:

```bash
sudo ./install.sh --resume
```

The script automatically:
- Loads saved configuration
- Loads generated secrets
- Resumes from last completed phase

## 🧪 Testing the Installation

### Health Check
```bash
curl http://localhost/health
# Expected: {"status":"healthy"}
```

### Admin Login
```bash
curl -X POST http://localhost/api/v1/auth/login/admin \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@iot-platform.com","password":"admin123"}'
  
# Expected: {"access_token":"eyJ...","admin_id":1,"role":"superadmin"}
```

### Database Isolation Test
```bash
# All must FAIL (connection refused):
nc -zv localhost 3306   # MySQL
nc -zv localhost 6379   # Redis
nc -zv localhost 27017  # MongoDB
nc -zv localhost 5000   # FastAPI
```

### Container Status
```bash
cd ~/iot-platform
docker compose ps
# All services should show "Up (healthy)"
```

## 🌐 Access Information

After successful installation:

### SSH Access
```bash
ssh USERNAME@VPS_IP -p CUSTOM_PORT
```

### API Endpoints
- Health: `http://VPS_IP/health`
- API Docs: `http://VPS_IP/docs`
- API Base: `http://VPS_IP/api/v1/`

### Default Credentials (CHANGE IMMEDIATELY)
- Admin: `admin@iot-platform.com` / `admin123`
- User: `user@iot-platform.com` / `user123`
- Manager: `manager@iot-platform.com` / `manager123`

## 📚 Next Steps

1. **Backup Secrets**
   ```bash
   cat ~/.iot-platform/.secrets
   # Copy to secure location
   ```

2. **Change Default Passwords**
   Use API endpoints to update passwords

3. **Setup SSL/TLS** (Recommended)
   - Install certbot
   - Configure Let's Encrypt
   - Update Nginx for HTTPS

4. **Configure Monitoring**
   - Setup Prometheus + Grafana
   - Configure alerts
   - Monitor system resources

5. **Setup Backups**
   - Automated MySQL backups
   - Configuration backups
   - Secrets backup

## 🐛 Troubleshooting

### Installation Fails at Phase X
1. Check log file: `./logs/install-*.log`
2. Review error message
3. Fix issue manually if needed
4. Resume: `sudo ./install.sh --resume`

### Cannot Connect via SSH After Phase 5
1. Use VPS console access (OVHcloud panel)
2. Check SSH service: `systemctl status sshd`
3. Check firewall: `nft list ruleset`
4. Emergency: Run `/usr/local/bin/emergency-disable-firewall.sh`

### Docker Services Won't Start
```bash
cd ~/iot-platform
docker compose logs
# Check specific service logs
```

### Database Connection Errors
1. Verify .env file exists and has correct credentials
2. Check MySQL container: `docker compose logs mysql`
3. Verify internal network: `docker network ls`

## 📖 Documentation

- **Full Guide**: GUIA_DEFINITIVA_2.0_COMPLETA.md
- **Architecture**: ARCHITECTURE_DIAGRAMS.md
- **Code Reference**: FASTAPI_CODE_REFERENCE.md
- **Summary**: RESUMEN_GUIA_DEFINITIVA_2.0.md

## ⚙️ System Architecture

```
Internet
    │
    └── nftables Firewall (Layer 1)
            │
            └── Fail2Ban (Layer 2)
                    │
                    └── Nginx :80,:443 (Layer 3)
                            │
                            └── FastAPI :5000 (Layer 4)
                                    │
                                    ├── MySQL :3306 (Layer 5)
                                    ├── Redis :6379 (Layer 5)
                                    └── MongoDB :27017 (Layer 5 - Future)

All databases on isolated Docker network 172.20.0.0/16
```

## 🔑 Authentication System

### 4 Authentication Types

1. **User** - `POST /api/v1/auth/login/user`
2. **Admin** - `POST /api/v1/auth/login/admin`
3. **Manager** - `POST /api/v1/auth/login/manager`
4. **Device** - `POST /api/v1/auth/login/device` (with cryptographic puzzles)

### Session Management
- JWT with JTI (unique token ID)
- Redis stores: `session:{type}:{id} = jti`
- Single session enforced (second login → 409)
- Logout deletes Redis key → immediate invalidation

## 💾 Database Schema

14 MySQL Tables:
- **RBAC (3)**: rol, permission, rol_permiso
- **Passwords (4)**: pasadmin, pasusuario, pasgerente, pasdispositivo
- **Entities (4)**: admin, usuario, manager, device
- **Services (2)**: service, app
- **M2M (2)**: servicio_dispositivo, servicio_app (actually 1, making 14 total with the missing servicio_app)

## 🤝 Contributing

Issues and improvements welcome!

## 📄 License

See LICENSE file

## 👤 Author

Based on GUIA_DEFINITIVA_2.0_COMPLETA.md
Automated installer by Agustin

---

**Remember**: Always backup `~/.iot-platform/.secrets` after installation!
