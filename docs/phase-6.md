# ESP IoT Phase 6 firmware library

The [EspIoT library](../firmware/arduino/EspIoT) turns an ESP32 project into an ESP IoT v1 device. A sketch registers its capabilities, joins trusted Wi-Fi, calls `begin`, and calls `poll` from its main loop. The Android app uses the advertised description to build the dashboard. The firmware uses Espressif's HTTP server and mDNS components. [ESP HTTP Server](https://docs.espressif.com/projects/esp-idf/en/v5.5/esp32/api-reference/protocols/esp_http_server.html) · [Espressif mDNS](https://components.espressif.com/components/espressif/mdns)

## Add it to an ESP32 project

Use Arduino IDE 2 or Arduino CLI with the Espressif ESP32 board core. Copy `firmware/arduino/EspIoT` into the sketchbook's `libraries` directory, or point Arduino CLI to the library with `--library`. The library uses components supplied by the board core. [Arduino library structure](https://docs.arduino.cc/arduino-cli/library-specification)

1. Initialize your project's pins and sensors. Create one long-lived `EspIoT` instance. Call `addSwitch`, `addRange`, `addSensor`, `addAction`, or `addMotionStop` to describe the project. Use stable capability IDs and increment the descriptor revision when capabilities change.
2. Join the trusted Wi-Fi in station mode. Once it has a private IPv4 address, call `device.begin("My ESP32", "controller", 1, 8080)`. Check `device.running()` if you need to know when the HTTP listener is ready. Use a free HTTP port when your project also has a web panel.
3. Call `device.poll()` frequently from the task that called `begin`. It services discovery, schedules event updates, and restores listeners when the Wi-Fi link returns. Publish new values with `publishSwitch`, `publishNumber`, or `publishUnavailable`.
4. Return `true` from a command callback after the local change succeeds. The SDK sends the acknowledgement and updates a writable capability's state. Callbacks run on the HTTP server task under the state lock. Keep them short, avoid calling SDK methods from inside them, and make Stop callbacks idempotent. `end` shuts down the listeners.

The device ID is generated on first setup and saved in the board's NVS. The boot ID changes after a reboot. The HTTP listener accepts peers on the current private Wi-Fi subnet. It serves the descriptor, status, and command routes. On board cores with WebSocket support it also serves a read-only snapshot stream. Discovery uses `_espiot._tcp` and nonce-matched unicast replies to local queries on UDP port `55073`. The SDK's ESP HTTP Server instance also uses port `32770` for internal control messages.

The current SDK advertises `auth: none` over HTTP. Use it on a trusted bench network. HTTP provides no encryption or hardware authentication. Firmware-side token enrollment and HTTPS/WSS remain later work. Guarded motion starts are disabled. A project with physical motion needs a physical stop and a local watchdog before deployment.

## Arduino examples

- [BenchLed](../firmware/arduino/EspIoT/examples/BenchLed/BenchLed.ino) controls one active-high LED. Copy `BenchPin.example.h` to `BenchPin.h` and choose the correct output GPIO for a low-voltage bench LED and its current-limiting resistor. The sketch starts with the pin unconfigured so the board choice is explicit.
- [ChipTemperature](../firmware/arduino/EspIoT/examples/ChipTemperature/ChipTemperature.ino) publishes the ESP32's internal chip temperature. It shows an unavailable reading when the core returns an invalid value. Use a separate sensor for ambient temperature.

Open the USB serial monitor at **115200 baud** with **Newline** selected. After reset, enter the Wi-Fi name and password at the prompts. The sketches avoid echoing the password or saving it to flash. In ESP IoT, open **Discover**, select the device, and register it. Manual entry uses the address printed on USB serial and port `8080`.

## ESP-IDF integration

The [ESP-IDF component wrapper](../firmware/esp-idf/esp_iot) uses the same sources as the Arduino library. For an ESP-IDF 5.5 project, add the wrapper's directory to `EXTRA_COMPONENT_DIRS` before including `project.cmake` and add `esp_iot` to the consuming component's requirements. Initialize NVS and networking in the application and use the default Wi-Fi station interface from `esp_netif_create_default_wifi_sta()`. The component manager resolves `espressif/mdns`. Enable `CONFIG_HTTPD_WS_SUPPORT` to advertise events. A standalone ESP-IDF build still needs verification. [ESP-IDF component build system](https://docs.espressif.com/projects/esp-idf/en/v5.5/esp32/api-guides/build-system.html)

## Run and test

Run from the workspace root. Install the ESP32 board core only if it is missing. The verified core version is `3.3.12`.

```powershell
arduino-cli core update-index --additional-urls https://espressif.github.io/arduino-esp32/package_esp32_index.json
arduino-cli core install esp32:esp32@3.3.12 --additional-urls https://espressif.github.io/arduino-esp32/package_esp32_index.json
arduino-cli compile --fqbn esp32:esp32:esp32 --library firmware/arduino/EspIoT --build-path firmware/build/bench-led-esp32 --build-property 'compiler.cpp.extra_flags=-DESP_IOT_LED_PIN=2' firmware/arduino/EspIoT/examples/BenchLed
arduino-cli compile --fqbn esp32:esp32:esp32c3 --library firmware/arduino/EspIoT --build-path firmware/build/temperature-c3 firmware/arduino/EspIoT/examples/ChipTemperature
pwsh -NoProfile -File .\firmware\tests\test-firmware.ps1 -FlutterContract
pwsh -NoProfile -File .\protocol\v1\test-descriptor.ps1
```

The LED pin in the compile check is an example for the compiler. Use a board-specific configuration before flashing. The host suite needs a C++14 compiler and PowerShell 7.5 or newer. `-FlutterContract` also requires Flutter and the dependencies in `app/`. It sends an Android-generated command into the actual C++ protocol engine and parses the firmware's acknowledgement and follow-up state.

For hardware verification, flash a selected board and test discovery over mDNS and UDP, live status, one LED change, reconnect after a Wi-Fi interruption, and identity persistence across a board reboot. Physical board networking and electrical behavior remain unverified.

## Verification

- `BenchLed` compiled for `esp32:esp32:esp32` with its LED code enabled. `ChipTemperature` compiled for `esp32:esp32:esp32c3`. Both binaries linked the HTTP command, UDP discovery, and WebSocket handlers.
- All six C++ protocol checks passed. The generated descriptor passed the shared schema. A Flutter contract test used the Android protocol models to decode the firmware descriptor, send a command, match the acknowledgement, and read the updated status.
- All 42 existing Flutter tests and 10 protocol descriptor checks passed.

## Changed files and next phase

- [Arduino SDK and examples](../firmware/arduino/EspIoT)
- [ESP-IDF wrapper](../firmware/esp-idf/esp_iot)
- [Firmware and Flutter contract tests](../firmware/tests)
- [v1 protocol implementation notes](protocol-v1.md)
- [Workspace README](../README.md)

Phase 7 adds device-issued pairing, verifies secure transport and reconnect behavior, and tests the firmware with physical boards.
