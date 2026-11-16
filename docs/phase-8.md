# ESP IoT Phase 8 remote connectivity preparation

## Android transport boundary

The [universal transport interface](../app/lib/core/transport/universal_transport.dart) exposes the verified device descriptor, a fresh status snapshot, optional live events, a route check, and a correlated command acknowledgement. The dashboard session uses these operations for controls, sensor history, reconnect, and lifecycle management. A connector is selected once per monitoring run. It owns route binding across retries and releases attempt resources on failure or pause.

The [local adapter](../app/lib/features/connection/lan_universal_connector.dart) implements the interface using ESP IoT v1 HTTPS or HTTP and WSS or WS on the selected Wi-Fi link. It rechecks the registered device identity before sending a saved pairing token and validates status and acknowledgement envelopes. One-shot device health checks use the same adapter. Legacy API profiles use their existing local HTTP and WebSocket engine. Local discovery, pairing, and control work without an account or broker.

## Proposed remote route

```text
Android universal connector
        | HTTPS requests and authenticated WSS device events
Ownership and device gateway service
        | MQTT 5 over TLS
Broker with per-device topic permissions
        | MQTT 5 over mutual TLS
Opted-in universal ESP32 firmware
```

- The gateway authenticates users, verifies tenant and device membership on each operation, and returns the same typed descriptor, status, and command outcomes as the local route. Keep gateway APIs and identity, broker, and provisioning providers behind separate interfaces. A remote connector can operate on mobile data without the LAN adapter or a local IP.
- Enrollment requires the signed-in owner to prove possession through an expiring, one-use challenge and a verified per-device identity. Require physical confirmation on the board for the first claim. Track remote claims separately from local pairing and require an explicit remote route selection. Ownership transfer revokes prior memberships and sessions before a new claim is accepted.
- The app receives short-lived, scoped gateway access tokens. Store any refresh credential in Android secure storage and clear it on logout. Issue each board a unique certificate and private key during provisioning. Use TLS hostname verification and a controlled certificate rotation and revocation process. Keep broker credentials in the gateway and provisioned devices. Keep LAN tokens, private keys, and remote credentials out of exports, logs, QR codes, and APK assets.
- The gateway enforces read, control, and management permissions, supports sharing and revocation, and records the actor, device, command ID, timestamp, and outcome. Revocation closes active streams and blocks new writes. Apply rate and payload limits, and audit without recording secrets or raw command payloads.

## MQTT 5 wire design

Use `esp-iot/v1/{tenantId}/{deviceId}` as the topic prefix. Both IDs are immutable, lowercase 32-character hex strings. Match both IDs to the authenticated device certificate and the ownership record. Broker ACLs deny by default. A board can subscribe to its own command topic and publish only to its own reply, status, and presence topics.

| Suffix | Publisher | Delivery and purpose |
| --- | --- | --- |
| `/commands` | Gateway | QoS 1, non-retained, short Message Expiry Interval. One validated v1 command per message. |
| `/acks` | Device | QoS 1, non-retained, short expiry. Correlated v1 applied or rejected acknowledgement. |
| `/status` | Device | Non-retained snapshot or heartbeat. A gateway status read needs a recent snapshot from the active device session. |
| `/presence` | Device or broker Last Will | Online and offline hints. Confirm availability through authenticated, fresh device status. |

The device uses Clean Start with Session Expiry Interval zero for its command subscription. Use Retain Handling 2 and Retain As Published 1 on that subscription. Reject retained command publications in firmware and enforce the broker policy against retained publishes to command topics. QoS 1 can redeliver a message and MQTT PUBACK confirms delivery at the MQTT layer. The app shows a command as applied only after an acknowledgement from the verified device. [OASIS MQTT 5.0 standard](https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html)

Wrap the existing [v1 command](protocol-v1.md) fields in a versioned gateway-to-device envelope. The gateway stamps the authorized command with the tenant and device IDs and an absolute expiry. The initial design limits command validity to five seconds. Publish with an MQTT Message Expiry Interval at most as long as the remaining validity and reject expired commands in firmware even if MQTT delivers them. The firmware needs a trustworthy time source and rejects time-limited writes when it cannot establish valid time.

```json
{
  "version": 1,
  "tenantId": "0123456789abcdef0123456789abcdef",
  "deviceId": "fedcba9876543210fedcba9876543210",
  "expiresAtMs": 1794400005000,
  "command": {
    "commandId": "456789abcdef0123456789abcdef0123",
    "bootId": "abcdef0123456789abcdef0123456789",
    "revision": 1,
    "capabilityId": "led",
    "op": "set",
    "value": true
  }
}
```

Firmware validates the topic and envelope IDs, expiry, boot ID, descriptor revision, operation, and value before dispatch. Deduplicate by tenant, device, boot ID, and command ID through expiry. Cache the result and request fingerprint. An identical redelivery returns the prior acknowledgement without another hardware write. A reused ID with different fields is rejected. Reserve deduplication capacity before acting and reject when full. The gateway accepts only device-authenticated acknowledgements that match the pending command, boot, and revision. A missing or invalid acknowledgement leaves the result unconfirmed. Reconnect restores status without replaying writes or changing routes.

Restrict the first remote pilot to individually approved, non-hazardous capabilities. Keep motion start and generic unreviewed actions disabled. Physical stop and firmware interlocks remain required for moving hardware. Reject stale or replayed readings using boot identity, sequence, and freshness. Clear the active status on restart, disconnect, or revocation and obtain a fresh full snapshot before enabling controls.

## Build and verification

Run the protocol and loopback checks from the workspace root. The firmware checks use a C++ compiler and the TLS test uses OpenSSL. Use `-OpenSsl` to provide its path when needed.

```powershell
pwsh -NoProfile -File .\protocol\v1\test-descriptor.ps1
pwsh -NoProfile -File .\firmware\tests\test-firmware.ps1 -FlutterContract
pwsh -NoProfile -File .\firmware\tests\test-secure-transport.ps1
Set-Location .\app
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

- Flutter analysis reported zero issues. All 46 Flutter tests passed. The new tests exercised a typed connection without a LAN registration and verified that a LAN retry keeps its original Wi-Fi binding.
- All 10 descriptor cases, nine C++ protocol checks, the generated descriptor schema check, and the Flutter-to-firmware contract passed.
- The HTTPS/WSS loopback check passed for certificate verification, pairing, saved token use, a verified command and live event, and revocation.
- The Android debug APK built at `app/build/app/outputs/flutter-apk/app-debug.apk`. Phase 8 added no runtime dependencies.

## Phase 9

Phase 8 ships the LAN adapter and the design. Remote enrollment, the broker, and the gateway remain future work. Phase 9 needs Android and physical ESP32 coverage across multiple boards and Wi-Fi networks, reconnect and timeout checks, performance and security verification, and a signed release APK. A future remote pilot also needs live broker tests for tenant isolation, expiry and duplicates, credential rotation and revocation, and the device safety policy.
