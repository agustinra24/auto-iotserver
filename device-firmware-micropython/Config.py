"""
This code is the configure file to set up all the variables
and parameters which are necessary to use the IoT system
This sections the passwords, IDs, PinOut, PinIn, and so on.
"""

# Identity fields
Nombre = "Esp32"
ID = '012345678'

# Wifi Fields
WifiSSID = 'AlexWifi'
WifiPassword = 'Alex1234'

#AES parameters
AES_Password = "Alex1234"


# Authentication Parameters
User_Name = "Sensor03"
Password = "789101112"

#End Points
End_Point= "http://148.247.201.66/"

## Pin out and in for sensor and outputs
# TODO: Ask how to define these variables, upper or lower case or mixed?

# Sensors
Pin_Sensor_Mic = 34
Pin_Sensor_Temp = 32

# Outputs / Actuators
Pin_IR_emitter = 13
Pin_Led_Green = 21
Pin_Led_Yellow = 22
Pin_Led_Red = 23

# Parameters Noise Fields:
high_level_noise = 2.5
medium_level_noise = 2.0

# Humidity and Temperature:

# IR Raw data control
IR_raw_data = [ 1230, 420, 1230, 420, 430, 1220, 1280, 420, 1230, 420, 430, 1220,
               430, 1220, 430, 1270, 380, 1270, 430, 1220, 430, 1270, 1230, 7020,
               1230, 420, 1280, 420, 430, 1220, 1230, 420, 1280, 370, 430, 1270,
               430, 1220, 430, 1220, 430, 1220, 430, 1270, 380, 1270, 1230, 7870,
               1280, 420, 1230, 420, 430, 1220, 1280, 420, 1230, 420, 380, 1270,
               430, 1220, 430, 1220, 430, 1270, 380, 1270, 430, 1220, 1230, 7070]