"""
This class represents an IoT device that connects to Wi-Fi,
reads data from sensors, and controls an LED semaphore.
The configuration is imported from a Python file named `Config.py`.
"""

import WifiControl
import Config  # Import the configuration module with device settings
from temperature_sensor import TemperatureSensor
from microphone_sensor import MicrophoneSensor
from led_semaphore import SemaphoreLed
from IR_send import InfraredModule

class DeviceIoT:
    def __init__(self):
        """
        Basic initialization without hardware configuration.
        """
        # Initialize attributes without setting specific values yet
        self.nombre = None
        self.id = None
        self.wifi = None
        self.microphone = None
        self.temperature = None
        self.semaphore = None
        self.ir_sender = None
        self.is_configured = False  # Track if the device has been configured


    def configure(self):
        """
        Configure the device using static values from the Config module.
        """
        print("[-] Configuring the IoT Device...")

        # Load configuration values from the Config.py file
        self.nombre = Config.Nombre
        self.id = Config.ID

        # Initialize Wi-Fi components with values from Config.py
        self.wifi = WifiControl.Wifi(
            wifi_ssid=Config.WifiSSID,
            wifi_password=Config.WifiPassword
        )
        self.wifi.connect_wifi()

        # Initialize sensors and LED semaphore
        self.microphone = MicrophoneSensor(input_pin=Config.Pin_Sensor_Mic)
        self.temperature = TemperatureSensor(input_pin=Config.Pin_Sensor_Temp)
        self.semaphore = SemaphoreLed(
            Config.Pin_Led_Red,
            Config.Pin_Led_Yellow,
            Config.Pin_Led_Green
        )

        self.ir_sender = InfraredModule(input_pin=Config.Pin_IR_emitter)
        self.is_configured = True  # Mark the device as configured
        print("[+] Configuration Complete!")

    def initialize(self):
        """
        Start the IoT device after ensuring it is configured.
        """
        self.configure()
        if not self.is_configured:
            raise Exception("Device has not been configured yet.")

        print("[*] Starting IoT Device...")
        print("Device Name:", self.nombre)
        print("Device ID:", self.id)
        print("[+] Device is Ready!")

    def get_temperature_average_level(self, sample_number: int = 5):
        """
        Calculate the average temperature from a set of readings.

        Parameters:
        sample_number (int): Number of samples to average.

        Returns:
        float: Average temperature in Celsius.
        """
        temperatures = [self.temperature.read_temperature() for _ in range(sample_number)]
        temperature_average = sum(temperatures) / sample_number
        print(f"Average Temperature: {temperature_average:.4f}°C")
        return temperature_average

    def get_humidity_average_level(self, sample_number: int = 5):
        """
        Calculate the average humidity from a set of readings.

        Parameters:
        sample_number (int): Number of samples to average.

        Returns:
        float: Average humidity percentage.
        """
        humidity_readings = [self.temperature.read_humidity() for _ in range(sample_number)]
        humidity_average = sum(humidity_readings) / sample_number
        print(f"Average Humidity: {humidity_average:.4f}%")
        return humidity_average

    def get_noise_level_average(self, samples:int = 5, delay_delta:int = 10):
        noise_level = self.microphone.sample_average(samples, delay_delta)
        print(f"Average Noise Level: {noise_level:.3f}%")
        return noise_level

    def send_ir_signal(self):
        self.ir_sender.send_raw_data(Config.IR_raw_data)
        print("The IR signal has been sent")

    def get_measurements(self, samples: int = 3):
        # get measurements and send data
        print("Getting measurements...")
        noise = self.get_noise_level_average()
        humidity = self.get_humidity_average_level(sample_number=samples)
        temperature = self.get_temperature_average_level(sample_number=samples)
        return noise, humidity, temperature


