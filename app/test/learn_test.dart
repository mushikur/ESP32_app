import 'dart:convert';
import 'dart:math' as math;

import 'package:esp_iot/app/app_theme.dart';
import 'package:esp_iot/features/learn/learn_board_3d.dart';
import 'package:esp_iot/features/learn/learn_catalog.dart';
import 'package:esp_iot/features/learn/learn_home_screen.dart';
import 'package:esp_iot/features/learn/learn_progress.dart';
import 'package:esp_iot/features/learn/learn_project_screen.dart';
import 'package:esp_iot/features/learn/learn_quiz.dart';
import 'package:esp_iot/features/learn/learn_rewards.dart';
import 'package:esp_iot/features/learn/learn_wiring_diagram.dart';
import 'package:esp_iot/features/learn/learn_wiring_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/test_learn.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LearnCatalog catalog;
  setUpAll(() async => catalog = await LearnCatalog.load(rootBundle));

  test(
    'lesson quizzes vary answer positions and preserve the correct options',
    () {
      for (final project in catalog.projects.values) {
        final questions = learnQuestionsFor(catalog, project);
        expect(
          questions.map((item) => item.answer),
          unorderedEquals([0, 1, 2]),
        );
        final [first, second, safety] = questions;
        expect(first.options[first.answer].en, project.wires.first.from.pin);
        final destination = project.wires[1].to.part;
        final title = catalog.parts[project.parts[destination]]!.title;
        expect(second.options[second.answer].en, '$destination · ${title.en}');
        expect(
          safety.options[safety.answer].en,
          'Unplug USB and switch off any external supply',
        );
      }
    },
  );

  for (final reduceMotion in [false, true]) {
    testWidgets(
      'wiring playback steps through every wire, reduced motion $reduceMotion',
      (tester) async {
        final project = catalog.projects['led_blink']!;
        final steps = <int>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(disableAnimations: reduceMotion),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: LearnWiringPlayer(
                  catalog: catalog,
                  project: project,
                  language: LearnLanguage.en,
                  onStep: steps.add,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final next = find.byTooltip('Next connection');
        final previous = find.byTooltip('Previous connection');
        expect(next, findsOneWidget);
        expect(find.textContaining('Connection 1 of 3 ·'), findsOneWidget);
        await _tapFinder(tester, next);
        expect(find.textContaining('Connection 2 of 3 ·'), findsOneWidget);
        await _tapFinder(tester, next);
        expect(find.textContaining('Connection 3 of 3 ·'), findsOneWidget);
        expect(find.text('Circuit complete'), findsOneWidget);
        expect(
          tester
              .widget<LearnWiringDiagram>(find.byType(LearnWiringDiagram))
              .pathPulse,
          0,
        );
        await _tapFinder(tester, previous);
        expect(find.textContaining('Connection 2 of 3 ·'), findsOneWidget);
        await _tapFinder(tester, previous);
        expect(find.textContaining('Connection 1 of 3 ·'), findsOneWidget);
        expect(steps, [1, 2, 1, 0]);

        await _tapFinder(tester, next);
        await _tapFinder(tester, next);
        await _tap(tester, 'Replay');
        expect(
          find.textContaining('Connection ${reduceMotion ? 1 : 3} of 3 ·'),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets(
    '3D board selects the nearest pin and marks the exact lesson header',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 320,
                child: SingleChildScrollView(
                  child: LearnBoard3D(
                    board: catalog.board,
                    project: catalog.projects['led_blink']!,
                    language: LearnLanguage.en,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final preview = tester.getRect(
        find.byKey(const ValueKey('learn-board-preview')),
      );
      // The 19 pin centers along J3 are evenly spaced in the default board pose.
      Offset j3Pin(int number) {
        const y = 19.5, z = 7.0, pitch = .72;
        final depth = y * math.cos(pitch) - z * math.sin(pitch);
        final height = y * math.sin(pitch) + z * math.cos(pitch);
        final scale = preview.width / 138 * (1 + depth / 900);
        final x = -48 + (number - 1) * 96 / 18;
        return preview.center + Offset(x * scale, -height * scale * .9);
      }

      await tester.tapAt(j3Pin(7));
      await tester.pumpAndSettle();
      expect(find.text('J3 · 7 · GND'), findsOneWidget);
      expect(find.text('This project uses this pin.'), findsOneWidget);

      await tester.tapAt(j3Pin(1));
      await tester.pumpAndSettle();
      expect(find.text('J3 · 1 · GND'), findsOneWidget);
      expect(find.text('This project uses this pin.'), findsNothing);
    },
  );

  test('all seven bundled circuits match their component wiring and board', () {
    const expected = {
      'led_blink': ['ESP.GPIO23:R1.1', 'R1.2:D1.A', 'D1.K:ESP.GND'],
      'button_led': [
        'ESP.GPIO23:R1.1',
        'R1.2:D1.A',
        'D1.K:ESP.GND',
        'ESP.GPIO18:SW1.A',
        'SW1.B:ESP.GND',
      ],
      'traffic_light': [
        'ESP.GPIO23:R1.1',
        'R1.2:D1.A',
        'D1.K:ESP.GND',
        'ESP.GPIO22:R2.1',
        'R2.2:D2.A',
        'D2.K:ESP.GND',
        'ESP.GPIO21:R3.1',
        'R3.2:D3.A',
        'D3.K:ESP.GND',
      ],
      'ldr_night_light': [
        'ESP.GPIO23:R1.1',
        'R1.2:D1.A',
        'D1.K:ESP.GND',
        'ESP.3V3:R2.1',
        'R2.2:LDR1.1',
        'LDR1.2:R3.1',
        'R3.1:ESP.GPIO34',
        'R3.2:ESP.GND',
      ],
      'servo_angle': [
        'ESP.GPIO18:M1.Signal',
        'PS1.+5V:M1.V+',
        'PS1.GND:M1.GND',
        'PS1.GND:ESP.GND',
      ],
      'dual_led_patterns': [
        'ESP.GPIO23:R1.1',
        'R1.2:D1.A',
        'D1.K:ESP.GND',
        'ESP.GPIO22:R2.1',
        'R2.2:D2.A',
        'D2.K:ESP.GND',
      ],
      'light_intensity_monitor': [
        'ESP.3V3:R2.1',
        'R2.2:LDR1.1',
        'LDR1.2:R3.1',
        'R3.1:ESP.GPIO34',
        'R3.2:ESP.GND',
      ],
    };
    expect(catalog.projects.keys, orderedEquals(expected.keys));
    expect(catalog.board.fqbn, 'esp32:esp32:esp32');
    expect(catalog.board.pinout['GPIO34'], (header: 'J2 · 5', mark: 'IO34'));
    expect(catalog.board.pinout['GPIO23'], (header: 'J3 · 2', mark: 'IO23'));
    expect(catalog.board.pinout['GND'], (header: 'J3 · 7', mark: 'GND'));
    for (final project in catalog.projects.values) {
      final wires = project.wires.map(
        (wire) =>
            '${wire.from.part}.${wire.from.pin}:${wire.to.part}.${wire.to.pin}',
      );
      expect(wires, orderedEquals(expected[project.id]!));
      expect(project.title.en, isNot(project.title.bn));
      expect(project.safety, isNotEmpty);
      expect(project.checks, hasLength(2));
      expect(project.issues, hasLength(2));
      expect(
        project.issues.map((issue) => issue.wireId),
        everyElement(isIn(project.wires.map((wire) => wire.id))),
      );
      for (final part in project.parts.entries) {
        if (part.key.startsWith('R') &&
            part.key != 'R1' &&
            const {
              'ldr_night_light',
              'light_intensity_monitor',
            }.contains(project.id)) {
          expect(part.value, 'resistor10k');
        } else if (part.key.startsWith('R')) {
          expect(part.value, 'resistor330');
        }
      }
    }
  });

  test(
    'catalog rejects unknown terminals, incorrect routes, and stale code notes',
    () async {
      const asset = 'assets/learn/projects/led_blink.json';
      for (final (path, from, to) in [
        (asset, '"A"', '"missing"'),
        ('assets/learn/sketches/led_blink.ino', 'ledPin = 23', 'ledPin = 22'),
        (asset, '[694,108]', '[694,109]'),
        (asset, '"wireId": "R1.2>D1.A"', '"wireId": "not_a_wire"'),
        (asset, '"id": "restart_pattern"', '"id": "blink_cycle"'),
        (
          asset,
          '"anchor": "void setup() {"',
          '"anchor": "void anotherSetup() {"',
        ),
      ]) {
        final contents = await rootBundle.loadString(path);
        final bundle = _OverrideBundle(path, contents.replaceFirst(from, to));
        await expectLater(LearnCatalog.load(bundle), throwsFormatException);
      }
    },
  );

  test('all seven sketches have complete nonblank line coverage', () {
    for (final project in catalog.projects.values) {
      final covered = [
        for (final note in project.codeNotes)
          for (var i = note.firstLine; i <= note.lastLine; i++) i,
      ];
      expect(covered.toSet(), hasLength(covered.length));
      expect(
        covered,
        containsAll([
          for (final (index, line) in project.sketchLines.indexed)
            if (line.trim().isNotEmpty) index + 1,
        ]),
      );
      expect(project.codeNotes.first.anchor, '#include <Arduino.h>');
    }
    expect(catalog.setup.map((step) => step.stage), LearnSetupStage.values);
    expect(catalog.projects['ldr_night_light']!.serialBaud, 115200);
    expect(catalog.projects['led_blink']!.serialBaud, isNull);
  });

  test('board headers and drawn paths match the lesson terminals', () {
    expect(
      catalog.board.headers['J2']!.map((pin) => pin.mark),
      orderedEquals(
        '3V3 EN VP VN IO34 IO35 IO32 IO33 IO25 IO26 IO27 IO14 IO12 GND IO13 D2 D3 CMD 5V'
            .split(' '),
      ),
    );
    expect(
      catalog.board.headers['J3']!.map((pin) => pin.mark),
      orderedEquals(
        'GND IO23 IO22 TX RX IO21 GND IO19 IO18 IO5 IO17 IO16 IO4 IO0 IO2 IO15 D1 D0 CLK'
            .split(' '),
      ),
    );
    expect(catalog.board.headers['J2']![4].role, LearnPinRole.analogInput);
    expect(catalog.board.headers['J3']![18].role, LearnPinRole.flash);
    for (final project in catalog.projects.values) {
      final circuit = project.circuit;
      expect(
        circuit.routes.keys,
        unorderedEquals(project.wires.map((wire) => wire.id)),
      );
      for (final wire in project.wires) {
        final path = circuit.routes[wire.id]!;
        expect(
          path.first,
          circuit.nodes[wire.from.part]!.terminals[wire.from.pin],
        );
        expect(path.last, circuit.nodes[wire.to.part]!.terminals[wire.to.pin]);
      }
    }
    final nightLight = catalog.projects['ldr_night_light']!.circuit;
    expect(
      nightLight.junctions['LDR1.2>R3.1'],
      contains(const Offset(560, 174)),
    );
    expect(
      nightLight.junctions['R3.1>ESP.GPIO34'],
      contains(const Offset(560, 174)),
    );
    expect(nightLight.junctions['ESP.3V3>R2.1'], isNull);
    expect(
      nightLight.sharesNet(
        (part: 'LDR1', pin: '2'),
        (part: 'ESP', pin: 'GPIO34'),
      ),
      isTrue,
    );
    expect(
      nightLight.sharesNet((part: 'LDR1', pin: '2'), (part: 'ESP', pin: '3V3')),
      isFalse,
    );
  });

  test('Phase A checks carry forward and wire edits persist on reload', () async {
    final store = TestLearnStore()
      ..encoded =
          '{"version":1,"language":"en","projects":{"led_blink":{"checked":["parts","wiring","upload","test"]}}}';
    final scope = ProviderContainer.test(
      overrides: [learnProgressStoreProvider.overrideWithValue(store)],
    );
    final project = catalog.projects['led_blink']!;
    final loaded = (await scope.read(learnProgressProvider.future))
        .forProject(project.id);
    expect(loaded.completed, isTrue);
    expect(loaded.checkedItems(project, LearnChecklist.parts), hasLength(6));
    expect(loaded.checkedItems(project, LearnChecklist.wiring), hasLength(3));
    expect(loaded.checkedItems(project, LearnChecklist.test), hasLength(2));
    final migrated = await store.load();
    expect(migrated.earnedProjects, {'led_blink'});
    expect(migrated.activityDays, isEmpty);

    final writer = scope.read(learnProgressProvider.notifier);
    final wire = project.wires.first.id;
    await writer.checkItem(project, LearnChecklist.wiring, wire, false);
    await writer.openProject(project.id);
    var saved = (await store.load()).forProject(project.id);
    expect(saved.completed, isFalse);
    expect(saved.checkedItems(project, LearnChecklist.wiring), hasLength(2));
    expect(
      saved.checkedItems(project, LearnChecklist.wiring),
      isNot(contains(wire)),
    );
    expect(saved.checkedItems(project, LearnChecklist.parts), hasLength(6));
    await writer.checkItem(project, LearnChecklist.wiring, wire, true);
    saved = (await store.load()).forProject(project.id);
    expect(saved.completed, isTrue);
  });

  test(
    'confirmed tests earn one project reward and use local calendar days',
    () async {
      final store = TestLearnStore();
      var now = DateTime(2026, 11, 9, 23, 58);
      final container = ProviderContainer.test(
        overrides: [
          learnProgressStoreProvider.overrideWithValue(store),
          learnClockProvider.overrideWithValue(() => now),
        ],
      );
      final project = catalog.projects['led_blink']!;
      final writer = container.read(learnProgressProvider.notifier);
      Future<LearnRewards> rewards() async =>
          LearnRewards.calculate(catalog, await store.load(), now);

      await writer.openProject(project.id);
      expect((await rewards()).streak, 0);
      await writer.check(project.id, LearnMilestone.upload, true);
      expect((await rewards()).goalMet, isTrue);

      now = DateTime(2026, 11, 10, 0, 1);
      await writer.check(project.id, LearnMilestone.upload, true);
      expect((await rewards()).goalMet, isFalse);
      expect((await rewards()).streak, 1);

      await writer.check(project.id, LearnMilestone.parts, true);
      await writer.check(project.id, LearnMilestone.wiring, true);
      final first = project.checks.first.id;
      final last = project.checks.last.id;
      await writer.checkItem(project, LearnChecklist.test, first, true);
      expect((await store.load()).forProject(project.id).completed, isFalse);
      expect((await rewards()).xp, 0);
      await writer.checkItem(project, LearnChecklist.test, last, true);
      expect((await store.load()).forProject(project.id).completed, isTrue);
      expect((await rewards()).badges, {LearnBadge.firstCircuit});
      expect((await rewards()).xp, 100);
      expect((await rewards()).streak, 2);

      await writer.checkItem(project, LearnChecklist.test, first, false);
      expect((await store.load()).forProject(project.id).completed, isFalse);
      expect((await rewards()).xp, 100);
      await writer.checkItem(project, LearnChecklist.test, first, true);
      await writer.changeLanguage(LearnLanguage.bn);
      final saved = await store.load();
      expect(saved.language, LearnLanguage.bn);
      expect(saved.earnedProjects, {project.id});
      expect(saved.activityDays, {
        learnDay(DateTime(2026, 11, 9)),
        learnDay(now),
      });
      expect((await rewards()).xp, 100);

      now = DateTime(2026, 11, 12, 12);
      expect((await rewards()).streak, 0);
      expect((await rewards()).goalMet, isFalse);
    },
  );

  test('the expanded lesson library can earn every badge', () {
    final progress = LearnProgress.decode(
      jsonEncode({
        'version': 1,
        'projects': {
          for (final id in catalog.projects.keys)
            id: {
              'checked': ['parts', 'wiring', 'upload', 'test'],
            },
        },
      }),
    );
    final rewards = LearnRewards.calculate(
      catalog,
      progress,
      DateTime(2026, 11, 11),
    );
    expect(rewards.xp, 700);
    expect(rewards.badges, unorderedEquals(LearnBadge.values));
    expect(rewards.skills.map((skill) => skill.completed), [5, 2, 1]);
    expect(rewards.streak, 0);
  });

  test(
    'practice can be cleared without changing completed wiring or rewards',
    () async {
      final store = TestLearnStore();
      final scope = ProviderContainer.test(
        overrides: [learnProgressStoreProvider.overrideWithValue(store)],
      );
      final writer = scope.read(learnProgressProvider.notifier);
      final project = catalog.projects['led_blink']!;
      await writer.check(project.id, LearnMilestone.wiring, true);
      final beforePractice = await store.load();
      for (final wire in project.wires) {
        await writer.checkItem(project, LearnChecklist.practice, wire.id, true);
      }
      final saved = await store.load();
      expect(
        saved
            .forProject(project.id)
            .checkedItems(project, LearnChecklist.practice),
        hasLength(3),
      );
      expect(saved.forProject(project.id).checked, {LearnMilestone.wiring});
      expect(saved.activityDays, beforePractice.activityDays);
      expect(saved.earnedProjects, isEmpty);
      await writer.resetPractice(project.id);
      final cleared = (await store.load()).forProject(project.id);
      expect(cleared.checkedItems(project, LearnChecklist.practice), isEmpty);
      expect(
        cleared.checkedItems(project, LearnChecklist.wiring),
        hasLength(3),
      );
    },
  );

  test('concurrent progress writes survive a fresh provider', () async {
    final store = TestLearnStore();
    final first = ProviderContainer.test(
      overrides: [learnProgressStoreProvider.overrideWithValue(store)],
    );
    final writer = first.read(learnProgressProvider.notifier);
    await Future.wait([
      writer.openProject('servo_angle'),
      writer.changeLanguage(LearnLanguage.bn),
      for (final step in LearnMilestone.values)
        writer.check('servo_angle', step, true),
    ]);
    final next = ProviderContainer.test(
      overrides: [learnProgressStoreProvider.overrideWithValue(store)],
    );
    final reloaded = await next.read(learnProgressProvider.future);
    expect(reloaded.language, LearnLanguage.bn);
    expect(reloaded.forProject('servo_angle').completed, isTrue);
    expect(reloaded.forProject('servo_angle').opened, isNotNull);
    expect(reloaded.forProject('led_blink').completed, isFalse);
  });

  testWidgets(
    'searches, opens a guide, copies its sketch, and saves progress',
    (tester) async {
      final store = TestLearnStore();
      Object? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') clipboard = call.arguments;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final router = _router('/learn');
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(router, catalog, store));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'servo');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Servo Angle Control'), findsOneWidget);
      expect(find.text('Traffic Light Model'), findsNothing);
      await _tap(tester, 'Servo Angle Control');
      await _tap(tester, 'Start building');

      await _stage(tester, 'Read the sketch');
      await _tap(tester, 'Copy sketch');
      expect(clipboard, {'text': catalog.projects['servo_angle']!.sketch});
      await _stage(tester, 'Gather the components');
      final servo = catalog.projects['servo_angle']!;
      for (final id in servo.parts.keys) {
        await _tapFinder(tester, find.byKey(ValueKey('component-$id')));
      }
      expect(find.text('6 of 6 components ready'), findsOneWidget);
      await _stage(tester, 'Wire the circuit');
      for (final (index, wire) in servo.wires.indexed) {
        if (index > 0) await _tap(tester, 'Next wire');
        await _tapFinder(
          tester,
          find.byKey(ValueKey('active-wire-${wire.id}')),
        );
      }
      expect(find.text('4 of 4 checked'), findsOneWidget);
      await _stage(tester, 'Upload with Arduino IDE');
      await _tap(tester, 'Arduino IDE finished uploading');
      await _stage(tester, 'Test the project');
      await _tapFinder(
        tester,
        find.byKey(const ValueKey('test-three_positions')),
      );
      expect(find.text('1 of 2 results confirmed'), findsOneWidget);
      expect(find.text('Project completed'), findsNothing);
      await _tapFinder(
        tester,
        find.byKey(const ValueKey('test-smooth_motion')),
      );
      expect(find.text('Project completed'), findsOneWidget);
      expect(find.text('You finished Servo Angle Control'), findsOneWidget);
      expect(find.text('100 XP earned'), findsOneWidget);
      expect(
        LearnProgress.decode(store.encoded!)
            .forProject('servo_angle')
            .completed,
        isTrue,
      );
      await _tap(tester, 'Project overview');
      await _tap(tester, 'Project library');
      await _tap(tester, 'Achievements');
      expect(find.text('Servo Starter'), findsOneWidget);
      expect(find.text('Earned'), findsNWidgets(2));
      await _tap(tester, 'Close');
      await _tap(tester, 'My Projects');
      expect(
        find.widgetWithText(ListTile, 'Servo Angle Control'),
        findsOneWidget,
      );
      await _tap(tester, 'Close');
      final languageButton = find.byTooltip('Lesson language');
      await tester.ensureVisible(languageButton);
      await tester.tap(languageButton);
      await tester.pumpAndSettle();
      await _tap(tester, 'বাংলা');
      expect(find.text('শিখুন ও বানান'), findsOneWidget);
      expect(LearnProgress.decode(store.encoded!).language, LearnLanguage.bn);
    },
  );

  testWidgets(
    'a troubleshooting issue opens the corresponding wire and returns to tests',
    (tester) async {
      final router = _router('/learn/ldr_night_light');
      addTearDown(router.dispose);
      final store = TestLearnStore();
      await tester.pumpWidget(_app(router, catalog, store));
      await tester.pumpAndSettle();
      await _tap(tester, 'Start building');
      await _stage(tester, 'Test the project');
      await _tap(tester, 'Troubleshoot a result');
      await _tap(tester, 'The reading stays near zero');
      expect(find.text('What to check'), findsOneWidget);
      await _tap(tester, 'Show related wiring');
      expect(
        find.byKey(const ValueKey('active-wire-R3.1>ESP.GPIO34')),
        findsOneWidget,
      );
      await _tap(tester, 'Back to troubleshooting');
      await _tap(tester, 'Back to project tests');
      expect(find.text('0 of 2 results confirmed'), findsOneWidget);
      expect((await store.load()).activityDays, isEmpty);
    },
  );

  testWidgets('inspects ADC pins, zooms the diagram, and selects a wire', (
    tester,
  ) async {
    final router = _router('/learn/ldr_night_light');
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(router, catalog, TestLearnStore()));
    await tester.pumpAndSettle();
    await _tap(tester, 'Start building');
    await _stage(tester, 'Know your ESP32 board');
    await _tap(tester, 'Explore board pins');
    await _tapFinder(tester, find.byKey(const ValueKey('board-pin-J2 · 5')));
    expect(find.text('J2 · 5 · IO34'), findsOneWidget);
    expect(
      find.text('ADC1 input. Reads voltage and cannot drive an output.'),
      findsOneWidget,
    );
    await _tapFinder(tester, find.byTooltip('Close pin explorer'));
    await _stage(tester, 'Wire the circuit');
    final diagram = find.byKey(const ValueKey('wiring-diagram'));
    final controller = tester
        .widget<InteractiveViewer>(diagram)
        .transformationController!;
    await _tapFinder(tester, find.byTooltip('Zoom in'));
    expect(controller.value.getMaxScaleOnAxis(), greaterThan(1));
    await _tapFinder(tester, find.byTooltip('Fit circuit'));
    expect(controller.value.isIdentity(), isTrue);
    await tester.ensureVisible(diagram);
    final viewport = tester.getRect(diagram);
    final project = catalog.projects['ldr_night_light']!;
    final size = project.circuit.size;
    final factor = math.min(
      viewport.width / size.width,
      viewport.height / size.height,
    );
    final origin =
        viewport.center - Offset(size.width, size.height) * (factor / 2);
    await tester.tapAt(
      origin + project.circuit.nodes['LDR1']!.bounds.center * factor,
    );
    await tester.pumpAndSettle();
    expect(find.text('LDR1 · Photoresistor (LDR)'), findsOneWidget);
    await _tap(tester, 'Next wire');
    expect(find.text('Connection 2 of 8'), findsOneWidget);
    expect(find.text('LDR1 · Photoresistor (LDR)'), findsNothing);
  });

  testWidgets(
    'practice draws only accepted wires and resumes at the next terminal',
    (tester) async {
      final router = _router('/learn/led_blink');
      addTearDown(router.dispose);
      final store = TestLearnStore();
      await tester.pumpWidget(_app(router, catalog, store));
      await tester.pumpAndSettle();
      await _tap(tester, 'Start building');
      await _stage(tester, 'Wire the circuit');
      await _tap(tester, 'Practice wiring');
      final diagram = find.byType(LearnWiringDiagram);
      Set<String>? visibleWires() =>
          tester.widget<LearnWiringDiagram>(diagram).visibleWires;
      expect(visibleWires(), isEmpty);

      Future<void> pickTerminal(String id) async {
        await _tap(tester, 'Choose a terminal');
        await _tapFinder(tester, find.byKey(ValueKey('practice-terminal-$id')));
      }

      await pickTerminal('ESP.GND');
      expect(
        find.text('Try again. That terminal is outside this connection.'),
        findsOneWidget,
      );
      expect(visibleWires(), isEmpty);
      expect((await store.load()).forProject('led_blink').checked, isEmpty);
      await _tap(tester, 'Hint');
      await _tap(tester, 'Show destination');
      expect(find.text('330 Ω resistor R1 · 1'), findsOneWidget);
      await pickTerminal('R1.1');
      expect(visibleWires(), {'ESP.GPIO23>R1.1'});
      expect(find.textContaining('Correct connection.'), findsOneWidget);
      await _tap(tester, 'Back to wiring guide');
      await _tap(tester, 'Practice wiring');
      expect(find.text('1 of 3 connections matched'), findsOneWidget);
      expect(find.text('330 Ω resistor R1 · 2'), findsOneWidget);

      final project = catalog.projects['led_blink']!;
      final canvas = find.byKey(const ValueKey('wiring-diagram'));
      await tester.ensureVisible(canvas);
      final viewport = tester.getRect(canvas);
      final size = project.circuit.size;
      final factor = math.min(
        viewport.width / size.width,
        viewport.height / size.height,
      );
      final origin =
          viewport.center - Offset(size.width, size.height) * (factor / 2);
      await tester.tapAt(
        origin + project.circuit.nodes['D1']!.terminals['A']! * factor,
      );
      await tester.pumpAndSettle();
      expect(visibleWires(), {'ESP.GPIO23>R1.1', 'R1.2>D1.A'});
      await _tap(tester, 'Next connection');
      await pickTerminal('ESP.GND');
      await _tap(tester, 'Finish practice');
      expect(find.text('Practice complete'), findsOneWidget);
      expect((await store.load()).earnedProjects, isEmpty);
      expect((await store.load()).activityDays, isEmpty);
      await _tap(tester, 'Practice again');
      expect(visibleWires(), isEmpty);
    },
  );

  testWidgets(
    'highlights the selected lines and exports the original sketch bytes',
    (tester) async {
      const export = MethodChannel('esp_iot/learn_export');
      MethodCall? call;
      var save = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(export, (
        request,
      ) async {
        call = request;
        return save;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          export,
          null,
        ),
      );
      final router = _router('/learn/servo_angle');
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(router, catalog, TestLearnStore()));
      await tester.pumpAndSettle();
      await _tap(tester, 'Start building');
      await _stage(tester, 'Read the sketch');
      await _tap(tester, 'Learn the code');
      expect(find.byKey(const ValueKey('highlight-1-1')), findsOneWidget);
      await _tap(tester, 'Convert pulse width into duty');
      final highlighted = find.byKey(const ValueKey('highlight-9-12'));
      expect(highlighted, findsOneWidget);
      expect(find.byKey(const ValueKey('highlight-1-1')), findsNothing);
      expect(
        find.descendant(
          of: highlighted,
          matching: find.textContaining('void moveServo', findRichText: true),
        ),
        findsOneWidget,
      );
      await _tap(tester, 'Download .ino');
      expect(find.text('Sketch saved'), findsNothing);
      expect(call!.method, 'saveSketch');
      expect(call!.arguments['name'], 'servo_angle.ino');
      expect(
        call!.arguments['bytes'],
        orderedEquals(utf8.encode(catalog.projects['servo_angle']!.sketch)),
      );
      save = true;
      await _tap(tester, 'Download .ino');
      expect(find.text('Sketch saved'), findsOneWidget);
    },
  );

  testWidgets(
    'shows board setup, upload troubleshooting, and the sketch baud rate',
    (tester) async {
      final router = _router('/learn/ldr_night_light');
      addTearDown(router.dispose);
      final store = TestLearnStore();
      await tester.pumpWidget(_app(router, catalog, store));
      await tester.pumpAndSettle();
      await _tap(tester, 'Start building');
      await _stage(tester, 'Upload with Arduino IDE');
      expect(find.text('Step 1 of 9'), findsOneWidget);
      await _tap(tester, 'Next');
      expect(find.text('Additional Boards Manager URLs'), findsOneWidget);
      final jump = find.byTooltip('Choose walkthrough step');
      await _tapFinder(tester, jump);
      await _tap(tester, 'Select the board and port', last: true);
      expect(find.text('ESP32 Dev Module'), findsOneWidget);
      expect(find.text('Example port'), findsOneWidget);
      await _tapFinder(tester, jump);
      await _tap(tester, 'Read the output and test', last: true);
      expect(find.text('115200 baud'), findsOneWidget);
      await _tap(tester, 'Upload stays at Connecting…');
      expect(
        find.textContaining('hold BOOT, tap and release EN'),
        findsOneWidget,
      );
      final progress = (await store.load()).forProject('ldr_night_light');
      expect(progress.checked, isNot(contains(LearnMilestone.upload)));
    },
  );
}

Future<void> _stage(WidgetTester tester, String title) async {
  final selector = find.byWidgetPredicate((widget) => widget is DropdownButton);
  await tester.ensureVisible(selector);
  await tester.tap(selector);
  await tester.pumpAndSettle();
  await _tap(tester, title, last: true);
}

Future<void> _tap(
  WidgetTester tester,
  String label, {
  bool last = false,
}) async {
  final matches = find.text(label);
  final target = last ? matches.last : matches.first;
  await _tapFinder(tester, target);
}

Future<void> _tapFinder(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

GoRouter _router(String initialLocation) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    ShellRoute(
      builder: (context, state, child) => Scaffold(body: child),
      routes: [
        GoRoute(
          path: '/learn',
          builder: (context, state) => const LearnHomeScreen(),
          routes: [
            GoRoute(
              path: ':projectId',
              builder: (context, state) =>
                  LearnProjectScreen(id: state.pathParameters['projectId']!),
            ),
          ],
        ),
      ],
    ),
  ],
);

Widget _app(GoRouter router, LearnCatalog catalog, TestLearnStore store) =>
    ProviderScope(
      overrides: [
        learnCatalogProvider.overrideWith((ref) async => catalog),
        learnProgressStoreProvider.overrideWithValue(store),
      ],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    );

class _OverrideBundle extends CachingAssetBundle {
  _OverrideBundle(this.path, this.contents);
  final String path, contents;

  @override
  Future<ByteData> load(String key) async => key == path
      ? ByteData.sublistView(Uint8List.fromList(utf8.encode(contents)))
      : rootBundle.load(key);
}
