import 'dart:convert';

import '../../core/protocol/device_descriptor.dart';
import '../../core/protocol/strict_json.dart';
import '../../core/transport/endpoint_path.dart';

enum ApiTransport { rest, websocket }

enum ApiAuth { none, bearer, basic, apiKey }

enum ResponseFormat { json, text, status }

const _profileLimit = 12 * 1024;
const maxCommandBytes = 2 * 1024;
final _tokenName = RegExp(r'^[A-Za-z][A-Za-z0-9_-]{0,47}$');
final _controlId = RegExp(r'^[a-z][a-z0-9_-]{0,31}$');
bool _headerText(String value) =>
    value.codeUnits.every((unit) => unit >= 0x20 && unit <= 0x7e);

Map<String, Object?> _object(Object? value, Set<String> fields, String label) {
  if (value is! Map<String, Object?> ||
      value.keys.any((key) => !fields.contains(key))) {
    throw FormatException('Invalid $label object or unknown field.');
  }
  return value;
}

class ApiCredential {
  const ApiCredential.none() : mode = ApiAuth.none, username = '', secret = '';
  const ApiCredential(this.mode, this.username, this.secret);

  final ApiAuth mode;
  final String username;
  final String secret;

  Map<String, String> headers({required bool secure}) {
    if (mode == ApiAuth.none) return const {};
    if (!secure) {
      throw const FormatException(
        'Credentials require a verified HTTPS or WSS device.',
      );
    }
    if (secret.isEmpty ||
        secret.length > 1024 ||
        !_headerText(secret) ||
        (mode == ApiAuth.bearer && secret.contains(' '))) {
      throw const FormatException('Enter a valid credential value.');
    }
    if (mode == ApiAuth.basic &&
        (username.isEmpty ||
            username.length > 128 ||
            username.contains(':') ||
            !_headerText(username))) {
      throw const FormatException(
        'Enter a Basic authentication username without a colon.',
      );
    }
    return switch (mode) {
      ApiAuth.none => const {},
      ApiAuth.bearer => {'Authorization': 'Bearer $secret'},
      ApiAuth.basic => {
        'Authorization':
            'Basic ${base64Encode(utf8.encode('$username:$secret'))}',
      },
      ApiAuth.apiKey => {'X-API-Key': secret},
    };
  }

  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'username': mode == ApiAuth.basic ? username : '',
    'secret': mode == ApiAuth.none ? '' : secret,
  };

  static ApiCredential fromJson(Object? value) {
    final data = _object(value, const {
      'mode',
      'username',
      'secret',
    }, 'credential');
    final mode = ApiAuth.values
        .where((mode) => mode.name == data['mode'])
        .firstOrNull;
    final username = data['username'];
    final secret = data['secret'];
    if (mode == null || username is! String || secret is! String) {
      throw const FormatException('Invalid saved credential.');
    }
    return ApiCredential(mode, username, secret);
  }
}

class ResponseRule {
  const ResponseRule._(
    this.format,
    this.httpStatus,
    this.pointer,
    this.hasExpected,
    this.expected,
  );

  final ResponseFormat format;
  final int httpStatus;
  final String pointer;
  final bool hasExpected;
  final Object? expected;

  static ResponseRule parse(
    Object? value, {
    required bool websocket,
    bool action = false,
  }) {
    final data = _object(value, const {
      'format',
      'status',
      'pointer',
      'equals',
    }, 'response');
    final format = ResponseFormat.values
        .where((item) => item.name == (data['format'] ?? 'json'))
        .firstOrNull;
    final status = data['status'] ?? 200;
    final pointer = data['pointer'] ?? '';
    final hasExpected = data.containsKey('equals');
    final expected = data['equals'];
    if (format == null ||
        status is! int ||
        status < 200 ||
        status > 299 ||
        pointer is! String ||
        pointer.length > 192 ||
        (pointer.isNotEmpty && !pointer.startsWith('/')) ||
        RegExp(r'~(?![01])|[\x00-\x1f\x7f]').hasMatch(pointer) ||
        (websocket &&
            (format != ResponseFormat.json || data.containsKey('status'))) ||
        (format != ResponseFormat.json && pointer.isNotEmpty) ||
        (format == ResponseFormat.status && hasExpected) ||
        (format == ResponseFormat.text && hasExpected && expected is! String) ||
        (expected is Map || expected is List) ||
        (action && websocket && !hasExpected)) {
      throw const FormatException(
        'Invalid response rule. WebSocket commands require a JSON acknowledgement value.',
      );
    }
    return ResponseRule._(format, status, pointer, hasExpected, expected);
  }

  Object? readHttp(int status, List<int> bytes) {
    if (status != httpStatus) {
      throw FormatException(
        'Expected HTTP $httpStatus. The device returned HTTP $status.',
      );
    }
    if (format == ResponseFormat.status) return 'HTTP $status';
    final text = utf8.decode(bytes);
    return format == ResponseFormat.json
        ? readJson(decodeStrictJson(text))
        : _match(text);
  }

