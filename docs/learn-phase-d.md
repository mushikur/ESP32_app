# ESP32 Learn & Build Phase D

Open **Learn** and choose a starter lesson. Under **Test the project**, perform each action on your circuit, compare it with the expected result, and check **I observed this result**. The app saves each result on the phone. Completing the components, wiring, upload, and test checkpoints finishes the project.

If something behaves differently, choose **Troubleshoot a result**. Open the symptom that matches what you see. Each card describes a possible cause, what to check, and how to fix it. **Show related wiring** opens the exact connection in the interactive schematic. Return to troubleshooting or the test checklist from there. For compile or USB upload issues, use the Arduino IDE walkthrough’s troubleshooting cards. [Espressif DevKitC V4 guide](https://docs.espressif.com/projects/esp-dev-kits/en/latest/esp32/esp32-devkitc/user_guide.html) · [Phase C upload guide](learn-phase-c.md#arduino-ide-walkthrough)

## Progress and rewards

| Feature | Rule |
| --- | --- |
| Project completion | All four checkpoints are checked. The completion card links to the next unfinished lesson. |
| XP | The first completion of each project earns 100 XP. Reviewing or rechecking a completed project keeps its original reward. |
| Daily goal | Mark one unchecked component, connection, upload, or test result today. |
| Learning streak | Consecutive days with a saved check count using the phone’s calendar. A streak from yesterday remains current until today ends. |
| Skill progress | Currently completed projects count toward lighting, sensors, and motors. |
| My Projects | Opened, in-progress, and completed lessons are available from the Learn dashboard. |

Open **Achievements** to see First Circuit, LED Master, Sensor Explorer, Servo Starter, and ESP32 Creator. All five can be earned with the starter library. Every lesson is available from the start. The completion card recommends what to build next.

Progress saved by earlier releases carries forward. A previously checked test checkpoint opens with its individual results checked. Previously completed projects earn their XP and badges. Daily streaks use checks recorded with a date. Progress and rewards work offline.

## Maintain a lesson

Each `checks` entry in the lesson JSON has a stable `id` plus localized `title`, `action`, and `expected` fields. Keep those IDs stable so saved checks follow the correct test. Each troubleshooting entry has localized `symptom`, `cause`, `inspect`, and `fix` fields, plus a `wireId` matching the relevant connection in the existing schematic. The catalog rejects duplicate test IDs and unknown wire references.

## Run the checks

From `app` run:

```powershell
flutter analyze
flutter test
flutter build apk --debug
```

Flutter analysis reported zero issues, all 59 Flutter tests passed, and the Android debug APK built. Tests covered individual result tracking, earlier saved checkpoints, one-time XP, calendar-day streaks, and troubleshooting links for the existing schematic.

On the offline Android emulator, the Blink lesson showed separate test results, the 100 XP completion card, and the Push Button LED recommendation. The LED troubleshooting card opened the anode connection. An offline restart restored the completed project, XP, daily goal, one-day streak, and First Circuit badge.

Physical circuit checks remain pending. Use the parts and power instructions in each lesson and the [Phase A bench guide](learn-phase-a.md#build-and-test). Each checked result is the learner’s observation from the circuit.

Phase E adds wiring practice, more projects, and optional simulator integration.
