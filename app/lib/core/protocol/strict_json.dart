import 'dart:convert';

final _tokens = RegExp(r'"(?:[^"\\\x00-\x1f]|\\.)*"|[{}\[\],]');

/// Checks the structure before decoding so duplicate keys cannot be overwritten.
Object? decodeStrictJson(String source) {
  final scopes = <Set<String>?>[];
  String? previous;
  for (final match in _tokens.allMatches(source)) {
    final token = match[0]!;
    switch (token) {
      case '{':
      case '[':
        scopes.add(token == '{' ? <String>{} : null);
        if (scopes.length > 12) {
          throw const FormatException('JSON is nested too deeply.');
        }
      case '}':
      case ']':
        if (scopes.isNotEmpty) scopes.removeLast();
      case ',':
        break;
      default:
        if (scopes.isNotEmpty && (previous == '{' || previous == ',')) {
          final keys = scopes.last;
          if (keys != null && !keys.add(jsonDecode(token) as String)) {
            throw const FormatException('JSON contains a duplicate field.');
          }
        }
    }
    previous = token;
  }
  final value = jsonDecode(source);
  _checkNumbers(value);
  return value;
}

void _checkNumbers(Object? value) {
  if (value is num && !value.isFinite) {
    throw const FormatException('JSON contains a non-finite number.');
  }
  if (value is Map<String, dynamic>) {
    value.values.forEach(_checkNumbers);
  } else if (value is List) {
    value.forEach(_checkNumbers);
  }
}
