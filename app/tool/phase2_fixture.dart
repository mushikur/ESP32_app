import 'dart:convert';
import 'dart:io';

/// Explicitly local, read-only protocol fixture for Android emulator checks.
Future<void> main() async {
  final source = File('../protocol/v1/examples/bench-controller.json');
  final descriptor =
      jsonDecode(await source.readAsString()) as Map<String, dynamic>;
  descriptor['name'] = 'ESP IoT test fixture';
  descriptor['auth'] = 'none';
  final universal = await HttpServer.bind(InternetAddress.loopbackIPv4, 8765);
  final legacy = await HttpServer.bind(InternetAddress.loopbackIPv4, 8766);
  universal.listen((request) => _serve(request, descriptor));
  legacy.listen((request) => _serve(request, null));
  stdout.writeln('Loopback test fixtures: universal 8765, legacy 8766.');
}

Future<void> _serve(
  HttpRequest request,
  Map<String, dynamic>? descriptor,
) async {
  final response = request.response;
  response.persistentConnection = false;
  if (request.method != 'GET') {
    response.statusCode = HttpStatus.methodNotAllowed;
  } else if (request.uri.path == '/.well-known/esp-iot' && descriptor != null) {
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(descriptor));
  } else if (request.uri.path == '/') {
    response.headers.contentType = ContentType.html;
    response.write('<!doctype html><title>Local ESP IoT test fixture</title>');
  } else {
    response.statusCode = HttpStatus.notFound;
  }
  await response.close();
}
