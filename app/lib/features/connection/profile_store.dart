import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/protocol/strict_json.dart';
import '../devices/device_registration.dart';
import '../discovery/local_endpoint.dart';
import 'api_profile.dart';

class SavedApiProfile {
  const SavedApiProfile(this.profile, this.credential);
  final ApiProfile profile;
  final ApiCredential credential;

  Map<String, String> headers(LocalEndpoint endpoint) => {
    ...profile.headers,
    ...credential.headers(secure: endpoint.secure),
  };
}

abstract interface class ApiProfileStore {
  Future<SavedApiProfile?> load(DeviceRegistration device);
  Future<void> save(DeviceRegistration device, SavedApiProfile configuration);
  Future<void> delete(DeviceRegistration device);
}

class SecureApiProfileStore implements ApiProfileStore {
  const SecureApiProfileStore(this._storage);
  final FlutterSecureStorage _storage;

  String _key(DeviceRegistration device) {
    final scope = device.usesOriginalStorageKeys
        ? device.endpoint.origin
        : device.registrationId;
    return 'esp_iot_profile_v1_${base64Url.encode(utf8.encode(scope))}';
  }

  @override
  Future<SavedApiProfile?> load(DeviceRegistration device) async {
    final value = await _storage.read(key: _key(device));
    if (value == null) return null;
    if (value.length > 28 * 1024) {
      throw const FormatException('Invalid saved API profile.');
    }
    final data = decodeStrictJson(value);
    if (data is! Map<String, Object?> ||
        data['version'] != 1 ||
        data['profile'] is! String) {
      throw const FormatException('Invalid saved API profile.');
    }
    final saved = SavedApiProfile(
      ApiProfile.parse(data['profile']! as String),
      ApiCredential.fromJson(data['credential']),
    );
    saved.headers(device.endpoint);
    return saved;
  }

  @override
  Future<void> save(
    DeviceRegistration device,
    SavedApiProfile configuration,
  ) async {
    configuration.headers(device.endpoint);
    await _storage.write(
      key: _key(device),
      value: jsonEncode({
        'version': 1,
        'profile': configuration.profile.source,
        'credential': configuration.credential.toJson(),
      }),
    );
  }

  @override
  Future<void> delete(DeviceRegistration device) =>
      _storage.delete(key: _key(device));
}

final apiProfileStoreProvider = Provider<ApiProfileStore>(
  (ref) => const SecureApiProfileStore(FlutterSecureStorage()),
);
