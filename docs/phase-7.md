# ESP IoT Phase 7 secure pairing and reliability

The Android app and ESP32 SDK support device-issued pairing over verified HTTPS. On a secure device, the descriptor remains public. Status, commands, and pairing removal require the token issued to that phone. The app saves the token in Android encrypted storage and binds it to the registration's device ID, HTTPS origin, and certificate fingerprint when supplied. [Android storage package](https://pub.dev/packages/flutter_secure_storage) · [ESP HTTPS Server](https://docs.espressif.com/projects/esp-idf/en/v5.5/esp32/api-reference/protocols/esp_https_server.html)

## Pair a phone

1. Start the ESP32 secure firmware on trusted Wi-Fi. For a privately issued or self-signed certificate, get its SHA-256 fingerprint from the board or an administrator you trust. The secure example prints it on USB serial.
2. In **Discover → Enter device address**, enter the board's address and port. Turn on **Use HTTPS**. Enter its fingerprint if it uses a private certificate. The app also accepts a pairing QR with an HTTPS fingerprint supplied by the device owner. With the fingerprint field blank, HTTPS uses the standard certificate trust checks. [Dart TLS verification](https://api.dart.dev/dart-io/SecureSocket/startConnect.html)
3. Register the verified device and open its connection screen. On the board, physically open a pairing window. With the secure example, send uppercase `P` on USB serial at 115200 baud.
4. Select **Pair securely**, enter the eight-digit code, and select **Pair device**. The code expires after 60 seconds or after use. A successful status reply confirms the connection.
5. Use **Remove pairing** to revoke this phone's token on the board. Use uppercase `R` in the secure example to revoke all tokens from the board. **Remove device** in device settings removes the local registration and its saved token. Revoke the board's token before removing the local registration when possible.

A fingerprint verifies the exact, currently valid leaf certificate supplied by the device. A new certificate or HTTPS origin needs fresh verification and pairing. For a replaced pinned certificate, revoke the old pairing and register the new fingerprint. The existing trusted-HTTP examples remain available with the app's local-network warning. Firmware continues to reject motion starts.

## Secure Arduino example

The [SecureChipTemperature sketch](../firmware/arduino/EspIoT/examples/SecureChipTemperature/SecureChipTemperature.ino) uses HTTPS on port `8443`. Provision a distinct certificate and private key for each board. Place them in the selected board's LittleFS volume as `/device.crt` and `/device.key`. The example mounts LittleFS with formatting disabled. For deployment, protect the private key and consider hardware-backed storage or flash encryption as part of provisioning.

For a bench certificate, run this from a new private folder for the board. Use its planned private IPv4 address in the subject alternative name.

```powershell
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -sha256 -days 365 -subj '/CN=ESP IoT bench' -addext 'subjectAltName=IP:192.168.1.100' -keyout device.key -out device.crt
openssl x509 -in device.crt -noout -fingerprint -sha256
```

Upload the sketch using the board and partition layout selected in Arduino IDE. Provision its LittleFS image using the same partition layout. For the ESP32-C3 `huge_app` layout checked in this phase, the filesystem partition is `spiffs` at `0x310000` with size `0xE0000`. A filesystem image upload replaces that partition's contents. Keep the private key and any filesystem image outside source control.

The firmware opens a pairing window only through a sketch callback. It accepts at most five attempts per window with a 750 ms minimum interval, keeps up to four token digests in board storage, and scopes command acknowledgements to the caller. Pairing windows close when the Wi-Fi listener stops. The app reconnects after transient connection loss, rechecks identity before sending a token, and asks for a fresh check when the Wi-Fi link changes.

The tested Arduino board core lacks the WebSocket authorization hook required before upgrade. Secure firmware on that core advertises HTTPS status polling. The Android WSS path was tested with an authorized loopback server. A configurable ESP-IDF build can enable the pre-handshake hook, and still needs board verification.

The Dart WebSocket reader can buffer fragments before the app checks an assembled message's size. The ESP IoT SDK emits individual, bounded snapshot frames.

## Build and test

Run these commands from the workspace root. Use the installed Espressif Arduino core `3.3.12` or follow the [Phase 6 setup](phase-6.md).

```powershell
arduino-cli compile --fqbn esp32:esp32:esp32c3:PartitionScheme=huge_app --library firmware/arduino/EspIoT --build-path firmware/build/secure-temperature-c3 firmware/arduino/EspIoT/examples/SecureChipTemperature
pwsh -NoProfile -File .\firmware\tests\test-firmware.ps1 -FlutterContract
pwsh -NoProfile -File .\firmware\tests\test-secure-transport.ps1
pwsh -NoProfile -File .\protocol\v1\test-descriptor.ps1
Set-Location .\app
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

The TLS check needs OpenSSL 3 and accepts an explicit path with `-OpenSsl`. It generates and deletes its own certificate and key and listens on loopback. For a physical check, use a selected board to verify the serial code, discovery, pairing after a restart, revocation, one authorized command on a suitable bench device, and reconnect after interrupting Wi-Fi. The available serial entries during this phase identified only Bluetooth ports, so physical ESP32 validation remains pending.

## Verification

- The Android debug APK built successfully. Static analysis, all 44 Flutter tests, and all 10 descriptor checks passed.
- The secure ESP32-C3 sensor and the existing ESP32 BenchLed both compiled. Nine C++ checks passed, including pairing expiry, rate limiting, digest persistence and revocation, and principal-scoped command deduplication. The generated descriptor and Flutter protocol contract also passed.
- The loopback HTTPS and WSS test rejected an unknown certificate and credentials on cleartext, enrolled a matching certificate, restored the token from encrypted-storage APIs, verified an authorized command and live event, and rejected the token after revocation.
- The Android emulator registered the pinned HTTPS fixture, paired with its one-time code, reopened the saved pairing, received WSS status, verified an LED command and its new state, and returned to Authorization required after revocation.

## Changed files and next phase

- [Android pairing flow and token storage](../app/lib/features/connection/secure_pairing.dart), [device session](../app/lib/features/connection/device_session.dart), [TLS transport](../app/lib/core/transport/lan_transport.dart), and [discovery and trust settings](../app/lib/features/discovery).
- [ESP32 HTTPS adapter](../firmware/arduino/EspIoT/src/EspIoT.cpp), [pairing window and token ledger](../firmware/arduino/EspIoT/src/espiot/Pairing.cpp), [secure Arduino sketch](../firmware/arduino/EspIoT/examples/SecureChipTemperature), and [ESP-IDF component wrapper](../firmware/esp-idf/esp_iot).
- [Android pairing tests](../app/test/secure_pairing_test.dart), [firmware and TLS checks](../firmware/tests), and [protocol notes](protocol-v1.md).

Phase 8 prepares a provider-independent remote transport design. Physical ESP32 and native ESP-IDF checks remain release requirements.
