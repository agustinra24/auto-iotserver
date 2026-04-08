"""
Main entry point for the IoT device firmware.

Boot sequence:
    1. Load configuration from /config.json (or enter UART provisioning)
    2. Initialize Wi-Fi, NTP, sensors, actuators, and puzzle authentication
    3. Enter telemetry loop: read sensors -> evaluate actuators -> send data

Authors:
    -- Raziel Campos (original)
    -- Jose Zapata (original)
    -- Alejandro Salinas (original crypto, sensors)
    -- Agustin Ahumada (puzzle auth, JWT, API adaptation)
"""

import config_manager
from Device import DeviceIoT


def main():
    # Step 1: Load and validate configuration
    config = config_manager.load()

    # Step 2: Initialize the device (Wi-Fi, NTP, sensors, auth)
    device = DeviceIoT(config)
    if not device.initialize():
        print("[main] Initialization failed. Halting.")
        return

    # Step 3: Enter the telemetry loop (runs indefinitely)
    device.run()


if __name__ == "__main__":
    print("=" * 50)
    print("  IoT Device Firmware v2.0")
    print("  Puzzle Auth + FastAPI compatible")
    print("=" * 50)
    main()
