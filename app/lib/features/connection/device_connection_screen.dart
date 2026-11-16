import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_theme.dart';
import '../../core/transport/lan_transport.dart';
import '../../core/ui/app_motion.dart';
import '../../core/ui/status_visuals.dart';
import '../../core/ui/surfaces.dart';
import '../dashboard/device_dashboard.dart';
import '../devices/device_connections.dart';
import '../devices/device_database.dart';
import '../devices/device_registration.dart';
import '../discovery/local_discovery_platform.dart';
import 'device_session.dart';
import 'lan_universal_connector.dart';
import 'profile_editor.dart';
import 'profile_store.dart';
import 'secure_pairing.dart';

class DeviceConnectionScreen extends ConsumerStatefulWidget {
  const DeviceConnectionScreen({required this.device, super.key});

  final DeviceRegistration device;

  @override
  ConsumerState<DeviceConnectionScreen> createState() =>
      _DeviceConnectionScreenState();
}

Future<void> openDeviceConnection(
  BuildContext context,
  DeviceRegistration device,
) => Navigator.of(context, rootNavigator: true).push<void>(
  MaterialPageRoute(builder: (_) => DeviceConnectionScreen(device: device)),
);

class _DeviceConnectionScreenState
    extends ConsumerState<DeviceConnectionScreen> {
  late final DeviceSession _session;
  late final DeviceConnections _connections;
  late final AppLifecycleListener _lifecycle;
  SavedApiProfile? _profile;
  DeviceCredential? _pairing;
  DiscoveryCancellation? _pairingOperation;
  String? _pairingNotice;
  bool _loading = true;
  bool _editing = false;
  String? _storageError;
  DateTime? _lastObserved;
  DateTime? _lastSavedContact;
  SessionPhase _lastPhase = SessionPhase.idle;

  bool get _legacy => widget.device.deviceId == null;
  bool get _canPair => !_legacy && widget.device.endpoint.secure;
  bool get _foreground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  @override
  void initState() {
    super.initState();
    _connections = ref.read(deviceConnectionsProvider.notifier);
    _session = DeviceSession(
      onCommand: (outcome) {
        unawaited(
          _connections.record(
            widget.device,
            kind: switch (outcome) {
              CommandOutcome.applied => ActivityKind.applied,
              CommandOutcome.rejected => ActivityKind.rejected,
              CommandOutcome.unconfirmed => ActivityKind.unconfirmed,
            },
          ),
        );
      },
    )..addListener(_observe);
    _lifecycle = AppLifecycleListener(
      onHide: () {
        _pairingOperation?.cancel();
        _session.pause();
      },
      onPause: _session.pause,
      onResume: _resume,
    );
    unawaited(
      Future<void>.microtask(() async {
        if (!mounted) return;
        unawaited(_connections.record(widget.device, opened: true));
        await _load();
      }),
    );
  }

  void _observe() {
    final phase = _session.phase;
    final changed = phase != _lastPhase;
    final contact = _session.lastContact;
    if (changed || contact != _lastObserved) {
      _connections.observe(widget.device, presenceForPhase(phase));
    }
    if (changed) {
      final kind =
          phase == SessionPhase.reconnecting &&
              _lastPhase == SessionPhase.connected
          ? ActivityKind.disconnected
          : activityForPhase(phase);
      if (kind != null) {
        final seen = phase == SessionPhase.connected ? contact : null;
        if (seen != null) _lastSavedContact = seen;
        unawaited(_connections.record(widget.device, kind: kind, seen: seen));
      }
    }
    _lastPhase = phase;
    _lastObserved = contact;
    if (phase == SessionPhase.paused ||
        (contact != null &&
            _lastSavedContact != null &&
            contact.difference(_lastSavedContact!) >=
                DeviceConnections.freshness)) {
      _saveContact();
    }
  }

  void _saveContact() {
    final seen = _session.lastContact;
    if (seen == null || seen == _lastSavedContact) return;
    _lastSavedContact = seen;
    unawaited(_connections.record(widget.device, seen: seen));
  }

  Future<void> _load() async {
    try {
      if (_legacy) {
        final profile = await ref
            .read(apiProfileStoreProvider)
            .load(widget.device);
        if (!mounted) return;
        _profile = profile;
      } else if (_canPair) {
        final pairing = await ref
            .read(pairingStoreProvider)
            .load(widget.device);
        if (!mounted) return;
        _pairing = pairing;
      }
    } on Exception {
      if (!mounted) return;
      _storageError = _legacy
          ? 'Could not read the encrypted profile. Save a new profile to reconnect.'
          : 'Could not read the encrypted pairing. Pair again to reconnect.';
    }
    if (!mounted) return;
    setState(() => _loading = false);
    if (_foreground && _storageError == null) _start();
  }

  void _start() {
    final transport = ref.read(deviceTransportProvider);
    final device = widget.device;
    if (_legacy) {
      _session.startLegacy(transport, device.endpoint, _profile);
    } else {
      _session.startUniversal(
        LanUniversalConnector(transport, device, pairing: _pairing),
      );
    }
  }

  void _resume() {
    if (!_loading &&
        !_editing &&
        _pairingOperation == null &&
        _storageError == null &&
        (_session.phase == SessionPhase.paused ||
            _session.phase == SessionPhase.idle)) {
      _start();
    }
  }

  Future<void> _edit() async {
    _editing = true;
    _session.pause();
    final saved = await Navigator.of(context).push<SavedApiProfile>(
      MaterialPageRoute(
        builder: (_) => ProfileEditor(device: widget.device, saved: _profile),
      ),
    );
    if (!mounted) return;
    setState(() {
      _editing = false;
      if (saved != null) {
        _profile = saved;
        _storageError = null;
      }
    });
    if (_foreground && _storageError == null) _start();
  }

  Future<void> _askPairingCode() async {
    var code = '';
    final selected = await showDialog<String>(
      context: context,
      animationStyle: AppMotion.dialog(context),
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          scrollable: true,
          title: const Text('Pair securely'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Open pairing on the ESP32 and enter the eight-digit code it shows.',
              ),
              const SizedBox(height: 12),
              TextField(
                keyboardType: TextInputType.number,
                maxLength: 8,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                enableInteractiveSelection: false,
                onChanged: (value) => refresh(() => code = value),
                decoration: const InputDecoration(labelText: 'One-time code'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: validPairingCode(code)
                  ? () => Navigator.pop(context, code)
                  : null,
              child: const Text('Pair device'),
            ),
          ],
        ),
      ),
    );
    if (mounted && selected != null) await _changePairing(code: selected);
  }

  Future<void> _askRevoke() async {
    final approved = await showDialog<bool>(
      context: context,
      animationStyle: AppMotion.dialog(context),
      builder: (context) => AlertDialog(
        title: const Text('Remove secure pairing?'),
        content: const Text(
          'The ESP32 will revoke this phone’s token. You can pair again using a new code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove pairing'),
          ),
        ],
      ),
    );
    if (mounted && approved == true) await _changePairing();
  }

  Future<void> _changePairing({String? code}) async {
    if (!_foreground || _pairingOperation != null || _session.commandBusy) {
      return;
    }
    final cancel = DiscoveryCancellation();
    final service = SecurePairing(ref.read(deviceTransportProvider));
    final store = ref.read(pairingStoreProvider);
    final device = widget.device;
    setState(() {
      _pairingOperation = cancel;
      _pairingNotice = null;
    });
    _session.pause();
    try {
      if (code != null) {
        final issued = await service.enroll(device, code, cancel);
        try {
          await store.save(device, issued);
        } on Exception {
          if (!cancel.isCancelled) {
            try {
              await service.revoke(device, issued, cancel);
            } on Exception {
              /* The device can clear its slots locally. */
            }
          }
          throw const FormatException(
            'Could not save the encrypted token. Open a new pairing window and try again.',
          );
        }
        _pairing = issued;
        _storageError = null;
        _pairingNotice = 'Secure pairing saved.';
      } else if (_pairing case final credential?) {
        await service.revoke(device, credential, cancel);
        _pairing = null;
        _pairingNotice = 'The device removed this phone’s pairing.';
        await store.delete(device);
      }
    } on ConnectionFailure catch (error) {
      _pairingNotice =
          code != null &&
              error.problem == ConnectionProblem.authentication &&
              error.detail == null
          ? 'The code was rejected or the pairing window closed. Open a fresh window on the device.'
          : error.message;
    } on Exception {
      _pairingNotice =
          'Pairing could not finish. Check the device and try again.';
    } finally {
      cancel.cancel();
      if (mounted) {
        setState(() => _pairingOperation = null);
        if (_foreground && _storageError == null) _start();
      }
    }
  }

  Future<void> _confirmCommand() async {
    final sessionContext = _session.controlContext;
    final approved = await showDialog<bool>(
      context: context,
      animationStyle: AppMotion.dialog(context),
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Send the test command?'),
        content: const Text(
          'This sends the configured command to your actual device once. Use a safe test action and confirm the device is ready. If the result is unclear, inspect the device before sending it again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send once'),
          ),
        ],
      ),
    );
    if (!mounted || approved != true || !_foreground) return;
    if (!identical(sessionContext, _session.controlContext)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The connection changed. Review the command and try again.',
          ),
        ),
      );
      return;
    }
    await _session.sendTestCommand(sessionContext);
  }

  @override
  void dispose() {
    _pairingOperation?.cancel();
    _lifecycle.dispose();
    _session.removeListener(_observe);
    _saveContact();
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _pairingOperation == null,
      child: AnnotatedRegion(
        value: AppTheme.overlays,
        child: Scaffold(
          appBar: AppBar(title: const Text('Device connection')),
          body: SafeArea(
            child: ScreenCanvas(
              child: ListenableBuilder(
                listenable: _session,
                builder: (context, _) {
                  final phase = _session.phase;
                  final localizations = MaterialLocalizations.of(context);
                  String format(DateTime time) =>
                      '${localizations.formatCompactDate(time)} ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(time))}';
                  return ScreenScroll(
                    children: [
                      SectionHeading(widget.device.name),
                      const SizedBox(height: 6),
                      Text(
                        widget.device.endpoint.origin,
                        style: TextStyle(color: AppColors.muted),
                      ),
                      const SizedBox(height: 16),
                      Panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ConnectionBeacon(
                                  tone: _loading
                                      ? StatusTone.waiting
                                      : phase.tone,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Semantics(
                                        liveRegion: true,
                                        child: MotionValue(
                                          identity: (_loading, phase),
                                          child: Text(
                                            _loading
                                                ? 'Loading connection settings…'
                                                : phase.label,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge
                                                ?.copyWith(
                                                  color: _loading
                                                      ? null
                                                      : phase.tone.color,
                                                ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _storageError ??
                                            _session.detail ??
                                            'Waiting to check the device.',
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (_session.lastContact case final contact?) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Last valid contact ${format(contact)}',
                                style: TextStyle(color: AppColors.muted),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (!_loading &&
                                    _storageError == null &&
                                    (!_legacy || _profile != null))
                                  OutlinedButton(
                                    onPressed:
                                        phase == SessionPhase.checking ||
                                            _session.commandBusy ||
                                            _pairingOperation != null
                                        ? null
                                        : _start,
                                    child: const Text('Check now'),
                                  ),
                                if (_legacy && !_loading)
                                  FilledButton(
                                    onPressed: _session.commandBusy
                                        ? null
                                        : _edit,
                                    child: Text(
                                      _profile == null
                                          ? 'Set API profile'
                                          : 'Edit API profile',
                                    ),
                                  ),
                                if (_canPair &&
                                    !_loading &&
                                    (phase == SessionPhase.authorization ||
                                        (widget.device.requiresPairing &&
                                            _pairing == null)))
                                  FilledButton(
                                    onPressed: _pairingOperation == null
                                        ? _askPairingCode
                                        : null,
                                    child: const Text('Pair securely'),
                                  ),
                                if (_pairing != null && !_loading)
                                  TextButton(
                                    onPressed:
                                        _pairingOperation == null &&
                                            !_session.commandBusy
                                        ? _askRevoke
                                        : null,
                                    child: const Text('Remove pairing'),
                                  ),
                              ],
                            ),
                            if (_pairingOperation != null ||
                                _pairingNotice != null)
                              Semantics(
                                liveRegion: true,
                                child: MotionValue(
                                  identity: (
                                    _pairingOperation != null,
                                    _pairingNotice,
                                  ),
                                  child: Text(
                                    _pairingOperation != null
                                        ? 'Verifying secure pairing…'
                                        : _pairingNotice!,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      DeviceDashboard(
                        device: widget.device,
                        session: _session,
                        profile: _profile?.profile,
                      ),
                      if (_session.sample case final sample?) ...[
                        const SizedBox(height: 16),
                        Panel(
                          padding: EdgeInsets.zero,
                          child: ExpansionTile(
                            title: const Text('Last status sample'),
                            childrenPadding: const EdgeInsets.fromLTRB(
                              18,
                              0,
                              18,
                              18,
                            ),
                            expandedCrossAxisAlignment:
                                CrossAxisAlignment.stretch,
                            children: [
                              if (_session.lastSample case final time?)
                                Text(
                                  'Read at ${format(time)}',
                                  style: TextStyle(color: AppColors.muted),
                                ),
                              const SizedBox(height: 8),
                              SelectableText(
                                sample,
                                style: const TextStyle(fontFamily: 'monospace'),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_profile?.profile.action != null) ...[
                        const SizedBox(height: 16),
                        const SectionHeading('Test command'),
                        const SizedBox(height: 8),
                        Panel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Send the optional action configured in your profile.',
                              ),
                              const SizedBox(height: 8),
                              FilledButton.tonal(
                                onPressed: _session.canTestCommand
                                    ? _confirmCommand
                                    : null,
                                child: const Text('Review test command'),
                              ),
                              if (_session.commandResult
                                  case final outcome?) ...[
                                const SizedBox(height: 8),
                                Semantics(
                                  liveRegion: true,
                                  child: Text(outcome),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
