## MicroPython Web Flasher — Documentacion Tecnica

Herramienta de despliegue, configuracion y gestion para firmware IoT en ESP32, ejecutable desde el navegador (Chrome/Edge) sin instalar software adicional. Forma parte del auto-iotserver V1.2 LTS.

### Resumen de funcionalidades

| Bloque | Funcion | Descripcion |
|--------|---------|-------------|
| 1 | Diagnostico de chip | Detecta modelo, revision, MAC, flash y frecuencia de cristal del ESP32 via esptool-js |
| 2 | Flash MicroPython | Graba MicroPython v1.25.0 con borrado completo de flash via esp-web-tools |
| 3 | Subida de archivos | Transfiere los 14 modulos .py del firmware al ESP32 via protocolo Raw REPL |
| 4 | Configuracion | Drag-and-drop de config.json o formulario manual con validacion |
| 5 | Monitor serial | Consola serial en tiempo real con filtro, timestamps, export y auto-reconexion |
| 6 | Gestion del dispositivo | Lectura/edicion de configuracion, explorador de archivos, borrado individual |

### Funcionalidades avanzadas

**Escaneo de redes WiFi**: Ejecuta `network.WLAN.scan()` directamente en el ESP32 via Raw REPL y presenta las redes disponibles en un dropdown con nombre, intensidad de senal (RSSI en dBm) e indicador de barras. El usuario selecciona la red en vez de escribir el SSID manualmente. Disponible en el paso 4 (configuracion) y en el paso 6 (gestion).

**Verificacion post-upload del filesystem**: Despues de subir archivos (paso 3), ejecuta `os.listdir('/')` en el ESP32 y compara los archivos presentes contra los 14 modulos esperados del firmware. Reporta archivos faltantes si los hay.

**Monitor serial con filtro en tiempo real**: Campo de texto sobre la consola que filtra lineas mientras se escriben. Soporta texto plano (busca substring) y expresiones regulares (`/patron/`). Boton de toggle para timestamps relativos (`+0.3s`, `+1.2s`). Boton "Copiar" que copia al portapapeles solo las lineas visibles (respetando el filtro activo). Boton "Guardar" que exporta el log completo con timestamps como archivo `.log`.

**Auto-reconexion del monitor**: Cuando el ESP32 se desconecta (por reinicio o desconexion USB), el monitor detecta la perdida y reintenta la conexion automaticamente despues de 3 segundos. Se desactiva al presionar "Detener" manualmente.

**Deteccion automatica de error Redis 409**: El monitor serial analiza cada linea de output. Cuando detecta el patron `409: stale session` o `All stale session retries exhausted`, muestra un banner con el comando de solucion (`docker compose exec redis redis-cli -a <password> FLUSHDB`) y un boton de copiar.

**Reporte de provisionamiento**: Al completar la configuracion (paso 4), se genera un resumen con: chip detectado (modelo, MAC, flash), archivos subidos (cantidad y errores), configuracion aplicada (servidor, device_id, WiFi) y estado de autenticacion. Descargable como archivo `.txt`.

**Codigo QR del dispositivo**: Genera un QR con la informacion del dispositivo provisionado (ID, MAC, firmware, servidor, WiFi, fecha) en formato texto plano. Util para etiquetar los dispositivos fisicos durante la validacion con 16 ESP32.

**Gestion post-provisionamiento (paso 6)**: Dos pestanas:
- Configuracion: lee el `config.json` actual del ESP32 via Raw REPL, lo presenta en un formulario editable (campos operativos como WiFi, servidor, intervalo son editables; campos sensibles como keys son solo lectura), y guarda los cambios con escritura atomica.
- Archivos: lista todos los archivos del ESP32 con tamano y tipo (firmware/config/custom), permite subir archivos individuales por drag-and-drop (reemplazo quirurgico), y borrar archivos con un click.

**Reinicio remoto del ESP32**: Boton en el paso 5 que envia Ctrl-C + Ctrl-D via serial para hacer soft reboot sin tocar el hardware fisicamente.

**Suspend/resume automatico del monitor**: Cuando una operacion serial (paso 6, configuracion, WiFi scan) necesita el puerto, el monitor se pausa automaticamente, la operacion se ejecuta, y el monitor se reanuda al terminar. El usuario no necesita intervenir.

**Documentacion integrada**: Boton "Documentacion del firmware" en el header que abre un modal con: descripcion de los 14 modulos, protocolo de autenticacion (6 pasos con HMAC-SHA256 + AES-256-CBC), diagrama de flujo Mermaid interactivo (renderizado con Mermaid.js v11, tema oscuro personalizado), limitaciones conocidas con soluciones, y autores.