  Object? readJson(Object? value) {
    var selected = value;
    if (pointer.isNotEmpty) {
      for (final token in pointer.substring(1).split('/')) {
        final key = token.replaceAll('~1', '/').replaceAll('~0', '~');
        final index = int.tryParse(key);
        if (selected is Map && selected.containsKey(key)) {
          selected = selected[key];
        } else if (selected is List &&
            index != null &&
            index.toString() == key &&
            index >= 0 &&
            index < selected.length) {
          selected = selected[index];
        } else {
          throw const FormatException(
            'The response is missing the configured JSON field.',
          );
        }
      }
    }
    return _match(selected);
  }

  Object? _match(Object? value) {
    if (hasExpected && value != expected) {
      throw const FormatException(
        'The response did not match the configured value.',
      );
    }
    return value;
  }
}

class ProfileAction {
  const ProfileAction._(
    this.method,
    this.path,
    this.body,
    this.correlationField,
    this.response,
  );
  final String method;
  final String path;
  final String? body;
  final String? correlationField;
  final ResponseRule response;

  static ProfileAction parse(Object? value, {required bool websocket}) {
    final data = _object(
      value,
      websocket
          ? const {'message', 'correlationField', 'response'}
          : const {'method', 'path', 'body', 'response'},
      'test command',
    );
    final response = ResponseRule.parse(
      data['response'],
      websocket: websocket,
      action: true,
    );
    if (websocket) {
      final message = data['message'];
      final field = data['correlationField'] ?? 'requestId';
      if (message is! Map<String, Object?> ||
          field is! String ||
          !_tokenName.hasMatch(field) ||
          !_headerText(field) ||
          message.containsKey(field)) {
        throw const FormatException(
          'Use a JSON command object and an unused correlation field.',
        );
      }
      final body = jsonEncode(message);
      if (utf8.encode(body).length > maxCommandBytes - 96) {
        throw const FormatException('The WebSocket command is too large.');
      }
      return ProfileAction._('', '', body, field, response);
    }
    final method = data['method'];
    if (method is! String ||
        !const {'GET', 'POST', 'PUT', 'PATCH', 'DELETE'}.contains(method)) {
      throw const FormatException(
        'Choose GET, POST, PUT, PATCH, or DELETE for the test command.',
      );
    }
    final path = validateEndpointPath(data['path']);
    final body = data.containsKey('body') ? jsonEncode(data['body']) : null;
    if ((method == 'GET' && body != null) ||
        (body != null && utf8.encode(body).length > maxCommandBytes)) {
      throw const FormatException(
        'GET commands cannot have a body. JSON command bodies are limited to 2 KiB.',
      );
    }
    return ProfileAction._(method, path, body, null, response);
  }
}

class ProfileControl {
  const ProfileControl._({
    required this.id,
    required this.name,
    required this.type,
    required this.reading,
    required this.commands,
    this.valueField,
    this.min,
    this.max,
    this.step,
    this.unit = '',
  });

  final String id, name, type, unit;
  final ResponseRule? reading;
  final Map<String, ProfileAction> commands;
  final String? valueField;
  final num? min, max, step;

  static ProfileControl parse(
    Object? value,
    bool websocket,
    String statusPath,
  ) {
    const base = {'id', 'name', 'type'};
    final type = value is Map ? value['type'] : null;
    final fields = switch (type) {
      'switch' => const {...base, 'pointer', 'on', 'off'},
      'range' => const {
        ...base,
        'pointer',
        'unit',
        'min',
        'max',
        'step',
        'set',
        'valueField',
      },
      'sensor' => const {...base, 'pointer', 'unit'},
      'action' => const {...base, 'invoke'},
      _ => throw const FormatException(
        'Use switch, range, sensor, or action for a dashboard control.',
      ),
    };
    final data = _object(value, fields, 'dashboard control');
    final id = data['id'];
    final name = data['name'];
    final unit = data['unit'] ?? '';
    if (id is! String ||
        !_controlId.hasMatch(id) ||
        !validLabel(id, 32) ||
        !validLabel(name, 64) ||
        !validLabel(unit, 16, allowEmpty: true)) {
      throw const FormatException(
        'Use a unique control ID, a label, and an optional short unit.',
      );
    }
    final reading = type == 'action'
        ? null
        : ResponseRule.parse({
            'format': 'json',
            'pointer': data['pointer'] ?? '',
          }, websocket: false);
    final commands = <String, ProfileAction>{};
    final slots = switch (type) {
      'switch' => const ['on', 'off'],
      'range' => const ['set'],
      'action' => const ['invoke'],
      _ => const <String>[],
    };
    for (final slot in slots) {
      final action = ProfileAction.parse(data[slot], websocket: websocket);
      if (!action.response.hasExpected ||
          (action.method == 'GET' && action.path == statusPath)) {
        throw const FormatException(
          'Dashboard commands need an expected acknowledgement and a separate path from status for GET commands.',
        );
      }
      commands[slot] = action;
    }
    final min = data['min'];
    final max = data['max'];
    final step = data['step'];
    final field = data['valueField'];
    if (type == 'range') {
      final command = commands['set']!;
      final body = command.body == null
          ? <String, Object?>{}
          : jsonDecode(command.body!);
      if (min is! num ||
          max is! num ||
          step is! num ||
          min >= max ||
          step <= 0 ||
          (max.toDouble() - min.toDouble()) / step > 10000 ||
          !validRangeValue(max, min, max, step) ||
          (max.toDouble() - min.toDouble()) / step < 1 ||
          field is! String ||
          !_tokenName.hasMatch(field) ||
          !_headerText(field) ||
          field == command.correlationField ||
          command.method == 'GET' ||
          body is! Map ||
          body.containsKey(field)) {
        throw const FormatException(
          'A range needs aligned bounds and a command with an unused JSON value field.',
        );
      }
    }
    return ProfileControl._(
      id: id,
      name: name! as String,
      type: type! as String,
      unit: unit as String,
      reading: reading,
      commands: Map.unmodifiable(commands),
      valueField: field as String?,
      min: min as num?,
      max: max as num?,
      step: step as num?,
    );
  }

