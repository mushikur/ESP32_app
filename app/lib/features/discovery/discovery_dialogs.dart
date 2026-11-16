import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/ui/app_motion.dart';
import '../../core/ui/surfaces.dart';
import 'discovery_service.dart';
import 'local_endpoint.dart';

typedef EndpointChoice = ({
  String? host,
  int port,
  bool secure,
  String? certificateSha256,
});

Future<EndpointChoice?> askForEndpoint(
  BuildContext context, {
  bool subnet = false,
  LocalEndpoint? initial,
}) {
  if (subnet) {
    return showDialog<EndpointChoice>(
      context: context,
      animationStyle: AppMotion.dialog(context),
      builder: (_) => const _EndpointForm(subnet: true),
    );
  }
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<EndpointChoice>(
      builder: (_) => _EndpointForm(subnet: false, initial: initial),
    ),
  );
}

class _EndpointForm extends StatefulWidget {
  const _EndpointForm({required this.subnet, this.initial});

  final bool subnet;
  final LocalEndpoint? initial;

  @override
  State<_EndpointForm> createState() => _EndpointFormState();
}

class _EndpointFormState extends State<_EndpointForm> {
  final _form = GlobalKey<FormState>();
  late final _address = TextEditingController(text: widget.initial?.host);
  late final _port = TextEditingController(
    text: widget.initial?.port.toString(),
  );
  late bool _secure = widget.initial?.secure ?? false;
  late final _fingerprint = TextEditingController(
    text: widget.initial?.certificateSha256,
  );
  String get _normalizedFingerprint =>
      _fingerprint.text.trim().replaceAll(':', '').toLowerCase();

  @override
  void dispose() {
    _address.dispose();
    _port.dispose();
    _fingerprint.dispose();
    super.dispose();
  }

  int get _defaultPort => _secure ? 443 : 80;

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final port = int.tryParse(_port.text.trim()) ?? _defaultPort;
    Navigator.of(context).pop((
      host: widget.subnet ? null : _address.text.trim(),
      port: port,
      secure: _secure,
      certificateSha256:
          _secure && !widget.subnet && _normalizedFingerprint.isNotEmpty
          ? _normalizedFingerprint
          : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final form = Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.subnet
                ? 'This checks up to 32 addresses near this phone on the current Wi-Fi. It reads only the public ESP IoT description on the port you choose.'
                : 'Enter the private IPv4 address of your ESP32 on this Wi-Fi.',
          ),
          const SizedBox(height: 16),
          if (!widget.subnet) ...[
            TextFormField(
              controller: _address,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'IPv4 address',
                hintText: '192.168.1.100',
              ),
              validator: (value) {
                final address = ipv4Number(value?.trim() ?? '');
                return address == null || !isPrivateIpv4(address)
                    ? 'Enter a private IPv4 address.'
                    : null;
              },
            ),
            const SizedBox(height: 8),
          ],
          TextFormField(
            controller: _port,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Port (optional)',
              hintText: '$_defaultPort',
            ),
            validator: (value) {
              final input = value?.trim() ?? '';
              if (input.isEmpty) return null;
              final port = int.tryParse(input);
              return !RegExp(r'^\d{1,5}$').hasMatch(input) ||
                      port == null ||
                      port < 1 ||
                      port > 65535
                  ? 'Enter a port from 1 to 65535.'
                  : null;
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Use HTTPS'),
            value: _secure,
            onChanged: (value) => setState(() => _secure = value),
          ),
          if (_secure && !widget.subnet)
            TextFormField(
              controller: _fingerprint,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Certificate fingerprint (optional)',
                helperText: 'For private certificates, copy the SHA-256 fingerprint from the device setup.',
                helperMaxLines: 3,
              ),
              validator: (_) =>
                  _normalizedFingerprint.isEmpty ||
                      validCertificateFingerprint(_normalizedFingerprint)
                  ? null
                  : 'Enter 64 hexadecimal digits.',
            ),
          if (!_secure)
            Text(
              'HTTP is unencrypted. Continue only on a Wi-Fi network you trust.',
              style: TextStyle(color: AppColors.violet),
            ),
        ],
      ),
    );
    final verify = FilledButton(
      onPressed: _submit,
      child: Text(widget.subnet ? 'Check subnet' : 'Verify address'),
    );
    if (!widget.subnet) {
      return AnnotatedRegion(
        value: AppTheme.overlays,
        child: Scaffold(
          appBar: AppBar(title: const Text('Enter device address')),
          body: ScreenCanvas(
            child: SafeArea(
              child: ScreenScroll(
                children: [
                  Panel(child: form),
                  const SizedBox(height: 16),
                  verify,
                ],
              ),
            ),
          ),
        ),
      );
    }
    return AlertDialog(
      title: const Text('Check nearby addresses?'),
      scrollable: true,
      content: form,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        verify,
      ],
    );
  }
}

Future<bool> confirmQrEndpoint(BuildContext context, PairingHint hint) async =>
    await showDialog<bool>(
      context: context,
      animationStyle: AppMotion.dialog(context),
      builder: (context) => AlertDialog(
        title: const Text('Verify QR address?'),
        scrollable: true,
        content: Text(
          'ESP IoT will read the public description at ${hint.endpoint.origin} and check that its device ID matches this QR code.'
          '${hint.endpoint.secure ? '' : '\n\nThis uses unencrypted HTTP. Continue only on trusted Wi-Fi.'}'
          '${hint.endpoint.certificateSha256 == null ? '' : '\n\nUse only a QR code you received from the device setup or its owner.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Verify address'),
          ),
        ],
      ),
    ) ??
    false;

Future<bool> confirmRegistration(
  BuildContext context,
  VerifiedDevice device, {
  String actionLabel = 'Register device',
}) async =>
    await showDialog<bool>(
      context: context,
      animationStyle: AppMotion.dialog(context),
      builder: (_) => _RegistrationDialog(device, actionLabel),
    ) ??
    false;

class _RegistrationDialog extends StatefulWidget {
  const _RegistrationDialog(this.device, this.actionLabel);

  final VerifiedDevice device;
  final String actionLabel;

  @override
  State<_RegistrationDialog> createState() => _RegistrationDialogState();
}

class _RegistrationDialogState extends State<_RegistrationDialog> {
  bool _acceptedHttp = false;

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final descriptor = device.descriptor;
    return AlertDialog(
      scrollable: true,
      title: Text(device.name),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectableText(device.endpoint.origin),
          const SizedBox(height: 12),
          Text(
            descriptor == null
                ? 'Web endpoint reachable. Configure a compatible API profile before controlling this device.'
                : 'ESP IoT v1 description verified · ${descriptor.capabilityCount} capabilities.',
          ),
          if (descriptor != null) ...[
            const SizedBox(height: 8),
            SelectableText('Device ID ${descriptor.id}'),
          ],
          if (descriptor?.requiresPairing == true) ...[
            const SizedBox(height: 8),
            const Text(
              'This device requires an authorization token before control.',
            ),
          ],
          if (!device.endpoint.secure) ...[
            const SizedBox(height: 12),
            Text(
              'HTTP is unencrypted. Other devices on the network can read or change this traffic.',
              style: TextStyle(color: AppColors.violet),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('I trust this Wi-Fi network'),
              value: _acceptedHttp,
              onChanged: (value) =>
                  setState(() => _acceptedHttp = value ?? false),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: device.endpoint.secure || _acceptedHttp
              ? () => Navigator.pop(context, true)
              : null,
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}
