import 'package:esp_iot/features/devices/device_database.dart';
import 'package:esp_iot/features/devices/device_registry.dart';
import 'package:esp_iot/features/discovery/local_discovery_platform.dart';
import 'package:esp_iot/features/discovery/local_endpoint.dart';
import 'package:esp_iot/features/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_discovery.dart';

void main() {
  testWidgets('Home refreshes Wi-Fi status and pauses lookups when hidden', (
    tester,
  ) async {
    final platform = _CountingDiscoveryPlatform();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          registrationStoreProvider.overrideWithValue(TestRegistrationStore()),
          deviceHistoryStoreProvider.overrideWithValue(TestHistoryStore()),
          discoveryPlatformProvider.overrideWithValue(platform),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const Scaffold(body: HomeScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Wi-Fi available · 192.168.1.20/24'), findsOneWidget);

    platform.scope = WifiScope('192.168.2.20', 24, 101, isDefault: false);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.textContaining('Make this Wi-Fi'), findsOneWidget);
    expect(find.textContaining('192.168.1.20'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    final before = platform.lookups;
    platform.scope = WifiScope('192.168.2.20', 24, 101);
    await tester.pump(const Duration(seconds: 20));
    expect(platform.lookups, before);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Wi-Fi available · 192.168.2.20/24'), findsOneWidget);

    platform.unavailable = true;
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('Local Wi-Fi is unavailable.'), findsOneWidget);
    expect(find.textContaining('192.168.2.20'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}

class _CountingDiscoveryPlatform extends TestDiscoveryPlatform {
  int lookups = 0;
  bool unavailable = false;

  @override
  Future<WifiScope> wifi() async {
    lookups++;
    if (unavailable) throw const DiscoveryFailure('noWifi');
    return scope;
  }
}
