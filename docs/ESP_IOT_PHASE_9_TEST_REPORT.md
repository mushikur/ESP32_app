# ESP IoT Phase 9 test report

Test date: 2026-11-11, Asia/Dhaka. Target: Samsung SM-E236B, Android 14 (API 34), ARM64, ADB serial `RFCT41K26QX`. Every installation and app interaction used that serial. The requested Flutter inventory and doctor commands detected the emulator and read its device properties. The emulator received no APK or app tests. No app data was cleared and no package was uninstalled.

**Status legend.** PASS means executed and passed. FAIL means executed and failed. BLOCKED means a required device or access was unavailable. NOT TESTED means the check was not executed. MOCK TESTED means a software fixture provided simulated device behavior.

## Project inspection

The workspace contains the Flutter application, Android native bridges for Wi-Fi discovery and sketch export, an Arduino ESP32 SDK, an ESP-IDF component wrapper, a versioned protocol schema, and documentation for Phases 0–8 and Learn & Build A–E. The checkout has no Git metadata. `git status --short --branch` returned “not a git repository,” so existing edits could not be compared against a commit.

The app implements seven workspace tabs. Device management includes local registrations, discovery, connection setup, compatible HTTP and WebSocket profiles, dashboard layout, history, and pairing for authenticated devices. Learn & Build has seven lessons with localized content and saved progress. Automations is an empty-state screen. Remote MQTT is a design and transport interface. A separate Android Tools screen, USB/OTG Serial Monitor, and joystick controller are absent from the inspected routes and feature code.

## Build and automated checks

The debug build includes the completed device-control phases and all seven Learn & Build lessons, including Phase E wiring practice. The application ID is `com.example.esp_iot` and the project version is `0.1.0+1`. Build tools were Flutter 3.47.5 and Dart 3.13.4. Android Build Tools 36 confirmed minimum SDK 24, target SDK 36, and ARM64, ARMv7, and x86-64 binaries.

| Final artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| [Debug APK](../app/build/app/outputs/flutter-apk/app-debug.apk) | 225,822,324 | `8303AD0201B81CCAC0D4747824B041248B4ACD0F271A0C7F6067AE45C7012A2A` |
| [Unsigned release APK](../app/build/app/outputs/flutter-apk/app-release.apk) | 75,781,290 | `241E6420370CE8B188100C570B0C3AAC28F96A62EE044525FD3E6C0C61E60C78` |

| Check | Result |
| --- | --- |
| Flutter static analysis | PASS, zero issues |
| Flutter unit and component tests | PASS, 34 tests |
| Flutter widget tests | PASS, 29 tests, including logo entrance settling and stopping decorative loops offstage and with reduced motion |
| Native Flutter integration suite | NOT TESTED. The project has no `app/integration_test` suite. Host contract checks and ADB-driven physical tests are recorded separately. |
| Dependency check | PASS. `flutter pub outdated --no-transitive` found the direct runtime dependencies current. The pinned development-only `sqflite_common_ffi` was 2.4.6 with 2.4.7 available. |
| Flutter doctor | PASS for the Android toolchain, SDK 36 and accepted licenses. The Windows desktop toolchain reports missing Visual Studio. |
| Protocol descriptor schema | Passed all 10 cases |
| C++ firmware suite | Passed all nine cases and the generated descriptor schema check |
| Flutter and C++ firmware contract | Passed the host-side v1 descriptor, status, command, and acknowledgement exchange |
| Secure transport test | Passed the computer’s HTTPS/WSS loopback fixture for certificate verification, token enrollment, authorized events and commands, and revocation |
| Arduino lesson sketches | Compiled all seven sketches for `esp32:esp32:esp32` |
| Arduino SDK examples | Compiled BenchLed for ESP32 and ChipTemperature and SecureChipTemperature for ESP32-C3 with Arduino ESP32 core 3.3.12 |
| Android debug APK | PASS. Gradle built the final motion APK. |
| APK integrity | `apksigner` verified one signer using APK Signature Scheme v2 |
| Initial Android release build | FAIL at `:app:lintVitalRelease` with `ReferenceType` on the launcher resource alias |
| Release retest after icon fix | PASS. Gradle assembled the APK. `apksigner` confirmed the build is unsigned. A distribution signing configuration is still required. |
| Final motion release build | PASS for compilation and Android lint. The compiled resource table includes the launcher variants and animated splash. The APK is unsigned. |

