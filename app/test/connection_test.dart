import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:esp_iot/core/protocol/device_command.dart';
import 'package:esp_iot/core/protocol/device_descriptor.dart';
import 'package:esp_iot/core/protocol/device_status.dart';
import 'package:esp_iot/core/transport/lan_transport.dart';
import 'package:esp_iot/core/transport/universal_transport.dart';
import 'package:esp_iot/features/connection/api_profile.dart';
import 'package:esp_iot/features/connection/device_connection_screen.dart';
import 'package:esp_iot/features/connection/device_session.dart';
import 'package:esp_iot/features/connection/lan_universal_connector.dart';
import 'package:esp_iot/features/connection/profile_store.dart';
import 'package:esp_iot/features/dashboard/dashboard_layout.dart';
import 'package:esp_iot/features/devices/device_database.dart';
import 'package:esp_iot/features/devices/device_registry.dart';
import 'package:esp_iot/features/discovery/discovery_service.dart';
import 'package:esp_iot/features/discovery/local_discovery_platform.dart';
import 'package:esp_iot/features/discovery/local_endpoint.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_discovery.dart';

const _rest = '''
{
  "transport":"rest","statusPath":"/status","pollSeconds":10,
  "response":{"format":"json","pointer":"/led"},
  "action":{"method":"POST","path":"/identify","body":{"identify":true},
    "response":{"format":"json","pointer":"/ok","equals":true}}
}''';

const _socket = '''
{
  "transport":"websocket","statusPath":"/ws","pollSeconds":10,
  "response":{"format":"json","pointer":"/led"},
  "action":{"message":{"op":"identify"},"correlationField":"requestId",
    "response":{"format":"json","pointer":"/ok","equals":true}}
}''';

const _mappedSocket = '''
{
  "transport":"websocket","statusPath":"/ws","response":{"format":"json"},
  "controls":[
    {"id":"speed","name":"Speed","type":"range","pointer":"/speed","min":0,"max":100,"step":5,"unit":"%","valueField":"speed",
     "set":{"message":{"op":"setSpeed"},"correlationField":"correlation","response":{"pointer":"/ok","equals":true}}},
    {"id":"temperature","name":"Temperature","type":"sensor","pointer":"/temperature","unit":"°C"}
  ]
}''';

const _bootId = '11111111111111111111111111111111';

Map<String, Object?> _status(int sequence, Map<String, Object?> values) => {
  'deviceId': testDeviceId,
  'bootId': _bootId,
  'revision': 1,
  'seq': sequence,
  'values': values,
};

Map<String, Object?> _dashboardDescriptor({bool events = false}) => {
  ...descriptorFixture(),
  'events': events,
  'capabilities': [
    {'id': 'led', 'name': 'LED', 'type': 'switch', 'confirm': false},
    {
      'id': 'fan',
      'name': 'Fan speed',
      'type': 'range',
      'confirm': true,
      'min': 0,
      'max': 100,
      'step': 5,
      'unit': '%',
    },
    {
      'id': 'temperature',
      'name': 'Temperature',
      'type': 'sensor',
      'unit': '°C',
    },
    {
      'id': 'drive',
      'name': 'Drive',
      'type': 'motion',
      'directions': ['forward', 'reverse'],
      'maxDurationMs': 500,
    },
    {'id': 'other', 'name': 'Other', 'type': 'x-example-extra'},
  ],
};

SavedApiProfile _profile(String text) =>
    SavedApiProfile(ApiProfile.parse(text), const ApiCredential.none());

DeviceRegistration _device({bool universal = false, bool secure = false}) {
  final descriptor = universal
      ? DeviceDescriptor.decode(utf8.encode(jsonEncode(descriptorFixture())))
      : null;
  return DeviceRegistration.fromVerified(
    VerifiedDevice(
      endpoint: LocalEndpoint(
        testEndpoint.host,
        secure ? 443 : 80,
        secure: secure,
      ),
      scope: testWifi,
      source: DiscoverySource.manual,
      checkedAt: DateTime.utc(2026),
      descriptor: descriptor,
    ),
  );
}

LanResponse _json(Object? data, {int status = 200}) => LanResponse(
  status,
  'application/json',
  Uint8List.fromList(utf8.encode(jsonEncode(data))),
);

