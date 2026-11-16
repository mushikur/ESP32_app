import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/ui/surfaces.dart';
import 'learn_catalog.dart';
import 'learn_sketch_export.dart';
import 'learn_widgets.dart';

enum _SketchView { complete, learn }

class LearnSketchViewer extends StatefulWidget {
  const LearnSketchViewer({
    required this.project,
    required this.language,
    super.key,
  });

  final LearnProject project;
  final LearnLanguage language;

  @override
  State<LearnSketchViewer> createState() => _LearnSketchViewerState();
}

class _LearnSketchViewerState extends State<LearnSketchViewer> {
  final _explanation = GlobalKey();
  _SketchView _view = _SketchView.complete;
  int? _active = 0;

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    final language = widget.language;
    final notes = project.codeNotes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          project.sketchFileName,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontFamily: 'monospace'),
        ),
        const SizedBox(height: 8),
        LearnSketchActions(project: project, language: language),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: Text(language.pick('Complete code', 'সম্পূর্ণ কোড')),
              selected: _view == _SketchView.complete,
              onSelected: (_) => setState(() => _view = _SketchView.complete),
            ),
            ChoiceChip(
              label: Text(language.pick('Learn the code', 'কোড বুঝুন')),
              selected: _view == _SketchView.learn,
              onSelected: (_) => setState(() => _view = _SketchView.learn),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_view == _SketchView.complete)
          _CodePane(
            lines: project.sketchLines,
            firstLine: 1,
            lastLine: project.sketchLines.length,
          )
        else ...[
          Text(
            language.pick(
              'Tap an explanation to see the matching lines.',
              'মিল আছে এমন লাইন দেখতে ব্যাখ্যায় ট্যাপ করুন।',
            ),
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 10),
          for (final (index, note) in notes.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Panel(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      key: ValueKey('code-note-${note.firstLine}'),
                      title: Text(language.text(note.title)),
                      subtitle: Text(_lineLabel(note, language)),
                      selected: _active == index,
                      selectedColor: AppColors.cyan,
                      trailing: Icon(
                        _active == index
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                      ),
                      onTap: () {
                        setState(
                          () => _active = _active == index ? null : index,
                        );
                        if (_active != null) revealLearnContent(_explanation);
                      },
                    ),
                    if (_active == index)
                      Padding(
                        key: _explanation,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _CodePane(
                              key: ValueKey(
                                'highlight-${note.firstLine}-${note.lastLine}',
                              ),
                              lines: project.sketchLines,
                              firstLine: note.firstLine,
                              lastLine: note.lastLine,
                              highlighted: true,
                            ),
                            const SizedBox(height: 10),
                            Text(language.text(note.text)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

String _lineLabel(LearnCodeNote note, LearnLanguage language) =>
    note.firstLine == note.lastLine
    ? language.pick('Line ${note.firstLine}', 'লাইন ${note.firstLine}')
    : language.pick(
        'Lines ${note.firstLine}–${note.lastLine}',
        'লাইন ${note.firstLine}–${note.lastLine}',
      );

class _CodePane extends StatelessWidget {
  const _CodePane({
    required this.lines,
    required this.firstLine,
    required this.lastLine,
    this.highlighted = false,
    super.key,
  });

  final List<String> lines;
  final int firstLine, lastLine;
  final bool highlighted;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: highlighted
          ? AppColors.tint(AppColors.cyan, .14)
          : AppColors.sunken,
      border: Border.all(color: highlighted ? AppColors.cyan : AppColors.line),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      child: SelectionArea(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = firstLine; i <= lastLine; i++)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectionContainer.disabled(
                      child: ExcludeSemantics(
                        child: Text(
                          '${i.toString().padLeft(2)}  ',
                          style: _codeStyle.copyWith(
                            color: highlighted
                                ? AppColors.cyan
                                : AppColors.muted,
                          ),
                        ),
                      ),
                    ),
                    Text.rich(
                      TextSpan(children: _syntax(lines[i - 1])),
                      style: _codeStyle,
                      textDirection: TextDirection.ltr,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

TextStyle get _codeStyle => TextStyle(
  fontFamily: 'monospace',
  fontSize: 13,
  height: 1.5,
  color: AppColors.text,
);

final _tokens = RegExp(
  r'//.*|"(?:\\.|[^"\\])*"|<Arduino\.h>|#include|\b(?:constexpr|const|void|bool|if|else|return|true|false|uint8_t|uint16_t|uint32_t|unsigned|long|static_cast)\b|\b(?:OUTPUT|INPUT_PULLUP|HIGH|LOW|ADC_11db)\b|\b[0-9]+(?:UL)?\b',
);

List<TextSpan> _syntax(String line) {
  final spans = <TextSpan>[];
  var position = 0;
  for (final match in _tokens.allMatches(line)) {
    if (match.start > position) {
      spans.add(TextSpan(text: line.substring(position, match.start)));
    }
    final token = match[0]!;
    final color = switch (token[0]) {
      '/' => AppColors.muted,
      '"' || '<' => AppColors.mint,
      _ when token.codeUnitAt(0) >= 48 && token.codeUnitAt(0) <= 57 =>
        AppColors.blue,
      _
          when const {
            'HIGH',
            'LOW',
            'OUTPUT',
            'INPUT_PULLUP',
            'ADC_11db',
          }.contains(token) =>
        AppColors.cyan,
      _ => AppColors.violet,
    };
    spans.add(
      TextSpan(
        text: token,
        style: TextStyle(color: color),
      ),
    );
    position = match.end;
  }
  if (position < line.length) {
    spans.add(TextSpan(text: line.substring(position)));
  }
  return spans;
}
