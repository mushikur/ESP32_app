#pragma once

#include <Arduino.h>
#include <WiFi.h>

namespace espiot {
namespace example {

inline bool readUsbLine(char* buffer, size_t capacity) {
  size_t length = 0;
  bool overflow = false;
  const uint32_t start = millis();
  while (millis() - start < 90000) {
    const int input = Serial.read();
    if (input < 0) {
      delay(10);
      continue;
    }
    if (input == '\r') continue;
    if (input == '\n') {
      buffer[length] = 0;
      return !overflow;
    }
    if (input < 0x20 || input == 0x7f || length + 1 >= capacity)
      overflow = true;
    else
      buffer[length++] = static_cast<char>(input);
  }
  return false;
}

inline bool connectUsbWifi() {
  char ssid[33]{}, password[65]{};
  Serial.println("Enter the trusted Wi-Fi name, followed by Newline.");
  if (!readUsbLine(ssid, sizeof(ssid)) || !ssid[0]) return false;
  Serial.println("Enter its Wi-Fi password, followed by Newline.");
  const bool entered = readUsbLine(password, sizeof(password));
  if (entered) {
    WiFi.persistent(false);
    WiFi.mode(WIFI_STA);
    WiFi.setAutoReconnect(true);
    WiFi.begin(ssid, password);
  }
  volatile char* clear = password;
  for (size_t index = 0; index < sizeof(password); ++index) clear[index] = 0;
  if (!entered) return false;
  const uint32_t start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 25000) delay(50);
  if (WiFi.status() != WL_CONNECTED) return false;
  Serial.print("Local address ");
  Serial.println(WiFi.localIP());
  return true;
}

}  // namespace example
}  // namespace espiot
