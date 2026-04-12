'use strict';

// ─── CONSTANTES ───────────────────────────────────────────────
var BAUD_RATE = 115200;
var MAX_LINES = 2000;
var CHUNK_SIZE = 200;
var SERIAL_DELAY_MS = 300;
var USB_FILTERS = [
  { usbVendorId: 0x10C4 }, // CP210x
  { usbVendorId: 0x1A86 }, // CH340
  { usbVendorId: 0x0403 }, // FTDI
  { usbVendorId: 0x303A }, // Espressif
];
var TIMEOUTS = {
  REPL_ENTRY: 3000,
  REPL_EXEC: 5000,
  FILE_OP: 8000,
  WIFI_SCAN: 15000,
  FETCH: 15000,
  REBOOT_WAIT: 500,
  EXEC_DEFAULT: 10000,
  PORT_SETTLE: 200,
  INTERRUPT_SETTLE: 500,
  RECONNECT_DELAY: 3000,
  RESUME_DELAY: 1500,
};
var MICROPYTHON_VERSION = 'v1.25.0';

// Comando Python para listar archivos del ESP32 con tamanos
var FS_LIST_CMD = "import os;print('FS_START');[(print(f+'|'+str(os.stat('/'+f)[6]))) for f in sorted(os.listdir('/'))];print('FS_END')";

// ─── ESTADO ───────────────────────────────────────────────────
var FIRMWARE_FILES = {};
var firmwareLoaded = false;
var KNOWN_FIRMWARE = [];

var serialPort = null;
var serialReader = null;
var monitorRunning = false;
var configData = null;
var operationInProgress = false;

var monitorPort = null;
var lineCount = 0;
var monitorLines = [];
var monitorStartTime = 0;
var showTimestamps = false;
var currentFilter = '';
var autoReconnect = true;
var monitorSuspended = false;
var redisAlertShown = false;

var provisioningData = {};

var mgmtOriginalConfig = null;

var docsInitialized = false;
var docsPreviousFocus = null;

// ─── HELPERS ──────────────────────────────────────────────────
// Atajo para getElementById, usado en bindeo de eventos y acceso a elementos del DOM
function $(id) { return document.getElementById(id); }

function showStatus(id, msg, type) {
  var el = $(id);
  if (!el) return;
  el.textContent = msg;
  el.className = 'status-msg visible ' + type;
}

function hideStatus(id) {
  var el = $(id);
  if (!el) return;
  el.className = 'status-msg';
  el.textContent = '';
}

function sleep(ms) {
  return new Promise(function(r) { setTimeout(r, ms); });
}

async function safeClosePort(port) {
  if (!port) return;
  try { await port.close(); } catch (_) {}
}

