import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_theme.dart';
import '../../core/ui/app_motion.dart';
import '../../core/ui/surfaces.dart';
import 'learn_art.dart';
import 'learn_board_3d.dart';
import 'learn_catalog.dart';
import 'learn_companion_apps.dart';
import 'learn_pin_explorer.dart';
import 'learn_progress.dart';
import 'learn_project_checks.dart';
import 'learn_quiz.dart';
import 'learn_reward_widgets.dart';
import 'learn_sketch_viewer.dart';
import 'learn_upload_guide.dart';
import 'learn_widgets.dart';
import 'learn_wiring_lab.dart';
import 'learn_wiring_practice.dart';

enum _Stage {
  overview('Understand the project', 'প্রকল্পটি বুঝুন'),
  parts('Gather the components', 'উপকরণ জোগাড় করুন', LearnMilestone.parts),
  board('Know your ESP32 board', 'ESP32 বোর্ড চিনুন'),
  wiring('Wire the circuit', 'সার্কিটের তার লাগান', LearnMilestone.wiring),
  practice('Practice wiring', 'সংযোগ অনুশীলন'),
  code('Read the sketch', 'স্কেচটি পড়ুন'),
  quiz('Check yourself', 'নিজেকে যাচাই করুন'),
  upload(
    'Upload with Arduino IDE',
    'Arduino IDE দিয়ে আপলোড',
    LearnMilestone.upload,
  ),
  test('Test the project', 'প্রকল্প পরীক্ষা করুন', LearnMilestone.test),
  help('Troubleshoot', 'সমস্যা সমাধান');

  const _Stage(this.en, this.bn, [this.milestone]);
  final String en, bn;
  final LearnMilestone? milestone;
  String label(LearnLanguage language) => language.pick(en, bn);
}

class LearnProjectScreen extends ConsumerStatefulWidget {
  const LearnProjectScreen({required this.id, super.key});

  final String id;

  @override
  ConsumerState<LearnProjectScreen> createState() => _LearnProjectScreenState();
}

class _LearnProjectScreenState extends ConsumerState<LearnProjectScreen> {
  _Stage? _stage;
  String? _wireFromIssue;
  final _completion = GlobalKey();
  bool _celebrate = false;

