# ESP IoT Google Play submission checklist

Use this checklist for ESP IoT 1.0.1, build 2003. The Play account owner should complete the items marked **Owner** and review the draft answers against the exact bundle submitted.

## 1. Prepare the bundle and signing

| Item | Current evidence or action |
| --- | --- |
| Application | ESP IoT, package `com.samir.esp_iot`, Android 7.0 minimum (API 24), Android 16 target (API 36). API 36 meets the phone and tablet submission rule effective 31 August 2026. Confirm the package is available in the intended Play Console account. [Current target API requirement](https://developer.android.com/google/play/requirements/target-sdk) |
| Candidate bundle | [ESP-IoT-1.0.1-2003.aab](../app/build/distribution/ESP-IoT-1.0.1-2003.aab), verified package `com.samir.esp_iot` and established release signer. SHA-256 `C0D64A947BD4862F74022A4C5D40F86D5304D6C6B0DA86FE1E3FAF851C751C03`. Bundletool validation passed. [Release build instructions](../app/README.md#release-builds) |
| App signing **Owner** | Enroll in Play App Signing and decide which certificate will sign Play installs. To preserve in-place updates for users of the existing signed APKs, use the existing ESP IoT production key as the **app-signing key**. Follow the Console’s encrypted key import flow. Keep the app-signing key backed up privately. A separate upload key can be registered for subsequent bundles. [Play App Signing](https://developer.android.com/studio/publish/app-signing) |
| Version code **Owner** | Build `2003` is above the earlier signed releases at `1`, `1001`, `2001` and `2002`. Keep increasing the code for future releases. Play installs also need the existing app-signing certificate for an in-place update from those APKs. The older `com.example.esp_iot` build remains a separate installation. [Historical release artifact version matrix](ESP_IOT_FINAL_RELEASE_REPORT.md#14-release-artifacts) |
| 64-bit native library and page size | Build 2003 passed the [16 KiB static checks](play-store/native-page-alignment.md) on both signed artifacts. The AAB declares `PAGE_ALIGNMENT_16K`. All 28 ARM64 and x86-64 library entries across the APK and AAB passed ELF load alignment, and the APK passed ZIP alignment. Runtime validation on a 16 KB Android device remains open. [16 KB Android guidance](https://developer.android.com/guide/practices/page-sizes) |

If the owner chooses a Google-generated **app-signing key**, the existing sideload APKs will have a different signature. Plan the transition with testers before enrolling. The upload key authenticates future uploads. It does not determine which signature users receive. [Play App Signing across distribution channels](https://developer.android.com/guide/app-bundle/faq)

Use the [official bundletool](https://developer.android.com/tools/bundletool) on the final candidate from the workspace root. Substitute its installed path and the actual candidate filename.

```powershell
$bundletool = 'C:\path\to\bundletool.jar'
$candidate = 'app/build/distribution/ESP-IoT-1.0.1-2003.aab'
java -jar $bundletool validate "--bundle=$candidate"
java -jar $bundletool dump manifest "--bundle=$candidate" --module=base
java -jar $bundletool dump config "--bundle=$candidate"
```

Confirm package name, SDK levels, version code, camera optionality and permissions in the manifest, and `PAGE_ALIGNMENT_16K` in the bundle configuration. On the 16 KB test device, check `adb shell getconf PAGE_SIZE` for `16384`, then run the install and smoke checks with the Play-generated or bundletool-generated APKs.

## 2. Complete the listing and App content

| Play Console item | Draft or owner action |
| --- | --- |
| Publisher **Owner** | Enter [legal publisher name], [public support email], [privacy contact], and any identity or organization information requested by the Console. Confirm [supported countries], [pricing], and [target audiences]. A new personal account may also need the owner to verify a physical Android device using the Play Console mobile app. [Developer device verification](https://support.google.com/googleplay/android-developer/answer/14316361) |
| Default listing | Suggested name **ESP IoT**. Suggested short description **Control your ESP32 projects over local Wi-Fi and learn electronics.** Choose the appropriate app category and languages for the published listing. |
| Preview assets **Owner** | Provide the approved 512 × 512 Play icon, a 1024 × 500 feature graphic, and at least two accurate screenshots of the released app. The feature graphic and screenshots accept JPEG or 24-bit PNG without alpha. For screenshots, the shorter side must be at least 320 px, the longer side at most 3,840 px and no more than twice the shorter side. Raw 1080 × 2408 phone captures exceed that aspect limit. Use suitable viewport dimensions or crop and recheck the content. Remove personal data, Wi-Fi identifiers and credentials. Provide tablet assets where applicable. [Play preview asset requirements](https://support.google.com/googleplay/android-developer/answer/9866151) |
| Privacy policy **Owner** | Replace the publisher, contact and effective-date placeholders in the [privacy policy draft](PRIVACY_POLICY_DRAFT.md). Host the reviewed policy on a public, login-free, non-editable HTTPS webpage. Enter [public privacy policy URL] in Play Console and make the policy available from the app. **Settings → Privacy and permissions** already presents the on-device explanation. Add the finalized policy link there when its URL is available. [Privacy policy and App content](https://support.google.com/googleplay/android-developer/answer/9859455) |
| Ads | Draft answer **No ads** based on the inspected app and dependencies. ML Kit diagnostic telemetry is separately disclosed under Data safety. Verify again for the submitted build. |
| App access **Owner** | No ESP IoT account or sign-in. Describe the hardware and network prerequisites in the reviewer instructions. Supply a reproducible way to review device-dependent behavior if requested. Use an authorized test device or a clearly labeled fixture, and keep private network details and real credentials out of the listing. |
| Content rating and audience **Owner** | Complete the official questionnaire using the shipped content and accurately declare the intended ages. Learn & Build includes electronics lessons. The owner determines the target audience and reviews the applicable Families requirements if children are included. [App content declarations](https://support.google.com/googleplay/android-developer/answer/9859455) |
| Permissions | `CAMERA` is for optional QR scanning. Manual address entry remains available. `INTERNET`, `ACCESS_NETWORK_STATE`, and `CHANGE_WIFI_MULTICAST_STATE` support the configured LAN connection and discovery. Review the final permissions shown in Console. [Permissions and privacy audit](ESP_IOT_RELEASE_PRIVACY_AUDIT.md) |
| Account deletion | Draft **No app account creation**. Local board pairing and an optional device API username are separate from an ESP IoT account. Answer the remaining Data deletion questions accurately. Local device removal and clearing app storage are described in the privacy policy. [Play account deletion requirements](https://support.google.com/googleplay/android-developer/answer/13327111) |

### Draft full description

Connect to compatible ESP32 projects on your local Wi-Fi. Discover supported ESP IoT devices, scan a pairing QR, or enter a local address. View device status and readings, use supported dashboard controls, and review recent activity. Legacy HTTP and WebSocket devices require a compatible API and an explicit connection profile.

Use Learn & Build to practice ESP32 wiring, explore board pins, follow guided projects, and save Arduino sketches. The lessons and progress are available on your device without an ESP IoT account. Arduino upload and the serial walkthrough use a computer.

### Draft reviewer instructions

Open ESP IoT and finish or skip the welcome tour. Open **Learn & Build** and select a lesson to view its wiring, code and troubleshooting guide. This flow requires no ESP32. In **Discover**, camera permission is requested only for the optional pairing QR workflow. **Manual address** can be used without the camera.

Device controls require a supported ESP32 on the same reachable private IPv4 Wi-Fi. Use the owner-provided [approved review setup] and [device or fixture instructions] for discovery, device status, pairing and controls. A device must support the ESP IoT protocol or provide a compatible configured API. Use a low-risk output or a simulation for command checks.

## 3. Draft Data safety responses

**Does the app collect or share required user data types?** Start with **Yes for collection**. Play counts off-device transmission by SDKs as collection even when it goes directly to another company. The bundled Google ML Kit scanner processes camera inputs and QR results on the device. Its Android SDK documentation separately describes transmitting metrics to Google over HTTPS. [Play Data safety definitions](https://support.google.com/googleplay/android-developer/answer/10787469) · [ML Kit Android data disclosure](https://developers.google.com/ml-kit/android-data-disclosure) · [ML Kit terms and privacy](https://developers.google.com/ml-kit/terms)

| Data safety candidate | Why it may apply | Draft handling |
| --- | --- | --- |
| Device or other IDs | Google documents a per-installation identifier for bundled ML Kit features. | Disclose collection. Review the purpose as analytics and the handling described by the SDK. |
| App info and performance | Google documents device and app details, scanner configuration, sizes and latency, feature version, and error information. | Disclose under the applicable diagnostics and other performance categories. Review the documented uses for analytics and troubleshooting. |
| App activity | Google documents feature event types, including scanner initialization, detection and release. | Map any recorded interaction events to the applicable App activity categories. Avoid declaring collection of the QR payload itself as a metric. |
| QR camera frames and decoded contents | The scanner processes these on the device. Scanning a supported QR can supply the board endpoint for a separately confirmed LAN request. | Separate the on-device scan from the subsequent device connection. Review actual LAN payloads for data transmitted off the phone. |
| Device setup, telemetry, and commands | Device identifiers and requests can cross the LAN to the user’s configured board. TLS and approved plaintext profiles have different transmission properties. | Review the actual payload and applicable Play collection, sharing, encryption and ephemeral definitions. Keep unencrypted device operations explicit in the policy. |
| App-private stores | Registered boards, activity, lesson progress, and encrypted credentials are stored on-device. The credential may later be used in an authenticated LAN request. | On-device storage alone does not count as collection. Evaluate each off-device use separately. |
| Sketch and link export | A selected sketch can go to a user-selected document provider. **Copy** places the selected sketch or link on the Android clipboard. | Check the scope of the specific user-initiated sharing exemption. Disclose the behavior in the privacy policy. |

- **Sharing** — Review Google’s role and the applicable Play exemption before answering. ML Kit’s statement about its downstream transfers does not decide whether the app’s transfer to Google qualifies as sharing under Play’s definitions.
- **Optional and ephemeral** — The user can skip camera scanning, but the merged build initializes the ML Kit SDK. Verify which metrics can be transmitted without using the scanner. An SDK operation’s short duration does not establish short retention of its metrics.
- **Encryption in transit** — ML Kit describes HTTPS for its metrics. ESP IoT also supports approved legacy HTTP and WS. A blanket “all collected data is encrypted” answer is appropriate only if the owner establishes that every in-scope off-device data flow satisfies that claim.
- **Deletion** — The app can clear local records and remove a pairing token from a reachable board. Confirm the publisher’s contact and process for questions about collected data. Local deletion does not prove Google’s SDK metrics can be deleted through ESP IoT.

Treat these rows as evidence for the form, then review and submit the declaration in Play Console using the final version. [Play Data safety guidance](https://support.google.com/googleplay/android-developer/answer/10787469)

## 4. Test on Play before production

1. **Owner** — Complete account and app setup. Upload the selected AAB to internal testing first. Review bundle validation, device catalog, generated APKs, reported SDK dependencies and pre-launch findings.
2. **Owner** — Verify Play installs on a fresh device and in-place updates from any supported sideload variant. Preserve registrations and learning progress where the package, certificate and version code permit an update.
3. **Owner** — Move to a closed test. A personal account created after 13 November 2023 generally needs at least 12 testers opted in continuously for 14 days before applying for production access. Confirm the account’s actual requirement in Console and retain test feedback for the application. [Google Play closed testing requirements](https://support.google.com/googleplay/android-developer/answer/14151465)
4. Exercise QR scanning and manual address, local discovery and pairing, secure and approved legacy connections, app restart and reconnect, firmware behavior, and sketch export. Use physical ESP32 hardware before treating control and pairing as hardware-verified. Add a tablet, a 16 KB test environment, and more Android versions to the existing Samsung and emulator coverage. [Release test evidence and gaps](ESP_IOT_FINAL_RELEASE_REPORT.md)
5. **Owner** — Complete the policy declarations, content rating, listing, preview assets and country selections. Review test results and decide whether to request production access and start rollout.
