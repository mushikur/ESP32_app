import 'dart:convert';
import 'dart:typed_data';

import 'package:esp_iot/core/protocol/device_descriptor.dart';
import 'package:esp_iot/core/transport/lan_transport.dart';
import 'package:esp_iot/features/connection/device_connection_screen.dart';
import 'package:esp_iot/features/connection/secure_pairing.dart';
import 'package:esp_iot/features/devices/device_database.dart';
import 'package:esp_iot/features/devices/device_registration.dart';
import 'package:esp_iot/features/discovery/discovery_service.dart';
import 'package:esp_iot/features/discovery/local_endpoint.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_discovery.dart';

final _pin = List.filled(32, 'ac').join();
final _token = List.filled(32, 'b3').join();
final _descriptor = descriptorFixture(auth: 'pairing-token');
const _code = '23901476';
final _device = DeviceRegistration.fromVerified(
  VerifiedDevice(
    endpoint: LocalEndpoint(
      '192.168.1.15',
      8443,
      secure: true,
      certificateSha256: _pin,
    ),
    scope: testWifi,
    source: DiscoverySource.manual,
    checkedAt: DateTime.utc(2026),
    descriptor: DeviceDescriptor.decode(utf8.encode(jsonEncode(_descriptor))),
  ),
);

void main() {
  test('certificate pins survive QR and registration round trips and require HTTPS', () {
    final hint = PairingHint.decode(_device.pairingHint!.encode());
    expect(hint.endpoint.certificateSha256, _pin);
    expect(hint.deviceId, _device.deviceId);
    final restored = DeviceRegistration.fromJson(_device.toJson());
    expect(restored.endpoint.certificateSha256, _pin);
    expect(
      () => PairingHint.decode(
        _device.pairingHint!.encode().replaceFirst('"https"', '"http"'),
      ),
      throwsFormatException,
    );
    expect(
      () => LocalEndpoint(
        '192.168.1.15',
        8443,
        secure: true,
        certificateSha256: '123',
      ),
      throwsFormatException,
    );
  });

  testWidgets(
    'pairing screen authorizes only after enrollment and supports confirmed revocation',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      const store = SecurePairingStore(FlutterSecureStorage());
      final transport = _PairingFixture();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pairingStoreProvider.overrideWithValue(store),
            deviceTransportProvider.overrideWithValue(transport),
            deviceHistoryStoreProvider.overrideWithValue(TestHistoryStore()),
          ],
          child: MaterialApp(home: DeviceConnectionScreen(device: _device)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Authorization required'), findsOneWidget);
      expect(transport.paths, ['/.well-known/esp-iot']);
      await tester.tap(find.text('Pair securely'));
      await tester.pumpAndSettle();
      final submit = find.widgetWithText(FilledButton, 'Pair device');
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      await tester.enterText(find.byType(TextField), _code);
      await tester.pump();
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.text('Secure pairing saved.'), findsOneWidget);
      expect(find.text('Connected'), findsOneWidget);
      expect(await store.load(_device), isNotNull);

      await tester.tap(find.text('Remove pairing'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove pairing'));
      await tester.pumpAndSettle();
      expect(find.text('Authorization required'), findsOneWidget);
      expect(await store.load(_device), isNull);
      expect(transport.revoked, isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}

class _PairingFixture implements DeviceTransport, DeviceLink {
  final paths = <String>[];
  bool revoked = false;

  @override
  Future<DeviceLink> open(LocalEndpoint endpoint) async => this;
  @override
  Future<void> checkNetwork() async {}
  @override
  Future<DeviceSocket> websocket(
    String path,
    ConnectionCancellation cancel, {
    Map<String, String> headers = const {},
  }) => throw StateError('The fixture advertises REST.');

  @override
  Future<LanResponse> request(
    String method,
    String path,
    ConnectionCancellation cancel, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    cancel.check();
    paths.add(path);
    LanResponse json(Object data) => LanResponse(
      200,
      'application/json',
      Uint8List.fromList(utf8.encode(jsonEncode(data))),
    );
    if (path == '/.well-known/esp-iot') return json(_descriptor);
    if (path == '/api/v1/pair') {
      final data = jsonDecode(body!) as Map;
      if (data['code'] != _code || data['deviceId'] != testDeviceId) {
        throw const ConnectionFailure(ConnectionProblem.authentication);
      }
      return json({'deviceId': testDeviceId, 'token': _token});
    }
    if (headers['Authorization'] != 'Bearer $_token' || revoked) {
      throw const ConnectionFailure(ConnectionProblem.authentication);
    }
    if (path == '/api/v1/pairing' && method == 'DELETE') {
      revoked = true;
      return LanResponse(204, '', Uint8List(0));
    }
    return json({
      'deviceId': testDeviceId,
      'bootId': '11111111111111111111111111111111',
      'revision': 1,
      'seq': 1,
      'values': {'led': false},
    });
  }
}