  Object? read(Object? status) {
    try {
      final value = reading?.readJson(status);
      return switch (type) {
        'switch' when value is bool => value,
        'sensor' when value is num => value,
        'range' when value is num && value >= min! && value <= max! => value,
        _ => null,
      };
    } on FormatException {
      return null;
    }
  }
}

class ApiProfile {
  const ApiProfile._(
    this.source,
    this.transport,
    this.statusPath,
    this.poll,
    this.response,
    this.headers,
    this.action,
    this.controls,
  );
  final String source;
  final ApiTransport transport;
  final String statusPath;
  final Duration poll;
  final ResponseRule response;
  final Map<String, String> headers;
  final ProfileAction? action;
  final Map<String, ProfileControl> controls;

  Set<String> get acknowledgementFields => {
    ?action?.correlationField,
    for (final control in controls.values)
      for (final mapping in control.commands.values) ?mapping.correlationField,
  };

  static ApiProfile parse(String source) {
    if (utf8.encode(source).length > _profileLimit) {
      throw const FormatException('API profiles are limited to 12 KiB.');
    }
    final data = _object(decodeStrictJson(source), const {
      'transport',
      'statusPath',
      'pollSeconds',
      'response',
      'headers',
      'action',
      'controls',
    }, 'API profile');
    final transport = ApiTransport.values
        .where((mode) => mode.name == data['transport'])
        .firstOrNull;
    final poll = data['pollSeconds'] ?? 10;
    if (transport == null || poll is! int || poll < 5 || poll > 300) {
      throw const FormatException(
        'Use REST or WebSocket and a status interval from 5 to 300 seconds.',
      );
    }
    final headers = <String, String>{};
    final rawHeaders = data['headers'] ?? const <String, Object?>{};
    if (rawHeaders is! Map<String, Object?> || rawHeaders.length > 8) {
      throw const FormatException('Set up to eight custom headers.');
    }
    for (final entry in rawHeaders.entries) {
      final key = entry.key.toLowerCase();
      final value = entry.value;
      // Restrict custom headers to application metadata. Authentication has a separate configuration.
      if (!key.startsWith('x-') ||
          !_tokenName.hasMatch(entry.key) ||
          !_headerText(entry.key) ||
          RegExp(r'auth|token|key|pass|secret|cookie|proxy|forwarded|redirect')
              .hasMatch(key) ||
          headers.containsKey(key) ||
          value is! String ||
          value.length > 256 ||
          !_headerText(value)) {
        throw const FormatException(
          'Custom headers must be unique, non-sensitive X- metadata headers.',
        );
      }
      headers[key] = value;
    }
    final websocket = transport == ApiTransport.websocket;
    final statusPath = validateEndpointPath(data['statusPath']);
    final action = data['action'] == null
        ? null
        : ProfileAction.parse(data['action'], websocket: websocket);
    if (action?.method == 'GET' && action?.path == statusPath) {
      throw const FormatException(
        'Use a separate read-only status path from the state-changing GET command.',
      );
    }
    final rawControls = data['controls'] ?? const [];
    if (rawControls is! List || rawControls.length > 24) {
      throw const FormatException(
        'An API profile can have up to 24 dashboard controls.',
      );
    }
    final controls = <String, ProfileControl>{};
    for (final value in rawControls) {
      final control = ProfileControl.parse(value, websocket, statusPath);
      if (controls.containsKey(control.id)) {
        throw const FormatException('Dashboard control IDs must be unique.');
      }
      controls[control.id] = control;
    }
    return ApiProfile._(
      source,
      transport,
      statusPath,
      Duration(seconds: poll),
      ResponseRule.parse(data['response'], websocket: websocket),
      Map.unmodifiable(headers),
      action,
      Map.unmodifiable(controls),
    );
  }
}
