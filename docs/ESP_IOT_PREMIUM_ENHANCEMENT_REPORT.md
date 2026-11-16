# ESP IoT premium visual, motion and learning enhancement report

Date — 12 November 2026, Asia/Dhaka. Flutter 3.47.5, Dart 3.13.4. Package `com.samir.esp_iot`, unchanged.

**Status legend.** PASS = executed and passed. NOT TESTED = not executed. PARTIAL = done for some cases only.

> **Headline.** The design system, brand mark, status language, animated wiring tutorial, checkpoint quizzes and a 3D board explorer are implemented and merged into the existing lesson and device flows. `flutter analyze` is clean and all **85** automated tests pass, up from 71. No existing feature was removed. The animated wiring playback and the light theme are both **verified on the physical Samsung SM-E236B** (Android 14) as well as by test — see §9 and [the captured frames](evidence/wiring-playback.png).

---

## 1. What was changed

| Area | File | Lines |
| --- | --- | ---: |
| Design system, dual palette, theme mode | [app_theme.dart](../app/lib/app/app_theme.dart) | 398 |
| Brand mark and animated logo | [esp_mark.dart](../app/lib/core/ui/esp_mark.dart) | 293 |
| Status language (dots, chips, beacon, skeletons, tick) | [status_visuals.dart](../app/lib/core/ui/status_visuals.dart) | 347 |
| Animated wiring tutorial | [learn_wiring_player.dart](../app/lib/features/learn/learn_wiring_player.dart) | 295 |
| Checkpoint quizzes | [learn_quiz.dart](../app/lib/features/learn/learn_quiz.dart) | 364 |
| Arduino app links | [learn_companion_apps.dart](../app/lib/features/learn/learn_companion_apps.dart) | 231 |
| Play Store bridge | [AppListingBridge.kt](../app/android/app/src/main/kotlin/com/samir/esp_iot/AppListingBridge.kt) | 65 |
| 3D board explorer | [learn_board_3d.dart](../app/lib/features/learn/learn_board_3d.dart) | 409 |
| Playback tests | [wiring_player_test.dart](../app/test/wiring_player_test.dart) | 146 |
| Palette goldens | [theme_golden_test.dart](../app/test/theme_golden_test.dart) | 131 |

Smaller edits touched Home, the workspace shell, Settings, the device card, the connection screen, the wiring diagram and the lesson screen. App code grew from about 16.3k to 18.4k lines; tests from 4.3k to 4.0k files plus two new suites (85 tests total).

---

## 2. Design system

**Before**, colours were compile-time constants in one dark-only class, with 68 hard-coded hex values scattered across 12 files and no light theme.

**Now** there is an `AppPalette` with named roles (background, surface, elevated, sunken, line, text, muted, cyan, blue, violet, mint, amber, coral, onAccent, navigation, shadow) in two complete sets, dark and light. `AppColors` reads the active palette, and `AppPaletteScope` swaps it and repaints the tree. Two helpers, `AppColors.tint()` and `tintLine()`, replace hand-mixed fills so a tinted surface is always derived from the palette rather than guessed.

Structural hex values in the nav bar, hero, code wells, pin explorer, upload guide and reward panels were converted to roles. The remaining literals are deliberate: the brand mark's own gradient, the Learn illustrations, and the wire colour names (red, green, yellow, violet, black) which describe physical jumper wires and must not change with the theme.

`AppShape` fixes the corner radii (control 14, card 20, hero 26, well 16) that were previously repeated as magic numbers.

A **light theme** is implemented and selectable in Settings (Dark / Light / System), saved to preferences. Rendered proof is checked in at [palette_light.png](../app/test/goldens/palette_light.png) and [palette_dark.png](../app/test/goldens/palette_dark.png), and the on-device comparison is at [themes.png](evidence/themes.png).

**Verified on the Samsung:** switching to Light repaints the whole workspace — white cards, dark text, light nav bar, light status-bar icons — and switching back to Dark restores it.

**Light theme caveat:** it is built and legible, but the product is designed around the dark workspace. The Learn illustrations, the circuit canvas and the brand tile stay dark in both themes by design, so a light-mode Home shows a dark illustration on a light card. Light mode is a supported alternative, not an equal partner.

