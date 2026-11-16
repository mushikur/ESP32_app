import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/protocol/device_descriptor.dart';
import '../../core/protocol/strict_json.dart';
import '../../core/transport/lan_transport.dart';
import '../devices/device_registration.dart';
import '../discovery/local_endpoint.dart';

final _codePattern = RegExp(r'^[0-9]{8}$');
bool validPairingCode(String code) =>
    code.length == 8 && _codePattern.hasMatch(code);

class DeviceCredential {
  DeviceCredential._(
    this._deviceId,
    this._origin,
    this._fingerprint,
    this._token,
  );

  final String _deviceId, _origin, _token;
  final String? _fingerprint;

  Map<String, String> headers(DeviceRegistration device) =>
      device.endpoint.secure &&
          _deviceId == device.deviceId &&
          _origin == device.endpoint.origin &&
          _fingerprint == device.endpoint.certificateSha256
      ? {'Authorization': 'Bearer $_token'}
      : const {};

  String _encode() => jsonEncode({
    'version': 1,
    'deviceId': _deviceId,
    'origin': _origin,
    'certificateSha256': _fingerprint,
    'token': _token,
  });

  static DeviceCredential _decode(String data) {
    if (data.length > 512) {
      throw const FormatException('Invalid saved pairing.');
    }
    final json = decodeStrictJson(data);
    if (json is! Map<String, Object?> ||
        json.length != 5 ||
        json['version'] != 1 ||
        !validDeviceId(json['deviceId']) ||
        !validLabel(json['origin'], 64) ||
        !json.containsKey('certificateSha256') ||
        (json['certificateSha256'] != null &&
            !validCertificateFingerprint(json['certificateSha256'])) ||
        !validCertificateFingerprint(json['token'])) {
      throw const FormatException('Invalid saved pairing.');
    }
    return DeviceCredential._(
      json['deviceId']! as String,
      json['origin']! as String,
      json['certificateSha256'] as String?,
      json['token']! as String,
    );
  }
}

abstract interface class PairingStore {
  Future<DeviceCredential?> load(DeviceRegistration device);
  Future<void> save(DeviceRegistration device, DeviceCredential credential);
  Future<void> delete(DeviceRegistration device);
}

class SecurePairingStore implements PairingStore {
  const SecurePairingStore(this._storage);
  final FlutterSecureStorage _storage;

  String _key(DeviceRegistration device) =>
      'esp_iot_pairing_v1_${base64Url.encode(utf8.encode(device.registrationId))}';

  @override
  Future<DeviceCredential?> load(DeviceRegistration device) async {
    if (!device.endpoint.secure || device.deviceId == null) return null;
    final raw = await _storage.read(key: _key(device));
    if (raw == null) return null;
    final credential = DeviceCredential._decode(raw);
    return credential.headers(device).isEmpty ? null : credential;
  }

  @override
  Future<void> save(
    DeviceRegistration device,
    DeviceCredential credential,
  ) async {
    if (credential.headers(device).isEmpty) {
      throw const FormatException(
        'The token belongs to another device address.',
      );
    }
    await _storage.write(key: _key(device), value: credential._encode());
  }

  @override
  Future<void> delete(DeviceRegistration device) =>
      _storage.delete(key: _key(device));
}

final pairingStoreProvider = Provider<PairingStore>(
  (_) => const SecurePairingStore(FlutterSecureStorage()),
);

Future<DeviceDescriptor> readRegisteredDescriptor(
  DeviceLink link,
  DeviceRegistration device,
  ConnectionCancellation cancel,
) async {
  final reply = await link.request('GET', '/.well-known/esp-iot', cancel);
  if (reply.status != 200 || reply.contentType != 'application/json') {
    throw const FormatException(
      'The device did not return an ESP IoT v1 description.',
    );
  }
  final descriptor = DeviceDescriptor.decode(reply.bytes);
  if (descriptor.id != device.deviceId ||
      (device.requiresPairing && !descriptor.requiresPairing)) {
    throw const ConnectionFailure(ConnectionProblem.identity);
  }
  return descriptor;
}

class SecurePairing {
  const SecurePairing(this._transport);
  final DeviceTransport _transport;

  Future<DeviceLink> _verified(
    DeviceRegistration device,
    ConnectionCancellation cancel,
  ) async {
    if (!device.endpoint.secure || device.deviceId == null) {
      throw const ConnectionFailure(
        ConnectionProblem.authentication,
        'Secure pairing requires a verified HTTPS device.',
      );
    }
    final link = await _transport.open(device.endpoint);
    cancel.check();
    if (!(await readRegisteredDescriptor(
      link,
      device,
      cancel,
    )).requiresPairing) {
      throw const ConnectionFailure(
        ConnectionProblem.authentication,
        'This firmware does not offer token pairing.',
      );
    }
    cancel.check();
    return link;
  }

  Future<DeviceCredential> enroll(
    DeviceRegistration device,
    String code,
    ConnectionCancellation cancel,
  ) async {
    if (!validPairingCode(code)) {
      throw const FormatException(
        'Enter the eight-digit code shown by the device.',
      );
    }
    final link = await _verified(device, cancel);
    final response = await link.request(
      'POST',
      '/api/v1/pair',
      cancel,
      body: jsonEncode({'deviceId': device.deviceId, 'code': code}),
    );
    if (response.status == 429) {
      throw const ConnectionFailure(
        ConnectionProblem.authentication,
        'Pairing is busy or its slots are full. Check the device and try a fresh code.',
      );
    }
    if (response.status != 200 ||
        response.contentType != 'application/json' ||
        response.bytes.length > 512) {
      throw const ConnectionFailure(
        ConnectionProblem.response,
        'The device did not issue a valid pairing token.',
      );
    }
    final data = decodeStrictJson(utf8.decode(response.bytes));
    if (data is! Map<String, Object?> ||
        data.length != 2 ||
        data['deviceId'] != device.deviceId ||
        !validCertificateFingerprint(data['token'])) {
      throw const FormatException(
        'The pairing response did not match this device.',
      );
    }
    cancel.check();
    return DeviceCredential._(
      device.deviceId!,
      device.endpoint.origin,
      device.endpoint.certificateSha256,
      data['token']! as String,
    );
  }

  Future<void> revoke(
    DeviceRegistration device,
    DeviceCredential credential,
    ConnectionCancellation cancel,
  ) async {
    final headers = credential.headers(device);
    if (headers.isEmpty) {
      throw const ConnectionFailure(ConnectionProblem.authentication);
    }
    final link = await _verified(device, cancel);
    final response = await link.request(
      'DELETE',
      '/api/v1/pairing',
      cancel,
      headers: headers,
    );
    if (response.status != 204 || response.bytes.isNotEmpty) {
      throw const ConnectionFailure(
        ConnectionProblem.response,
        'The device did not confirm that pairing was removed.',
      );
    }
  }
}
