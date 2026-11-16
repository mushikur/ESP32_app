import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_theme.dart';
import '../../core/ui/app_motion.dart';
import '../../core/ui/surfaces.dart';
import '../connection/api_profile.dart';
import '../connection/device_session.dart';
import '../devices/device_registry.dart';
import 'dashboard_control.dart';
import 'dashboard_editor.dart';
import 'dashboard_layout.dart';

class DeviceDashboard extends ConsumerStatefulWidget {
  const DeviceDashboard({
    required this.device,
    required this.session,
    required this.profile,
    super.key,
  });

  final DeviceRegistration device;
  final DeviceSession session;
  final ApiProfile? profile;

  @override
  ConsumerState<DeviceDashboard> createState() => _DeviceDashboardState();
}

class _DeviceDashboardState extends ConsumerState<DeviceDashboard> {
  List<TilePreference>? _layout;
  bool _layoutError = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final layout = await ref
          .read(dashboardLayoutStoreProvider)
          .load(widget.device);
      if (mounted) setState(() => _layout = layout);
    } on Exception {
      if (mounted) {
        setState(() {
          _layout = const [];
          _layoutError = true;
        });
      }
    }
  }

  Future<void> _edit(
    Map<String, DashboardControl> controls,
    List<TilePreference> tiles,
  ) async {
    final store = ref.read(dashboardLayoutStoreProvider);
    final next = await Navigator.push<List<TilePreference>>(
      context,
      MaterialPageRoute(
        builder: (_) => DashboardEditor(
          controls: controls,
          tiles: tiles,
          save: (layout) => store.save(widget.device, layout),
        ),
      ),
    );
    if (mounted && next != null) {
      setState(() {
        _layout = next;
        _layoutError = false;
      });
    }
  }

  Future<void> _send(
    DashboardControl control,
    String label,
    String operation, [
    Object? value,
  ]) async {
    final session = widget.session;
    final sessionContext = session.controlContext;
    final stop = operation == 'stop';
    if (!(stop ? session.canStop : session.canControl)) return;
    if (!stop &&
        (control.confirm ||
            control.type != 'switch' ||
            session.descriptor?.capabilities.values.any(
                  (item) => item.type == 'motion',
                ) ==
                true)) {
      final description = switch (value) {
        true => 'Turn on $label?',
        false => 'Turn off $label?',
        final num number =>
          'Set $label to ${_measurement(number, control.unit)}?',
        _ => 'Run $label?',
      };
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(description),
          content: const Text(
            'Make sure the device is ready before sending this command.',
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
      if (!mounted || approved != true) return;
    }
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    if (!identical(sessionContext, session.controlContext)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The connection changed. Review the control and try again.',
          ),
        ),
      );
      return;
    }
    await session.sendControl(sessionContext, control.id, operation, value);
    final result = session.commandResult;
    if (mounted && !stop && result != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(result)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final descriptor = session.descriptor;
    final controls = descriptor != null
        ? descriptor.capabilities.map(
            (id, value) => MapEntry(id, DashboardControl.universal(value)),
          )
        : widget.profile?.controls.map(
                (id, value) => MapEntry(id, DashboardControl.legacy(value)),
              ) ??
              const <String, DashboardControl>{};
    if (descriptor == null && controls.isEmpty) return const SizedBox.shrink();
    final motion = controls.values.where((control) => control.type == 'motion');
    final editable = Map.of(controls)
      ..removeWhere((_, control) => control.type == 'motion');
    final tiles = reconcileLayout(_layout ?? const [], editable.keys);
    final visible = tiles.where((tile) => !tile.hidden);
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            children: [
              const SectionHeading('Device controls'),
              if (editable.isNotEmpty)
                TextButton.icon(
                  onPressed: _layout == null || session.commandBusy
                      ? null
                      : () => _edit(editable, tiles),
                  icon: const Icon(Icons.dashboard_customize_outlined),
                  label: const Text('Edit dashboard'),
                ),
            ],
          ),
          if (_layoutError)
            const Text(
              'Saved layout could not be read. Edit the dashboard to save a new layout.',
            ),
          if (session.phase != SessionPhase.connected &&
              session.lastSample != null)
            Text(
              'Showing the last verified readings.',
              style: TextStyle(color: AppColors.muted),
            ),
          const SizedBox(height: 10),
          for (final control in motion)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TileHeading(
                      name: control.name,
                      icon: Icons.gamepad_outlined,
                      accent: AppColors.violet,
                    ),
                    const SizedBox(height: 12),
                    MotionValue(
                      identity: session.controlValues[control.id],
                      child: Text(switch (session.controlValues[control.id]) {
                        'stopped' => 'Reported stopped',
                        final String direction => 'Reported $direction',
                        _ => 'Motion status unavailable',
                      }),
                    ),
                    Text(
                      'Movement is locked. Supported directions: ${control.directions.join(', ')}.',
                      style: TextStyle(color: AppColors.muted),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .errorContainer,
                        foregroundColor: Theme.of(context)
                            .colorScheme
                            .onErrorContainer,
                      ),
                      onPressed: session.canStop
                          ? () => _send(control, control.name, 'stop')
                          : null,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: Text('Stop ${control.name}'),
                    ),
                    if ((
                          session.stopControlId == control.id,
                          session.stopResult,
                        )
                        case (true, final result?))
                      Semantics(
                        liveRegion: true,
                        child: MotionValue(
                          identity: result,
                          child: Text(result),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (visible.isEmpty && motion.isEmpty)
            Panel(
              child: Text(
                tiles.isEmpty ? 'This device has no advertised controls.' : 'All controls are hidden. Edit the dashboard to add them back.',
              ),
            ),
          if (session.commandResult case final result?) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                result,
                style: TextStyle(color: AppColors.muted),
              ),
            ),
            const SizedBox(height: 8),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 12.0;
              final twoColumns =
                  constraints.maxWidth >= 580 &&
                  MediaQuery.textScalerOf(context).scale(16) <= 20;
              final width = twoColumns
                  ? (constraints.maxWidth - gap) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final tile in visible)
                    SizedBox(
                      key: ValueKey(tile.id),
                      width: width,
                      child: _ControlTile(
                        control: controls[tile.id]!,
                        tile: tile,
                        session: session,
                        send: (operation, value) => _send(
                          controls[tile.id]!,
                          tile.name ?? controls[tile.id]!.name,
                          operation,
                          value,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

String _measurement(num value, String unit) {
  final display = value is int || value == value.roundToDouble()
      ? value.toString().replaceFirst(RegExp(r'\.0$'), '')
      : double.parse(value.toStringAsPrecision(8)).toString();
  return unit.isEmpty ? display : '$display $unit';
}

class _TileHeading extends StatelessWidget {
  const _TileHeading({
    required this.name,
    required this.icon,
    required this.accent,
  });
  final String name;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconTile(icon, color: accent, size: 40),
      const SizedBox(width: 12),
      Expanded(
        child: Text(name, style: Theme.of(context).textTheme.titleMedium),
      ),
    ],
  );
}

class _ControlTile extends StatelessWidget {
  const _ControlTile({
    required this.control,
    required this.tile,
    required this.session,
    required this.send,
  });
  final DashboardControl control;
  final TilePreference tile;
  final DeviceSession session;
  final Future<void> Function(String, Object?) send;

  @override
  Widget build(BuildContext context) {
    final label = tile.name ?? control.name;
    final accent = tileColor(tile.color);
    final value = session.controlValues[control.id];
    final enabled = session.canControl;
    final Widget body = switch (control.type) {
      'switch' when value is bool => Row(
        children: [
          Expanded(child: Text(value ? 'On' : 'Off')),
          Semantics(
            label: label,
            child: Switch(
              value: value,
              activeThumbColor: accent,
              onChanged: enabled ? (next) => send('set', next) : null,
            ),
          ),
        ],
      ),
      'switch' => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('State unavailable'),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: enabled ? () => send('set', true) : null,
                child: const Text('Turn on'),
              ),
              OutlinedButton(
                onPressed: enabled ? () => send('set', false) : null,
                child: const Text('Turn off'),
              ),
            ],
          ),
        ],
      ),
      'range' => _RangeControl(
        key: ObjectKey(session.controlContext),
        control: control,
        label: label,
        accent: accent,
        value: value as num?,
        enabled: enabled,
        apply: (next) => send('set', next),
      ),
      'sensor' => _SensorReading(
        value: value as num?,
        unit: control.unit,
        accent: accent,
        samples: session.history(control.id),
      ),
      'action' => Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonal(
          onPressed: enabled ? () => send('invoke', null) : null,
          child: Text('Run $label'),
        ),
      ),
      _ => Text(
        'This capability type is unsupported.',
        style: TextStyle(color: AppColors.muted),
      ),
    };
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TileHeading(
            name: label,
            icon: tileIcon(tile.icon, control.type),
            accent: accent,
          ),
          const SizedBox(height: 12),
          body,
        ],
      ),
    );
  }
}

