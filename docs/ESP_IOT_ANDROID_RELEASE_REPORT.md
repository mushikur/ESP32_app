# ESP IoT Android release report

## Release 1.0.1, build 2003

Verified on November 12, 2026. The universal APK and AAB target API 36, support a minimum of API 24, and use the established release certificate for `com.samir.esp_iot`.

| File | SHA-256 |
| --- | --- |
| [Universal APK](../app/build/distribution/ESP-IoT-1.0.1-2003.apk) | `D769E95BC8677BA2088C6FE1C47F6442C4B60B542735FC132CD85896BCAB134D` |
| [Google Play AAB](../app/build/distribution/ESP-IoT-1.0.1-2003.aab) | `C0D64A947BD4862F74022A4C5D40F86D5304D6C6B0DA86FE1E3FAF851C751C03` |

Flutter analysis found zero issues and all 90 tests passed. The tests cover the theme switch, wiring playback, pin selection, quiz choices, command approval across reconnects, and Wi-Fi handling. The signed APK passed signature and ZIP alignment verification. The signed AAB passed signature and bundletool validation. All 28 64-bit library entries across both packages passed 16 KiB ELF alignment checks.

Android refused to install the signed APK over the existing debug-signed `com.samir.esp_iot` on Samsung `RFCT41K26QX`. The installation and its saved data were preserved. The separate `ESP IoT Debug` build with package ID `com.samir.esp_iot.debug` installed and launched on the Samsung. USB disconnected before the new screenshots could be captured. Automatic approval review rejected emulator use for the screenshot task under the physical-phone restriction. The exact production APK remains untested on this Samsung.

Play Console verification, a public privacy policy and support contact, current listing screenshots, and the store's app-content declarations remain open. See the [Google Play submission checklist](GOOGLE_PLAY_SUBMISSION.md).

## Baseline audit

Audit started November 11, 2026, Asia/Dhaka.

The workspace contains the Flutter app, Android bridges, protocol schema and examples, ESP32 firmware, and seven Learn & Build lessons. Existing Phase 9 evidence covers a debug build on the Samsung SM-E236B. The workspace has no Git metadata. The current debug application ID is `com.example.esp_iot`, version `0.1.0+1`. The existing release APK was unsigned.

| Item | Baseline |
| --- | --- |
| Toolchain | Flutter 3.47.5, Dart 3.13.4, Android Gradle Plugin 9.1.0, Gradle 9.3.1, Kotlin 2.4.0, Java/Kotlin target 17, NDK 28.2.13676358 |
| Android SDK | Minimum 24, target 36, compile 36. Flutter 3.47 supports Arm32, Arm64, and x86-64 beginning at API 24. Google Play's current mobile submission target is API 36. [Flutter platform support](https://docs.flutter.dev/reference/supported-platforms) · [Google Play target API](https://developer.android.com/google/play/requirements/target-sdk) |
| App identity | ESP IoT launcher name, adaptive icon and animated Android 12+ splash. The existing placeholder application ID and unsigned release require a distribution identity and certificate decision. |
| Native components | Local Wi-Fi discovery bridge, sketch export bridge, QR camera via Mobile Scanner, secure storage and SQLite plugins. Android declares camera hardware optional. |
| Local state | Preferences store onboarding, learning progress and dashboard layout. SQLite stores device registrations and activity. Secure storage holds connection credentials and tokens. |
| Transport | Local Wi-Fi with mDNS/UDP discovery, explicit profiles for legacy HTTP, HTTP and WebSocket transport, TLS and pairing-token support. The baseline manifest globally allows cleartext and requires a narrower release configuration. |
| Implemented screens | Home, inventory, discovery and QR, device dashboards and settings, activity, settings, onboarding, and Learn & Build. Automations is an empty-state screen. Sensor trends and guarded Stop are dashboard features. Serial Monitor appears in the Arduino IDE walkthrough. |
| Physical availability | ADB initially detected Samsung `RFCT41K26QX` as unauthorized. An Android 16 x86-64 emulator is available. No positive physical ESP32 result has been established. |

## Release priorities

1. Preserve the tested SDK floor and verify ABI coverage and native library alignment in the release artifacts.
2. Limit platform cleartext and preserve the app's explicitly accepted local HTTP profiles. Check newer Android local-network behavior and first-use permissions.
3. Exercise compact, landscape, tablet, and enlarged-text layouts and preserve the existing artwork and motion.
4. Verify debug and release builds, the APK and bundle, device launches, and app-data preservation. Keep physical, emulator, and fixture results distinct.
5. Use owner-approved application ID and signing identity. Prepare privacy, permission, and distribution guidance before any publication.

The current Play submission requirements include 16 KB page support on applicable 64-bit devices. A static artifact inspection checks alignment, and a compatible emulator can establish a runtime result. [Android 16 KB compatibility](https://developer.android.com/guide/practices/page-sizes)
