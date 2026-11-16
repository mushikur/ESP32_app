# ESP IoT final release report

This report records the original 1.0.0 release. See the [current install guide](ESP_IOT_INSTALL_GUIDE.md) and [Google Play checklist](GOOGLE_PLAY_SUBMISSION.md) for the latest candidate.

Report date — 12 November 2026, Asia/Dhaka. Build host — Windows 11, Flutter 3.47.5, Dart 3.13.4, AGP 9.1.0, Gradle 9.3.1, Kotlin 2.4.0, Android Build Tools 36.0.0, JDK 17 (Android Studio JBR).

**Status legend.** PASS = executed and passed. FAIL = executed and failed. BLOCKED = required device or access unavailable. NOT TESTED = not executed. MOCK TESTED = simulation or fixture only.

> **Headline.** The release APKs and the App Bundle build, are signed with a newly created production key, and install and run correctly on the physical Samsung SM-E236B (Android 14) and on an Android 16 emulator. No critical security defect was found. **No ESP32 hardware was available**, so device control, pairing and reconnection are fixture-tested only. Android 7.0–13 and 15 are **NOT TESTED**.

---

## 1. Project audit

### 1.1 What was inspected

Flutter and Dart versions, Gradle and AGP configuration, the source and merged Android manifests, Gradle and Pub dependency sets, Kotlin/Java compatibility, min/target/compile SDK, the two native plugin bridges, permissions, signing configuration, assets and fonts, SQLite and secure storage, the LAN transport layer, device discovery, and all seven workspace modules plus Learn & Build.

### 1.2 Defects found and fixed

| # | Severity | Issue | Root cause | Fix | Verified |
| --- | --- | --- | --- | --- | --- |
| 1 | **Critical** | Release builds produced a different package (`com.samir.esp_iot`) from debug and from the installed app (`com.example.esp_iot`). | `androidComponents.onVariants` rewrote `applicationId` for release only. | Unified on `com.samir.esp_iot` for every build type; `namespace` and the Kotlin source package moved to match; the variant override removed. | PASS — `aapt2 dump badging` reports `com.samir.esp_iot` on all artifacts |
| 2 | **Critical** | `com.example.*` is permanently rejected by Google Play. | Flutter template default never changed. | Same fix as #1. | PASS |
| 3 | **High** | No launcher icon for Android 7.0–7.1. `@mipmap/espiot_launcher` existed only as `mipmap-anydpi-v26` plus a `values/` alias to a VectorDrawable, which API 24–25 launchers cannot rasterize. | The earlier `lintVitalRelease` `ReferenceType` failure was worked around with a resource alias rather than real raster assets. | Generated true PNG launcher icons at all five densities from the brand vector, removed the alias, added `roundIcon`, added a `<monochrome>` layer for Android 13+ themed icons. | PASS — resource table lists mdpi–xxxhdpi PNGs plus anydpi‑v26 for both icons |
| 4 | **High** | No code or resource shrinking; release APK 75.8 MB with a full un-obfuscated dex. | `isMinifyEnabled` never enabled; no ProGuard rules file. | Enabled R8 + `shrinkResources` with a hand-written `proguard-rules.pro` covering Flutter embedding, the app's channel bridges, package:jni, ML Kit, CameraX, sqflite and Tink. | PASS — `classes.dex` is 2.1 MB in the shipped APK; no runtime `ClassNotFoundException` |
| 5 | **High** | No production signing key existed; release artifacts were unsigned and therefore not installable. | Never created. | Created a 4096-bit RSA key (SHA384withRSA, 30-year validity) outside the repository; wired signing through a gitignored `android/key.properties` with an environment-variable fallback. | PASS — `apksigner` verifies v2 and v3 |
| 6 | Medium | `flutter analyze` reported an unnecessary import, contradicting the Phase 9 "zero issues" claim. | Drift after that report. | Removed the redundant import. | PASS — analyze clean |
| 7 | Medium | R8 build failed on missing Play Core classes. | Flutter's deferred-components manager compiles against Play Core, which this app does not bundle. | Added `-dontwarn com.google.android.play.core.**`. | PASS |
| 8 | Low | Release dex carried the dependency metadata blob. | AGP default. | `dependenciesInfo { includeInApk = false }`; kept in the bundle for Play. | PASS |
| 9 | Low | `android.util.Log` v/d/i calls could reach logcat in release. | No stripping configured. | `-assumenosideeffects` strips them from release builds. | PASS |

