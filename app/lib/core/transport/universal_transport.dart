import '../protocol/device_command.dart';
import '../protocol/device_descriptor.dart';
import '../protocol/device_status.dart';
import 'connection_failure.dart';

/// Scoped to one monitoring run. The selected route must stay fixed on retry.
abstract interface class UniversalConnector {
  Future<UniversalConnection> connect(ConnectionCancellation cancel);
}

/// A connection to a verified device on the selected route.
///
/// Implementations verify identity, authorize each operation, bound I/O, and
/// return only validated device messages. A write with an uncertain result
/// must fail without replaying the command on this or another route.
abstract interface class UniversalConnection {
  DeviceDescriptor get descriptor;
  bool get hasLiveEvents;

  /// Returns a fresh full snapshot for the verified identity and revision.
  Future<DeviceStatus> readStatus();

  /// Streams full snapshots and heartbeats for the verified device.
  Future<Stream<DeviceStatus>> openEvents();

  Future<void> checkRoute();
  Future<DeviceAcknowledgement> sendCommand(DeviceCommand command);

  /// Releases attempt resources. Safe to call more than once.
  void close();
}
