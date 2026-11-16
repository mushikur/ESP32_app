import 'dart:convert';
import 'dart:typed_data';

import 'package:esp_iot/features/devices/device_database.dart';
import 'package:esp_iot/features/devices/device_registry.dart';
import 'package:esp_iot/features/discovery/local_discovery_platform.dart';
import 'package:esp_iot/features/discovery/local_endpoint.dart';

const testDeviceId = '0123456789abcdef0123456789abcdef';
final testWifi = WifiScope('192.168.1.20', 24, 100);
final testEndpoint = LocalEndpoint('192.168.1.10', 80, secure: false);

Map<String, Object?> descriptorFixture({
  String id = testDeviceId,
  String auth = 'none',
}) => {
  'protocol': 'esp-iot',
  'version': 1,
  'deviceId': id,
  'revision': 1,
  'name': 'Bench ESP32',
  'type': 'lighting',
  'auth': auth,
  'events': false,
  'capabilities': [
    {'id': 'led', 'type': 'switch', 'name': 'LED', 'confirm': false},
  ],
};

ProbeResponse descriptorResponse({
  String id = testDeviceId,
  String auth = 'none',
}) => ProbeResponse(
  200,
  'application/json',
  utf8.encode(jsonEncode(descriptorFixture(id: id, auth: auth))),
);

Map<String, Object?> udpFixture(String nonce, {String host = '192.168.1.10'}) =>
    {
      'host': host,
      'payload': Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'protocol': 'esp-iot',
            'version': 1,
            'kind': 'offer',
            'nonce': nonce,
            'deviceId': testDeviceId,
            'port': 80,
            'tls': false,
          }),
        ),
      ),
    };

class TestDiscoveryPlatform implements LocalDiscoveryPlatform {
  WifiScope scope = testWifi;
  List<Map<Object?, Object?>> announcements = [];
  List<Map<Object?, Object?>> Function(String nonce) udpReplies = (_) => [];
  ProbeResponse Function(LocalEndpoint endpoint, bool root) reply = (_, _) =>
      descriptorResponse();
  final probes = <({LocalEndpoint endpoint, bool root, bool quick})>[];

  @override
  Future<WifiScope> wifi() async => scope;

  @override
  Future<List<Map<Object?, Object?>>> mdns(
    WifiScope scope,
    DiscoveryCancellation cancel,
  ) async {
    cancel.check();
    return announcements;
  }

  @override
  Future<List<Map<Object?, Object?>>> udp(
    WifiScope scope,
    String nonce,
    DiscoveryCancellation cancel,
  ) async {
    cancel.check();
    return udpReplies(nonce);
  }

  @override
  Future<ProbeResponse> probe(
    WifiScope scope,
    LocalEndpoint endpoint,
    DiscoveryCancellation cancel, {
    bool root = false,
    bool quick = false,
  }) async {
    cancel.check();
    probes.add((endpoint: endpoint, root: root, quick: quick));
    return reply(endpoint, root);
  }
}

class TestRegistrationStore implements RegistrationStore {
  String? data;
  bool failWrites = false;
  int writes = 0;

  @override
  Future<String?> load() async => data;

  @override
  Future<void> save(String data) async {
    if (failWrites) throw Exception('Storage unavailable');
    this.data = data;
    writes++;
  }
}

class TestHistoryStore implements DeviceHistoryStore {
  final activity = <ActivityEntry>[];
  final usage = <String, DeviceUsage>{};

  @override
  Future<DeviceHistory> history() async =>
      DeviceHistory(List.of(activity), Map.of(usage));

  @override
  Future<void> record(
    DeviceRegistration device,
    DateTime time, {
    ActivityKind? kind,
    DateTime? seen,
    bool opened = false,
  }) async {
    final id = device.registrationId;
    final previous = usage[id];
    usage[id] = (
      lastSeen: seen ?? previous?.lastSeen,
      lastOpened: opened ? time : previous?.lastOpened,
    );
    if (kind != null) {
      activity.insert(0, (registrationId: id, kind: kind, time: time));
    }
  }
}