### 1.3 Defects found and **not** fixed

| Severity | Issue | Why it is open |
| --- | --- | --- |
| Low | `sqflite_common_ffi` is pinned at 2.4.6; 2.4.7 is available. | Development-only dependency used by the host test suite; pinned deliberately to match `sqflite`. No release impact. |
| Low | Build warns that `cupertino_icons` glyphs are referenced without the font being bundled. | Cosmetic; no Cupertino icon is used in any rendered screen tested. Would only matter if a Cupertino icon is added later. |
| Informational | Automations tab is an empty state. | Unimplemented by design; phases beyond 8 were never specified. |
| Informational | Phase 8 remote/MQTT access is a design document and a transport interface only. | No remote implementation exists, so none was tested or shipped. |

### 1.4 Pre-existing strengths confirmed

The LAN transport rejects proxies, redirects, URL user-info and any peer whose host, port or scheme differs from the registered endpoint, and re-verifies the Wi-Fi link identity before and after each exchange and every 4 s during a WebSocket session. Credential headers are refused over plaintext HTTP. Descriptor parsing is bounded at 32 KiB with duplicate-key and nesting-depth rejection before decode. Only private IPv4 ranges are accepted. These were reviewed, not changed.

---

## 2. Supported Android versions

| Setting | Value | Justification |
| --- | --- | --- |
| `minSdkVersion` | **24** (Android 7.0) | Set by the strictest plugin requirements: `flutter_secure_storage` 11.2.0 and `shared_preferences_android` 2.5.4 both require 24. It was **not** lowered to inflate compatibility. |
| `targetSdkVersion` | **36** (Android 16) | Meets the current Play target-API requirement. |
| `compileSdkVersion` | **36** | Matches `mobile_scanner` 7.5.0, which compiles against 36. |

### Version-specific behavior

| Android | Expected behavior |
| --- | --- |
| 7.0–7.1 (24–25) | Supported. Uses the new raster launcher icons (the adaptive icon is v26-only). Network Security Config enforces the HTTPS default. |
| 8.0–12L (26–32) | Supported. Adaptive launcher icon. Camera permission requested on scanner use. |
| 13–15 (33–35) | Supported. Themed (monochrome) launcher icon now available. |
| 16 (36) | Supported and the only version actually exercised. Android 16's local-network restriction is opt-in and this app does not opt in. |
| 17 (37) and later | **Not yet addressed.** Raising `targetSdk` to 37 will require handling Android's runtime Local Network permission for manual addresses and the app's discovery sockets. |

**Limitation:** `minSdk 24` cannot be lowered without dropping encrypted credential storage. Android 6 and earlier cannot be supported.

---

## 3. Compatibility limitations

- The app requires a **Wi-Fi network that Android has selected as the default route**. It deliberately refuses to talk to devices over mobile data or a VPN-routed default link.
- Only **private IPv4** device addresses are accepted (10/8, 172.16/12, 192.168/16). IPv6 and public addresses are rejected by design.
- QR scanning requires a working camera and bundles Google ML Kit. On a device without a camera the scanner is unavailable; manual address entry remains.
- Device control requires firmware that speaks the **ESP IoT v1 protocol**, or a legacy device for which the user supplies an explicit REST/WebSocket API profile. An arbitrary ESP32 web page cannot be controlled automatically.
- One physical phone was tested, a Samsung SM-E236B. Xiaomi, Redmi, POCO, Realme, OPPO, Vivo, OnePlus, Pixel and Motorola devices were **NOT TESTED** — none was available — so no claim is made for them.

---

## 4. Tested device models

