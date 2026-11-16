import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/io.dart';

import '../../features/discovery/local_discovery_platform.dart';
import '../../features/discovery/local_endpoint.dart';
import '../protocol/strict_json.dart';
import 'connection_failure.dart';
import 'endpoint_path.dart';

export 'connection_failure.dart';

const _maxResponse = 32 * 1024;
const _deadline = Duration(seconds: 5);

class LanResponse {
  const LanResponse(this.status, this.contentType, this.bytes);
  final int status;
  final String contentType;
  final Uint8List bytes;
}

Object? decodeLanEvent(Object? message) {
  if (message is! String || utf8.encode(message).length > _maxResponse) {
    throw const FormatException(
      'Expected a bounded WebSocket JSON text frame.',
    );
  }
  return decodeStrictJson(message);
}

abstract interface class DeviceSocket {
  Stream<Object?> get messages;
  void send(String text);
  void close();
}

abstract interface class DeviceLink {
  Future<void> checkNetwork();
  Future<LanResponse> request(
    String method,
    String path,
    ConnectionCancellation cancel, {
    Map<String, String> headers = const {},
    String? body,
  });
  Future<DeviceSocket> websocket(
    String path,
    ConnectionCancellation cancel, {
    Map<String, String> headers = const {},
  });
}

abstract interface class DeviceTransport {
  Future<DeviceLink> open(LocalEndpoint endpoint);
}

final deviceTransportProvider = Provider<DeviceTransport>(
  (ref) => LanTransport(ref.watch(discoveryPlatformProvider)),
);

class LanTransport implements DeviceTransport {
  const LanTransport(this._platform);
  final LocalDiscoveryPlatform _platform;

  @override
  Future<DeviceLink> open(LocalEndpoint endpoint) async {
    final scope = await _wifi(_platform);
    if (!scope.isDefault || !scope.contains(endpoint.host)) {
      throw const ConnectionFailure(ConnectionProblem.network);
    }
    return _LanLink(_platform, scope, endpoint);
  }

  Future<LanResponse> probeCleartext(
    WifiScope scope,
    LocalEndpoint endpoint,
    ConnectionCancellation cancel, {
    required bool root,
    required bool quick,
  }) async {
    if (endpoint.secure || !scope.isDefault || !scope.contains(endpoint.host)) {
      throw const ConnectionFailure(ConnectionProblem.network);
    }
    return _LanLink(_platform, scope, endpoint)._request(
      'GET',
      root ? '/' : '/.well-known/esp-iot',
      cancel,
      probe: root ? _Probe.reachability : _Probe.descriptor,
      quick: quick,
    );
  }
}

enum _Probe { descriptor, reachability }

Future<WifiScope> _wifi(LocalDiscoveryPlatform platform) async {
  try {
    return await platform.wifi();
  } on DiscoveryFailure {
    throw const ConnectionFailure(ConnectionProblem.network);
  } on FormatException {
    throw const ConnectionFailure(ConnectionProblem.network);
  }
}

class _LanLink implements DeviceLink {
  const _LanLink(this._platform, this._scope, this._endpoint);
  final LocalDiscoveryPlatform _platform;
  final WifiScope _scope;
  final LocalEndpoint _endpoint;

  @override
  Future<void> checkNetwork() async {
    final current = await _wifi(_platform);
    if (!current.isDefault || !current.sameLink(_scope)) {
      throw const ConnectionFailure(ConnectionProblem.changed);
    }
  }

  Uri _uri(String path, {bool websocket = false}) => Uri(
    scheme: websocket ? (_endpoint.secure ? 'wss' : 'ws') : _endpoint.scheme,
    host: _endpoint.host,
    port: _endpoint.port,
    path: validateEndpointPath(path),
  );

  bool _matchesPin(X509Certificate certificate) {
    final now = DateTime.now();
    return !now.isBefore(certificate.startValidity) &&
        now.isBefore(certificate.endValidity) &&
        sha256.convert(certificate.der).toString() ==
            _endpoint.certificateSha256;
  }

  void _checkHeaders(Map<String, String> headers) {
    if (!_endpoint.secure &&
        headers.keys.any(
          (name) => const {
            'authorization',
            'cookie',
            'x-api-key',
          }.contains(name.toLowerCase()),
        )) {
      throw const ConnectionFailure(
        ConnectionProblem.authentication,
        'Credentials require HTTPS or WSS.',
      );
    }
  }

