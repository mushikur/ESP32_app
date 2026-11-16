import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/ui/surfaces.dart';
import 'learn_catalog.dart';
import 'learn_pin_explorer.dart';
import 'learn_wiring_diagram.dart';
import 'learn_wiring_player.dart';
import 'learn_widgets.dart';

class LearnWiringLab extends StatefulWidget {
  const LearnWiringLab({
    required this.catalog,
    required this.project,
    required this.language,
    required this.checked,
    required this.onCheck,
    this.initialWire,
    this.onReturnToTroubleshooting,
    super.key,
  });

  final LearnCatalog catalog;
  final LearnProject project;
  final LearnLanguage language;
  final Set<String> checked;
  final void Function(String id, bool checked) onCheck;
  final String? initialWire;
  final VoidCallback? onReturnToTroubleshooting;

  @override
  State<LearnWiringLab> createState() => _LearnWiringLabState();
}

class _LearnWiringLabState extends State<LearnWiringLab> {
  final _diagram = GlobalKey();
  late int _step;
  String? _part;
  LearnTerminal? _pin;

  @override
  void initState() {
    super.initState();
    final requested = widget.project.wires.indexWhere(
      (wire) => wire.id == widget.initialWire,
    );
    final first = widget.project.wires.indexWhere(
      (wire) => !widget.checked.contains(wire.id),
    );
    _step = requested >= 0 ? requested : (first < 0 ? 0 : first);
    if (requested >= 0) revealLearnContent(_diagram);
  }

