#include <EspIoT.h>
#include <LittleFS.h>
#include <espiot/example/UsbWifi.h>

#include <cmath>
#include <memory>
#include <new>

std::unique_ptr<uint8_t[]> certificate;
std::unique_ptr<uint8_t[]> privateKey;
EspIoT device;
uint32_t lastReading = 0;
bool configured = false;

size_t loadPem(const char* path, std::unique_ptr<uint8_t[]>& destination) {
  File file = LittleFS.open(path, "r");
  const size_t size = file ? file.size() : 0;
  if (!size || size >= 8192) return 0;
  auto buffer = std::unique_ptr<uint8_t[]>(new (std::nothrow) uint8_t[size + 1]);
  if (!buffer || file.read(buffer.get(), size) != size) return 0;
  buffer[size] = 0;
  destination = std::move(buffer);
  return size + 1;
}

void setup() {
  Serial.begin(115200);
  delay(1500);
  if (!LittleFS.begin(false)) {
    Serial.println("Provision LittleFS with this board's TLS certificate and private key.");
    return;
  }
  const size_t certLength = loadPem("/device.crt", certificate);
  const size_t keyLength = loadPem("/device.key", privateKey);
  if (!certLength || !keyLength ||
      !device.addSensor("chip_temperature", "Chip temperature",
                        "\xC2\xB0"
                        "C") ||
      !espiot::example::connectUsbWifi()) {
    Serial.println("Check the certificate, private key, and Wi-Fi before resetting.");
    return;
  }
  EspIoT::TlsCredentials tls{certificate.get(), certLength, privateKey.get(), keyLength};
  configured = device.beginSecure("ESP IoT Secure Sensor", "sensor", 1, tls, 8443);
  if (!configured) {
    Serial.println("Secure setup failed. Check the certificate and saved device storage.");
    return;
  }
  Serial.println("HTTPS port 8443. Use the SHA-256 fingerprint below in ESP IoT.");
  Serial.println(device.certificateFingerprint());
  Serial.println("Enter uppercase P to open pairing or uppercase R to revoke all pairings.");
}

void loop() {
  device.poll();
  if (configured && Serial.available()) {
    const int input = Serial.read();
    if (input == 'P') {
      char code[9]{};
      if (device.openPairingWindow(code)) {
        Serial.print("One-time pairing code, valid for 60 seconds: ");
        Serial.println(code);
      } else
        Serial.println("Pairing unavailable. Check the connection and available slots.");
    } else if (input == 'R') {
      Serial.println(device.clearPairings() ? "All pairings revoked."
                                            : "Could not save pairing changes.");
    }
  }
  if (configured && millis() - lastReading >= 2000) {
    lastReading = millis();
    const float reading = temperatureRead();
    if (std::isfinite(reading))
      device.publishNumber("chip_temperature", reading);
    else
      device.publishUnavailable("chip_temperature");
  }
  delay(10);
}