| Device | Type | Android | Result |
| --- | --- | --- | --- |
| Samsung SM-E236B (`RFCT41K26QX`) | Physical, arm64-v8a, 1080×2408 @ 450 dpi (384 dp) | 14 (API 34) | PASS — see §6. ADB was `unauthorized` for most of the session and was authorized near the end. |
| `sdk_gphone64_x86_64` (`emulator-5554`) | Emulator | 16 (API 36), x86-64 | PASS — see §6 |

No other physical device was available. No Xiaomi, OPPO, Vivo, OnePlus, Pixel, Motorola or tablet hardware was tested.

---

## 5. Emulator test matrix

Only one Android system image is installed on this PC (`android-36.1`), so older-API emulators could not be created without a large SDK download that was not performed.

| Configuration | Width | Font scale | Result |
| --- | --- | --- | --- |
| API 36, 720×1280, 320 dpi (360 dp) portrait | 360 dp | 1.0 | PASS — all seven tabs render, no overflow |
| API 36, same, font scale 1.5 | 360 dp | 1.5 | PASS — nav bar reflows to two rows, hero art drops out, no overflow |
| API 36, same, font scale 2.0 | 360 dp | 2.0 | PASS — no overflow across Home, Devices, Learn, Automations, Settings |
| API 36, density 360 (320 dp wide) | 320 dp | 1.0 | PASS — no overflow |
| API 36, landscape 1280×720 | 640 dp | 1.0 | PASS — no overflow, nav bar single row |
| API 24–35, any density | — | — | **NOT TESTED** — no system image installed |
| Foldable / tablet form factors | — | — | **NOT TESTED** — no such AVD or hardware |

Overflow was measured by clearing logcat and counting `RenderFlex`/`overflowed by` lines after each configuration change. Every configuration returned **zero**.

---

## 6. Physical phone test results

Samsung SM-E236B, Android 14, owner profile (user 0). Artifact under test: `esp-iot-1.0.0-arm64-v8a.apk` (release, R8-shrunk, production-signed). Input was driven over ADB; the phone was also being handled by its owner during the run.

| Check | Result |
| --- | --- |
| Install (`adb install -r --user 0`) | PASS |
| Cold launch | PASS — 1,182 ms first launch, 997 ms and 937 ms on later cold starts (`am start -W` TotalTime) |
| Onboarding renders and can be skipped | PASS |
| All seven tabs render (Home, Devices, Discover, Learn, Automate, Activity, Settings) | PASS — zero `RenderFlex` overflow lines, zero fatal exceptions in logcat |
| Wi-Fi detection through the native bridge | PASS — Home and Discover showed the phone's private address and /24 prefix |
| Automatic discovery on a real Wi-Fi network | PASS for execution and the empty state ("No ESP IoT devices found"). No ESP32 was present, so nothing could be found |
| Camera permission flow | PASS — in-app rationale screen first, then the Android prompt; permission recorded as granted |
| QR scanner | PASS for camera start and decoder load — the back camera reached `CAMERA_STATE_ACTIVE` and ML Kit logged its barcode decoder as created. **Decoding an actual pairing QR was NOT TESTED** |
| Learn & Build catalog and a project page (Blink an LED) | PASS |
| Force-stop and cold restart | PASS — returned to Home, onboarding stayed completed |
| Update over the existing install | PASS — same-key reinstall succeeded; saved state and the camera permission were kept |
| Memory after navigating all tabs and the scanner | 169.6 MB total PSS (one sample) |
| Launcher icon and label on One UI | **NOT TESTED** — not visually inspected |
| Manual address entry, keyboard behavior | **NOT TESTED** |
| Font scaling, display scaling, landscape on the phone | **NOT TESTED** on the phone (emulator only, §5) |
| TalkBack | **NOT TESTED** |
| Sketch export through the system file picker | **NOT TESTED** |
| Uninstall behavior | **NOT TESTED** — nothing was uninstalled |
| Device pairing, control, reconnection | **BLOCKED** — no ESP32 |

**Unexplained observation.** In one of three scanner runs the app was back on Discover about six seconds after the camera opened, with no error in logcat. The phone was being handled at the time, so a back gesture is the likely cause, but this was not confirmed. Worth watching for when you test the scanner yourself.

