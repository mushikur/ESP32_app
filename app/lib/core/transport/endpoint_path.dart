final _pathCharacters = RegExp(r'^/[A-Za-z0-9_./~-]*$');

/// API profiles can select a route on the registered origin only.
String validateEndpointPath(Object? input) {
  if (input is! String ||
      input.length > 192 ||
      !_pathCharacters.hasMatch(input) ||
      input.trim() != input ||
      input.contains('//') ||
      input.split('/').any((segment) => segment == '.' || segment == '..')) {
    throw const FormatException(
      'Use a relative device path such as /api/status. URLs, queries, and dot segments are excluded.',
    );
  }
  return input;
}
