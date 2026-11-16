import 'dart:convert';
import 'dart:math';

import 'device_descriptor.dart';
import 'device_status.dart';

enum DeviceAcknowledgement { applied, rejected }

String newCommandId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

class DeviceCommand {
  DeviceCommand(
    this.descriptor,
    this.snapshot,
    this.capabilityId,
    this.operation,
    this.value,
  ) : id = newCommandId() {
    final control = descriptor.capabilities[capabilityId];
    final valid = switch ((control?.type, operation)) {
      ('switch', 'set') => value is bool,
      ('range', 'set') => validRangeValue(
        value,
        control!.min!,
        control.max!,
        control.step!,
      ),
      ('action', 'invoke') || ('motion', 'stop') => value == null,
      _ => false,
    };
    if (!valid || snapshot.sequence == null) {
      throw const FormatException(
        'This command is unavailable for the current device.',
      );
    }
  }

  final DeviceDescriptor descriptor;
  final DeviceStatus snapshot;
  final String capabilityId, operation, id;
  final Object? value;

  String get body => jsonEncode(payload);

  Map<String, Object?> get payload => {
    'commandId': id,
    'bootId': snapshot.bootId,
    'revision': descriptor.revision,
    'capabilityId': capabilityId,
    'op': operation,
    if (operation == 'set') 'value': value,
  };

  DeviceAcknowledgement readAcknowledgement(Object? data) {
    if (data is Map<String, Object?> &&
        data['commandId'] == id &&
        data['deviceId'] == descriptor.id &&
        data['bootId'] == snapshot.bootId &&
        data['revision'] is int &&
        data['revision'] == descriptor.revision) {
      if (data['outcome'] == 'applied') return DeviceAcknowledgement.applied;
      if (data['outcome'] == 'rejected' && validLabel(data['code'], 64)) {
        return DeviceAcknowledgement.rejected;
      }
    }
    throw const FormatException(
      'The acknowledgement did not match this command.',
    );
  }
}
