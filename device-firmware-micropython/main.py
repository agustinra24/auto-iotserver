"""
This is the main script to run the IoT project.


Authors:
    -- Raziel Campos
    -- Jose Zapata
    -- Alejandro Salinas
"""

from Device import DeviceIoT
# TODO: Move the http class to device, enhance the control phases ...
from http_communication import HttpCommunication
import Config
import json
import hashlib
import time
from Authentication3 import Authentication3
from Processing_data import ProcessingData

def main():
    # The object initialization is once per run
    device = DeviceIoT()
    device.initialize()
    #Getting AES Key
    key = hashlib.sha256(Config.AES_Password.encode()).digest()[:16]  # AES-128 key

    ## Authentication Logging
    auth = Authentication3(username=Config.User_Name, password=Config.Password,
                           login_url=Config.End_Point + "devices/auth")
    token = auth.get_session_token()
    print(f" ******** the current token is: {token} **********")

    ### _____ Classes to initialize _______
    # the http communication object
    http_object = HttpCommunication(data_send_endpoint=Config.End_Point + "devices/add_data", token=token)
    ### Processing data class
    actions_actuators = ProcessingData(esp32=device)

    while True:
        start_time = time.time() # measurement the delta time

        # get measurements and send data
        noise, humidity, temperature = device.get_measurements(samples=3)
        data_packet = http_object.data_structure(id_device="ESP32", timestamp="12:12:12", msm1=temperature, msm2=humidity,
                                                 msm3=noise)
        print("The data Packet is:", data_packet)
        data_packet = data_packet.encode() # bytes
        data_response = http_object.send_data_encrypted(data_packet, key)

        print("data_response:", data_response)
        plain_data = http_object.received_data_encrypted(data_response, key)
        print("data_response decrypted:", plain_data)

        actions_actuators.semaphore_action(plain_data)
        actions_actuators.fan_action(plain_data)

        t = time.time() - start_time
        print(f"It takes to gather, send and receive a response in: {str(t)} [s]" )


if __name__ == '__main__':
    print("*********** This is the main process ***********")
    main()
