import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_theme.dart';
import '../../core/ui/app_motion.dart';
import '../../core/ui/surfaces.dart';
import '../devices/device_registry.dart';
import 'discovery_dialogs.dart';
import 'discovery_radar.dart';
import 'discovery_service.dart';
import 'local_discovery_platform.dart';
import 'local_endpoint.dart';
import 'pairing_qr.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  late final AppLifecycleListener _lifecycle;
  DiscoveryCancellation? _operation;
  DiscoveryReport? _report;
  String? _progress;
  String? _notice;
  bool _dialogOpen = false;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onHide: _suspend, onPause: _suspend);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _foreground) unawaited(_search());
    });
  }

  bool get _foreground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _operation?.cancel();
    super.dispose();
  }

  void _suspend() {
    if (!mounted || (_operation == null && _report == null)) return;
    _operation?.cancel();
    setState(() {
      _operation = null;
      _progress = null;
      _report = null;
      _notice = 'Search again when you return to the app.';
    });
  }

  void _stop() {
    _operation?.cancel();
    setState(() {
      _operation = null;
      _progress = null;
      _notice = 'Search stopped.';
    });
  }

  Future<T?> _run<T>(
    String label,
    Future<T> Function(DiscoveryCancellation) work, {
    bool scanning = false,
  }) async {
    _operation?.cancel();
    final operation = DiscoveryCancellation();
    setState(() {
      _operation = operation;
      _progress = label;
      _scanning = scanning;
      _notice = null;
    });
    try {
      final result = await work(operation);
      if (mounted &&
          identical(_operation, operation) &&
          !operation.isCancelled) {
        return result;
      }
    } on DiscoveryFailure catch (error) {
      if (mounted &&
          identical(_operation, operation) &&
          error.code != 'cancelled') {
        setState(() {
          if (error.code == 'networkChanged') _report = null;
          _notice = error.message;
        });
      }
    } on FormatException catch (error) {
      if (mounted && identical(_operation, operation)) {
        setState(() => _notice = error.message);
      }
    } on Exception {
      if (mounted && identical(_operation, operation)) {
        setState(
          () => _notice =
              'The operation could not finish. Check Wi-Fi and try again.',
        );
      }
    } finally {
      operation.cancel();
      if (mounted && identical(_operation, operation)) {
        setState(() {
          _operation = null;
          _progress = null;
        });
      }
    }
    return null;
  }

  Future<void> _search({EndpointChoice? subnet}) async {
    setState(() => _report = null);
    final service = ref.read(discoveryServiceProvider);
    final report = await _run(
      subnet == null
          ? 'Listening for ESP IoT devices…'
          : 'Checking nearby Wi-Fi addresses…',
      (cancel) => service.search(
        cancel,
        subnetPort: subnet?.port,
        subnetSecure: subnet?.secure ?? false,
      ),
      scanning: true,
    );
    if (mounted && report != null) {
      setState(() => _report = report);
      ref.invalidate(wifiSnapshotProvider);
    }
  }

  Future<void> _chooseAddress({bool subnet = false}) async {
    if (_dialogOpen) return;
    _operation?.cancel();
    setState(() {
      _operation = null;
      _progress = null;
      _dialogOpen = true;
    });
    final choice = await askForEndpoint(context, subnet: subnet);
    if (!mounted) return;
    setState(() => _dialogOpen = false);
    if (choice == null) return;
    if (subnet) {
      await _search(subnet: choice);
    } else {
      await _verify(
        LocalEndpoint(
          choice.host!,
          choice.port,
          secure: choice.secure,
          certificateSha256: choice.certificateSha256,
        ),
      );
    }
  }

  Future<void> _scanQr() async {
    if (_dialogOpen) return;
    _operation?.cancel();
    setState(() {
      _operation = null;
      _progress = null;
      _dialogOpen = true;
    });
    final hint = await scanPairingHint(context);
    if (!mounted) return;
    final accepted = hint != null && await confirmQrEndpoint(context, hint);
    if (!mounted) return;
    setState(() => _dialogOpen = false);
    if (accepted) await _verify(hint.endpoint, expectedId: hint.deviceId);
  }

  Future<void> _verify(LocalEndpoint endpoint, {String? expectedId}) async {
    final service = ref.read(discoveryServiceProvider);
    final device = await _run(
      'Verifying ${endpoint.origin}…',
      (cancel) => service.verify(endpoint, cancel, expectedId: expectedId),
    );
    if (mounted && device != null) await _register(device);
  }

  Future<void> _register(VerifiedDevice device) async {
    if (_dialogOpen || _operation != null) return;
    setState(() => _dialogOpen = true);
    final confirmed = await confirmRegistration(context, device);
    if (!mounted) return;
    setState(() => _dialogOpen = false);
    if (!confirmed || !_foreground) return;
    final service = ref.read(discoveryServiceProvider);
    final registry = ref.read(deviceRegistryProvider.notifier);
    final saved = await _run('Saving ${device.name}…', (cancel) async {
      await service.checkCurrent(device.scope);
      cancel.check();
      try {
        await registry.register(device);
      } on FormatException {
        rethrow;
      } on Exception {
        throw const FormatException(
          'Could not save the registration. The existing inventory was kept.',
        );
      }
      return true;
    });
    if (!mounted || saved != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            MotionPulse(
              active: true,
              child: Icon(Icons.check_circle_outline, color: AppColors.mint),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text('${device.name} added to My Devices.')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final saved =
        ref.watch(deviceRegistryProvider).value ?? const <DeviceRegistration>[];
    final report = _report;
    final progress = _progress;
    final notice = _notice;
    return ScreenScroll(
      children: [
        const Eyebrow('LOCAL CONNECTION'),
        const SizedBox(height: 8),
        Semantics(
          header: true,
          child: Text('Discover', style: text.headlineLarge),
        ),
        const SizedBox(height: 6),
        Text(
          'Find ESP IoT projects on your current Wi-Fi.',
          style: text.bodyMedium?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 18),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DiscoveryRadar(active: progress != null && _scanning),
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: MotionValue(
                  identity: progress ?? report?.scope.address,
                  child: Text(
                    progress ??
                        (report == null
                            ? 'Search your local network'
                            : 'Wi-Fi · ${report.scope.address}'),
                    style: text.titleMedium,
                  ),
                ),
              ),
              if (progress != null && AppMotion.enabled(context)) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              const SizedBox(height: 8),
              Text(
                'Search reads public device descriptions, which may use unencrypted HTTP. It stays on your private Wi-Fi link.',
                style: text.bodySmall?.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: 10),
              if (progress == null)
                FilledButton.icon(
                  onPressed: _dialogOpen ? null : () => _search(),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Search again'),
                )
              else
                TextButton(onPressed: _stop, child: const Text('Stop')),
            ],
          ),
        ),
        if (notice != null) ...[
          const SizedBox(height: 12),
          MotionReveal(
            key: ValueKey(notice),
            child: Semantics(
              liveRegion: true,
              child: Panel(child: Text(notice)),
            ),
          ),
        ],
        if (report != null) ...[
          const SizedBox(height: 20),
          const SectionHeading('Verified devices'),
          const SizedBox(height: 10),
          for (final warning in report.warnings) ...[
            Text(
              warning,
              style: text.bodySmall?.copyWith(color: AppColors.violet),
            ),
            const SizedBox(height: 8),
          ],
          if (report.devices.isEmpty)
            const EmptyPanel(
              icon: Icons.wifi_find_rounded,
              title: 'No ESP IoT devices found',
              description: 'Check that the device is powered and on the same Wi-Fi. Try its address or pairing QR if discovery traffic is blocked.',
            )
          else
            for (final (index, device) in report.devices.indexed) ...[
              MotionReveal(
                key: ValueKey(device.endpoint.origin),
                delay: Duration(milliseconds: index.clamp(0, 5) * 38),
                child: _ResultTile(
                  device,
                  saved: saved.any((entry) => entry.matches(device)),
                  onReview: _dialogOpen || progress != null
                      ? null
                      : () => _register(device),
                ),
              ),
              const SizedBox(height: 8),
            ],
        ],
        const SizedBox(height: 20),
        const SectionHeading('Other ways to connect'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _dialogOpen ? null : () => _chooseAddress(),
              icon: const Icon(Icons.lan_outlined),
              label: const Text('Manual address'),
            ),
            OutlinedButton.icon(
              onPressed: _dialogOpen ? null : _scanQr,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Scan pairing QR'),
            ),
            TextButton.icon(
              onPressed: _dialogOpen
                  ? null
                  : () => _chooseAddress(subnet: true),
              icon: const Icon(Icons.wifi_find_rounded),
              label: const Text('Check nearby addresses'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile(this.device, {required this.saved, required this.onReview});

  final VerifiedDevice device;
  final bool saved;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final descriptor = device.descriptor!;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(device.name, style: text.titleLarge),
          const SizedBox(height: 4),
          Text(
            device.endpoint.origin,
            style: text.bodyMedium?.copyWith(color: AppColors.muted),
          ),
          if (device.hostname != null)
            Text(device.hostname!, style: text.bodySmall),
          const SizedBox(height: 6),
          Text(
            'ESP IoT v1 · ${descriptor.type} · ${device.source.label}',
            style: text.bodySmall?.copyWith(color: AppColors.cyan),
          ),
          if (descriptor.requiresPairing)
            const Text('Authorization token required'),
          const SizedBox(height: 8),
          if (saved)
            Text(
              'Saved in My Devices',
              style: TextStyle(color: AppColors.mint),
            )
          else
            FilledButton.tonal(
              onPressed: onReview,
              child: const Text('Review and add'),
            ),
        ],
      ),
    );
  }
}
