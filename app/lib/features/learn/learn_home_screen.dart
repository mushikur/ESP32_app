import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_theme.dart';
import '../../core/ui/app_motion.dart';
import '../../core/ui/surfaces.dart';
import 'learn_art.dart';
import 'learn_catalog.dart';
import 'learn_progress.dart';
import 'learn_reward_widgets.dart';
import 'learn_rewards.dart';
import 'learn_widgets.dart';

class LearnHomeScreen extends ConsumerStatefulWidget {
  const LearnHomeScreen({super.key});

  @override
  ConsumerState<LearnHomeScreen> createState() => _LearnHomeScreenState();
}

class _LearnHomeScreenState extends ConsumerState<LearnHomeScreen> {
  String _query = '';
  LearnCategory? _category;
  LearnDifficulty? _difficulty;
  bool _onlyCompleted = false;
  Timer? _midnight;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refreshDay);
    _scheduleDayRefresh();
  }

  void _refreshDay() {
    if (!mounted) return;
    setState(() {});
    _scheduleDayRefresh();
  }

  void _scheduleDayRefresh() {
    _midnight?.cancel();
    final now = ref.read(learnClockProvider)();
    final next = now.isUtc
        ? DateTime.utc(now.year, now.month, now.day + 1)
        : DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(next.difference(now), _refreshDay);
  }

  @override
  void dispose() {
    _midnight?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(learnCatalogProvider);
    final saved = ref.watch(learnProgressProvider);
    final language = saved.value?.language ?? LearnLanguage.en;
    final content = catalog.value;
    final progress = saved.value;
    if (content == null || progress == null) {
      return LearnLoadState(
        language: language,
        failed: catalog.hasError || saved.hasError,
        retry: () {
          if (catalog.hasError) ref.invalidate(learnCatalogProvider);
          if (saved.hasError) ref.invalidate(learnProgressProvider);
        },
      );
    }
    final text = Theme.of(context).textTheme;
    final rewards = LearnRewards.calculate(
      content,
      progress,
      ref.watch(learnClockProvider)(),
    );
    final all = content.projects.values.toList();
    final recent =
        all.where((p) => progress.forProject(p.id).opened != null).toList()
          ..sort(
            (a, b) => progress
                .forProject(b.id)
                .opened!
                .compareTo(progress.forProject(a.id).opened!),
          );
    final suggested =
        recent.where((p) => !progress.forProject(p.id).completed).firstOrNull ??
        all.where((p) => !progress.forProject(p.id).completed).firstOrNull;
    final completed = all
        .where((p) => progress.forProject(p.id).completed)
        .length;
    final filtered = all.where((project) {
      if (_onlyCompleted && !progress.forProject(project.id).completed) {
        return false;
      }
      if (_category != null && !project.categories.contains(_category)) {
        return false;
      }
      if (_difficulty != null && project.difficulty != _difficulty) {
        return false;
      }
      return _query.isEmpty ||
          [
            project.title.en,
            project.title.bn,
            project.intro.en,
            project.intro.bn,
          ].any((term) => term.toLowerCase().contains(_query));
    }).toList();
    final title = language.pick('Learn & Build', 'শিখুন ও বানান');

    return ScreenScroll(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(title, style: text.headlineLarge)),
            PopupMenuButton<LearnLanguage>(
              tooltip: language.pick('Lesson language', 'পাঠের ভাষা'),
              initialValue: language,
              icon: Icon(Icons.translate_rounded, color: AppColors.cyan),
              onSelected: (value) => saveLearnChange(
                context,
                ref.read(learnProgressProvider.notifier).changeLanguage(value),
                language,
              ),
              itemBuilder: (context) => const [
                PopupMenuItem(value: LearnLanguage.en, child: Text('English')),
                PopupMenuItem(value: LearnLanguage.bn, child: Text('বাংলা')),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          language.pick(
            'Build your first circuit, one project at a time.',
            'একটি করে প্রকল্প বানিয়ে আপনার প্রথম সার্কিট শিখুন।',
          ),
          style: text.bodyLarge?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 18),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconTile(Icons.route_rounded, color: AppColors.mint),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          language.pick('Beginner path', 'শুরুর পথ'),
                          style: text.titleMedium,
                        ),
                        Text(
                          language.pick(
                            '$completed of ${all.length} projects completed',
                            '${all.length}টি প্রকল্পের মধ্যে $completedটি সম্পূর্ণ',
                          ),
                          style: text.bodySmall?.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              LearnProgressBar(
                fraction: completed / all.length,
                label: language.pick(
                  'Beginner path progress',
                  'শুরুর পথের অগ্রগতি',
                ),
              ),
              const SizedBox(height: 12),
              LearnRewardSummary(
                catalog: content,
                progress: progress,
                rewards: rewards,
              ),
            ],
          ),
        ),
        if (suggested != null) ...[
          const SizedBox(height: 22),
          SectionHeading(
            language.pick('Recommended next', 'পরের প্রস্তাবিত প্রকল্প'),
          ),
          const SizedBox(height: 10),
          _ProjectCard(
            project: suggested,
            progress: progress.forProject(suggested.id),
            language: language,
            featured: true,
          ),
        ],
        if (recent.isNotEmpty) ...[
          const SizedBox(height: 22),
          SectionHeading(
            language.pick('Recently opened', 'সম্প্রতি খোলা হয়েছে'),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final project in recent.take(3))
                ActionChip(
                  avatar: const Icon(Icons.history_rounded, size: 18),
                  label: Text(language.text(project.title)),
                  onPressed: () => context.push('/learn/${project.id}'),
                ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        SectionHeading(language.pick('Project library', 'প্রকল্পের লাইব্রেরি')),
        const SizedBox(height: 12),
        TextField(
          decoration: InputDecoration(
            labelText: language.pick('Search projects', 'প্রকল্প খুঁজুন'),
            prefixIcon: const Icon(Icons.search_rounded),
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onChanged: (value) =>
              setState(() => _query = value.trim().toLowerCase()),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 3,
          children: [
            ChoiceChip(
              label: Text(language.pick('All categories', 'সব বিভাগ')),
              selected: _category == null,
              onSelected: (_) => setState(() => _category = null),
            ),
            for (final category in LearnCategory.values)
              ChoiceChip(
                label: Text(category.label(language)),
                selected: category == _category,
                onSelected: (selected) =>
                    setState(() => _category = selected ? category : null),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 3,
          children: [
            PopupMenuButton<String>(
              tooltip: language.pick(
                'Filter by difficulty',
                'স্তর দিয়ে বাছাই',
              ),
              initialValue: _difficulty?.name ?? 'all',
              onSelected: (value) => setState(
                () => _difficulty = value == 'all'
                    ? null
                    : LearnDifficulty.values.byName(value),
              ),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'all',
                  child: Text(language.pick('All difficulties', 'সব স্তর')),
                ),
                for (final level in LearnDifficulty.values)
                  PopupMenuItem(
                    value: level.name,
                    child: Text(level.label(language)),
                  ),
              ],
              child: Chip(
                avatar: const Icon(Icons.tune_rounded, size: 17),
                label: Text(
                  _difficulty?.label(language) ??
                      language.pick('Difficulty', 'স্তর'),
                ),
              ),
            ),
            FilterChip(
              label: Text(language.pick('Completed', 'সম্পূর্ণ')),
              selected: _onlyCompleted,
              onSelected: (value) => setState(() => _onlyCompleted = value),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (filtered.isEmpty)
          EmptyPanel(
            icon: Icons.search_off_rounded,
            title: language.pick('No projects match', 'কোনো প্রকল্প মেলেনি'),
            description: language.pick(
              'Try another category, difficulty, or search term.',
              'অন্য বিভাগ, স্তর বা শব্দ দিয়ে খুঁজুন।',
            ),
          )
        else
          for (final (index, project) in filtered.indexed)
            Padding(
              key: ValueKey(project.id),
              padding: const EdgeInsets.only(bottom: 10),
              child: MotionReveal(
                delay: Duration(milliseconds: index.clamp(0, 4) * 35),
                child: _ProjectCard(
                  project: project,
                  progress: progress.forProject(project.id),
                  language: language,
                ),
              ),
            ),
      ],
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.progress,
    required this.language,
    this.featured = false,
  });

  final LearnProject project;
  final ProjectProgress progress;
  final LearnLanguage language;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(19),
      side: BorderSide(
        color: featured
            ? LearnArt.colorFor(project.artwork).withValues(alpha: .45)
            : AppColors.line,
      ),
    );
    final cardText = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(language.text(project.title), style: text.titleMedium),
        const SizedBox(height: 4),
        Text(
          '${project.difficulty.label(language)} · ${project.minutes} ${language.pick('min', 'মিনিট')} · ${project.parts.length} ${language.pick('parts', 'উপকরণ')}',
          style: text.bodySmall?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 4),
        Text(language.text(project.objectives.first), style: text.bodySmall),
        if (progress.checked.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            progress.completed
                ? language.pick('Completed', 'সম্পূর্ণ')
                : language.pick(
                    '${progress.checked.length} of 4 checkpoints',
                    '৪টির মধ্যে ${progress.checked.length}টি ধাপ',
                  ),
            style: text.bodySmall?.copyWith(color: AppColors.mint),
          ),
        ],
      ],
    );
    return Material(
      color: AppColors.surface,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/learn/${project.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: featured ? 84 : 70,
                  height: featured ? 86 : 66,
                  child: LearnArt(project.artwork),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: cardText),
              const SizedBox(width: 5),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.muted,
                size: 19,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
