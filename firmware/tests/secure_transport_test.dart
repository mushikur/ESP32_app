import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:esp_iot/core/protocol/device_descriptor.dart';
import 'package:esp_iot/core/transport/lan_transport.dart';
import 'package:esp_iot/features/connection/device_session.dart';
import 'package:esp_iot/features/connection/lan_universal_connector.dart';
import 'package:esp_iot/features/connection/secure_pairing.dart';
import 'package:esp_iot/features/devices/device_registration.dart';
import 'package:esp_iot/features/discovery/discovery_service.dart';
import 'package:esp_iot/features/discovery/local_discovery_platform.dart';
import 'package:esp_iot/features/discovery/local_endpoint.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../app/test/support/test_discovery.dart';

const _boot = '11111111111111111111111111111111';
const _code = '28461357';

class _Endpoint implements LocalEndpoint {
  const _Endpoint(this.port, this.certificateSha256, {this.secure = true});
  @override
  String get host => '127.0.0.1';
  @override
  final int port;
  @override
  final bool secure;
  @override
  final String? certificateSha256;
  @override
  String get scheme => secure ? 'https' : 'http';
  @override
  String get origin => '$scheme://$host:$port';
}

class _Wifi implements WifiScope {
  const _Wifi();
  @override
  bool get isDefault => true;
  @override
  bool contains(String host) => host == '127.0.0.1';
  @override
  bool sameLink(WifiScope other) => identical(this, other);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'real HTTPS and WSS enforce the enrolled certificate and device token',
    () async {
      const certPath = String.fromEnvironment('ESP_IOT_TEST_CERT');
      const keyPath = String.fromEnvironment('ESP_IOT_TEST_KEY');
      expect(
        certPath,
        isNotEmpty,
        reason: 'Run firmware/tests/test-secure-transport.ps1',
      );
      final pem = await File(certPath).readAsString();
      final pin = sha256
          .convert(
            base64Decode(pem.replaceAll(RegExp(r'-----[^-]+-----|\s'), '')),
          )
          .toString();
      final context = SecurityContext()
        ..useCertificateChain(certPath)
        ..usePrivateKey(keyPath);
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      final sockets = <WebSocket>[];
      addTearDown(() async {
        for (final socket in sockets) {
          await socket.close();
        }
        await server.close(force: true);
      });
      final token = List.filled(32, 'ab').join();
      final descriptor = {
        ...descriptorFixture(auth: 'pairing-token'),
        'events': true,
      };
      var requests = 0;
      var enrollmentRequests = 0;
      var redirects = 0;
      var issued = false;
      var revoked = false;
      var led = false;
      var sequence = 0;
      Map<String, Object?> snapshot() => {
        'deviceId': testDeviceId,
        'revision': 1,
        'bootId': _boot,
        'seq': ++sequence,
        'values': {'led': led},
      };

      server.listen((request) async {
        requests++;
        final path = request.uri.path;
        final authorized =
            issued &&
            !revoked &&
            request.headers.value('authorization') == 'Bearer $token';
        Object? body;
        if (path == '/.well-known/esp-iot') {
          body = descriptor;
        } else if (path == '/api/v1/pair') {
          enrollmentRequests++;
          final enrollment =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          if (!issued &&
              enrollment['deviceId'] == testDeviceId &&
              enrollment['code'] == _code) {
            issued = true;
            body = {'deviceId': testDeviceId, 'token': token};
          } else {
            request.response.statusCode = 401;
          }
        } else if (!authorized) {
          request.response.statusCode = 401;
        } else if (path == '/api/v1/status') {
          body = snapshot();
        } else if (path == '/api/v1/events') {
          final socket = await WebSocketTransformer.upgrade(request);
          sockets.add(socket);
          socket.add(jsonEncode(snapshot()));
          return;
        } else if (path == '/api/v1/commands') {
          final command =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          led = command['value'] == true;
          body = {
            'commandId': command['commandId'],
            'deviceId': testDeviceId,
            'bootId': _boot,
            'revision': 1,
            'outcome': 'applied',
          };
          for (final socket in sockets.where(
            (item) => item.readyState == WebSocket.open,
          )) {
            socket.add(jsonEncode(snapshot()));
          }
        } else if (path == '/api/v1/pairing' && request.method == 'DELETE') {
          revoked = true;
          request.response.statusCode = 204;
        } else if (path == '/redirect') {
          request.response.statusCode = 307;
          request.response.headers.set('location', '/other');
        } else if (path == '/other') {
          redirects++;
        }
        if (body != null) {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(body));
        }
        await request.response.close();
      });

