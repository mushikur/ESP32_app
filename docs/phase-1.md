# ESP IoT Phase 1 interface

Phase 1 adds the visual system and app navigation. The dashboard begins with an empty inventory, zero registered devices, and an unavailable Wi-Fi status. The Discover screen previews the supported connection methods. Automation and activity pages explain where future device data will appear.

## What changed

| Area | Files and behavior |
| --- | --- |
| App shell | [main.dart](../app/lib/main.dart), [app theme](../app/lib/app/app_theme.dart), [router](../app/lib/app/app_router.dart), and [workspace shell](../app/lib/app/workspace_shell.dart). Six sections share a dark Material 3 theme and animated navigation. Large text on narrow screens gives the navigation two rows. |
| Visual identity | [Flutter artwork](../app/lib/core/ui/esp_artwork.dart) and [Android resources](../app/android/app/src/main/res/). The chip mark appears in the app, launcher, and splash. Canvas artwork supplies the depth and motion without a 3D runtime. The active tour slide animates when system motion settings allow it. [Android adaptive icons](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive), [Android splash screens](https://developer.android.com/develop/ui/views/launch/splash-screen) |
| First run | [Onboarding](../app/lib/features/onboarding/) provides a three-page tour with swipe, Next, Back, and Skip. Settings can replay it. SharedPreferencesAsync stores one versioned completion flag. It was introduced in this phase for the tour. [Shared Preferences](https://pub.dev/packages/shared_preferences) |
| Workspace | [Home](../app/lib/features/home/home_screen.dart), [device card](../app/lib/features/devices/device_card.dart), and [section screens](../app/lib/features/workspace/workspace_screens.dart). The reusable device card appears in the tour as an illustration. The inventory contains only paired records once pairing is available. |
| Tests | [Widget tests](../app/test/app_smoke_test.dart) cover launch, tour completion and relaunch, skipping after a preference write failure, replay, six sections, motion, and tap target checks at 320 dp with 200 percent text size. |

## Run the app

Run these PowerShell commands from the workspace root with an Android phone or emulator available.

```powershell
Set-Location .\app
flutter pub get
flutter devices
flutter run -d <android-device-id>
```

Build and check the debug preview from the same folder.

```powershell
flutter analyze
flutter test
flutter build apk --debug
```

The debug APK is written to `app/build/app/outputs/flutter-apk/app-debug.apk`. The provisional application ID remains `com.example.esp_iot`.

The Android build disables incremental Kotlin compilation because the Windows package cache and project live on separate drives. The first build installed Android SDK Platform 35 and CMake 3.22.1 for the plugin dependencies. [Kotlin build settings](https://kotlinlang.org/docs/gradle-compilation-and-caches.html#incremental-compilation)

## Verification

- Dart formatting, Flutter analysis, all six widget tests, and the Android debug build passed. The widget tests cover the normal and reduced-motion tour, completion and relaunch, Settings replay, all six sections, storage failure, startup loading, and accessibility on a narrow layout.
- The Android 16 `small_phone` emulator ran all three onboarding pages, opened all six sections, replayed the tour from Settings, and kept the completion flag after a force-stop and relaunch. The emulator was tested with hardware graphics after its software-rendered instance exited.
- The Phase 0 protocol suite still passes all ten descriptor checks.
- Phone-sized renders were reviewed for onboarding, the illustrative card, Home, and Discover. The primary button, panel copy, and selected navigation colors each have a contrast ratio above 8:1 against their paired backgrounds.
- Physical Android and ESP32 tests remain pending.

## Next phase

Phase 2 connects the Discover screen to Android network permissions, mDNS, and the ESP IoT UDP discovery protocol. Add manual address and QR entry, validate and deduplicate candidates, and test discovery on a physical Android phone and ESP32 boards on the same Wi-Fi. Live control, device history, and automation depend on the later transport and persistence phases.