---

## 3. Brand identity

The old mark was a generic Wi-Fi glyph inside a chip outline — close to the stock "wireless" icon the brief asked to avoid.

The new mark is an **"E" drawn as three circuit traces**: the outer two terminate in open pads, the short middle trace reaches toward a solid violet node. It reads as both a letter and a bus with a connected device, is distinct in silhouette, and survives down to 48 px.

Delivered:

| Asset | Where |
| --- | --- |
| Vector mark | `mipmap-anydpi/espiot_mark.xml` |
| Adaptive icon (background, foreground, monochrome) | `drawable/espiot_launcher_*.xml` |
| Raster launcher icons, 5 densities, plus round variants | `mipmap-{m,h,xh,xxh,xxxh}dpi/` |
| Splash | `drawable-v31/espiot_splash_motion.xml`, existing animator |
| In-app painter | `paintEspMark()` in `esp_mark.dart` |

The in-app logo animates: traces draw outward from the middle, the short arm extends, pads appear, then it floats gently while a halo breathes, a light sweeps diagonally across the plate, and the node pulses. It never spins. One-shot on entry; the launch screen is the only place it loops.

Verified on device: the mark renders in the app bar, inside the orbiting chip artwork, and on the Android 12+ splash.

---

## 4. Motion and micro-interactions

A deliberate decision shaped this section. The existing codebase avoids permanently running animations on main screens, and the brief asks for smoothness on mid-range phones. My first implementation gave every status indicator a permanent pulse; it made `pumpAndSettle` hang in four existing tests and would have burned battery for no information.

The rule now: **a steady state pulses once on arrival and rests; only a genuinely in-progress state loops.**

| Element | Behaviour |
| --- | --- |
| `StatusDot` | One expanding ring when the state changes; continuous only while connecting |
| `ConnectionBeacon` | Same, at tile size, with a tone-matched icon |
| `StatusChip` | Tinted pill with dot, used on device cards |
| `SkeletonBox` | Shimmer while counts load |
| `SuccessTick` | Draws a check once on a confirmed answer |
| `MotionValue` | Existing cross-fade, now used for live counts and Wi-Fi address |

Four states are visually distinct by colour, icon and motion: **live** (mint, link, breathing), **waiting** (cyan, sensors, outward rings), **idle** (muted, wifi-off, still), **fault** (coral, error, single pulse). `SessionPhase` and `DevicePresence` each map to a tone, so every screen shows the same state the same way.

All decorative motion still routes through the existing `DecorativeMotion`, which stops offstage and under reduced motion.

---

## 5. Home dashboard

- Time-of-day greeting in the eyebrow.
- Hero gradient now palette-driven with a layered shadow and the hero corner radius; it adapts to light mode instead of being fixed dark.
- Count tiles show a shimmer while the registry loads instead of an em dash, animate the number on change, and carry a live dot when devices are connected.
- Network panel is tone-aware: icon, text and dot change together for available / checking / unavailable. Confirmed on the emulator showing the coral fault state, and on the phone showing the live state with the real subnet.
- A Learn & Build shortcut card was added at the foot of Home, as the brief asked.

---

## 6. Learn & Build

### 6.1 Animated wiring tutorial — the headline feature

`LearnWiringPlayer` sits at the top of the wiring stage. It plays the project's connections **in build order**, one every 1.5 s, drawing each wire along its real path. When the last wire lands, the caption changes to "Circuit complete", a live chip appears, and charge markers begin sliding along every wire to show the direction current flows.

It is built entirely on the lesson's **existing validated circuit data** — the same `LearnCircuit` that already rejects overlapping paths, wires that cross unrelated nets, and coordinates outside the board. The player cannot invent a connection the lesson does not define. No generated imagery is involved.

Controls: play/pause, previous, next, replay, a progress bar, and a live-region caption naming both terminals plus the lesson's own reason for that wire. Under reduced motion the whole thing becomes a stepper, with the button tooltip and icon changing to match.

Three real defects were found and fixed by writing tests for it:

