import '../transport/connection_failure.dart';
import 'device_descriptor.dart';

class DeviceStatus {
  const DeviceStatus._(this.bootId, this.sequence, this.values);
  final String bootId;
  final int? sequence;
  final Map<String, Object?>? values;

  static DeviceStatus parse(
    Object? value,
    DeviceDescriptor descriptor, {
    bool allowHeartbeat = false,
  }) {
    if (value is! Map<String, Object?> ||
        !validDeviceId(value['deviceId']) ||
        !validDeviceId(value['bootId']) ||
        value['revision'] is! int) {
      throw const FormatException('Invalid ESP IoT status envelope.');
    }
    if (value['deviceId'] != descriptor.id ||
        value['revision'] != descriptor.revision) {
      throw const ConnectionFailure(ConnectionProblem.identity);
    }
    final bootId = value['bootId']! as String;
    final kind = value['kind'];
    if (allowHeartbeat && kind == 'heartbeat' && value.length == 4) {
      return DeviceStatus._(bootId, null, null);
    }
    final sequence = value['seq'];
    final values = value['values'];
    if ((kind != null && kind != 'snapshot') ||
        sequence is! int ||
        sequence < 0 ||
        sequence > 9007199254740991 ||
        values is! Map<String, Object?> ||
        values.length > 48 ||
        !values.entries.every(
          (entry) => descriptor.acceptsStatusValue(entry.key, entry.value),
        )) {
      throw const FormatException('Invalid ESP IoT status snapshot.');
    }
    return DeviceStatus._(bootId, sequence, Map.unmodifiable(values));
  }
}
