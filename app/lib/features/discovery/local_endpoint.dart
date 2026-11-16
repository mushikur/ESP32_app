import 'dart:convert';

import '../../core/protocol/device_descriptor.dart';
import '../../core/protocol/strict_json.dart';

final _ipv4Shape = RegExp(r'^(0|[1-9]\d{0,2})(\.(0|[1-9]\d{0,2})){3}$');
final _fingerprintShape = RegExp(r'^[a-f0-9]{64}$');
bool validCertificateFingerprint(Object? value) =>
    value is String && value.length == 64 && _fingerprintShape.hasMatch(value);

int? ipv4Number(String input) {
  if (input.trim() != input || !_ipv4Shape.hasMatch(input)) return null;
  var result = 0;
  for (final part in input.split('.')) {
    final octet = int.tryParse(part);
    if (octet == null || octet > 255) return null;
    result = (result << 8) | octet;
  }
  return result;
}

bool isPrivateIpv4(int number) =>
    number >> 24 == 10 || number >> 20 == 0xac1 || number >> 16 == 0xc0a8;

String ipv4Address(int number) =>
    [24, 16, 8, 0].map((shift) => (number >> shift) & 255).join('.');

class LocalEndpoint {
  factory LocalEndpoint(
    String host,
    int port, {
    required bool secure,
    String? certificateSha256,
  }) {
    final address = ipv4Number(host);
    if (address == null || !isPrivateIpv4(address)) {
      throw const FormatException(
        'Enter a private IPv4 address, such as 192.168.1.100.',
      );
    }
    if (port < 1 || port > 65535) {
      throw const FormatException('Enter a port from 1 to 65535.');
    }
    if (certificateSha256 != null &&
        (!secure || !validCertificateFingerprint(certificateSha256))) {
      throw const FormatException(
        'Use a 64-digit SHA-256 fingerprint with HTTPS.',
      );
    }
    return LocalEndpoint._(host, port, secure, certificateSha256);
  }

  const LocalEndpoint._(
    this.host,
    this.port,
    this.secure,
    this.certificateSha256,
  );
  final String host;
  final int port;
  final bool secure;
  final String? certificateSha256;

  String get scheme => secure ? 'https' : 'http';
  String get origin => '$scheme://$host:$port';

  @override
  bool operator ==(Object other) =>
      other is LocalEndpoint &&
      host == other.host &&
      port == other.port &&
      secure == other.secure;

  @override
  int get hashCode => Object.hash(host, port, secure);
}

class WifiScope {
  factory WifiScope(
    String address,
    int prefix,
    int networkId, {
    bool isDefault = true,
  }) {
    final number = ipv4Number(address);
    if (number == null || !isPrivateIpv4(number) || prefix < 8 || prefix > 30) {
      throw const FormatException(
        'This Wi-Fi network has no supported private IPv4 subnet.',
      );
    }
    final mask = (0xffffffff << (32 - prefix)) & 0xffffffff;
    final first = number & mask;
    final last = first | (0xffffffff ^ mask);
    if (!isPrivateIpv4(first) ||
        !isPrivateIpv4(last) ||
        number == first ||
        number == last) {
      throw const FormatException(
        'This Wi-Fi network has no supported private IPv4 subnet.',
      );
    }
    return WifiScope._(
      address,
      prefix,
      networkId,
      isDefault,
      number,
      first,
      last,
    );
  }

  const WifiScope._(
    this.address,
    this.prefix,
    this.networkId,
    this.isDefault,
    this._number,
    this._first,
    this._last,
  );
  final String address;
  final int prefix;
  final int networkId;
  final bool isDefault;
  final int _number;
  final int _first;
  final int _last;

  bool contains(String host) {
    final number = ipv4Number(host);
    return number != null &&
        number != _number &&
        number > _first &&
        number < _last;
  }

  Iterable<String> nearbyHosts() sync* {
    // Cover common small subnets in full and a bounded window around this phone on larger ones.
    final start = (_number - 16).clamp(
      _first + 1,
      (_last - 33).clamp(_first + 1, _last - 1),
    );
    for (var host = start; host < _last && host <= start + 32; host++) {
      if (host != _number) yield ipv4Address(host);
    }
  }

  bool sameLink(WifiScope other) =>
      address == other.address &&
      prefix == other.prefix &&
      networkId == other.networkId;
}

class PairingHint {
  factory PairingHint(LocalEndpoint endpoint, String deviceId) {
    if (!validDeviceId(deviceId)) {
      throw const FormatException('The QR code has an invalid device ID.');
    }
    return PairingHint._(endpoint, deviceId);
  }

  const PairingHint._(this.endpoint, this.deviceId);
  final LocalEndpoint endpoint;
  final String deviceId;

  factory PairingHint.decode(String payload) {
    if (payload.length > 512) {
      throw const FormatException(
        'This QR code is too large for an ESP IoT pairing hint.',
      );
    }
    final value = decodeStrictJson(payload);
    if (value is! Map<String, Object?> ||
        value.length != (value.containsKey('certificateSha256') ? 8 : 7) ||
        value['protocol'] != 'esp-iot' ||
        value['version'] is! int ||
        value['version'] != 1 ||
        value['kind'] != 'pairing-hint' ||
        value['host'] is! String ||
        value['port'] is! int ||
        !const {'http', 'https'}.contains(value['scheme']) ||
        !validDeviceId(value['deviceId']) ||
        (value.containsKey('certificateSha256') &&
            (!validCertificateFingerprint(value['certificateSha256']) ||
                value['scheme'] != 'https'))) {
      throw const FormatException('Scan a valid ESP IoT v1 pairing QR code.');
    }
    return PairingHint(
      LocalEndpoint(
        value['host']! as String,
        value['port']! as int,
        secure: value['scheme'] == 'https',
        certificateSha256: value['certificateSha256'] as String?,
      ),
      value['deviceId']! as String,
    );
  }

  String encode() => jsonEncode({
    'protocol': 'esp-iot',
    'version': 1,
    'kind': 'pairing-hint',
    'host': endpoint.host,
    'port': endpoint.port,
    'scheme': endpoint.scheme,
    'deviceId': deviceId,
    'certificateSha256': ?endpoint.certificateSha256,
  });
}
