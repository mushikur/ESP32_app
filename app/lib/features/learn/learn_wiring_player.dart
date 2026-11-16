import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/ui/app_motion.dart';
import '../../core/ui/status_visuals.dart';
import '../../core/ui/surfaces.dart';
import 'learn_catalog.dart';
import 'learn_wiring_diagram.dart';

/// Draws a project's wiring one connection at a time, then briefly traces
/// the completed drawing.
///
/// Every position comes from the project's validated circuit data, so the
/// animation can only show connections the lesson actually defines.
class LearnWiringPlayer extends StatefulWidget {
  const LearnWiringPlayer({
    required this.catalog,
    required this.project,
    required this.language,
    this.onStep,
    super.key,
  });

  final LearnCatalog catalog;
  final LearnProject project;
  final LearnLanguage language;

  /// Called with the wire index as playback reaches it, so the surrounding
  /// lesson can follow along.
  final ValueChanged<int>? onStep;

  @override
  State<LearnWiringPlayer> createState() => _LearnWiringPlayerState();
}

/// One wire is drawn over this long, then the next begins.
const _perWire = Duration(milliseconds: 1500);
const _traceDuration = Duration(milliseconds: 1600);

class _LearnWiringPlayerState extends State<LearnWiringPlayer>
    with TickerProviderStateMixin {
  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: _perWire * widget.project.wires.length,
  )..addStatusListener(_onDrawDone);
  late final AnimationController _completionTrace = AnimationController(
    vsync: this,
    duration: _traceDuration,
  );
  int _announced = -1;

  int get _count => widget.project.wires.length;

  /// Index of the wire being drawn, and how far through it playback is.
  ///
  /// A value that lands exactly on a boundary belongs to the wire that just
  /// finished, so stepping shows a completed connection rather than the next
  /// empty one.
  (int, double) get _position {
    final exact = _draw.value * _count;
    // Stepping sets the controller to a fraction that multiplies back to a
    // whole number only approximately, so a boundary needs a tolerance.
    final index = ((exact - 1e-6).ceil() - 1).clamp(0, _count - 1);
    return (index, (exact - index).clamp(0.0, 1.0));
  }

  bool get _complete => _draw.isCompleted;

  @override
  void initState() {
    super.initState();
    _draw.addListener(_report);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _draw.stop();
      _completionTrace.reset();
    }
  }

  @override
  void dispose() {
    _draw.dispose();
    _completionTrace.dispose();
    super.dispose();
  }

  void _report() {
    final (index, _) = _position;
    if (index != _announced) {
      _announced = index;
      widget.onStep?.call(index);
    }
  }

  void _onDrawDone(AnimationStatus status) {
    if (!mounted) return;
    if (status == AnimationStatus.completed) {
      if (AppMotion.enabled(context)) _completionTrace.forward(from: 0);
    } else {
      _completionTrace.reset();
    }
    setState(() {});
  }

  void _toggle() {
    setState(() {
      if (_draw.isAnimating) {
        _draw.stop();
      } else {
        _draw.forward();
      }
    });
  }

  void _replay() {
    setState(() {
      _announced = -1;
      _draw.value = 0;
      if (AppMotion.enabled(context)) {
        _draw.forward();
      }
    });
  }

  /// Moves whole connections at a time, for the step buttons.
  void _jump(int delta) {
    _draw.stop();
    final (index, _) = _position;
    final current = index + delta;
    setState(() {
      _draw.value = ((current + 1) / _count).clamp(0.0, 1.0);
    });
    _report();
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final wires = widget.project.wires;
    final text = Theme.of(context).textTheme;

    return Panel(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      // One builder drives the diagram, caption and progress together, so the
      // text can never lag behind the drawing.
      child: AnimatedBuilder(
        animation: Listenable.merge([_draw, _completionTrace]),
        builder: (context, _) {
          final (index, progress) = _position;
          final active = wires[index];
          final playing = _draw.isAnimating;
          // With reduced motion the player becomes a stepper.
          final stepping = !AppMotion.enabled(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      language.pick('Watch it being wired', 'তার লাগানো দেখুন'),
                      style: text.titleMedium,
                    ),
                  ),
                  if (_complete)
                    StatusChip(
                      tone: StatusTone.live,
                      label: language.pick(
                        'Circuit complete',
                        'সার্কিট সম্পূর্ণ',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _complete
                    ? language.pick(
                        'All lesson connections are shown. Inspect the terminals in the wiring lab below.',
                        'পাঠের সব সংযোগ দেখানো হয়েছে। নিচের সংযোগ ল্যাবে প্রান্তগুলো দেখুন।',
                      )
                    : stepping
                    ? language.pick(
                        'Step through the connections in the order you should build them.',
                        'যে ক্রমে বানাবেন সেই ক্রমে সংযোগগুলো দেখুন।',
                      )
                    : language.pick(
                        'Each connection is drawn in the order you should build it.',
                        'যে ক্রমে বানাবেন সেই ক্রমে প্রতিটি সংযোগ আঁকা হচ্ছে।',
                      ),
                style: text.bodySmall?.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: 10),
              LearnWiringDiagram(
                project: widget.project,
                language: language,
                activeWire: active.id,
                traceOverride: _complete || stepping ? 1 : progress,
                visibleWires: {for (var i = 0; i <= index; i++) wires[i].id},
                pathPulse:
                    _complete && !stepping && _completionTrace.isAnimating
                    ? _completionTrace.value
                    : 0,
                viewerKey: const ValueKey('wiring-playback'),
                showZoomControls: false,
                onPart: (_, _) {},
                inspected: null,
                inspectedPart: null,
              ),
              const SizedBox(height: 6),
              Semantics(
                liveRegion: true,
                child: Text(
                  _caption(index, active, language),
                  style: text.titleSmall?.copyWith(
                    color: learnWireColor(active.color),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(language.text(active.why), style: text.bodySmall),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: _complete
                    ? 1
                    : (index + (stepping ? 1 : progress)) / _count,
                minHeight: 5,
                borderRadius: BorderRadius.circular(4),
                backgroundColor: AppColors.tint(AppColors.cyan, .10),
                semanticsLabel: language.pick(
                  'Wiring progress',
                  'সংযোগের অগ্রগতি',
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  IconButton(
                    tooltip: language.pick('Previous connection', 'আগের সংযোগ'),
                    onPressed: index > 0 ? () => _jump(-1) : null,
                    icon: const Icon(Icons.skip_previous_rounded),
                  ),
                  if (!stepping && !_complete)
                    IconButton.filled(
                      tooltip: playing
                          ? language.pick('Pause', 'থামান')
                          : language.pick('Play', 'চালান'),
                      onPressed: _toggle,
                      icon: Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                  IconButton(
                    tooltip: language.pick('Next connection', 'পরের সংযোগ'),
                    onPressed: _complete ? null : () => _jump(1),
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _replay,
                    icon: const Icon(Icons.restart_alt_rounded, size: 18),
                    label: Text(language.pick('Replay', 'আবার দেখুন')),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  String _caption(int index, LearnWire active, LearnLanguage language) {
    final from = widget.catalog.terminalLabel(
      widget.project,
      active.from,
      language,
    );
    final to = widget.catalog.terminalLabel(
      widget.project,
      active.to,
      language,
    );
    return language.pick(
      'Connection ${index + 1} of $_count · $from → $to',
      '$_count টির মধ্যে সংযোগ ${index + 1} · $from → $to',
    );
  }
}
