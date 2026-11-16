import 'package:flutter/material.dart';

import '../../core/protocol/device_descriptor.dart';
import '../../core/ui/surfaces.dart';
import 'dashboard_control.dart';
import 'dashboard_layout.dart';

class DashboardEditor extends StatefulWidget {
  const DashboardEditor({
    required this.controls,
    required this.tiles,
    required this.save,
    super.key,
  });

  final Map<String, DashboardControl> controls;
  final List<TilePreference> tiles;
  final Future<void> Function(List<TilePreference>) save;

  @override
  State<DashboardEditor> createState() => _DashboardEditorState();
}

class _DashboardEditorState extends State<DashboardEditor> {
  late final _tiles = widget.tiles.toList();
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final tiles = List<TilePreference>.unmodifiable(_tiles);
      await widget.save(tiles);
      if (mounted) Navigator.pop(context, tiles);
    } on Exception {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save the dashboard. Try again.';
        });
      }
    }
  }

  Future<void> _edit(int index) async {
    final tile = _tiles[index];
    final changed = await showDialog<TilePreference>(
      context: context,
      builder: (_) => _TileAppearance(tile, widget.controls[tile.id]!),
    );
    if (mounted && changed != null) setState(() => _tiles[index] = changed);
  }

  void _move(int index, int destination) => setState(() {
    final other = _tiles[destination];
    _tiles[destination] = _tiles[index];
    _tiles[index] = other;
  });

  @override
  Widget build(BuildContext context) {
    final visible = [
      for (final (index, tile) in _tiles.indexed)
        if (!tile.hidden) index,
    ];
    final hidden = [
      for (final (index, tile) in _tiles.indexed)
        if (tile.hidden) index,
    ];
    Widget entry(int index, {int? up, int? down}) {
      final tile = _tiles[index];
      final control = widget.controls[tile.id]!;
      final label = tile.name ?? control.name;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Panel(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconTile(
                    tileIcon(tile.icon, control.type),
                    color: tileColor(tile.color),
                    size: 38,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (!tile.hidden) ...[
                    IconButton(
                      tooltip: 'Move $label up',
                      onPressed: _saving || up == null
                          ? null
                          : () => _move(index, up),
                      icon: const Icon(Icons.keyboard_arrow_up_rounded),
                    ),
                    IconButton(
                      tooltip: 'Move $label down',
                      onPressed: _saving || down == null
                          ? null
                          : () => _move(index, down),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                    IconButton(
                      tooltip: 'Edit $label appearance',
                      onPressed: _saving ? null : () => _edit(index),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ],
                  TextButton.icon(
                    onPressed: _saving
                        ? null
                        : () => setState(
                            () => _tiles[index] = tile.withVisibility(
                              tile.hidden,
                            ),
                          ),
                    icon: Icon(
                      tile.hidden ? Icons.add_rounded : Icons.remove_rounded,
                    ),
                    label: Text(tile.hidden ? 'Add' : 'Remove'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('Edit dashboard')),
        body: SafeArea(
          child: ScreenCanvas(
            child: ScreenScroll(
              children: [
                const SectionHeading('Visible controls'),
                const SizedBox(height: 12),
                if (visible.isEmpty)
                  const Text(
                    'Add a control below to show it on this dashboard.',
                  ),
                for (final (position, index) in visible.indexed)
                  entry(
                    index,
                    up: position > 0 ? visible[position - 1] : null,
                    down: position + 1 < visible.length
                        ? visible[position + 1]
                        : null,
                  ),
                if (hidden.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const SectionHeading('Available to add'),
                  const SizedBox(height: 12),
                  for (final index in hidden) entry(index),
                ],
                if (_error case final message?)
                  Semantics(liveRegion: true, child: Text(message)),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save dashboard'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TileAppearance extends StatefulWidget {
  const _TileAppearance(this.tile, this.control);
  final TilePreference tile;
  final DashboardControl control;

  @override
  State<_TileAppearance> createState() => _TileAppearanceState();
}

class _TileAppearanceState extends State<_TileAppearance> {
  final _form = GlobalKey<FormState>();
  late String _name = widget.tile.name ?? '';
  late TileIcon _icon = widget.tile.icon;
  late TileColor _color = widget.tile.color;

  String _label(Enum value) =>
      '${value.name[0].toUpperCase()}${value.name.substring(1)}';

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Control appearance'),
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            initialValue: _name,
            maxLength: 64,
            decoration: InputDecoration(
              labelText: 'Custom name',
              hintText: widget.control.name,
            ),
            onChanged: (value) => _name = value.trim(),
            validator: (_) => validLabel(_name, 64, allowEmpty: true)
                ? null
                : 'Enter a valid control name.',
          ),
          DropdownButtonFormField<TileIcon>(
            initialValue: _icon,
            decoration: const InputDecoration(labelText: 'Icon'),
            items: [
              for (final icon in TileIcon.values)
                DropdownMenuItem(value: icon, child: Text(_label(icon))),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _icon = value);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<TileColor>(
            initialValue: _color,
            decoration: const InputDecoration(labelText: 'Color'),
            items: [
              for (final color in TileColor.values)
                DropdownMenuItem(
                  value: color,
                  child: Text(
                    _label(color),
                    style: TextStyle(color: tileColor(color)),
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _color = value);
            },
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState?.validate() != true) return;
          Navigator.pop(
            context,
            TilePreference(
              widget.tile.id,
              name: _name.isEmpty ? null : _name,
              icon: _icon,
              color: _color,
              hidden: widget.tile.hidden,
            ),
          );
        },
        child: const Text('Apply'),
      ),
    ],
  );
}
