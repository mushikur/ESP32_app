#include <Arduino.h>

constexpr uint8_t ledPin = 23;
constexpr uint8_t buttonPin = 18;

void setup() {
  pinMode(ledPin, OUTPUT);
  digitalWrite(ledPin, LOW);
  pinMode(buttonPin, INPUT_PULLUP);
}

void loop() {
  // The button joins the input to GND when pressed.
  const bool pressed = digitalRead(buttonPin) == LOW;
  digitalWrite(ledPin, pressed ? HIGH : LOW);
  delay(10);
}
