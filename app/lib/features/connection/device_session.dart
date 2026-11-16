import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/protocol/device_command.dart';
import '../../core/ui/status_visuals.dart';
import '../../core/protocol/device_descriptor.dart';
import '../../core/protocol/device_status.dart';
import '../../core/transport/lan_transport.dart';
import '../../core/transport/universal_transport.dart';
import '../devices/device_registration.dart';
import '../discovery/local_endpoint.dart';
import 'api_profile.dart';
import 'lan_universal_connector.dart';
import 'profile_store.dart';
import 'secure_pairing.dart';

enum SessionPhase {
  idle('Ready to connect'),
  checking('Checking connection'),
  connected('Connected'),
  authorization('Authorization required'),
  reconnecting('Reconnecting'),
  offline('Offline'),
  error('Connection error'),
  paused('Monitoring paused');

  const SessionPhase(this.label);
  final String label;

  StatusTone get tone => switch (this) {
    SessionPhase.connected => StatusTone.live,
    SessionPhase.checking || SessionPhase.reconnecting => StatusTone.waiting,
    SessionPhase.idle ||
    SessionPhase.paused ||
    SessionPhase.offline => StatusTone.idle,
    SessionPhase.authorization || SessionPhase.error => StatusTone.fault,
  };
}

class DeviceSession extends ChangeNotifier {
  DeviceSession({this.onCommand});
  final void Function(CommandOutcome)? onCommand;
  ConnectionCancellation? _run;
  ({DeviceLink link, LocalEndpoint endpoint})? _legacy;
  UniversalConnection? _universal;
  DeviceSocket? _socket;
  SavedApiProfile? _configuration;
  _PendingAck? _ack;
  bool _disposed = false;
  DeviceDescriptor? _descriptor;
  DeviceStatus? _snapshot;
  (String, int, String)? _historyScope;
  int? _lastHistorySequence;
  Map<String, Object?> _legacyValues = const {};
  final _history = <String, List<({DateTime time, num value})>>{};
  Object _controlContext = Object();
  bool _commandBusy = false;
  bool _stopBusy = false;
  String? stopControlId;
  String? stopResult;

  DeviceDescriptor? get descriptor => _descriptor;
  Map<String, Object?> get controlValues => _snapshot?.values ?? _legacyValues;
  Object get controlContext => _controlContext;
  bool get commandBusy => _commandBusy || _stopBusy;
  bool get canControl => phase == SessionPhase.connected && !commandBusy;
  bool get canStop => phase == SessionPhase.connected && !_stopBusy;
  List<({DateTime time, num value})> history(String id) =>
      List.unmodifiable(_history[id] ?? const []);

  SessionPhase phase = SessionPhase.idle;
  String? detail;
  String? sample;
  DateTime? lastContact;
  DateTime? lastSample;
  String? commandResult;

  bool get canTestCommand =>
      canControl && _configuration?.profile.action != null;

  void startLegacy(
    DeviceTransport transport,
    LocalEndpoint endpoint,
    SavedApiProfile? configuration,
  ) {
    DeviceLink? bound;
    _start(
      configuration,
      configuration == null
          ? null
          : (run, verified) async {
              final link = bound ??= await transport.open(endpoint);
              run.check();
              _legacy = (link: link, endpoint: endpoint);
              await _monitorLegacy(
                link,
                endpoint,
                configuration,
                run,
                verified,
              );
            },
    );
  }

  void startUniversal(UniversalConnector connector) {
    _start(
      null,
      (run, verified) => _monitorUniversal(connector, run, verified),
    );
  }

  void _start(
    SavedApiProfile? configuration,
    Future<void> Function(ConnectionCancellation, void Function())? attempt,
  ) {
    _stop();
    if (!identical(configuration, _configuration)) _history.clear();
    _configuration = configuration;
    _descriptor = null;
    _snapshot = null;
    _legacyValues = const {};
    sample = null;
    lastSample = null;
    commandResult = null;
    stopResult = null;
    stopControlId = null;
    _commandBusy = _stopBusy = false;
    if (attempt == null) {
      _setPhase(
        SessionPhase.idle,
        'Set an API profile for this legacy web project.',
      );
      return;
    }
    final run = _run = ConnectionCancellation();
    _setPhase(SessionPhase.checking, 'Waiting for a valid device response.');
    unawaited(_monitor(run, attempt));
  }

