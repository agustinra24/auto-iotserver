# Auto-IoTServer

Automated deployment package for an IoT backend with integrated security
controls. The repository includes:

- A Debian/Trixie-oriented installer.
- A FastAPI backend.
- MySQL, MongoDB, Redis, and Nginx templates.
- MicroPython ESP32 device firmware.
- A browser-based MicroPython web flasher.

This project is an integration and deployment platform. It is not the core
SRAM-PUF thesis implementation, although it can be used later as an integration
target for lifecycle and device-identity work.

## Status

The V1.3 RC1 installer was validated in a clean Debian 13.4 ARM64 netinst VM
with 2 GB nominal RAM and the `compact-storage` profile. The validation checked
installer completion, container health, local and LAN health endpoints, database
network isolation, no observed OOM kill, and recovery after reboot.

That evidence is suitable for lab, demo, and light IoT workloads. It is not a
load test and does not replace production hardening, operational monitoring, or
backup validation.

## Architecture

```text
auto-iotserver/
├── install.sh
├── lib/                         # Installer phases, validation, secrets, UI
├── templates/                   # Docker, Nginx, Fail2Ban, MySQL templates
├── device-firmware-micropython/ # ESP32 MicroPython device firmware
├── web-flasher/                 # Browser flasher and provisioning UI
├── docs/
│   └── db-diagram.png
└── logs/
```

Runtime services deployed by the installer:

| Service | Purpose |
|---------|---------|
| FastAPI | REST API and authentication endpoints |
| MySQL 8 | Relational platform data |
| MongoDB 7 | Sensor readings and device logs |
| Redis 7 | Active sessions and authentication state |
| Nginx | Reverse proxy, static flasher serving, and rate limiting |

On Raspberry Pi 4/400/CM4, MongoDB 7 is not treated as a production target.
The installer can use a legacy MongoDB 4.4 mode for lab compatibility when
explicitly accepted.

## Security Model

The current device authentication flow is a cryptographic puzzle based on
HMAC-SHA256 and AES-256-CBC. A device proves possession of its configured secret
without sending the secret over the network. Successful authentication returns a
JWT Bearer token used for telemetry calls.

The platform also includes:

- Single active-session policy per entity.
- Fail2Ban jails for SSH and Nginx-related logs.
- nftables firewall configuration.
- SSH hardening during installation.
- Internal-only database network exposure through Docker networking.
- Installer-generated secrets stored on the deployed host.

This security model is useful as an operational baseline, but it is not a
post-quantum authentication design. PQC and PUF integration should be introduced
incrementally and tested without weakening the current device contract.

## Requirements

- Debian 13.x Trixie or a compatible derivative.
- Root or `sudo` access.
- Network access to Debian package repositories and Docker Hub.
- At least 2 GB RAM for lab or compact deployments.
- A snapshot or backup before installation on any important host.

Minimal bootstrap packages:

```bash
sudo apt update
sudo apt install -y git curl
```

## Installation

```bash
git clone https://github.com/agustinra24/auto-iotserver.git
cd auto-iotserver
chmod +x install.sh
sudo ./install.sh --dry-run
sudo ./install.sh
```

The installer detects memory, swap, CPU, disk space, architecture, and Debian
version. It may select conservative profiles for low-resource or compact-storage
hosts.

Resume an interrupted installation:

```bash
sudo ./install.sh --resume
```

Advanced Raspberry Pi compatibility override:

```bash
sudo ./install.sh --allow-legacy-pi4-mongodb
```

The installer validates DNS and Docker Hub reachability before deployment. If a
network blocks Docker Hub, TLS, external DNS, or requires an authenticated proxy,
the installer should fail with diagnostics rather than attempting an unsafe
bypass.

## API Smoke Checks

Health endpoint:

```bash
curl http://localhost/health
```

Interactive API documentation:

```text
http://<server>/docs
http://<server>/redoc
```

Container state:

```bash
docker compose ps
```

Database ports should not be reachable from the host network:

```bash
nc -zv localhost 3306
nc -zv localhost 6379
nc -zv localhost 27017
```

Those checks are expected to fail if database isolation is configured correctly.

## Device Firmware

The `device-firmware-micropython/` directory contains the ESP32 MicroPython
firmware used by this platform. It includes sensor reading, actuator control,
WiFi management, cryptographic puzzle authentication, JWT-based telemetry, and
configuration handling.

Typical manual workflow:

```bash
uv run device-firmware-micropython/compute_server_key.py
mpremote cp device-firmware-micropython/*.py :
mpremote cp device-firmware-micropython/config.json :
```

The recommended provisioning path is the browser flasher in `web-flasher/`.

## Web Flasher

Serve the web flasher locally:

```bash
cd web-flasher
python3 -m http.server 8080
```

Open this URL in Chrome or Edge:

```text
http://localhost:8080
```

The Web Serial API is required. Firefox and Safari are not supported for this
workflow.

## Post-Install Tasks

- Store the generated secrets file securely.
- Change the system user password if the installer created or modified it.
- Remove demo users before exposing the service.
- Configure TLS certificates before public deployment.
- Configure backups for MySQL and MongoDB.
- Add monitoring for disk, memory, container health, and API latency.
- Review rate limits for the expected workload.

## Troubleshooting

Detailed installer logs are written under:

```text
logs/
```

Inspect container logs:

```bash
docker compose logs fastapi
docker compose logs nginx
docker compose logs mysql
docker compose logs mongodb
docker compose logs redis
```

If device authentication fails with a stale session conflict, clear active Redis
session state only in a controlled lab or recovery context:

```bash
docker compose exec redis redis-cli -a <password> FLUSHDB
```

The Redis password is stored in the deployed secrets file.

## License

See `LICENSE`.
