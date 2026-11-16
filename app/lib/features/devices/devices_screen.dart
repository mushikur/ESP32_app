import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_theme.dart';
import '../../core/transport/lan_transport.dart';
import '../../core/ui/surfaces.dart';
import '../connection/device_connection_screen.dart';
import '../connection/device_session.dart';
import '../connection/profile_store.dart';
import '../connection/secure_pairing.dart';
import '../discovery/local_discovery_platform.dart';
import '../discovery/pairing_qr.dart';
import 'device_activity_screen.dart';
import 'device_card.dart';
import 'device_connections.dart';
import 'device_database.dart';
import 'device_registry.dart';
import 'device_settings_screen.dart';

class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});

  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  DiscoveryCancellation? _run;
  late final AppLifecycleListener _lifecycle;
  int _checked = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onHide: _cancel);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _run?.cancel();
    super.dispose();
  }

  void _cancel() {
    if (_run == null) return;
    _run!.cancel();
    if (mounted) setState(() => _run = null);
  }

  Future<void> _check(List<DeviceRegistration> entries) async {
    if (_run != null || entries.isEmpty) return;
    final cancel = DiscoveryCancellation();
    final transport = ref.read(deviceTransportProvider);
    final profiles = ref.read(apiProfileStoreProvider);
    final pairings = ref.read(pairingStoreProvider);
    final connections = ref.read(deviceConnectionsProvider.notifier);
    setState(() {
      _run = cancel;
      _checked = 0;
      _total = entries.length;
    });
    var cursor = 0;
    Future<void> worker() async {
      while (!cancel.isCancelled && cursor < entries.length) {
        final device = entries[cursor++];
        var phase = SessionPhase.error;
        try {
          final configuration = device.deviceId == null
              ? await profiles.load(device)
              : null;
          cancel.check();
          final pairing = device.deviceId != null && device.endpoint.secure
              ? await pairings.load(device)
              : null;
          cancel.check();
          phase = await checkDeviceConnection(
            device,
            transport,
            configuration,
            cancel,
            pairing: pairing,
          );
        } on Exception {
          if (cancel.isCancelled) return;
        }
        if (!mounted || cancel.isCancelled) return;
        final current =
            ref
                .read(deviceRegistryProvider)
                .value
                ?.any(
                  (item) =>
                      item.registrationId == device.registrationId &&
                      item.endpoint == device.endpoint &&
                      item.endpoint.certificateSha256 ==
                          device.endpoint.certificateSha256,
                ) ??
            false;
        if (current) {
          connections.observe(device, presenceForPhase(phase));
          final kind = activityForPhase(phase);
          if (kind != null) {
            unawaited(
              connections.record(
                device,
                kind: kind,
                seen: phase == SessionPhase.connected ? DateTime.now() : null,
              ),
            );
          }
        }
        setState(() => _checked++);
      }
    }

    try {
      await Future.wait(List.generate(min(entries.length, 3), (_) => worker()));
    } finally {
      if (mounted && identical(_run, cancel)) setState(() => _run = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final inventory = ref.watch(deviceRegistryProvider);
    final entries = inventory.value;
    final observations = ref.watch(deviceConnectionsProvider);
    final history = ref.watch(deviceHistoryProvider).value;
    return ScreenScroll(
      children: [
        const Eyebrow('YOUR INVENTORY'),
        const SizedBox(height: 8),
        Semantics(
          header: true,
          child: Text('My Devices', style: theme.headlineLarge),
        ),
        const SizedBox(height: 6),
        Text(
          'ESP32 projects saved on this phone.',
          style: theme.bodyMedium?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 22),
        if (inventory.hasError)
          EmptyPanel(
            icon: Icons.error_outline_rounded,
            title: 'Could not load registrations',
            description: 'Try loading your saved device list again.',
            action: TextButton(
              onPressed: () => ref.invalidate(deviceRegistryProvider),
              child: const Text('Try again'),
            ),
          )
        else if (entries == null)
          const Panel(child: Text('Loading registrations…'))
        else if (entries.isEmpty)
          EmptyPanel(
            icon: Icons.developer_board_outlined,
            title: 'No registered devices',
            description: 'Discover a compatible ESP32 or check an existing project by its local address.',
            action: FilledButton.icon(
              onPressed: () => context.go('/discover'),
              icon: const Icon(Icons.radar_rounded, size: 19),
              label: const Text('Explore discovery'),
            ),
          )
        else ...[
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _run == null ? () => _check(entries) : _cancel,
                icon: Icon(
                  _run == null ? Icons.refresh_rounded : Icons.close_rounded,
                ),
                label: Text(
                  _run == null ? 'Check connections' : 'Cancel checks',
                ),
              ),
              if (_run != null)
                Semantics(
                  liveRegion: true,
                  child: Text('Checked $_checked of $_total'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          for (final entry in entries) ...[
            _RegisteredDevice(
              entry,
              presence: presenceOf(observations, entry),
              lastSeen: history?.usage[entry.registrationId]?.lastSeen,
              beforeNavigation: _cancel,
            ),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }
}

class _RegisteredDevice extends StatelessWidget {
  const _RegisteredDevice(
    this.entry, {
    required this.presence,
    required this.lastSeen,
    required this.beforeNavigation,
  });

  final DeviceRegistration entry;
  final DevicePresence presence;
  final DateTime? lastSeen;
  final VoidCallback beforeNavigation;

  @override
  Widget build(BuildContext context) {
    void openConnection() {
      beforeNavigation();
      unawaited(openDeviceConnection(context, entry));
    }

    void openSettings() {
      beforeNavigation();
      Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute(builder: (_) => DeviceSettingsScreen(device: entry)),
      );
    }

    return DeviceCard(
      name: entry.name,
      category: [
        entry.category ??
            (entry.deviceId == null
                ? 'Legacy web project'
                : 'ESP IoT v1 · ${entry.type ?? 'device'}'),
        ?entry.room,
      ].join(' · '),
      icon: deviceIcon(entry),
      presence: presence,
      connection: 'Local · ${entry.endpoint.origin}',
      lastSeen: lastSeen == null
          ? 'Address verified ${formatDeviceTime(context, entry.checkedAt)}'
          : 'Last seen ${formatDeviceTime(context, lastSeen!)}',
      onOpen: openConnection,
      onSettings: openSettings,
      quickAction: Wrap(
        spacing: 8,
        children: [
          TextButton.icon(
            onPressed: openConnection,
            icon: const Icon(Icons.sensors_rounded),
            label: Text(
              presence == DevicePresence.offline ||
                      presence == DevicePresence.problem
                  ? 'Reconnect'
                  : 'Open connection',
            ),
          ),
          if (entry.pairingHint case final hint?)
            TextButton.icon(
              onPressed: () {
                beforeNavigation();
                unawaited(showPairingQr(context, hint));
              },
              icon: const Icon(Icons.qr_code_rounded),
              label: const Text('Show pairing QR'),
            ),
        ],
      ),
    );
  }
}
