import 'dart:convert';

import '../../core/protocol/device_command.dart';
import '../../core/protocol/device_descriptor.dart';
import '../../core/protocol/device_status.dart';
import '../../core/protocol/strict_json.dart';
import '../../core/transport/lan_transport.dart';
import '../../core/transport/universal_transport.dart';
import '../devices/device_registration.dart';
import 'secure_pairing.dart';

class LanUniversalConnector implements UniversalConnector {
  LanUniversalConnector(this._transport, this._device, {this._pairing});

  final DeviceTransport _transport;
  final DeviceRegistration _device;
  final DeviceCredential? _pairing;
  DeviceLink? _bound;

  @override
  Future<UniversalConnection> connect(ConnectionCancellation cancel) async {
    // Keep the original Wi-Fi binding across retries within this run.
    cancel.check();
    final link = _bound ??= await _transport.open(_device.endpoint);
    final attempt = ConnectionCancellation();
    final detach = cancel.onCancel(attempt.cancel);
    try {
      final descriptor = await readRegisteredDescriptor(link, _device, attempt);
      attempt.check();
      final headers = descriptor.requiresPairing
          ? _pairing?.headers(_device)
          : null;
      if (descriptor.requiresPairing && (headers == null || headers.isEmpty)) {
        throw const ConnectionFailure(
          ConnectionProblem.authentication,
          'Open pairing on the device and enter its one-time code.',
        );
      }
      return _LanUniversalConnection(
        link,
        descriptor,
        headers ?? const {},
        attempt,
        detach,
      );
    } catch (_) {
      detach();
      attempt.cancel();
      rethrow;
    }
  }
}

class _LanUniversalConnection implements UniversalConnection {
  _LanUniversalConnection(
    this._link,
    this.descriptor,
    this._headers,
    this._cancel,
    this._detach,
  );

  final DeviceLink _link;
  @override
  final DeviceDescriptor descriptor;
  final Map<String, String> _headers;
  final ConnectionCancellation _cancel;
  final void Function() _detach;
  DeviceSocket? _socket;

  @override
  bool get hasLiveEvents => descriptor.hasEvents;

  @override
  Future<DeviceStatus> readStatus() async {
    final reply = await _link.request(
      'GET',
      '/api/v1/status',
      _cancel,
      headers: _headers,
    );
    if (reply.status != 200 || reply.contentType != 'application/json') {
      throw const FormatException(
        'The ESP IoT status route must return HTTP 200 JSON.',
      );
    }
    return DeviceStatus.parse(
      decodeStrictJson(utf8.decode(reply.bytes)),
      descriptor,
    );
  }

  @override
  Future<Stream<DeviceStatus>> openEvents() async {
    final socket = await _link.websocket(
      '/api/v1/events',
      _cancel,
      headers: _headers,
    );
    if (_cancel.isCancelled) {
      socket.close();
      _cancel.check();
    }
    _socket = socket;
    return _validatedEvents(socket.messages);
  }

  Stream<DeviceStatus> _validatedEvents(Stream<Object?> messages) async* {
    await for (final message in messages) {
      try {
        yield DeviceStatus.parse(
          decodeLanEvent(message),
          descriptor,
          allowHeartbeat: true,
        );
      } on FormatException {
        // Invalid events cannot refresh liveness or readings.
      }
    }
  }

  @override
  Future<void> checkRoute() => _link.checkNetwork();

  @override
  Future<DeviceAcknowledgement> sendCommand(DeviceCommand command) async {
    return readLanAcknowledgement(
      command,
      await _link.request(
        'POST',
        '/api/v1/commands',
        _cancel,
        headers: _headers,
        body: command.body,
      ),
    );
  }

  @override
  void close() {
    _detach();
    _cancel.cancel();
    _socket?.close();
    _socket = null;
  }
}

DeviceAcknowledgement readLanAcknowledgement(
  DeviceCommand command,
  LanResponse reply,
) {
  if (reply.contentType != 'application/json') {
    throw const FormatException('Expected a JSON acknowledgement.');
  }
  final acknowledgement = command.readAcknowledgement(
    decodeStrictJson(utf8.decode(reply.bytes)),
  );
  if (switch (acknowledgement) {
    DeviceAcknowledgement.applied => reply.status == 200,
    DeviceAcknowledgement.rejected => const {
      400,
      409,
      429,
    }.contains(reply.status),
  }) {
    return acknowledgement;
  }
  throw const FormatException(
    'The acknowledgement did not match this command.',
  );
}
