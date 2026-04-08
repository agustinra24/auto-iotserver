"""
This class is used to connect the ESP32 to a Wi-Fi network.
It uses the MicroPython `network` module to establish a connection in STA mode (Station Mode).
"""

import network  # Import the network module for Wi-Fi functionality
import time  # Import the time module for delays
import Config  # Import a custom configuration file where SSID and password are stored

class Wifi:
    """
    A class to manage Wi-Fi connectivity on an ESP32 device.
    """

    def __init__(self, wifi_ssid, wifi_password):
        """
        Initialize the Wi-Fi class with credentials from the Config module.
        """
        self.ssid = wifi_ssid  # Retrieve Wi-Fi SSID (network name) from Config
        self.password = wifi_password  # Retrieve Wi-Fi password from Config
        self.status = False  # Track connection status (False = Not Connected)

    def connect_wifi(self):
        """
        Connect to the specified Wi-Fi network and handle possible errors.
        """
        print('Connecting to Wi-Fi ... ... ...')  # Notify user that connection is in progress

        try:
            # Create a Wi-Fi station interface (STA mode: Connect to an existing network)
            wlan = network.WLAN(network.STA_IF)  # Create a WLAN object in STA mode
            wlan.active(True)  # Activate the Wi-Fi interface

            # Check if the device is already connected
            if wlan.isconnected():
                print("The device is already connected:", wlan.ifconfig())  # Print current IP configuration
                self.status = True  # Update connection status
                return  # Exit the function since we are already connected

            # Attempt to connect using stored credentials
            wlan.connect(self.ssid, self.password)

            # Define a timeout limit to prevent infinite waiting
            timeout = 10  # Maximum time (in seconds) to wait for connection
            start_time = time.time()  # Record the current time

            # Wait for the connection to establish or until timeout occurs
            while not wlan.isconnected():
                if time.time() - start_time > timeout:  # Check if timeout is exceeded
                    print("Error: Timeout, the device was not able to connect.")  # Notify failure
                    return  # Exit function if connection fails
                time.sleep(1)  # Small delay to prevent excessive CPU usage

            # Successfully connected
            print("Connected to:", wlan.ifconfig())  # Print assigned IP configuration
            self.status = True  # Update connection status to True

        except Exception as e:
            print("Error to establish connection to Wi-Fi:", e)  # Print any exception that occurs