  @override
  void initState() {
    super.initState();
    unawaited(
      ref
          .read(learnCatalogProvider.future)
          .then<void>(
            (catalog) async {
              if (!mounted || !catalog.projects.containsKey(widget.id)) return;
              final language =
                  ref.read(learnProgressProvider).value?.language ??
                  LearnLanguage.en;
              await saveLearnChange(
                context,
                ref.read(learnProgressProvider.notifier).openProject(widget.id),
                language,
              );
            },
            onError: (Object _) {
              // The page displays the catalog loading error.
            },
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(learnProgressProvider, (previous, next) {
      if (previous?.value?.forProject(widget.id).completed == false &&
          next.value?.forProject(widget.id).completed == true) {
        setState(() => _celebrate = true);
        revealLearnContent(_completion);
      }
    });
    final catalogState = ref.watch(learnCatalogProvider);
    final progressState = ref.watch(learnProgressProvider);
    final catalog = catalogState.value;
    final saved = progressState.value;
    final language = saved?.language ?? LearnLanguage.en;
    if (catalog == null || saved == null) {
      return LearnLoadState(
        language: language,
        failed: catalogState.hasError || progressState.hasError,
        retry: () {
          if (catalogState.hasError) ref.invalidate(learnCatalogProvider);
          if (progressState.hasError) ref.invalidate(learnProgressProvider);
        },
      );
    }
    final project = catalog.projects[widget.id];
    if (project == null) {
      return ScreenScroll(
        children: [
          EmptyPanel(
            icon: Icons.book_outlined,
            title: language.pick(
              'Project unavailable',
              'প্রকল্পটি পাওয়া যায়নি',
            ),
            description: language.pick(
              'Choose a lesson from the project library.',
              'লাইব্রেরি থেকে একটি পাঠ বেছে নিন।',
            ),
            action: OutlinedButton(
              onPressed: _back,
              child: Text(
                language.pick('Project library', 'প্রকল্পের লাইব্রেরি'),
              ),
            ),
          ),
        ],
      );
    }
    final progress = saved.forProject(project.id);
    final stage = _stage;
    final completion = progress.completed
        ? LearnCompletionPanel(
            key: _completion,
            project: project,
            language: language,
            next: _nextProject(catalog, saved, project.id),
            animate: _celebrate,
          )
        : null;
    return ScreenScroll(
      key: ValueKey(stage),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: stage == null ? _back : () => _show(null),
            icon: const Icon(Icons.arrow_back_rounded),
            label: Text(
              stage == null
                  ? language.pick('Project library', 'প্রকল্পের লাইব্রেরি')
                  : language.pick('Project overview', 'প্রকল্পের পরিচয়'),
            ),
          ),
        ),
        if (stage == null)
          ..._preview(context, catalog, project, progress, language, completion)
        else
          ..._guide(
            context,
            catalog,
            project,
            progress,
            language,
            stage,
            completion,
          ),
      ],
    );
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/learn');
    }
  }

  void _show(_Stage? stage, {String? wireId}) => setState(() {
    _stage = stage;
    _wireFromIssue = wireId;
    _celebrate = false;
  });

  LearnProject? _nextProject(
    LearnCatalog catalog,
    LearnProgress progress,
    String id,
  ) {
    final all = catalog.projects.values;
    bool remaining(LearnProject project) =>
        project.id != id && !progress.forProject(project.id).completed;
    return all
            .skipWhile((project) => project.id != id)
            .skip(1)
            .where(remaining)
            .firstOrNull ??
        all.where(remaining).firstOrNull;
  }

  List<Widget> _preview(
    BuildContext context,
    LearnCatalog catalog,
    LearnProject project,
    ProjectProgress progress,
    LearnLanguage language,
    Widget? completion,
  ) {
    final text = Theme.of(context).textTheme;
    final started = progress.checked.isNotEmpty || progress.items.isNotEmpty;
    return [
      const SizedBox(height: 8),
      MotionReveal(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: SizedBox(height: 154, child: LearnArt(project.artwork)),
        ),
      ),
      const SizedBox(height: 17),
      Text(
        '${project.difficulty.label(language)} · ${project.minutes} ${language.pick('min', 'মিনিট')}',
        style: text.titleSmall?.copyWith(
          color: LearnArt.colorFor(project.artwork),
        ),
      ),
      const SizedBox(height: 6),
      Text(language.text(project.title), style: text.headlineLarge),
      const SizedBox(height: 8),
      Text(language.text(project.intro), style: text.bodyLarge),
      const SizedBox(height: 7),
      Text(
        catalog.board.name,
        style: text.bodySmall?.copyWith(color: AppColors.muted),
      ),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: () {
          final next = !started || progress.completed
              ? _Stage.overview
              : _Stage.values.firstWhere(
                  (stage) =>
                      stage.milestone != null &&
                      !progress.checked.contains(stage.milestone),
                );
          _show(next);
        },
        icon: Icon(
          progress.completed ? Icons.replay_rounded : Icons.play_arrow_rounded,
        ),
        label: Text(
          progress.completed
              ? language.pick('Revisit the guide', 'নির্দেশিকা আবার দেখুন')
              : !started
              ? language.pick('Start building', 'বানানো শুরু করুন')
              : language.pick('Continue building', 'বানানো চালিয়ে যান'),
        ),
      ),
      const SizedBox(height: 12),
      _LessonProgress(progress: progress, language: language),
      if (completion != null) ...[const SizedBox(height: 12), completion],
      const SizedBox(height: 24),
      SectionHeading(language.pick('What you’ll learn', 'যা শিখবেন')),
      const SizedBox(height: 9),
      ...project.objectives.map((item) => _Bullet(language.text(item))),
      const SizedBox(height: 20),
      SectionHeading(language.pick('Required components', 'যা লাগবে')),
      const SizedBox(height: 9),
      _PartList(catalog: catalog, project: project, language: language),
    ];
  }

  List<Widget> _guide(
    BuildContext context,
    LearnCatalog catalog,
    LearnProject project,
    ProjectProgress progress,
    LearnLanguage language,
    _Stage stage,
    Widget? completion,
  ) {
    final text = Theme.of(context).textTheme;
    void checkItem(LearnChecklist list, String id, bool checked) => unawaited(
      saveLearnChange(
        context,
        ref
            .read(learnProgressProvider.notifier)
            .checkItem(project, list, id, checked),
        language,
      ),
    );
    final content = switch (stage) {
      _Stage.overview => [
        Text(language.text(project.overview), style: text.bodyLarge),
        const SizedBox(height: 18),
        _TextCard(
          title: 'GPIO',
          body: language.pick(
            'A pin that reads an input or controls an output, such as an LED.',
            'যে পিন ইনপুট পড়ে বা LED-এর মতো আউটপুট নিয়ন্ত্রণ করে।',
          ),
        ),
        _TextCard(
          title: 'GND',
          body: language.pick(
            'The circuit’s shared ground. It provides the return path for current.',
            'সার্কিটের সাধারণ গ্রাউন্ড। কারেন্ট ফেরার পথ দেয়।',
          ),
        ),
      ],
      _Stage.parts => [
        _PartsChecklist(
          catalog: catalog,
          project: project,
          language: language,
          checked: progress.checkedItems(project, LearnChecklist.parts),
          onCheck: (id, value) => checkItem(LearnChecklist.parts, id, value),
        ),
      ],
      _Stage.board => [
        _TextCard(
          title: catalog.board.name,
          body: language.text(catalog.board.orientation),
        ),
        LearnBoard3D(
          board: catalog.board,
          project: project,
          language: language,
        ),
        const SizedBox(height: 10),
        LearnPinExplorerButton(
          board: catalog.board,
          project: project,
          language: language,
        ),
      ],
      _Stage.wiring => [
        _TextCard(
          title: language.pick('Before wiring', 'তার লাগানোর আগে'),
          body: language.text(catalog.safety),
        ),
        for (final warning in project.safety) _Bullet(language.text(warning)),
        const SizedBox(height: 10),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: () => _show(_Stage.practice),
            icon: const Icon(Icons.school_outlined, size: 18),
            label: Text(language.pick('Practice wiring', 'সংযোগ অনুশীলন')),
          ),
        ),
        const SizedBox(height: 8),
        LearnWiringLab(
          catalog: catalog,
          project: project,
          language: language,
          checked: progress.checkedItems(project, LearnChecklist.wiring),
          onCheck: (id, value) => checkItem(LearnChecklist.wiring, id, value),
          initialWire: _wireFromIssue,
          onReturnToTroubleshooting: _wireFromIssue == null
              ? null
              : () => _show(_Stage.help),
        ),
      ],
      _Stage.practice => [
        LearnWiringPractice(
          catalog: catalog,
          project: project,
          language: language,
          matched: progress.checkedItems(project, LearnChecklist.practice),
          onMatch: (id) => ref
              .read(learnProgressProvider.notifier)
              .checkItem(project, LearnChecklist.practice, id, true),
          onReset: () => ref
              .read(learnProgressProvider.notifier)
              .resetPractice(project.id),
          onReturn: () => _show(_Stage.wiring),
        ),
      ],
      _Stage.code => [LearnSketchViewer(project: project, language: language)],
      _Stage.quiz => [
        LearnQuiz(catalog: catalog, project: project, language: language),
      ],
      _Stage.upload => [
        LearnUploadGuide(
          catalog: catalog,
          project: project,
          language: language,
        ),
        const SizedBox(height: 12),
        LearnCompanionApps(language: language),
      ],
      _Stage.test => [
        LearnTestChecklist(
          project: project,
          language: language,
          checked: progress.checkedItems(project, LearnChecklist.test),
          onCheck: (id, value) => checkItem(LearnChecklist.test, id, value),
          onTroubleshoot: () => _show(_Stage.help),
        ),
      ],
      _Stage.help => [
        LearnProjectTroubleshooting(
          project: project,
          language: language,
          onWire: (id) => _show(_Stage.wiring, wireId: id),
          onTests: () => _show(_Stage.test),
        ),
      ],
    };
    return [
      const SizedBox(height: 5),
      Text(language.text(project.title), style: text.titleLarge),
      const SizedBox(height: 9),
      _LessonProgress(progress: progress, language: language),
      const SizedBox(height: 12),
      DropdownButton<_Stage>(
        isExpanded: true,
        value: stage,
        onChanged: (value) => _show(value),
        items: [
          for (final option in _Stage.values)
            DropdownMenuItem(
              value: option,
              child: Text(
                option.label(language),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
      const SizedBox(height: 14),
      SectionHeading(stage.label(language)),
      const SizedBox(height: 12),
      MotionReveal(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: content,
        ),
      ),
      if (stage == _Stage.upload) ...[
        const SizedBox(height: 14),
        Panel(
          padding: EdgeInsets.zero,
          child: CheckboxListTile(
            value: progress.checked.contains(LearnMilestone.upload),
            title: Text(
              language.pick(
                'Arduino IDE finished uploading',
                'Arduino IDE আপলোড শেষ করেছে',
              ),
            ),
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (value) => saveLearnChange(
              context,
              ref
                  .read(learnProgressProvider.notifier)
                  .check(project.id, LearnMilestone.upload, value ?? false),
              language,
            ),
          ),
        ),
      ],
      if (completion != null) ...[const SizedBox(height: 14), completion],
      const SizedBox(height: 18),
      Wrap(
        alignment: WrapAlignment.end,
        spacing: 10,
        runSpacing: 10,
        children: [
          if (stage.index > 0)
            OutlinedButton(
              onPressed: () => _show(
                stage == _Stage.code
                    ? _Stage.wiring
                    : _Stage.values[stage.index - 1],
              ),
              child: Text(language.pick('Previous step', 'আগের ধাপ')),
            ),
          FilledButton(
            onPressed: () => _show(
              stage == _Stage.wiring
                  ? _Stage.code
                  : _Stage.values.elementAtOrNull(stage.index + 1),
            ),
            child: Text(
              stage == _Stage.help
                  ? language.pick('Project overview', 'প্রকল্পের পরিচয়')
                  : language.pick('Next step', 'পরের ধাপ'),
            ),
          ),
        ],
      ),
    ];
  }
}

class _LessonProgress extends StatelessWidget {
  const _LessonProgress({required this.progress, required this.language});
  final ProjectProgress progress;
  final LearnLanguage language;

  @override
  Widget build(BuildContext context) {
    final count = progress.checked.length;
    final total = LearnMilestone.values.length;
    final label = progress.completed
        ? language.pick('Project completed', 'প্রকল্প সম্পূর্ণ')
        : language.pick(
            '$count of $total checkpoints',
            '$totalটির মধ্যে $countটি ধাপ সম্পূর্ণ',
          );
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          LearnProgressBar(fraction: count / total, label: label),
        ],
      ),
    );
  }
}