The automated transport and firmware checks used test fixtures or host executables. They provide protocol evidence independently of physical ESP32 validation.

The three SDK example compiles follow the commands in [Phase 6](phase-6.md) and [Phase 7](phase-7.md). No board was flashed.

## Physical phone and app coverage

ADB authorization initially dropped during setup. Windows continued to report a healthy Samsung USB interface. After the user restarted the phone and approved USB debugging, ADB reported `device`. The streamed `install -r` succeeded and `am start -W` reported a successful cold launch. Package inspection confirmed `com.example.esp_iot`, version `0.1.0`, version code 1, and target SDK 36.

| Area | Physical check | Result |
| --- | --- | --- |
| Install and launch | Data-preserving USB install, cold launch and installed version | PASS on the Samsung |
| Home | Device counts, Wi-Fi status, discovery shortcut and recent devices layout | PASS for rendering and tab navigation |
| My Devices | Empty registry and later fixture registration | PASS for the empty screen. Fixture detail is listed below. |
| Discover | Automatic search and repeat search, empty state, required private IPv4 validation, HTTP warning, HTTPS fingerprint field and keyboard input | PASS for the tested UI and Wi-Fi discovery flow. The user confirmed no ESP32 was available. |
| Learn & Build | Open the catalog and view the seven bundled projects | PASS for the catalog. Individual guided interactions are tracked below. |
| Automations | Open the existing empty state | PASS |
| Activity | Verify the empty state and later see the fixture's registration event | PASS for both observed states |
| Settings | Open the settings page | PASS for rendering and tab navigation |
| Evidence | Capture and inspect app screenshots and app-process Logcat | PASS for the captured paths. Screenshots with unrelated notifications are excluded from the published evidence. |

This table records the initial physical pass. The launcher-fix debug APK was subsequently installed with `-r`, and the registered fixture was still present after launch. The final animated APK received its own installation and launch checks below.

| Additional Android check | Status |
| --- | --- |
| First-run onboarding and replay | PASS for opening the first replay page on the Samsung. Full replay and first-run completion were verified by Flutter widget tests. |
| QR camera prompt, scan, and successful QR pairing | NOT TESTED on the Samsung. The app declares the camera permission, and the descriptor/QR validation has automated coverage. |
| Nearby-address consent, port errors, additional text scales and orientations | NOT TESTED on the Samsung. The blank IPv4 error and HTTPS field were confirmed on the physical form. The 200% text-size test passed on the host. |
| Dashboard editing, profile setup, multi-device checks, removal and re-pairing | NOT TESTED on the Samsung. Existing unit and widget checks passed. |

## Defect and fix

**Release blocker.** Android lint rejected the `mipmap/espiot_launcher` alias in `branding.xml` because its target was a `drawable`. The original vector now lives under `mipmap-anydpi`. The alias, adaptive foreground, and legacy splash reference the same moved resource. The change retains the existing vector artwork and adaptive icon.

**Retest.** Both Android variants built after the resource fix. The Samsung accepted the fixed debug APK and opened the app with its saved fixture. The final motion build passed the same release lint and also packaged the animated splash and original vector resources.

## Motion implementation

The requested motion pass keeps the existing Flutter mark painter, Android vector paths, color palette, and navigation. The Android 12+ system splash uses a short scale animation on the original vector. Flutter shows the floating mark and a six-particle painter while preferences load, then proceeds directly to the existing route.

- The Home logo and hero settle after their entrance cycles. The Home panels use short staggered reveals and bottom navigation uses shared transitions.
- Discovery runs the radar only during an active search. Results and notices reveal when the app receives them. Connected and disconnected states follow verified session status.
- Sensor displays transition between incoming readings and reveal the newest section of the trend. The motion dashboard animates reported state and Stop feedback. Stop retains its direct command path.
- Learn & Build uses short project and stage reveals, progress and XP transitions, and wiring and achievement feedback. Technical lesson content is unchanged.
- Decorative loops honor reduced motion and visibility. The implementation uses Flutter animation APIs and Android resources, with no new package dependencies.

