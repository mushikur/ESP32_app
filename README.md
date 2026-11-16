# ESP IoT

ESP IoT pairs an Android app with a reusable firmware library to discover and control compatible ESP32 projects over local Wi-Fi. Phase 8 defines a transport interface and MQTT design for future remote access.

- [Premium visual, motion and learning enhancement report](docs/ESP_IOT_PREMIUM_ENHANCEMENT_REPORT.md)
- [Google Play submission checklist](docs/GOOGLE_PLAY_SUBMISSION.md)
- [Historical Android 1.0.0 release report](docs/ESP_IOT_FINAL_RELEASE_REPORT.md)
- [Installation guide for sharing the APK](docs/ESP_IOT_INSTALL_GUIDE.md)
- [Phase 9 build, automated tests, and physical Android testing report](docs/ESP_IOT_PHASE_9_TEST_REPORT.md)
- [Phase 8 transport interface, MQTT design, and verification](docs/phase-8.md)
- [Learn & Build Phase E wiring practice and expanded lessons](docs/learn-phase-e.md)
- [Learn & Build Phase D tests, troubleshooting, and rewards](docs/learn-phase-d.md)
- [Learn & Build Phase C sketch downloads, code explanations, and IDE walkthrough](docs/learn-phase-c.md)
- [Learn & Build Phase B wiring lab, pin explorer, and verification](docs/learn-phase-b.md)
- [Learn & Build Phase A lessons, setup, and validation](docs/learn-phase-a.md)
- [Phase 7 secure pairing, setup, and verification](docs/phase-7.md)
- [Phase 6 firmware library, ESP32 examples, and verification](docs/phase-6.md)
- [Phase 5 device management, migration, and history](docs/phase-5.md)
- [Phase 4 dashboards, legacy mappings, and verification](docs/phase-4.md)
- [Phase 3 connection setup, profiles, and verification](docs/phase-3.md)
- [Phase 2 discovery, setup, and verification](docs/phase-2.md)
- [Phase 1 interface and verification](docs/phase-1.md)
- [Architecture, setup, and test plan](docs/phase-0.md)
- [Universal device protocol v1 draft](docs/protocol-v1.md)
- [Example device descriptor](protocol/v1/examples/bench-controller.json)

Use PowerShell 7.5 or newer to check the descriptor draft from the workspace root.

```powershell
pwsh -NoProfile -File .\protocol\v1\test-descriptor.ps1
```

Run the Android app checks from `app/`.

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```
