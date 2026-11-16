# ESP IoT Phase 5 device management

Open **My Devices** to see your registered devices. **Check connections** verifies their current local status and can be cancelled. Each card shows the latest verified contact when available. Open a card or select **Reconnect** to start a foreground session with live readings. Home shows recent devices and counts from fresh checks.

Use a device's settings button to rename it, change its room, category, or icon, view its connection information, check its address, see its history, or remove it. Clearing a custom name restores the device's advertised name. Compatible devices can share an address and device ID using the pairing QR. Registering from Discover verifies the address before saving it.

## Addresses and status

- A saved ESP IoT v1 device can move to a new address. The app checks the device ID and connection security, confirms the new endpoint, and keeps the registration's details and history. An HTTPS registration requires HTTPS after a move. An HTTP address requires trusted Wi-Fi consent. Plain HTTP IDs provide identification on a trusted network and can be imitated by another device on that network.
- A legacy profile is tied to the registered origin. Verify the saved address from its settings, or register a new address from Discover and configure its API profile there.
- Inventory checks make read requests to at most three registered devices at a time. They use the universal status route or a configured legacy status rule. An unconfigured legacy project or missing active Wi-Fi has unknown status. A valid reply is required for Connected. Inventory observations expire after 30 seconds and clear when the app goes into the background. Last seen remains a historical timestamp.

## Local storage and Activity

SQLite stores registrations, successful contact and last-opened times, and up to 300 recent activity events. The Activity tab shows connection checks, device registrations, address verification, and acknowledged, rejected, or unconfirmed command outcomes. Device settings also opens a timeline filtered to that registration. Activity records contain timestamps and event types. Command bodies, headers, credentials, and sensor readings stay outside the timeline.

On the first successful open, the database imports the original registration list from preferences in a transaction. The migration marker prevents another import, and the original list is cleared after the transaction commits. Existing encrypted API profiles and dashboard layouts remain readable. New registrations use their own storage keys, including when an address or device ID was used by a previous registration. Profiles stay in Android secure storage and layouts stay in local preferences.

Removing a device deletes the registration and its history in one database transaction. The app then removes the profile and layout. A durable cleanup record lets it retry if Android storage is temporarily unavailable. Re-registering creates an independent registration.

## Changed files

- [Device registration and validation](../app/lib/features/devices/device_registration.dart), [database and migration](../app/lib/features/devices/device_database.dart), and [inventory operations](../app/lib/features/devices/device_registry.dart).
- [Inventory, cards, settings, and activity](../app/lib/features/devices), [Home](../app/lib/features/home/home_screen.dart), and [app routes](../app/lib/app/app_router.dart).
- [Connection screen](../app/lib/features/connection/device_connection_screen.dart), [session and status check](../app/lib/features/connection/device_session.dart), [profile storage](../app/lib/features/connection/profile_store.dart), [profile editor](../app/lib/features/connection/profile_editor.dart), [layout storage](../app/lib/features/dashboard/dashboard_layout.dart), and [address verification dialogs](../app/lib/features/discovery/discovery_dialogs.dart).
- [Dependencies](../app/pubspec.yaml), [lockfile](../app/pubspec.lock), and [device management tests](../app/test/device_management_test.dart).

## Run and test

Phase 5 uses `sqflite` on Android and `sqflite_common_ffi` for SQLite tests. [Android SQLite adapter](https://pub.dev/packages/sqflite) · [SQLite test adapter](https://pub.dev/packages/sqflite_common_ffi)

```powershell
pwsh -NoProfile -File .\protocol\v1\test-descriptor.ps1
Set-Location .\app
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter run
```

Run `dart run tool/phase3_fixture.dart` in a second terminal in `app/`. On the Android emulator, the universal fixture is at `10.0.2.2:8765` and the legacy fixture is at `10.0.2.2:8766`. For an upgrade check, install the new APK over a previous version with registered fixtures. Open My Devices, check connections, and open an existing legacy dashboard. Edit a device, relaunch, and check its details and history. Use a disposable registration to test removal.

## Verification

Static analysis, all 42 Flutter tests, and all 10 protocol checks passed. Tests exercised SQLite migration and reopening, saved metadata and history, transactional removal, isolation from a previous registration's encrypted profile, identity checks on address changes, and confirmation before removal.

The debug APK built successfully. An in-place Android emulator upgrade imported both Phase 4 fixture registrations and opened the legacy dashboard using its existing encrypted profile. Verified connections appeared in Activity and on the device cards. Saving the fixture's new name and room updated the inventory.

## Scope and next phase

Pairing in this phase means local registration and QR-assisted identity checks. Firmware-issued authorization tokens are scheduled for Phase 7. Device status remains local and foreground only. Phase 6 adds the reusable ESP32 firmware library and examples. Hardware, HTTPS/WSS, and guarded movement still require release verification.
