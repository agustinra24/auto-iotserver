"""
IoT device orchestrator.

Initializes all hardware components (sensors, actuators, Wi-Fi) and
provides the main telemetry loop that reads sensors, evaluates local
actuator logic, and sends data to the FastAPI server.

Original authors: Raziel Campos, Jose Zapata, Alejandro Salinas.
Updated: Agustin Ahumada (puzzle auth, JWT, NTP, reconnection).
"""

import time

try:
    import ntptime
except ImportError:
    ntptime = None

from WifiControl import Wifi
from temperature_sensor import TemperatureSensor
from microphone_sensor import MicrophoneSensor
from led_semaphore import SemaphoreLed
from IR_send import InfraredModule
from actuator_logic import ActuatorLogic
from http_client import HttpClient
from puzzle_auth import PuzzleAuth
import config_manager


def _iso_timestamp() -> str:
    """Format current UTC time as ISO 8601 string from time.localtime()."""
    t = time.localtime()
    return "{:04d}-{:02d}-{:02d}T{:02d}:{:02d}:{:02d}Z".format(
        t[0], t[1], t[2], t[3], t[4], t[5])


class DeviceIoT:
    """Manages hardware, authentication, and the telemetry loop."""

    def __init__(self, config: dict):
        """
        Parameters:
            config: Validated config dict from config_manager.load().
        """
        self.config = config
        self.wifi = None
        self.http = None
        self.auth = None
        self.temp_sensor = None
        self.mic_sensor = None
        self.semaphore = None
        self.ir_sender = None
        self.actuators = None
        self.token = None

    def initialize(self) -> bool:
        """
        Initialize all subsystems: Wi-Fi, NTP, sensors, actuators, HTTP, auth.

        Returns:
            True if all critical subsystems initialized, False otherwise.
        """
        print("[device] Initializing...")

        # Wi-Fi
        self.wifi = Wifi(self.config["wifi_ssid"], self.config["wifi_pass"])
        if not self.wifi.connect_with_retry():
            print("[device] FATAL: Cannot connect to Wi-Fi")
            return False

        # NTP time sync
        self._sync_ntp()

        # Sensors (unchanged from original firmware)
        self.temp_sensor = TemperatureSensor(input_pin=config_manager.PIN_SENSOR_TEMP)
        self.mic_sensor = MicrophoneSensor(input_pin=config_manager.PIN_SENSOR_MIC)

        # Actuators
        self.semaphore = SemaphoreLed(
            config_manager.PIN_LED_RED,
            config_manager.PIN_LED_YELLOW,
            config_manager.PIN_LED_GREEN
        )
        self.ir_sender = InfraredModule(input_pin=config_manager.PIN_IR_EMITTER)
        self.actuators = ActuatorLogic(
            self.config["thresholds"], self.semaphore, self.ir_sender
        )

        # HTTP client and puzzle authentication
        self.http = HttpClient(self.config["server_url"], self.config["server_port"])
        self.auth = PuzzleAuth(self.config, self.http)

        # Authenticate
        self.token = self.auth.authenticate()
        if not self.token:
            print("[device] WARNING: Authentication failed. Running in degraded mode.")

        print("[device] Initialization complete. device_id={}".format(
            self.config["device_id"]))
        return True

    def _sync_ntp(self):
        """Synchronize system clock via NTP. Non-fatal on failure."""
        if ntptime is None:
            print("[device] ntptime module not available, skipping NTP sync")
            return
        for attempt in range(3):
            try:
                ntptime.settime()
                print("[device] NTP synced: {}".format(_iso_timestamp()))
                return
            except OSError as e:
                print("[device] NTP attempt {}/3 failed: {}".format(attempt + 1, e))
                time.sleep(2)
        print("[device] NTP sync failed after 3 attempts. Timestamps may be inaccurate.")

    def _read_sensors(self) -> tuple:
        """
        Read all sensors with averaging.

        Returns:
            Tuple of (temperature: float, humidity: float, noise_voltage: float).
            Falls back to simulated data if physical sensors are not connected.
        """
        try:
            # Temperature sensor: 3 samples, each with 0.9s internal delay
            temperatures = []
            humidities = []
            for _ in range(3):
                temperatures.append(self.temp_sensor.read_temperature())
                humidities.append(self.temp_sensor.read_humidity())

            temp_avg = sum(temperatures) / len(temperatures)
            hum_avg = sum(humidities) / len(humidities)

            # Microphone: 5 samples, 10ms between samples
            noise_avg = self.mic_sensor.sample_average(5, 10)

            return (temp_avg, hum_avg, noise_avg)

        except OSError as e:
            # Sensors not connected: generate simulated readings for demo/testing
            import os
            rand_byte = os.urandom(1)[0]
            temp_sim = 20.0 + (rand_byte % 15)          # 20-34 C
            hum_sim = 40.0 + ((rand_byte >> 2) % 40)    # 40-79 %
            noise_sim = 1.0 + (rand_byte % 20) / 10.0   # 1.0-2.9 V
            print("[device] Sensors not connected, using simulated data: "
                  "temp={:.1f} hum={:.0f} noise={:.1f}".format(temp_sim, hum_sim, noise_sim))
            return (temp_sim, hum_sim, noise_sim)

    def _send_reading(self, temperature: float, humidity: float) -> bool:
        """
        Send sensor data to the API. Re-authenticates on 401.

        Parameters:
            temperature: Average temperature in Celsius.
            humidity:    Average humidity percentage.

        Returns:
            True if data was accepted (201), False otherwise.
        """
        if not self.token:
            return False

        payload = {
            "device_id": self.config["device_id"],
            "temperature": round(temperature, 2),
            "humidity": int(humidity),
            "location": self.config["location"],
            "timestamp": _iso_timestamp()
        }

        status, body = self.http.post_json("/api/v1/device/reading", payload, self.token)

        if status == 201:
            count = body.get("readings_count", "?") if body else "?"
            print("[device] OK: {} readings stored".format(count))
            return True

        if status == 401:
            print("[device] Token expired. Re-authenticating...")
            self.token = self.auth.authenticate()
            if self.token:
                # Retry once with fresh token
                status, body = self.http.post_json(
                    "/api/v1/device/reading", payload, self.token)
                if status == 201:
                    print("[device] OK after re-auth")
                    return True

        print("[device] Send failed: HTTP {}".format(status))
        return False

    def run(self):
        """
        Main telemetry loop. Reads sensors, evaluates actuators, sends data.

        Runs indefinitely. Handles Wi-Fi drops, sensor errors, and auth expiry.
        Sleeps for config["read_interval_s"] between cycles.
        """
        interval = self.config["read_interval_s"]
        print("[device] Starting telemetry loop (interval={}s)".format(interval))

        while True:
            start = time.time()

            # Check Wi-Fi health
            if not self.wifi.is_connected():
                print("[device] Wi-Fi lost. Reconnecting...")
                if self.wifi.reconnect():
                    self._sync_ntp()
                else:
                    print("[device] Wi-Fi reconnect failed. Skipping this cycle.")
                    time.sleep(interval)
                    continue

            # Read sensors
            temp, hum, noise = self._read_sensors()

            if temp is not None and hum is not None:
                # Evaluate local actuator logic (uses noise for LEDs, temp+hum for IR)
                if noise is not None:
                    self.actuators.evaluate(temp, hum, noise)

                # Send temperature and humidity to the server
                # (noise is not sent; the API has no compatible field)
                self._send_reading(temp, hum)
            else:
                print("[device] Sensor failure, skipping send")

            # Sleep for the remaining interval time
            elapsed = time.time() - start
            sleep_time = max(1, interval - int(elapsed))
            time.sleep(sleep_time)
