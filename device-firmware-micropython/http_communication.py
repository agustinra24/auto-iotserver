import json
import urequests
from AES_Cipher import AESCipher

def wrap_measurement(measurement, type_data, unit):
    """
    This function wrap the structure of the measurement values, in other words, it creates a list
    wrapping the measurement with the next parameters:
    type_data: Type of data being recorded (e.g., Temperature, Humidity).
    unit: Measurement unit of the recorded value.
    value: The numerical value recorded.
    :param measurement:
    :param unit:
    :param type_data:
    :return returned_value:
    """
    returned_value = {
        "type_data": type_data,
        "unit": unit,
        "value": measurement
    }
    return returned_value

class HttpCommunication:
    def __init__(self, data_send_endpoint, token):
        """
        Initializes the HTTP communication class with an endpoint URL.
        :param data_send_endpoint: The URL endpoint where data will be sent.
        """
        self.data_send_endpoint = data_send_endpoint
        self.__token = token

    def send_data_encrypted(self, data:bytes, key:bytes):
        print("sending encrypted data and IV ... ... ... ")
        cipher = AESCipher(key)
        cipher_text = cipher.data_encryption(data)
        received_data = self.send_data(cipher_text)
        return received_data

    @staticmethod
    def received_data_encrypted( data:bytes, key:bytes):
        print("Data Received from server: ", data)
        cipher = AESCipher(key)
        decipher_text = cipher.data_decryption(data)
        decipher_text = decipher_text.decode()
        print("decipher_message from server: ", decipher_text)
        decipher_text = json.loads(decipher_text)
        return decipher_text

    def send_data(self, data_pack, endpoint=None):
        """
        Sends JSON data to a specified endpoint via an HTTP POST request.
        :param data_pack: The JSON data packet to be sent.
        :param endpoint: Optional, overrides the default endpoint if provided.
        """
        if endpoint is None:
            endpoint = self.data_send_endpoint

        #headers = {"Content-Type": "application/json", "Accept": "application/json"}  # Ensure JSON response
        headers = {"Content-Type": "application/octet-stream",
                   "Cookie": self.__token}
        try:
            # Send the POST request with JSON payload
            send_post = urequests.post(url=endpoint, data=data_pack, headers=headers)
            # Log the response for debugging
            print(f"Response Code from server: {send_post.status_code}") # response from server
            print(f"Response Data from server: {send_post.text}") # response from server

            received_data = send_post.text
            send_post.close()  # Close the connection to free resources
            print("Data successfully sent via HTTP")
            return received_data

        except Exception as e:
            print(f"Error sending data by client: {e}")

    @staticmethod
    def data_structure(id_device: str, timestamp: str, msm1: float, msm2: float, msm3: float):
        """
        Constructs a JSON data packet with the required structure.
        :param id_device: Identifier for the device sending the data.
        :param timestamp: Time at which the data was recorded.
        :param msm3:
        :param msm2:
        :param msm1:
        :return: JSON string of the structured data.
        """
        data_packet = {
            "id_device": id_device,
            "timestamp": timestamp,
            "measurement1": wrap_measurement(msm1, "Celsius", "float"), # temperature
            "measurement2": wrap_measurement(msm2, "Percentage", "float"), # humidity
            "measurement3": wrap_measurement(msm3, "Voltage", "float"), # noise

        }

        return json.dumps(data_packet)  # Return JSON string to ensure proper transmission

