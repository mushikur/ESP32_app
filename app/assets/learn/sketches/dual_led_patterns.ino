#include <Arduino.h>

constexpr uint8_t redPin = 23;
constexpr uint8_t greenPin = 22;
constexpr unsigned long redInterval = 500;
constexpr unsigned long greenInterval = 1000;
unsigned long lastRed = 0;
unsigned long lastGreen = 0;
bool redOn = false;
bool greenOn = false;

void setup() {
  pinMode(redPin, OUTPUT);
  pinMode(greenPin, OUTPUT);
  digitalWrite(redPin, LOW);
  digitalWrite(greenPin, LOW);
  lastRed = lastGreen = millis();
}

void loop() {
  const unsigned long now = millis();
  if (now - lastRed >= redInterval) {
    lastRed = now;
    redOn = !redOn;
    digitalWrite(redPin, redOn ? HIGH : LOW);
  }
  if (now - lastGreen >= greenInterval) {
    lastGreen = now;
    greenOn = !greenOn;
    digitalWrite(greenPin, greenOn ? HIGH : LOW);
  }
}
