import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/transport/lan_transport.dart';
import '../../core/protocol/device_descriptor.dart';
import '../../core/protocol/strict_json.dart';
import 'local_discovery_platform.dart';
import 'local_endpoint.dart';

export 'local_discovery_platform.dart' show discoveryPlatformProvider;

enum DiscoverySource {
  mdns('mDNS'),
  udp('ESP IoT UDP'),
  subnet('Subnet check'),
  manual('Manual address'),
  qr('QR code');

  const DiscoverySource(this.label);
  final String label;
}

class VerifiedDevice {
  const VerifiedDevice({
    required this.endpoint,
    required this.scope,
    required this.source,
    required this.checkedAt,
    this.descriptor,
    this.hostname,
  });

  final LocalEndpoint endpoint;
  final WifiScope scope;
  final DiscoverySource source;
  final DateTime checkedAt;
  final DeviceDescriptor? descriptor;
  final String? hostname;

  String get name => descriptor?.name ?? 'ESP32 at ${endpoint.host}';
  bool get isLegacy => descriptor == null;
}

class DiscoveryReport {
  const DiscoveryReport(this.scope, this.devices, this.warnings);
  final WifiScope scope;
  final List<VerifiedDevice> devices;
  final List<String> warnings;
}

class _Candidate {
  const _Candidate(this.endpoint, this.source, {this.id, this.hostname});
  final LocalEndpoint endpoint;
  final DiscoverySource source;
  final String? id;
  final String? hostname;
}

final wifiSnapshotProvider = FutureProvider.autoDispose<WifiScope>(
  (ref) => ref.watch(discoveryPlatformProvider).wifi(),
  retry: (_, _) => null,
);
final discoveryServiceProvider = Provider<DiscoveryService>(
  (ref) => DiscoveryService(ref.watch(discoveryPlatformProvider)),
);

class DiscoveryService {
  DiscoveryService(this._platform);
  final LocalDiscoveryPlatform _platform;

  Future<DiscoveryReport> search(
    DiscoveryCancellation cancel, {
    int? subnetPort,
    bool subnetSecure = false,
  }) async {
    final scope = await _activeWifi();
    cancel.check();
    final warnings = <String>[];
    final candidates = <_Candidate>[];
    if (subnetPort == null) {
      final nonce = _nonce();
      final announcements = await Future.wait([
        _readSource(
          () => _platform.mdns(scope, cancel),
          'mDNS could not run.',
          warnings,
        ),
        _readSource(
          () => _platform.udp(scope, nonce, cancel),
          'UDP discovery could not run.',
          warnings,
        ),
      ], eagerError: true);
      cancel.check();
      for (final record in announcements[0]) {
        final offer = _mdnsCandidate(record);
        if (offer != null) candidates.add(offer);
      }
      for (final record in announcements[1]) {
        final offer = _udpCandidate(record, nonce);
        if (offer != null) candidates.add(offer);
      }
    } else {
      for (final host in scope.nearbyHosts().take(32)) {
        candidates.add(
          _Candidate(
            LocalEndpoint(host, subnetPort, secure: subnetSecure),
            DiscoverySource.subnet,
          ),
        );
      }
    }

    final endpoints = <LocalEndpoint, List<_Candidate>>{};
    for (final candidate in candidates) {
      if (scope.contains(candidate.endpoint.host)) {
        endpoints.putIfAbsent(candidate.endpoint, () => []).add(candidate);
      }
    }
    final queue = <_Candidate>[];
    var conflicts = false;
    for (final entries in endpoints.values) {
      final ids = entries.map((entry) => entry.id).nonNulls.toSet();
      if (ids.length > 1) {
        conflicts = true;
        continue;
      }
      final first = entries.first;
      queue.add(
        _Candidate(
          first.endpoint,
          first.source,
          id: ids.firstOrNull,
          hostname: first.hostname,
        ),
      );
    }

    final verified = <VerifiedDevice>[];
    final timer = Stopwatch()..start();
    for (var offset = 0; offset < queue.length; offset += 2) {
      cancel.check();
      // Reserve time for the final in-flight pair within the ten-second probe budget.
      if (timer.elapsedMilliseconds >= 8500) {
        warnings.add(
          'The search reached its time limit. Use a manual address for a specific device.',
        );
        break;
      }
      final batchStart = timer.elapsedMilliseconds;
      final batch = await Future.wait(
        queue
            .skip(offset)
            .take(2)
            .map((item) => _verifyCandidate(scope, item, cancel)),
        eagerError: true,
      );
      verified.addAll(batch.nonNulls);
      if (subnetPort != null && offset + 2 < queue.length) {
        final delay = 500 - (timer.elapsedMilliseconds - batchStart);
        if (delay > 0) {
          await Future<void>.delayed(Duration(milliseconds: delay));
        }
      }
    }
    cancel.check();
    await checkCurrent(scope);
    cancel.check();
    final grouped = <String, List<VerifiedDevice>>{};
    for (final device in verified) {
      grouped.putIfAbsent(device.descriptor!.id, () => []).add(device);
    }
    final devices = <VerifiedDevice>[];
    for (final matches in grouped.values) {
      if (matches.length == 1) {
        devices.add(matches.single);
      } else {
        conflicts = true;
      }
    }
    if (conflicts) {
      warnings.add(
        'Conflicting device identities were withheld. Verify the intended address manually.',
      );
    }
    if (subnetPort == null && candidates.isNotEmpty && verified.isEmpty) {
      warnings.add(
        'Devices advertised on Wi-Fi, but their descriptions could not be verified.',
      );
    }
    return DiscoveryReport(
      scope,
      List.unmodifiable(devices),
      List.unmodifiable(warnings),
    );
  }