class _PartList extends StatelessWidget {
  const _PartList({
    required this.catalog,
    required this.project,
    required this.language,
  });
  final LearnCatalog catalog;
  final LearnProject project;
  final LearnLanguage language;

  @override
  Widget build(BuildContext context) {
    final quantities = <String, int>{};
    for (final kind in project.parts.values) {
      quantities.update(kind, (count) => count + 1, ifAbsent: () => 1);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in quantities.entries)
          _Bullet(
            '${entry.value} × ${language.text(catalog.parts[entry.key]!.title)}',
          ),
      ],
    );
  }
}

class _PartsChecklist extends StatelessWidget {
  const _PartsChecklist({
    required this.catalog,
    required this.project,
    required this.language,
    required this.checked,
    required this.onCheck,
  });

  final LearnCatalog catalog;
  final LearnProject project;
  final LearnLanguage language;
  final Set<String> checked;
  final void Function(String id, bool checked) onCheck;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        language.pick(
          '${checked.length} of ${project.parts.length} components ready',
          '${project.parts.length}টির মধ্যে ${checked.length}টি উপকরণ প্রস্তুত',
        ),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 9),
      for (final entry in project.parts.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Panel(
            padding: EdgeInsets.zero,
            child: CheckboxListTile(
              key: ValueKey('component-${entry.key}'),
              value: checked.contains(entry.key),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (value) => onCheck(entry.key, value ?? false),
              title: Text(
                '${entry.key} · ${language.text(catalog.parts[entry.value]!.title)}',
              ),
              subtitle: Text(language.text(catalog.parts[entry.value]!.about)),
            ),
          ),
        ),
    ],
  );
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 4, right: 9),
          child: Icon(Icons.circle, size: 8, color: AppColors.cyan),
        ),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _TextCard extends StatelessWidget {
  const _TextCard({required this.title, required this.body});
  final String title, body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Panel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 5),
          Text(body),
        ],
      ),
    ),
  );
}
