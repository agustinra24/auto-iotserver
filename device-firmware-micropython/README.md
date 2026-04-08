## 📦 Firmware Structure

The firmware developed in this project follows a **modular structure**, designed to facilitate maintainability, scalability, and code reuse. Each module fulfills a specific role within the IoT system, allowing a clear separation of responsibilities. Below are the main functional layers of the system:

- **Communication Module:**  
  Manages the Wi-Fi connection and secure data transmission to the IoT server using protocols such as HTTP. Files such as `WifiControl.py` and `http_communication.py` are part of this layer.

- **Authentication Module:**  
  Responsible for generating the device's authentication requests using locally stored parameters, including the use of secret keys. This logic is mainly implemented in `Authentication3.py`.

- **Sensor Reading Modules:**  
  Include the logic to acquire environmental data such as temperature, noise, and humidity from sensors connected to the device. Examples include `temperature_sensor.py` and `microphone_sensor.py`.

- **Data Processing Module:**  
  Processes and classifies the response received from the IoT server to determine the environmental state (e.g., high temperature, low noise), and based on that, trigger actions on the device's actuators. Implemented in `Processing_data.py`.

- **Actuator Module:**  
  Defines the actions to be executed according to the data analysis, such as turning on LEDs or sending IR signals. Includes files such as `led_semaphore.py` and `IR_send.py`.

- **Functionality Module (`Device.py`):**  
  This file implements a class that encapsulates the complete logic of the IoT device. It internally integrates the sensor, communication, processing, authentication, and actuator modules. It acts as a high-level abstraction of the device's behavior and allows centralized control from `main.py`.

- **Main Module (`main.py`):**  
  Serves as the entry point of the system, coordinating the execution of the above modules in a continuous workflow.

---

The firmware design also adopts an **object-oriented programming (OOP)** approach, allowing encapsulation of the behavior and state of each component in classes. This improves code organization, facilitates feature extension, and promotes best practices in embedded system development using MicroPython.

---

## 👥 Authors

- Alejandro Salinas  
- José Zapata  
- Raziel Campos
