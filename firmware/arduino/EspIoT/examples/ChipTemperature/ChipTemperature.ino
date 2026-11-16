#include <EspIoT.h>
#include <espiot/example/UsbWifi.h>

#include <cmath>

EspIoT device;
uint32_t lastReading = 0;
bool configured = false;

void setup() {
  Serial.begin(115200);
  delay(1500);
  configured = device.addSensor("chip_temperature", "Chip temperature",
                                "\xC2\xB0"
                                "C") &&
               espiot::example::connectUsbWifi() &&
               device.begin("ESP IoT Chip Sensor", "sensor", 1, 8080);
  Serial.println(configured ? "ESP IoT HTTP port 8080"
                            : "Setup could not finish. Check Wi-Fi, then reset.");
}

void loop() {
  if (configured && millis() - lastReading >= 2000) {
    lastReading = millis();
    const float reading = temperatureRead();
    if (std::isfinite(reading))
      device.publishNumber("chip_temperature", reading);
    else
      device.publishUnavailable("chip_temperature");
  }
  device.poll();
  delay(10);
}