function sanitizeFilename(name) {
  var base = name.replace(/.*[\/\\]/, '');
  if (/['";\\\x00-\x1f]/.test(base)) {
    throw new Error('Nombre de archivo no permitido: ' + base);
  }
  if (base.length === 0 || base.length > 64) {
    throw new Error('Nombre de archivo invalido (vacio o excede 64 caracteres).');
  }
  return base;
}

function escapeForPythonBytes(str) {
  var out = '';
  for (var i = 0; i < str.length; i++) {
    var c = str.charCodeAt(i);
    if (c === 0x5C) {
      out += '\\\\';
    } else if (c === 0x27) {
      out += "\\'";
    } else if (c === 0x0A) {
      out += '\\n';
    } else if (c === 0x0D) {
      out += '\\r';
    } else if (c === 0x09) {
      out += '\\t';
    } else if (c < 0x20 || c > 0x7E) {
      out += '\\x' + c.toString(16).padStart(2, '0');
    } else {
      out += str[i];
    }
  }
  return out;
}

// Escapa texto para escribir en archivos del ESP32 via f.write('...')
// Distinto de escapeForPythonBytes (b'...'): aqui solo se escapan
// los caracteres que rompen un string literal Python de comillas simples.
function escapeForPythonString(str) {
  return str
    .replace(/\\/g, '\\\\')
    .replace(/'/g, "\\'")
    .replace(/\n/g, '\\n')
    .replace(/\r/g, '\\r');
}

function parseFileListing(raw) {
  var lines = raw.split('\n');
  var files = [];
  var capturing = false;
  for (var i = 0; i < lines.length; i++) {
    var ln = lines[i].replace(/\r/g, '').trim();
    if (ln.indexOf('FS_START') !== -1) { capturing = true; continue; }
    if (ln.indexOf('FS_END') !== -1) break;
    if (capturing && ln.indexOf('|') !== -1) {
      var parts = ln.split('|');
      var name = parts[0].trim();
      var size = parseInt(parts[1]) || 0;
      if (name.length > 0) files.push({ name: name, size: size });
    }
  }
  return files;
}

// ─── SERIAL: BAJO NIVEL ──────────────────────────────────────
async function serialWrite(port, data) {
  var writer = port.writable.getWriter();
  try {
    if (typeof data === 'string') {
      await writer.write(new TextEncoder().encode(data));
    } else {
      await writer.write(data instanceof Uint8Array ? data : new Uint8Array(data));
    }
  } finally {
    writer.releaseLock();
  }
}

async function serialReadUntil(port, sentinel, timeoutMs) {
  var reader = port.readable.getReader();
  var decoder = new TextDecoder('utf-8', { fatal: false });
  var buf = '';
  var deadline = Date.now() + timeoutMs;
  try {
    while (Date.now() < deadline) {
      var remaining = deadline - Date.now();
      if (remaining <= 0) break;
      var result = await Promise.race([
        reader.read(),
        sleep(remaining).then(function() { return { value: null, done: true }; })
      ]);
      var value = result.value;
      var done = result.done;
      if (done || value === null) break;
      buf += decoder.decode(value, { stream: true });
      if (buf.includes(sentinel)) return buf;
    }
  } finally {
    try { await reader.cancel(); } catch (_) {}
    reader.releaseLock();
  }
  return buf;
}

// ─── SERIAL: REPL ─────────────────────────────────────────────
async function enterRawRepl(port) {
  await serialWrite(port, String.fromCharCode(3));
  await sleep(SERIAL_DELAY_MS);
  await serialWrite(port, String.fromCharCode(3));
  await sleep(500);

  await serialWrite(port, String.fromCharCode(1));
  var resp = await serialReadUntil(port, 'raw REPL', TIMEOUTS.REPL_ENTRY);
  if (!resp.includes('raw REPL')) {
    await serialWrite(port, String.fromCharCode(3));
    await sleep(SERIAL_DELAY_MS);
    await serialWrite(port, String.fromCharCode(1));
    var resp2 = await serialReadUntil(port, 'raw REPL', TIMEOUTS.REPL_ENTRY);
    if (!resp2.includes('raw REPL')) {
      throw new Error('No se pudo entrar al Raw REPL. Respuesta: ' + resp2.slice(-100));
    }
  }
}

async function execRawRepl(port, code) {
  await serialWrite(port, code + '\r\n');
  await serialWrite(port, String.fromCharCode(4));
  var result = await serialReadUntil(port, 'OK', TIMEOUTS.FILE_OP);
  return result;
}

async function execAndCapture(port, code, sentinel, timeout) {
  await serialWrite(port, code + '\r\n');
  await serialWrite(port, String.fromCharCode(4));
  return await serialReadUntil(port, sentinel, timeout || TIMEOUTS.EXEC_DEFAULT);
}

async function connectAndEnterRepl() {
  await suspendMonitor();
  var port = await navigator.serial.requestPort({ filters: USB_FILTERS });
  await port.open({ baudRate: BAUD_RATE });
  await sleep(200);
  // Interrupcion robusta: Ctrl-B (salir de raw REPL) + 5x Ctrl-C (interrumpir firmware)
  await serialWrite(port, String.fromCharCode(2));
  await sleep(SERIAL_DELAY_MS);
  for (var ci = 0; ci < 5; ci++) {
    await serialWrite(port, String.fromCharCode(3));
    await sleep(SERIAL_DELAY_MS);
  }
  await sleep(500);
  // Entrar a raw REPL
  await serialWrite(port, String.fromCharCode(1));
  var resp = await serialReadUntil(port, 'raw REPL', TIMEOUTS.REPL_ENTRY);
  if (resp.indexOf('raw REPL') === -1) {
    // Reintentar con otro ciclo de interrupciones
    for (var ri = 0; ri < 3; ri++) {
      await serialWrite(port, String.fromCharCode(3));
      await sleep(SERIAL_DELAY_MS);
    }
    await serialWrite(port, String.fromCharCode(1));
    resp = await serialReadUntil(port, 'raw REPL', TIMEOUTS.REPL_ENTRY);
    if (resp.indexOf('raw REPL') === -1) {
      await safeClosePort(port);
      throw new Error('No se pudo entrar al Raw REPL. El firmware puede estar en un sleep largo.');
    }
  }
  return port;
}

async function exitReplAndClose(port, skipReboot) {
  await serialWrite(port, String.fromCharCode(2)); // Ctrl-B: exit raw REPL
  await sleep(200);
  if (!skipReboot) {
    await serialWrite(port, String.fromCharCode(4)); // Ctrl-D: soft reboot firmware
    await sleep(TIMEOUTS.REBOOT_WAIT);
  }
  await safeClosePort(port);
  await sleep(SERIAL_DELAY_MS);
}

// ─── CARD 1: DIAGNOSTICO ─────────────────────────────────────
async function runDiagnostics() {
  if (operationInProgress) {
    showStatus('diagStatus', 'Otra operacion en curso. Espera a que termine.', 'warn');
    return;
  }
  if (!window.EspLoader || !window.Transport) {
    showStatus('diagStatus', 'Error: librerias esptool-js no cargadas. Verifica tu conexion a internet y recarga.', 'err');
    return;
  }
  provisioningData = {};
  var btn = $('btnDiag');
  var resultBox = $('diagResult');
  btn.disabled = true;
  btn.classList.add('loading');
  operationInProgress = true;
  hideStatus('diagStatus');
  resultBox.classList.add('hidden');
  resultBox.textContent = '';

  var port = null;
  var transport = null;
  try {
    showStatus('diagStatus', 'Solicitando acceso al puerto serial...', 'ok');
    port = await navigator.serial.requestPort({ filters: USB_FILTERS });
    // Do NOT call port.open() here: Transport opens it internally
    transport = new window.Transport(port, true);
    var loader = new window.EspLoader({
      transport: transport,
      baudrate: BAUD_RATE,
      romBaudrate: BAUD_RATE,
    });

    showStatus('diagStatus', 'Conectando con el chip...', 'ok');
    await loader.main();

    var info = {};

    // Nombre del chip (propiedad, no funcion)
    info.chip = loader.chip.CHIP_NAME || 'Desconocido';

    // Features
    try {
      var getFeatures = loader.chip.getChipFeatures || loader.chip.get_chip_features;
      if (getFeatures) {
        var feats = await getFeatures.call(loader.chip, loader);
        info.features = Array.isArray(feats) ? feats.join(', ') : String(feats);
      }
    } catch (_) { info.features = 'No disponible'; }

    // MAC address
    try {
      var readMac = loader.chip.readMac || loader.chip.read_mac;
      if (readMac) {
        var mac = await readMac.call(loader.chip, loader);
        if (Array.isArray(mac)) {
          info.mac = mac.map(function(b) { return b.toString(16).padStart(2, '0'); }).join(':');
        } else {
          info.mac = String(mac);
        }
      }
    } catch (_) { info.mac = 'No disponible'; }

    // Tamano de flash
    try {
      var flashSize = await loader.detectFlashSize();
      info.flash = flashSize || 'No detectado';
    } catch (_) {
      try {
        var flashId = await loader.readFlashId();
        info.flash = 'Flash ID: 0x' + flashId.toString(16);
      } catch (__) { info.flash = 'No detectado'; }
    }

    // Frecuencia del cristal
    try {
      var getCrystal = loader.chip.getCrystalFreq || loader.chip.get_crystal_freq;
      if (getCrystal) {
        var freq = await getCrystal.call(loader.chip, loader);
        info.crystal = freq + ' MHz';
      }
    } catch (_) { info.crystal = 'No disponible'; }

    // Construir resultado con pares etiqueta/valor
    resultBox.textContent = '';
    var fields = [
      ['Chip', info.chip],
      ['Features', info.features || 'N/A'],
      ['MAC', info.mac || 'N/A'],
      ['Flash', info.flash || 'N/A'],
      ['Crystal', info.crystal || 'N/A'],
    ];
    for (var fi = 0; fi < fields.length; fi++) {
      var line = document.createElement('span');
      line.className = 'line';
      var lbl = document.createElement('span');
      lbl.className = 'label';
      lbl.textContent = fields[fi][0] + ': ';
      var val = document.createElement('span');
      val.className = 'value';
      val.textContent = fields[fi][1];
      line.appendChild(lbl);
      line.appendChild(val);
      resultBox.appendChild(line);
    }
    resultBox.classList.remove('hidden');

    showStatus('diagStatus', 'Diagnostico completado. Chip detectado: ' + info.chip, 'ok');
    recordProvisioningStep('chip', info.chip);
    recordProvisioningStep('mac', info.mac);
    recordProvisioningStep('flash', info.flash);

  } catch (err) {
    showStatus('diagStatus', 'Error: ' + err.message, 'err');
  } finally {
    // Limpiar transport y puerto siempre
    if (transport) {
      try { await transport.disconnect(); } catch (_) {}
    }
    await safeClosePort(port);
    btn.disabled = false;
    btn.classList.remove('loading');
    operationInProgress = false;
  }
}

// ─── CARD 2: FLASH FIRMWARE ──────────────────────────────────
// esp-web-tools completion listener is registered in initEventListeners()

// ─── CARD 3: SUBIDA DE ARCHIVOS ──────────────────────────────
async function loadFirmwareFiles() {
  if (firmwareLoaded) return FIRMWARE_FILES;
  var resp = await fetch('firmware/files/manifest.json', { signal: AbortSignal.timeout(TIMEOUTS.FETCH) });
  if (!resp.ok) throw new Error('No se pudo cargar el manifest de firmware: HTTP ' + resp.status);
  var manifest = await resp.json();
  var files = manifest.files || [];
  var names = files.map(function(f) {
    var n = typeof f === 'string' ? f : f.name;
    return sanitizeFilename(n);
  });
  // Cargar todos los archivos en paralelo para reducir tiempo de espera
  var results = await Promise.all(names.map(function(name) {
    return fetch('firmware/files/' + name, { signal: AbortSignal.timeout(TIMEOUTS.FETCH) })
      .then(function(r) {
        if (!r.ok) throw new Error('No se pudo cargar ' + name + ': HTTP ' + r.status);
        return r.text().then(function(text) { return { name: name, text: text }; });
      });
  }));
  var loadedFiles = {};
  results.forEach(function(r) { loadedFiles[r.name] = r.text; });
  // Asignar solo despues de que todos los archivos carguen correctamente
  FIRMWARE_FILES = loadedFiles;
  KNOWN_FIRMWARE = names;
  firmwareLoaded = true;
  return FIRMWARE_FILES;
}

async function uploadFiles() {
  if (operationInProgress) {
    showStatus('uploadStatus', 'Otra operacion en curso. Espera a que termine.', 'warn');
    return;
  }
  operationInProgress = true;
  await suspendMonitor();
  var btn = $('btnUpload');
  var progressSection = $('uploadProgressSection');
  var progressFill = $('uploadProgressFill');
  var progressFile = $('uploadProgressFile');
  var progressPct = $('uploadProgressPct');
  var resultBox = $('uploadResult');

  btn.disabled = true;
  btn.classList.add('loading');

  // Cargar modulos del firmware desde el servidor
  try {
    showStatus('uploadStatus', 'Cargando modulos del firmware...', 'ok');
    await loadFirmwareFiles();
  } catch (fwErr) {
    showStatus('uploadStatus', 'Error: ' + fwErr.message, 'err');
    btn.disabled = false;
    btn.classList.remove('loading');
    operationInProgress = false;
    resumeMonitor();
    return;
  }
  hideStatus('uploadStatus');
  resultBox.textContent = '';
  resultBox.classList.add('hidden');
  progressSection.classList.remove('hidden');
  progressFill.style.width = '0%';
  progressFill.classList.add('active');
  progressPct.textContent = '0%';

  var skipReboot = false;

  try {
    showStatus('uploadStatus', 'Solicitando acceso al puerto serial...', 'ok');
    serialPort = await navigator.serial.requestPort({ filters: USB_FILTERS });
    await serialPort.open({ baudRate: BAUD_RATE });
    await sleep(200);

    showStatus('uploadStatus', 'Entrando al Raw REPL...', 'ok');
    await enterRawRepl(serialPort);

    var fileNames = Object.keys(FIRMWARE_FILES);
    var total = fileNames.length + (configData ? 1 : 0);
    var uploaded = 0;
    var results = [];

    for (var fni = 0; fni < fileNames.length; fni++) {
      var fname = fileNames[fni];
      var content = FIRMWARE_FILES[fname];
      if (!content || content.length === 0) {
        results.push(fname + ': SKIP (vacio)');
        uploaded++;
        continue;
      }
      progressFile.textContent = fname + ' (' + (uploaded + 1) + '/' + total + ')';
      showStatus('uploadStatus', 'Subiendo ' + fname + '...', 'ok');

      try {
        await execRawRepl(serialPort, "f=open('/" + fname + "','wb')");

        for (var i = 0; i < content.length; i += CHUNK_SIZE) {
          var chunk = content.substring(i, i + CHUNK_SIZE);
          var escaped = escapeForPythonBytes(chunk);
          await execRawRepl(serialPort, "f.write(b'" + escaped + "')");
        }

        await execRawRepl(serialPort, "f.close()");
        results.push(fname + ': OK');
      } catch (fileErr) {
        try { await execRawRepl(serialPort, "f.close()"); } catch (_) {}
        results.push(fname + ': ERROR - ' + fileErr.message);
      }

      uploaded++;
      var pct = Math.round((uploaded / total) * 100);
      progressFill.style.width = pct + '%';
      progressPct.textContent = pct + '%';
    }

    // Subir config.json si esta disponible
    if (configData) {
      showStatus('uploadStatus', 'Subiendo config.json (' + total + '/' + total + ')...', 'ok');
      try {
        var cfgCopy = JSON.parse(JSON.stringify(configData));
        var uiSsid = $('cfgWifiSsid').value.trim();
        var uiPass = $('cfgWifiPass').value.trim();
        if (uiSsid) cfgCopy.wifi_ssid = uiSsid;
        if (uiPass) cfgCopy.wifi_pass = uiPass;

        var jsonStr = JSON.stringify(cfgCopy, null, 2);
        if (jsonStr.length > 16384) {
          throw new Error('config.json excede el tamano maximo (16KB).');
        }
        await execRawRepl(serialPort, "f=open('/config.json','w')");

        for (var ci = 0; ci < jsonStr.length; ci += CHUNK_SIZE) {
          var cfgChunk = escapeForPythonString(jsonStr.slice(ci, ci + CHUNK_SIZE));
          await execRawRepl(serialPort, "f.write('" + cfgChunk + "')");
        }
        await execRawRepl(serialPort, "f.close()");
        results.push('config.json: OK');
      } catch (cfgErr) {
        try { await execRawRepl(serialPort, "f.close()"); } catch (_) {}
        results.push('config.json: ERROR - ' + cfgErr.message);
      }
      uploaded++;
      progressFill.style.width = '100%';
    } else {
      // Sin config cargado: no reiniciar, avisar al usuario
      skipReboot = true;
    }

    resultBox.textContent = '';
    for (var ri = 0; ri < results.length; ri++) {
      var row = document.createElement('div');
      row.className = 'upload-row';
      var isOk = results[ri].includes(': OK');
      var icon = document.createElement('span');
      icon.className = isOk ? 'check' : 'cross';
      icon.textContent = isOk ? '\u2713' : '\u2717';
      var fnameSpan = document.createElement('span');
      fnameSpan.className = 'fname';
      fnameSpan.textContent = results[ri].split(':')[0];
      var fstatus = document.createElement('span');
      fstatus.className = 'fstatus';
      fstatus.textContent = isOk ? 'OK' : results[ri].split(': ').slice(1).join(': ');
      row.appendChild(icon);
      row.appendChild(fnameSpan);
      row.appendChild(fstatus);
      resultBox.appendChild(row);
    }
    resultBox.classList.remove('hidden');
    progressFile.textContent = 'Verificando...';
    progressPct.textContent = '100%';
    progressFill.style.width = '100%';

    // Verificacion del filesystem: listar archivos en el ESP32
    try {
      var lsResult = await execRawRepl(serialPort, "import os; print('\\n'.join(os.listdir('/')))");
      var lsParts = lsResult.split('OK');
      var lsOutput = lsParts.length > 1 ? lsParts.slice(1).join('OK') : lsResult;
      var fsFiles = lsOutput.split('\n').map(function(l) { return l.trim(); }).filter(function(l) { return l.length > 0 && l.indexOf('>') === -1 && l.indexOf('\x04') === -1; });
      var missing = [];
      var fileNames2 = Object.keys(FIRMWARE_FILES);
      for (var vi = 0; vi < fileNames2.length; vi++) {
        if (fsFiles.indexOf(fileNames2[vi]) === -1) missing.push(fileNames2[vi]);
      }
      if (missing.length > 0) {
        showStatus('uploadStatus', missing.length + ' archivo(s) no encontrado(s) en el ESP32: ' + missing.join(', '), 'warn');
      }
    } catch (_) { /* verification is best-effort */ }

    progressFile.textContent = 'Completado';
    progressFill.classList.remove('active');

    if (skipReboot) {
      showStatus('uploadStatus', 'Archivos subidos. Carga config.json en el Paso 4 antes de reiniciar.', 'warn');
      // Do NOT exit raw REPL or reboot; ESP32 stays in REPL for Card 4
    } else {
      // Salir de raw REPL (Ctrl-B) y reiniciar (Ctrl-D)
      showStatus('uploadStatus', 'Archivos subidos. Reiniciando ESP32...', 'ok');
      await serialWrite(serialPort, String.fromCharCode(2));
      await sleep(SERIAL_DELAY_MS);
      await serialWrite(serialPort, String.fromCharCode(4));
      await sleep(TIMEOUTS.REBOOT_WAIT);
      await safeClosePort(serialPort);
      serialPort = null;
    }

    var errCount = results.filter(function(r) { return r.includes('ERROR'); }).length;
    recordProvisioningStep('filesUploaded', results.filter(function(r) { return r.indexOf('OK') !== -1; }).length);
    recordProvisioningStep('filesErrors', errCount);
    if (errCount > 0) {
      showStatus('uploadStatus', errCount + ' archivo(s) con error. Revisa los resultados.', 'err');
    } else if (!skipReboot) {
      showStatus('uploadStatus', 'Todos los archivos subidos correctamente. ESP32 reiniciado.', 'ok');
    }

  } catch (err) {
    showStatus('uploadStatus', 'Error: ' + err.message, 'err');
    if (serialPort) {
      await safeClosePort(serialPort);
      serialPort = null;
    }
  } finally {
    btn.disabled = false;
    btn.classList.remove('loading');
    operationInProgress = false;
    resumeMonitor();
  }
}

// ─── CARD 4: CONFIGURACION ───────────────────────────────────
function loadConfigFile(file) {
  var reader = new FileReader();
  reader.onload = function(e) {
    try {
      var parsed = JSON.parse(e.target.result);
      configData = parsed;
      showConfigSummary(parsed);
    } catch (err) {
      showStatus('configFileStatus', 'Error al parsear JSON: ' + err.message, 'err');
    }
  };
  reader.readAsText(file);
}

function showConfigSummary(cfg) {
  $('configSummary').classList.remove('hidden');
  var pillsEl = $('configPills');
  pillsEl.textContent = '';

  var fields = [
    ['server_url', cfg.server_url],
    ['server_port', cfg.server_port],
    ['device_id', cfg.device_id],
    ['api_key', cfg.api_key ? '***' + cfg.api_key.slice(-6) : null],
    ['device_key_hex', cfg.device_key_hex ? cfg.device_key_hex.slice(0,8) + '...' : null],
    ['server_key_hex', cfg.server_key_hex ? cfg.server_key_hex.slice(0,8) + '...' : null],
    ['read_interval_s', cfg.read_interval_s],
    ['location', cfg.location],
    ['wifi_ssid', cfg.wifi_ssid],
    ['wifi_pass', cfg.wifi_pass ? '***' : null],
  ];

  for (var i = 0; i < fields.length; i++) {
    var key = fields[i][0];
    var val = fields[i][1];
    var row = document.createElement('div');
    row.className = 'cfg-field';
    var lbl = document.createElement('span');
    lbl.className = 'cfg-label';
    lbl.textContent = key;
    var valEl = document.createElement('span');
    var isReplace = typeof val === 'string' && val === 'REPLACE';
    var isPending = val === null || val === undefined || isReplace;
    valEl.className = 'cfg-value' + (isPending ? ' pending' : '');
    valEl.textContent = isPending ? (isReplace ? 'PENDIENTE' : 'N/A') : val;
    row.appendChild(lbl);
    row.appendChild(valEl);
    pillsEl.appendChild(row);
  }

  // Pre-fill WiFi fields if present and not REPLACE
  var ssidInput = $('cfgWifiSsid');
  var passInput = $('cfgWifiPass');
  if (cfg.wifi_ssid && cfg.wifi_ssid !== 'REPLACE') ssidInput.value = cfg.wifi_ssid;
  if (cfg.wifi_pass && cfg.wifi_pass !== 'REPLACE') passInput.value = cfg.wifi_pass;

  // Highlight REPLACE
  if (cfg.wifi_ssid === 'REPLACE') ssidInput.placeholder = 'PENDIENTE: ingresa el SSID';
  if (cfg.wifi_pass === 'REPLACE') passInput.placeholder = 'PENDIENTE: ingresa la contrasena';
}

async function uploadConfigToDevice(jsonStr) {
  await suspendMonitor();
  var port = serialPort;
  var ownPort = false;

  try {
    if (!port || !port.readable) {
      port = await navigator.serial.requestPort({ filters: USB_FILTERS });
      await port.open({ baudRate: BAUD_RATE });
      ownPort = true;
    }

    // First, exit raw REPL if we're already in it (after skipReboot path).
    // Ctrl-B exits raw REPL to normal REPL. Safe to send even if not in raw REPL.
    await serialWrite(port, String.fromCharCode(2));
    await sleep(SERIAL_DELAY_MS);

    // Interrupcion robusta: 5x Ctrl-C con delays de 300ms (maneja modo UART provisioning)
    for (var i = 0; i < 5; i++) {
      await serialWrite(port, String.fromCharCode(3));
      await sleep(SERIAL_DELAY_MS);
    }
    await sleep(500);

    // Entrar a raw REPL con reintento
    await serialWrite(port, String.fromCharCode(1));
    var resp = await serialReadUntil(port, 'raw REPL', TIMEOUTS.REPL_ENTRY);
    if (!resp.includes('raw REPL')) {
      await serialWrite(port, String.fromCharCode(3));
      await sleep(SERIAL_DELAY_MS);
      await serialWrite(port, String.fromCharCode(1));
      resp = await serialReadUntil(port, 'raw REPL', TIMEOUTS.REPL_ENTRY);
      if (!resp.includes('raw REPL')) {
        throw new Error('No se pudo entrar al Raw REPL.');
      }
    }

    // Escritura atomica: escribir en .tmp y renombrar (original intacto si falla)
    await execRawRepl(port, "f=open('/config.json.tmp','w')");

    for (var ci = 0; ci < jsonStr.length; ci += CHUNK_SIZE) {
      var chunk = escapeForPythonString(jsonStr.slice(ci, ci + CHUNK_SIZE));
      await execRawRepl(port, "f.write('" + chunk + "')");
    }
    await execRawRepl(port, "f.close()");
    await execRawRepl(port, "import os;os.rename('/config.json.tmp','/config.json')");

    // Salir de raw REPL y reiniciar
    await serialWrite(port, String.fromCharCode(2));
    await sleep(SERIAL_DELAY_MS);
    await serialWrite(port, String.fromCharCode(4));
    await sleep(TIMEOUTS.REBOOT_WAIT);

    if (ownPort) {
      await safeClosePort(port);
    } else {
      await safeClosePort(serialPort);
      serialPort = null;
    }

    return true;
  } catch (err) {
    if (ownPort) {
      await safeClosePort(port);
    } else {
      // Puerto compartido quedo en estado desconocido, cerrarlo para evitar corrupcion
      await safeClosePort(serialPort);
      serialPort = null;
    }
    throw err;
  }
}

async function uploadConfigFromFile() {
  if (operationInProgress) {
    showStatus('configFileStatus', 'Otra operacion en curso. Espera a que termine.', 'warn');
    return;
  }
  if (!configData) {
    showStatus('configFileStatus', 'No se ha cargado ningun archivo config.json.', 'err');
    return;
  }
  hideStatus('configFileStatus');
  var btn = $('btnUploadConfig');
  if (btn) { btn.disabled = true; btn.classList.add('loading'); }
  operationInProgress = true;
  try {
    var cfgCopy = JSON.parse(JSON.stringify(configData));
    var uiSsid = $('cfgWifiSsid').value.trim();
    var uiPass = $('cfgWifiPass').value.trim();
    if (uiSsid) cfgCopy.wifi_ssid = uiSsid;
    if (uiPass) cfgCopy.wifi_pass = uiPass;

    showStatus('configFileStatus', 'Subiendo config.json al ESP32...', 'ok');
    var jsonStr = JSON.stringify(cfgCopy, null, 2);
    await uploadConfigToDevice(jsonStr);
    showStatus('configFileStatus', 'config.json subido correctamente. ESP32 reiniciado.', 'ok');
    recordProvisioningStep('serverUrl', cfgCopy.server_url);
    recordProvisioningStep('serverPort', cfgCopy.server_port);
    recordProvisioningStep('deviceId', cfgCopy.device_id);
    recordProvisioningStep('wifiSsid', cfgCopy.wifi_ssid);
    showProvisioningReport();
  } catch (err) {
    showStatus('configFileStatus', 'Error: ' + err.message, 'err');
  } finally {
    if (btn) { btn.disabled = false; btn.classList.remove('loading'); }
    operationInProgress = false;
    resumeMonitor();
  }
}

function toggleManualForm() {
  var form = $('manualForm');
  form.classList.toggle('visible');
}

async function uploadManualConfig() {
  if (operationInProgress) {
    showStatus('manualConfigStatus', 'Otra operacion en curso. Espera a que termine.', 'warn');
    return;
  }
  hideStatus('manualConfigStatus');

  // Validate BEFORE acquiring the lock
  var wifiSsid = $('mWifiSsid').value.trim();
  var wifiPass = $('mWifiPass').value.trim();
  var serverUrl = $('mServerUrl').value.trim().replace(/^(https?:\/\/)+/, '$1');
  if (serverUrl && !/^https?:\/\//.test(serverUrl)) serverUrl = 'http://' + serverUrl;
  var serverPort = parseInt($('mServerPort').value) || 5000;
  var deviceId = $('mDeviceId').value.trim();
  var apiKey = $('mApiKey').value.trim();
  var deviceKeyHex = $('mDeviceKey').value.trim();
  var serverKeyHex = $('mServerKey').value.trim();
  var interval = parseInt($('mInterval').value) || 30;
  var location = $('mLocation').value.trim();

  var hexRegex = /^[0-9a-fA-F]{64}$/;
  if (!wifiSsid) {
    showStatus('manualConfigStatus', 'WiFi SSID es requerido.', 'err');
    return;
  }
  try { var u = new URL(serverUrl); if (u.protocol !== 'http:' && u.protocol !== 'https:') throw 0; }
  catch (_) { showStatus('manualConfigStatus', 'URL del servidor invalida (ej: http://192.168.1.100).', 'err'); return; }
  if (!apiKey) {
    showStatus('manualConfigStatus', 'API Key es requerida.', 'err');
    return;
  }
  if (!hexRegex.test(deviceKeyHex)) {
    showStatus('manualConfigStatus', 'Device Key debe tener exactamente 64 caracteres hexadecimales (0-9, a-f).', 'err');
    return;
  }
  if (!hexRegex.test(serverKeyHex)) {
    showStatus('manualConfigStatus', 'Server Key debe tener exactamente 64 caracteres hexadecimales (0-9, a-f).', 'err');
    return;
  }

  // Lock adquirido DESPUES de pasar la validacion
  var mBtn = $('btnManualUpload');
  if (mBtn) { mBtn.disabled = true; mBtn.classList.add('loading'); }
  operationInProgress = true;

  var cfg = {
    wifi_ssid: wifiSsid,
    wifi_pass: wifiPass,
    server_url: serverUrl,
    server_port: serverPort,
    device_id: deviceId,
    api_key: apiKey,
    device_key_hex: deviceKeyHex.toLowerCase(),
    server_key_hex: serverKeyHex.toLowerCase(),
    read_interval_s: interval,
    location: location,
    thresholds: {
      temp_high: 35,
      temp_low: 18,
      humidity_high: 80,
      noise_high_v: 2.5,
      noise_medium_v: 2.0
    }
  };

  try {
    showStatus('manualConfigStatus', 'Subiendo config.json al ESP32...', 'ok');
    var jsonStr = JSON.stringify(cfg, null, 2);
    await uploadConfigToDevice(jsonStr);
    showStatus('manualConfigStatus', 'config.json subido correctamente. ESP32 reiniciado.', 'ok');
    recordProvisioningStep('serverUrl', cfg.server_url);
    recordProvisioningStep('serverPort', cfg.server_port);
    recordProvisioningStep('deviceId', cfg.device_id);
    recordProvisioningStep('wifiSsid', cfg.wifi_ssid);
    showProvisioningReport();
  } catch (err) {
    showStatus('manualConfigStatus', 'Error: ' + err.message, 'err');
  } finally {
    if (mBtn) { mBtn.disabled = false; mBtn.classList.remove('loading'); }
    operationInProgress = false;
    resumeMonitor();
  }
}

// ─── CARD 5: MONITOR SERIAL ──────────────────────────────────
function classifyLine(line) {
  if (/error|fail|fatal|traceback|exception/i.test(line)) return 'log-error';
  if (/\bok\b|success|connected|readings stored/i.test(line)) return 'log-success';
  if (/warn|retry|409/i.test(line)) return 'log-warn';
  if (/config|device|firmware/i.test(line)) return 'log-info';
  return 'log-default';
}

function appendLine(text, cls) {
  var con = $('serialConsole');
  var now = Date.now();
  var elapsed = monitorStartTime ? ((now - monitorStartTime) / 1000).toFixed(1) : '0.0';
  var ts = new Date(now).toLocaleTimeString('en-US', { hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' });

  // Almacenar en buffer (limitado a MAX_LINES)
  monitorLines.push({ text: text, cls: cls, ts: ts, elapsed: elapsed });
  if (monitorLines.length > MAX_LINES) monitorLines.shift();

  var div = document.createElement('div');
  div.className = 'log-line ' + cls;
  div.setAttribute('data-text', text.toLowerCase());

  if (showTimestamps) {
    var tsSpan = document.createElement('span');
    tsSpan.className = 'log-ts';
    tsSpan.textContent = '+' + elapsed + 's';
    div.appendChild(tsSpan);
  }

  div.appendChild(document.createTextNode(text));

  // Aplicar filtro
  if (currentFilter && !matchesFilter(text, currentFilter, null)) {
    div.classList.add('filtered');
  }

  con.appendChild(div);
  lineCount++;

  while (lineCount > MAX_LINES) {
    if (con.firstElementChild) { con.removeChild(con.firstElementChild); lineCount--; }
    else break;
  }

  // Agrupar scroll en requestAnimationFrame para evitar reflow por cada linea
  // durante rafagas de output serial. El flag se guarda en la propia funcion.
  if (!appendLine._scrollPending) {
    appendLine._scrollPending = true;
    requestAnimationFrame(function() {
      con.scrollTop = con.scrollHeight;
      appendLine._scrollPending = false;
    });
  }

  // Detect Redis 409 stale session error
  if (text.indexOf('409') !== -1 && text.indexOf('stale session') !== -1) showRedisAlert();
  if (text.indexOf('All stale session retries exhausted') !== -1) showRedisAlert();
}

// Acepta texto plano (busca substring) o regex (/patron/)
// Si se pasa un RegExp compilado, lo usa directamente para evitar recompilar por linea.
function matchesFilter(text, filter, compiledRe) {
  if (compiledRe) return compiledRe.test(text);
  if (filter.length > 2 && filter[0] === '/' && filter[filter.length - 1] === '/') {
    try { return new RegExp(filter.slice(1, -1), 'i').test(text); } catch (_) { return true; }
  }
  return text.toLowerCase().indexOf(filter.toLowerCase()) !== -1;
}

var _filterTimer = null;
function applyFilter() {
  clearTimeout(_filterTimer);
  _filterTimer = setTimeout(function() {
    currentFilter = $('monFilterInput').value.trim();
    // Compilar regex una sola vez si el filtro es /patron/
    var compiledRe = null;
    if (currentFilter.length > 2 && currentFilter[0] === '/' && currentFilter[currentFilter.length - 1] === '/') {
      try { compiledRe = new RegExp(currentFilter.slice(1, -1), 'i'); } catch (_) { return; }
    }
    var lines = $('serialConsole').querySelectorAll('.log-line');
    for (var i = 0; i < lines.length; i++) {
      var lineText = lines[i].getAttribute('data-text') || lines[i].textContent;
      if (!currentFilter || matchesFilter(lineText, currentFilter, compiledRe)) {
        lines[i].classList.remove('filtered');
      } else {
        lines[i].classList.add('filtered');
      }
    }
  }, 150);
}

function toggleTimestamps() {
  showTimestamps = $('monTimestamps').checked;
}

function copyLog() {
  var lines;
  if (currentFilter) {
    lines = monitorLines.filter(function(l) { return matchesFilter(l.text, currentFilter); });
  } else {
    lines = monitorLines;
  }
  if (lines.length === 0) return;
  var text = lines.map(function(l) { return l.text; }).join('\n');
  var btn = $('btnCopyLog');
  navigator.clipboard.writeText(text).then(function() {
    var orig = btn.textContent;
    btn.textContent = ' Copiado';
    setTimeout(function() { btn.textContent = orig; }, 2000);
  }).catch(function() {
    prompt('Copia manualmente:', text.substring(0, 2000));
  });
}

function exportLog() {
  if (monitorLines.length === 0) return;
  var content = monitorLines.map(function(l) {
    return '[' + l.ts + ' +' + l.elapsed + 's] ' + l.text;
  }).join('\n');
  var a = document.createElement('a');
  a.href = 'data:text/plain;charset=utf-8,' + encodeURIComponent(content);
  a.setAttribute('download', 'serial-log-' + new Date().toISOString().slice(0, 19).replace(/:/g, '') + '.log');
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
}

function showRedisAlert() {
  if (redisAlertShown) return;
  redisAlertShown = true;
  $('redisAlert').classList.add('visible');
}

function copyRedisCmd() {
  var cmd = $('redisCmd').textContent;
  navigator.clipboard.writeText(cmd).then(function() {
    var btn = document.querySelector('.redis-alert__copy');
    btn.textContent = 'Copiado';
    setTimeout(function() { btn.textContent = 'Copiar'; }, 2000);
  }).catch(function() {
    prompt('Copia este comando manualmente:', cmd);
  });
}

async function startMonitor(existingPort) {
  if (monitorRunning) return;
  autoReconnect = true;
  var btnStart = $('btnMonStart');
  var btnStop = $('btnMonStop');
  monitorStartTime = monitorStartTime || Date.now();

  try {
    if (existingPort) {
      monitorPort = existingPort;
    } else {
      monitorPort = await navigator.serial.requestPort({ filters: USB_FILTERS });
      await monitorPort.open({ baudRate: BAUD_RATE });
    }

    monitorRunning = true;
    btnStart.disabled = true;
    btnStop.disabled = false;

    var reader = monitorPort.readable.getReader();
    serialReader = reader;
    var decoder = new TextDecoder('utf-8', { fatal: false });
    var lineBuf = '';

    try {
      while (monitorRunning) {
        var result = await reader.read();
        var value = result.value;
        var done = result.done;
        if (done) break;

        lineBuf += decoder.decode(value, { stream: true });
        var parts = lineBuf.split('\n');
        lineBuf = parts.pop(); // keep incomplete fragment

        for (var pi = 0; pi < parts.length; pi++) {
          var line = parts[pi].replace(/\r/g, '');
          if (line.length === 0) continue;
          appendLine(line, classifyLine(line));
        }
      }
    } catch (readErr) {
      if (monitorRunning) {
        appendLine('[Monitor error: ' + readErr.message + ']', 'log-error');
      }
    }

    // Vaciar buffer restante
    if (lineBuf.length > 0) {
      var flushed = lineBuf.replace(/\r/g, '');
      if (flushed.length > 0) {
        appendLine(flushed, classifyLine(flushed));
      }
    }

  } catch (err) {
    appendLine('[Error al conectar: ' + err.message + ']', 'log-error');
  } finally {
    var shouldReconnect = autoReconnect;
    if (serialReader) {
      try { await serialReader.cancel(); } catch (_) {}
      try { serialReader.releaseLock(); } catch (_) {}
      serialReader = null;
    }
    if (monitorPort) {
      await safeClosePort(monitorPort);
      monitorPort = null;
    }
    monitorRunning = false;
    var bStart = $('btnMonStart');
    var bStop = $('btnMonStop');
    if (bStart) bStart.disabled = false;
    if (bStop) bStop.disabled = true;

    // Reconexion automatica si no fue detenido manualmente
    if (shouldReconnect) {
      appendLine('[Monitor desconectado. Reintentando en 3s...]', 'log-warn');
      await sleep(3000);
      if (autoReconnect) {
        try {
          var ports = await navigator.serial.getPorts();
          for (var pi2 = 0; pi2 < ports.length; pi2++) {
            try {
              await ports[pi2].open({ baudRate: BAUD_RATE });
              appendLine('[Reconectado automaticamente]', 'log-success');
              startMonitor(ports[pi2]);
              return;
            } catch (_) {}
          }
          appendLine('[No se pudo reconectar. Presiona Iniciar.]', 'log-warn');
        } catch (_) {
          appendLine('[Auto-reconnect no disponible.]', 'log-warn');
        }
      }
    }
  }
}

async function suspendMonitor() {
  if (!monitorRunning) return false;
  await stopMonitor();
  monitorSuspended = true;
  appendLine('[Monitor pausado para operacion serial]', 'log-warn');
  return true;
}

async function resumeMonitor() {
  if (!monitorSuspended) return;
  appendLine('[Reanudando monitor...]', 'log-info');
  await sleep(TIMEOUTS.RESUME_DELAY);
  // Verificar que sigue pendiente (otra operacion pudo haber llamado suspend/resume)
  if (!monitorSuspended) return;
  monitorSuspended = false;
  // Usar getPorts() en vez de requestPort() para evitar requerir gesto de usuario
  try {
    var ports = await navigator.serial.getPorts();
    if (ports.length > 0) {
      await ports[0].open({ baudRate: BAUD_RATE });
      startMonitor(ports[0]);
    } else {
      appendLine('[No se encontro puerto autorizado. Presiona Iniciar.]', 'log-warn');
    }
  } catch (e) {
    appendLine('[No se pudo reconectar: ' + e.message + ']', 'log-warn');
  }
}

async function stopMonitor() {
  autoReconnect = false;
  monitorRunning = false;
  var btnStart = $('btnMonStart');
  var btnStop = $('btnMonStop');

  if (serialReader) {
    try { await serialReader.cancel(); } catch (_) {}
    try { serialReader.releaseLock(); } catch (_) {}
    serialReader = null;
  }
  if (monitorPort) {
    await safeClosePort(monitorPort);
    monitorPort = null;
  }

  btnStart.disabled = false;
  btnStop.disabled = true;
}

async function rebootDevice() {
  if (operationInProgress) return;
  operationInProgress = true;
  await suspendMonitor();
  var port = null;
  try {
    port = await navigator.serial.requestPort({ filters: USB_FILTERS });
    await port.open({ baudRate: BAUD_RATE });
    await sleep(200);
    await serialWrite(port, String.fromCharCode(3));
    await sleep(200);
    await serialWrite(port, String.fromCharCode(3));
    await sleep(200);
    await serialWrite(port, String.fromCharCode(4));
    await sleep(TIMEOUTS.REBOOT_WAIT);
    await safeClosePort(port);
    appendLine('[ESP32 reiniciado via serial]', 'log-success');
  } catch (err) {
    if (err.name !== 'NotFoundError') {
      appendLine('[Error al reiniciar: ' + err.message + ']', 'log-error');
    }
    await safeClosePort(port);
  } finally {
    operationInProgress = false;
  }
  await resumeMonitor();
}

function clearMonitor() {
  var con = $('serialConsole');
  con.textContent = '';
  lineCount = 0;
  monitorLines = [];
  redisAlertShown = false;
  $('redisAlert').classList.remove('visible');
}

// ─── CARD 5B: REPORTE DE PROVISIONAMIENTO ────────────────────
function recordProvisioningStep(key, value) {
  provisioningData[key] = value;
  provisioningData.timestamp = new Date().toISOString();
}

function showProvisioningReport() {
  var card = $('cardReport');
  var content = $('reportContent');
  if (!provisioningData.timestamp) return;

  var lines = [];
  lines.push('=== Reporte de Provisionamiento ===');
  lines.push('Fecha: ' + provisioningData.timestamp);
  lines.push('');
  if (provisioningData.chip) {
    lines.push('--- Diagnostico ---');
    lines.push('Chip: ' + (provisioningData.chip || 'N/A'));
    lines.push('MAC: ' + (provisioningData.mac || 'N/A'));
    lines.push('Flash: ' + (provisioningData.flash || 'N/A'));
    lines.push('');
  }
  lines.push('--- Firmware ---');
  lines.push('MicroPython: ' + MICROPYTHON_VERSION);
  lines.push('Archivos subidos: ' + (provisioningData.filesUploaded || 'N/A'));
  lines.push('Errores: ' + (provisioningData.filesErrors || '0'));
  lines.push('');
  if (provisioningData.serverUrl) {
    lines.push('--- Configuracion ---');
    lines.push('Server: ' + provisioningData.serverUrl + ':' + (provisioningData.serverPort || ''));
    lines.push('Device ID: ' + (provisioningData.deviceId || 'N/A'));
    lines.push('WiFi SSID: ' + (provisioningData.wifiSsid || 'N/A'));
    lines.push('');
  }
  lines.push('--- Estado ---');
  lines.push('Autenticacion: ' + (provisioningData.authStatus || 'Pendiente (revisar monitor serial)'));

  content.textContent = lines.join('\n');
  card.classList.remove('hidden');
  card.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
}

function downloadReport() {
  var text = $('reportContent').textContent;
  var a = document.createElement('a');
  a.href = 'data:text/plain;charset=utf-8,' + encodeURIComponent(text);
  var id = provisioningData.deviceId || 'device';
  a.setAttribute('download', 'provisioning-report-' + id + '-' + new Date().toISOString().slice(0, 10) + '.txt');
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
}

function generateQR() {
  if (typeof qrcode === 'undefined') {
    alert('Libreria QR no cargada. Verifica la conexion a internet.');
    return;
  }
  var text = 'DISPOSITIVO IoT\n' +
    'ID: ' + (provisioningData.deviceId || '?') + '\n' +
    'MAC: ' + (provisioningData.mac || '?') + '\n' +
    'FW: MicroPython ' + MICROPYTHON_VERSION + '\n' +
    'Server: ' + (provisioningData.serverUrl || '').replace('http://', '').replace('https://', '') + ':' + (provisioningData.serverPort || '') + '\n' +
    'WiFi: ' + (provisioningData.wifiSsid || '?') + '\n' +
    'Fecha: ' + (provisioningData.timestamp || new Date().toISOString()).slice(0, 19);
  var qr;
  try {
    qr = qrcode(0, 'M');
    qr.addData(text);
    qr.make();
  } catch (qrErr) {
    alert('Error al generar QR: ' + qrErr.message);
    return;
  }

  var canvas = $('qrCanvas');
  var size = 200;
  canvas.width = size;
  canvas.height = size;
  canvas.classList.remove('hidden');
  var ctx = canvas.getContext('2d');
  var cellSize = size / qr.getModuleCount();
  ctx.fillStyle = '#181825';
  ctx.fillRect(0, 0, size, size);
  ctx.fillStyle = '#a78bfa';
  for (var r = 0; r < qr.getModuleCount(); r++) {
    for (var c = 0; c < qr.getModuleCount(); c++) {
      if (qr.isDark(r, c)) {
        ctx.fillRect(c * cellSize, r * cellSize, cellSize + 0.5, cellSize + 0.5);
      }
    }
  }
}

// ─── CARD 6: GESTION DE DISPOSITIVO ──────────────────────────
function switchMgmtTab(tabId) {
  var tabs = document.querySelectorAll('.mgmt-tab');
  var panels = document.querySelectorAll('.mgmt-panel');
  for (var i = 0; i < tabs.length; i++) tabs[i].classList.remove('active');
  for (var i = 0; i < panels.length; i++) panels[i].classList.add('hidden');
  $(tabId).classList.remove('hidden');
  var btns = document.querySelectorAll('.mgmt-tab');
  for (var i = 0; i < btns.length; i++) {
    if (btns[i].getAttribute('data-tab') === tabId) btns[i].classList.add('active');
  }
}

// --- Config Tab ---
async function readDeviceConfig() {
  if (operationInProgress) { showStatus('mgmtConfigStatus', 'Otra operacion en curso.', 'warn'); return; }
  operationInProgress = true;
  var btn = $('btnReadConfig');
  btn.disabled = true; btn.classList.add('loading');
  hideStatus('mgmtConfigStatus');
  var port = null;
  try {
    showStatus('mgmtConfigStatus', 'Conectando al ESP32...', 'ok');
    port = await connectAndEnterRepl();
    showStatus('mgmtConfigStatus', 'Leyendo config.json...', 'ok');
    var code = "f=open('/config.json','r');d=f.read();f.close();print('CFG_READ_START');print(d);print('CFG_READ_END')";
    var result = await execAndCapture(port, code, 'CFG_READ_END', TIMEOUTS.FILE_OP);
    await exitReplAndClose(port);
    port = null;

    // Parse: extract between CFG_READ_START and CFG_READ_END
    var startIdx = result.indexOf('CFG_READ_START');
    var endIdx = result.indexOf('CFG_READ_END');
    if (startIdx === -1 || endIdx === -1) throw new Error('No se pudo leer config.json del ESP32.');
    var jsonStr = result.substring(startIdx + 14, endIdx).trim();
    // Limpiar caracteres de control
    jsonStr = jsonStr.replace(/[\x00-\x08\x0b\x0c\x0e-\x1f]/g, '').trim();
    if (jsonStr.charAt(0) === '\n') jsonStr = jsonStr.substring(1);

    var cfg = JSON.parse(jsonStr);
    mgmtOriginalConfig = cfg;
    populateConfigForm(cfg);
    showStatus('mgmtConfigStatus', 'Configuracion leida correctamente.', 'ok');
  } catch (err) {
    showStatus('mgmtConfigStatus', 'Error: ' + err.message, 'err');
    await safeClosePort(port);
  } finally {
    btn.disabled = false; btn.classList.remove('loading');
    operationInProgress = false;
    resumeMonitor();
  }
}

function populateConfigForm(cfg) {
  var container = $('mgmtConfigForm');
  container.classList.remove('hidden');
  container.textContent = '';

  var editableFields = [
    { key: 'wifi_ssid', label: 'WiFi SSID', type: 'text' },
    { key: 'wifi_pass', label: 'WiFi Password', type: 'password' },
    { key: 'server_url', label: 'Server URL', type: 'text' },
    { key: 'server_port', label: 'Server Port', type: 'number' },
    { key: 'read_interval_s', label: 'Intervalo (s)', type: 'number' },
    { key: 'location', label: 'Ubicacion', type: 'text' },
  ];
  var readonlyFields = [
    { key: 'device_id', label: 'Device ID' },
    { key: 'api_key', label: 'API Key', truncate: true },
    { key: 'device_key_hex', label: 'Device Key', truncate: true },
    { key: 'server_key_hex', label: 'Server Key', truncate: true },
  ];

  var grid = document.createElement('div');
  grid.className = 'mgmt-config-grid';

  function addField(key, label, type, value, readonly, full) {
    var field = document.createElement('div');
    field.className = 'mgmt-field' + (full ? ' full' : '');
    var lbl = document.createElement('label');
    lbl.textContent = label;
    lbl.setAttribute('for', 'mgmt-' + key);
    var inp = document.createElement('input');
    inp.type = type || 'text';
    inp.id = 'mgmt-' + key;
    inp.value = value !== null && value !== undefined ? value : '';
    if (readonly) { inp.readOnly = true; }
    field.appendChild(lbl);
    field.appendChild(inp);
    grid.appendChild(field);
  }

  for (var i = 0; i < editableFields.length; i++) {
    var f = editableFields[i];
    addField(f.key, f.label, f.type, cfg[f.key], false, f.key === 'server_url');
  }
  for (var i = 0; i < readonlyFields.length; i++) {
    var f = readonlyFields[i];
    var val = cfg[f.key];
    if (f.truncate && typeof val === 'string' && val.length > 12) val = val.substring(0, 8) + '...' + val.substring(val.length - 4);
    addField(f.key, f.label, 'text', val, true, f.key.indexOf('_key') !== -1);
  }

  container.appendChild(grid);
  $('btnSaveConfig').classList.remove('hidden');
}

async function saveDeviceConfig() {
  if (operationInProgress) { showStatus('mgmtConfigStatus', 'Otra operacion en curso.', 'warn'); return; }
  if (!mgmtOriginalConfig) { showStatus('mgmtConfigStatus', 'Lee la configuracion primero.', 'err'); return; }

  // Combinar campos editados con la config original
  var cfg = JSON.parse(JSON.stringify(mgmtOriginalConfig));
  cfg.wifi_ssid = $('mgmt-wifi_ssid').value.trim();
  cfg.wifi_pass = $('mgmt-wifi_pass').value;
  var sUrl = $('mgmt-server_url').value.trim().replace(/^(https?:\/\/)+/, '$1');
  if (sUrl && !/^https?:\/\//.test(sUrl)) sUrl = 'http://' + sUrl;
  cfg.server_url = sUrl;
  cfg.server_port = parseInt($('mgmt-server_port').value) || cfg.server_port;
  cfg.read_interval_s = parseInt($('mgmt-read_interval_s').value) || cfg.read_interval_s;
  cfg.location = $('mgmt-location').value.trim();

  if (!cfg.wifi_ssid) { showStatus('mgmtConfigStatus', 'WiFi SSID es requerido.', 'err'); return; }

  operationInProgress = true;
  var btn = $('btnSaveConfig');
  btn.disabled = true; btn.classList.add('loading');
  try {
    showStatus('mgmtConfigStatus', 'Guardando configuracion en ESP32...', 'ok');
    var jsonStr = JSON.stringify(cfg, null, 2);
    await uploadConfigToDevice(jsonStr);
    showStatus('mgmtConfigStatus', 'Configuracion actualizada. ESP32 reiniciado.', 'ok');
    mgmtOriginalConfig = cfg;
  } catch (err) {
    showStatus('mgmtConfigStatus', 'Error: ' + err.message, 'err');
  } finally {
    btn.disabled = false; btn.classList.remove('loading');
    operationInProgress = false;
    resumeMonitor();
  }
}

// --- Files Tab ---
async function readDeviceFiles() {
  if (operationInProgress) { showStatus('mgmtFileStatus', 'Otra operacion en curso.', 'warn'); return; }
  operationInProgress = true;
  var btn = $('btnReadFiles');
  btn.disabled = true; btn.classList.add('loading');
  hideStatus('mgmtFileStatus');
  var port = null;
  try {
    showStatus('mgmtFileStatus', 'Conectando al ESP32...', 'ok');
    port = await connectAndEnterRepl();
    showStatus('mgmtFileStatus', 'Leyendo sistema de archivos...', 'ok');
    var result = await execAndCapture(port, FS_LIST_CMD, 'FS_END', TIMEOUTS.FILE_OP);
    await exitReplAndClose(port);
    port = null;

    var files = parseFileListing(result);

    displayFileList(files);
    showStatus('mgmtFileStatus', files.length + ' archivos encontrados.', 'ok');
  } catch (err) {
    showStatus('mgmtFileStatus', 'Error: ' + err.message, 'err');
    await safeClosePort(port);
  } finally {
    btn.disabled = false; btn.classList.remove('loading');
    operationInProgress = false;
    resumeMonitor();
  }
}

function displayFileList(files) {
  var container = $('mgmtFileList');
  container.classList.remove('hidden');
  container.textContent = '';

  var table = document.createElement('div');
  table.className = 'mgmt-file-table';

  var presentNames = files.map(function(f) { return f.name; });
  var missing = KNOWN_FIRMWARE.filter(function(kf) { return presentNames.indexOf(kf) === -1; });

  for (var i = 0; i < files.length; i++) {
    var f = files[i];
    var row = document.createElement('div');
    row.className = 'mgmt-file-row';

    var icon = document.createElement('span');
    icon.className = 'mgmt-file-icon';
    var isFw = KNOWN_FIRMWARE.indexOf(f.name) !== -1;
    var isCfg = f.name === 'config.json';
    icon.textContent = isFw ? '\u2713' : (isCfg ? '\u2699' : '\u25CB');
    icon.style.color = isFw ? 'var(--success)' : (isCfg ? 'var(--warning)' : 'var(--accent-mp)');

    var name = document.createElement('span');
    name.className = 'mgmt-file-name';
    name.textContent = f.name;

    var badge = document.createElement('span');
    badge.className = 'mgmt-badge ' + (isFw ? 'fw' : (isCfg ? 'config' : 'custom'));
    badge.textContent = isFw ? 'firmware' : (isCfg ? 'config' : 'custom');

    var size = document.createElement('span');
    size.className = 'mgmt-file-size';
    size.textContent = f.size < 1024 ? f.size + ' B' : (f.size / 1024).toFixed(1) + ' KB';

    var del = document.createElement('button');
    del.type = 'button';
    del.className = 'mgmt-file-del';
    del.title = 'Eliminar ' + f.name;
    del.setAttribute('aria-label', 'Eliminar ' + f.name);
    del.setAttribute('data-file', f.name);
    del.onclick = function() { deleteDeviceFile(this.getAttribute('data-file')); };
    del.textContent = '\u2715';

    row.appendChild(icon);
    row.appendChild(name);
    row.appendChild(badge);
    row.appendChild(size);
    row.appendChild(del);
    table.appendChild(row);
  }

  container.appendChild(table);

  // Show missing firmware files warning
  if (missing.length > 0) {
    var warn = document.createElement('div');
    warn.className = 'mgmt-missing-list';
    warn.textContent = 'Faltan ' + missing.length + ' archivo(s) del firmware: ' + missing.join(', ');
    container.appendChild(warn);
  }

  // Show dropzone
  $('mgmtDropzone').classList.remove('hidden');
}

async function deleteDeviceFile(filename) {
  if (operationInProgress) { showStatus('mgmtFileStatus', 'Otra operacion en curso.', 'warn'); return; }
  try { filename = sanitizeFilename(filename); } catch (e) {
    showStatus('mgmtFileStatus', e.message, 'err'); return;
  }
  if (!confirm('Eliminar /' + filename + ' del ESP32?')) return;

  operationInProgress = true;
  hideStatus('mgmtFileStatus');
  var port = null;
  try {
    showStatus('mgmtFileStatus', 'Eliminando ' + filename + '...', 'ok');
    port = await connectAndEnterRepl();
    await execRawRepl(port, "import os;os.remove('/" + filename + "')");

    // Refresh file list
    var lsCode = FS_LIST_CMD;
    var lsResult = await execAndCapture(port, lsCode, 'FS_END', TIMEOUTS.FILE_OP);
    await exitReplAndClose(port);
    port = null;

    var files = parseFileListing(lsResult);
    displayFileList(files);
    showStatus('mgmtFileStatus', filename + ' eliminado.', 'ok');
  } catch (err) {
    showStatus('mgmtFileStatus', 'Error al eliminar: ' + err.message, 'err');
    await safeClosePort(port);
  } finally {
    operationInProgress = false;
    resumeMonitor();
  }
}

async function uploadMgmtFiles(fileList) {
  if (operationInProgress) { showStatus('mgmtFileStatus', 'Otra operacion en curso.', 'warn'); return; }

  // Validar extensiones y sanitizar nombres
  var validFiles = [];
  for (var i = 0; i < fileList.length; i++) {
    var safeName;
    try { safeName = sanitizeFilename(fileList[i].name); } catch (e) {
      showStatus('mgmtFileStatus', e.message, 'err');
      return;
    }
    if (safeName.endsWith('.py') || safeName.endsWith('.json')) {
      validFiles.push({ file: fileList[i], safeName: safeName });
    } else {
      showStatus('mgmtFileStatus', 'Archivo ignorado (solo .py y .json): ' + safeName, 'warn');
    }
  }
  if (validFiles.length === 0) return;

  operationInProgress = true;
  hideStatus('mgmtFileStatus');
  var port = null;
  try {
    showStatus('mgmtFileStatus', 'Conectando al ESP32...', 'ok');
    port = await connectAndEnterRepl();
    var results = [];

    for (var fi = 0; fi < validFiles.length; fi++) {
      var entry = validFiles[fi];
      var safeName = entry.safeName;
      showStatus('mgmtFileStatus', 'Subiendo ' + safeName + ' (' + (fi + 1) + '/' + validFiles.length + ')...', 'ok');

      var content = await entry.file.text();
      var tmpName = '/' + safeName + '.tmp';
      var finalName = '/' + safeName;

      try {
        // Escritura atomica: escribir en .tmp primero, luego renombrar
        await execRawRepl(port, "f=open('" + tmpName + "','w')");
        for (var ci = 0; ci < content.length; ci += CHUNK_SIZE) {
          var chunk = escapeForPythonString(content.slice(ci, ci + CHUNK_SIZE));
          await execRawRepl(port, "f.write('" + chunk + "')");
        }
        await execRawRepl(port, "f.close()");
        // Atomic rename: original untouched until this succeeds
        await execRawRepl(port, "import os;os.rename('" + tmpName + "','" + finalName + "')");
        results.push(safeName + ': OK');
      } catch (err) {
        try { await execRawRepl(port, "f.close()"); } catch (_) {}
        // Clean up .tmp if it exists
        try { await execRawRepl(port, "import os;os.remove('" + tmpName + "')"); } catch (_) {}
        results.push(safeName + ': ERROR - ' + err.message);
      }
    }

    // Releer lista de archivos para verificacion
    showStatus('mgmtFileStatus', 'Verificando archivos...', 'ok');
    var lsCode = FS_LIST_CMD;
    var lsResult = await execAndCapture(port, lsCode, 'FS_END', TIMEOUTS.FILE_OP);

    // Soft reboot del ESP32 despues de modificar archivos
    showStatus('mgmtFileStatus', 'Reiniciando ESP32...', 'ok');
    await serialWrite(port, String.fromCharCode(2)); // Ctrl-B exit raw REPL
    await sleep(200);
    await serialWrite(port, String.fromCharCode(4)); // Ctrl-D soft reboot
    await sleep(1000);
    await safeClosePort(port);
    port = null;

    // Parse and refresh display
    var files = parseFileListing(lsResult);
    displayFileList(files);

    var errCount = results.filter(function(r) { return r.indexOf('ERROR') !== -1; }).length;
    if (errCount > 0) {
      showStatus('mgmtFileStatus', errCount + ' error(es). ' + results.join('; '), 'err');
    } else {
      showStatus('mgmtFileStatus', validFiles.length + ' archivo(s) subido(s) correctamente.', 'ok');
    }
  } catch (err) {
    showStatus('mgmtFileStatus', 'Error: ' + err.message, 'err');
    await safeClosePort(port);
  } finally {
    operationInProgress = false;
    resumeMonitor();
  }
}

// ─── WIFI SCANNER ─────────────────────────────────────────────
async function scanWifi(targetInputId) {
  if (operationInProgress) return;
  operationInProgress = true;
  await suspendMonitor();
  var scanPort = null;
  var ownPort = false;
  try {
    // Use existing serialPort or request new one
    if (serialPort && serialPort.readable) {
      scanPort = serialPort;
    } else {
      scanPort = await navigator.serial.requestPort({ filters: USB_FILTERS });
      await scanPort.open({ baudRate: BAUD_RATE });
      ownPort = true;
      await sleep(200);
    }

    // Salir de raw REPL si estamos dentro, luego entrar de nuevo
    await serialWrite(scanPort, String.fromCharCode(2));
    await sleep(200);
    await serialWrite(scanPort, String.fromCharCode(3));
    await sleep(SERIAL_DELAY_MS);
    await serialWrite(scanPort, String.fromCharCode(3));
    await sleep(SERIAL_DELAY_MS);
    await serialWrite(scanPort, String.fromCharCode(1));
    var replResp = await serialReadUntil(scanPort, 'raw REPL', TIMEOUTS.REPL_ENTRY);
    if (replResp.indexOf('raw REPL') === -1) {
      throw new Error('No se pudo entrar al Raw REPL. El ESP32 puede estar ejecutando codigo.');
    }

    // Scan WiFi networks (bypass execRawRepl: need to wait for SCAN_END, not OK)
    var scanCode = "import network; s=network.WLAN(network.STA_IF); s.active(True); nets=s.scan(); print('SCAN_START'); [print(str(n[0],'utf-8')+'|'+str(n[3])+'|'+str(n[4])) for n in sorted(nets,key=lambda x:-x[3])]; print('SCAN_END')";
    await serialWrite(scanPort, scanCode + '\r\n');
    await serialWrite(scanPort, String.fromCharCode(4)); // Ctrl-D execute
    // Wait for SCAN_END (scan takes 3-5s on ESP32)
    var result = await serialReadUntil(scanPort, 'SCAN_END', TIMEOUTS.WIFI_SCAN);

    // Salir de raw REPL
    await serialWrite(scanPort, String.fromCharCode(2));

    if (ownPort) {
      await safeClosePort(scanPort);
    }

    // Parse results
    var lines = result.split('\n');
    var networks = [];
    var capturing = false;
    for (var si = 0; si < lines.length; si++) {
      var ln = lines[si].replace(/\r/g, '').trim();
      if (ln.indexOf('SCAN_START') !== -1) { capturing = true; continue; }
      if (ln.indexOf('SCAN_END') !== -1) break;
      if (capturing && ln.indexOf('|') !== -1) {
        var parts = ln.split('|');
        var ssid = parts[0].trim();
        var rssi = parseInt(parts[1]) || -99;
        var authMode = parseInt(parts[2]) || 0;
        if (ssid.length > 0) {
          networks.push({ ssid: ssid, rssi: rssi, open: authMode === 0 });
        }
      }
    }

    if (networks.length === 0) {
      alert('No se encontraron redes WiFi. Verifica que el ESP32 tenga la antena disponible.');
      return;
    }

    // Populate select dropdown
    var selectId = targetInputId === 'cfgWifiSsid' ? 'cfgWifiSelect' : 'mWifiSelect';
    var select = $(selectId);
    select.textContent = '';
    var defOpt = document.createElement('option');
    defOpt.value = '';
    defOpt.textContent = networks.length + ' redes encontradas:';
    select.appendChild(defOpt);
    for (var ni = 0; ni < networks.length; ni++) {
      var opt = document.createElement('option');
      opt.value = networks[ni].ssid;
      var bars = networks[ni].rssi > -50 ? '\u2593\u2593\u2593\u2593' : networks[ni].rssi > -70 ? '\u2593\u2593\u2593\u2591' : networks[ni].rssi > -80 ? '\u2593\u2593\u2591\u2591' : '\u2593\u2591\u2591\u2591';
      opt.textContent = networks[ni].ssid + '  ' + bars + '  (' + networks[ni].rssi + ' dBm)' + (networks[ni].open ? ' [OPEN]' : '');
      select.appendChild(opt);
    }
    select.classList.remove('hidden');

  } catch (err) {
    alert('Error al escanear WiFi: ' + err.message);
    if (ownPort && scanPort) {
      await safeClosePort(scanPort);
    }
  } finally {
    operationInProgress = false;
    resumeMonitor();
  }
}

// ─── MODAL DOCUMENTACION ─────────────────────────────────────
function openDocsModal() {
  var overlay = $('docsOverlay');
  docsPreviousFocus = document.activeElement;
  overlay.classList.add('open');
  document.body.style.overflow = 'hidden';
  var closeBtn = $('docsCloseBtn');
  if (closeBtn) closeBtn.focus();

  if (!docsInitialized && window.mermaidLib) {
    window.mermaidLib.run({ nodes: Array.from(overlay.querySelectorAll('.mermaid')) });
    docsInitialized = true;
  }
}

function closeDocsModal() {
  $('docsOverlay').classList.remove('open');
  document.body.style.overflow = '';
  if (docsPreviousFocus) { docsPreviousFocus.focus(); docsPreviousFocus = null; }
}

// ─── INICIALIZACION ───────────────────────────────────────────
function setupDropzone() {
  // Config dropzone (Card 4)
  var dz = $('configDropzone');
  var fi = $('configFileInput');
  if (dz && fi) {
    dz.addEventListener('click', function() { fi.click(); });
    dz.addEventListener('keydown', function(e) { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); fi.click(); } });
    dz.addEventListener('dragover', function(e) { e.preventDefault(); dz.classList.add('drag-over'); });
    dz.addEventListener('dragleave', function() { dz.classList.remove('drag-over'); });
    dz.addEventListener('drop', function(e) {
      e.preventDefault();
      dz.classList.remove('drag-over');
      var file = e.dataTransfer.files[0];
      if (file) loadConfigFile(file);
    });
    fi.addEventListener('change', function() {
      if (fi.files[0]) loadConfigFile(fi.files[0]);
    });
  }

  // Management file upload dropzone (Card 6)
  var mdz = $('mgmtDropzone');
  var mfi = $('mgmtFileInput');
  if (mdz && mfi) {
    mdz.addEventListener('click', function() { mfi.click(); });
    mdz.addEventListener('keydown', function(e) { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); mfi.click(); } });
    mdz.addEventListener('dragover', function(e) { e.preventDefault(); mdz.classList.add('drag-over'); });
    mdz.addEventListener('dragleave', function() { mdz.classList.remove('drag-over'); });
    mdz.addEventListener('drop', function(e) {
      e.preventDefault();
      mdz.classList.remove('drag-over');
      if (e.dataTransfer.files.length > 0) uploadMgmtFiles(e.dataTransfer.files);
    });
    mfi.addEventListener('change', function() {
      if (mfi.files.length > 0) uploadMgmtFiles(mfi.files);
      mfi.value = '';
    });
  }
}

function initEventListeners() {
  // Card 1: Diagnostico
  $('btnDiag').addEventListener('click', runDiagnostics);

  // Card 2: esp-web-tools completion listener
  var espBtn = document.querySelector('esp-web-install-button');
  if (espBtn) {
    espBtn.addEventListener('state-changed', function(ev) {
      var state = ev.detail && ev.detail.state;
      if (state === 'finished') {
        showStatus('flashStatus', 'MicroPython instalado correctamente.', 'ok');
        // Flash complete
      } else if (state === 'error') {
        showStatus('flashStatus', 'Error durante la instalacion del firmware.', 'err');
      }
    });
  }

  // Card 3: Upload files
  $('btnUpload').addEventListener('click', uploadFiles);

  // Docs button
  var docsBtn = document.querySelector('[data-action="open-docs"]');
  if (docsBtn) docsBtn.addEventListener('click', openDocsModal);

  // Card 4: Config WiFi scan buttons
  var wifiScanBtns = document.querySelectorAll('[data-scan-target]');
  for (var i = 0; i < wifiScanBtns.length; i++) {
    (function(btn) {
      btn.addEventListener('click', function() {
        scanWifi(btn.getAttribute('data-scan-target'));
      });
    })(wifiScanBtns[i]);
  }

  // Card 4: WiFi select dropdowns
  $('cfgWifiSelect').addEventListener('change', function() {
    var target = this.getAttribute('data-target-input');
    if (this.value && target) $(target).value = this.value;
  });
  $('mWifiSelect').addEventListener('change', function() {
    var target = this.getAttribute('data-target-input');
    if (this.value && target) $(target).value = this.value;
  });

  // Card 4: Upload config
  $('btnUploadConfig').addEventListener('click', uploadConfigFromFile);

  // Card 4: Manual toggle
  $('manualToggle').addEventListener('click', toggleManualForm);

  // Card 4: Manual upload
  $('btnManualUpload').addEventListener('click', uploadManualConfig);

  // Card 5: Monitor
  $('btnMonStart').addEventListener('click', function() { startMonitor(); });
  $('btnMonStop').addEventListener('click', stopMonitor);
  $('btnClearMon').addEventListener('click', clearMonitor);
  $('btnReboot').addEventListener('click', rebootDevice);
  $('btnExportLog').addEventListener('click', exportLog);
  $('btnCopyLog').addEventListener('click', copyLog);
  $('monTimestamps').addEventListener('change', toggleTimestamps);
  $('monFilterInput').addEventListener('input', applyFilter);

  // Card 5B: Report
  $('btnDownloadReport').addEventListener('click', downloadReport);
  $('btnQR').addEventListener('click', generateQR);
  $('btnRedisCmd').addEventListener('click', copyRedisCmd);

  // Card 6: Management tabs
  var mgmtTabs = document.querySelectorAll('.mgmt-tab[data-tab]');
  for (var ti = 0; ti < mgmtTabs.length; ti++) {
    (function(tab) {
      tab.addEventListener('click', function() {
        switchMgmtTab(tab.getAttribute('data-tab'));
      });
    })(mgmtTabs[ti]);
  }

  // Card 6: Config tab
  $('btnReadConfig').addEventListener('click', readDeviceConfig);
  $('btnSaveConfig').addEventListener('click', saveDeviceConfig);

  // Card 6: Files tab
  $('btnReadFiles').addEventListener('click', readDeviceFiles);

  // Docs overlay: close on background click
  var docsOverlay = $('docsOverlay');
  if (docsOverlay) {
    docsOverlay.addEventListener('click', function(event) {
      if (event.target === this) closeDocsModal();
    });
  }

  // Docs close button
  $('docsCloseBtn').addEventListener('click', closeDocsModal);

  // Escape key closes docs
  document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') closeDocsModal();
  });

  // Dropzone setup
  setupDropzone();
}

document.addEventListener('DOMContentLoaded', function() {
  if (!('serial' in navigator)) {
    var c = document.querySelector('.container');
    c.textContent = '';
    var card = document.createElement('div');
    card.className = 'card';
    card.style.cssText = 'text-align:center;padding:3rem';
    var h = document.createElement('h2');
    h.style.color = 'var(--error)';
    h.textContent = 'Navegador no compatible';
    var p = document.createElement('p');
    p.style.cssText = 'color:var(--text-secondary);margin-top:1rem';
    p.textContent = 'Esta herramienta requiere la Web Serial API. Usa Google Chrome o Microsoft Edge en escritorio.';
    card.appendChild(h);
    card.appendChild(p);
    c.appendChild(card);
    return;
  }
  initEventListeners();
});
