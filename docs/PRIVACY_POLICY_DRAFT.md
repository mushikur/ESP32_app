# ESP IoT privacy policy draft

**Effective date** — [Insert the publication date]  
**Publisher** — [Insert the legal name of the publisher]  
**Privacy contact** — [Insert a monitored email address or contact page]

## How ESP IoT uses your information

ESP IoT connects your Android phone or tablet to compatible devices on your local Wi-Fi. The app has no account system or ESP IoT cloud service.

- **Device setup and control.** The app reads your local network state and private IPv4 address to find compatible devices and check the address you enter or scan. It exchanges device descriptions, status, readings, and commands directly with devices on that network. The devices you connect to can receive your requests and may have their own data practices.
- **Saved devices and activity.** The app saves device names, local addresses, device IDs, dashboard settings, last-seen and last-opened times, and recent connection and command outcomes in its private app storage. Sensor trend samples are held in memory for the active session.
- **Credentials.** Secure pairing tokens and optional API credentials and profiles are encrypted in Android app storage using keys protected by Android Keystore. The app sends credentials to the configured device over HTTPS or WSS. Compatible legacy devices may use unencrypted HTTP or WS after your approval. Use these connections only on a Wi-Fi network you trust and keep private information out of legacy requests.
- **Learning and exports.** Lesson progress, language preference, and achievement activity are saved on your device. You can copy a sketch or link to the Android clipboard. Saving a sketch opens Android’s file picker. The file goes to the location you choose, which can include a cloud storage provider. The provider’s own privacy practices apply. [Android file picker](https://developer.android.com/training/data-storage/shared/documents-files)

## Camera and Google ML Kit

Android may ask for camera access when you open **Discover → Scan pairing QR**. You can enter the device address manually if you skip or deny camera access. The scanner decodes camera frames on your device. ESP IoT does not save or upload frames. A pairing QR can contain a device’s local address, port, identifier, connection scheme, and certificate fingerprint. Share it with people you trust.

ESP IoT uses the Google ML Kit Barcode Scanning SDK. Google says the SDK processes camera input and scan results on your device. The SDK can send diagnostics and usage metrics to Google, such as device and app details, a per-installation identifier, scanner settings, performance, and error information. Google uses those metrics to maintain, diagnose, and improve the SDK and detect abuse. [Google ML Kit terms and privacy](https://developers.google.com/ml-kit/terms) · [Google ML Kit Android data disclosure](https://developers.google.com/ml-kit/android-data-disclosure) · [Google privacy policy](https://policies.google.com/privacy)

## Retention and deletion

ESP IoT keeps up to 300 device activity entries across all saved devices. Use **Remove device** in a device’s settings to remove its registration and history and clear associated saved settings and credentials. If cleanup is interrupted, the app retries when it opens. To revoke an active secure pairing token on the ESP32 itself, use **Remove pairing** in the device’s connection screen while the device is reachable, or follow the firmware’s local revocation instructions.

Learning progress and other saved settings stay on your device until you clear the app’s storage or uninstall it. You can manage camera access in Android Settings. Exported sketches and data held by your ESP32, a selected storage provider, or Google are managed separately. ESP IoT disables Android cloud backup. Its Android backup and device transfer rules exclude the app’s preferences and databases, including device registrations, encrypted credentials, and learning progress. [Android backup behavior](https://developer.android.com/identity/data/autobackup)

## Questions and changes

Contact the publisher above with privacy questions. If the app’s data practices change, the publisher will update this policy and its effective date.
