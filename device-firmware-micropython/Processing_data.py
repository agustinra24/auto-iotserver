import time
class ProcessingData:
    def __init__(self, esp32:object):
        self.noise_level = None
        self.temperature_level = None
        self.humidity_level = None
        self.esp32 = esp32

    def semaphore_action(self, data_pack):
        self.noise_level = data_pack['2_noise_level']
        if self.noise_level == "high":
            self.esp32.semaphore.set_red()
        elif self.noise_level == "medium":
            self.esp32.semaphore.set_yellow()
        else:
            self.esp32.semaphore.set_green()

    def fan_action(self, data_pack):
        self.temperature_level = data_pack['3_temperature']
        self.humidity_level = data_pack['4_humidity']
        if self.temperature_level == "low" and self.humidity_level == "high":
            print("Sending IR signal ... ... ...")
            for i in range(0,3):
                self.esp32.send_ir_signal()
                time.sleep(0.5)

        else:
            print("Nothing to do into IR emitter")



