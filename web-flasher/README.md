# MicroPython Web Flasher

Browser-based provisioning tool for the Auto-IoTServer ESP32 MicroPython
firmware. It runs from Chrome or Edge and uses the Web Serial API.

This flasher is for the Auto-IoTServer MicroPython device firmware. It is not
the same tool as the parent repository's PUF provisioning flasher.

## Capabilities

- Flash MicroPython to ESP32 from the browser.
- Upload the platform firmware `.py` files through Raw REPL.
- Generate or deploy `config.json`.
- Scan WiFi networks from the ESP32 and select the SSID in the browser.
- Open a serial monitor with filters and exportable logs.
- Read and edit operational configuration.
- List and replace files on the ESP32 filesystem.
- Generate a provisioning report for lab tracking.

## Files

```text
web-flasher/
├── index.html
├── styles.css
├── app.js
└── firmware/
    ├── ESP32_GENERIC-20250415-v1.25.0.bin
    └── manifest.json
```

The UI is split into separate HTML, CSS, and JavaScript files to keep the tool
maintainable.

## Requirements

- Google Chrome or Microsoft Edge.
- Web Serial API support.
- ESP32 connected by USB.
- A local HTTP server.

Firefox and Safari do not support the Web Serial API required by this workflow.

## Usage

```bash
cd server/auto-iotserver/web-flasher
python3 -m http.server 8080
```

Open:

```text
http://localhost:8080
```

Follow the UI steps to flash MicroPython, upload firmware files, configure WiFi
and API settings, and monitor the device.

## Operational Notes

- Entering Raw REPL interrupts the running firmware and may trigger a reboot.
- If the server still has an active Redis session for the device, a rebooted
  ESP32 can receive HTTP 409 until the session expires or is cleared.
- The firmware files are uploaded as text through Raw REPL. Arbitrary binary
  upload is not part of this tool's current contract.
- The browser page should be served over `localhost` or a trusted local network
  during lab provisioning.

## Safety Notes

- Review generated configuration before uploading it to a device.
- Do not commit generated `config.json` files containing real credentials.
- Treat serial logs as potentially sensitive when they contain device IDs,
  network names, or error traces.
