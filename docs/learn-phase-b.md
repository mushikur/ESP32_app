# ESP32 Learn & Build Phase B

Open **Learn**, choose a project, and select **Start building** or **Continue building**.

- **Gather the components** has a checklist for each part or kit item. The app saves each check as you go.
- **Know your ESP32 board** opens the pin explorer for the ESP32-DevKitC V4 with ESP32-WROOM-32E. Face the module toward you with USB at the bottom. J2 is on the left and J3 is on the right. Tap a header position to read its function. The explorer highlights the exact positions used by the lesson and identifies the flash pins and the USB power restriction. [Espressif header reference](https://docs.espressif.com/projects/esp-dev-kits/en/latest/esp32/esp32-devkitc/user_guide.html#header-block)
- **Wire the circuit** shows the full schematic. Tap a wire or use the previous and next controls to trace it. Tap a component or terminal to inspect it. Pinch or use the zoom buttons, drag to pan, and tap **Fit circuit** to return to the overview. **All connections** and **Inspect components** provide text controls for the same selections.
- Mark a connection after checking the physical circuit with the power disconnected. A junction dot shows where wires join. The schematic shows electrical connections. Use the written steps to place legs on connected breadboard rows and identify the labeled headers on the real board.

The five Phase A lessons use the same bundled sketches and electrical connections. The app records the parts and wiring milestones when every item in the respective checklist is checked. A completed Phase A milestone opens with its corresponding checklist already checked. You can uncheck an individual item and recheck it later. Upload and hardware behavior remain separate learner confirmations.

## Maintain a diagram

The project file contains both the original `wires` and a `wiringLayout`. The layout supplies geometry for the existing electrical connections.

1. Set the canvas `size` and give each wired component a `rect` in left, top, width, height order. Add the component’s terminal names to the `left` and `right` lists in top-to-bottom order. The renderer spaces those terminals evenly along the corresponding side.
2. For each connection that needs a turn, add ordered `[x, y]` points to `bends`. Key the entry as `fromPart.fromPin>toPart.toPin` using the same direction as the wire record. The renderer derives the first and last points from the terminal positions. Keep routes horizontal or vertical and clear of components. Where paths on a shared net branch, place a bend or endpoint at the junction.
3. Use the board header data in `catalog.json` for physical pin positions. A row’s optional `terminal` field assigns the lesson reference to that exact header position. Add any new lesson references to the board part’s pin list. Keep project, component, and wire IDs stable when editing a diagram so saved checklist items still match.
4. Run the catalog tests and inspect the diagram at fit and zoomed scales. Check the physical circuit with the listed components before marking a lesson bench-tested.

Catalog loading validates terminal coverage, route geometry, component bounds, and overlapping paths on separate nets. The original wiring tests still check the expected physical endpoints for every lesson.

## Run the checks

From `app`, run the following commands with the installed Flutter SDK.

```powershell
flutter analyze
flutter test
flutter build apk --debug
```

Analysis reported zero issues, all 53 Flutter tests passed, and the Android debug APK built. On a small Android emulator without an active network, the Blink lesson opened its schematic and pin explorer, showed IO34 as an ADC input, and restored the saved connection after restart. The lab opened on the first unchecked wire. Physical circuit checks remain pending.

For the circuit bench test and sketch build commands, see [Phase A setup](learn-phase-a.md#build-and-test). Phase C adds source download, interactive code explanations, and an illustrated Arduino IDE walkthrough.
