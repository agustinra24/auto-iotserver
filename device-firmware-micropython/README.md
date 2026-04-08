## Firmware MicroPython para ESP32 (IoT Device)

Firmware modular para ESP32 que se comunica con la API FastAPI del auto-iotserver. Lee sensores de temperatura, humedad y ruido, controla actuadores (LED semaforo, IR) con logica local, y envia telemetria al servidor usando autenticacion criptografica de puzzle (HMAC-SHA256 + AES-256-CBC) con tokens JWT.

### Requisitos

- ESP32-WROOM-32D con MicroPython (v1.20+)
- Sensores: DHT11 (GPIO 32), MAX4466 microfono (GPIO 34)
- Actuadores: LED semaforo RGB (GPIO 21/22/23), IR emisor (GPIO 13)
- Servidor auto-iotserver desplegado con Docker

### Provisionamiento

1. Flashear MicroPython al ESP32
2. Registrar el dispositivo en la API (admin crea device, obtiene `device_id`, `api_key`, `encryption_key`)
3. Computar `server_key` con el script helper:
   ```
   uv run compute_server_key.py ~/.iot-platform/.secrets
   ```
4. Editar `config.json` con las credenciales del dispositivo
5. Subir todos los archivos `.py` y `config.json` al ESP32 via `mpremote` o `ampy`

Si `config.json` no existe o tiene valores placeholder, el firmware entra en modo de configuracion interactiva por UART al arrancar.

### Estructura

```
main.py                 Entry point, secuencia de boot
Device.py               Orquestador: sensores + actuadores + auth + telemetria
config_manager.py       Carga config.json, validacion, provisioning UART
config.json             Credenciales y configuracion (template con placeholders)
puzzle_auth.py          Autenticacion puzzle HMAC-SHA256 + AES-256 -> JWT
http_client.py          Cliente HTTP con JWT Bearer, retry, backoff
hmac_sha256.py          HMAC-SHA256 manual (RFC 2104, MicroPython no tiene hmac)
aes256.py               AES-256-CBC compatible con crypto_new.py del servidor
WifiControl.py          WiFi STA con reconexion automatica y backoff
actuator_logic.py       Logica local de actuadores (umbrales de config.json)
temperature_sensor.py   Sensor DHT11 (temperatura y humedad)
microphone_sensor.py    Sensor MAX4466 (nivel de ruido por ADC)
led_semaphore.py        LED semaforo RGB (rojo/amarillo/verde)
IR_send.py              Transmisor infrarrojo PWM 38kHz
compute_server_key.py   Script helper PEP 723 para computar server_key
```

### Protocolo de autenticacion

El firmware usa el mismo protocolo de puzzle criptografico que la API espera:

1. Genera R2 (32 bytes aleatorios)
2. Calcula P2 = HMAC-SHA256(device_key || server_key, R2)
3. Cifra P2 con AES-256-CBC usando device_key
4. Envia puzzle_response a `POST /api/v1/auth/device/login`
5. Recibe JWT con expiracion de 24h
6. Usa JWT como Bearer token para enviar lecturas a `POST /api/v1/device/reading`

### Flujo de ejecucion

```
Boot -> config.json -> WiFi -> NTP sync -> Puzzle auth -> JWT
                                                          |
                                                          v
Loop: leer sensores -> actuadores locales -> POST reading -> sleep
         |                                       |
         |                                 401? -> re-auth
         |                            WiFi lost? -> reconnect + NTP
```

### Limitaciones conocidas

- El sensor de ruido (microfono) se usa localmente para el LED semaforo pero no se envia a la API (no hay campo compatible en SensorReading).
- Si el ESP32 se reinicia y la sesion Redis aun esta activa (TTL 24h), el dispositivo no puede autenticarse hasta que expire. Reintenta con backoff hasta 5 veces.
- `config.json` almacena claves en texto plano. Para produccion, considerar flash encryption del ESP32.
- Comunicacion HTTP plana (sin TLS). El servidor tiene Nginx con TLS, pero `urequests` de MicroPython tiene soporte TLS limitado.
- Sin actualizaciones OTA, sin watchdog hardware, sin buffer local de datos offline.

### Autores

- Alejandro Salinas (sensores, crypto original, actuadores)
- Jose Zapata (estructura original)
- Raziel Campos (estructura original)
- Agustin Ahumada (adaptacion a API FastAPI, puzzle auth, JWT, AES-256)