  Future<VerifiedDevice> verify(
    LocalEndpoint endpoint,
    DiscoveryCancellation cancel, {
    String? expectedId,
  }) async {
    final scope = await _activeWifi();
    cancel.check();
    final candidate = _Candidate(
      endpoint,
      expectedId == null ? DiscoverySource.manual : DiscoverySource.qr,
      id: expectedId,
    );
    final device = await _probe(
      scope,
      candidate,
      cancel,
      allowLegacy: expectedId == null,
    );
    await checkCurrent(scope);
    cancel.check();
    return device;
  }

  Future<void> checkCurrent(WifiScope scope) async {
    try {
      if (!scope.sameLink(await _activeWifi())) {
        throw const DiscoveryFailure('networkChanged');
      }
    } on DiscoveryFailure catch (error) {
      if (const {
        'noWifi',
        'vpn',
        'noPrivateIpv4',
        'wifiNotDefault',
      }.contains(error.code)) {
        throw const DiscoveryFailure('networkChanged');
      }
      rethrow;
    }
  }

  Future<WifiScope> _activeWifi() async {
    final scope = await _platform.wifi();
    if (!scope.isDefault) throw const DiscoveryFailure('wifiNotDefault');
    return scope;
  }

  Future<VerifiedDevice?> _verifyCandidate(
    WifiScope scope,
    _Candidate candidate,
    DiscoveryCancellation cancel,
  ) async {
    try {
      return await _probe(scope, candidate, cancel, quick: true);
    } on FormatException {
      return null;
    } on DiscoveryFailure catch (error) {
      if (_searchBlocking(error)) rethrow;
      return null;
    }
  }

  Future<VerifiedDevice> _probe(
    WifiScope scope,
    _Candidate candidate,
    DiscoveryCancellation cancel, {
    bool allowLegacy = false,
    bool quick = false,
  }) async {
    final endpoint = candidate.endpoint;
    if (!scope.contains(endpoint.host)) {
      throw const DiscoveryFailure('outsideWifi');
    }
    final response = await _requestProbe(scope, endpoint, cancel, quick: quick);
    cancel.check();
    _checkStatus(response.status);
    DeviceDescriptor? descriptor;
    if (response.status == 200 && response.contentType == 'application/json') {
      descriptor = DeviceDescriptor.decode(response.body);
      if (candidate.id != null && candidate.id != descriptor.id) {
        throw const DiscoveryFailure('identity');
      }
      if (descriptor.requiresPairing && !endpoint.secure) {
        throw const DiscoveryFailure('insecurePairing');
      }
    } else if (allowLegacy &&
        (const {404, 405, 501}.contains(response.status) ||
            (response.status == 200 &&
                (response.contentType == 'text/html' ||
                    response.contentType.isEmpty)))) {
      final panel = await _requestProbe(scope, endpoint, cancel, root: true);
      cancel.check();
      _checkStatus(panel.status);
      if (panel.status < 200 || panel.status >= 300) {
        throw const DiscoveryFailure('unsupported');
      }
    } else {
      throw const DiscoveryFailure('unsupported');
    }
    return VerifiedDevice(
      endpoint: endpoint,
      scope: scope,
      source: candidate.source,
      checkedAt: DateTime.now().toUtc(),
      descriptor: descriptor,
      hostname: candidate.hostname,
    );
  }

