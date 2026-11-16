#include <Arduino.h>

constexpr uint8_t redPin = 23;
constexpr uint8_t yellowPin = 22;
constexpr uint8_t greenPin = 21;

void showLight(uint8_t activePin) {
  // Turn all three outputs off before turning the selected light on.
  digitalWrite(redPin, LOW);
  digitalWrite(yellowPin, LOW);
  digitalWrite(greenPin, LOW);
  digitalWrite(activePin, HIGH);
}

void setup() {
  pinMode(redPin, OUTPUT);
  pinMode(yellowPin, OUTPUT);
  pinMode(greenPin, OUTPUT);
}

void loop() {
  showLight(redPin);
  delay(3000);
  showLight(greenPin);
  delay(3000);
  showLight(yellowPin);
  delay(1000);
}