  void pause() {
    if (_run == null) return;
    _stop();
    if (_commandBusy) {
      commandResult = 'Command unconfirmed. Monitoring was paused.';
      onCommand?.call(CommandOutcome.unconfirmed);
    }
    if (_stopBusy) {
      stopResult = 'Stop unconfirmed. Check the device directly.';
      onCommand?.call(CommandOutcome.unconfirmed);
    }
    _commandBusy = _stopBusy = false;
    _setPhase(
      SessionPhase.paused,
      'Monitoring resumes when this screen is active.',
    );
  }

  void _stop() {
    _controlContext = Object();
    _run?.cancel();
    _run = null;
    _legacy = null;
    _universal?.close();
    _universal = null;
    _socket?.close();
    _socket = null;
    final pending = _ack;
    _ack = null;
    if (pending != null && !pending.result.isCompleted) {
      pending.result.complete(false);
    }
  }

  @override
  void dispose() {
    if (_commandBusy) onCommand?.call(CommandOutcome.unconfirmed);
    if (_stopBusy) onCommand?.call(CommandOutcome.unconfirmed);
    _disposed = true;
    _stop();
    super.dispose();
  }

  bool _active(ConnectionCancellation run) =>
      !_disposed && identical(_run, run) && !run.isCancelled;

  Future<void> _monitor(
    ConnectionCancellation run,
    Future<void> Function(ConnectionCancellation, void Function()) attempt,
  ) async {
    var failures = 0;
    while (_active(run)) {
      try {
        await attempt(run, () => failures = 0);
      } on ConnectionFailure catch (failure) {
        if (!_active(run)) return;
        final problem = failure.problem;
        if (problem == ConnectionProblem.authentication) {
          _setPhase(SessionPhase.authorization, failure.message);
          return;
        }
        if (problem != ConnectionProblem.timeout &&
            problem != ConnectionProblem.offline) {
          _setPhase(SessionPhase.error, failure.message);
          return;
        }
        final wait = Duration(
          milliseconds:
              min(30000, 1500 * (1 << min(failures++, 5))) +
              Random().nextInt(400),
        );
        _setPhase(
          failures > 2 ? SessionPhase.offline : SessionPhase.reconnecting,
          '${failure.message} Retrying in ${(wait.inMilliseconds / 1000).ceil()} s.',
        );
        await _wait(wait, run);
      } on FormatException catch (error) {
        if (_active(run)) _setPhase(SessionPhase.error, error.message);
        return;
      } on Exception {
        if (_active(run)) {
          _setPhase(SessionPhase.error, ConnectionProblem.response.message);
        }
        return;
      }
    }
  }

  Future<void> _monitorLegacy(
    DeviceLink link,
    LocalEndpoint endpoint,
    SavedApiProfile configuration,
    ConnectionCancellation run,
    void Function() verified,
  ) async {
    final headers = configuration.headers(endpoint);
    final profile = configuration.profile;
    if (profile.transport == ApiTransport.rest) {
      while (_active(run)) {
        final reading = await _readLegacy(link, configuration, headers, run);
        if (!_active(run)) return;
        verified();
        _receivedLegacy(
          reading,
          'REST · matched status response',
          configuration,
        );
        await _wait(profile.poll, run);
      }
      return;
    }
    final socket = await link.websocket(
      profile.statusPath,
      run,
      headers: headers,
    );
    try {
      if (!_active(run)) return;
      _socket = socket;
      await _watchStream(
        socket.messages,
        run,
        checkRoute: link.checkNetwork,
        idle: Duration(seconds: max(12, profile.poll.inSeconds * 2)),
        frame: (message) {
          final data = decodeLanEvent(message);
          if (_receiveAcknowledgement(data, profile)) return false;
          final reading = profile.response.readJson(data);
          verified();
          _receivedLegacy(
            reading,
            'WebSocket · matched status event',
            configuration,
          );
          return true;
        },
      );
    } finally {
      socket.close();
      if (identical(_socket, socket)) {
        _socket = null;
        final pending = _ack;
        if (pending != null && !pending.result.isCompleted) {
          pending.result.complete(false);
        }
      }
    }
  }

