import 'dart:convert';
import 'dart:math';

import '../../core/protocol/device_descriptor.dart';
import '../../core/protocol/strict_json.dart';
import '../discovery/discovery_service.dart';
import '../discovery/local_endpoint.dart';

enum DeviceIcon { automatic, board, light, outlet, fan, sensor, robot }

class DeviceRegistration {
  const DeviceRegistration._({
    required this.registrationId,
    required this.endpoint,
    required this.advertisedName,
    required this.checkedAt,
    required this.requiresPairing,
    this.deviceId,
    this.type,
    this.hostname,
    this.customName,
    this.room,
    this.category,
    this.icon = DeviceIcon.automatic,
  });

  final String registrationId;
  final LocalEndpoint endpoint;
  final String advertisedName;
  final DateTime checkedAt;
  final bool requiresPairing;
  final String? deviceId, type, hostname, customName, room, category;
  final DeviceIcon icon;

  String get name => customName ?? advertisedName;
  bool get usesOriginalStorageKeys => registrationId.startsWith('v1:');

  PairingHint? get pairingHint {
    final id = deviceId;
    return id == null ? null : PairingHint(endpoint, id);
  }

  factory DeviceRegistration.fromVerified(VerifiedDevice device) {
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return DeviceRegistration._(
      registrationId: 'p5:$id',
      endpoint: device.endpoint,
      advertisedName: device.name,
      checkedAt: device.checkedAt,
      requiresPairing: device.descriptor?.requiresPairing ?? false,
      deviceId: device.descriptor?.id,
      type: device.descriptor?.type,
      hostname: device.hostname,
    );
  }

  DeviceRegistration withDetails({
    required String? name,
    required String? room,
    required String? category,
    required DeviceIcon icon,
  }) {
    final details = [name, room, category]
        .map((value) => value?.trim())
        .map((value) => value == '' ? null : value)
        .toList();
    if (details[0] != null && !validLabel(details[0], 64) ||
        details.skip(1).nonNulls.any((value) => !validLabel(value, 32))) {
      throw const FormatException(
        'Use a name up to 64 characters and a room or category up to 32 characters.',
      );
    }
    return DeviceRegistration._(
      registrationId: registrationId,
      endpoint: endpoint,
      advertisedName: advertisedName,
      checkedAt: checkedAt,
      requiresPairing: requiresPairing,
      deviceId: deviceId,
      type: type,
      hostname: hostname,
      customName: details[0],
      room: details[1],
      category: details[2],
      icon: icon,
    );
  }

  DeviceRegistration reverified(VerifiedDevice verified) {
    final descriptor = verified.descriptor;
    if (deviceId != descriptor?.id ||
        (deviceId == null && endpoint != verified.endpoint) ||
        (endpoint.secure && !verified.endpoint.secure) ||
        (endpoint.certificateSha256 != null &&
            verified.endpoint.certificateSha256 !=
                endpoint.certificateSha256) ||
        (requiresPairing && descriptor?.requiresPairing != true) ||
        (descriptor?.requiresPairing == true && !verified.endpoint.secure)) {
      throw const FormatException(
        'The new address does not match this registration and its security settings.',
      );
    }
    return DeviceRegistration._(
      registrationId: registrationId,
      endpoint: verified.endpoint,
      advertisedName: verified.name,
      checkedAt: verified.checkedAt,
      requiresPairing: descriptor?.requiresPairing ?? false,
      deviceId: deviceId,
      type: descriptor?.type,
      hostname:
          verified.hostname ??
          (endpoint == verified.endpoint ? hostname : null),
      customName: customName,
      room: room,
      category: category,
      icon: icon,
    );
  }

  factory DeviceRegistration.fromJson(Object? data) {
    if (data is! Map<String, Object?>) {
      throw const FormatException('Invalid registration.');
    }
    final host = data['host'];
    final port = data['port'];
    final secure = data['secure'];
    final fingerprint = data['certificateSha256'];
    final name = data['name'];
    final checkedAt = data['checkedAt'];
    final requiresPairing = data['requiresPairing'];
    final deviceId = data['deviceId'];
    final type = data['type'];
    final hostname = data['hostname'];
    final customName = data['customName'];
    final room = data['room'];
    final category = data['category'];
    final icon = DeviceIcon.values
        .where((item) => item.name == (data['icon'] ?? 'automatic'))
        .firstOrNull;
    final storedId = data['registrationId'];
    if (host is! String ||
        port is! int ||
        secure is! bool ||
        (fingerprint != null && !validCertificateFingerprint(fingerprint)) ||
        !validLabel(name, 64) ||
        checkedAt is! String ||
        requiresPairing is! bool ||
        (deviceId != null && !validDeviceId(deviceId)) ||
        (type != null && !validLabel(type, 32)) ||
        (hostname != null && !validLabel(hostname, 64)) ||
        (customName != null && !validLabel(customName, 64)) ||
        (room != null && !validLabel(room, 32)) ||
        (category != null && !validLabel(category, 32)) ||
        icon == null ||
        (storedId != null && !validLabel(storedId, 128)) ||
        (requiresPairing && (!secure || deviceId == null))) {
      throw const FormatException('Invalid registration.');
    }
    final endpoint = LocalEndpoint(
      host,
      port,
      secure: secure,
      certificateSha256: fingerprint as String?,
    );
    final verifiedAt = DateTime.parse(checkedAt).toUtc();
    return DeviceRegistration._(
      registrationId:
          storedId as String? ??
          'v1:${verifiedAt.microsecondsSinceEpoch}:${deviceId ?? endpoint.origin}',
      endpoint: endpoint,
      advertisedName: name! as String,
      checkedAt: verifiedAt,
      requiresPairing: requiresPairing,
      deviceId: deviceId as String?,
      type: type as String?,
      hostname: hostname as String?,
      customName: customName as String?,
      room: room as String?,
      category: category as String?,
      icon: icon,
    );
  }

  Map<String, Object?> toJson() => {
    'registrationId': registrationId,
    'host': endpoint.host,
    'port': endpoint.port,
    'secure': endpoint.secure,
    'certificateSha256': ?endpoint.certificateSha256,
    'name': advertisedName,
    'checkedAt': checkedAt.toIso8601String(),
    'requiresPairing': requiresPairing,
    'deviceId': deviceId,
    'type': type,
    'hostname': hostname,
    'customName': customName,
    'room': room,
    'category': category,
    'icon': icon.name,
  };

  bool matches(VerifiedDevice device) =>
      endpoint == device.endpoint && deviceId == device.descriptor?.id;
}

const deviceRegistrationLimit = 128;

List<DeviceRegistration> decodeRegistrations(String data) {
  if (data.length > 256 * 1024) {
    throw const FormatException('The registry is too large.');
  }
  final decoded = decodeStrictJson(data);
  if (decoded is! List || decoded.length > deviceRegistrationLimit) {
    throw const FormatException('The device registry could not be read.');
  }
  final entries = decoded.map(DeviceRegistration.fromJson).toList();
  final ids = entries.map((entry) => entry.deviceId).nonNulls.toList();
  if (entries.map((entry) => entry.endpoint).toSet().length != entries.length ||
      entries.map((entry) => entry.registrationId).toSet().length !=
          entries.length ||
      ids.toSet().length != ids.length) {
    throw const FormatException(
      'The registry contains duplicate addresses or identities.',
    );
  }
  return List.unmodifiable(entries);
}

String encodeRegistrations(Iterable<DeviceRegistration> devices) =>
    jsonEncode(devices.map((entry) => entry.toJson()).toList());
