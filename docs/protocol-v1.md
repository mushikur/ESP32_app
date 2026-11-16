# ESP IoT device protocol v1 draft

The wire identifier is `esp-iot`. The [descriptor schema](../protocol/v1/device.schema.json) is JSON Schema Draft 2020-12. The [bench descriptor](../protocol/v1/examples/bench-controller.json) is a test fixture. This draft must be validated against real firmware before freezing v1. [JSON Schema 2020-12](https://json-schema.org/draft/2020-12)

## Discovery and identity

- mDNS service `_espiot._tcp` advertises the API host and port. TXT `v=1`, `id=<deviceId>` and `tls=0|1` are hints. The app independently validates the descriptor, scheme, endpoint and identity.
- The UDP draft uses configurable private port `55073` on the current Wi-Fi IPv4 link. The UTF-8 JSON query is `{"protocol":"esp-iot","version":1,"kind":"discover","nonce":"<32 lowercase hex>"}`. A compatible device unicasts `{"protocol":"esp-iot","version":1,"kind":"offer","nonce":"<same nonce>","deviceId":"<32 lowercase hex>","port":8080,"tls":false}` back to the query source. Use the response source IP. Keep datagrams at or below 512 bytes and rate-limit responses. Do not send tokens, persistent credentials, full descriptors or broadcast replies. Correlation limits accidental matches. It provides no authentication.
- The QR pairing hint uses this UTF-8 JSON object with the same protocol version and device ID as the descriptor. Verify the address with the user and match the returned descriptor ID. Credentials and arbitrary links are excluded from v1 QR hints. Phase 2 accepts a canonical private IPv4 literal on the current Wi-Fi link. Unknown versions and additional fields are rejected.

  ```json
  {"protocol":"esp-iot","version":1,"kind":"pairing-hint","host":"192.168.1.100","port":80,"scheme":"http","deviceId":"0123456789abcdef0123456789abcdef"}
  ```
- `deviceId` is a random persistent 128-bit identifier generated per device and retained across restarts. A reset that clears identity also clears pairing credentials. IP addresses, discovery data and IDs received over plain HTTP cannot authenticate hardware.

## HTTP routes

| Route | Contract |
| --- | --- |
| `GET /.well-known/esp-iot` | Public descriptor and capability inventory. Keep this payload free of credentials, network settings, and live sensor values. |
| `POST /api/v1/pair` | For `pairing-token` devices over verified HTTPS. Requires a one-time code from a physically opened, short-lived pairing window. Return a scoped, revocable per-client token. |
| `GET /api/v1/status` | Full current snapshot and health check. Require authorization on paired devices. |
| `POST /api/v1/commands` | Submit a typed command and return an outcome tied to `commandId`. Require authorization on paired devices. |
| `GET /api/v1/events` | Optional WebSocket upgrade when `events` is true. Authorize the upgrade. Send a full snapshot on connection and subsequent complete snapshots or application heartbeats. |
| `DELETE /api/v1/pairing` | Revoke the calling credential where token pairing is enabled. |

Require JSON content types for payloads. Initial budgets are 32 KiB for descriptor and snapshot payloads and 2 KiB for commands. Reject duplicate JSON keys, invalid UTF-8, non-finite numbers and excess nesting. Pairing codes expire and are rate-limited. Use a bearer token in the `Authorization` header over HTTPS/WSS. Use no credentials in URLs. An `auth: none` device may run on trusted local HTTP with explicit app consent. Keep guarded motion disabled on unauthenticated or unencrypted profiles.

## Capabilities and state

The descriptor `revision` increases when capability definitions change. Capability IDs are unique within the device and stable across descriptor updates. ID syntax, maximum lengths, fields and known types are defined by the schema. Runtime validation also checks duplicate capability IDs, strictly ordered range bounds, finite numbers, step alignment and a reasonable maximum number of selectable steps. Unknown extension types use `x-<vendor>-<type>` and render as unsupported without sending commands. Unsupported protocol versions must fail closed.

`switch` maps to boolean state and a `set` command. `range` maps to numeric state and `set`, with units and bounds enforced at both ends. `sensor` is read-only with numeric state and units. `action` maps to `invoke` with no arbitrary payload. `motion` maps to `move` or `stop`. Stop is mandatory for motion, does not require confirmation, and is independent of presentation preferences. A required `confirm` flag on other writable controls controls the prompt. The app can enforce stricter safety rules.

Status and WebSocket snapshots carry `deviceId`, `revision`, a random 128-bit lowercase hexadecimal `bootId` per reboot, an increasing integer snapshot `seq` within that boot, and a `values` object keyed by capability ID. A snapshot can also include `"kind":"snapshot"`. An unavailable reading is `null`, distinct from zero or false. Motion state uses `stopped` or a listed direction. Actions have no persistent value. Full snapshots make reconnect and packet loss recovery explicit. A heartbeat contains `"kind":"heartbeat"` and only the current `deviceId`, `bootId`, and `revision`. It can refresh connection liveness without marking sensor data fresh. Ignore stale messages from prior sessions. Re-fetch the descriptor on revision change and revalidate trust before resuming control.

## Commands and acknowledgements

Commands are typed rather than device-supplied URLs. The app uses the advertised capabilities to decide which request forms to send. Example request body for an LED:

```json
{
  "commandId": "15ec37ca42bb4dd08e068cc6fe660d2a",
  "bootId": "8acf14d32f144f87a12672b84804ee0e",
  "revision": 1,
  "capabilityId": "led",
  "op": "set",
  "value": true
}
```

Only `set` takes a boolean or number in `value`, depending on capability type. `invoke` and `stop` have no value. `move` takes a listed `direction`, integer `durationMs` from 100 through the descriptor maximum, and a device-issued short-lived `leaseId`. Reject mismatched boot or revision before applying the command. Move requires explicit user initiation, a verified device-side lease and a watchdog that ends motion at its deadline or on lease loss. Initial hazardous-motion support is gated on verification of the lease handshake, hardware stop behavior and fault tests.

A final outcome includes `commandId`, `deviceId`, `bootId`, `revision`, and `outcome` of `applied` or `rejected`. An `applied` result may include authoritative new state. A rejection includes a stable error `code` such as `invalid_command`, `auth_required`, `forbidden`, `descriptor_changed`, `device_restarted`, `busy`, or `unsafe_state`. Map these to HTTP `400`, `401`, `403`, `409` or `429` as appropriate. Return `200` for applied outcomes. A socket close, HTTP success without the expected body, or a timeout is not evidence of execution.

Firmware deduplicates command IDs by authorized principal for a bounded period within the same boot. Identical duplicates return the original outcome. Reject reuse with a different payload and bound in-flight requests and deduplication storage. The app must not automatically replay writes with ambiguous outcomes. Reconcile via status where possible. Keep automatic retries for discovery, reads and reconnects.

## Secure pairing wire format

`POST /api/v1/pair` accepts a JSON object with exactly `deviceId` and `code`. The ID is the verified device's 32-character lowercase hexadecimal ID. The code is an eight-digit string. A successful HTTP 200 JSON response has exactly `deviceId` and `token`. The token contains 64 lowercase hexadecimal characters from 32 random bytes. The app sends it as `Authorization: Bearer <token>` only over its verified HTTPS or WSS origin. `DELETE /api/v1/pairing` revokes that caller's token and returns HTTP 204 with an empty body.

The SDK pairing window lasts 60 seconds, accepts at most five attempts with a minimum 750 ms interval, and closes on successful use. Firmware retains token digests in its device-scoped storage. A change of device identity invalidates those digests. The secure SDK advertises WebSocket events only when it can authorize the upgrade. The Phase 7 guide covers supported deployment modes and tests. [Secure pairing guide](phase-7.md)

An HTTPS pairing hint can include one optional `certificateSha256` field of 64 lowercase hexadecimal characters. This is the SHA-256 digest of the leaf certificate's DER bytes. QR hints from a trusted device owner can establish the expected certificate. mDNS and UDP discovery remain address hints. They do not establish certificate trust.

## Phase 6 SDK subset

The Arduino SDK supports up to 16 switch, range, sensor, action, and stop capabilities per device. It uses one local anonymous command scope with a 30-second acknowledgement window and room for 15 ordinary command outcomes. When the window is full, ordinary commands return `busy`. Stop has reserved capacity and can still call an idempotent local stop handler if the cache is full. Movement requests return `unsafe_state`. The SDK supports up to three read-only WebSocket subscribers and publishes full snapshots at two-second intervals. See the hardware setup and verification in the [firmware library guide](phase-6.md).