The implementation lives in [the shared motion widgets](../app/lib/core/ui/app_motion.dart), [the original mark and animated logo](../app/lib/core/ui/esp_artwork.dart), and [the discovery radar painter](../app/lib/features/discovery/discovery_radar.dart). [Motion widget tests](../app/test/motion_test.dart) cover the timed entrance and offstage and reduced-motion behavior.

## Performance baseline

On the first installed debug build, Android reported 7,675 ms for the cold launch. The app-process log showed skipped-frame messages during startup. A later package-scoped snapshot showed 398,824 KiB total PSS, 461,292 KiB total RSS, and Android frame statistics of 9 janky frames among 100 recorded frames. These are debug-mode observations from one phone. Release timing, a battery run, and long-duration leak testing require separate measurements.

The baseline app-process Logcat capture had 709 lines and contained no matched fatal exceptions, ANRs, Flutter errors, or render overflows. It contained two skipped-frame warnings. The final animated debug APK's first measured cold launch was 6,145 ms. Its 179-line app-process Logcat sample had zero matching fatal exceptions, ANRs, Flutter errors, or render overflows and two skipped-frame warnings. The final build's native window sample reported 6 janky frames out of 36, a 30 ms 90th percentile, 377,724 KiB total PSS, and 435,916 KiB total RSS. These are individual debug snapshots. The native window counter does not establish Flutter animation frame rate or a sustained 60 FPS result.

## Hardware-dependent checks

The host serial enumeration found four generic serial ports and identified no ESP32 board. A board connected only to Wi-Fi still requires a real discovery or connection check from the phone.

| Capability | Implementation audited | Physical validation |
| --- | --- | --- |
| Local Wi-Fi discovery and connection | mDNS and UDP discovery with descriptor verification, manual address entry, and QR pairing | BLOCKED for a positive hardware result. The Samsung completed two searches and the user confirmed no ESP32 was available. |
| Sensor Monitor | Sensor values and session trend on a dashboard driven by a supported descriptor or configured API profile | BLOCKED for physical measurements and disconnect recovery on a real sensor. |
| Serial Monitor | Desktop Arduino IDE walkthrough with per-sketch baud guidance. Native Android USB/OTG serial, baud control, and Wi-Fi serial bridge are absent. | BLOCKED for USB serial output and commands from a physical board. |
| Robot Controller | Motion-capable dashboards display reported motion and an immediate guarded Stop action. The app has no joystick or motion-start controls. | BLOCKED for motor movement, physical Stop, and real robot connection loss. |

### Software fixture on the Samsung

The temporary test endpoint was based on the repository's Phase 3 fixture. It served a unique, labeled mock device on the same Wi-Fi and accepted requests only from the Samsung's address. The phone verified its 13-capability descriptor over HTTP, registered it, displayed a registration event, obtained status, and opened its WebSocket event stream. The registration survived the next `install -r` and app launch. The endpoint had no hardware outputs. The fixture server was stopped and its ports were verified closed. The labeled registration remains on the phone because the USB session ended before cleanup.

| Software fixture check | Status |
| --- | --- |
| Manual HTTP verification, registration, and activity entry | MOCK TESTED on the Samsung |
| Universal dashboard, verified status and WebSocket event connection | MOCK TESTED on the Samsung |
| Real LED, relay, fan, servo, and motion outputs | BLOCKED. No ESP32 was available. |
| Sensor graph, missing and invalid readings, Stop acknowledgement, and loss recovery | NOT TESTED on the Samsung. The fixture dashboard showed its motion state and Stop action. No physical command or successful end-to-end command retest was recorded. |
| HTTPS/WSS, token enrollment, authenticated commands, and revocation | MOCK TESTED using the repository's loopback integration test on the computer. |

## Learn & Build A–E

