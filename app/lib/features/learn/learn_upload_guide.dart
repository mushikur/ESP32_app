import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/ui/surfaces.dart';
import 'learn_catalog.dart';
import 'learn_sketch_export.dart';
import 'learn_widgets.dart';

class LearnUploadGuide extends StatefulWidget {
  const LearnUploadGuide({
    required this.catalog,
    required this.project,
    required this.language,
    super.key,
  });

  final LearnCatalog catalog;
  final LearnProject project;
  final LearnLanguage language;

  @override
  State<LearnUploadGuide> createState() => _LearnUploadGuideState();
}

class _LearnUploadGuideState extends State<LearnUploadGuide> {
  static const _downloadPage = 'https://www.arduino.cc/en/software';
  final _stepHeader = GlobalKey();
  int _index = 0;

  void _go(int index) {
    setState(() => _index = index);
    revealLearnContent(_stepHeader);
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final catalog = widget.catalog;
    final steps = catalog.setup;
    final step = steps[_index];
    final theme = Theme.of(context).textTheme;
    final board = catalog.board;
    final project = widget.project;
    final url = switch (step.stage) {
      LearnSetupStage.install => _downloadPage,
      LearnSetupStage.preferences => board.packageIndex,
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          language.pick(
            'Use Arduino IDE 2 on your computer. Keep this guide open while you work.',
            'কম্পিউটারে Arduino IDE 2 ব্যবহার করুন। কাজের সময় এই নির্দেশিকা খোলা রাখুন।',
          ),
        ),
        const SizedBox(height: 12),
        Panel(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                key: _stepHeader,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      language.pick(
                        'Step ${_index + 1} of ${steps.length}',
                        '${steps.length}টির মধ্যে ধাপ ${_index + 1}',
                      ),
                      style: theme.labelLarge?.copyWith(color: AppColors.cyan),
                    ),
                  ),
                  PopupMenuButton<int>(
                    tooltip: language.pick(
                      'Choose walkthrough step',
                      'নির্দেশিকার ধাপ বাছুন',
                    ),
                    icon: const Icon(Icons.list_alt_rounded),
                    initialValue: _index,
                    onSelected: _go,
                    itemBuilder: (context) => [
                      for (final (index, item) in steps.indexed)
                        PopupMenuItem(
                          value: index,
                          child: Text(language.text(item.title)),
                        ),
                    ],
                  ),
                ],
              ),
              Text(language.text(step.title), style: theme.titleLarge),
              const SizedBox(height: 12),
              _IdeIllustration(
                stage: step.stage,
                board: board,
                project: project,
                language: language,
              ),
              const SizedBox(height: 12),
              Text(language.text(step.text)),
              if (step.stage == LearnSetupStage.serial &&
                  project.serialBaud == null) ...[
                const SizedBox(height: 8),
                Text(
                  language.pick(
                    'This sketch has no Serial Monitor output. Continue to the project test.',
                    'এই স্কেচে Serial Monitor আউটপুট নেই। প্রকল্প পরীক্ষায় যান।',
                  ),
                ),
              ],
              if (url != null) ...[
                const SizedBox(height: 10),
                SelectableText(
                  url,
                  style: theme.bodySmall?.copyWith(color: AppColors.cyan),
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () => copyLearnText(
                      context,
                      url,
                      language,
                      language.pick('Link copied', 'লিঙ্ক কপি হয়েছে'),
                    ),
                    icon: const Icon(Icons.content_copy_rounded, size: 18),
                    label: Text(language.pick('Copy link', 'লিঙ্ক কপি করুন')),
                  ),
                ),
              ],
              if (step.stage == LearnSetupStage.sketch) ...[
                const SizedBox(height: 10),
                LearnSketchActions(project: project, language: language),
              ],
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 8,
                runSpacing: 6,
                children: [
                  OutlinedButton(
                    onPressed: _index == 0 ? null : () => _go(_index - 1),
                    child: Text(language.pick('Previous', 'আগেরটি')),
                  ),
                  FilledButton.tonal(
                    onPressed: _index + 1 >= steps.length
                        ? null
                        : () => _go(_index + 1),
                    child: Text(language.pick('Next', 'পরেরটি')),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SectionHeading(
          language.pick('Upload troubleshooting', 'আপলোডের সমস্যা সমাধান'),
        ),
        const SizedBox(height: 8),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final issue in catalog.uploadIssues)
                ExpansionTile(
                  title: Text(language.text(issue.symptom)),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(language.text(issue.cause)),
                    const SizedBox(height: 7),
                    Text(language.text(issue.fix)),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _IdeIllustration extends StatelessWidget {
  const _IdeIllustration({
    required this.stage,
    required this.board,
    required this.project,
    required this.language,
  });

  final LearnSetupStage stage;
  final LearnBoard board;
  final LearnProject project;
  final LearnLanguage language;

  @override
  Widget build(BuildContext context) {
    final baud = project.serialBaud;
    final (caption, body) = switch (stage) {
      LearnSetupStage.install => (
        'Arduino IDE 2',
        const [_IdeItem(Icons.desktop_windows_outlined, 'Arduino IDE 2')],
      ),
      LearnSetupStage.preferences => (
        'Preferences',
        const [_IdeItem(Icons.link_rounded, 'Additional Boards Manager URLs')],
      ),
      LearnSetupStage.boards => (
        'Boards Manager',
        [
          const _IdeItem(Icons.search_rounded, 'esp32'),
          _IdeItem(
            Icons.developer_board_outlined,
            'esp32 by Espressif Systems',
            detail: board.coreVersion,
          ),
        ],
      ),
      LearnSetupStage.connect => (
        language.pick('USB connection', 'USB সংযোগ'),
        [
          _IdeItem(
            Icons.usb_rounded,
            'Micro-USB',
            detail: language.pick('Data cable', 'ডেটা কেবল'),
          ),
          const _IdeItem(Icons.developer_board_outlined, 'ESP32-DevKitC V4'),
        ],
      ),
      LearnSetupStage.boardPort => (
        'Select other board and port',
        [
          _IdeItem(Icons.developer_board_outlined, board.ideBoard),
          _IdeItem(
            Icons.usb_rounded,
            'COM3',
            detail: language.pick('Example port', 'পোর্টের উদাহরণ'),
          ),
        ],
      ),
      LearnSetupStage.libraries => (
        language.pick(
          'Included with the board package',
          'বোর্ড প্যাকেজের সঙ্গে আছে',
        ),
        const [_IdeItem(Icons.code_rounded, 'Arduino.h')],
      ),
      LearnSetupStage.sketch => (
        'File → Open',
        [
          _IdeItem(Icons.folder_outlined, project.id),
          _IdeItem(Icons.description_outlined, project.sketchFileName),
        ],
      ),
      LearnSetupStage.upload => (
        'Arduino IDE 2',
        [
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ToolbarAction(Icons.check_rounded, 'Verify'),
              _ToolbarAction(Icons.arrow_forward_rounded, 'Upload'),
            ],
          ),
          const _IdeItem(Icons.terminal_rounded, 'Output'),
        ],
      ),
      LearnSetupStage.serial when baud != null => (
        'Tools → Serial Monitor',
        [_IdeItem(Icons.monitor_heart_outlined, '$baud baud')],
      ),
      LearnSetupStage.serial => (
        language.pick('Project test', 'প্রকল্প পরীক্ষা'),
        [_IdeItem(Icons.science_outlined, language.text(project.title))],
      ),
    };
    return Container(
      decoration: BoxDecoration(
        color: AppColors.sunken,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColoredBox(
              color: AppColors.tint(AppColors.cyan, .20),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Text(
                  caption,
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: AppColors.cyan),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (index, item) in body.indexed) ...[
                    if (index > 0) const SizedBox(height: 7),
                    item,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdeItem extends StatelessWidget {
  const _IdeItem(this.icon, this.label, {this.detail});
  final IconData icon;
  final String label;
  final String? detail;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      child: Row(
        children: [
          Icon(icon, color: AppColors.mint, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label),
                if (detail case final text?)
                  Text(
                    text,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: AppColors.muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _ToolbarAction extends StatelessWidget {
  const _ToolbarAction(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Chip(
    avatar: Icon(icon, size: 17, color: AppColors.cyan),
    label: Text(label),
    backgroundColor: AppColors.surface,
  );
}
