import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/transport/lan_transport.dart';
import 'local_endpoint.dart';

final discoveryPlatformProvider = Provider<LocalDiscoveryPlatform>(
  (ref) => AndroidLocalDiscovery(),
);

class DiscoveryFailure implements Exception {
  const DiscoveryFailure(this.code);
  final String code;

  String get message => switch (code) {
    'noWifi' => 'Connect this phone to Wi-Fi, then try again.',
    'wifiNotDefault' => 'Make this Wi-Fi Android’s active connection to discover and control devices.',
    'vpn' => 'The active VPN is masking the local Wi-Fi link. Try again on your trusted Wi-Fi without the VPN.',
    'noPrivateIpv4' =>
      'This Wi-Fi does not have a supported private IPv4 subnet.',
    'outsideWifi' =>
      'Use a different device address on the same Wi-Fi subnet as this phone.',
    'networkChanged' => 'Wi-Fi changed during discovery. Start a new search on the current network.',
    'permission' => 'Android blocked local network access. Review the app permissions and Wi-Fi settings.',
    'certificate' =>
      'HTTPS verification failed. Check the device certificate and address.',
    'timeout' => 'The device did not respond in time. Check its power, address, and Wi-Fi connection.',
    'tooLarge' => 'The device description exceeds 32 KiB.',
    'invalidResponse' =>
      'The device returned an invalid or unsupported response.',
    'authentication' =>
      'This endpoint requires authentication before it can be verified.',
    'redirect' => 'The device redirected this request. Enter the final local address directly.',
    'identity' =>
      'The device ID does not match the discovery message or QR code.',
    'insecurePairing' => 'This device requires token pairing over verified HTTPS. Use its HTTPS address.',
    'unsupported' => 'No supported device description or reachable web panel was found at this address.',
    'busy' => 'The local network tools are busy. Try again in a moment.',
    'platform' => 'Local network discovery is available in the Android app.',
    _ => 'Could not reach this device. Check that it is on the same Wi-Fi and that the port is correct.',
  };
}

class DiscoveryCancellation extends ConnectionCancellation {
  @override
  void check() {
    if (isCancelled) throw const DiscoveryFailure('cancelled');
  }
}

class ProbeResponse {
  const ProbeResponse(this.status, this.contentType, this.body);

  final int status;
  final String contentType;
  final List<int> body;
}

abstract interface class LocalDiscoveryPlatform {
  Future<WifiScope> wifi();
  Future<List<Map<Object?, Object?>>> mdns(
    WifiScope scope,
    DiscoveryCancellation cancel,
  );
  Future<List<Map<Object?, Object?>>> udp(
    WifiScope scope,
    String nonce,
    DiscoveryCancellation cancel,
  );
  Future<ProbeResponse> probe(
    WifiScope scope,
    LocalEndpoint endpoint,
    DiscoveryCancellation cancel, {
    bool root = false,
    bool quick = false,
  });
}

class AndroidLocalDiscovery implements LocalDiscoveryPlatform {
  static const _channel = MethodChannel('esp_iot/local_discovery');
  static int _nextOperation = 0;

  @override
  Future<WifiScope> wifi() async {
    final value = await _invoke<Map<Object?, Object?>>('wifi');
    return WifiScope(
      value['address']! as String,
      value['prefix']! as int,
      value['networkId']! as int,
      isDefault: value['isDefault'] == true,
    );
  }

  @override
  Future<List<Map<Object?, Object?>>> mdns(
    WifiScope scope,
    DiscoveryCancellation cancel,
  ) async => (await _operation<List<Object?>>(
    'mdns',
    scope,
    cancel,
  )).cast<Map<Object?, Object?>>();

  @override
  Future<List<Map<Object?, Object?>>> udp(
    WifiScope scope,
    String nonce,
    DiscoveryCancellation cancel,
  ) async => (await _operation<List<Object?>>('udp', scope, cancel, {
    'nonce': nonce,
  })).cast<Map<Object?, Object?>>();

  @override
  Future<ProbeResponse> probe(
    WifiScope scope,
    LocalEndpoint endpoint,
    DiscoveryCancellation cancel, {
    bool root = false,
    bool quick = false,
  }) async {
    if (!scope.isDefault) throw const DiscoveryFailure('wifiNotDefault');
    if (!endpoint.secure) {
      try {
        final reply = await LanTransport(this)
            .probeCleartext(scope, endpoint, cancel, root: root, quick: quick);
        return ProbeResponse(reply.status, reply.contentType, reply.bytes);
      } on ConnectionFailure catch (error) {
        throw DiscoveryFailure(switch (error.problem) {
          ConnectionProblem.changed ||
          ConnectionProblem.network => 'networkChanged',
          ConnectionProblem.authentication => 'authentication',
          ConnectionProblem.redirect => 'redirect',
          ConnectionProblem.timeout => 'timeout',
          ConnectionProblem.response => 'invalidResponse',
          ConnectionProblem.tooLarge => 'tooLarge',
          ConnectionProblem.cancelled => 'cancelled',
          _ => 'unreachable',
        });
      }
    }
    final value = await _operation<Map<Object?, Object?>>(
      'probe',
      scope,
      cancel,
      {
        'host': endpoint.host,
        'port': endpoint.port,
        'root': root,
        'quick': quick,
      },
    );
    return ProbeResponse(
      value['status']! as int,
      value['contentType']! as String,
      value['body']! as Uint8List,
    );
  }

  Future<T> _operation<T>(
    String method,
    WifiScope scope,
    DiscoveryCancellation cancel, [
    Map<String, Object?> arguments = const {},
  ]) async {
    final id = _nextOperation = (_nextOperation % 2147483647) + 1;
    final detach = cancel.onCancel(() => unawaited(_cancel(id)));
    try {
      final timeout = switch (method) {
        'probe' when arguments['quick'] == true => const Duration(
          milliseconds: 1500,
        ),
        'probe' => const Duration(seconds: 4),
        _ => const Duration(seconds: 5),
      };
      final result = await _invoke<T>(method, {
        ...arguments,
        'operation': id,
        'address': scope.address,
        'prefix': scope.prefix,
        'networkId': scope.networkId,
      }, timeout);
      cancel.check();
      return result;
    } on DiscoveryFailure catch (error) {
      if (error.code == 'timeout') unawaited(_cancel(id));
      rethrow;
    } finally {
      detach();
    }
  }

  Future<T> _invoke<T>(
    String method, [
    Object? arguments,
    Duration timeout = const Duration(seconds: 3),
  ]) async {
    try {
      final value = await _channel
          .invokeMethod<T>(method, arguments)
          .timeout(timeout);
      if (value == null) throw const DiscoveryFailure('invalidResponse');
      return value;
    } on PlatformException catch (error) {
      throw DiscoveryFailure(error.code);
    } on MissingPluginException {
      throw const DiscoveryFailure('platform');
    } on TimeoutException {
      throw const DiscoveryFailure('timeout');
    }
  }

  Future<void> _cancel(int id) async {
    try {
      await _channel
          .invokeMethod<void>('cancel', {'operation': id})
          .timeout(const Duration(seconds: 2));
    } on PlatformException {
      // The operation may already have completed or the activity may have closed.
    } on MissingPluginException {
      // The platform channel has already been detached.
    } on TimeoutException {
      // The operation's own deadline still applies when Android resumes.
    }
  }
}
