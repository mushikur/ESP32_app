# ESP32 Learn & Build Phase E

Open **Learn**, choose a project, then open **Wire the circuit → Practice wiring**. Each round highlights a starting terminal. Tap the matching destination on the schematic or use **Choose a terminal** for a text list. Zoom and pan work in practice. **Hint** explains the connection’s purpose and can reveal the destination.

A correct answer animates the existing lesson wire. A wrong answer leaves the schematic unchanged. A terminal on the same electrical net receives separate feedback when the round asks for a different connection. The lab evaluates the schematic’s connections. Follow the wiring and test instructions when building the real circuit.

Practice saves locally and resumes at the first unmatched connection. **Practice again** clears practice for that lesson. Component checks, real wire checks, upload and test results, XP, and streaks are tracked independently. Practice is optional and all seven lessons are available offline in English and Bangla.

## New lessons

| Lesson | Circuit | Learning objective |
| --- | --- | --- |
| Two LEDs with Different Patterns | IO23 through 330 Ω to the red LED. IO22 through 330 Ω to a low forward-voltage green LED. Both cathodes share ground. | Use two independent `millis()` intervals. Red switches every 500 ms and green every 1,000 ms. |
| Light Intensity Monitor | 3V3 through 10 kΩ and an LDR to the IO34 sense node, then through 10 kΩ to ground. | Average eight voltage samples and compare bright and covered readings at 115200 baud. Readings are relative light measurements in millivolts. |

Both lessons use the Espressif ESP32-DevKitC V4 with ESP32-WROOM-32E. They include component lists, schematics, downloadable sketches, code explanations, upload instructions, test checklists, and troubleshooting. [Espressif pinout](https://docs.espressif.com/projects/esp-dev-kits/en/latest/esp32/esp32-devkitc/user_guide.html#header-block) · [Arduino timing reference](https://docs.arduino.cc/language-reference/en/functions/time/millis/) · [Espressif ADC reference](https://docs.espressif.com/projects/arduino-esp32/en/latest/api/adc.html)

## Add practice to a lesson

The app generates practice rounds from the lesson’s validated `wires` in order. A round starts at `from` and accepts `to`. Each accepted wire uses its existing `wiringLayout` path. Keep project IDs and terminal names stable to retain saved matches. To add a project, follow the [lesson authoring guide](learn-phase-a.md#add-a-lesson) and [schematic guide](learn-phase-b.md#maintain-a-diagram). Test every path and use the physical circuit procedure before marking the lesson bench-tested.

## Run the checks

Run from the workspace root with PowerShell 7.5, Arduino CLI, and Espressif core `3.3.12`. Pass `-ArduinoCli` if the executable is outside PATH.

```powershell
pwsh -NoProfile -File .\firmware\tests\test-learn-sketches.ps1
Set-Location .\app
flutter analyze
flutter test
flutter build apk --debug
```

All seven Arduino sketches compiled. The full Flutter suite passed 61 tests before final lint cleanup, and Dart analysis of the final Learn source and tests reported zero issues. Android packaging and emulator verification are pending. Automatic approval review reached its usage limit before the final Flutter build could start. Physical circuit checks also remain pending.
