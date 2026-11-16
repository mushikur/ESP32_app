import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../connection/profile_store.dart';
import '../connection/secure_pairing.dart';
import '../dashboard/dashboard_layout.dart';
import '../discovery/discovery_service.dart';
import 'device_database.dart';
import 'device_registration.dart';

export 'device_database.dart' show RegistrationStore;
export 'device_registration.dart';

final registrationStoreProvider = Provider<RegistrationStore>(
  (ref) => ref.watch(deviceDatabaseProvider),
);
final deviceRegistryProvider =
    AsyncNotifierProvider<DeviceRegistry, List<DeviceRegistration>>(
      DeviceRegistry.new,
      retry: (_, _) => null,
    );

class DeviceRegistry extends AsyncNotifier<List<DeviceRegistration>> {
  Future<void> _writes = Future.value();
  Future<bool> _cleanup = Future.value(true);

  @override
  Future<List<DeviceRegistration>> build() async {
    final store = ref.watch(registrationStoreProvider);
    final data = await store.load();
    final entries = data == null
        ? const <DeviceRegistration>[]
        : decodeRegistrations(data);
    if (ref.mounted) unawaited(_cleanRemovals(store));
    return entries;
  }

  Future<void> register(VerifiedDevice device) => _update((entries) {
    if (entries.any((entry) => entry.matches(device))) return;
    final id = device.descriptor?.id;
    if (entries.any(
      (entry) =>
          entry.endpoint == device.endpoint ||
          (id != null && entry.deviceId == id),
    )) {
      throw const FormatException(
        'This address or device ID is already registered. Open its settings to verify the address.',
      );
    }
    if (entries.length >= deviceRegistrationLimit) {
      throw const FormatException('The device registry is full.');
    }
    entries.add(DeviceRegistration.fromVerified(device));
  });

  Future<void> edit(
    String id, {
    required String? name,
    required String? room,
    required String? category,
    required DeviceIcon icon,
  }) => _update((entries) {
    final index = _index(entries, id);
    entries[index] = entries[index].withDetails(
      name: name,
      room: room,
      category: category,
      icon: icon,
    );
  });

  Future<void> verifyAddress(
    DeviceRegistration original,
    VerifiedDevice verified,
  ) => _update((entries) {
    final index = _index(entries, original.registrationId);
    final current = entries[index];
    if (current.endpoint != original.endpoint) {
      throw const FormatException(
        'The saved address changed. Open settings again.',
      );
    }
    if (entries.indexed.any(
      (entry) => entry.$1 != index && entry.$2.endpoint == verified.endpoint,
    )) {
      throw const FormatException(
        'Another registration already uses this address.',
      );
    }
    entries[index] = current.reverified(verified);
  });

  Future<bool> forget(String id) async {
    final store = ref.read(registrationStoreProvider);
    await _update((entries) => entries.removeAt(_index(entries, id)));
    return ref.mounted ? _cleanRemovals(store) : false;
  }

  int _index(List<DeviceRegistration> entries, String id) {
    final index = entries.indexWhere((entry) => entry.registrationId == id);
    if (index < 0) {
      throw const FormatException('This device is no longer registered.');
    }
    return index;
  }

  Future<void> _update(void Function(List<DeviceRegistration>) change) {
    final write = _writes.then((_) async {
      final store = ref.read(registrationStoreProvider);
      final entries = await future;
      final next = entries.toList();
      change(next);
      if (next.length == entries.length &&
          next.indexed.every(
            (entry) => identical(entry.$2, entries[entry.$1]),
          )) {
        return;
      }
      await store.save(encodeRegistrations(next));
      if (ref.mounted) {
        state = AsyncData(List.unmodifiable(next));
        if (store is DeviceDatabase) ref.invalidate(deviceHistoryProvider);
      }
    });
    _writes = write.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return write;
  }

  Future<bool> _cleanRemovals(RegistrationStore store) {
    if (store is! DeviceDatabase) return Future.value(true);
    final profiles = ref.read(apiProfileStoreProvider);
    final pairings = ref.read(pairingStoreProvider);
    final layouts = ref.read(dashboardLayoutStoreProvider);
    return _cleanup = _cleanup.then((_) async {
      try {
        var complete = true;
        for (final device in await store.pendingRemovals()) {
          try {
            if (device.deviceId == null) {
              await profiles.delete(device);
            } else if (device.endpoint.secure) {
              await pairings.delete(device);
            }
            await layouts.delete(device);
            await store.completeRemoval(device.registrationId);
          } on Exception {
            complete = false;
          }
        }
        return complete;
      } on Exception {
        return false;
      }
    });
  }
}