  Future<void> _monitorUniversal(
    UniversalConnector connector,
    ConnectionCancellation run,
    void Function() verified,
  ) async {
    final connection = await connector.connect(run);
    try {
      if (!_active(run)) return;
      final descriptor = connection.descriptor;
      var current = await connection.readStatus();
      if (!_active(run)) return;
      _universal = connection;
      if (!connection.hasLiveEvents) verified();
      const statusInfo = 'ESP IoT v1 · verified status';
      _receivedUniversal(descriptor, current, statusInfo);
      if (!_active(run)) return;
      if (connection.hasLiveEvents) {
        final events = await connection.openEvents();
        if (!_active(run)) return;
        await _watchStream(
          events,
          run,
          checkRoute: connection.checkRoute,
          idle: const Duration(seconds: 24),
          frame: (next) {
            if (next.bootId != current.bootId) {
              throw const ConnectionFailure(
                ConnectionProblem.offline,
                'The device restarted. Checking its identity and status again.',
              );
            }
            if (next.sequence == null) {
              verified();
              lastContact = DateTime.now();
              _setPhase(
                SessionPhase.connected,
                'ESP IoT v1 · validated heartbeat',
              );
              return true;
            }
            if (next.sequence! <= current.sequence!) return false;
            current = next;
            verified();
            _receivedUniversal(
              descriptor,
              next,
              'ESP IoT v1 · verified live event',
            );
            return true;
          },
        );
      } else {
        while (_active(run)) {
          await _wait(const Duration(seconds: 10), run);
          if (!_active(run)) return;
          final next = await connection.readStatus();
          if (!_active(run)) return;
          if (next.bootId != current.bootId ||
              next.sequence! < current.sequence!) {
            throw const ConnectionFailure(
              ConnectionProblem.offline,
              'The device restarted or sent an older snapshot. Checking it again.',
            );
          }
          verified();
          if (next.sequence == current.sequence) {
            lastContact = DateTime.now();
            _setPhase(SessionPhase.connected, statusInfo);
          } else {
            current = next;
            _receivedUniversal(descriptor, next, statusInfo);
          }
        }
      }
    } finally {
      if (identical(_universal, connection)) _universal = null;
      connection.close();
    }
  }

