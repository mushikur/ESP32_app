# Release audit for LAN networking

## Baseline and change plan

ESP IoT finds compatible firmware over Android NSD/mDNS and a bounded UDP discovery window. It accepts a manual private IPv4 address or a pairing QR and optionally checks a bounded list of nearby hosts. Device links use fixed host, port, scheme, and API paths. Registration requires consent for HTTP. Stored legacy devices use an explicit REST or WebSocket profile. No automatic web-interface control or live remote transport is implemented.

The existing Android manifest opts every native networking component into cleartext traffic so its URLConnection-based HTTP probe can reach dynamically entered LAN addresses. Android's Network Security Config supports static domain exceptions. It cannot express arbitrary private subnets with CIDR rules. The release change will default the native network policy to HTTPS. Legacy discovery probes will use the same Dart LAN client as device control, with the current private Wi-Fi subnet, bounded responses, no credentials, and no redirects. Native HTTPS probes will keep Android's certificate validation. [Network Security Config](https://developer.android.com/privacy-and-security/security-config) · [Flutter networking policy and Dart sockets](https://docs.flutter.dev/release/breaking-changes/network-policy-ios-android)

The Dart LAN client already requires Wi-Fi to be the active default connection and checks the Android link identity before and after exchanges. Cleartext discovery will now share that requirement. The discovery screen will tell users to make Wi-Fi active when Android routes through another default network. The phone and device can use a private Wi-Fi network without Internet access while Android uses it as the default link.

## Android version and permissions

| Platform | Expected behavior at target API 36 |
| --- | --- |
| Android 7–8.1, API 24–27 | Network Security Config provides the same native HTTPS default as newer Android versions. Camera permission is requested on scanner use. |
| Android 9–12L, API 28–32 | HTTPS policy stays explicit. The discovery bridge uses the platform NSD API and a bounded multicast lock for legacy Wi-Fi discovery. |
| Android 13–15, API 33–35 | The bridge selects the Wi-Fi network for NSD where the API supports it. It releases legacy discovery resources on cancellation, timeout, or activity pause. |
| Android 16, API 36 | The local network restriction experiment is opt-in and used the temporary Nearby Devices permission. This app does not opt in. |
| Android 17, API 37, at target API 36 | Android supplies an implicit LAN grant to apps declaring Internet. The runtime Local Network permission applies when raising the target SDK to 37. A future target-37 build must request it for manual addresses and the app's direct discovery sockets, or use system-mediated per-device discovery where supported. |

ESP IoT declares Internet, network state, and Wi-Fi multicast state. The scanner library contributes the camera declaration, and the manifest makes camera hardware optional. Bluetooth, USB host serial, notification, and location access are outside the current app's permission needs. [Android local network permission](https://developer.android.com/privacy-and-security/local-network-permission) · [Android 16 behavior changes](https://developer.android.com/about/versions/16/behavior-changes-16)

## Security boundaries

- REST and WebSocket clients reject redirects, proxy routes, URL user info, unexpected peers, and out-of-subnet addresses. Discovery does not execute command mappings. Unauthenticated legacy probes read only the discovery descriptor or confirm that the root path responds.
- Authentication headers and pairing tokens require TLS. Ordinary HTTPS/WSS use certificate validation. When the user supplies a certificate pin, the exact SHA-256 of the peer certificate and its validity period are checked on each connection. The pin is a separate trust mechanism for a private device certificate.
- QR hints contain endpoint and identity data and optionally the SHA-256 pin. They carry no credentials. Users see the endpoint before pairing. A QR or unauthenticated device ID cannot establish the trustworthiness of a LAN.
- Credentials are kept through Android-backed secure storage. Profiles and history use app-local storage. Avoid entering secrets in user-configured request bodies or metadata, which are not credential fields.

## Verification plan

Run the discovery and connection tests and HTTPS/WSS fixture. Inspect the merged manifest in the release APK and exercise permission denial, legacy HTTP on an active Wi-Fi subnet, network changes, and a real ESP32 before making hardware compatibility claims.
