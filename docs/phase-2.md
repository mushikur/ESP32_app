# ESP IoT Phase 2 local discovery

Discover starts a short Wi-Fi search when opened. It listens for `_espiot._tcp` services and sends one ESP IoT UDP query on port `55073`. The Android bridge binds requests to the selected Wi-Fi network and runs off the UI thread. Dart applies a separate deadline so a stalled platform reply can be reported in the app. The app verifies candidates against the v1 description, deduplicates endpoints, and withholds conflicting identities.

Manual address entry tests a private IPv4 address and optional port on the same link. A universal project returns a valid descriptor. An existing project may pass a separate read-only check of its web endpoint and be saved as a legacy project for later API setup. The app follows the protocol's fixed read paths and blocks redirects.

The optional subnet check asks for consent on each run. It uses one chosen port, up to 32 nearby addresses, two concurrent requests, and at most four starts per second. The probe window is bounded at about ten seconds. Search and verification are cancelled when leaving Discover or backgrounding the app.

The QR scanner uses bundled Android barcode detection and works without a first-use model download. The app previews the destination and verifies the advertised ID before registration. A saved universal device can display its own QR hint in My Devices. The payload carries connection information only. [Mobile scanner](https://pub.dev/packages/mobile_scanner), [QR rendering](https://pub.dev/packages/pretty_qr_code)

My Devices keeps confirmed registrations in local preferences. HTTP registration requires explicit trusted Wi-Fi consent. An HTTP descriptor identifies what the endpoint reports and cannot authenticate the hardware. HTTPS uses Android certificate validation, including the IPv4 address, and has no cleartext downgrade. Device cards show when the address was verified. Online, offline, and token authorization state depend on the later connection phases.

## Android requirements

Phase 2 supports directly connected RFC 1918 IPv4 Wi-Fi. Use the numeric address for manual entry and QR codes. An active VPN, IPv6-only or unsupported subnet, and isolated guest networks may prevent discovery. Android can report the mDNS service name as a display hint on versions that lack the hostname API.

The app targets API 36 and uses Android internet, network state, and multicast permissions. The camera prompt appears only when opening the scanner. A future target SDK 37 migration requires the Android local network permission flow. The app does not request location or SSID access. [Android local network permission](https://developer.android.com/privacy-and-security/local-network-permission), [Android NSD](https://developer.android.com/reference/android/net/nsd/NsdManager)

## Changed areas

- [Android discovery bridge](../app/android/app/src/main/kotlin/com/example/esp_iot/LocalDiscoveryBridge.kt), [activity](../app/android/app/src/main/kotlin/com/example/esp_iot/MainActivity.kt), and [manifest](../app/android/app/src/main/AndroidManifest.xml) for Wi-Fi scope, mDNS, UDP, bounded HTTP metadata requests, and lifecycle cancellation.
- [Discovery screen and services](../app/lib/features/discovery/) for search, consent, manual verification, QR, and actionable errors. [Protocol validation](../app/lib/core/protocol/) checks the v1 descriptor, ranges, capabilities, and duplicate JSON keys.
- [Device inventory](../app/lib/features/devices/device_registry.dart), [My Devices](../app/lib/features/devices/devices_screen.dart), and [Home](../app/lib/features/home/home_screen.dart) for saved registrations and Wi-Fi information.
- [Discovery tests](../app/test/discovery_test.dart), [widget tests](../app/test/app_smoke_test.dart), and [loopback HTTP fixture](../app/tool/phase2_fixture.dart) for reproducible validation.

## Run and test

Run these commands from the workspace root with an Android device or emulator available.

```powershell
pwsh -NoProfile -File .\protocol\v1\test-descriptor.ps1
Set-Location .\app
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter run
```

For an emulator integration check, run `dart run tool/phase2_fixture.dart` from `app/` in a separate terminal. The fixture listens on the Windows loopback address only. Use **Discover → Manual address** with `10.0.2.2`, port `8765` for the universal fixture or `8766` for the legacy fixture. Use HTTP on the test emulator. Review the response, confirm the trusted test network, save, and reopen the app to check persistence. The fixtures simulate documented protocol responses and do not represent hardware results. [Android emulator networking](https://developer.android.com/studio/run/emulator-networking-address)

## Verification

- Dart formatting, Flutter analysis, 20 Flutter tests, 10 schema checks, and the Android debug build passed.
- On the Android 16 emulator, the final APK completed a Wi-Fi search without any compatible advertisements present. The dedicated address form worked with the Android keyboard. Both loopback HTTP fixtures were verified and saved, the universal pairing QR displayed, and both registrations survived a force-stop and relaunch.
- The automated suite checks descriptor and QR validation, mDNS and UDP candidate handling, nonce matching, deduplication, subnet limits, off-link and redirect rejection, timeouts, Wi-Fi changes, and registration persistence.
- Real ESP32 mDNS and UDP announcements and physical camera decoding are pending. The emulator evidence covers virtual Wi-Fi, local HTTP verification, and QR display.

## Next phase

Phase 3 adds the REST and WebSocket transport, explicit API profiles, and connection health. Before a hardware readiness claim, verify mDNS and UDP from compatible firmware and camera decoding on a physical Android phone. Test a router that permits discovery traffic and a guest network with client isolation.
