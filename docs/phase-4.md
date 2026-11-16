# ESP IoT Phase 4 dashboards

Open **My Devices → Open connection**. A universal device's verified capability descriptor populates the dashboard. Switches cover LEDs and individual relay channels. Ranges cover fan speed, servo angle, and settings such as a motor speed limit. Sensors show the current reading, units, last reading time, and a trend for up to 60 received samples. Actions send a single typed request. Unknown capabilities show as unsupported.

**Edit dashboard** reorders controls and changes labels, icons, colors, and visibility. Use **Remove** to hide a tile and **Add** to bring it back. Layouts are stored per device, with universal layouts keyed by device ID and legacy layouts keyed by registered origin. Updated descriptors or profiles can introduce new tiles. Obsolete controls are omitted.

## Commands and safety

- Universal writes go to `POST /api/v1/commands`. The app checks the command ID, device ID, boot ID, and descriptor revision in the acknowledgement. A verified status update determines the displayed device state. Failed or ambiguous writes are never replayed automatically.
- Ranges, actions, legacy writes, descriptor-marked switches, and writable controls on motion-capable universal devices require confirmation. Dragging a slider only selects a value locally.
- Motion tiles keep Stop available outside the editable layout while the device is connected. Stop sends a typed request without confirmation. The app displays whether it received an acknowledgement. Use the physical stop if connectivity or the result is uncertain.
- Motion starts stay locked until a device-side lease and watchdog are implemented and verified. The Phase 4 fixture changes only in-memory values. The sample motor slider adjusts a speed limit.

## Map an existing project's API

Use **Edit API profile** to add a `controls` list to the existing JSON profile. The **Dashboard example** button loads a REST LED and temperature example. Its URLs and response fields must match your firmware. Older profiles and their optional test actions continue to work.

Each control needs a unique `id`, a display `name`, and a `type`. `pointer` selects a value from the profile's status result after its own `response` rule. Use an empty pointer for a scalar result. Use JSON booleans for switches and JSON numbers for ranges and sensors. A missing field or a value of the wrong type leaves that tile unavailable.

| Control | Mapping |
| --- | --- |
| `switch` | `pointer` and `on` / `off` command mappings |
| `range` | `pointer`, `min`, `max`, `step`, optional `unit`, `set`, and `valueField` for the chosen number |
| `sensor` | `pointer` and optional `unit` |
| `action` | `invoke` command mapping |

A REST command uses the Phase 3 method, path, optional JSON body, and response rule. Dashboard commands need a response rule with `equals` to distinguish a confirmed action from a generic HTTP success. WebSocket commands use a `message` object and a `correlationField` that firmware echoes. Reserve correlation fields for acknowledgements. A range command inserts its numeric value into the configured unused top-level `valueField`.

This WebSocket profile matches the loopback legacy fixture.

```json
{
  "transport": "websocket",
  "statusPath": "/ws",
  "response": {"format": "json"},
  "controls": [
    {
      "id": "led", "name": "LED", "type": "switch", "pointer": "/led",
      "on": {"message": {"op": "setLed", "enabled": true}, "response": {"pointer": "/ok", "equals": true}},
      "off": {"message": {"op": "setLed", "enabled": false}, "response": {"pointer": "/ok", "equals": true}}
    },
    {"id": "temperature", "name": "Temperature", "type": "sensor", "pointer": "/temperature", "unit": "°C"}
  ]
}
```

## Changed files

- [Dashboard renderer, layout editor, and storage](../app/lib/features/dashboard).
- [Connection screen](../app/lib/features/connection/device_connection_screen.dart), [session](../app/lib/features/connection/device_session.dart), [profile parser](../app/lib/features/connection/api_profile.dart), and [profile editor](../app/lib/features/connection/profile_editor.dart).
- [Capability model](../app/lib/core/protocol/device_descriptor.dart), [command model](../app/lib/core/protocol/device_command.dart), [example descriptor](../protocol/v1/examples/bench-controller.json), and [loopback fixture](../app/tool/phase3_fixture.dart).
- [Connection and dashboard tests](../app/test/connection_test.dart), [descriptor regression test](../app/test/discovery_test.dart), and [workspace README](../README.md).

## Run and test

From the workspace root, run the protocol checks and Flutter suite. No new packages are required.

```powershell
pwsh -NoProfile -File .\protocol\v1\test-descriptor.ps1
Set-Location .\app
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter run
```

From a second terminal in `app/`, run `dart run tool/phase3_fixture.dart`. On the Android emulator, register `10.0.2.2:8765` for the universal fixture and `10.0.2.2:8766` for the legacy one. Switch the fixture LED and wait for the next status sample. Edit the layout and reopen the device to check persistence. The fixtures are loopback-only development tools.

## Verification

Static analysis passed, all 37 Flutter tests passed, and all 10 protocol descriptor checks passed. The debug APK built successfully. The tests cover typed acknowledgements, WebSocket command correlation, bounded sensor history, confirmation before changing a range, and reloading a customized layout while retaining the motion Stop control.

On the Android emulator, the universal fixture streamed status updates and displayed the motion Stop control. After confirming an LED switch, the fixture reported the new state and the dashboard displayed it on the next verified update. The legacy fixture also passed the REST dashboard example's read test, confirmed switch write, and follow-up status update.

## Scope and next phase

Sensor trends are kept in memory for the open session. Phase 5 adds the device management and connection history workflows. Physical hardware, HTTPS/WSS deployments, pairing-token enrollment, and guarded movement still need verification or implementation before release.
