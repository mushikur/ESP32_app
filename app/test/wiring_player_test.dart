import 'package:esp_iot/features/learn/learn_catalog.dart';
import 'package:esp_iot/features/learn/learn_wiring_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reads how many connections the player says it is on, from its caption.
int captionIndex(WidgetTester tester) {
  final caption = tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data ?? '')
      .firstWhere((value) => value.startsWith('Connection '));
  return int.parse(RegExp(r'Connection (\d+) of').firstMatch(caption)![1]!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LearnCatalog catalog;
  setUpAll(() async => catalog = await LearnCatalog.load(rootBundle));

  Widget host(LearnProject project, {bool reduceMotion = false}) => MaterialApp(
    home: MediaQuery(
      // A tall surface so the whole player, including its transport row,
      // is laid out and tappable without scrolling.
      data: MediaQueryData(
        disableAnimations: reduceMotion,
        size: const Size(800, 2000),
      ),
      child: Scaffold(
        body: SingleChildScrollView(
          child: LearnWiringPlayer(
            catalog: catalog,
            project: project,
            language: LearnLanguage.en,
          ),
        ),
      ),
    ),
  );

  testWidgets('playback draws each connection in order and then flows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final project = catalog.projects['led_blink']!;
    await tester.pumpWidget(host(project));
    await tester.pumpAndSettle();

    // Nothing moves until the user asks for it.
    expect(captionIndex(tester), 1);
    expect(tester.hasRunningAnimations, isFalse);

    await tester.tap(find.byTooltip('Play'));
    await tester.pump();
    expect(tester.hasRunningAnimations, isTrue);

    // Each connection takes 1500 ms, so the caption advances as time passes.
    await tester.pump(const Duration(milliseconds: 1600));
    expect(captionIndex(tester), 2);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(captionIndex(tester), 3);

    // Once every wire is drawn the current-flow loop takes over.
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.text('Circuit complete'), findsOneWidget);
    expect(find.byTooltip('Play'), findsNothing);
    expect(tester.hasRunningAnimations, isTrue);

    // Replay returns to the first connection and plays again.
    await tester.tap(find.text('Replay'));
    await tester.pump();
    expect(captionIndex(tester), 1);
    expect(find.text('Circuit complete'), findsNothing);
  });

  testWidgets('pause holds the current connection', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(catalog.projects['led_blink']!));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Play'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1600));
    expect(captionIndex(tester), 2);

    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(captionIndex(tester), 2);
    expect(find.byTooltip('Play'), findsOneWidget);
  });

  testWidgets('reduced motion turns the player into a stepper', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final project = catalog.projects['led_blink']!;
    await tester.pumpWidget(host(project, reduceMotion: true));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Play'), findsNothing);
    expect(captionIndex(tester), 1);

    // Stepping advances one whole connection at a time and never animates.
    await tester.tap(find.byTooltip('Next connection').first);
    await tester.pumpAndSettle();
    expect(captionIndex(tester), 2);
    expect(tester.hasRunningAnimations, isFalse);

    await tester.tap(find.byTooltip('Previous connection'));
    await tester.pumpAndSettle();
    expect(captionIndex(tester), 1);
  });

  testWidgets('every bundled project can be played to completion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final project in catalog.projects.values) {
      await tester.pumpWidget(host(project));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Play'));
      await tester.pump();
      await tester.pump(
        Duration(milliseconds: 1500 * project.wires.length + 200),
      );
      expect(
        find.text('Circuit complete'),
        findsOneWidget,
        reason: 'playback should finish for ${project.id}',
      );
      // Leave the looping flow animation in a stopped state for the next pass.
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