| Feature | Validation |
| --- | --- |
| Project library and the expanded seven-lesson catalog | PASS for rendering and scrolling on the Samsung |
| Bilingual lesson content, component lists, board pin mapping, and diagrams | PASS in host asset and widget checks. Physical walkthrough interactions remain untested. |
| Sketch viewer, explanation lines, Arduino IDE guide, and export | PASS in the existing Flutter suite. All seven Arduino examples compiled. Android save-picker and clipboard behavior remain untested on this phone. |
| Test checklists, troubleshooting, local learning progress, XP, and achievements | PASS in host tests. Circuit results and unlock animations remain unverified on hardware. |
| Phase E wiring practice | PASS in host interaction and persistence checks. The lessons were not wired on a physical ESP32. |

## Security and permissions

- PASS for rejecting a blank private IPv4 address and showing the local HTTP warning on the Samsung. The HTTPS switch exposed the optional fingerprint field.
- MOCK TESTED for certificate pinning, rejecting an unknown certificate, token authorization, secure storage integration, and revocation on the host fixture.
- Android disables app backup and declares network access and Wi-Fi multicast permissions. Camera access comes from the scanner's merged manifest and is scoped to the QR flow. The physical camera permission flow remains untested.
- Device authentication and secure storage still require a release-device check against actual ESP32 hardware. No credential values or raw app logs are published in this report.

## Final motion APK and release readiness

**PASS for USB installation and cold launch.** USB ADB temporarily lost authorization. The user approved restarting the shared Windows ADB service and requested USB only. Once authorization returned, `adb -s RFCT41K26QX install -r` succeeded. The installed `base.apk` SHA-256 matched the final debug APK in this report. The Samsung then reported a successful cold launch.

| Final build check | Status |
| --- | --- |
| Home logo, light ring, and hero | PASS. Two captures show changes in the logo ring and orbit at different points in the motion cycle. The dashboard and its shortcut remained readable. [First capture](../app/build/phase-9-physical/20-motion-home-early.png) · [Second capture](../app/build/phase-9-physical/21-motion-home-late.png) |
| Discovery radar and settled state | PASS. The beam moved during a real Wi-Fi search, then the screen returned to Search again. [First capture](../app/build/phase-9-physical/22-motion-radar-early.png) · [Second capture](../app/build/phase-9-physical/23-motion-radar-late.png) |
| Device registration after update | PASS. The labeled fixture persisted across the final installation and restart. |
| Native splash frame-by-frame capture, full Learn & Build animation walkthrough, sensor and Stop retests, screen recording | BLOCKED for completion on this phone after ADB disconnected during the fixture retest. The splash resource and motion widgets were verified on the host. |

The [baseline Home](../app/build/phase-9-physical/02-home.png) and [HTTPS form](../app/build/phase-9-physical/09-https-form.png) document the earlier phone run.

**Recommendation.** Keep this as a debug candidate. Release requires completing the remaining Samsung retests, a signed distribution build, and physical ESP32 coverage for discovery, authentication, sensors, reconnection, and Stop. Multi-device operation, long-duration performance, battery impact, and crash recovery remain unverified on the phone.

## Reproduce the checks

From the workspace root:

```powershell
pwsh -NoProfile -File .\protocol\v1\test-descriptor.ps1
pwsh -NoProfile -File .\firmware\tests\test-firmware.ps1 -FlutterContract
pwsh -NoProfile -File .\firmware\tests\test-secure-transport.ps1
pwsh -NoProfile -File .\firmware\tests\test-learn-sketches.ps1
Push-Location .\app
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub
flutter build apk --release --no-pub
Pop-Location
adb -s RFCT41K26QX get-state
adb -s RFCT41K26QX install -r .\app\build\app\outputs\flutter-apk\app-debug.apk
adb -s RFCT41K26QX shell am start -W -n com.example.esp_iot/.MainActivity
```

Use `-OpenSsl` or `-ArduinoCli` with the test scripts when those tools are outside PATH. Android documents `install -r` as a reinstall that retains app data. [Android Debug Bridge reference](https://developer.android.com/tools/adb)
