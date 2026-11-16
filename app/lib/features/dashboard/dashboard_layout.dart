import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/protocol/device_descriptor.dart';
import '../../core/protocol/strict_json.dart';
import '../devices/device_registration.dart';

enum TileIcon { automatic, light, power, speed, thermometer, tune, bolt }

enum TileColor { cyan, blue, violet, mint, amber }

class TilePreference {
  const TilePreference(
    this.id, {
    this.name,
    this.icon = TileIcon.automatic,
    this.color = TileColor.cyan,
    this.hidden = false,
  });

  final String id;
  final String? name;
  final TileIcon icon;
  final TileColor color;
  final bool hidden;

  TilePreference withVisibility(bool visible) => TilePreference(
    id,
    name: name,
    icon: icon,
    color: color,
    hidden: !visible,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'icon': icon.name,
    'color': color.name,
    'hidden': hidden,
  };

  static TilePreference fromJson(Object? value) {
    if (value is Map<String, Object?> &&
        value['id'] is String &&
        RegExp(r'^[a-z][a-z0-9_-]{0,31}$').hasMatch(value['id']! as String) &&
        (value['name'] == null || validLabel(value['name'], 64)) &&
        value['hidden'] is bool) {
      final icon = TileIcon.values
          .where((item) => item.name == value['icon'])
          .firstOrNull;
      final color = TileColor.values
          .where((item) => item.name == value['color'])
          .firstOrNull;
      if (icon != null && color != null) {
        return TilePreference(
          value['id']! as String,
          name: value['name'] as String?,
          icon: icon,
          color: color,
          hidden: value['hidden']! as bool,
        );
      }
    }
    throw const FormatException('Invalid dashboard tile settings.');
  }
}

List<TilePreference> reconcileLayout(
  Iterable<TilePreference> saved,
  Iterable<String> available,
) {
  final ids = available.toSet();
  return [
    for (final tile in saved)
      if (ids.remove(tile.id)) tile,
    for (final id in ids) TilePreference(id),
  ];
}

abstract interface class DashboardLayoutStore {
  Future<List<TilePreference>> load(DeviceRegistration device);
  Future<void> save(DeviceRegistration device, List<TilePreference> tiles);
  Future<void> delete(DeviceRegistration device);
}

class LocalDashboardLayoutStore implements DashboardLayoutStore {
  LocalDashboardLayoutStore(this._preferences);
  final SharedPreferencesAsync _preferences;

  String _key(DeviceRegistration device) {
    final identity = device.usesOriginalStorageKeys
        ? (device.deviceId ?? device.endpoint.origin)
        : device.registrationId;
    return 'esp_iot_dashboard_v1_${base64Url.encode(utf8.encode(identity))}';
  }

  @override
  Future<List<TilePreference>> load(DeviceRegistration device) async {
    final raw = await _preferences.getString(_key(device));
    if (raw == null) return const [];
    if (raw.length > 32768) {
      throw const FormatException('Invalid dashboard settings.');
    }
    final data = decodeStrictJson(raw);
    if (data is! List || data.length > 48) {
      throw const FormatException('Invalid dashboard settings.');
    }
    final tiles = data.map(TilePreference.fromJson).toList();
    if (tiles.map((tile) => tile.id).toSet().length != tiles.length) {
      throw const FormatException('Invalid dashboard settings.');
    }
    return List.unmodifiable(tiles);
  }

  @override
  Future<void> save(DeviceRegistration device, List<TilePreference> tiles) =>
      _preferences.setString(
        _key(device),
        jsonEncode(tiles.map((tile) => tile.toJson()).toList()),
      );

  @override
  Future<void> delete(DeviceRegistration device) =>
      _preferences.remove(_key(device));
}

final dashboardLayoutStoreProvider = Provider<DashboardLayoutStore>(
  (_) => LocalDashboardLayoutStore(SharedPreferencesAsync()),
);
