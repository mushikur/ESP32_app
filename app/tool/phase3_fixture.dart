import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:esp_iot/core/protocol/device_descriptor.dart';

// Loopback-only development fixtures. Commands change in-memory values.
Future<void> main() async {
  final descriptor = jsonDecode(
    await File('../protocol/v1/examples/bench-controller.json').readAsString(),
  ) as Map<String, dynamic>;
  descriptor['name'] = 'ESP IoT test fixture';
  descriptor['auth'] = 'none';
  descriptor['events'] = true;
  final capabilities = DeviceDescriptor.decode(
    utf8.encode(jsonEncode(descriptor)),
  ).capabilities;
  const bootId = '11111111111111111111111111111111';
  final universal = await HttpServer.bind(InternetAddress.loopbackIPv4, 8765);
  final legacy = await HttpServer.bind(InternetAddress.loopbackIPv4, 8766);
  var sequence = 0;
  var commandCount = 0;
  var legacyLed = false;
  final values = <String, Object?>{
    'led': false,
    'relay_1': false,
    'relay_2': true,
    'relay_3': false,
    'relay_4': false,
    'fan_speed': 25,
    'servo_angle': 90,
    'drive': 'stopped',
    'motor_limit': 30,
  };
  Map<String, Object?> legacyStatus() => {
    'led': legacyLed,
    'temperature': 23.5,
    'identifyCount': commandCount,
  };
  Map<String, Object?> universalStatus() => {
    'deviceId': descriptor['deviceId'],
    'revision': descriptor['revision'],
    'bootId': bootId,
    'seq': ++sequence,
    'values': {
      ...values,
      'temperature': 22 + (sequence % 8) / 5,
      'distance': 54 - sequence % 12,
    },
  };
  universal.listen((request) async {
    if (request.method == 'GET' &&
        request.uri.path == '/api/v1/events' &&
        WebSocketTransformer.isUpgradeRequest(request)) {
      await _events(request, universalStatus);
      return;
    }
    if (request.method == 'GET' && request.uri.path == '/.well-known/esp-iot') {
      await _json(request, descriptor);
    } else if (request.method == 'GET' &&
        request.uri.path == '/api/v1/status') {
      await _json(request, universalStatus());
    } else if (request.method == 'POST' &&
        request.uri.path == '/api/v1/commands') {
      final payload = await _readCommand(request);
      final id = payload?['commandId'];
      if (payload == null ||
          !validDeviceId(id) ||
          payload['bootId'] != bootId ||
          payload['revision'] != descriptor['revision']) {
        request.response.statusCode = HttpStatus.badRequest;
        await _json(request, {'code': 'invalid_command'});
        return;
      }
      final capability = capabilities[payload['capabilityId']];
      final operation = payload['op'];
      final value = payload['value'];
      final applied = switch ((capability?.type, operation)) {
        ('switch', 'set') => value is bool,
        ('range', 'set') => validRangeValue(
          value,
          capability!.min!,
          capability.max!,
          capability.step!,
        ),
        ('motion', 'stop') ||
        ('action', 'invoke') => !payload.containsKey('value'),
        _ => false,
      };
      if (applied && operation == 'set') values[capability!.id] = value;
      if (applied && operation == 'stop') values[capability!.id] = 'stopped';
      if (!applied) request.response.statusCode = HttpStatus.badRequest;
      await _json(request, {
        'commandId': id,
        'deviceId': descriptor['deviceId'],
        'bootId': bootId,
        'revision': descriptor['revision'],
        'outcome': applied ? 'applied' : 'rejected',
        if (!applied) 'code': 'invalid_command',
      });
    } else {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
  });
  legacy.listen((request) async {
    if (request.method == 'GET' &&
        request.uri.path == '/ws' &&
        WebSocketTransformer.isUpgradeRequest(request)) {
      await _events(
        request,
        legacyStatus,
        onMessage: (socket, message) {
          if (message is! String || message.length > 2048) return;
          try {
            final data = jsonDecode(message);
            if (data is! Map || data['requestId'] is! String) return;
            final enabled = data['enabled'];
            final identify = data['op'] == 'identify';
            final setLed = data['op'] == 'setLed' && enabled is bool;
            if (identify) commandCount++;
            if (setLed) legacyLed = enabled;
            socket.add(
              jsonEncode({
                'ok': identify || setLed,
                'requestId': data['requestId'],
                'identifyCount': commandCount,
              }),
            );
          } on FormatException {
            // Ignore malformed fixture commands.
          }
        },
      );
      return;
    }
    if (request.method == 'GET' && request.uri.path == '/status') {
      await _json(request, legacyStatus());
    } else if (request.method == 'POST' && request.uri.path == '/led') {
      final data = await _readCommand(request);
      if (data?['enabled'] case final bool enabled) {
        legacyLed = enabled;
        await _json(request, {'ok': true});
      } else {
        request.response.statusCode = HttpStatus.badRequest;
        await _json(request, {'ok': false});
      }
    } else if (request.method == 'POST' && request.uri.path == '/identify') {
      final body = await utf8.decoder.bind(request).join();
      try {
        final data = jsonDecode(body);
        if (data is Map && data['identify'] == true) {
          await _json(request, {'ok': true, 'identifyCount': ++commandCount});
          return;
        }
      } on FormatException {
        // Return a fixture validation error.
      }
      request.response.statusCode = HttpStatus.badRequest;
      await _json(request, {'ok': false});
    } else if (request.method == 'GET' && request.uri.path == '/') {
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        '<!doctype html><title>Phase 3 legacy test fixture</title>',
      );
      await request.response.close();
    } else if (request.method == 'GET' && request.uri.path == '/redirect') {
      request.response.statusCode = HttpStatus.found;
      request.response.headers.set('location', '/status');
      await request.response.close();
    } else {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
  });
  stdout.writeln(
    'Loopback fixtures active on 8765 (ESP IoT v1) and 8766 (legacy REST and WS).',
  );
}

Future<Map<String, Object?>?> _readCommand(HttpRequest request) async {
  final bytes = <int>[];
  await for (final chunk in request) {
    if (bytes.length + chunk.length > 2048) return null;
    bytes.addAll(chunk);
  }
  try {
    final value = jsonDecode(utf8.decode(bytes));
    return value is Map<String, Object?> ? value : null;
  } on FormatException {
    return null;
  }
}

Future<void> _json(HttpRequest request, Object? value) async {
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(value));
  await request.response.close();
}

Future<void> _events(
  HttpRequest request,
  Object? Function() reading, {
  void Function(WebSocket socket, Object? message)? onMessage,
}) async {
  final socket = await WebSocketTransformer.upgrade(request);
  void send() {
    if (socket.readyState == WebSocket.open) socket.add(jsonEncode(reading()));
  }

  send();
  final timer = Timer.periodic(const Duration(seconds: 2), (_) => send());
  socket.listen(
    (message) => onMessage?.call(socket, message),
    onDone: timer.cancel,
    onError: (Object _) => timer.cancel(),
    cancelOnError: true,
  );
}