**The old build is still installed.** `com.example.esp_iot` remains on the phone next to the new `com.samir.esp_iot`; it was left untouched.

---

## 7. UI and responsive layout results

| Check | Result |
| --- | --- |
| All seven tabs render | PASS on the Samsung (Android 14) and on the API 36 emulator |
| Text overflow at 1.0×, 1.5×, 2.0× font scale | PASS — zero `RenderFlex` overflows |
| Bottom navigation at 320 dp and at 2.0× scale | PASS — reflows to two rows rather than clipping |
| Landscape orientation | PASS — no orientation lock; layout adapts |
| Safe areas, status bar, gesture bar | PASS — `SafeArea` applied on every screen inspected; no content under the gesture bar in any screenshot |
| Tablet / wide-screen behavior | Content is capped at 720 dp and centered (`ScreenScroll`). Correct by inspection; **NOT TESTED** on a real tablet |
| Notches and camera cutouts | PASS on the Samsung's punch-hole display in portrait — no content under the status bar or gesture bar in any capture. Landscape with a cutout **NOT TESTED** |
| Reduced motion | Implemented throughout (routing transitions and decorative loops honor `disableAnimations`); covered by the host widget tests, **NOT TESTED** on a device |
| Screen-reader output | **NOT TESTED** — TalkBack was not exercised. `Semantics(header: true)` and semantic labels are present in source |
| Keyboard appearance | **NOT TESTED** — no text-entry screen was driven on the emulator |

No redesign was performed. The existing premium animated identity is intact — the launch logo, particle field, orbital device artwork and motion reveals all render in the release build.

---

## 8. Network and ESP32 results

| Check | Result |
| --- | --- |
| Release manifest enforces HTTPS default | PASS — `usesCleartextTraffic="false"` and `networkSecurityConfig` both present in the shipped APK's binary manifest |
| Android network security not globally disabled | PASS — base config permits no cleartext; legacy HTTP is gated per-connection in Dart, not by a manifest opt-out |
| Wi-Fi link detection on a real network | PASS on the Samsung |
| Local Wi-Fi connection to a real ESP32 | **BLOCKED** — no ESP32 hardware available |
| Manual IP connection | **NOT TESTED** on device |
| QR pairing | Scanner start PASS on the Samsung; decoding a pairing code and completing pairing **NOT TESTED** |
| Automatic discovery (mDNS/UDP) | Ran to completion on the Samsung with the correct empty state; finding a device **BLOCKED** — no ESP32. Subnet check **NOT TESTED** |
| HTTP REST and WebSocket transport | **MOCK TESTED** — host fixtures in the existing suite |
| Device authentication, pairing, revocation | **MOCK TESTED** — HTTPS/WSS loopback fixture |
| Reconnection, network switching, offline LAN | **MOCK TESTED** — host tests only |
| Multiple connected devices | **NOT TESTED** |

No claim is made that any particular existing ESP32 web interface integrates automatically. Devices must implement ESP IoT v1 or be given an explicit API profile.

---

## 9. Security audit

| Area | Finding |
| --- | --- |
| Hardcoded credentials | **PASS** — a pattern scan of the shipped APK (dex, assets, resources) for private keys, Google API keys and common token formats returned zero hits |
| Signing key handling | **PASS** — key stored at `C:\Users\USER\.android-keys\esp_iot-release.jks`, outside the project tree; `android/key.properties` holds the passwords and is matched by `android/.gitignore` lines 12–14. No password appears in this report, in any build log, or in any project file |
| TLS verification | **PASS** — never disabled. Ordinary HTTPS uses platform validation; an optional user-supplied SHA-256 pin is checked against the exact peer certificate and its validity window on every connection |
| Credentials over plaintext | **PASS** — `Authorization`, `Cookie` and `X-API-Key` are refused unless the endpoint is HTTPS/WSS |
| Secure storage | **PASS** — API credentials and pairing tokens use `flutter_secure_storage` (Android Keystore-wrapped); tokens are bound to deviceId + origin + certificate fingerprint and are rejected if the device moves |
| Local database | SQLite is app-private and unencrypted; it holds endpoint addresses, board IDs and activity times, not credentials. Excluded from cloud backup and device transfer. Acceptable, and documented in the privacy policy |
| QR pairing data | **PASS** — carries endpoint and identity plus an optional pin, never a credential; the endpoint is shown to the user before pairing |
| Input validation | **PASS** — strict JSON decode rejects duplicate keys, depth > 12 and non-finite numbers before parsing; descriptors bounded at 32 KiB; labels filtered for control characters and bidirectional overrides; endpoint paths reject URLs, queries and dot segments |
| Debug logging | **PASS** — release builds strip `Log.v/d/i`; the app's own messages are user-facing and redact credential-like keys |
| Release flags | **PASS** — no `debuggable`, no `testOnly`, `allowBackup="false"` in the shipped manifest |
| Unnecessary data collection | **PASS** — no account, analytics, ad or crash-upload backend. Three install-time permissions plus camera on demand |

