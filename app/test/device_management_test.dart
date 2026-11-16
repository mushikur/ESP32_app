import 'dart:convert';
import 'dart:io';

import 'package:esp_iot/core/protocol/device_descriptor.dart';
import 'package:esp_iot/features/connection/api_profile.dart';
import 'package:esp_iot/features/connection/profile_store.dart';
import 'package:esp_iot/features/devices/device_database.dart';
import 'package:esp_iot/features/devices/device_registry.dart';
import 'package:esp_iot/features/devices/devices_screen.dart';
import 'package:esp_iot/features/discovery/discovery_service.dart';
import 'package:esp_iot/features/discovery/local_endpoint.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_discovery.dart';

final _verifiedAt = DateTime.utc(2026, 11, 1);

VerifiedDevice _verified({
  LocalEndpoint? endpoint,
  bool universal = false,
  String id = testDeviceId,
}) => VerifiedDevice(
  endpoint: endpoint ?? testEndpoint,
  scope: testWifi,
  source: DiscoverySource.manual,
  checkedAt: _verifiedAt,
  descriptor: universal
      ? DeviceDescriptor.decode(
          utf8.encode(jsonEncode(descriptorFixture(id: id))),
        )
      : null,
);

String _oldRegistry(Iterable<VerifiedDevice> devices) => jsonEncode([
  for (final verified in devices)
    DeviceRegistration.fromVerified(verified).toJson()
      ..remove('registrationId')
      ..remove('customName')
      ..remove('room')
      ..remove('category')
      ..remove('icon'),
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SQLite imports the old inventory once and preserves edits, activity, and deletion across restart', () async {
    sqfliteFfiInit();
    final directory = await Directory.systemTemp.createTemp(
      'esp_iot_sqlite_test_',
    );
    final path = '${directory.path}/inventory.db';
    addTearDown(() => directory.delete(recursive: true));
    var imports = 0;
    Future<String?> previous() async {
      imports++;
      return _oldRegistry([_verified()]);
    }

    final db = DeviceDatabase(databaseFactoryFfi, previous, path: path);
    addTearDown(db.close);
    final original = decodeRegistrations(await db.load()).single;
    expect(original.endpoint, testEndpoint);
    expect(original.usesOriginalStorageKeys, isTrue);
    expect((await db.history()).activity, isEmpty);
    final edited = original.withDetails(
      name: 'Desk sensor',
      room: 'Lab',
      category: 'Sensors',
      icon: DeviceIcon.sensor,
    );
    await db.save(encodeRegistrations([edited]));
    final time = _verifiedAt.add(const Duration(minutes: 3));
    await db.record(edited, time, opened: true);
    await db.record(edited, time, kind: ActivityKind.offline);
    expect((await db.history()).usage[edited.registrationId]?.lastSeen, isNull);
    await db.record(edited, time, kind: ActivityKind.connected, seen: time);
    await db.record(edited, time, kind: ActivityKind.applied);
    await db.record(edited, _verifiedAt, seen: _verifiedAt);
    await db.close();

    final reopened = DeviceDatabase(databaseFactoryFfi, previous, path: path);
    addTearDown(reopened.close);
    final saved = decodeRegistrations(await reopened.load()).single;
    expect(
      (saved.name, saved.room, saved.category, saved.icon),
      ('Desk sensor', 'Lab', 'Sensors', DeviceIcon.sensor),
    );
    expect(saved.registrationId, original.registrationId);
    final history = await reopened.history();
    expect(history.activity.map((event) => event.kind), [
      ActivityKind.applied,
      ActivityKind.connected,
      ActivityKind.offline,
    ]);
    expect(history.usage[saved.registrationId], (
      lastSeen: time,
      lastOpened: time,
    ));
    await reopened.save(encodeRegistrations([]));
    expect(
      (await reopened.pendingRemovals()).single.registrationId,
      saved.registrationId,
    );
    await reopened.close();

    final afterRemoval = DeviceDatabase(
      databaseFactoryFfi,
      previous,
      path: path,
    );
    addTearDown(afterRemoval.close);
    expect(decodeRegistrations(await afterRemoval.load()), isEmpty);
    expect(
      (await afterRemoval.pendingRemovals()).single.registrationId,
      saved.registrationId,
    );
    final replacement = DeviceRegistration.fromVerified(_verified());
    await afterRemoval.save(encodeRegistrations([replacement]));
    await afterRemoval.record(
      saved,
      time,
      kind: ActivityKind.connected,
      seen: time,
    );
    expect((await afterRemoval.history()).activity.map((event) => event.kind), [
      ActivityKind.registered,
    ]);
    expect(
      (await afterRemoval.history())
          .usage[replacement.registrationId]
          ?.lastSeen,
      isNull,
    );
    await afterRemoval.completeRemoval(saved.registrationId);
    expect(await afterRemoval.pendingRemovals(), isEmpty);
    expect(imports, 1);
  });

  test('reverifying a universal address preserves preferences and rejects identity changes or downgrade', () async {
    final store = TestRegistrationStore();
    final container = ProviderContainer(
      overrides: [registrationStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    final provider = container.read(deviceRegistryProvider.notifier);
    await provider.register(_verified(universal: true));
    final initial = container.read(deviceRegistryProvider).requireValue.single;
    await provider.edit(
      initial.registrationId,
      name: 'Bench',
      room: 'Lab',
      category: 'Lighting',
      icon: DeviceIcon.light,
    );
    final secure = LocalEndpoint('192.168.1.15', 443, secure: true);
    await expectLater(
      provider.verifyAddress(
        initial,
        _verified(
          endpoint: secure,
          universal: true,
          id: '33333333333333333333333333333333',
        ),
      ),
      throwsFormatException,
    );
    await provider.verifyAddress(
      initial,
      _verified(endpoint: secure, universal: true),
    );
    final updated = container.read(deviceRegistryProvider).requireValue.single;
    expect(updated.registrationId, initial.registrationId);
    expect(updated.endpoint, secure);
    expect(updated.name, 'Bench');
    await expectLater(
      provider.verifyAddress(updated, _verified(universal: true)),
      throwsFormatException,
    );
    final legacy = DeviceRegistration.fromVerified(_verified());
    expect(
      () => legacy.reverified(_verified(endpoint: secure)),
      throwsFormatException,
    );
  });

  test('a new registration at a previous address cannot read the old encrypted profile', () async {
    FlutterSecureStorage.setMockInitialValues({});
    const profiles = SecureApiProfileStore(FlutterSecureStorage());
    final original = decodeRegistrations(_oldRegistry([_verified()])).single;
    final replacement = DeviceRegistration.fromVerified(_verified());
    final config = SavedApiProfile(
      ApiProfile.parse('''
      {"transport":"rest","statusPath":"/status","response":{"format":"json"}}
    '''),
      const ApiCredential.none(),
    );
    await profiles.save(original, config);
    expect((await profiles.load(original))?.profile.statusPath, '/status');
    expect(await profiles.load(replacement), isNull);
    await profiles.save(replacement, config);
    await profiles.delete(original);
    expect(await profiles.load(original), isNull);
    expect(await profiles.load(replacement), isNotNull);
  });

  testWidgets(
    'device settings save details and require confirmation before removal',
    (tester) async {
      final store = TestRegistrationStore()..data = _oldRegistry([_verified()]);
      final device = decodeRegistrations(store.data!).single;
      final history = TestHistoryStore();
      await history.record(
        device,
        _verifiedAt,
        kind: ActivityKind.connected,
        seen: _verifiedAt,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            registrationStoreProvider.overrideWithValue(store),
            deviceHistoryStoreProvider.overrideWithValue(history),
          ],
          child: const MaterialApp(home: Scaffold(body: DevicesScreen())),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await tap(find.byTooltip('Settings for ${device.name}'));
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Workshop light');
      await tester.enterText(fields.at(1), 'Workshop');
      await tap(find.text('Save details'));
      expect(decodeRegistrations(store.data!).single.name, 'Workshop light');
      await tap(find.text('Connection history'));
      expect(find.text('Connected'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tap(find.text('Remove device'));
      await tap(find.text('Cancel'));
      expect(decodeRegistrations(store.data!), hasLength(1));
      await tap(find.text('Remove device'));
      await tap(find.widgetWithText(FilledButton, 'Remove device'));
      expect(decodeRegistrations(store.data!), isEmpty);
      expect(find.text('No registered devices'), findsOneWidget);
    },
  );
}
