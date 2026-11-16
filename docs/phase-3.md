# ESP IoT Phase 3 connections

Open **My Devices → Open connection**. Universal devices use the ESP IoT v1 descriptor and status routes. The app revalidates the registered ID and schema revision, then polls REST or consumes the advertised WebSocket stream. Heartbeats can refresh contact time while the last status sample keeps its own timestamp. An unvalidated reply or a socket handshake alone cannot mark the session connected.

Legacy devices use a profile that you configure for that firmware. Choose a REST or WebSocket template, edit the JSON, and select **Test read** before saving. Connection reads automatically run while the device screen is active. Configure only a read-only path for status. Some older ESP32 projects change state in GET handlers.

## Profile format

This example matches the bundled legacy fixture. Adapt the paths and JSON selectors to your device.

```json
{
  "transport": "rest",
  "statusPath": "/status",
  "pollSeconds": 10,
  "response": {"format": "json", "pointer": "/led"},
  "action": {
    "method": "POST",
    "path": "/identify",
    "body": {"identify": true},
    "response": {"format": "json", "pointer": "/ok", "equals": true}
  }
}
```

- The status interval accepts 5–300 seconds. With WebSocket it sets the expected update cadence, and the app reconnects when valid events stop arriving.
- REST status and command rules can match JSON, exact text, or a configured HTTP status code. JSON rules can select a value using JSON Pointer and compare a scalar with `equals`. The default HTTP response code is 200.
- The optional REST test action supports GET, POST, PUT, PATCH, and DELETE. Paths are literal relative paths on the saved origin. Use a different read-only route from a state-changing GET. An HTTP status-only response leaves device state unconfirmed.
- Profiles support up to eight non-sensitive X- metadata headers. The separate authentication form supports Basic, Bearer, and X-API-Key for HTTPS/WSS devices. Profile JSON and credentials are encrypted together in Android storage. Android backup is disabled to avoid restoring encrypted data without its keys. [Flutter Secure Storage](https://pub.dev/packages/flutter_secure_storage)

For the fixture's WebSocket endpoint, use the following profile. The command sends a new correlation ID. The device must echo that exact ID in a JSON acknowledgement with `ok: true`.

```json
{
  "transport": "websocket",
  "statusPath": "/ws",
  "pollSeconds": 10,
  "response": {"format": "json", "pointer": "/led"},
  "action": {
    "message": {"op": "identify"},
    "correlationField": "requestId",
    "response": {"format": "json", "pointer": "/ok", "equals": true}
  }
}
```

Test actions require explicit confirmation each time. Failed or missing acknowledgements stay unconfirmed. The app retries health reads and connections with backoff. It never replays a test action automatically.

## Local transport and scope

Dio handles bounded REST requests. The WebSocket client keeps upgrades on the registered origin and applies a 32 KiB frame limit. It also checks assembled JSON messages before parsing them. Dart can buffer fragments before that message check. Both transports block redirects and proxies, check the current private IPv4 Wi-Fi link, and verify certificates for TLS. Live sessions require that Wi-Fi be Android's active network. Local Wi-Fi works without an account or cloud service. [Dio](https://pub.dev/packages/dio), [WebSocket Channel](https://pub.dev/packages/web_socket_channel)

Phase 3 monitors the device on its foreground connection screen. Closing the screen or backgrounding the app pauses polling and closes its event stream. The inventory continues to show an unknown live status outside a session. The editor accepts JSON configuration, uses literal paths without queries, and requires an acknowledgement contract for WebSocket test commands. Universal token enrollment and the device dashboard are later phases.

## Changed areas

- [LAN transport and path validation](../app/lib/core/transport), [protocol models](../app/lib/core/protocol), and the [Android Wi-Fi bridge](../app/android/app/src/main/kotlin/com/example/esp_iot/LocalDiscoveryBridge.kt).
- [Session monitor](../app/lib/features/connection/device_session.dart), [device connection screen](../app/lib/features/connection/device_connection_screen.dart), and [My Devices navigation](../app/lib/features/devices/devices_screen.dart).
- [Profile validation](../app/lib/features/connection/api_profile.dart), [profile editor](../app/lib/features/connection/profile_editor.dart), and [encrypted profile storage](../app/lib/features/connection/profile_store.dart).
- [Dependency manifest](../app/pubspec.yaml), [lockfile](../app/pubspec.lock), and [Android manifest](../app/android/app/src/main/AndroidManifest.xml).
- [Connection tests](../app/test/connection_test.dart) and the [loopback-only fixture](../app/tool/phase3_fixture.dart).
- [Workspace README](../README.md) and [protocol documentation](protocol-v1.md).

## Run and test

Run these commands from the workspace root.

```powershell
pwsh -NoProfile -File .\protocol\v1\test-descriptor.ps1
Set-Location .\app
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter run
```

In a second terminal in `app/`, run `dart run tool/phase3_fixture.dart`. From the Android emulator, register `10.0.2.2:8765` for the universal fixture or `10.0.2.2:8766` for the legacy fixture. Reuse registrations from Phase 2 if available. Fixture actions increment a counter in memory and operate without hardware.

## Verification

- Static analysis passed, all 32 Flutter tests passed, and all 10 protocol descriptor checks passed. The debug APK built successfully.
- A real loopback REST and WebSocket test verified command acknowledgements and rejection of redirects. The Android emulator verified universal live events and legacy REST and WebSocket status against the local fixture. The saved REST profile produced another matching response after restarting the emulator.
- Physical ESP32 hardware and HTTPS/WSS device deployments remain unverified.

## Next phase

Phase 4 adds controls generated from verified capability descriptors and compatible profiles. Device-side safety checks, secure token enrollment, and physical ESP32 validation remain release gates.