class _RangeControl extends StatefulWidget {
  const _RangeControl({
    required this.control,
    required this.label,
    required this.accent,
    required this.value,
    required this.enabled,
    required this.apply,
    super.key,
  });
  final DashboardControl control;
  final String label;
  final Color accent;
  final num? value;
  final bool enabled;
  final Future<void> Function(num) apply;

  @override
  State<_RangeControl> createState() => _RangeControlState();
}

class _RangeControlState extends State<_RangeControl> {
  int? _draft;

  @override
  Widget build(BuildContext context) {
    final control = widget.control;
    final min = control.min!;
    final max = control.max!;
    final step = control.step!;
    final steps = ((max.toDouble() - min.toDouble()) / step).round();
    final reported = widget.value;
    final current = reported == null
        ? 0
        : ((reported.toDouble() - min.toDouble()) / step).round().clamp(
            0,
            steps,
          );
    final selection = _draft ?? current;
    num at(int index) {
      if (index == 0) return min;
      if (index == steps) return max;
      final value = (min.toDouble() + step.toDouble() * index).clamp(min, max);
      if (min is int && step is int && value.abs() <= 9007199254740991) {
        return value.round();
      }
      return value;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          reported == null
              ? 'Value unavailable'
              : 'Reported ${_measurement(reported, control.unit)}',
        ),
        Slider(
          value: selection.toDouble(),
          max: steps.toDouble(),
          divisions: steps,
          activeColor: widget.accent,
          label: _measurement(at(selection), control.unit),
          semanticFormatterCallback: (value) =>
              '${widget.label}, ${_measurement(at(value.round()), control.unit)}',
          onChanged: widget.enabled
              ? (value) => setState(() => _draft = value.round())
              : null,
        ),
        if (_draft case final index?)
          Text(
            'Selected ${_measurement(at(index), control.unit)}',
            style: TextStyle(color: AppColors.muted),
          ),
        OutlinedButton(
          onPressed: widget.enabled && _draft != null
              ? () async {
                  await widget.apply(at(selection));
                  if (mounted) setState(() => _draft = null);
                }
              : null,
          child: const Text('Apply value'),
        ),
      ],
    );
  }
}

