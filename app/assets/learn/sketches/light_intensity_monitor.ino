#include <Arduino.h>

constexpr uint8_t sensorPin = 34;
constexpr uint8_t sampleCount = 8;

void setup() {
  Serial.begin(115200);
  analogSetPinAttenuation(sensorPin, ADC_11db);
}

void loop() {
  uint32_t totalMv = 0;
  for (uint8_t sample = 0; sample < sampleCount; sample++) {
    totalMv += analogReadMilliVolts(sensorPin);
  }
  const uint32_t averageMv = totalMv / sampleCount;
  Serial.printf("Light input: %lu mV\n", static_cast<unsigned long>(averageMv));
  delay(250);
}
