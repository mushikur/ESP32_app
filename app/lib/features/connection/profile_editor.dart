import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_theme.dart';
import '../../core/transport/lan_transport.dart';
import '../../core/ui/surfaces.dart';
import '../devices/device_registry.dart';
import '../discovery/local_discovery_platform.dart';
import 'api_profile.dart';
import 'device_session.dart';
import 'profile_store.dart';

const _restTemplate = '''
{
  "transport": "rest",
  "statusPath": "/status",
  "pollSeconds": 10,
  "response": {"format": "json"}
}''';

const _socketTemplate = '''
{
  "transport": "websocket",
  "statusPath": "/ws",
  "pollSeconds": 10,
  "response": {"format": "json"}
}''';

const _dashboardExample = '''
{
  "transport": "rest",
  "statusPath": "/status",
  "response": {"format": "json"},
  "controls": [
    {
      "id": "led", "name": "LED", "type": "switch", "pointer": "/led",
      "on": {"method": "POST", "path": "/led", "body": {"enabled": true}, "response": {"pointer": "/ok", "equals": true}},
      "off": {"method": "POST", "path": "/led", "body": {"enabled": false}, "response": {"pointer": "/ok", "equals": true}}
    },
    {"id": "temperature", "name": "Temperature", "type": "sensor", "pointer": "/temperature", "unit": "°C"}
  ]
}''';

class ProfileEditor extends ConsumerStatefulWidget {
  const ProfileEditor({required this.device, this.saved, super.key});

  final DeviceRegistration device;
  final SavedApiProfile? saved;

