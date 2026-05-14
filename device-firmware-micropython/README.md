# ESP32 MicroPython Device Firmware

MicroPython firmware for ESP32 devices that report sensor data to
Auto-IoTServer. The firmware reads local sensors, controls simple actuators, and
authenticates to the FastAPI backend through the platform's HMAC-SHA256 and
AES-256-CBC puzzle flow.

This firmware is separate from the SRAM-PUF research firmware in the parent
`did-puf-framework` repository. It is the operational device firmware for the
Auto-IoTServer platform.

## Requirements

- ESP32 with MicroPython v1.20 or newer.
- WiFi credentials.
- A generated `config.json` file.
- `mpremote` or the web flasher for file transfer.

Tested hardware assumptions in this tree include:

- DHT11 on GPIO 32.
- MAX4466 microphone on GPIO 34.
- RGB LED on GPIO 21, GPIO 22, and GPIO 23.
- IR emitter on GPIO 13.
- BOOT button on GPIO 0 for pause/resume toggling.

## Files

```text
main.py                 Boot entry point
Device.py               Device orchestration
WifiControl.py          WiFi STA connection management
config.json             Configuration template
config_manager.py       Configuration loading and validation
puzzle_auth.py          Device authentication puzzle
http_client.py          JWT Bearer HTTP client
aes256.py               AES-256-CBC helper
hmac_sha256.py          HMAC-SHA256 helper
temperature_sensor.py   Temperature and humidity sensor wrapper
microphone_sensor.py    Noise sensor wrapper
led_semaphore.py        RGB LED signaling
IR_send.py              Infrared emitter helper
actuator_logic.py       Local actuator rules
button_toggle.py        BOOT button pause/resume support
compute_server_key.py   Host helper for config generation
```

## Provisioning

Recommended path: use `../web-flasher/index.html` from Chrome or Edge. The web
flasher can flash MicroPython, upload the firmware files, generate or deploy
`config.json`, scan WiFi networks, and monitor serial output.

Manual path:

```bash
cd server/auto-iotserver

uv run device-firmware-micropython/compute_server_key.py
mpremote cp device-firmware-micropython/*.py :
mpremote cp device-firmware-micropython/config.json :
```

`compute_server_key.py` can read the deployed platform secrets from
`~/.iot-platform/.secrets` when available. If the secrets file is unavailable,
it falls back to interactive prompts for the required fields.

If `config.json` is missing or still contains placeholder values for
`api_key` or `device_key`, the firmware enters interactive UART configuration at
boot.

## Authentication Flow

1. Load `config.json`.
2. Connect to WiFi.
3. Build a device authentication puzzle using local device secrets.
4. Send the puzzle response to `POST /api/v1/auth/device/login`.
5. Store the returned JWT in memory.
6. Send readings to `POST /api/v1/device/reading` with a Bearer token.
7. Re-authenticate when the token expires or the server rejects it.

The device secret is never sent as a standalone field during normal
authentication.

## Runtime Behavior

- Sensor readings are sampled locally.
- Temperature and humidity are sent to the API.
- Noise is used locally for LED behavior in the current firmware contract.
- The BOOT button toggles telemetry pause/resume without stopping local sensor
  reads.
- Network and authentication failures use retry and backoff logic.

## Known Limits

- The firmware uses the Auto-IoTServer puzzle authentication scheme, not PUF or
  post-quantum device authentication.
- If the device reboots while a Redis session is still active on the server, the
  server can reject re-authentication with HTTP 409 until the session expires or
  an operator clears the lab session state.
- Binary file transfer is not handled by this firmware README. Use text `.py`
  uploads through Raw REPL or the web flasher.

## Recovery Note

In a controlled lab environment, stale sessions can be cleared from the server:

```bash
docker compose exec redis redis-cli -a <password> FLUSHDB
```

Use this only when you understand the effect on active sessions.
