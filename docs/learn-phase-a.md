# ESP32 Learn & Build Phase A

Open **Learn** in ESP IoT. Search or filter the library, open a project, and select **Start building**. Use the step selector to review the parts, wiring, code, manual Arduino IDE upload, tests, and troubleshooting. The four progress checkboxes are your own confirmations. The app saves them and your lesson language on the phone. Use the language button to switch between English and Bangla. Lessons, sketches, and illustrations are available offline.

## Starter circuits

All five lessons target Espressif **ESP32-DevKitC V4 with ESP32-WROOM-32E**. The in-app wiring steps show the silkscreen labels and exact header positions. Use a different board only after checking its own pinout and voltage limits. [Espressif board pinout and power requirements](https://docs.espressif.com/projects/esp-dev-kits/en/latest/esp32/esp32-devkitc/user_guide.html)

| Lesson | Key electrical checks | Expected result |
| --- | --- | --- |
| Blink an LED | IO23 through 330 Ω to LED anode, cathode to GND | Red LED completes one blink per second |
| Push Button LED | Same LED circuit, normally open switch between IO18 and GND, internal pull-up | LED lights while the button is held |
| Traffic Light Model | IO23 red, IO22 yellow, IO21 green, with a separate 330 Ω resistor per LED | Red for three seconds, green for three, yellow for one |
| LDR Night Light | 3V3 → 10 kΩ → LDR → IO34 sense node → 10 kΩ → GND, with a separate IO23 LED circuit | ADC reading falls when the sensor is covered and the LED lights below the calibrated threshold |
| Servo Angle Control | IO18 signal to FEETECH FS90, separate regulated 5 V servo power, shared ground | The unloaded servo moves between three positions and pauses at each |

The LDR divider caps the sense voltage at about 1.65 V for nominal 10 kΩ resistors and a 3.3 V supply. Calibrate the threshold with the measured bright and covered values. The FS90 supports a 3.3 V control signal. The sketch uses a 50 Hz signal with 1,200, 1,500, and 1,800 µs pulses inside its published operating range. Keep the servo unloaded and connect only the external supply ground to the USB-powered ESP32. [Arduino-ESP32 ADC reference](https://docs.espressif.com/projects/arduino-esp32/en/latest/api/adc.html) · [Arduino-ESP32 LEDC reference](https://docs.espressif.com/projects/arduino-esp32/en/latest/api/ledc.html) · [FS90 specifications and datasheet](https://www.pololu.com/product/2818)

## Build and test

Use Arduino IDE 2 or Arduino CLI with Espressif Arduino core `3.3.12`. Select **ESP32 Dev Module** for this board. No external Arduino libraries are required. [Espressif Arduino setup](https://docs.espressif.com/projects/arduino-esp32/en/latest/installing.html) · [Arduino IDE board and port selection](https://support.arduino.cc/hc/en-us/articles/4406856349970-Select-board-and-port-in-Arduino-IDE)

Run from the workspace root in PowerShell 7.5 or newer.

```powershell
arduino-cli core update-index --additional-urls https://espressif.github.io/arduino-esp32/package_esp32_index.json
arduino-cli core install esp32:esp32@3.3.12 --additional-urls https://espressif.github.io/arduino-esp32/package_esp32_index.json
pwsh -NoProfile -File .\firmware\tests\test-learn-sketches.ps1
Set-Location .\app
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

Skip core installation if the version is installed. Pass `-ArduinoCli` to the test script if the executable is outside PATH. The script compiles each bundled sketch for `esp32:esp32:esp32`.

Flutter analysis reported zero issues and all 50 tests passed. All five sketches compiled against Espressif core `3.3.12`. The debug APK built and ran on a small Android emulator with no active network. The emulator reopened the Blink lesson in Bangla and showed its saved checkpoint after an app restart. Physical circuit tests are pending.

For the hardware pass, use a dedicated DevKitC V4 with the components named in the lesson. Start with USB and external power disconnected and trace each terminal in the app. For the servo, switch on the separate 5 V supply before connecting USB. Upload the sketch over USB from the IDE and complete each lesson’s expected-behavior checks. Record the bright and covered millivolt readings for the LDR. Check the servo unloaded. For normal shutdown, disconnect USB before switching off the servo supply.

## Add a lesson

1. Add a stable lowercase project ID to `app/assets/learn/catalog.json`. Reuse the catalog’s board and parts where applicable.
2. Add a project JSON file under `app/assets/learn/projects` and an Arduino sketch with the same ID under `app/assets/learn/sketches`. Copy a current lesson to see the required fields and provide English and Bangla strings.
3. Assign an instance ID to every part and reference each end of a connection as `[instanceId, terminal]`. Use a board pin from the documented pinout and match the project’s `gpio` mapping to named `constexpr uint8_t ...Pin` declarations in the sketch.
4. Include the circuit-specific safety instructions, expected results, and troubleshooting. Match each code explanation anchor to a fragment in the real sketch. Choose an existing preview style or add one to `learn_art.dart`.
5. Add a wiring expectation in `app/test/learn_test.dart`, run the app and sketch checks, and perform the hardware pass before marking the lesson bench-tested.

The app validates bundled content before opening the library. It checks project and board IDs, component references, wire terminals, pin constants, and code explanation anchors. The wiring review and bench test cover the electrical behavior. Publishing additional bundled lessons currently requires an app update.

## Next phases

Phase B adds board diagrams, a pin explorer, an interactive wiring lab, and per-component and per-wire checklists using the existing connection data. Phase C adds source download, interactive code explanations, and an illustrated IDE walkthrough. Phase D adds per-test tracking and achievements. Phase E expands the lesson library and wiring practice.
