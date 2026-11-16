enum ConnectionProblem {
  network(
    'Connect to your device’s Wi-Fi and make it Android’s active network.',
  ),
  changed(
    'The Wi-Fi connection changed. Check the device address before trying again.',
  ),
  authentication(
    'The device requires authorization or rejected the configured credentials.',
  ),
  certificate(
    'The TLS certificate did not pass verification for the registered address.',
  ),
  redirect(
    'The endpoint redirected the request. Update its configured local path.',
  ),
  timeout('The device did not return a valid response in time.'),
  offline('The device could not be reached. Check its power and connection.'),
  response('The response did not match the configured API.'),
  tooLarge('The device response exceeded 32 KiB.'),
  identity(
    'The device identity or protocol revision changed. Verify the registered device again.',
  ),
  cancelled('The connection was cancelled.');

  const ConnectionProblem(this.message);
  final String message;
}

class ConnectionFailure implements Exception {
  const ConnectionFailure(this.problem, [this.detail]);
  final ConnectionProblem problem;
  final String? detail;
  String get message => detail ?? problem.message;
}

class ConnectionCancellation {
  final _listeners = <void Function()>{};
  bool _cancelled = false;
  bool get isCancelled => _cancelled;

  void check() {
    if (_cancelled) {
      throw const ConnectionFailure(ConnectionProblem.cancelled);
    }
  }

  void Function() onCancel(void Function() listener) {
    check();
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in _listeners.toList()) {
      listener();
    }
    _listeners.clear();
  }
}