      final platform = TestDiscoveryPlatform()..scope = const _Wifi();
      final transport = LanTransport(platform);
      DeviceRegistration registration(String? selected, {int? port}) =>
          DeviceRegistration.fromVerified(
            VerifiedDevice(
              endpoint: _Endpoint(port ?? server.port, selected),
              scope: const _Wifi(),
              source: DiscoverySource.manual,
              checkedAt: DateTime.now(),
              descriptor: DeviceDescriptor.decode(
                utf8.encode(jsonEncode(descriptor)),
              ),
            ),
          );
      Matcher problem(ConnectionProblem value) => isA<ConnectionFailure>()
          .having((error) => error.problem, 'problem', value);

      await HttpOverrides.runWithHttpOverrides(() async {
        const store = SecurePairingStore(FlutterSecureStorage());
        FlutterSecureStorage.setMockInitialValues({});
        final pairing = SecurePairing(transport);
        final device = registration(pin);
        final cancel = DiscoveryCancellation();
        final wrongPin = pin[0] == '0'
            ? '1${pin.substring(1)}'
            : '0${pin.substring(1)}';
        await expectLater(
          pairing.enroll(registration(wrongPin), _code, cancel),
          throwsA(problem(ConnectionProblem.certificate)),
        );
        await expectLater(
          pairing.enroll(registration(null), _code, cancel),
          throwsA(problem(ConnectionProblem.certificate)),
        );
        expect(requests, 0);
        final clear = await transport.open(
          _Endpoint(server.port, null, secure: false),
        );
        await expectLater(
          clear.request(
            'GET',
            '/api/v1/status',
            cancel,
            headers: {'Authorization': 'Bearer $token'},
          ),
          throwsA(problem(ConnectionProblem.authentication)),
        );
        expect(requests, 0);

        expect(
          await checkDeviceConnection(device, transport, null, cancel),
          SessionPhase.authorization,
        );
        await expectLater(
          pairing.enroll(device, '00000000', cancel),
          throwsA(problem(ConnectionProblem.authentication)),
        );
        final credential = await pairing.enroll(device, _code, cancel);
        expect(enrollmentRequests, 2);
        await store.save(device, credential);
        final restored = await store.load(device);
        expect(restored, isNotNull);
        expect(
          restored!.headers(
            registration(pin, port: server.port == 443 ? 8443 : 443),
          ),
          isEmpty,
        );
        expect(restored.headers(registration(wrongPin)), isEmpty);
        expect(
          await checkDeviceConnection(
            device,
            transport,
            null,
            cancel,
            pairing: restored,
          ),
          SessionPhase.connected,
        );

        final session = DeviceSession();
        final event = Completer<void>();
        void waitForEvent() {
          if (!event.isCompleted &&
              session.detail?.contains('verified live event') == true)
            event.complete();
        }

        session.addListener(waitForEvent);
        try {
          session.startUniversal(
            LanUniversalConnector(transport, device, pairing: restored),
          );
          await event.future.timeout(const Duration(seconds: 8));
          expect(session.canControl, isTrue);
          await session.sendControl(session.controlContext, 'led', 'set', true);
          expect(led, isTrue);
          expect(session.commandResult, 'Device acknowledged the command.');
        } finally {
          session.dispose();
        }

        final link = await transport.open(device.endpoint);
        await expectLater(
          link.request(
            'GET',
            '/redirect',
            cancel,
            headers: restored.headers(device),
          ),
          throwsA(problem(ConnectionProblem.redirect)),
        );
        expect(redirects, 0);
        await pairing.revoke(device, restored, cancel);
        expect(
          await checkDeviceConnection(
            device,
            transport,
            null,
            cancel,
            pairing: restored,
          ),
          SessionPhase.authorization,
        );
        await store.delete(device);
        expect(await store.load(device), isNull);
        await expectLater(
          pairing.enroll(device, _code, cancel),
          throwsA(problem(ConnectionProblem.authentication)),
        );
      }, _RealHttp());
    },
  );
}
