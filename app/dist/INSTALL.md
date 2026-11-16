# Installing ESP IoT

ESP IoT is shared as an APK file rather than through the Play Store, so Android will ask you to confirm the install once. The steps below are all you need.

## What you need

- An Android phone or tablet running **Android 7.0 or newer**.
- Enough free space to download and install the APK.
- A **Wi-Fi network** — ESP IoT only talks to devices on your local network, never over mobile data.

## Install

1. **Download** the signed [ESP IoT 1.0.1 APK](../build/distribution/ESP-IoT-1.0.1-2003.apk) to the phone.
2. **Open** it — tap the finished download, or find it in Files under *Downloads*.
3. Android will likely say it **can't install apps from this source**. Tap **Settings** on that message, turn on **Allow from this source** for the app you downloaded with (Chrome, Files, Drive…), then press back. You only do this once, and you are allowing that one app to install — not turning off Android's protection.
4. Tap **Install**.
5. If Play Protect blocks installation, check the APK with the person who provided it.
6. Open **ESP IoT**.

## First run

- The welcome tour explains the workspace. You can skip it and replay it later from **Settings → Replay introduction**.
- ESP IoT asks for **camera access only when you open the pairing QR scanner**. If you decline, use **Discover → Manual address** instead — nothing else needs the camera.
- No account, no sign-in, no subscription.

## Connect an ESP32

1. Put the phone and the board on the **same Wi-Fi network**, and make sure Wi-Fi is the connection Android is actually using.
2. Open **Discover**. Compatible boards running the ESP IoT firmware appear on their own.
3. If a board does not appear, use **Manual address** and type its private IP (for example `192.168.1.100`), or scan its pairing QR.
4. Tap a device to register it, then open it to control it.

Your boards need the ESP IoT firmware library, or a connection profile you set up yourself for a project with its own REST or WebSocket API. An arbitrary ESP32 web page cannot be controlled automatically.

No ESP32 yet? **Learn & Build** has seven guided projects with wiring diagrams and code, and needs no hardware to read through.

## Updating later

Install the newer APK over the existing release to keep devices, settings and learning progress. Android requires the same package ID and signing certificate and a version code at least as high as the installed release. Build `2003` follows builds `1`, `1001`, `2001` and `2002` of the signed `com.samir.esp_iot` release.

If Android reports a signature mismatch or downgrade, keep the installed app and obtain an APK signed for the same package and certificate with a suitable version code. The older `com.example.esp_iot` debug app has its own installation and local data.

## If something goes wrong

| Problem | What to do |
| --- | --- |
| "App not installed" | Check free space, Android version and the APK version and signature. Keep the installed app while checking. |
| "Can't install from this source" | Step 3 above — allow the app you downloaded with. |
| No devices found in Discover | Confirm the phone is on Wi-Fi and that Wi-Fi is the active connection; some guest and corporate networks block devices from seeing each other. |
| Scanner will not open | Camera access was denied. Android Settings → Apps → ESP IoT → Permissions → Camera, or just use Manual address. |

## Privacy in one paragraph

ESP IoT has no account and no cloud service. Device addresses, activity history and learning progress stay on your phone. API credentials and pairing tokens are stored encrypted. Authentication is never sent over an unencrypted connection. The QR scanner uses Google ML Kit, which processes scans on the device and may send Google its own diagnostic and usage metrics. See the [privacy policy draft](../../docs/PRIVACY_POLICY_DRAFT.md) for the full statement.
