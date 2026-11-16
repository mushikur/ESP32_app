import 'package:esp_iot/features/learn/learn_catalog.dart';
import 'package:esp_iot/features/learn/learn_companion_apps.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingLauncher implements AppListingLauncher {
  _RecordingLauncher({this.failure});

  final String? failure;
  final opened = <String>[];

  @override
  Future<void> open(String applicationId) async {
    opened.add(applicationId);
    if (failure != null) throw CompanionAppFailure(failure!);
  }
}

void main() {
  Widget host(_RecordingLauncher launcher, {LearnLanguage? language}) =>
      ProviderScope(
        overrides: [appListingLauncherProvider.overrideWithValue(launcher)],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LearnCompanionApps(language: language ?? LearnLanguage.en),
            ),
          ),
        ),
      );

  test('every listed app uses a valid Android application id', () {
    expect(learnCompanionApps, isNotEmpty);
    final pattern = RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$');
    for (final app in learnCompanionApps) {
      expect(
        pattern.hasMatch(app.applicationId),
        isTrue,
        reason: '${app.applicationId} is not a usable Play Store id',
      );
      // Only Arduino's own namespace belongs in this list.
      expect(app.applicationId.startsWith('cc.arduino.'), isTrue);
    }
  });

  testWidgets('tapping an app opens its Play Store listing', (tester) async {
    final launcher = _RecordingLauncher();
    await tester.pumpWidget(host(launcher));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Arduino IoT Cloud Remote'));
    await tester.pumpAndSettle();
    expect(launcher.opened, ['cc.arduino.cloudiot']);

    await tester.tap(find.text('Arduino Science Journal'));
    await tester.pumpAndSettle();
    expect(launcher.opened, [
      'cc.arduino.cloudiot',
      'cc.arduino.sciencejournal',
    ]);
  });

  testWidgets('a store failure is reported and does not wedge the row', (
    tester,
  ) async {
    final launcher = _RecordingLauncher(failure: 'Google Play is unavailable.');
    await tester.pumpWidget(host(launcher));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Arduino IoT Cloud Remote'));
    await tester.pumpAndSettle();
    expect(find.text('Google Play is unavailable.'), findsOneWidget);

    // The tile must accept another attempt after the failure.
    await tester.tap(find.text('Arduino IoT Cloud Remote'));
    await tester.pumpAndSettle();
    expect(launcher.opened.length, 2);
  });

  testWidgets('the card says an upload still needs a computer', (tester) async {
    await tester.pumpWidget(host(_RecordingLauncher()));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('neither one can upload a sketch'),
      findsOneWidget,
    );
    expect(find.textContaining('Arduino IDE on a computer'), findsOneWidget);

    await tester.pumpWidget(
      host(_RecordingLauncher(), language: LearnLanguage.bn),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Arduino IDE'), findsOneWidget);
  });
}