  HttpClient _client(
    ConnectionCancellation cancel, {
    Duration connectionTimeout = const Duration(seconds: 3),
  }) => HttpClient()
    ..connectionTimeout = connectionTimeout
    ..autoUncompress = false
    ..findProxy = ((_) => 'DIRECT')
    ..connectionFactory = (url, proxyHost, proxyPort) async {
      if (proxyHost != null ||
          proxyPort != null ||
          url.userInfo.isNotEmpty ||
          url.host != _endpoint.host ||
          url.port != _endpoint.port ||
          url.scheme != _endpoint.scheme) {
        throw const ConnectionFailure(ConnectionProblem.redirect);
      }
      await checkNetwork();
      cancel.check();
      final task = _endpoint.secure
          ? await SecureSocket.startConnect(
              _endpoint.host,
              _endpoint.port,
              onBadCertificate: _endpoint.certificateSha256 == null
                  ? null
                  : _matchesPin,
            )
          : await Socket.startConnect(
              InternetAddress(_endpoint.host),
              _endpoint.port,
              sourceAddress: InternetAddress(_scope.address),
            );
      final socket = task.socket.then<Socket>((socket) async {
        try {
          cancel.check();
          if (_endpoint.certificateSha256 != null) {
            final certificate = (socket as SecureSocket).peerCertificate;
            if (certificate == null || !_matchesPin(certificate)) {
              throw const ConnectionFailure(ConnectionProblem.certificate);
            }
          }
          if (socket.remoteAddress.address != _endpoint.host ||
              socket.remotePort != _endpoint.port) {
            throw const ConnectionFailure(ConnectionProblem.changed);
          }
          await checkNetwork();
          cancel.check();
          return socket;
        } on Object {
          socket.destroy();
          rethrow;
        }
      });
      return ConnectionTask.fromSocket(socket, task.cancel);
    };

  @override
  Future<LanResponse> request(
    String method,
    String path,
    ConnectionCancellation cancel, {
    Map<String, String> headers = const {},
    String? body,
  }) => _request(method, path, cancel, headers: headers, body: body);

  Future<LanResponse> _request(
    String method,
    String path,
    ConnectionCancellation cancel, {
    Map<String, String> headers = const {},
    String? body,
    _Probe? probe,
    bool quick = false,
  }) async {
    _checkHeaders(headers);
    final uri = _uri(path);
    if (!const {'GET', 'POST', 'PUT', 'PATCH', 'DELETE'}.contains(method)) {
      throw const ConnectionFailure(ConnectionProblem.response);
    }
    await checkNetwork();
    cancel.check();
    final client = _client(
      cancel,
      connectionTimeout: Duration(
        milliseconds: probe == null ? 3000 : (quick ? 550 : 1200),
      ),
    );
    final dio = Dio()
      ..httpClientAdapter = IOHttpClientAdapter(createHttpClient: () => client);
    final token = CancelToken();
    final detach = cancel.onCancel(() {
      token.cancel();
      client.close(force: true);
    });
    try {
      final response = await _exchange(
        dio,
        uri,
        method,
        headers,
        body,
        token,
        probe: probe,
      ).timeout(
        probe == null
            ? _deadline
            : Duration(milliseconds: quick ? 1450 : 3200),
      );
      await checkNetwork();
      cancel.check();
      return response;
    } on DioException catch (error) {
      if (error.error case final ConnectionFailure failure) throw failure;
      if (error.error is HandshakeException) {
        throw const ConnectionFailure(ConnectionProblem.certificate);
      }
      throw ConnectionFailure(switch (error.type) {
        DioExceptionType.cancel => ConnectionProblem.cancelled,
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout => ConnectionProblem.timeout,
        DioExceptionType.badCertificate => ConnectionProblem.certificate,
        _ => ConnectionProblem.offline,
      });
    } on TimeoutException {
      throw const ConnectionFailure(ConnectionProblem.timeout);
    } on SocketException {
      throw const ConnectionFailure(ConnectionProblem.offline);
    } on HttpException {
      throw const ConnectionFailure(ConnectionProblem.response);
    } finally {
      detach();
      token.cancel();
      dio.close(force: true);
      client.close(force: true);
    }
  }