  Future<void> _watchStream<T>(
    Stream<T> messages,
    ConnectionCancellation run, {
    required Future<void> Function() checkRoute,
    required Duration idle,
    required bool Function(T data) frame,
  }) async {
    final done = Completer<ConnectionFailure>();
    void finish(ConnectionFailure error) {
      if (!done.isCompleted) done.complete(error);
    }

    Timer? watchdog;
    void reset(Duration timeout) {
      watchdog?.cancel();
      watchdog = Timer(
        timeout,
        () => finish(const ConnectionFailure(ConnectionProblem.timeout)),
      );
    }

    reset(const Duration(seconds: 8));
    final detach = run.onCancel(
      () => finish(const ConnectionFailure(ConnectionProblem.cancelled)),
    );
    var checking = false;
    final network = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (checking || done.isCompleted) return;
      checking = true;
      try {
        await checkRoute();
      } on ConnectionFailure catch (failure) {
        finish(failure);
      } on Exception {
        finish(const ConnectionFailure(ConnectionProblem.network));
      } finally {
        checking = false;
      }
    });
    final subscription = messages.listen(
      (message) {
        if (!_active(run) || done.isCompleted) return;
        try {
          if (frame(message)) reset(idle);
        } on FormatException {
          // Invalid frames cannot refresh the connection or sensor freshness.
        } on ConnectionFailure catch (failure) {
          finish(failure);
        }
      },
      onError: (Object error) => finish(
        error is ConnectionFailure
            ? error
            : const ConnectionFailure(ConnectionProblem.offline),
      ),
      onDone: () => finish(const ConnectionFailure(ConnectionProblem.offline)),
    );
    try {
      throw await done.future;
    } finally {
      watchdog?.cancel();
      detach();
      network.cancel();
      unawaited(
        subscription.cancel().then<void>((_) {}, onError: (Object _) {}),
      );
    }
  }

  bool _receiveAcknowledgement(Object? data, ApiProfile profile) {
    if (data is! Map || !profile.acknowledgementFields.any(data.containsKey)) {
      return false;
    }
    final pending = _ack;
    if (pending != null &&
        !pending.result.isCompleted &&
        data[pending.action.correlationField] == pending.id) {
      try {
        pending.action.response.readJson(data);
        pending.result.complete(true);
      } on FormatException {
        pending.result.complete(false);
      }
    }
    return true;
  }

  Future<void> sendTestCommand(Object context) async {
    final legacy = _legacy;
    final configuration = _configuration;
    final action = configuration?.profile.action;
    if (!canTestCommand ||
        legacy == null ||
        configuration == null ||
        action == null) {
      return;
    }
    await _execute(
      context,
      (run) => _sendProfile(
        legacy.link,
        legacy.endpoint,
        run,
        configuration,
        action,
      ),
    );
  }

  Future<void> sendControl(
    Object context,
    String id,
    String operation,
    Object? value,
  ) async {
    if (!identical(context, controlContext)) return;
    final universal = _universal;
    final descriptor = _descriptor;
    final snapshot = _snapshot;
    if (universal != null && descriptor != null && snapshot != null) {
      await _execute(context, (_) async {
        final command = DeviceCommand(
          descriptor,
          snapshot,
          id,
          operation,
          value,
        );
        final acknowledgement = await universal.sendCommand(command);
        return acknowledgement == DeviceAcknowledgement.applied
            ? (
                outcome: CommandOutcome.applied,
                message: 'Device acknowledged the command.',
              )
            : (
                outcome: CommandOutcome.rejected,
                message: 'The device rejected the command.',
              );
      }, stopId: operation == 'stop' ? id : null);
      return;
    }
    final legacy = _legacy;
    final configuration = _configuration;
    final control = configuration?.profile.controls[id];
    if (legacy == null || configuration == null || control == null) return;
    final slot = operation == 'set' && control.type == 'switch'
        ? (value == true ? 'on' : 'off')
        : operation;
    final action = control.commands[slot];
    if (action == null || (control.type == 'switch' && value is! bool)) return;
    final field = control.valueField;
    if (field != null &&
        !validRangeValue(value, control.min!, control.max!, control.step!)) {
      return;
    }
    await _execute(
      context,
      (run) => _sendProfile(
        legacy.link,
        legacy.endpoint,
        run,
        configuration,
        action,
        valueField: field,
        value: value,
      ),
    );
  }

  Future<void> _execute(
    Object context,
    Future<_CommandReceipt> Function(ConnectionCancellation) send, {
    String? stopId,
  }) async {
    final stop = stopId != null;
    final run = _run;
    if (!(stop ? canStop : canControl) ||
        run == null ||
        !identical(context, controlContext)) {
      return;
    }
    if (stop) {
      _stopBusy = true;
      stopControlId = stopId;
      stopResult = 'Waiting for stop acknowledgement…';
    } else {
      _commandBusy = true;
      commandResult = 'Waiting for acknowledgement…';
    }
    notifyListeners();
    final unclear = (
      outcome: CommandOutcome.unconfirmed,
      message: stop ? 'Stop unconfirmed. Check the device directly.' : 'Command unconfirmed. Check the device before sending another command.',
    );
    var result = unclear;
    try {
      run.check();
      result = await send(run);
    } on Exception {
      // The device may have received the write. Leave it unconfirmed.
    } finally {
      if (_active(run)) {
        if (!identical(context, controlContext)) result = unclear;
        if (stop) {
          _stopBusy = false;
          stopResult = result.message;
        } else {
          _commandBusy = false;
          commandResult = result.message;
        }
        onCommand?.call(result.outcome);
        notifyListeners();
      }
    }
  }

  Future<_CommandReceipt> _sendProfile(
    DeviceLink link,
    LocalEndpoint endpoint,
    ConnectionCancellation run,
    SavedApiProfile configuration,
    ProfileAction action, {
    String? valueField,
    Object? value,
  }) async {
    final body = action.body;
    Map<String, Object?> mappedBody() => {
      if (body != null) ...(jsonDecode(body) as Map<String, Object?>),
      ?valueField: value,
    };
    if (configuration.profile.transport == ApiTransport.rest) {
      final payload = valueField == null ? body : jsonEncode(mappedBody());
      if (payload != null && utf8.encode(payload).length > maxCommandBytes) {
        throw const FormatException('The mapped command is too large.');
      }
      final reply = await link.request(
        action.method,
        action.path,
        run,
        headers: configuration.headers(endpoint),
        body: payload,
      );
      action.response.readHttp(reply.status, reply.bytes);
      return action.response.hasExpected
          ? (
              outcome: CommandOutcome.applied,
              message: 'The configured acknowledgement matched.',
            )
          : (
              outcome: CommandOutcome.unconfirmed,
              message: 'The endpoint returned the configured response. Device state is unconfirmed.',
            );
    }
    final socket = _socket;
    await link.checkNetwork();
    run.check();
    if (socket == null || !identical(_socket, socket)) {
      throw const ConnectionFailure(ConnectionProblem.offline);
    }
    final pending = _PendingAck(newCommandId(), action);
    final payload = jsonEncode({
      ...mappedBody(),
      action.correlationField!: pending.id,
    });
    if (utf8.encode(payload).length > maxCommandBytes) {
      throw const FormatException('The mapped command is too large.');
    }
    _ack = pending;
    try {
      socket.send(payload);
      final matched = await pending.result.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => false,
      );
      if (!matched) throw const ConnectionFailure(ConnectionProblem.response);
      return (
        outcome: CommandOutcome.applied,
        message: 'The correlated acknowledgement matched.',
      );
    } finally {
      if (identical(_ack, pending)) _ack = null;
    }
  }

  void _receivedUniversal(
    DeviceDescriptor descriptor,
    DeviceStatus snapshot,
    String info,
  ) {
    _descriptor = descriptor;
    _snapshot = snapshot;
    final scope = (descriptor.id, descriptor.revision, snapshot.bootId);
    if (_historyScope != scope) {
      _history.clear();
      _lastHistorySequence = null;
      _historyScope = scope;
    }
    if (_lastHistorySequence == null ||
        snapshot.sequence! > _lastHistorySequence!) {
      for (final capability in descriptor.capabilities.values) {
        if (capability.type == 'sensor') {
          _record(capability.id, snapshot.values![capability.id]);
        }
      }
      _lastHistorySequence = snapshot.sequence;
    }
    _received(snapshot.values, info);
  }

  void _receivedLegacy(
    Object? reading,
    String info,
    SavedApiProfile configuration,
  ) {
    _legacyValues = Map.unmodifiable({
      for (final control in configuration.profile.controls.values)
        control.id: control.read(reading),
    });
    for (final control in configuration.profile.controls.values) {
      if (control.type == 'sensor') {
        _record(control.id, _legacyValues[control.id]);
      }
    }
    _received(reading, info, configuration.credential);
  }

  void _record(String id, Object? value) {
    if (value is! num || !value.isFinite) return;
    final samples = _history.putIfAbsent(id, () => []);
    if (samples.length == 60) samples.removeAt(0);
    samples.add((time: DateTime.now(), value: value));
  }

  void _received(Object? reading, String info, [ApiCredential? credential]) {
    lastContact = lastSample = DateTime.now();
    sample = previewReading(reading, credential);
    _setPhase(SessionPhase.connected, info);
  }

  void _setPhase(SessionPhase next, String info) {
    if (phase == SessionPhase.connected && next != phase) {
      _controlContext = Object();
    }
    phase = next;
    detail = info;
    notifyListeners();
  }
}