**Residual risk to disclose:** `mobile_scanner` bundles Google ML Kit, whose initialization provider and Google DataTransport services appear in the merged manifest. Google documents on-device scan processing with separate diagnostic/usage metrics. This must be declared in Play Data safety.

No critical security issue remains unresolved.

---

## 10. Performance observations

| Metric | Observation |
| --- | --- |
| Cold start, Samsung SM-E236B | **1.18 s** first launch; 1.00 s and 0.94 s on later cold starts |
| Memory, Samsung SM-E236B | 169.6 MB total PSS after visiting every tab and the scanner (single sample) |
| Cold start, API 36 x86-64 emulator | First launch after install 14.6 s to "Fully drawn"; subsequent cold start **7.2 s**. Emulator figures on a build-loaded host — not representative of a physical phone |
| Release dex size | 2.1 MB after R8 (down from an un-shrunk build) |
| Native code | 23.7 MB per ABI: `libflutter.so` 11.2 MB, `libapp.so` 7.6 MB, ML Kit `libbarhopper_v3.so` 4.7 MB |
| Repeated navigation | No leak or slowdown observed across ~15 tab switches; no crash |
| CPU, battery, frame timing | **NOT TESTED** — `dumpsys gfxinfo` does not see Flutter's own render surface, and no profiling build was run |
| Long-running connections, sensor graph updates | **NOT TESTED** — requires an ESP32 |

Existing design choices that bound cost were confirmed by inspection: sensor history is capped at 60 samples per control, activity history at 300 rows, reconnect uses exponential backoff with jitter to 30 s, and decorative animations stop when offstage or when reduced motion is on.

---

## 11–12. Bugs found and fixed

Nine defects found; **seven fixed**, two deliberately left (§1.3). No feature and no test was removed. Full detail in §1.2. Automated verification after all changes:

| Check | Result |
| --- | --- |
| `flutter analyze` | **PASS** — no issues found |
| `flutter test` | **PASS** — 71/71 tests |
| Debug APK build | PASS (built earlier in the session) |
| Release APK build | PASS |
| Split-per-ABI release build | PASS |
| App Bundle build | PASS |
| `apksigner verify` | PASS — v2 + v3 |
| Install and launch on API 36 emulator | PASS |
| Install, launch, tabs, discovery, scanner, restart and update on the Samsung SM-E236B | PASS — §6 |
| Cold restart — saved state preserved | PASS — onboarding stayed completed |
| Update over an existing install (`install -r`) | PASS — installed without a signature error, relaunched to Home with saved state intact |
| Android 12+ splash screen | PASS — brand mark renders from `windowSplashScreenAnimatedIcon` |

---

## 13. Remaining blockers

1. **No ESP32 hardware.** All protocol, pairing and TLS evidence is fixture-based. Hardware compatibility is unproven.
2. **One physical phone, one Android version.** Only the Samsung on Android 14 and an Android 16 emulator were exercised. Android 7–13 and 15, and every other manufacturer, are untested.
3. **Gaps on the phone itself** — QR decode, manual address entry, keyboard, TalkBack, launcher icon appearance and sketch export were not exercised (§6).
4. **Play Console assets absent** — screenshots, feature graphic and a hosted privacy-policy URL are still required (§18).