  @override
  ConsumerState<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends ConsumerState<ProfileEditor> {
  late final _source = TextEditingController(
    text: widget.saved?.profile.source ?? _restTemplate,
  );
  late final _username = TextEditingController(
    text: widget.saved?.credential.username ?? '',
  );
  late final _secret = TextEditingController(
    text: widget.saved?.credential.secret ?? '',
  );
  late ApiAuth _mode = widget.saved?.credential.mode ?? ApiAuth.none;
  late final AppLifecycleListener _lifecycle;
  DiscoveryCancellation? _test;
  bool _saving = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: _cancelTest,
      onPause: _cancelTest,
    );
  }

  void _clearNotice(String _) {
    if (_notice != null) setState(() => _notice = null);
  }

  void _applyTemplate(String source) => setState(() {
    _source.text = source;
    _notice = null;
  });

  @override
  void dispose() {
    _lifecycle.dispose();
    _test?.cancel();
    _source.dispose();
    _username.dispose();
    _secret.dispose();
    super.dispose();
  }

  void _cancelTest() {
    final running = _test;
    if (running == null) return;
    running.cancel();
    setState(() {
      _test = null;
      _notice = 'Read test cancelled.';
    });
  }

  SavedApiProfile _configuration() {
    final credential = _mode == ApiAuth.none
        ? const ApiCredential.none()
        : ApiCredential(_mode, _username.text.trim(), _secret.text);
    final saved = SavedApiProfile(
      ApiProfile.parse(_source.text.trim()),
      credential,
    );
    saved.headers(widget.device.endpoint);
    return saved;
  }

  Future<void> _check() async {
    final transport = ref.read(deviceTransportProvider);
    final cancel = DiscoveryCancellation();
    setState(() {
      _test = cancel;
      _notice = 'Waiting for the configured read response…';
    });
    try {
      final reading = await testApiProfile(
        transport,
        widget.device.endpoint,
        _configuration(),
        cancel,
      );
      if (mounted && identical(_test, cancel)) {
        setState(() => _notice = 'Read test matched.\n$reading');
      }
    } on FormatException catch (error) {
      if (mounted && identical(_test, cancel)) {
        setState(() => _notice = error.message);
      }
    } on ConnectionFailure catch (error) {
      if (mounted && identical(_test, cancel)) {
        setState(() => _notice = error.message);
      }
    } on Exception {
      if (mounted && identical(_test, cancel)) {
        setState(
          () => _notice =
              'The read test could not finish. Check the profile and Wi-Fi.',
        );
      }
    } finally {
      cancel.cancel();
      if (mounted && identical(_test, cancel)) setState(() => _test = null);
    }
  }

  Future<void> _save() async {
    final store = ref.read(apiProfileStoreProvider);
    setState(() => _saving = true);
    try {
      final saved = _configuration();
      await store.save(widget.device, saved);
      if (mounted) Navigator.pop(context, saved);
    } on FormatException catch (error) {
      if (mounted) setState(() => _notice = error.message);
    } on Exception {
      if (mounted) {
        setState(
          () => _notice = 'Could not save the encrypted profile. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _test != null || _saving;
    return PopScope(
      canPop: !_saving,
      child: AnnotatedRegion(
        value: AppTheme.overlays,
        child: Scaffold(
          appBar: AppBar(title: const Text('API profile')),
          body: SafeArea(
            child: ScreenCanvas(
              child: ScreenScroll(
                children: [
                  const Eyebrow('LEGACY DEVICE INTEGRATION'),
                  const SizedBox(height: 8),
                  SectionHeading(widget.device.name),
                  const SizedBox(height: 5),
                  Text(
                    widget.device.endpoint.origin,
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Choose a template and edit it to match your firmware. Test a read-only status path before saving. Add a controls list to map dashboard tiles to this API.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => _applyTemplate(_restTemplate),
                        child: const Text('REST template'),
                      ),
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => _applyTemplate(_socketTemplate),
                        child: const Text('WebSocket template'),
                      ),
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => _applyTemplate(_dashboardExample),
                        child: const Text('Dashboard example'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Panel(
                    child: TextField(
                      controller: _source,
                      onChanged: _clearNotice,
                      enabled: !busy,
                      minLines: 7,
                      maxLines: 16,
                      autocorrect: false,
                      enableSuggestions: false,
                      keyboardType: TextInputType.multiline,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'API profile JSON',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (widget.device.endpoint.secure)
                    Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButtonFormField<ApiAuth>(
                            initialValue: _mode,
                            decoration: const InputDecoration(
                              labelText: 'Authentication',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: ApiAuth.none,
                                child: Text('None'),
                              ),
                              DropdownMenuItem(
                                value: ApiAuth.bearer,
                                child: Text('Bearer token'),
                              ),
                              DropdownMenuItem(
                                value: ApiAuth.basic,
                                child: Text('Basic authentication'),
                              ),
                              DropdownMenuItem(
                                value: ApiAuth.apiKey,
                                child: Text('X-API-Key'),
                              ),
                            ],
                            onChanged: busy
                                ? null
                                : (mode) => setState(() {
                                    _mode = mode ?? ApiAuth.none;
                                    _secret.clear();
                                    _username.clear();
                                    _notice = null;
                                  }),
                          ),
                          if (_mode == ApiAuth.basic)
                            TextField(
                              controller: _username,
                              onChanged: _clearNotice,
                              enabled: !busy,
                              autocorrect: false,
                              enableSuggestions: false,
                              decoration: const InputDecoration(
                                labelText: 'Username',
                              ),
                            ),
                          if (_mode != ApiAuth.none)
                            TextField(
                              controller: _secret,
                              onChanged: _clearNotice,
                              enabled: !busy,
                              obscureText: true,
                              autocorrect: false,
                              enableSuggestions: false,
                              decoration: const InputDecoration(
                                labelText: 'Password or token',
                              ),
                            ),
                        ],
                      ),
                    )
                  else
                    const Panel(
                      child: Text(
                        'This device uses unencrypted HTTP or WS. Keep credentials and private data out of this profile.',
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (_notice case final notice?) ...[
                    Semantics(
                      liveRegion: true,
                      child: Panel(child: SelectableText(notice)),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (_test != null)
                        OutlinedButton(
                          onPressed: _cancelTest,
                          child: const Text('Cancel read test'),
                        )
                      else
                        OutlinedButton(
                          onPressed: busy ? null : _check,
                          child: const Text('Test read'),
                        ),
                      FilledButton(
                        onPressed: busy ? null : _save,
                        child: const Text('Save API profile'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
