import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_theme.dart';
import '../../core/protocol/device_descriptor.dart';
import '../../core/ui/surfaces.dart';
import '../connection/device_connection_screen.dart';
import '../discovery/discovery_dialogs.dart';
import '../discovery/discovery_service.dart';
import '../discovery/local_discovery_platform.dart';
import '../discovery/local_endpoint.dart';
import '../discovery/pairing_qr.dart';
import 'device_activity_screen.dart';
import 'device_card.dart';
import 'device_database.dart';
import 'device_registry.dart';

class DeviceSettingsScreen extends ConsumerStatefulWidget {
  const DeviceSettingsScreen({required this.device, super.key});
  final DeviceRegistration device;

  @override
  ConsumerState<DeviceSettingsScreen> createState() =>
      _DeviceSettingsScreenState();
}

class _DeviceSettingsScreenState extends ConsumerState<DeviceSettingsScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.device.customName);
  late final _room = TextEditingController(text: widget.device.room);
  late final _category = TextEditingController(text: widget.device.category);
  late DeviceIcon _icon = widget.device.icon;
  late final AppLifecycleListener _lifecycle;
  DiscoveryCancellation? _verification;
  bool _saving = false;
  String? _notice;
  bool get _busy => _saving || _verification != null;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onHide: () => _verification?.cancel());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _verification?.cancel();
    _name.dispose();
    _room.dispose();
    _category.dispose();
    super.dispose();
  }

  void _report(String message) {
    if (mounted) setState(() => _notice = message);
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _notice = null;
    });
    try {
      await ref
          .read(deviceRegistryProvider.notifier)
          .edit(
            widget.device.registrationId,
            name: _name.text,
            room: _room.text,
            category: _category.text,
            icon: _icon,
          );
      _report('Device details saved.');
    } on FormatException catch (error) {
      _report(error.message);
    } on Exception {
      _report('Could not save device details. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changeAddress(DeviceRegistration device) async {
    final choice = await askForEndpoint(context, initial: device.endpoint);
    if (choice == null || !mounted) return;
    await _verify(
      device,
      LocalEndpoint(
        choice.host!,
        choice.port,
        secure: choice.secure,
        certificateSha256: choice.certificateSha256,
      ),
    );
  }

  Future<void> _verify(
    DeviceRegistration device,
    LocalEndpoint endpoint,
  ) async {
    if (_busy) return;
    if (device.endpoint.secure && !endpoint.secure) {
      _report('Use HTTPS for this device.');
      return;
    }
    final cancel = DiscoveryCancellation();
    setState(() {
      _verification = cancel;
      _notice = 'Verifying the device address…';
    });
    try {
      final discovery = ref.read(discoveryServiceProvider);
      final verified = await discovery.verify(
        endpoint,
        cancel,
        expectedId: device.deviceId,
      );
      cancel.check();
      if (!mounted) return;
      device.reverified(verified);
      if ((device.endpoint != endpoint ||
              device.endpoint.certificateSha256 !=
                  endpoint.certificateSha256) &&
          !await confirmRegistration(
            context,
            verified,
            actionLabel: 'Use verified address',
          )) {
        _report('Address change cancelled.');
        return;
      }
      if (!mounted) return;
      await discovery.checkCurrent(verified.scope);
      cancel.check();
      if (!mounted) return;
      await ref
          .read(deviceRegistryProvider.notifier)
          .verifyAddress(device, verified);
      _report('Device address verified.');
    } on DiscoveryFailure catch (error) {
      _report(
        cancel.isCancelled ? 'Address verification cancelled.' : error.message,
      );
    } on FormatException catch (error) {
      _report(error.message);
    } on Exception {
      _report(
        'Could not verify the device address. Check Wi-Fi and try again.',
      );
    } finally {
      cancel.cancel();
      if (mounted) setState(() => _verification = null);
    }
  }

  Future<void> _forget(DeviceRegistration device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text('Remove ${device.name}?'),
        content: const Text(
          'This removes the registration, saved dashboard, API profile, and history from this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove device'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _busy) return;
    setState(() {
      _saving = true;
      _notice = null;
    });
    try {
      final complete = await ref
          .read(deviceRegistryProvider.notifier)
          .forget(device.registrationId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            complete ? '${device.name} removed.' : 'Device removed. Saved settings cleanup will retry the next time the app opens.',
          ),
        ),
      );
      Navigator.pop(context);
    } on Exception {
      _report('Could not remove the device. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(deviceRegistryProvider).value;
    final device =
        entries
            ?.where(
              (item) => item.registrationId == widget.device.registrationId,
            )
            .firstOrNull ??
        widget.device;
    final seen = ref
        .watch(deviceHistoryProvider)
        .value
        ?.usage[device.registrationId]
        ?.lastSeen;
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: AppColors.muted);
    TextFormField field(
      TextEditingController controller,
      String label,
      int limit, {
      String? hint,
    }) => TextFormField(
      enabled: !_busy,
      controller: controller,
      maxLength: limit,
      decoration: InputDecoration(labelText: label, hintText: hint),
      validator: (value) =>
          validLabel(value?.trim() ?? '', limit, allowEmpty: true)
          ? null
          : 'Enter a valid $label.',
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Device settings')),
      body: SafeArea(
        child: ScreenCanvas(
          child: ScreenScroll(
            children: [
              Row(
                children: [
                  IconTile(deviceIcon(device)),
                  const SizedBox(width: 12),
                  Expanded(child: SectionHeading(device.name)),
                ],
              ),
              const SizedBox(height: 16),
              if (_notice case final notice?) ...[
                Semantics(liveRegion: true, child: Panel(child: Text(notice))),
                const SizedBox(height: 12),
              ],
              Panel(
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionHeading('Device details'),
                      const SizedBox(height: 12),
                      field(_name, 'Name', 64, hint: device.advertisedName),
                      field(_room, 'Room', 32),
                      field(_category, 'Category', 32),
                      DropdownButtonFormField<DeviceIcon>(
                        initialValue: _icon,
                        decoration: const InputDecoration(labelText: 'Icon'),
                        items: [
                          for (final icon in DeviceIcon.values)
                            DropdownMenuItem(
                              value: icon,
                              child: Text(
                                '${icon.name[0].toUpperCase()}${icon.name.substring(1)}',
                              ),
                            ),
                        ],
                        onChanged: _busy
                            ? null
                            : (icon) {
                                if (icon != null) setState(() => _icon = icon);
                              },
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _busy ? null : _save,
                        child: const Text('Save details'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeading('Connection settings'),
                    const SizedBox(height: 10),
                    SelectableText(device.endpoint.origin),
                    Text(
                      device.endpoint.secure
                          ? 'HTTPS on local Wi-Fi'
                          : 'Unencrypted HTTP on local Wi-Fi',
                      style: muted,
                    ),
                    Text(
                      'Address verified ${formatDeviceTime(context, device.checkedAt)}',
                      style: muted,
                    ),
                    Text(
                      seen == null
                          ? 'No successful status check yet'
                          : 'Last seen ${formatDeviceTime(context, seen)}',
                      style: muted,
                    ),
                    if (device.hostname case final host?)
                      Text(host, style: muted),
                    if (device.deviceId case final id?) ...[
                      const SizedBox(height: 8),
                      SelectableText('Device ID $id', style: muted),
                      if (device.type case final type?)
                        Text('ESP IoT v1 · $type', style: muted),
                      if (device.requiresPairing)
                        const Text('This device requires a pairing token.'),
                    ] else ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Legacy projects use a profile tied to this address. Register a new address from Discover if it changes.',
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _verify(device, device.endpoint),
                          child: const Text('Verify saved address'),
                        ),
                        if (device.deviceId != null)
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _changeAddress(device),
                            child: const Text('Change address'),
                          ),
                        if (device.pairingHint case final hint?)
                          TextButton.icon(
                            onPressed: _busy
                                ? null
                                : () => showPairingQr(context, hint),
                            icon: const Icon(Icons.qr_code_rounded),
                            label: const Text('Show pairing QR'),
                          ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => openDeviceConnection(context, device),
                          child: Text(
                            device.deviceId == null
                                ? 'Open connection and API profile'
                                : 'Reconnect',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => openDeviceHistory(context, device),
                icon: const Icon(Icons.history),
                label: const Text('Connection history'),
              ),
              TextButton.icon(
                onPressed: _busy ? null : () => _forget(device),
                icon: const Icon(Icons.delete_outline_rounded),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                label: const Text('Remove device'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