1. The caption and progress bar were outside the animation listener, so they lagged behind the drawing. The whole panel is now driven by one `AnimatedBuilder`.
2. Stepping backwards from a completed wire stayed on the same wire, because of a leftover "part-way" rule.
3. A floating-point round-trip (`(n+1)/count × count` landing just above a whole number) pushed the index onto the next wire, so stepping skipped one. Fixed with an explicit tolerance.

### 6.2 Checkpoint quizzes

A new **Check yourself** stage after the code stage. Questions are generated from the project's own data — which terminal the first connection starts from, which component a named wire reaches, and a safety question drawn from the lesson's own warnings — with distractors taken from other real parts and pins in the same project. Choosing an answer reveals the right one, marks the wrong one, and shows the explanation, which for wiring questions is the lesson's existing "why" text.

### 6.3 Arduino's mobile apps on Google Play

The upload stage now ends with a card linking Arduino's own Android apps, so a learner can reach them in one tap:

| App | Play Store id | What it is for |
| --- | --- | --- |
| Arduino IoT Cloud Remote | `cc.arduino.cloudiot` | Watching and controlling an Arduino Cloud dashboard from a phone, once a board is already running |
| Arduino Science Journal | `cc.arduino.sciencejournal` | Recording and graphing readings from the phone's own sensors |

Both were checked on the live Play Store before being added: published by **Arduino**, currently listed, and actively maintained (IoT Cloud Remote was updated on 9 November 2026).

**An accuracy point that shaped the copy.** There is **no official Arduino IDE on Google Play**, and neither of these apps can compile or upload a sketch to an ESP32 — IoT Cloud Remote is a dashboard client, and dashboards are built on a computer. Telling a beginner otherwise would cost them hours. The card therefore states in its own first paragraph that uploading still needs the Arduino IDE on a computer, and a test asserts that sentence stays there.

**How the link is opened.** Dart passes only an application id over a new `esp_iot/app_listing` channel; the Kotlin side validates it against the Android package grammar and builds the store address itself, so this channel cannot be used to open an arbitrary URL. It tries `market://` against `com.android.vending` first and falls back to the web listing, reporting a failure to the user if neither opens. No new permission and no new Dart dependency were needed.

### 6.4 3D board explorer

A rotatable ESP32-DevKitC on the **Know your ESP32 board** stage. Drag to turn, pinch-free zoom buttons, reset view, and tap any pin for its role description. Pins the current project uses are highlighted; role colours separate power, ground, analog, serial and plain GPIO. Geometry is projected by hand from a handful of flat faces — no 3D engine, no model assets — so it stays cheap on a mid-range phone. Pin positions come from the catalog's real `headers` data, 19 per header.

Verified on the emulator: the board renders with its shield can, USB connector, gold header pins and the project's pins highlighted in cyan.

---

## 7. Device and control surfaces

PARTIAL. Device cards now use `StatusChip` instead of coloured text, and the connection screen uses `ConnectionBeacon` with a tone-coloured phase label. The brief's **robot controller joystick**, **sensor monitor graph overhaul** and **serial monitor** were **NOT** implemented — the first two do not exist as separate modules in this codebase (sensor trends are already drawn in the dashboard), and there is no serial monitor module at all. The existing discovery radar was left as it was; it already animates a sweep with contact blips.

---

## 8. Accessibility and performance

- Reduced motion is honoured everywhere new, including the wiring player's stepper fallback, and is covered by a test.
- New interactive elements carry tooltips and semantics; the wiring caption is a live region; status chips expose a combined label and hide their decorative parts.
- Touch targets on the transport row use `IconButton`, which meets the 48 dp minimum.
- No permanently running animation was added to any main screen.
- The Arduino app card is a labelled button with an explicit "Open … on Google Play" semantics label, and shows a spinner while the store is opening.
- Every new `AnimationController` is disposed; the player disposes both of its controllers.
- Contrast in the light palette was chosen for dark text on white cards; **it has NOT been measured against WCAG ratios**.

---

## 9. Testing

