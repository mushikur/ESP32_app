import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:esp_iot/core/protocol/device_descriptor.dart';
import 'package:esp_iot/features/devices/device_registry.dart';
import 'package:esp_iot/features/discovery/discovery_service.dart';
import 'package:esp_iot/features/discovery/local_discovery_platform.dart';
import 'package:esp_iot/features/discovery/local_endpoint.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_discovery.dart';

Matcher failure(String code) =>
    isA<DiscoveryFailure>().having((error) => error.code, 'code', code);

void main() {
  testWidgets('a stalled Android Wi-Fi lookup ends at the app deadline', (
    tester,
  ) async {
    const channel = MethodChannel('esp_iot/local_discovery');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final nativeReply = Completer<Object?>();
    messenger.setMockMethodCallHandler(channel, (_) => nativeReply.future);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final expectation = expectLater(
      AndroidLocalDiscovery().wifi(),
      throwsA(failure('timeout')),
    );
    await tester.pump(const Duration(seconds: 3));
    await expectation;
    nativeReply.complete(null);
    await tester.pump();
  });

  test('accepts the shared v1 descriptor fixture', () {
    final bytes = File('../protocol/v1/examples/bench-controller.json')
        .readAsBytesSync();
    final descriptor = DeviceDescriptor.decode(bytes);
    expect(descriptor.id, testDeviceId);
    expect(descriptor.capabilityCount, 13);
    expect(descriptor.requiresPairing, isTrue);
  });

  test(
    'rejects duplicate keys, invalid capabilities, and oversized descriptions',
    () {
      final valid = jsonEncode(descriptorFixture());
      final duplicate = valid.replaceFirst(
        '"name":',
        r'"name":"spoof","\u006eame":',
      );
      expect(
        () => DeviceDescriptor.decode(utf8.encode(duplicate)),
        throwsFormatException,
      );
      final data = descriptorFixture();
      final capabilities = data['capabilities']! as List;
      capabilities.add(capabilities.first);
      expect(
        () => DeviceDescriptor.decode(utf8.encode(jsonEncode(data))),
        throwsFormatException,
      );
      expect(
        () => DeviceDescriptor.decode(List.filled(32769, 32)),
        throwsFormatException,
      );
    },
  );

  test('rejects unsafe destinations and bounds an optional subnet check', () {
    for (final host in [
      '8.8.8.8',
      '127.0.0.1',
      '192.168.1.001',
      '192.168.1.10/admin',
      '192.168.1.10\n',
    ]) {
      expect(
        () => LocalEndpoint(host, 80, secure: false),
        throwsFormatException,
      );
    }
    expect(
      () => LocalEndpoint('192.168.1.10', 0, secure: false),
      throwsFormatException,
    );
    expect(() => WifiScope('192.168.1.20', 8, 100), throwsFormatException);
    expect(testWifi.contains('192.168.2.2'), isFalse);
    expect(testWifi.contains('192.168.1.20'), isFalse);
    expect(testWifi.contains('192.168.1.255'), isFalse);
    final hosts = testWifi.nearbyHosts().toList();
    expect(hosts, hasLength(32));
    expect(hosts.every(testWifi.contains), isTrue);
    expect(WifiScope('10.0.0.1', 30, 1).nearbyHosts(), ['10.0.0.2']);
  });

  test(
    'QR hints round-trip and reject links, tokens, and changed versions',
    () {
      final hint = PairingHint(testEndpoint, testDeviceId);
      final decoded = PairingHint.decode(hint.encode());
      expect(decoded.endpoint, testEndpoint);
      expect(decoded.deviceId, testDeviceId);
      final payload = jsonDecode(hint.encode()) as Map;
      expect(
        () => PairingHint.decode('https://192.168.1.10'),
        throwsFormatException,
      );
      expect(
        () => PairingHint.decode(jsonEncode({...payload, 'token': 'secret'})),
        throwsFormatException,
      );
      expect(
        () => PairingHint.decode(jsonEncode({...payload, 'version': 2})),
        throwsFormatException,
      );
    },
  );

  test('deduplicates mDNS and UDP and ignores bad nonce and off-link announcements', () async {
    final platform = TestDiscoveryPlatform()
      ..announcements = [
        {
          'host': testEndpoint.host,
          'port': 80,
          'secure': false,
          'service': 'Bench',
        },
        {'host': '192.168.2.10', 'port': 80, 'secure': false},
      ]
      ..udpReplies = (nonce) => [
        udpFixture(nonce),
        udpFixture('stale', host: '192.168.1.11'),
      ];
    final report = await DiscoveryService(platform)
        .search(DiscoveryCancellation());
    expect(report.devices.single.descriptor!.id, testDeviceId);
    expect(report.devices.single.hostname, 'Bench');
    expect(platform.probes.single.endpoint, testEndpoint);
    expect(platform.probes.single.quick, isTrue);
    expect(platform.probes.single.root, isFalse);
  });

  test(
    'validates a UDP-only offer and rejects a conflicting advertised identity',
    () async {
      final platform = TestDiscoveryPlatform()
        ..udpReplies = (nonce) => [udpFixture(nonce)];
      final service = DiscoveryService(platform);
      expect(
        (await service.search(DiscoveryCancellation())).devices.single.source,
        DiscoverySource.udp,
      );

      platform.announcements = [
        {
          'host': testEndpoint.host,
          'port': 80,
          'secure': false,
          'deviceId': 'ffffffffffffffffffffffffffffffff',
        },
      ];
      platform.probes.clear();
      final report = await service.search(DiscoveryCancellation());
      expect(report.devices, isEmpty);
      expect(report.warnings, contains(contains('Conflicting')));
      expect(platform.probes, isEmpty);
    },
  );

  test(
    'withholds the same device ID offered from two distinct origins',
    () async {
      final platform = TestDiscoveryPlatform()
        ..announcements = [
          {'host': '192.168.1.10', 'port': 80, 'secure': false},
          {'host': '192.168.1.11', 'port': 80, 'secure': false},
        ];
      final report = await DiscoveryService(platform)
          .search(DiscoveryCancellation());
      expect(report.devices, isEmpty);
      expect(report.warnings, contains(contains('Conflicting')));
    },
  );

  test(
    'subnet checks use one port and read only descriptors inside the link',
    () async {
      final platform = TestDiscoveryPlatform()
        ..scope = WifiScope('10.0.0.1', 30, 1);
      final report = await DiscoveryService(platform)
          .search(DiscoveryCancellation(), subnetPort: 8080);
      expect(
        report.devices.single.endpoint,
        LocalEndpoint('10.0.0.2', 8080, secure: false),
      );
      expect(platform.probes.single.root, isFalse);
      expect(platform.probes.single.quick, isTrue);
    },
  );

  test('manual address can verify a legacy web endpoint but QR requires its identity', () async {
    final platform = TestDiscoveryPlatform()
      ..reply = (_, root) => root
          ? const ProbeResponse(200, 'text/html', [])
          : const ProbeResponse(404, '', []);
    final service = DiscoveryService(platform);
    final legacy = await service.verify(testEndpoint, DiscoveryCancellation());
    expect(legacy.isLegacy, isTrue);
    expect(platform.probes.map((probe) => probe.root), [false, true]);
    platform.probes.clear();
    await expectLater(
      service.verify(
        testEndpoint,
        DiscoveryCancellation(),
        expectedId: testDeviceId,
      ),
      throwsA(failure('unsupported')),
    );
    expect(platform.probes.single.root, isFalse);
  });

  test(
    'rejects redirects, off-link probes, QR mismatches, and tokens over HTTP',
    () async {
      final platform = TestDiscoveryPlatform()
        ..reply = (_, _) => const ProbeResponse(302, '', []);
      final service = DiscoveryService(platform);
      await expectLater(
        service.verify(testEndpoint, DiscoveryCancellation()),
        throwsA(failure('redirect')),
      );
      expect(platform.probes.single.root, isFalse);
      platform.probes.clear();
      await expectLater(
        service.verify(
          LocalEndpoint('192.168.2.2', 80, secure: false),
          DiscoveryCancellation(),
        ),
        throwsA(failure('outsideWifi')),
      );
      expect(platform.probes, isEmpty);
      platform.reply = (_, _) => descriptorResponse();
      await expectLater(
        service.verify(
          testEndpoint,
          DiscoveryCancellation(),
          expectedId: 'ffffffffffffffffffffffffffffffff',
        ),
        throwsA(failure('identity')),
      );
      platform.reply = (_, _) => descriptorResponse(auth: 'pairing-token');
      await expectLater(
        service.verify(testEndpoint, DiscoveryCancellation()),
        throwsA(failure('insecurePairing')),
      );
    },
  );

  test('discards cancelled and changed-network results', () async {
    final platform = TestDiscoveryPlatform();
    final service = DiscoveryService(platform);
    final cancel = DiscoveryCancellation()..cancel();
    await expectLater(service.search(cancel), throwsA(failure('cancelled')));
    platform.reply = (_, _) {
      platform.scope = WifiScope('192.168.2.10', 24, 101);
      return descriptorResponse();
    };
    await expectLater(
      service.verify(testEndpoint, DiscoveryCancellation()),
      throwsA(failure('networkChanged')),
    );
  });

  test('discovery and HTTPS verification require active Wi-Fi', () async {
    final secondary = WifiScope(
      testWifi.address,
      testWifi.prefix,
      testWifi.networkId,
      isDefault: false,
    );
    final platform = TestDiscoveryPlatform()..scope = secondary;
    final service = DiscoveryService(platform);
    final endpoint = LocalEndpoint(testEndpoint.host, 443, secure: true);
    await expectLater(
      service.verify(endpoint, DiscoveryCancellation()),
      throwsA(failure('wifiNotDefault')),
    );
    await expectLater(
      service.search(DiscoveryCancellation()),
      throwsA(failure('wifiNotDefault')),
    );
    await expectLater(
      service.search(
        DiscoveryCancellation(),
        subnetPort: 443,
        subnetSecure: true,
      ),
      throwsA(failure('wifiNotDefault')),
    );
    expect(platform.probes, isEmpty);

    platform
      ..scope = testWifi
      ..reply = (_, _) {
        platform.scope = secondary;
        return descriptorResponse();
      };
    await expectLater(
      service.verify(endpoint, DiscoveryCancellation()),
      throwsA(failure('networkChanged')),
    );
  });

  test('serializes duplicate registrations and preserves the inventory on a failed write', () async {
    final storage = TestRegistrationStore();
    final provider = ProviderContainer(
      overrides: [registrationStoreProvider.overrideWithValue(storage)],
    );
    addTearDown(provider.dispose);
    final service = DiscoveryService(TestDiscoveryPlatform());
    final device = await service.verify(testEndpoint, DiscoveryCancellation());
    final registry = provider.read(deviceRegistryProvider.notifier);
    await Future.wait([registry.register(device), registry.register(device)]);
    expect(storage.writes, 1);
    expect(provider.read(deviceRegistryProvider).value, hasLength(1));
    expect(storage.data, isNot(contains('token')));

    final platform = TestDiscoveryPlatform()
      ..reply = (_, _) =>
          descriptorResponse(id: 'ffffffffffffffffffffffffffffffff');
    final other = await DiscoveryService(platform).verify(
      LocalEndpoint('192.168.1.11', 80, secure: false),
      DiscoveryCancellation(),
    );
    storage.failWrites = true;
    await expectLater(registry.register(other), throwsException);
    expect(provider.read(deviceRegistryProvider).value, hasLength(1));
    storage.failWrites = false;
    await registry.register(other);
    final reopened = ProviderContainer(
      overrides: [registrationStoreProvider.overrideWithValue(storage)],
    );
    addTearDown(reopened.dispose);
    expect(await reopened.read(deviceRegistryProvider.future), hasLength(2));
  });
}