---

## 14. Release artifacts

All four are signed with the same production key. Certificate SHA-256: `EB:61:68:B8:FC:0A:BC:08:D5:42:EB:5A:E5:5C:14:AC:3D:B8:38:01:FE:E4:5E:F8:03:C7:67:0B:EC:78:52:FF`

| Artifact | Version | versionCode | Bytes | SHA-256 |
| --- | --- | ---: | ---: | --- |
| `app/dist/esp-iot-1.0.0-universal.apk` | 1.0.0 | 1 | 76,727,857 | `58423a2afee5ef940e712c89bf3a561516c15b1d55218be66917a11af265c401` |
| `app/dist/esp-iot-1.0.0-arm64-v8a.apk` | 1.0.0 | 2001 | 28,507,422 | `0a934dbe9f2a3221d2b6e5b321660e7bdc4845020e5662b6da31e081af307694` |
| `app/dist/esp-iot-1.0.0-armeabi-v7a.apk` | 1.0.0 | 1001 | 24,377,234 | `3b90f7c98e593e452b13a8c33d41797c19ad6568f5c091e4544ecd75136774bd` |
| `app/dist/esp-iot-1.0.0.aab` | 1.0.0 | 1 | 68,667,599 | `3f29f60144b18c89c4a452da77c919eed0fc3d89909d1cff35d2ddcf963e241a` |

Gradle's own outputs remain at `app/build/app/outputs/flutter-apk/` and `app/build/app/outputs/bundle/release/`.

