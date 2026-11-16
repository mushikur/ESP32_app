#include <Arduino.h>

constexpr uint8_t ledPin = 23;
constexpr uint8_t sensorPin = 34;
constexpr uint32_t thresholdMv = 650;  // Adjust using your measured values.
constexpr uint32_t bandMv = 40;       // Keep this below the threshold.
bool lampOn = false;

void setup() {
  Serial.begin(115200);
  pinMode(ledPin, OUTPUT);
  digitalWrite(ledPin, LOW);
  analogSetPinAttenuation(sensorPin, ADC_11db);
}

void loop() {
  const uint32_t lightMv = analogReadMilliVolts(sensorPin);
  if (lightMv < thresholdMv - bandMv) {
    lampOn = true;
  } else if (lightMv > thresholdMv + bandMv) {
    lampOn = false;
  }
  digitalWrite(ledPin, lampOn ? HIGH : LOW);
  Serial.printf("Light input: %lu mV\n", static_cast<unsigned long>(lightMv));
  delay(200);
}
