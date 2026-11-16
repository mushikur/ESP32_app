import 'dart:async';

import 'package:esp_iot/app/workspace_shell.dart';
import 'package:esp_iot/features/devices/device_database.dart';
import 'package:esp_iot/features/devices/device_registry.dart';
import 'package:esp_iot/features/discovery/discovery_service.dart';
import 'package:esp_iot/features/discovery/local_endpoint.dart';
import 'package:esp_iot/features/learn/learn_progress.dart';
import 'package:esp_iot/features/onboarding/onboarding_store.dart';
import 'package:esp_iot/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'support/test_discovery.dart';
import 'support/test_learn.dart';

void main() {
  testWidgets('completes the tour and opens Home on relaunch', (tester) async {
    final preferences = _TestStore();
    _reduceMotion(tester);
    await _open(tester, preferences);

    expect(find.text('One home for your ESP32s.'), findsOneWidget);
    await _tapText(tester, 'Next');
    expect(find.text('ILLUSTRATIVE DEVICE CARD'), findsOneWidget);
    await _tapText(tester, 'Next');
    expect(find.text('Local by design.'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous page'));
    await tester.pumpAndSettle();
    expect(find.text('A dashboard for each project.'), findsOneWidget);
    await _tapText(tester, 'Next');
    await _tapText(tester, 'Open ESP IoT');
    expect(find.text('Command center'), findsOneWidget);
    expect(preferences.completionWrites, 1);

    await tester.pumpWidget(const SizedBox());
    await _open(tester, preferences);
    expect(find.text('Command center'), findsOneWidget);
    expect(find.text('Skip'), findsNothing);
  });

  testWidgets('opens workspace sections and replays the tour from Settings', (
    tester,
  ) async {
    final preferences = _TestStore(completed: true);
    _reduceMotion(tester);
    await _open(tester, preferences);

    expect(find.text('0'), findsNWidgets(3));
    await _tapText(tester, 'Discover devices');
    expect(find.text('No ESP IoT devices found'), findsOneWidget);
    expect(find.text('Scan pairing QR'), findsOneWidget);

    for (final (tab, title) in [
      (WorkspaceTab.devices, 'No registered devices'),
      (WorkspaceTab.automations, 'No automations'),
      (WorkspaceTab.activity, 'No activity yet'),
      (WorkspaceTab.settings, 'Replay introduction'),
    ]) {
      await _tapTab(tester, tab);
      expect(find.text(title), findsOneWidget);
    }

    await _tapText(tester, 'Replay introduction');
    expect(find.text('One home for your ESP32s.'), findsOneWidget);
    await _tapText(tester, 'Close');
    expect(find.text('Replay introduction'), findsOneWidget);
    expect(preferences.completionWrites, 0);

    await _tapTab(tester, WorkspaceTab.home);
    expect(find.text('Command center'), findsOneWidget);
  });

  testWidgets('keeps the tour and navigation usable at 200 percent text size', (
    tester,
  ) async {
    _reduceMotion(tester);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _open(tester, _TestStore());
    await _tapText(tester, 'Next');
    await _tapText(tester, 'Next');
    await _tapText(tester, 'Open ESP IoT');
    expect(find.text('Command center'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

    for (final tab in WorkspaceTab.values) {
      await _tapTab(tester, tab);
      expect(tester.takeException(), isNull);
    }
  });

  for (final (name, size, density, scale, safeArea) in [
    (
      'compact portrait',
      const Size(336, 640),
      3.0,
      1.0,
      const FakeViewPadding(top: 90, bottom: 72),
    ),
    (
      'short landscape with a side cutout',
      const Size(704, 320),
      2.0,
      2.0,
      const FakeViewPadding(left: 72, bottom: 24),
    ),
    (
      'tablet',
      const Size(800, 1280),
      1.5,
      1.3,
      const FakeViewPadding(top: 36, bottom: 24),
    ),
  ]) {
    testWidgets('keeps every workspace tab usable on $name', (tester) async {
      _reduceMotion(tester);
      tester.view.devicePixelRatio = density;
      tester.view.physicalSize = size * density;
      tester.view.padding = safeArea;
      tester.view.viewPadding = safeArea;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await _open(tester, _TestStore(completed: true));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

      for (final tab in WorkspaceTab.values) {
        final target = find.byKey(ValueKey(tab)).hitTestable();
        expect(target, findsOneWidget, reason: tab.name);
        final bounds = tester.getRect(target);
        expect(bounds.width, greaterThanOrEqualTo(48), reason: tab.name);
        expect(bounds.height, greaterThanOrEqualTo(48), reason: tab.name);
        expect(bounds.left, greaterThanOrEqualTo(safeArea.left / density));
        expect(
          bounds.bottom,
          lessThanOrEqualTo(size.height - safeArea.bottom / density),
        );
        await _tapTab(tester, tab);
        expect(
          tester.widget<WorkspaceShell>(find.byType(WorkspaceShell)).activeTab,
          tab,
        );
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('keeps manual address verification reachable with the keyboard', (
    tester,
  ) async {
    _reduceMotion(tester);
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.padding = const FakeViewPadding(top: 64, bottom: 48);
    tester.view.viewPadding = const FakeViewPadding(top: 64, bottom: 48);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _open(tester, _TestStore(completed: true));
    await _tapTab(tester, WorkspaceTab.discover);
    await tester.ensureVisible(find.text('Manual address'));
    await _tapText(tester, 'Manual address');

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.first, testEndpoint.host);
    tester.view.padding = const FakeViewPadding(top: 64);
    tester.view.viewInsets = const FakeViewPadding(bottom: 520);
    await tester.pumpAndSettle();
    await tester.ensureVisible(fields.at(1));
    await tester.enterText(fields.at(1), '65536');
    await tester.pumpAndSettle();

    final verify = find.text('Verify address');
    await tester.ensureVisible(verify);
    await tester.pumpAndSettle();
    expect(verify.hitTestable(), findsOneWidget);
    await _tapText(tester, 'Verify address');
    expect(find.text('Enter a port from 1 to 65535.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('explains camera use and preserves manual pairing after denial', (
    tester,
  ) async {
    _reduceMotion(tester);
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(1408, 608);
    tester.view.padding = const FakeViewPadding(left: 72, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(left: 72, bottom: 24);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final previousScanner = MobileScannerPlatform.instance;
    final scanner = _TestCamera(denied: true);
    MobileScannerPlatform.instance = scanner;
    addTearDown(() async {
      MobileScannerPlatform.instance = previousScanner;
      await scanner.close();
    });

    await _open(tester, _TestStore(completed: true));
    await _tapTab(tester, WorkspaceTab.discover);
    final scan = find.text('Scan pairing QR');
    await tester.ensureVisible(scan);
    await _tapText(tester, 'Scan pairing QR');
    expect(find.text('Scan with your camera'), findsOneWidget);
    expect(scanner.starts, 0);

    await tester.ensureVisible(find.text('Back to Discover'));
    await _tapText(tester, 'Back to Discover');
    expect(scanner.starts, 0);
    await tester.ensureVisible(scan);
    await _tapText(tester, 'Scan pairing QR');

    final openCamera = find.text('Open camera');
    await tester.ensureVisible(openCamera);
    expect(openCamera.hitTestable(), findsOneWidget);
    await _tapText(tester, 'Open camera');
    expect(scanner.starts, 1);
    expect(find.text('Camera unavailable'), findsOneWidget);

    await tester.ensureVisible(find.text('Back to Discover'));
    await _tapText(tester, 'Back to Discover');
    await tester.ensureVisible(find.text('Manual address'));
    await _tapText(tester, 'Manual address');
    expect(find.text('Enter device address'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reviews a scanned pairing hint before verifying the address', (
    tester,
  ) async {
    _reduceMotion(tester);
    final previousScanner = MobileScannerPlatform.instance;
    final scanner = _TestCamera();
    MobileScannerPlatform.instance = scanner;
    addTearDown(() async {
      MobileScannerPlatform.instance = previousScanner;
      await scanner.close();
    });

    await _open(tester, _TestStore(completed: true));
    await _tapTab(tester, WorkspaceTab.discover);
    await tester.ensureVisible(find.text('Scan pairing QR'));
    await _tapText(tester, 'Scan pairing QR');
    await tester.ensureVisible(find.text('Open camera'));
    await _tapText(tester, 'Open camera');
    expect(scanner.starts, 1);
    expect(
      find.text('Point the camera at an ESP IoT pairing QR code.'),
      findsOneWidget,
    );

    scanner.scan('an unrelated QR');
    await tester.pumpAndSettle();
    expect(find.textContaining('That code could not be read'), findsOneWidget);
    scanner.scan(PairingHint(testEndpoint, testDeviceId).encode());
    await tester.pumpAndSettle();
    expect(find.text('Verify QR address?'), findsOneWidget);
    expect(find.textContaining(testEndpoint.origin), findsOneWidget);

    await _tapText(tester, 'Verify address');
    expect(find.text('Bench ESP32'), findsOneWidget);
    final register = find.widgetWithText(FilledButton, 'Register device');
    expect(tester.widget<FilledButton>(register).onPressed, isNull);
    await _tapText(tester, 'Cancel');
    expect(find.text('Discover'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('animates the active tour and stops animating on Home', (
    tester,
  ) async {
    final preferences = _TestStore();
    await tester.pumpWidget(_app(preferences));
    await tester.pump();
    expect(find.text('One home for your ESP32s.'), findsOneWidget);
    expect(tester.hasRunningAnimations, isTrue);

    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 360));
    expect(find.text('A dashboard for each project.'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 360));
    expect(find.text('Local by design.'), findsOneWidget);
    await _tapText(tester, 'Open ESP IoT');
    expect(find.text('Command center'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('opens Home when the tour preference cannot be saved', (
    tester,
  ) async {
    _reduceMotion(tester);
    await _open(tester, _TestStore(failSave: true));
    await _tapText(tester, 'Skip');

    expect(find.text('Command center'), findsOneWidget);
    expect(
      find.text(
        'Tour completion could not be saved. The tour may appear next time.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows a loading state until the launch preference is read', (
    tester,
  ) async {
    final read = Completer<bool>();
    _reduceMotion(tester);
    await tester.pumpWidget(_app(_TestStore(read: read.future)));
    expect(find.text('Opening workspace'), findsOneWidget);

    read.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('Command center'), findsOneWidget);
  });

  testWidgets(
    'registers a manually verified device only after HTTP consent and reloads it',
    (tester) async {
      _reduceMotion(tester);
      final preferences = _TestStore(completed: true);
      final registry = TestRegistrationStore();
      await _open(tester, preferences, registry: registry);
      await _tapTab(tester, WorkspaceTab.discover);
      await tester.ensureVisible(find.text('Manual address'));
      await _tapText(tester, 'Manual address');
      await tester.enterText(
        find.byType(TextFormField).first,
        testEndpoint.host,
      );
      await _tapText(tester, 'Verify address');
      expect(find.text('Bench ESP32'), findsOneWidget);
      final register = find.widgetWithText(FilledButton, 'Register device');
      expect(tester.widget<FilledButton>(register).onPressed, isNull);
      expect(registry.writes, 0);
      await tester.ensureVisible(find.text('I trust this Wi-Fi network'));
      await _tapText(tester, 'I trust this Wi-Fi network');
      await _tapText(tester, 'Register device');
      expect(registry.writes, 1);

      await _tapTab(tester, WorkspaceTab.devices);
      expect(find.text('Bench ESP32'), findsOneWidget);
      expect(find.text('Status unknown'), findsOneWidget);
      await _tapText(tester, 'Show pairing QR');
      expect(find.text('ESP IoT pairing QR'), findsOneWidget);
      await _tapText(tester, 'Close');

      await tester.pumpWidget(const SizedBox());
      await _open(tester, preferences, registry: registry);
      await _tapTab(tester, WorkspaceTab.devices);
      expect(find.text('Bench ESP32'), findsOneWidget);
    },
  );
}

Widget _app(_TestStore preferences, {TestRegistrationStore? registry}) =>
    ProviderScope(
      overrides: [
        onboardingStoreProvider.overrideWithValue(preferences),
        discoveryPlatformProvider.overrideWithValue(TestDiscoveryPlatform()),
        deviceHistoryStoreProvider.overrideWithValue(TestHistoryStore()),
        learnProgressStoreProvider.overrideWithValue(TestLearnStore()),
        registrationStoreProvider.overrideWithValue(
          registry ?? TestRegistrationStore(),
        ),
      ],
      child: const EspIotApp(),
    );

Future<void> _open(
  WidgetTester tester,
  _TestStore preferences, {
  TestRegistrationStore? registry,
}) async {
  await tester.pumpWidget(_app(preferences, registry: registry));
  await tester.pumpAndSettle();
}

void _reduceMotion(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

Future<void> _tapText(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> _tapTab(WidgetTester tester, WorkspaceTab tab) async {
  await tester.tap(find.byKey(ValueKey(tab)));
  await tester.pumpAndSettle();
}

class _TestStore implements OnboardingStore {
  _TestStore({this.completed = false, this.failSave = false, this.read});

  bool completed;
  final bool failSave;
  final Future<bool>? read;
  int completionWrites = 0;

  @override
  Future<bool> isComplete() async => read ?? completed;

  @override
  Future<void> markComplete() async {
    if (failSave) throw Exception('Storage unavailable');
    completionWrites++;
    completed = true;
  }
}

class _TestCamera extends MobileScannerPlatform {
  _TestCamera({this.denied = false});

  final bool denied;
  final _captures = StreamController<BarcodeCapture?>.broadcast();
  int starts = 0;

  @override
  Stream<BarcodeCapture?> get barcodesStream => _captures.stream;

  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();

  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();

  @override
  Future<MobileScannerViewAttributes> start(StartOptions startOptions) async {
    starts++;
    if (denied) {
      throw const MobileScannerException(
        errorCode: MobileScannerErrorCode.permissionDenied,
      );
    }
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.off,
      size: Size(480, 640),
    );
  }

  @override
  Widget buildCameraView() => const ColoredBox(color: Colors.black);

  @override
  Future<void> stop() async {}

  void scan(String payload) => _captures.add(
    BarcodeCapture(
      barcodes: [Barcode(format: BarcodeFormat.qrCode, rawValue: payload)],
    ),
  );

  Future<void> close() => _captures.close();
}