void main() {
  test('a saved registration needs a matching status response to pass a health check', () async {
    final transport = _TestTransport();
    final cancel = DiscoveryCancellation();
    expect(
      await checkDeviceConnection(_device(), transport, null, cancel),
      SessionPhase.idle,
    );
    expect(transport.link.requests, isEmpty);
    final device = _device(universal: true);
    transport.link.descriptor = descriptorFixture(
      id: '22222222222222222222222222222222',
    );
    expect(
      await checkDeviceConnection(device, transport, null, cancel),
      SessionPhase.error,
    );
    expect(transport.link.requests, [('GET', '/.well-known/esp-iot')]);
    transport.link.descriptor = descriptorFixture();
    expect(
      await checkDeviceConnection(device, transport, null, cancel),
      SessionPhase.connected,
    );
    transport.link.failedReads = 1;
    expect(
      await checkDeviceConnection(
        _device(),
        transport,
        _profile(_rest),
        cancel,
      ),
      SessionPhase.offline,
    );
  });
  test('typed commands bind their acknowledgement to the active boot and capability', () {
    final descriptor = DeviceDescriptor.decode(
      utf8.encode(jsonEncode(_dashboardDescriptor())),
    );
    final snapshot = DeviceStatus.parse(_status(1, {'led': false}), descriptor);
    final command = DeviceCommand(descriptor, snapshot, 'fan', 'set', 35);
    expect(jsonDecode(command.body), {
      'commandId': command.id,
      'bootId': _bootId,
      'revision': 1,
      'capabilityId': 'fan',
      'op': 'set',
      'value': 35,
    });
    final ack = {
      'commandId': command.id,
      'deviceId': testDeviceId,
      'bootId': _bootId,
      'revision': 1,
      'outcome': 'applied',
    };
    expect(command.readAcknowledgement(ack), DeviceAcknowledgement.applied);
    expect(
      () => readLanAcknowledgement(command, _json(ack, status: 202)),
      throwsFormatException,
    );
    expect(
      readLanAcknowledgement(
        command,
        _json({...ack, 'outcome': 'rejected', 'code': 'busy'}, status: 429),
      ),
      DeviceAcknowledgement.rejected,
    );
    expect(
      () => command.readAcknowledgement({...ack, 'bootId': testDeviceId}),
      throwsFormatException,
    );
    expect(
      () => command.readAcknowledgement({...ack, 'commandId': testDeviceId}),
      throwsFormatException,
    );
    expect(
      () => DeviceCommand(descriptor, snapshot, 'fan', 'set', 36),
      throwsFormatException,
    );
    expect(
      () => DeviceCommand(descriptor, snapshot, 'drive', 'move', null),
      throwsFormatException,
    );
    expect(
      () => DeviceCommand(descriptor, snapshot, 'temperature', 'set', 10),
      throwsFormatException,
    );
    expect(
      jsonDecode(
        DeviceCommand(descriptor, snapshot, 'drive', 'stop', null).body,
      ).containsKey('value'),
      isFalse,
    );
  });

  test('legacy mappings reject invalid reads, command definitions and duplicate IDs', () {
    final profile = ApiProfile.parse(_mappedSocket);
    expect(profile.controls['speed']!.read({'speed': 25}), 25);
    expect(profile.controls['speed']!.read({'speed': '25'}), isNull);
    expect(profile.controls['temperature']!.read({}), isNull);
    expect(profile.acknowledgementFields, {'correlation'});
    expect(
      () =>
          ApiProfile.parse(_mappedSocket.replaceFirst('"step":5', '"step":3')),
      throwsFormatException,
    );
    expect(
      () => ApiProfile.parse(
        _mappedSocket.replaceFirst('"valueField":"speed"', '"valueField":"op"'),
      ),
      throwsFormatException,
    );
    expect(
      () => ApiProfile.parse(
        _mappedSocket.replaceFirst('"equals":true', '"status":200'),
      ),
      throwsFormatException,
    );
    expect(
      () => ApiProfile.parse(
        _mappedSocket.replaceFirst('"id":"temperature"', '"id":"speed"'),
      ),
      throwsFormatException,
    );
  });

  testWidgets(
    'mapped WebSocket writes correlate acknowledgements and retain verified readings',
    (tester) async {
      final transport = _TestTransport();
      final session = DeviceSession()
        ..startLegacy(transport, _device().endpoint, _profile(_mappedSocket));
      await tester.pump();
      final socket = transport.link.socket;
      socket.events.add('{"speed":25,"temperature":22}');
      await tester.pump();
      expect(session.controlValues['speed'], 25);
      final write = session.sendControl(
        session.controlContext,
        'speed',
        'set',
        40,
      );
      await tester.pump();
      final message = jsonDecode(socket.sent.single) as Map;
      expect(message, containsPair('op', 'setSpeed'));
      expect(message, containsPair('speed', 40));
      socket.events.add('{"correlation":"unrelated","ok":true,"speed":50}');
      await tester.pump();
      expect(session.commandBusy, isTrue);
      expect(session.controlValues['speed'], 25);
      socket.events.add(
        jsonEncode({'correlation': message['correlation'], 'ok': true}),
      );
      await tester.pump();
      await write;
      expect(session.commandResult, 'The correlated acknowledgement matched.');
      expect(session.controlValues['speed'], 25);
      for (var index = 0; index < 63; index++) {
        socket.events.add(jsonEncode({'speed': 40, 'temperature': index}));
      }
      await tester.pump();
      expect(session.controlValues['speed'], 40);
      expect(session.history('temperature'), hasLength(60));
      expect(session.history('temperature').last.value, 62);
      session.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'universal writes wait for matching acknowledgements and a fresh status snapshot',
    (tester) async {
      final transport = _TestTransport();
      final link = transport.link
        ..descriptor = _dashboardDescriptor(events: true);
      link.universalStatus = _status(1, {'led': false, 'temperature': 22});
      final session = DeviceSession()
        ..startUniversal(
          LanUniversalConnector(transport, _device(universal: true)),
        );
      await tester.pump();
      final currentContext = session.controlContext;
      link.badAcknowledgement = true;
      await session.sendControl(currentContext, 'led', 'set', true);
      expect(session.commandResult, startsWith('Command unconfirmed'));
      expect(link.commands, hasLength(1));
      link.badAcknowledgement = false;
      await session.sendControl(currentContext, 'led', 'set', true);
      expect(session.commandResult, 'Device acknowledged the command.');
      expect(session.controlValues['led'], isFalse);
      link.socket.events.add(
        jsonEncode(_status(2, {'led': true, 'temperature': 24})),
      );
      await tester.pump();
      expect(session.controlValues['led'], isTrue);
      expect(session.history('temperature').map((sample) => sample.value), [
        22,
        24,
      ]);
      session.pause();
      await session.sendControl(currentContext, 'led', 'set', false);
      expect(link.commands, hasLength(2));
      session.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'a typed connector works without a LAN registration and stops on revocation',
    (tester) async {
      final connection = _TypedConnection();
      final outcomes = <CommandOutcome>[];
      final session = DeviceSession(onCommand: outcomes.add)
        ..startUniversal(connection);
      await tester.pump();
      expect(session.phase, SessionPhase.checking);
      expect(session.lastContact, isNull);

      connection.initial.complete(connection.snapshot(2, false));
      await tester.pump();
      expect(session.phase, SessionPhase.connected);
      final context = session.controlContext;
      await session.sendControl(context, 'led', 'set', true);
      expect(outcomes, [CommandOutcome.applied]);
      expect(session.controlValues['led'], isFalse);

      connection.events.add(connection.snapshot(1, true));
      await tester.pump();
      expect(session.controlValues['led'], isFalse);
      connection.events.add(connection.snapshot(3, true));
      await tester.pump();
      expect(session.controlValues['led'], isTrue);

      connection.events.addError(
        const ConnectionFailure(ConnectionProblem.authentication),
      );
      await tester.pump();
      expect(session.phase, SessionPhase.authorization);
      expect(connection.closed, isTrue);
      await session.sendControl(context, 'led', 'set', false);
      expect(connection.commands, hasLength(1));
      session.dispose();
      await tester.pump();
    },
  );

  testWidgets('a universal LAN retry uses the original Wi-Fi binding', (
    tester,
  ) async {
    final transport = _TestTransport();
    transport.link.failedReads = 1;
    final session = DeviceSession()
      ..startUniversal(
        LanUniversalConnector(transport, _device(universal: true)),
      );
    await tester.pump();
    expect(session.phase, SessionPhase.reconnecting);
    transport.link.changed = true;
    await tester.pump(const Duration(seconds: 2));
    expect(session.phase, SessionPhase.error);
    expect(transport.opens, 1);
    expect(session.lastContact, isNull);
    session.dispose();
    await tester.pump();
  });

  testWidgets(
    'dashboard lays out capabilities, retains Stop, and persists tile changes',
    (tester) async {
      final transport = _TestTransport();
      final link = transport.link..descriptor = _dashboardDescriptor();
      link.universalStatus = _status(1, {
        'led': false,
        'fan': 25,
        'temperature': 22,
        'drive': 'stopped',
      });
      final store = _TestLayouts();
      final device = _device(universal: true);
      Widget app() => ProviderScope(
        overrides: [
          deviceTransportProvider.overrideWithValue(transport),
          deviceHistoryStoreProvider.overrideWithValue(TestHistoryStore()),
          dashboardLayoutStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(home: DeviceConnectionScreen(device: device)),
      );
      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('Reported 25 %'), findsOneWidget);
      expect(find.text('22 °C'), findsOneWidget);
      expect(find.text('This capability type is unsupported.'), findsOneWidget);
      await tap(find.text('Stop Drive'));
      expect(link.commands.single['op'], 'stop');
      expect(find.byType(AlertDialog), findsNothing);
      final slider = find.byType(Slider);
      tester.widget<Slider>(slider).onChanged!(7);
      await tester.pump();
      expect(link.commands, hasLength(1));
      await tap(find.text('Apply value'));
      expect(find.text('Set Fan speed to 35 %?'), findsOneWidget);
      await tap(find.text('Send once'));
      expect(link.commands.last['value'], 35);
      await tap(find.text('Edit dashboard'));
      await tap(find.byTooltip('Edit LED appearance'));
      await tester.enterText(find.byType(TextFormField), 'Desk light');
      await tap(find.text('Apply'));
      await tap(find.byTooltip('Move Fan speed up'));
      await tap(find.widgetWithText(TextButton, 'Remove').last);
      await tap(find.text('Save dashboard'));
      expect(store.saved.map((tile) => tile.id), [
        'fan',
        'led',
        'temperature',
        'other',
      ]);
      expect(store.saved[1].name, 'Desk light');
      expect(store.saved.last.hidden, isTrue);
      expect(store.saved.any((tile) => tile.id == 'drive'), isFalse);
      expect(find.text('Stop Drive'), findsOneWidget);
      expect(find.text('Desk light'), findsOneWidget);
      expect(find.text('Other'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('Desk light'), findsOneWidget);
      expect(find.text('Other'), findsNothing);
      expect(find.text('Stop Drive'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  test('real local REST and WebSocket exchanges keep their origin and acknowledge commands', () async {
    HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress('127.0.0.2'), 0);
    } on SocketException {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    }
    addTearDown(() => server.close(force: true));
    var restWrites = 0;
    var socketWrites = 0;
    var redirectedRequests = 0;
    final sockets = <WebSocket>[];
    addTearDown(() async {
      for (final socket in sockets) {
        await socket.close();
      }
    });
    server.listen((request) async {
      switch (request.uri.path) {
        case '/identify':
          final body =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          if (request.method == 'POST' && body['identify'] == true) {
            restWrites++;
          }
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'ok': restWrites == 1}));
        case '/redirect':
        case '/upgrade-redirect':
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set('location', '/followed');
        case '/followed':
          redirectedRequests++;
        case '/ws':
          final socket = await WebSocketTransformer.upgrade(request);
          sockets.add(socket);
          socket.add('{"led":false}');
          socket.listen((message) {
            final payload = jsonDecode(message as String) as Map;
            if (payload['op'] == 'identify') socketWrites++;
            socket.add(
              jsonEncode({
                'requestId': payload['requestId'],
                'ok': socketWrites == 1,
              }),
            );
          });
          return;
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final endpoint = _LoopbackEndpoint(server.address.address, server.port);
    final platform = TestDiscoveryPlatform()
      ..scope = _LoopbackScope(endpoint.host);
    final cancel = DiscoveryCancellation();
    addTearDown(cancel.cancel);
    await HttpOverrides.runWithHttpOverrides(() async {
      final link = await LanTransport(platform).open(endpoint);
      final response = await link.request(
        'POST',
        '/identify',
        cancel,
        body: '{"identify":true}',
      );
      expect(response.status, 200);
      expect(jsonDecode(utf8.decode(response.bytes)), {'ok': true});
      await expectLater(
        link.request('GET', '/redirect', cancel),
        throwsA(
          isA<ConnectionFailure>().having(
            (failure) => failure.problem,
            'problem',
            ConnectionProblem.redirect,
          ),
        ),
      );
      await expectLater(
        link.websocket('/upgrade-redirect', cancel),
        throwsA(
          isA<ConnectionFailure>().having(
            (failure) => failure.problem,
            'problem',
            ConnectionProblem.redirect,
          ),
        ),
      );
      final socket = await link.websocket('/ws', cancel);
      final reader = StreamIterator(socket.messages);
      try {
        expect(
          await reader.moveNext().timeout(const Duration(seconds: 3)),
          isTrue,
        );
        expect(reader.current, '{"led":false}');
        socket.send('{"op":"identify","requestId":"local-test"}');
        expect(
          await reader.moveNext().timeout(const Duration(seconds: 3)),
          isTrue,
        );
        expect(jsonDecode(reader.current as String), {
          'requestId': 'local-test',
          'ok': true,
        });
      } finally {
        socket.close();
        await reader.cancel();
      }
    }, _RealHttpOverrides());
    expect(restWrites, 1);
    expect(socketWrites, 1);
    expect(redirectedRequests, 0);
  });

  test('cleartext discovery reads only a bounded JSON descriptor', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requests = <(String, String, String?, String?)>[];
    var content = jsonEncode(descriptorFixture());
    var mediaType = ContentType.json;
    server.listen((request) async {
      requests.add((
        request.method,
        request.uri.path,
        request.headers.value(HttpHeaders.authorizationHeader),
        request.headers.value('x-api-key'),
      ));
      request.response.headers.contentType = mediaType;
      request.response.write(content);
      await request.response.close();
    });
    final endpoint = _LoopbackEndpoint(server.address.address, server.port);
    final platform = TestDiscoveryPlatform()
      ..scope = _LoopbackScope(endpoint.host);
    final scope = platform.scope;
    final transport = LanTransport(platform);
    final cancel = DiscoveryCancellation();
    addTearDown(cancel.cancel);

    Future<LanResponse> probe({bool root = false}) => transport.probeCleartext(
      scope,
      endpoint,
      cancel,
      root: root,
      quick: false,
    );

    await HttpOverrides.runWithHttpOverrides(() async {
      final descriptor = await probe();
      expect(descriptor.status, 200);
      expect(descriptor.contentType, 'application/json');
      expect(utf8.decode(descriptor.bytes), content);

      content = ' ' * (40 * 1024);
      await expectLater(
        probe(),
        throwsA(
          isA<ConnectionFailure>().having(
            (failure) => failure.problem,
            'problem',
            ConnectionProblem.tooLarge,
          ),
        ),
      );
      mediaType = ContentType.html;
      final fallback = await probe();
      expect(fallback.contentType, 'text/html');
      expect(fallback.bytes, isEmpty);
      final panel = await probe(root: true);
      expect(panel.status, 200);
      expect(panel.bytes, isEmpty);

      platform.scope = testWifi;
      await expectLater(
        probe(),
        throwsA(
          isA<ConnectionFailure>().having(
            (failure) => failure.problem,
            'problem',
            ConnectionProblem.changed,
          ),
        ),
      );
    }, _RealHttpOverrides());
    expect(requests, [
      ('GET', '/.well-known/esp-iot', null, null),
      ('GET', '/.well-known/esp-iot', null, null),
      ('GET', '/.well-known/esp-iot', null, null),
      ('GET', '/', null, null),
    ]);
  });

  test('validates profile paths, headers, polling, and response rules', () {
    final profile = ApiProfile.parse(_rest);
    expect(profile.action!.method, 'POST');
    expect(profile.action!.body, '{"identify":true}');
    expect(
      profile.response.readHttp(200, utf8.encode('{"led":false}')),
      isFalse,
    );
    expect(
      () => profile.response.readHttp(200, utf8.encode('{"other":true}')),
      throwsFormatException,
    );
    expect(
      () => profile.response.readHttp(201, utf8.encode('{"led":true}')),
      throwsFormatException,
    );
    for (final path in [
      'https://10.0.0.1',
      '//10.0.0.1/status',
      '/../status',
      '/status?secret=123',
      '/%2F',
    ]) {
      expect(
        () => ApiProfile.parse(_rest.replaceFirst('/status', path)),
        throwsFormatException,
      );
    }
    expect(
      () => ApiProfile.parse(
        _rest.replaceFirst('"pollSeconds":10', '"pollSeconds":1'),
      ),
      throwsFormatException,
    );
    expect(
      () => ApiProfile.parse(
        _rest.replaceFirst(
          '"response":',
          '"headers":{"X-Forwarded-Host":"10.0.0.1"},"response":',
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => ApiProfile.parse(
        _socket.replaceFirst('"equals":true', '"status":200'),
      ),
      throwsFormatException,
    );
  });

  test('checks credentials only over TLS and redacts displayed secrets', () {
    const credential = ApiCredential(ApiAuth.basic, 'operator', 'my-secret');
    expect(() => credential.headers(secure: false), throwsFormatException);
    expect(
      credential.headers(secure: true)['Authorization'],
      'Basic ${base64Encode(utf8.encode('operator:my-secret'))}',
    );
    final preview = previewReading({
      'nested': {'apiKey': 'unknown'},
      'echo': 'my-secret',
    }, credential);
    expect(preview, contains('[redacted]'));
    expect(preview, isNot(contains('my-secret')));
    expect(preview, isNot(contains('unknown')));
  });

  test('validates status identity, revision, boot and capability values', () {
    final descriptor = DeviceDescriptor.decode(
      utf8.encode(jsonEncode(descriptorFixture())),
    );
    final data = {
      'deviceId': testDeviceId,
      'revision': 1,
      'bootId': '11111111111111111111111111111111',
      'seq': 1,
      'values': {'led': false},
    };
    expect(DeviceStatus.parse(data, descriptor).values!['led'], isFalse);
    expect(
      () => DeviceStatus.parse({...data, 'revision': 2}, descriptor),
      throwsA(isA<ConnectionFailure>()),
    );
    expect(
      () => DeviceStatus.parse({
        ...data,
        'values': {'led': 'false'},
      }, descriptor),
      throwsFormatException,
    );
    expect(
      DeviceStatus.parse(
        {
          'deviceId': testDeviceId,
          'revision': 1,
          'bootId': data['bootId'],
          'kind': 'heartbeat',
        },
        descriptor,
        allowHeartbeat: true,
      ).values,
      isNull,
    );
  });

  test(
    'rejects live transport when Android is using a different default link',
    () async {
      final platform = TestDiscoveryPlatform()
        ..scope = WifiScope(testWifi.address, 24, 100, isDefault: false);
      await expectLater(
        LanTransport(platform).open(testEndpoint),
        throwsA(
          isA<ConnectionFailure>().having(
            (error) => error.problem,
            'problem',
            ConnectionProblem.network,
          ),
        ),
      );
      await expectLater(
        LanTransport(platform).probeCleartext(
          platform.scope,
          testEndpoint,
          DiscoveryCancellation(),
          root: false,
          quick: true,
        ),
        throwsA(
          isA<ConnectionFailure>().having(
            (error) => error.problem,
            'problem',
            ConnectionProblem.network,
          ),
        ),
      );
    },
  );

  test(
    'profile read test uses GET and excludes the configured write',
    () async {
      final transport = _TestTransport();
      expect(
        await testApiProfile(
          transport,
          testEndpoint,
          _profile(_rest),
          DiscoveryCancellation(),
        ),
        'false',
      );
      expect(transport.link.requests, [('GET', '/status')]);
    },
  );

  testWidgets(
    'WebSocket waits for a valid status and correlates command acknowledgements',
    (tester) async {
      final transport = _TestTransport();
      final session = DeviceSession();
      session.startLegacy(transport, _device().endpoint, _profile(_socket));
      await tester.pump();
      expect(session.phase, SessionPhase.checking);
      transport.link.socket.events.add('{"unrelated":true}');
      await tester.pump();
      expect(session.phase, SessionPhase.checking);
      expect(session.canTestCommand, isFalse);

      transport.link.socket.events.add('{"led":false}');
      await tester.pump();
      expect(session.phase, SessionPhase.connected);
      final command = session.sendTestCommand(session.controlContext);
      await tester.pump();
      final sent = jsonDecode(transport.link.socket.sent.single) as Map;
      transport.link.socket.events.add('{"requestId":"wrong","ok":true}');
      await tester.pump();
      expect(session.commandBusy, isTrue);
      transport.link.socket.events.add(
        jsonEncode({'requestId': sent['requestId'], 'ok': true}),
      );
      await tester.pump();
      await command;
      expect(
        session.commandResult,
        contains('correlated acknowledgement matched'),
      );
      expect(transport.link.socket.sent, hasLength(1));
      session.dispose();
      await tester.pump();
      expect(transport.link.socket.closed, isTrue);
    },
  );

  testWidgets('an unconfirmed REST command is never retried', (tester) async {
    final transport = _TestTransport();
    transport.link.failCommand = true;
    final session = DeviceSession();
    session.startLegacy(transport, _device().endpoint, _profile(_rest));
    await tester.pump();
    expect(session.phase, SessionPhase.connected);
    await session.sendTestCommand(session.controlContext);
    await tester.pump(const Duration(seconds: 25));
    expect(session.commandResult, contains('unconfirmed'));
    expect(
      transport.link.requests.where((request) => request.$1 == 'POST'),
      hasLength(1),
    );
    session.dispose();
    await tester.pump();
  });

  testWidgets('universal health fails closed on a mismatched descriptor', (
    tester,
  ) async {
    final transport = _TestTransport();
    transport.link.descriptor = descriptorFixture(
      id: 'ffffffffffffffffffffffffffffffff',
    );
    final session = DeviceSession();
    session.startUniversal(
      LanUniversalConnector(transport, _device(universal: true)),
    );
    await tester.pump();
    expect(session.phase, SessionPhase.error);
    expect(transport.link.requests, [('GET', '/.well-known/esp-iot')]);
    session.dispose();
    await tester.pump();
  });

  testWidgets('retries a failed health read and connects after a valid reply', (
    tester,
  ) async {
    final transport = _TestTransport();
    transport.link.failedReads = 1;
    final session = DeviceSession();
    session.startLegacy(transport, _device().endpoint, _profile(_rest));
    await tester.pump();
    expect(session.phase, SessionPhase.reconnecting);
    expect(session.lastContact, isNull);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(session.phase, SessionPhase.connected);
    expect(transport.link.requests, [('GET', '/status'), ('GET', '/status')]);
    session.dispose();
    await tester.pump();
  });

  testWidgets('a changed Wi-Fi link ends an active WebSocket session', (
    tester,
  ) async {
    final transport = _TestTransport();
    final session = DeviceSession();
    session.startLegacy(transport, _device().endpoint, _profile(_socket));
    await tester.pump();
    transport.link.socket.events.add('{"led":false}');
    await tester.pump();
    transport.link.changed = true;
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(session.phase, SessionPhase.error);
    expect(transport.link.socket.closed, isTrue);
    session.dispose();
    await tester.pump();
  });

  testWidgets(
    'device screen saves a profile and confirms a single real test action',
    (tester) async {
      final transport = _TestTransport();
      final storage = _TestProfiles();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deviceTransportProvider.overrideWithValue(transport),
            deviceHistoryStoreProvider.overrideWithValue(TestHistoryStore()),
            apiProfileStoreProvider.overrideWithValue(storage),
          ],
          child: MaterialApp(home: DeviceConnectionScreen(device: _device())),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set API profile'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, _rest);
      final save = find.text('Save API profile');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(storage.saved, isNotNull);
      expect(find.text('Connected'), findsOneWidget);
      final review = find.text('Review test command');
      await tester.ensureVisible(review);
      await tester.tap(review);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        transport.link.requests.where((request) => request.$1 == 'POST'),
        isEmpty,
      );
      await tester.tap(review);
      await tester.pumpAndSettle();
      transport.link.failedReads = 1;
      await tester.pump(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Connected'), findsOneWidget);
      await tester.tap(find.text('Send once'));
      await tester.pumpAndSettle();
      expect(
        find.text('The connection changed. Review the command and try again.'),
        findsOneWidget,
      );
      expect(
        transport.link.requests.where((request) => request.$1 == 'POST'),
        isEmpty,
      );
      await tester.tap(review);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send once'));
      await tester.pumpAndSettle();
      expect(
        find.text('The configured acknowledgement matched.'),
        findsOneWidget,
      );
      expect(
        transport.link.requests.where((request) => request.$1 == 'POST'),
        hasLength(1),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}

class _TestTransport implements DeviceTransport {
  final link = _TestLink();
  int opens = 0;

  @override
  Future<DeviceLink> open(LocalEndpoint endpoint) async {
    opens++;
    return link;
  }
}

class _TestLink implements DeviceLink {
  final socket = _TestSocket();
  final requests = <(String, String)>[];
  Map<String, Object?> descriptor = descriptorFixture();
  Map<String, Object?> universalStatus = _status(1, {'led': false});
  final commands = <Map<String, Object?>>[];
  bool badAcknowledgement = false;
  bool failCommand = false;
  bool changed = false;
  int failedReads = 0;

  @override
  Future<void> checkNetwork() async {
    if (changed) throw const ConnectionFailure(ConnectionProblem.changed);
  }

  @override
  Future<LanResponse> request(
    String method,
    String path,
    ConnectionCancellation cancel, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    await checkNetwork();
    cancel.check();
    requests.add((method, path));
    if ((path == '/status' || path == '/api/v1/status') && failedReads > 0) {
      failedReads--;
      throw const ConnectionFailure(ConnectionProblem.offline);
    }
    if (method == 'POST' && failCommand) {
      throw const ConnectionFailure(ConnectionProblem.timeout);
    }
    if (path == '/api/v1/commands') {
      final command = jsonDecode(body!) as Map<String, Object?>;
      commands.add(command);
      return _json({
        'commandId': badAcknowledgement ? testDeviceId : command['commandId'],
        'bootId': command['bootId'],
        'deviceId': descriptor['deviceId'],
        'revision': command['revision'],
        'outcome': 'applied',
      });
    }
    return _json(switch (path) {
      '/.well-known/esp-iot' => descriptor,
      '/api/v1/status' => universalStatus,
      '/identify' => {'ok': true},
      _ => {'led': false},
    });
  }

  @override
  Future<DeviceSocket> websocket(
    String path,
    ConnectionCancellation cancel, {
    Map<String, String> headers = const {},
  }) async => socket;
}

class _TypedConnection implements UniversalConnector, UniversalConnection {
  final initial = Completer<DeviceStatus>();
  final events = StreamController<DeviceStatus>();
  final commands = <DeviceCommand>[];
  bool closed = false;

  @override
  final descriptor = DeviceDescriptor.decode(
    utf8.encode(jsonEncode(_dashboardDescriptor())),
  );

  DeviceStatus snapshot(int sequence, bool led) =>
      DeviceStatus.parse(_status(sequence, {'led': led}), descriptor);

  @override
  bool get hasLiveEvents => true;

  @override
  Future<UniversalConnection> connect(ConnectionCancellation cancel) async {
    cancel.check();
    return this;
  }

  @override
  Future<DeviceStatus> readStatus() => initial.future;

  @override
  Future<Stream<DeviceStatus>> openEvents() async => events.stream;

  @override
  Future<void> checkRoute() async {}

  @override
  Future<DeviceAcknowledgement> sendCommand(DeviceCommand command) async {
    commands.add(command);
    return command.readAcknowledgement({
      'commandId': command.id,
      'deviceId': descriptor.id,
      'bootId': command.snapshot.bootId,
      'revision': descriptor.revision,
      'outcome': 'applied',
    });
  }

  @override
  void close() {
    if (closed) return;
    closed = true;
    unawaited(events.close());
  }
}

class _TestLayouts implements DashboardLayoutStore {
  List<TilePreference> saved = const [];

  @override
  Future<List<TilePreference>> load(DeviceRegistration device) async => saved;

  @override
  Future<void> save(
    DeviceRegistration device,
    List<TilePreference> tiles,
  ) async {
    saved = tiles;
  }

  @override
  Future<void> delete(DeviceRegistration device) async => saved = const [];
}

class _TestSocket implements DeviceSocket {
  final events = StreamController<Object?>.broadcast();
  final sent = <String>[];
  bool closed = false;

  @override
  Stream<Object?> get messages => events.stream;

  @override
  void send(String text) => sent.add(text);

  @override
  void close() {
    if (closed) return;
    closed = true;
    unawaited(events.close());
  }
}

class _TestProfiles implements ApiProfileStore {
  SavedApiProfile? saved;

  @override
  Future<SavedApiProfile?> load(DeviceRegistration device) async => saved;

  @override
  Future<void> save(
    DeviceRegistration device,
    SavedApiProfile configuration,
  ) async {
    saved = configuration;
  }

  @override
  Future<void> delete(DeviceRegistration device) async => saved = null;
}

// The test reaches loopback only. Production registrations require private LAN addresses.
class _LoopbackEndpoint implements LocalEndpoint {
  const _LoopbackEndpoint(this.host, this.port);
  @override
  final String host;
  @override
  final int port;
  @override
  String? get certificateSha256 => null;
  @override
  bool get secure => false;
  @override
  String get scheme => 'http';
  @override
  String get origin => '$scheme://$host:$port';
}

class _LoopbackScope implements WifiScope {
  const _LoopbackScope(this._host);
  final String _host;
  @override
  String get address => '127.0.0.1';
  @override
  int get prefix => 8;
  @override
  int get networkId => 1;
  @override
  bool get isDefault => true;
  @override
  bool contains(String host) => host == _host;
  @override
  Iterable<String> nearbyHosts() => const [];
  @override
  bool sameLink(WifiScope other) => identical(this, other);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RealHttpOverrides extends HttpOverrides {}