typedef _Sample = ({DateTime time, num value});

class _SensorReading extends StatelessWidget {
  const _SensorReading({
    required this.value,
    required this.unit,
    required this.accent,
    required this.samples,
  });
  final num? value;
  final String unit;
  final Color accent;
  final List<_Sample> samples;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MotionValue(
        identity: (value, unit),
        child: Text(
          value == null ? 'Reading unavailable' : _measurement(value!, unit),
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(color: accent),
        ),
      ),
      if (samples.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(
          'Last reading ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(samples.last.time))}',
          style: TextStyle(color: AppColors.muted),
        ),
      ],
      if (samples.length >= 2) ...[
        const SizedBox(height: 12),
        Semantics(
          label:
              'Sensor trend, ${samples.length} samples, first ${_measurement(samples.first.value, unit)}, latest ${_measurement(samples.last.value, unit)}',
          child: SizedBox(
            height: 54,
            width: double.infinity,
            child: TweenAnimationBuilder<double>(
              key: ValueKey(samples.last),
              tween: Tween(begin: .86, end: 1),
              duration: AppMotion.duration(context, AppMotion.standard),
              curve: AppMotion.ease,
              builder: (context, fraction, child) =>
                  ClipRect(clipper: _TrendReveal(fraction), child: child),
              child: RepaintBoundary(
                child: CustomPaint(painter: _SensorTrend(samples, accent)),
              ),
            ),
          ),
        ),
      ],
    ],
  );
}

class _TrendReveal extends CustomClipper<Rect> {
  const _TrendReveal(this.fraction);

  final double fraction;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_TrendReveal oldClipper) => oldClipper.fraction != fraction;
}

class _SensorTrend extends CustomPainter {
  const _SensorTrend(this.samples, this.accent);
  final List<_Sample> samples;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final values = samples.map((sample) => sample.value.toDouble()).toList();
    final scale = values.map((value) => value.abs()).fold<double>(1, math.max);
    final normalized = values.map((value) => value / scale).toList();
    final bottom = normalized.reduce(math.min);
    final top = normalized.reduce(math.max);
    final path = Path();
    final first = samples.first.time;
    final duration = samples.last.time.difference(first).inMilliseconds;
    for (final (index, value) in normalized.indexed) {
      final elapsed = samples[index].time.difference(first).inMilliseconds;
      final fraction = duration <= 0
          ? index / (samples.length - 1)
          : (elapsed / duration).clamp(0.0, 1.0);
      final level = top == bottom ? .5 : (top - value) / (top - bottom);
      final x = 2 + fraction * (size.width - 4);
      final y = 2 + level * (size.height - 4);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      Paint()..color = AppColors.line,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = accent
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_SensorTrend oldDelegate) =>
      accent != oldDelegate.accent || !listEquals(samples, oldDelegate.samples);
}