| Check | Result |
| --- | --- |
| `flutter analyze` | **PASS** — no issues |
| `flutter test` | **PASS** — 85 tests (was 71) |
| Wiring playback: order, pause, replay, reduced-motion stepping | **PASS** — 4 new tests |
| Wiring playback completes for all 7 bundled projects | **PASS** |
| Light and dark palette rendering | **PASS** — golden images checked in |
| New brand mark on device (app bar, artwork, splash) | **PASS** on Samsung SM-E236B |
| Home dashboard, status colours, Wi-Fi live state | **PASS** on Samsung |
| Wi-Fi fault state | **PASS** on Android 16 emulator |
| Wiring player rendering and stepping | **PASS** on emulator |
| 3D board explorer | **PASS** on emulator |
| Quiz stage present in lesson navigation | **PASS** on emulator |
| **Wiring animation playing on a physical phone** | **PASS** — captured at three points: first wire drawing, last wire drawing, and complete with current flowing ([evidence](evidence/wiring-playback.png)) |
| Light theme on a physical device | **PASS** — Settings → Light repaints Settings and Home; Dark restores ([evidence](evidence/themes.png)) |
| Time-of-day greeting on device | **PASS** — showed "GOOD MORNING" at 11:04 |
| Quiz stage renders on a device | **PASS** on the Samsung |
| Quiz answered end-to-end on a device | **NOT TESTED** |
| Arduino app card renders, opens Play, returns cleanly | **PASS** on the Samsung — the Play Store app opened on the Arduino IoT Cloud Remote listing and back returned to ESP IoT without a crash ([evidence](evidence/arduino-app-link.png)) |
| 3D board pin tap on a device | **NOT TESTED** |
| Frame timing / FPS measurement | **NOT TESTED** |
| Real ESP32 of any kind | **NOT TESTED** — no hardware |

**Device evidence.** The playback was captured on the Samsung at three points: the first connection part-drawn with the pause icon showing and the progress bar about a quarter full; the third connection part-drawn with the bar about four-fifths full; and the finished circuit with charge markers spaced along the ground return. Timings matched the 1.5 s per connection the player is built around.

**What is still only covered by test.** Pause, replay and the reduced-motion stepper were exercised in the widget suite but not tapped through on the phone. No frame-timing measurement was taken.

---

## 10. Before and after

Two evidence images are published, cropped to exclude personal notifications: [wiring-playback.png](evidence/wiring-playback.png) (three stages of the animation on the Samsung) and [themes.png](evidence/themes.png) (dark Home, light Home, light Settings on the Samsung). The visual differences that matter:

| | Before | After |
| --- | --- | --- |
| Logo | Wi-Fi glyph in a chip outline | "E" drawn as circuit traces with a connected node |
| Themes | Dark only | Dark, light, and follow-system |
| Colour | 68 hard-coded hex values, dark-only constants | Role-based dual palette with tint helpers |
| Device status | Coloured text label | Dot + chip + beacon, four distinct tones with motion |
| Loading counts | Em dash | Shimmer placeholder |
| Wiring lesson | Static diagram, step through wires manually | Plays itself in build order, then shows current flow |
| Lesson stages | 9 | 10, with a checkpoint quiz |
| Board stage | Text plus a 2D pin list | Rotatable 3D board with tappable, project-highlighted pins |

---

## 11. Remaining limitations

1. **Robot controller, sensor monitor and serial monitor were not built** — they are not present in this codebase, and inventing them was outside a visual enhancement pass.
2. **Circuit Lab and Code Studio** were not rebuilt. The existing wiring lab and sketch viewer were kept and extended rather than replaced.
3. **Light theme is secondary.** The Learn illustrations and circuit canvas stay dark in both themes.
4. **Golden tests may be brittle** across machines with different font rendering. If `theme_golden_test.dart` fails elsewhere, regenerate with `flutter test --update-goldens` after reviewing the image.
5. **No frame-timing data.** `dumpsys gfxinfo` does not see Flutter's own render surface, and no profile build was run.
6. **Leaving the app is now possible** from the upload stage, via Google Play. No user data is sent — only an application id, to the local Play Store app. Worth a line in the privacy audit when that document is next revised.
7. The version was `1.0.1+2003` when this pass finished; versioning is being managed elsewhere in the repo and I did not change it.
