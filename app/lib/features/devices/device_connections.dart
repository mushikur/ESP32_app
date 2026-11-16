import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/status_visuals.dart';
import '../connection/device_session.dart';
import '../discovery/local_endpoint.dart';
import 'device_database.dart';
import 'device_registration.dart';

enum DevicePresence {
  connected('Connected'),
  offline('Offline'),
  authorization('Authorization required'),
  problem('Needs attention'),
  unknown('Status unknown');

  const DevicePresence(this.label);
  final String label;

  StatusTone get tone => switch (this) {
    DevicePresence.connected => StatusTone.live,
    DevicePresence.offline => StatusTone.idle,
    DevicePresence.authorization => StatusTone.fault,
    DevicePresence.problem => StatusTone.fault,
    DevicePresence.unknown => StatusTone.idle,
  };
}

DevicePresence presenceForPhase(SessionPhase phase) => switch (phase) {
  SessionPhase.connected => DevicePresence.connected,
  SessionPhase.offline => DevicePresence.offline,
  SessionPhase.authorization => DevicePresence.authorization,
  SessionPhase.error => DevicePresence.problem,
  _ => DevicePresence.unknown,
};

ActivityKind? activityForPhase(SessionPhase phase) => switch (phase) {
  SessionPhase.connected => ActivityKind.connected,
  SessionPhase.offline => ActivityKind.offline,
  SessionPhase.authorization => ActivityKind.authorization,
  SessionPhase.error => ActivityKind.failed,
  _ => null,
};

typedef ConnectionObservation = ({
  LocalEndpoint endpoint,
  DevicePresence presence,
  DateTime until,
});

DevicePresence presenceOf(
  Map<String, ConnectionObservation> observations,
  DeviceRegistration device,
) {
  final result = observations[device.registrationId];
  return result != null &&
          result.endpoint == device.endpoint &&
          result.until.isAfter(DateTime.now())
      ? result.presence
      : DevicePresence.unknown;
}

final deviceConnectionsProvider =
    NotifierProvider<DeviceConnections, Map<String, ConnectionObservation>>(
      DeviceConnections.new,
    );

class DeviceConnections extends Notifier<Map<String, ConnectionObservation>> {
  Timer? _expiry;
  bool _hidden = false;
  static const freshness = Duration(seconds: 30);

  @override
  Map<String, ConnectionObservation> build() {
    final listener = AppLifecycleListener(
      onHide: () {
        _hidden = true;
        _expiry?.cancel();
        state = const {};
      },
      onResume: () => _hidden = false,
    );
    ref.onDispose(() {
      _expiry?.cancel();
      listener.dispose();
    });
    return const {};
  }

  void observe(DeviceRegistration device, DevicePresence presence) {
    if (!ref.mounted || _hidden) return;
    final next = Map.of(state);
    if (presence == DevicePresence.unknown) {
      if (next[device.registrationId]?.endpoint != device.endpoint) return;
      next.remove(device.registrationId);
    } else {
      next[device.registrationId] = (
        endpoint: device.endpoint,
        presence: presence,
        until: DateTime.now().add(freshness),
      );
    }
    state = Map.unmodifiable(next);
    _scheduleExpiry();
  }

  void _scheduleExpiry() {
    _expiry?.cancel();
    if (state.isEmpty) return;
    final next = state.values
        .map((result) => result.until)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    _expiry = Timer(next.difference(DateTime.now()), () {
      final now = DateTime.now();
      state = Map.unmodifiable(
        Map.of(state)..removeWhere((_, result) => !result.until.isAfter(now)),
      );
      _scheduleExpiry();
    });
  }

  Future<void> record(
    DeviceRegistration device, {
    ActivityKind? kind,
    DateTime? seen,
    bool opened = false,
  }) async {
    if (!ref.mounted) return;
    try {
      await ref
          .read(deviceHistoryStoreProvider)
          .record(
            device,
            DateTime.now(),
            kind: kind,
            seen: seen,
            opened: opened,
          );
      if (ref.mounted) ref.invalidate(deviceHistoryProvider);
    } on Exception {
      // History availability is independent of an active device connection.
    }
  }
}
