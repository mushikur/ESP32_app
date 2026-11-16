# ESP32 Learn & Build Phase C

In any of the five starter lessons, open **Read the sketch**.

- **Complete code** shows the whole Arduino C++ sketch with line numbers and syntax colors. **Copy sketch** copies the original source.
- **Learn the code** explains every nonblank line in short groups. Tap a topic to highlight the corresponding numbered lines and read the explanation in English or Bangla.
- **Download .ino** opens Android’s save picker. Choose a folder such as **Downloads** and save. The app writes the original UTF-8 source to the document you selected and confirms the save after writing finishes. The picker grants access to the chosen document. [Android Storage Access Framework](https://developer.android.com/training/data-storage/shared/documents-files)

Transfer the saved file to your computer. In Arduino IDE, the sketch folder and primary file must have matching names, such as `led_blink/led_blink.ino`. Use the name shown in the lesson if the phone adds a duplicate-file suffix. [Arduino sketch specification](https://docs.arduino.cc/arduino-cli/sketch-specification)

## Arduino IDE walkthrough

Open **Upload with Arduino IDE** and use **Next**, **Previous**, or the step selector. The nine in-app illustrations show the relevant Arduino IDE 2 controls for installing the IDE, adding the board package URL, using Boards Manager, connecting USB, selecting the board and port, checking libraries, opening a sketch, verifying and uploading, and reading Serial Monitor or checking the project. The five starter sketches use the bundled `Arduino.h` from the ESP32 board package. [Arduino IDE upload guide](https://support.arduino.cc/hc/en-us/articles/4733418441116-Upload-a-sketch-in-Arduino-IDE) · [Espressif board package setup](https://docs.espressif.com/projects/arduino-esp32/en/latest/installing.html)

Use the ESP32-DevKitC V4 with ESP32-WROOM-32E, the **ESP32 Dev Module** IDE profile, and Espressif Arduino core `3.3.12`. Choose the serial port that appears when you connect your board with a Micro-USB data cable. The COM port in the illustration is an example. The LDR and servo sketches use `115200` baud. The LDR prints readings continuously and the servo prints an error if PWM setup fails. [Arduino Serial Monitor](https://docs.arduino.cc/software/ide-v2/tutorials/ide-v2-serial-monitor/)

**Upload troubleshooting** covers missing ports and USB drivers, missing board profiles, compile errors, busy ports, the DevKitC BOOT and EN controls, and serial output at the wrong baud rate. Firmware upload is performed manually in Arduino IDE on the computer. Mark the lesson’s upload checkpoint after the IDE reports completion. [Espressif flashing troubleshooting](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/get-started/flashing-troubleshooting.html)

## Maintain a lesson

Edit `codeNotes` in the lesson JSON and keep the `.ino` source under `app/assets/learn/sketches`. Each note has a one-based, inclusive `lines` range, an `anchor` matching the trimmed first source line, and localized `title` and `text` fields. Keep ranges ordered and disjoint, and cover all nonblank lines. Blank lines may separate notes. Catalog loading rejects gaps, overlaps, or an anchor that no longer matches the source.

The upload walkthrough and troubleshooting are in `app/assets/learn/catalog.json`. The code viewer, upload guide, and Android export bridge use Flutter and the Android SDK. Sketch exports accept up to 32 KiB. No new runtime dependencies or storage permissions are required.

## Run the checks

From the workspace root, compile the bundled sketches with PowerShell 7.5 or newer and Arduino CLI. Add `-ArduinoCli` with the executable path when the CLI is outside PATH.

```powershell
pwsh -NoProfile -File .\firmware\tests\test-learn-sketches.ps1
Set-Location .\app
flutter analyze
flutter test
flutter build apk --debug
```

Flutter analysis reported zero issues, all 56 Flutter tests passed, and the Android debug APK built. All five Arduino sketches compiled against Espressif core `3.3.12`. On an Android emulator with no active network, the Blink lesson saved `led_blink.ino` into Downloads through Android’s picker. The exported file and the bundled sketch had identical SHA-256 hashes. The emulator also displayed the selected code lines and the Verify and Upload illustration. Physical USB upload and circuit tests remain pending.

Phase D adds per-test progress, project troubleshooting, and achievements.