  Future<ProbeResponse> _requestProbe(
    WifiScope scope,
    LocalEndpoint endpoint,
    DiscoveryCancellation cancel, {
    bool root = false,
    bool quick = false,
  }) async {
    if (endpoint.certificateSha256 == null) {
      return _platform.probe(scope, endpoint, cancel, root: root, quick: quick);
    }
    try {
      final link = await LanTransport(_platform).open(endpoint);
      final reply = await link.request(
        'GET',
        root ? '/' : '/.well-known/esp-iot',
        cancel,
      );
      return ProbeResponse(reply.status, reply.contentType, reply.bytes);
    } on ConnectionFailure catch (error) {
      throw DiscoveryFailure(switch (error.problem) {
        ConnectionProblem.certificate => 'certificate',
        ConnectionProblem.timeout => 'timeout',
        ConnectionProblem.authentication => 'authentication',
        ConnectionProblem.redirect => 'redirect',
        ConnectionProblem.changed => 'networkChanged',
        ConnectionProblem.network => 'noWifi',
        ConnectionProblem.tooLarge => 'tooLarge',
        ConnectionProblem.cancelled => 'cancelled',
        _ => 'invalidResponse',
      });
    }
  }

  void _checkStatus(int status) {
    if (status == 401 || status == 403) {
      throw const DiscoveryFailure('authentication');
    }
    if (status >= 300 && status < 400) throw const DiscoveryFailure('redirect');
  }

  Future<List<Map<Object?, Object?>>> _readSource(
    Future<List<Map<Object?, Object?>>> Function() read,
    String warning,
    List<String> warnings,
  ) async {
    try {
      return await read();
    } on DiscoveryFailure catch (error) {
      if (_searchBlocking(error)) rethrow;
      warnings.add(warning);
      return [];
    }
  }

  bool _searchBlocking(DiscoveryFailure error) => const {
    'cancelled',
    'networkChanged',
    'permission',
    'noWifi',
    'noPrivateIpv4',
    'vpn',
  }.contains(error.code);

  _Candidate? _mdnsCandidate(Map<Object?, Object?> record) {
    final host = record['host'];
    final port = record['port'];
    final secure = record['secure'];
    final id = record['deviceId'];
    final hostname = record['hostname'] ?? record['service'];
    if (host is! String ||
        port is! int ||
        secure is! bool ||
        (id != null && !validDeviceId(id))) {
      return null;
    }
    try {
      return _Candidate(
        LocalEndpoint(host, port, secure: secure),
        DiscoverySource.mdns,
        id: id as String?,
        hostname: validLabel(hostname, 64) ? hostname as String : null,
      );
    } on FormatException {
      return null;
    }
  }

  _Candidate? _udpCandidate(Map<Object?, Object?> record, String nonce) {
    final host = record['host'];
    final payload = record['payload'];
    if (host is! String ||
        payload is! Uint8List ||
        payload.isEmpty ||
        payload.length > 512) {
      return null;
    }
    try {
      final message = decodeStrictJson(utf8.decode(payload));
      if (message is! Map<String, Object?> ||
          message.length != 7 ||
          message['protocol'] != 'esp-iot' ||
          message['version'] is! int ||
          message['version'] != 1 ||
          message['kind'] != 'offer' ||
          message['nonce'] != nonce ||
          !validDeviceId(message['deviceId']) ||
          message['port'] is! int ||
          message['tls'] is! bool) {
        return null;
      }
      return _Candidate(
        LocalEndpoint(
          host,
          message['port']! as int,
          secure: message['tls']! as bool,
        ),
        DiscoverySource.udp,
        id: message['deviceId']! as String,
      );
    } on FormatException {
      return null;
    }
  }

  String _nonce() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}
