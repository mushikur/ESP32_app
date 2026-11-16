#include <EspIoT.h>
#include <espiot/example/UsbWifi.h>

#if __has_include("BenchPin.h")
#include "BenchPin.h"
#endif

#ifndef ESP_IOT_LED_PIN
#define ESP_IOT_LED_PIN -1
#endif

EspIoT device;

bool setLed(void*, bool enabled) {
  digitalWrite(ESP_IOT_LED_PIN, enabled ? HIGH : LOW);
  return true;
}

void setup() {
  Serial.begin(115200);
  delay(1500);
  if (ESP_IOT_LED_PIN < 0 || !digitalPinCanOutput(ESP_IOT_LED_PIN)) {
    Serial.println("Set a usable LED GPIO in BenchPin.h before running this example.");
    return;
  }
  pinMode(ESP_IOT_LED_PIN, OUTPUT);
  digitalWrite(ESP_IOT_LED_PIN, LOW);
  if (!device.addSwitch("led", "Bench LED", setLed) || !device.publishSwitch("led", false) ||
      !espiot::example::connectUsbWifi() ||
      !device.begin("ESP IoT Bench LED", "lighting", 1, 8080)) {
    Serial.println("Setup could not finish. Check the LED configuration and Wi-Fi, then reset.");
    return;
  }
  Serial.println("ESP IoT HTTP port 8080");
}

void loop() {
  device.poll();
  delay(10);
}