enum CommandOutcome { applied, rejected, unconfirmed }

typedef _CommandReceipt = ({CommandOutcome outcome, String message});

Future<SessionPhase> checkDeviceConnection(
  DeviceRegistration device,
  DeviceTransport transport,
  SavedApiProfile? configuration,
  ConnectionCancellation cancel, {
  DeviceCredential? pairing,
}) async {
  try {
    if (device.deviceId == null) {
      if (configuration == null) return SessionPhase.idle;
      await testApiProfile(transport, device.endpoint, configuration, cancel);
    } else {
      final connection = await LanUniversalConnector(
        transport,
        device,
        pairing: pairing,
      ).connect(cancel);
      try {
        await connection.readStatus();
      } finally {
        connection.close();
      }
    }
    cancel.check();
    return SessionPhase.connected;
  } on ConnectionFailure catch (failure) {
    if (cancel.isCancelled || failure.problem == ConnectionProblem.cancelled) {
      rethrow;
    }
    return switch (failure.problem) {
      ConnectionProblem.offline ||
      ConnectionProblem.timeout => SessionPhase.offline,
      ConnectionProblem.authentication => SessionPhase.authorization,
      ConnectionProblem.network ||
      ConnectionProblem.changed => SessionPhase.idle,
      _ => SessionPhase.error,
    };
  } on FormatException {
    return SessionPhase.error;
  }
}

