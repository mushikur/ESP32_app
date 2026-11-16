#include <Arduino.h>

constexpr uint8_t servoPin = 18;
constexpr uint32_t frequencyHz = 50;
constexpr uint8_t resolutionBits = 14;
constexpr uint32_t periodUs = 20000;
bool pwmReady = false;

void moveServo(uint16_t pulseUs) {
  const uint32_t duty = pulseUs * (1UL << resolutionBits) / periodUs;
  ledcWrite(servoPin, duty);
}

void setup() {
  Serial.begin(115200);
  pwmReady = ledcAttach(servoPin, frequencyHz, resolutionBits);
  if (!pwmReady) {
    Serial.println("Could not start servo pulses. Check the selected board.");
    return;
  }
  moveServo(1500);
  delay(1500);
}

void loop() {
  if (!pwmReady) {
    delay(1000);
    return;
  }
  // Use three positions near the centre and allow the unloaded servo to settle.
  moveServo(1200);
  delay(1500);
  moveServo(1500);
  delay(1500);
  moveServo(1800);
  delay(1500);
  moveServo(1500);
  delay(1500);
}
