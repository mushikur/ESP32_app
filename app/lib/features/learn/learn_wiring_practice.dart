import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/ui/app_motion.dart';
import '../../core/ui/surfaces.dart';
import 'learn_catalog.dart';
import 'learn_widgets.dart';
import 'learn_wiring_diagram.dart';

enum _PracticeFeedback { correct, source, sameNet, incorrect, saveFailed }

class LearnWiringPractice extends StatefulWidget {
  const LearnWiringPractice({
    required this.catalog,
    required this.project,
    required this.language,
    required this.matched,
    required this.onMatch,
    required this.onReset,
    required this.onReturn,
    super.key,
  });

  final LearnCatalog catalog;
  final LearnProject project;
  final LearnLanguage language;
  final Set<String> matched;
  final Future<void> Function(String wireId) onMatch;
  final Future<void> Function() onReset;
  final VoidCallback onReturn;

  @override
  State<LearnWiringPractice> createState() => _LearnWiringPracticeState();
}

class _LearnWiringPracticeState extends State<LearnWiringPractice> {
  final _prompt = GlobalKey();
  final _notice = GlobalKey();
  late LearnWire? _wire;
  _PracticeFeedback? _feedback;
  bool _hint = false;
  bool _reveal = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _wire = widget.project.wires
        .where((wire) => !widget.matched.contains(wire.id))
        .firstOrNull;
  }

  void _advance() {
    final current = _wire;
    setState(() {
      _wire = widget.project.wires
          .where(
            (wire) =>
                wire.id != current?.id && !widget.matched.contains(wire.id),
          )
          .firstOrNull;
      _feedback = null;
      _hint = _reveal = false;
    });
    revealLearnContent(_prompt);
  }

  Future<void> _tryTerminal(LearnTerminal terminal) async {
    final wire = _wire;
    if (wire == null || _saving || _feedback == _PracticeFeedback.correct) {
      return;
    }
    if (terminal != wire.to) {
      setState(() {
        _feedback = switch (terminal) {
          _ when terminal == wire.from => _PracticeFeedback.source,
          _ when widget.project.circuit.sharesNet(wire.from, terminal) =>
            _PracticeFeedback.sameNet,
          _ => _PracticeFeedback.incorrect,
        };
      });
      revealLearnContent(_prompt);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onMatch(wire.id);
      if (mounted) setState(() => _feedback = _PracticeFeedback.correct);
    } on Exception {
      if (mounted) setState(() => _feedback = _PracticeFeedback.saveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (mounted) revealLearnContent(_notice);
  }

  Future<void> _reset() async {
    setState(() => _saving = true);
    try {
      await widget.onReset();
      if (!mounted) return;
      setState(() {
        _wire = widget.project.wires.first;
        _feedback = null;
        _hint = _reveal = false;
      });
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.language.pick(
                'Could not restart practice. Try again.',
                'অনুশীলন আবার শুরু করা যায়নি। আবার চেষ্টা করুন।',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _chooseTerminal({String? part}) async {
    final wire = _wire;
    if (wire == null || _saving || _feedback == _PracticeFeedback.correct) {
      return;
    }
    final candidates = <LearnTerminal>[
      for (final node in widget.project.circuit.nodes.entries)
        if (part == null || node.key == part)
          for (final pin in node.value.terminals.keys)
            if ((part: node.key, pin: pin) != wire.from)
              (part: node.key, pin: pin),
    ];
    if (candidates.isEmpty) return;
    final selected = await showDialog<LearnTerminal>(
      context: context,
      animationStyle: AppMotion.dialog(context),
      builder: (context) => AlertDialog(
        title: Text(
          widget.language.pick('Choose a terminal', 'একটি টার্মিনাল বাছুন'),
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final terminal in candidates)
                  ListTile(
                    key: ValueKey(
                      'practice-terminal-${terminal.part}.${terminal.pin}',
                    ),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.circle_outlined, size: 18),
                    title: Text(_label(terminal)),
                    onTap: () => Navigator.of(context).pop(terminal),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(widget.language.pick('Cancel', 'বাতিল')),
          ),
        ],
      ),
    );
    if (mounted && selected != null) await _tryTerminal(selected);
  }

  String _label(LearnTerminal terminal) =>
      widget.catalog.terminalLabel(widget.project, terminal, widget.language);

  String _feedbackText(LearnWire wire, _PracticeFeedback feedback) {
    final language = widget.language;
    return switch (feedback) {
      _PracticeFeedback.correct => language.pick(
        'Correct connection. ${language.text(wire.why)}',
        'সঠিক সংযোগ। ${language.text(wire.why)}',
      ),
      _PracticeFeedback.source => language.pick(
        'This is the starting terminal. Choose the other end of the wire.',
        'এটি শুরুর টার্মিনাল। তারের অন্য প্রান্ত বাছুন।',
      ),
      _PracticeFeedback.sameNet => language.pick(
        'That terminal shares the same electrical net. Find the specific connection for this step.',
        'টার্মিনালটি একই বৈদ্যুতিক সংযোগে আছে। এই ধাপের নির্দিষ্ট প্রান্তটি খুঁজুন।',
      ),
      _PracticeFeedback.incorrect => language.pick(
        'Try again. That terminal is outside this connection.',
        'আবার চেষ্টা করুন। টার্মিনালটি এই সংযোগের বাইরে।',
      ),
      _PracticeFeedback.saveFailed => language.pick(
        'Could not save this practice step. Try again.',
        'অনুশীলনের এই ধাপটি সেভ করা যায়নি। আবার চেষ্টা করুন।',
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final wire = _wire;
    final language = widget.language;
    final text = Theme.of(context).textTheme;
    final correct = _feedback == _PracticeFeedback.correct;
    final visible = {...widget.matched, if (wire != null && correct) wire.id};
    final total = widget.project.wires.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          key: _prompt,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MotionValue(
                identity: visible.length,
                child: Text(
                  language.pick(
                    '${visible.length} of $total connections matched',
                    '$totalটির মধ্যে ${visible.length}টি সংযোগ মিলেছে',
                  ),
                  style: text.labelLarge?.copyWith(color: AppColors.cyan),
                ),
              ),
              const SizedBox(height: 6),
              if (wire == null) ...[
                Text(
                  language.pick('Practice complete', 'অনুশীলন সম্পূর্ণ'),
                  style: text.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  language.pick(
                    'You matched every wire in this lesson. Use the wiring guide for your real circuit.',
                    'এই পাঠের সব তার মিলিয়েছেন। বাস্তব সার্কিটের জন্য সংযোগ নির্দেশিকা ব্যবহার করুন।',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: _saving ? null : _reset,
                  child: Text(
                    language.pick('Practice again', 'আবার অনুশীলন করুন'),
                  ),
                ),
              ] else ...[
                Text(
                  language.pick(
                    'Start from this terminal',
                    'এই টার্মিনাল থেকে শুরু করুন',
                  ),
                  style: text.titleMedium,
                ),
                MotionValue(
                  identity: wire.id,
                  child: Text(
                    _label(wire.from),
                    style: text.titleMedium?.copyWith(color: AppColors.violet),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  language.pick(
                    'Tap the other terminal on the schematic, or choose it from the list.',
                    'স্কিম্যাটিকে অন্য টার্মিনালে ট্যাপ করুন, অথবা তালিকা থেকে বাছুন।',
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _saving || correct ? null : _chooseTerminal,
                      icon: const Icon(Icons.list_rounded, size: 18),
                      label: Text(
                        language.pick(
                          'Choose a terminal',
                          'একটি টার্মিনাল বাছুন',
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _saving || correct
                          ? null
                          : () => setState(() => _hint = !_hint),
                      icon: const Icon(Icons.lightbulb_outline, size: 18),
                      label: Text(language.pick('Hint', 'ইঙ্গিত')),
                    ),
                  ],
                ),
                if (_hint && !correct) ...[
                  const SizedBox(height: 8),
                  Text(language.text(wire.why)),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: () => setState(() => _reveal = !_reveal),
                      child: Text(
                        _reveal
                            ? language.pick('Hide destination', 'গন্তব্য লুকান')
                            : language.pick(
                                'Show destination',
                                'গন্তব্য দেখুন',
                              ),
                      ),
                    ),
                  ),
                  if (_reveal) Text(_label(wire.to), style: text.titleSmall),
                ],
                if (_feedback case final feedback?) ...[
                  const SizedBox(height: 8),
                  Semantics(
                    key: _notice,
                    liveRegion: true,
                    child: MotionValue(
                      identity: feedback,
                      child: Text(
                        _feedbackText(wire, feedback),
                        style: text.bodyMedium?.copyWith(
                          color: correct ? AppColors.mint : AppColors.violet,
                        ),
                      ),
                    ),
                  ),
                ],
                if (correct) ...[
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: _advance,
                    child: Text(
                      visible.length == total
                          ? language.pick('Finish practice', 'অনুশীলন শেষ করুন')
                          : language.pick('Next connection', 'পরের সংযোগ'),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        LearnWiringDiagram(
          project: widget.project,
          language: language,
          activeWire: correct ? wire?.id : null,
          visibleWires: visible,
          prompt: wire?.id,
          onPart: (part, pin) {
            if (pin == null) {
              _chooseTerminal(part: part);
            } else {
              _tryTerminal((part: part, pin: pin));
            }
          },
          inspected: correct ? null : wire?.from,
          inspectedPart: correct ? null : wire?.from.part,
        ),
        const SizedBox(height: 5),
        Text(
          language.pick(
            'Practice uses the lesson schematic. Your real wiring and test checklists stay separate.',
            'অনুশীলনে পাঠের স্কিম্যাটিক ব্যবহার হয়। বাস্তব সংযোগ ও পরীক্ষার তালিকা আলাদা থাকে।',
          ),
          style: text.bodySmall?.copyWith(color: AppColors.muted),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: widget.onReturn,
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: Text(
              language.pick('Back to wiring guide', 'সংযোগ নির্দেশিকায় ফিরুন'),
            ),
          ),
        ),
      ],
    );
  }
}
