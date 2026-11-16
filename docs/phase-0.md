# ESP IoT Phase 0 architecture

ESP IoT is an Android-first, local-first Flutter app. A device can be added without an account or internet service. Universal firmware exposes a versioned contract. Existing projects use individually verified mappings, so the same dashboard can work with both types of device.

## Workspace and tools

The starting workspace was empty, including hidden entries, with no Git repository or existing app or firmware to preserve. `flutter doctor -v` found Flutter stable 3.47.5, Dart 3.13.4, Android Studio with Java 25, and a working Android toolchain with accepted licenses. It reported platform `android-37.0` and Build Tools `36.0.0`. No Android phone or running Android emulator was listed. Windows desktop tooling is outside the Android target. Arduino CLI, PlatformIO, and `idf.py` were absent from the shell path.

The starter inherits Flutter's minimum Android API 24 and compile and target API 36. `com.example.esp_iot` is a temporary application ID for development. The Phase 0 screen is a launch smoke target. The product design starts in Phase 1.

On a new machine, install Flutter stable and Android Studio, then use SDK Manager to install the SDK platform required by the Flutter project, Platform-Tools, Build-Tools, and Command-line Tools. Install an emulator image or connect an Android phone with USB debugging. Run the license command if Doctor reports pending licenses. [Flutter Android setup](https://docs.flutter.dev/platform-integration/android/setup)

```powershell
flutter --version
flutter doctor -v
flutter doctor --android-licenses
flutter devices
Set-Location .\app
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter run -d <android-device-id>
```

Before firmware work, install Arduino IDE with Espressif's `esp32` board package or use Arduino CLI. The SDK should expose a small C++ capability and command core with an Arduino networking adapter first. Keep network and storage interfaces separable so an ESP-IDF adapter can use the same contract and fixtures. [Arduino-ESP32 installation](https://docs.espressif.com/projects/arduino-esp32/en/latest/installing.html)

```powershell
arduino-cli core update-index --additional-urls https://espressif.github.io/arduino-esp32/package_esp32_index.json
arduino-cli core install esp32:esp32 --additional-urls https://espressif.github.io/arduino-esp32/package_esp32_index.json
arduino-cli board list
```

## Repository layout

This is the target tree. Add directories in their owning phase. Keep a single Flutter package until a second consumer needs shared Dart code.

```text
ESP loT app/
  app/
    android/                           Android runner, permissions and NSD bridge
    assets/
      branding/                        Logo and app icon sources
      illustrations/                   Lightweight device art
    lib/
      main.dart                        Composition entry point
      app/                             App shell, theme, routes, providers
      core/
        devices/                       Domain models and repository interfaces
        protocol/                      Universal wire types and validation
        transport/                     Local transport interfaces and adapters
        storage/                       SQLite and credential adapters
        ui/                            Shared accessible design components
      features/
        onboarding/
        home/
        devices/
        discovery/
        integrations/                  REST, WebSocket and manual profiles
        dashboard/                     Capability renderer and layout editor
        automations/
        activity/
        settings/
    test/                              Dart unit and Flutter widget tests
    integration_test/                  Android end-to-end tests
    pubspec.yaml
    pubspec.lock
  protocol/
    v1/
      device.schema.json               Descriptor schema
      examples/                        Shared test fixtures
      test-descriptor.ps1              Structural schema checks
  firmware/
    EspIoT/                            Arduino library with portable core
    examples/                          LED, relay, sensor and guarded motion
    esp_idf/                           Adapter when validated on hardware
  docs/
    phase-0.md
    protocol-v1.md
```

## App boundaries and dependencies

Widgets render immutable state and call Riverpod controllers. Controllers coordinate discovery, repositories, and per-device sessions. A `DeviceAdapter` normalizes universal or legacy device behavior into capabilities, observations, and command outcomes. A local transport manages byte-level HTTP and WebSocket IO, and a connection manager owns timeouts, stale status, and network changes. Keep adapter parsing and command validation independently testable in Dart.

| Phase | Dependencies | Role |
| --- | --- | --- |
| 0–1 | [Flutter Material 3](https://api.flutter.dev/flutter/material/ThemeData/useMaterial3.html), [flutter_riverpod](https://pub.dev/packages/flutter_riverpod), [go_router](https://pub.dev/packages/go_router) | App shell and state. Flutter animation primitives and `CustomPainter` are sufficient for the initial design. |
| 2 | Kotlin `NsdManager`, `dart:io`, [mobile_scanner](https://pub.dev/packages/mobile_scanner), [pretty_qr_code](https://pub.dev/packages/pretty_qr_code) | Android mDNS, UDP, QR scanning and generation. Use an offline-capable scanner configuration. Verify generated codes round-trip through the scanner. |
| 3 | [dio](https://pub.dev/packages/dio), [web_socket_channel](https://pub.dev/packages/web_socket_channel) | Bounded HTTP requests and WebSocket framing. Keep authentication, TLS policy, cancellation, and connection state in app-owned code. |
| 5 | [sqflite](https://pub.dev/packages/sqflite), [shared_preferences](https://pub.dev/packages/shared_preferences), [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) | Transactional device, profile, layout and history data. Preferences hold UI settings. Secure storage holds only credentials referenced by opaque IDs in SQLite. |
| Tests | Flutter SDK `flutter_test` and `integration_test`, `flutter_lints` | Unit, widget, Android integration, and static checks. |

Add packages from `app/` when their phase needs them. Use stable compatible versions and commit the resolved app lockfile once the project is placed under version control.

```powershell
flutter pub add flutter_riverpod go_router
flutter pub add mobile_scanner pretty_qr_code
flutter pub add dio web_socket_channel
flutter pub add sqflite shared_preferences flutter_secure_storage
```

Phase 1 establishes the Material 3 design system, onboarding, and six-section shell. Home will have honest empty states. Automations and Activity can have navigation and empty states until they have real data and behavior. Use reduced-motion preferences, legible contrast, screen-reader labels, and lightweight animations.

## Local discovery and connection

1. Start a bounded search when Discover opens on Wi-Fi. Browse `_espiot._tcp` using `NsdManager` on the active network. TXT metadata is a display hint. Resolve candidates, then validate the universal descriptor.
2. In parallel, send the ESP IoT UDP discovery query on the current Wi-Fi IPv4 link. Accept bounded replies to the current query only and use their source address as the candidate. See the [protocol draft](protocol-v1.md) for the proposed message contract.
3. Deduplicate universal candidates by validated device ID and trust binding. Never merge conflicting identities. For legacy devices use the selected origin and profile, and require review if an address or identity changes.
4. Offer QR or manual host and port entry when multicast or broadcast is blocked. Show the parsed destination before connecting. For optional subnet search, require consent per run and limit the scope to the active directly connected Wi-Fi IPv4 prefix. Start with a ceiling of 32 candidates, two concurrent requests, four starts per second, a ten-second deadline, and a single documented descriptor probe on the configured port. No port sweep, arbitrary CIDR, or background scanning.
5. Cancel discovery and stale requests on page exit or network change. Expect guest Wi-Fi isolation, filtered multicast, and DHCP address changes. Pause periodic work in the background and revalidate when the app returns.

Use `INTERNET` and the network state permissions appropriate to the Android APIs used. Request camera permission at QR scan time. Android 17 apps targeting SDK 37 or higher need the runtime `ACCESS_LOCAL_NETWORK` permission for broad LAN management, including UDP and direct connections. A system mDNS picker can grant narrower access to one selected service where supported. Gate Android-version-specific behavior and test permission denial and revocation. Show Wi-Fi connection state without requiring SSID access. [Android local network permissions](https://developer.android.com/privacy-and-security/local-network-permission), [Android NSD reference](https://developer.android.com/reference/android/net/nsd/NsdManager)

Model discovering separately from the session states connecting, connected, authentication required, reconnecting, offline, and error. A valid health response or authenticated, identity-matched live message can establish freshness. Expose last seen and mark readings stale after missed updates. Share a bounded scheduler across devices, prefer live status over polling, apply jittered backoff for health checks, and revalidate identity before using a rediscovered address. Ambiguous writes remain unconfirmed until a valid acknowledgement or fresh mapped state resolves them.

## Existing ESP32 web projects

- **Test connection.** Normalize the user-entered host, port and scheme. Use bounded requests on that origin only. First check the universal descriptor, then a user-selected template's documented read-only status route. A reachable HTML panel counts as reachable, with API support still unknown.
- **Known templates.** Ship a template only against a documented and tested route contract. An LED profile might map `GET /status` to switch state and `POST /led/on` and `POST /led/off` to actions. Profiles may explicitly map legacy state-changing `GET` routes. Discovery and health checks must never run those routes.
- **Manual builder.** Map a control to an HTTP method, relative path, selected headers and a typed request body with bounded input substitution. Define allowed status codes, JSON Pointer mappings, expected values, polling interval and credential references. For WebSocket, configure same-device path, typed message templates, safe selectors and correlation IDs where supported. Keep automatic probing away from write endpoints and disable writes on newly imported profiles until reviewed.
- **Honest state.** Distinguish reachable, authenticated, and verified control. A transport-level `2xx` can show request accepted when the profile defines that contract. Only a configured acknowledgement or verified state read proves the expected result. A webpage without a stable endpoint mapping needs a manual profile or a separate optional legacy viewer.

Layouts reference stable capability IDs and store presentation overrides separately. This preserves names, order, icons, and colors across capability updates while preventing customization from removing motion safety rules. Bound sensor and connection history, apply versioned migrations, and export only scrubbed configuration. Import is a preview and validation flow. Sensitive values in endpoint bodies, headers, or query strings must be replaced by credential references before persistence or export.

## Security and future remote access

- Trust the chosen endpoint only after identity and transport checks. Validate descriptor sizes, types, unique capability IDs, ranges, and versions before rendering. Constrain local URLs to the chosen device and active local route, validate DNS answers and the actual socket destination, reject redirects and cross-origin requests, and block credentials from crossing origins or appearing in logs. Unverified announcements can populate candidates only.
- Prefer HTTPS/WSS with normal certificate verification. Any private trust enrollment needs independently verified device identity, explicit approval, and a rotation path. Unencrypted HTTP/WS is an explicit per-device compatibility setting, limited to the trusted local network, with a clear warning that traffic can be read or changed. Enforce that policy at the shared Dart transport and test the Android cleartext configuration with both clients. [Android network security configuration](https://developer.android.com/privacy-and-security/security-config)
- Store tokens with Android-backed secure storage. Exclude secrets from exports, backups, QR display after enrollment, diagnostics and logs. Revoke device credentials where supported and remove local credentials on unpair. Devices with no authentication cannot establish a strong identity from an IP address or an advertised ID. [Android Keystore](https://developer.android.com/privacy-and-security/keystore)
- Require firmware-side limits, a watchdog and a physical means to stop hazardous motion. Enable network controls for hazardous motion only when the device's safety contract is verified. Keep Stop available without confirmation. Treat a timed-out stop as unconfirmed and show the appropriate local stop instructions. Generic legacy profiles with unverified motion safety remain read-only for those controls.
- Phase 8 defines a separate MQTT-over-TLS adapter for the normalized device interface. Use explicit owner enrollment, per-device/topic authorization, short-lived scoped app credentials, and per-device credentials provisioned outside the APK. Commands need correlation IDs, expiry, deduplication, and acknowledgement. Expired, retained, or queued motion commands must never execute. Keep remote control opt-in and disabled until security and hardware tests pass.

## Test plan and phase gates

| Gate | Required evidence |
| --- | --- |
| Phase 0 | Verify host tools, resolve the app shell dependencies, analyze the shell, and validate draft schema fixtures. Record any Android build blocker. |
| Phase 1 | Run onboarding and navigation on Android. Check the six destinations, empty states, dark theme contrast, text scaling, reduced motion and small-screen layout. |
| Phases 2–3 | Exercise valid and malformed descriptors, duplicate advertisements, UDP nonce mismatch, permission denied, DHCP changes, offline and timeout paths, wrong credentials, reconnect and command acknowledgement. Use a local deterministic fixture for faults. |
| Phases 4–5 | Verify dynamic LED, relay, fan, servo, motor and sensor controls, unknown capabilities, dashboard edits and migration, restart persistence, export redaction, and profile import review. |
| Phases 6–7 | Flash two real ESP32 boards, one universal and one legacy. Verify mDNS and UDP on a physical Android phone. Run concurrent devices on normal and client-isolated Wi-Fi, with internet disconnected and Wi-Fi toggled. Verify device-side motion timeout and stop on a secured test bench. |
| Phases 8–9 | Review the remote interface and ownership design. Profile the Android app on a phone, inspect logs and backup behavior, test the release build, then sign and verify the APK with release keys supplied outside the source tree. |

Emulator tests can reach a development server on the Windows host through `10.0.2.2`. Keep that address confined to test configuration. Hardware discovery, Wi-Fi behavior, and actuation require physical tests. [Android emulator networking](https://developer.android.com/studio/run/emulator-networking-address)

## Phase 0 verification

- Flutter and the Android toolchain passed Doctor. `flutter pub add` resolved Riverpod 3.5.0 and GoRouter 18.1.4.
- Dart formatting and `flutter analyze` passed. The Flutter startup widget test passed.
- The descriptor test accepted the example and rejected nine malformed variants. These are structural checks. The semantic and wire-level checks are planned for the protocol implementation.
- `flutter build apk --debug` produced `app/build/app/outputs/flutter-apk/app-debug.apk`. Android launch and ESP32 hardware testing are pending.

The Phase 1 gate is user approval. Before public release, choose the permanent Android application ID, configure signing, and record the tested Android and ESP32 support matrix.