class _PendingAck {
  _PendingAck(this.id, this.action);
  final String id;
  final ProfileAction action;
  final result = Completer<bool>();
}

Future<Object?> _readLegacy(
  DeviceLink link,
  SavedApiProfile configuration,
  Map<String, String> headers,
  ConnectionCancellation run,
) async {
  final profile = configuration.profile;
  final reply = await link.request(
    'GET',
    profile.statusPath,
    run,
    headers: headers,
  );
  return profile.response.readHttp(reply.status, reply.bytes);
}

Future<void> _wait(Duration delay, ConnectionCancellation run) async {
  if (run.isCancelled) return;
  final done = Completer<void>();
  final timer = Timer(delay, done.complete);
  final detach = run.onCancel(() {
    timer.cancel();
    if (!done.isCompleted) done.complete();
  });
  try {
    await done.future;
  } finally {
    detach();
  }
}

Future<String> testApiProfile(
  DeviceTransport transport,
  LocalEndpoint endpoint,
  SavedApiProfile configuration,
  ConnectionCancellation cancel,
) async {
  final link = await transport.open(endpoint);
  cancel.check();
  final headers = configuration.headers(endpoint);
  final profile = configuration.profile;
  if (profile.transport == ApiTransport.rest) {
    return previewReading(
      await _readLegacy(link, configuration, headers, cancel),
      configuration.credential,
    );
  }
  final socket = await link.websocket(
    profile.statusPath,
    cancel,
    headers: headers,
  );
  try {
    final match = await _matchingFrames(
      socket.messages,
      profile,
    ).first.timeout(const Duration(seconds: 8));
    return previewReading(match, configuration.credential);
  } on TimeoutException {
    throw const ConnectionFailure(ConnectionProblem.timeout);
  } on StateError {
    throw const ConnectionFailure(ConnectionProblem.offline);
  } finally {
    socket.close();
  }
}

Stream<Object?> _matchingFrames(
  Stream<Object?> stream,
  ApiProfile profile,
) async* {
  await for (final message in stream) {
    try {
      final data = decodeLanEvent(message);
      if (data is Map && profile.acknowledgementFields.any(data.containsKey)) {
        continue;
      }
      yield profile.response.readJson(data);
    } on FormatException {
      // Wait for a frame that matches the status rule.
    }
  }
}

final _sensitiveKey = RegExp(
  r'token|secret|password|authorization|cookie|api[-_]?key',
  caseSensitive: false,
);

String previewReading(Object? value, [ApiCredential? credential]) {
  final secret = credential?.secret ?? '';
  final basic = credential?.mode == ApiAuth.basic
      ? base64Encode(utf8.encode('${credential!.username}:$secret'))
      : '';
  String redactText(String text) {
    if (secret.isNotEmpty) text = text.replaceAll(secret, '[redacted]');
    if (basic.isNotEmpty) text = text.replaceAll(basic, '[redacted]');
    return text;
  }

  Object? redact(Object? item) {
    if (item is String) return redactText(item);
    if (item is Map) {
      return {
        for (final entry in item.entries)
          redactText(
            entry.key.toString(),
          ): _sensitiveKey.hasMatch(entry.key.toString())
              ? '[redacted]'
              : redact(entry.value),
      };
    }
    if (item is List) return item.map(redact).toList();
    return item;
  }

  final safe = redact(value);
  final formatted = safe is String
      ? safe
      : const JsonEncoder.withIndent('  ').convert(safe);
  return formatted.length > 4096
      ? '${formatted.substring(0, 4096)}…'
      : formatted;
}