  void _selectWire(int index, {bool reveal = true}) {
    setState(() {
      _step = index;
      _part = null;
      _pin = null;
    });
    final diagram = _diagram.currentContext;
    if (reveal && diagram != null) {
      Scrollable.ensureVisible(
        diagram,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 230),
        curve: Curves.easeOut,
      );
    }
  }

  void _inspect(String id, String? pin) => setState(() {
    _part = id;
    _pin = pin == null ? null : (part: id, pin: pin);
  });

  String _route(LearnWire wire) {
    final from = widget.catalog.terminalLabel(
      widget.project,
      wire.from,
      widget.language,
    );
    final to = widget.catalog.terminalLabel(
      widget.project,
      wire.to,
      widget.language,
    );
    return '$from → $to';
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    final language = widget.language;
    final wires = project.wires;
    final active = wires[_step];
    final inspected = _part;
    final color = learnWireColor(active.color);
    final colorLabel = _wireColorName(active.color, language);
    final heading = Theme.of(context).textTheme.titleMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LearnWiringPlayer(
          catalog: widget.catalog,
          project: project,
          language: language,
          onStep: (index) {
            if (index != _step) {
              setState(() {
                _step = index;
                _part = null;
                _pin = null;
              });
            }
          },
        ),
        const SizedBox(height: 10),
        Panel(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(language.pick('Wiring lab', 'সংযোগ ল্যাব'), style: heading),
              const SizedBox(height: 4),
              Text(
                language.pick(
                  'Tap a wire, component, or pin. Pinch or use the zoom buttons to see more detail.',
                  'তার, উপকরণ বা পিনে ট্যাপ করুন। আরও স্পষ্ট দেখতে দুই আঙুল বা জুম বোতাম ব্যবহার করুন।',
                ),
              ),
              const SizedBox(height: 9),
              LearnWiringDiagram(
                key: _diagram,
                project: project,
                language: language,
                activeWire: active.id,
                onWire: (id) => _selectWire(
                  wires.indexWhere((wire) => wire.id == id),
                  reveal: false,
                ),
                onPart: _inspect,
                inspected: _pin,
                inspectedPart: inspected,
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  language.pick(
                    'Junction dots mark shared connections. Use the wiring steps to find the breadboard rows.',
                    'বিন্দু দিয়ে যৌথ সংযোগ দেখানো হয়েছে। ব্রেডবোর্ডের সারি খুঁজতে সংযোগ ধাপ দেখুন।',
                  ),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: AppColors.muted),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            LearnPinExplorerButton(
              board: widget.catalog.board,
              project: project,
              language: language,
            ),
            if (widget.onReturnToTroubleshooting case final onReturn?)
              TextButton.icon(
                onPressed: onReturn,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: Text(
                  language.pick(
                    'Back to troubleshooting',
                    'সমস্যা সমাধানে ফিরুন',
                  ),
                ),
              ),
          ],
        ),
        if (inspected != null) ...[
          const SizedBox(height: 8),
          _componentDetails(inspected, heading),
        ],
        const SizedBox(height: 8),
        Panel(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                language.pick(
                  'Connection ${_step + 1} of ${wires.length}',
                  '${wires.length}টির মধ্যে সংযোগ ${_step + 1}',
                ),
                style: heading?.copyWith(color: color),
              ),
              const SizedBox(height: 5),
              Text(_route(active), style: heading),
              const SizedBox(height: 6),
              Text('$colorLabel · ${language.text(active.why)}'),
              const SizedBox(height: 7),
              CheckboxListTile(
                key: ValueKey('active-wire-${active.id}'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: widget.checked.contains(active.id),
                onChanged: (value) => widget.onCheck(active.id, value ?? false),
                title: Text(
                  language.pick(
                    'I checked this connection',
                    'এই সংযোগটি মিলিয়েছি',
                  ),
                ),
              ),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 8,
                runSpacing: 4,
                children: [
                  OutlinedButton(
                    onPressed: _step > 0 ? () => _selectWire(_step - 1) : null,
                    child: Text(language.pick('Previous wire', 'আগের তার')),
                  ),
                  OutlinedButton(
                    onPressed: _step + 1 < wires.length
                        ? () => _selectWire(_step + 1)
                        : null,
                    child: Text(language.pick('Next wire', 'পরের তার')),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Panel(
          padding: EdgeInsets.zero,
          child: ExpansionTile(
            title: Text(language.pick('All connections', 'সব সংযোগ')),
            subtitle: Text(
              language.pick(
                '${widget.checked.length} of ${wires.length} checked',
                '${wires.length}টির মধ্যে ${widget.checked.length}টি মিলিয়েছি',
              ),
            ),
            children: [
              for (final (index, wire) in wires.indexed)
                ListTile(
                  selected: index == _step,
                  selectedColor: AppColors.cyan,
                  leading: Icon(
                    widget.checked.contains(wire.id)
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                    color: learnWireColor(wire.color),
                  ),
                  title: Text(_route(wire)),
                  onTap: () => _selectWire(index),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Panel(
          padding: EdgeInsets.zero,
          child: ExpansionTile(
            title: Text(language.pick('Inspect components', 'উপকরণ দেখুন')),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              for (final id in project.circuit.nodes.keys)
                ListTile(
                  selected: id == inspected,
                  title: Text(
                    '$id · ${language.text(widget.catalog.parts[project.parts[id]]!.title)}',
                  ),
                  onTap: () => _inspect(id, null),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _componentDetails(String id, TextStyle? heading) {
    final language = widget.language;
    final part = widget.catalog.parts[widget.project.parts[id]]!;
    final pins = widget.project.circuit.nodes[id]!.terminals.keys;
    final pin = _pin;
    return Panel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$id · ${language.text(part.title)}', style: heading),
          const SizedBox(height: 5),
          Text(language.text(part.about)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 7,
            children: [
              for (final name in pins)
                ChoiceChip(
                  label: Text(name),
                  selected: name == pin?.pin,
                  onSelected: (value) => _inspect(id, value ? name : null),
                ),
            ],
          ),
          if (pin != null) ...[
            const SizedBox(height: 5),
            Text(
              widget.catalog.terminalLabel(widget.project, pin, language),
              style: TextStyle(color: AppColors.violet),
            ),
            for (final (index, wire) in widget.project.wires.indexed)
              if (wire.from == pin || wire.to == pin)
                TextButton(
                  onPressed: () => _selectWire(index),
                  child: Text(_route(wire), textAlign: TextAlign.start),
                ),
          ],
        ],
      ),
    );
  }
}

String _wireColorName(String color, LearnLanguage language) => switch (color) {
  'red' => language.pick('Red', 'লাল'),
  'green' => language.pick('Green', 'সবুজ'),
  'yellow' => language.pick('Yellow', 'হলুদ'),
  'violet' => language.pick('Violet', 'বেগুনি'),
  'black' => language.pick('Black', 'কালো'),
  _ => language.pick('Cyan', 'সায়ান'),
};