The original per-ABI APKs carry higher version codes than the original universal APK. Use the [current signed universal APK](ESP_IOT_INSTALL_GUIDE.md#install) to update from those builds while retaining app data.

**Version note.** The version was moved from `0.1.0+2` to **`1.0.0+1`** for this release. Because the package identifier also changed, there is no upgrade path from any previously installed build — see §16.

---

## 15. AAB build details

`app/dist/esp-iot-1.0.0.aab`, 68,667,599 bytes, versionCode 1, signed with the production key. Google Play will re-sign it under Play App Signing and generate per-device splits, so the download a user receives will be far smaller than the bundle. The dependency metadata blob is included in the bundle (and excluded from the shared APKs) as Play expects.

---

## 16. Signing status

**Signed with a newly created production key.** No pre-existing key was found anywhere on this PC (only Android's `debug.keystore`), and none was overwritten.

| Property | Value |
| --- | --- |
| Keystore | `C:\Users\USER\.android-keys\esp_iot-release.jks` |
| Format / algorithm | PKCS#12, RSA 4096-bit, SHA384withRSA |
| Alias | `espiot` |
| Validity | 30 years from 11 November 2026 |
| Credentials | `app/android/key.properties` (gitignored); `ESP_IOT_RELEASE_*` environment variables also supported |

### Back up this key now

Losing it means you can never publish an update that existing users can install — they would have to uninstall and lose their data, and Play would reject the upload outright.

1. Copy **both** `esp_iot-release.jks` and `app/android/key.properties` (the passwords live in it) to at least two places you control — an encrypted archive on an external drive and a password manager's secure-file store are a good pair.
2. Never commit either file. `app/android/.gitignore` already excludes `key.properties`, `*.jks` and `*.keystore`.
3. Never paste the passwords into chat, an issue tracker or a build log.
4. If you publish to Play and want to update the original sideloaded release in place, follow the [Play App Signing instructions](GOOGLE_PLAY_SUBMISSION.md#1-prepare-the-bundle-and-signing) to use this production key as the app-signing key. A separate upload key can be registered for later bundles.

### ⚠️ Existing installs will not upgrade

The earlier debug build uses `com.example.esp_iot`. These release artifacts use `com.samir.esp_iot`. Android installs them separately and keeps each app's registered devices, pairing tokens and learning progress in its own storage.

---

## 17. Installation instructions

See [ESP_IOT_INSTALL_GUIDE.md](ESP_IOT_INSTALL_GUIDE.md) for the version to hand to friends.

---

## 18. Google Play readiness

| Requirement | Status |
| --- | --- |
| Unique package identifier | **READY** — `com.samir.esp_iot`; confirm it is unused on Play before your first upload |
| Target API level | **READY** — 36 |
| App signing | **READY** — AAB signed; enrol in Play App Signing at upload |
| Android App Bundle | **READY** — builds and is signed |
| App icon (512×512 PNG) | **NOT DONE** — must be exported; the source vector exists |
| Feature graphic (1024×500) | **NOT DONE** |
| Screenshots (2–8 phone) | **NOT DONE** — working captures from this session were not kept as store assets; take clean ones on the phone with notifications cleared |
| Privacy policy URL | **NOT DONE** — [PRIVACY_POLICY_DRAFT.md](PRIVACY_POLICY_DRAFT.md) exists but must be hosted at a public URL |
| Data safety declaration | **DRAFT** — see [the privacy audit](ESP_IOT_RELEASE_PRIVACY_AUDIT.md). Must disclose ML Kit's diagnostic/usage metrics |
| Permission justifications | **READY** — camera (QR pairing), internet/network state, Wi-Fi multicast (discovery); all documented in the privacy audit |
| Content rating questionnaire | **NOT DONE** — complete in Play Console |
| Store listing text | **DRAFT** — below |
| Testing track | **NOT READY** — a closed test is strongly advised before production, given §13 |

### Draft store listing

**Title:** ESP IoT — Control & Learn

**Short description (≤80):** Control your ESP32 projects over local Wi-Fi and learn electronics.

**Full description:**

> ESP IoT turns your phone into a control panel for the ESP32 boards you build yourself — no account, no cloud, no subscription. Everything happens on your own Wi-Fi.
>
> **Find and control your boards.** Discover compatible devices automatically over your local network, scan a pairing QR, or type an address by hand. Switches, sliders, sensor readings and motion controls appear from the device's own description, so a board you flashed this morning is usable this afternoon.
>
> **Built for real projects.** Save devices with names and rooms, arrange a dashboard per board, watch live sensor history, and review connection activity. Legacy projects with their own REST or WebSocket API work too, through explicit connection profiles you control.
>
> **Learn & Build.** Seven guided electronics projects, in English and Bengali — wiring diagrams you can zoom, an interactive pin explorer, annotated Arduino sketches you can export, upload walkthroughs and troubleshooting, with progress and achievements as you go.
>
> **Private by design.** No account. No analytics backend. Device addresses and learning progress stay on your phone; API credentials and pairing tokens are stored encrypted. Authentication is never sent over an unencrypted connection, and certificate pinning is available for your own device certificates.
>
> Requires an ESP32 running the ESP IoT firmware library, or any local device you can describe with a connection profile. Android 7.0 or newer.

**Category:** Tools. **Content rating:** expected Everyone — no user-generated content, ads or purchases.

---

## 19. Final release recommendation

**Ready to share privately with friends as a first release. Not ready for Google Play production.**

What is established: the app builds, shrinks, signs and installs; on the physical Samsung it cold-starts in about a second, renders every tab, detects Wi-Fi, runs discovery, opens the camera scanner and keeps its data across a restart and an update. On the emulator it survives 2× font scaling, a 320 dp screen and landscape without a layout overflow. It carries no secret, no debug flag and no disabled TLS check, and 71 automated tests plus a clean analyzer back the code.

What is not: **no ESP32 was connected at any point.** Discovering, pairing with and controlling real hardware — the app's main purpose — has only been verified against software fixtures. Only one phone model was tested.

Recommended order:

1. Flash an ESP32 with the bundled firmware library and verify discovery, QR pairing, control and reconnection end to end on the Samsung.
2. Share the APK with two or three friends on different brands and Android versions, and collect what they see.
3. Then complete the Play assets in §18 and start a closed test.

Do not describe the app as supporting every Android phone. The honest claim today is: **builds for Android 7.0+, verified on one Samsung phone running Android 14 and on an Android 16 emulator, real-ESP32 verification pending.**