### Mitigaciones y correcciones de seguridad

**Escritura atomica (proteccion contra corrupcion)**: Todos los archivos se escriben primero a un archivo temporal (`.tmp`) y se renombran al destino final con `os.rename()` solo si la escritura completo correctamente. Si la transferencia falla (desconexion USB, timeout), el archivo original permanece intacto. Esto previene el escenario donde `config.json` queda con 0 bytes y el firmware se congela.

**Lock de operaciones concurrentes**: Variable global `operationInProgress` previene que dos operaciones seriales se ejecuten simultaneamente (por ejemplo, si el usuario hace doble click en un boton o intenta subir archivos mientras el diagnostico esta corriendo).

**Interrupcion robusta del firmware**: Para entrar al Raw REPL, se envian 5 Ctrl-C con 300ms entre cada uno (en vez de 2), seguido de un retry con 3 Ctrl-C adicionales. Esto garantiza la interrupcion incluso si el firmware esta en `time.sleep(30)`.

**Validacion de inputs antes del lock**: Las validaciones del formulario manual (campos vacios, hex invalido, URL malformada) se ejecutan ANTES de adquirir el lock de operacion. Si la validacion falla, el lock nunca se adquiere y los botones no se bloquean permanentemente.

**Normalizacion de URL**: El campo Server URL detecta y corrige protocolos duplicados (`http://http://` a `http://`), agrega `http://` si falta, y valida la URL con el constructor `new URL()`.

**Normalizacion de hex keys**: Las claves hexadecimales (device_key, server_key) se normalizan a minusculas antes de guardar, evitando inconsistencias case-sensitive.

**CDN fallback**: Si las librerias externas (esptool-js, esp-web-tools) no cargan, se muestra un mensaje claro en vez de un crash silencioso.

**Compatibilidad de navegador**: Deteccion de Web Serial API al inicio. Si el navegador no la soporta, muestra un mensaje informando que se requiere Chrome o Edge.

### Arquitectura tecnica

Archivo unico: `web-flasher/index.html` (~3500 lineas). Todo el CSS, HTML y JavaScript esta embebido en un solo archivo para maxima portabilidad (se puede servir con cualquier servidor HTTP estatico, incluyendo `python3 -m http.server`).

**Dependencias externas (CDN):**
- esptool-js v0.5.7: comunicacion con el bootloader ROM del ESP32
- esp-web-tools v10.2.1: interfaz de flash con soporte de manifesto
- Mermaid.js v11: renderizado del diagrama de flujo en el modal de documentacion
- qrcode-generator v1.4.4: generacion de codigos QR

**Protocolo de comunicacion:**
- Raw REPL de MicroPython: Ctrl-C (interrumpir), Ctrl-A (entrar raw REPL), Ctrl-D (ejecutar/reboot), Ctrl-B (salir)
- Chunks de 200 caracteres con escape de texto (`\\`, `\'`, `\n`, `\r`) para evitar desbordar el buffer del REPL
- Sentinels personalizados (`SCAN_START`/`SCAN_END`, `CFG_READ_START`/`CFG_READ_END`, `FS_START`/`FS_END`) para capturar output completo sin depender del ack `OK` del protocolo

**Diseno visual:**
- Tema oscuro premium con gradiente de fondo, grid pattern sutil y glassmorphism en cards
- Acento violet (#a78bfa) como color de identidad, distinto del PUF web flasher (amber/cyan)
- Animaciones de entrada stagger, hover lift con glow, step connectors entre cards
- Terminal con traffic lights (red/yellow/green dots) al estilo macOS
- Responsive a 640px con soporte para `prefers-reduced-motion`

### Requisitos

- Google Chrome o Microsoft Edge (Web Serial API)
- ESP32-WROOM-32D conectado por USB
- Servidor HTTP para servir el archivo (ej: `python3 -m http.server 8080`)

### Uso

```bash
cd server/auto-iotserver/web-flasher
python3 -m http.server 8080
# Abrir http://localhost:8080 en Chrome
```

### Limitaciones conocidas

- Acceder al REPL del ESP32 (pasos 3, 4, 6) requiere interrumpir el firmware en ejecucion. Esto causa un reinicio automatico y re-autenticacion con el servidor.
- Si la sesion Redis del servidor no ha expirado (TTL 24h), la re-autenticacion puede fallar con error 409. El monitor serial detecta esto y muestra el comando de solucion.
- Web Serial API solo disponible en Chrome y Edge (no Firefox, no Safari).
- Los archivos del firmware se transfieren como texto via Raw REPL; archivos binarios puros no son soportados.
