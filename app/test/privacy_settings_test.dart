import 'package:esp_iot/features/workspace/workspace_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('opens and scrolls privacy information from compact Settings', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: SettingsScreen())),
      ),
    );

    final privacy = find.text('Privacy and permissions');
    await tester.ensureVisible(privacy);
    await tester.tap(privacy);
    await tester.pumpAndSettle();
    expect(find.text('Privacy'), findsOneWidget);

    final camera = find.text('QR camera access');
    await tester.ensureVisible(camera);
    expect(camera.hitTestable(), findsOneWidget);
    expect(find.textContaining('Google ML Kit'), findsOneWidget);
    final safety = find.text('Safe device use');
    await tester.ensureVisible(safety);
    expect(safety.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Replay introduction'), findsOneWidget);
  });
}
