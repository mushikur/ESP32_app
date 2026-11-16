import 'dart:convert';

import 'strict_json.dart';

bool validDeviceId(Object? value) =>
    value is String && value.length == 32 && _hexId.hasMatch(value);

final _hexId = RegExp(r'^[a-f0-9]{32}$');
final _id = RegExp(r'^[a-z][a-z0-9_-]{0,31}$');
final _extensionType = RegExp(r'^x-[a-z0-9]+-[a-z0-9][a-z0-9_-]*$');
final _unsafeText = RegExp(r'[\x00-\x1f\x7f-\x9f\u2028-\u202e\u2066-\u2069]');

bool validLabel(Object? value, int max, {bool allowEmpty = false}) =>
    value is String &&
    (allowEmpty || value.trim().isNotEmpty) &&
    value.runes.length <= max &&
    !_unsafeText.hasMatch(value);

bool _validId(Object? value) =>
    value is String && !_unsafeText.hasMatch(value) && _id.hasMatch(value);

class DeviceDescriptor {
  DeviceDescriptor._(this._fields, Iterable<DeviceCapability> controls)
    : capabilities = Map.unmodifiable({
        for (final item in controls) item.id: item,
      });

  static const maxBytes = 32 * 1024;
  final Map<String, Object?> _fields;

  String get id => _fields['deviceId']! as String;
  String get name => _fields['name']! as String;
  String get type => _fields['type']! as String;
  int get revision => _fields['revision']! as int;
  bool get hasEvents => _fields['events']! as bool;
  bool get requiresPairing => _fields['auth'] == 'pairing-token';
  final Map<String, DeviceCapability> capabilities;
  int get capabilityCount => capabilities.length;

  bool acceptsStatusValue(String id, Object? value) {
    final capability = capabilities[id];
    if (capability == null || capability.type == 'action') return false;
    if (value == null) return true;
    return switch (capability.type) {
      'switch' => value is bool,
      'range' =>
        value is num && value >= capability.min! && value <= capability.max!,
      'sensor' => value is num,
      'motion' => value == 'stopped' || capability.directions.contains(value),
      _ =>
        value is bool ||
            value is num ||
            validLabel(value, 128, allowEmpty: true),
    };
  }

  static DeviceDescriptor decode(List<int> bytes) {
    if (bytes.length > maxBytes) {
      throw const FormatException('The device description exceeds 32 KiB.');
    }
    final data = decodeStrictJson(utf8.decode(bytes));
    if (data is! Map<String, Object?> ||
        data['protocol'] != 'esp-iot' ||
        data['version'] is! int ||
        data['version'] != 1) {
      throw const FormatException('This device does not advertise ESP IoT v1.');
    }
    final revision = data['revision'];
    final capabilities = data['capabilities'];
    if (!_hasFields(data, const {
          'protocol',
          'version',
          'deviceId',
          'revision',
          'name',
          'type',
          'auth',
          'events',
          'capabilities',
        }) ||
        !validDeviceId(data['deviceId']) ||
        !validLabel(data['name'], 64) ||
        !_validId(data['type']) ||
        revision is! int ||
        revision < 1 ||
        revision > 2147483647 ||
        !const {'none', 'pairing-token'}.contains(data['auth']) ||
        data['events'] is! bool ||
        capabilities is! List ||
        capabilities.length > 48) {
      throw const FormatException('The device description is invalid.');
    }
    final ids = <Object?>{};
    final controls = <DeviceCapability>[];
    for (final item in capabilities) {
      if (item is! Map<String, Object?> ||
          !_validId(item['id']) ||
          !ids.add(item['id']) ||
          !validLabel(item['name'], 64) ||
          !_validCapability(item)) {
        throw const FormatException(
          'The device advertises an invalid or duplicate capability.',
        );
      }
      controls.add(DeviceCapability._(item));
    }
    return DeviceDescriptor._(data, controls);
  }
}

class DeviceCapability {
  DeviceCapability._(Map<String, Object?> fields)
    : id = fields['id']! as String,
      name = fields['name']! as String,
      type = fields['type']! as String,
      confirm = fields['confirm'] == true,
      min = fields['min'] as num?,
      max = fields['max'] as num?,
      step = fields['step'] as num?,
      unit = fields['unit'] as String? ?? '',
      directions = List.unmodifiable(
        (fields['directions'] as List?)?.cast<String>() ?? const <String>[],
      );

  final String id, name, type, unit;
  final bool confirm;
  final num? min, max, step;
  final List<String> directions;
}

bool validRangeValue(Object? value, num min, num max, num step) {
  if (value is! num || !value.isFinite || value < min || value > max) {
    return false;
  }
  final index = (value.toDouble() - min.toDouble()) / step;
  return index.isFinite && (index - index.round()).abs() < 1e-7;
}

const _baseFields = {'id', 'name', 'type'};

bool _hasFields(Map<String, Object?> fields, Set<String> expected) =>
    fields.length == expected.length && fields.keys.every(expected.contains);

bool _validCapability(Map<String, Object?> item) {
  final type = item['type'];
  switch (type) {
    case 'switch':
    case 'action':
      return _hasFields(item, const {..._baseFields, 'confirm'}) &&
          item['confirm'] is bool;
    case 'range':
      final min = item['min'];
      final max = item['max'];
      final step = item['step'];
      if (!_hasFields(item, const {
            ..._baseFields,
            'min',
            'max',
            'step',
            'unit',
            'confirm',
          }) ||
          min is! num ||
          max is! num ||
          step is! num ||
          min >= max ||
          step <= 0 ||
          item['confirm'] is! bool ||
          !validLabel(item['unit'], 16, allowEmpty: true)) {
        return false;
      }
      final steps = (max.toDouble() - min.toDouble()) / step;
      return steps.isFinite &&
          steps >= 1 &&
          steps <= 10000 &&
          (steps - steps.round()).abs() < 1e-7;
    case 'sensor':
      return _hasFields(item, const {..._baseFields, 'unit'}) &&
          validLabel(item['unit'], 16, allowEmpty: true);
    case 'motion':
      final duration = item['maxDurationMs'];
      final directions = item['directions'];
      return _hasFields(item, const {
            ..._baseFields,
            'directions',
            'maxDurationMs',
          }) &&
          duration is int &&
          duration >= 100 &&
          duration <= 2000 &&
          directions is List &&
          directions.isNotEmpty &&
          directions.length <= 4 &&
          directions.toSet().length == directions.length &&
          directions.every(
            const {'forward', 'reverse', 'left', 'right'}.contains,
          );
    default:
      final extension = item['extension'];
      return type is String &&
          type.length <= 48 &&
          !_unsafeText.hasMatch(type) &&
          _extensionType.hasMatch(type) &&
          (_hasFields(item, _baseFields) ||
              (_hasFields(item, const {..._baseFields, 'extension'}) &&
                  extension is Map &&
                  extension.length <= 16));
  }
}