  Future<LanResponse> _exchange(
    Dio dio,
    Uri uri,
    String method,
    Map<String, String> headers,
    String? body,
    CancelToken token, {
    required _Probe? probe,
  }) async {
    final reply = await dio.requestUri<ResponseBody>(
      uri,
      data: body,
      cancelToken: token,
      options: Options(
        method: method,
        responseType: ResponseType.stream,
        followRedirects: false,
        validateStatus: (_) => true,
        headers: {
          ...headers,
          'Accept': switch (probe) {
            _Probe.descriptor => 'application/json',
            _Probe.reachability => '*/*',
            null => 'application/json, text/plain',
          },
          'Accept-Encoding': 'identity',
          'Connection': 'close',
          if (body != null) 'Content-Type': 'application/json',
        },
      ),
    );
    final status = reply.statusCode ?? 0;
    _checkHttpStatus(status);
    final contentType =
        reply.headers.value('content-type')?.split(';').first.trim().toLowerCase() ??
        '';
    if (probe == _Probe.reachability ||
        (probe == _Probe.descriptor &&
            (status != 200 || contentType != 'application/json'))) {
      // Legacy verification only needs the response status and media type.
      return LanResponse(status, contentType, Uint8List(0));
    }
    final encoding = reply.headers.value('content-encoding');
    if (encoding != null && encoding.toLowerCase() != 'identity') {
      throw const ConnectionFailure(
        ConnectionProblem.response,
        'Compressed replies are unsupported.',
      );
    }
    final length = int.tryParse(reply.headers.value('content-length') ?? '');
    if (length != null && length > _maxResponse) {
      throw const ConnectionFailure(ConnectionProblem.tooLarge);
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in reply.data!.stream) {
      if (bytes.length + chunk.length > _maxResponse) {
        throw const ConnectionFailure(ConnectionProblem.tooLarge);
      }
      bytes.add(chunk);
    }
    return LanResponse(status, contentType, bytes.takeBytes());
  }

  @override
  Future<DeviceSocket> websocket(
    String path,
    ConnectionCancellation cancel, {
    Map<String, String> headers = const {},
  }) async {
    _checkHeaders(headers);
    final uri = _uri(path, websocket: true);
    await checkNetwork();
    cancel.check();
    final client = _client(cancel);
    final stop = cancel.onCancel(() => client.close(force: true));
    var abandoned = false;
    WebSocket? socket;
    try {
      final pending =
          WebSocket.connect(
            uri.toString(),
            headers: headers,
            customClient: _UpgradeClient(client),
            compression: CompressionOptions.compressionOff,
            maxPayloadLength: _maxResponse,
          ).then((value) {
            if (abandoned || cancel.isCancelled) {
              unawaited(
                value.close().then<void>((_) {}, onError: (Object _) {}),
              );
              throw const ConnectionFailure(ConnectionProblem.cancelled);
            }
            socket = value;
            return value;
          });
      final connected = await pending.timeout(_deadline);
      await checkNetwork();
      cancel.check();
      connected.pingInterval = const Duration(seconds: 12);
      final session = _LanSocket(IOWebSocketChannel(connected), cancel);
      socket = null; // The returned connection now owns the upgraded socket.
      return session;
    } on WebSocketException catch (error) {
      _checkHttpStatus(error.httpStatusCode ?? 0);
      throw const ConnectionFailure(
        ConnectionProblem.response,
        'The endpoint did not accept a WebSocket connection.',
      );
    } on FormatException {
      throw const ConnectionFailure(ConnectionProblem.response);
    } on TypeError {
      throw const ConnectionFailure(ConnectionProblem.response);
    } on HandshakeException {
      throw const ConnectionFailure(ConnectionProblem.certificate);
    } on TimeoutException {
      throw const ConnectionFailure(ConnectionProblem.timeout);
    } on SocketException {
      throw const ConnectionFailure(ConnectionProblem.offline);
    } on HttpException {
      throw const ConnectionFailure(ConnectionProblem.response);
    } finally {
      abandoned = true;
      stop();
      if (socket case final remaining?) {
        unawaited(remaining.close().then<void>((_) {}, onError: (Object _) {}));
      }
      client.close(force: true);
    }
  }
}

void _checkHttpStatus(int status) {
  if (status == 401 || status == 403) {
    throw const ConnectionFailure(ConnectionProblem.authentication);
  }
  if (status >= 300 && status < 400) {
    throw const ConnectionFailure(ConnectionProblem.redirect);
  }
}

// Dart's WebSocket handshake uses openUrl on its supplied client.
class _UpgradeClient implements HttpClient {
  _UpgradeClient(this._client);
  final HttpClient _client;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      (await _client.openUrl(method, url))..followRedirects = false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LanSocket implements DeviceSocket {
  _LanSocket(this._channel, ConnectionCancellation cancel) {
    _detach = cancel.onCancel(close);
  }

  final IOWebSocketChannel _channel;
  late final void Function() _detach;
  bool _closed = false;

  @override
  Stream<Object?> get messages => _channel.stream;

  @override
  void send(String text) {
    if (_closed) throw const ConnectionFailure(ConnectionProblem.offline);
    _channel.sink.add(text);
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _detach();
    unawaited(_channel.sink.close().then<void>((_) {}, onError: (Object _) {}));
  }
}
