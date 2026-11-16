import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_theme.dart';
import '../../core/ui/app_motion.dart';
import '../../core/ui/surfaces.dart';
import 'learn_catalog.dart';
import 'learn_progress.dart';
import 'learn_rewards.dart';
import 'learn_widgets.dart';

class LearnRewardSummary extends StatelessWidget {
  const LearnRewardSummary({
    required this.catalog,
    required this.progress,
    required this.rewards,
    super.key,
  });

  final LearnCatalog catalog;
  final LearnProgress progress;
  final LearnRewards rewards;

  @override
  Widget build(BuildContext context) {
    final language = progress.language;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 5,
          children: [
            Chip(
              avatar: Icon(Icons.bolt_rounded, color: AppColors.cyan, size: 18),
              label: MotionValue(
                identity: rewards.xp,
                child: Text('${rewards.xp} XP'),
              ),
            ),
            Chip(
              avatar: Icon(
                Icons.local_fire_department_rounded,
                color: AppColors.violet,
                size: 18,
              ),
              label: Text(
                language.pick(
                  '${rewards.streak}-day streak',
                  '${rewards.streak} দিনের ধারাবাহিকতা',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          rewards.goalMet
              ? language.pick('Daily goal met', 'আজকের লক্ষ্য পূরণ হয়েছে')
              : language.pick(
                  'Daily goal · Check off one learning step',
                  'আজকের লক্ষ্য · শেখার একটি ধাপ চিহ্নিত করুন',
                ),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: rewards.goalMet ? AppColors.mint : AppColors.muted,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                animationStyle: AppMotion.dialog(context),
                builder: (context) =>
                    _Achievements(rewards: rewards, language: language),
              ),
              icon: const Icon(Icons.emoji_events_outlined, size: 18),
              label: Text(language.pick('Achievements', 'অর্জন')),
            ),
            TextButton.icon(
              onPressed: () => _openProjects(context),
              icon: const Icon(Icons.bookmark_outline, size: 18),
              label: Text(language.pick('My Projects', 'আমার প্রকল্প')),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openProjects(BuildContext context) async {
    final language = progress.language;
    final projects = catalog.projects.values.where((project) {
      final saved = progress.forProject(project.id);
      return saved.opened != null ||
          saved.completed ||
          saved.items.isNotEmpty ||
          saved.checked.isNotEmpty ||
          progress.earnedProjects.contains(project.id);
    }).toList();
    final selected = await showDialog<String>(
      context: context,
      animationStyle: AppMotion.dialog(context),
      builder: (context) => AlertDialog(
        title: Text(language.pick('My Projects', 'আমার প্রকল্প')),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: projects.isEmpty
                ? Text(
                    language.pick(
                      'Open a lesson to add it here.',
                      'এখানে যোগ করতে একটি পাঠ খুলুন।',
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final project in projects)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            progress.forProject(project.id).completed
                                ? Icons.task_alt
                                : Icons.bookmark_outline,
                            color: AppColors.mint,
                          ),
                          title: Text(language.text(project.title)),
                          subtitle: Text(
                            progress.forProject(project.id).completed
                                ? language.pick('Completed', 'সম্পূর্ণ')
                                : language.pick(
                                    'Continue learning',
                                    'শেখা চালিয়ে যান',
                                  ),
                          ),
                          onTap: () => Navigator.of(context).pop(project.id),
                        ),
                    ],
                  ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(language.pick('Close', 'বন্ধ করুন')),
          ),
        ],
      ),
    );
    if (selected != null && context.mounted) context.push('/learn/$selected');
  }
}

class _Achievements extends StatelessWidget {
  const _Achievements({required this.rewards, required this.language});

  final LearnRewards rewards;
  final LearnLanguage language;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(language.pick('Achievements', 'অর্জন')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                language.pick(
                  '${rewards.xp} XP earned',
                  '${rewards.xp} XP অর্জিত',
                ),
                style: text.titleMedium?.copyWith(color: AppColors.cyan),
              ),
              const SizedBox(height: 8),
              for (final badge in LearnBadge.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: _BadgeRow(
                    badge: badge,
                    earned: rewards.badges.contains(badge),
                    language: language,
                  ),
                ),
              if (rewards.skills.isNotEmpty) ...[
                const SizedBox(height: 14),
                SectionHeading(
                  language.pick('Skill progress', 'দক্ষতার অগ্রগতি'),
                ),
                for (final skill in rewards.skills) ...[
                  const SizedBox(height: 10),
                  Text(skill.category.label(language), style: text.titleMedium),
                  Text(
                    language.pick(
                      '${skill.completed} of ${skill.total} projects complete',
                      '${skill.total}টির মধ্যে ${skill.completed}টি প্রকল্প সম্পূর্ণ',
                    ),
                  ),
                  const SizedBox(height: 5),
                  LearnProgressBar(
                    fraction: skill.completed / skill.total,
                    label: skill.category.label(language),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(language.pick('Close', 'বন্ধ করুন')),
        ),
      ],
    );
  }
}

class _BadgeRow extends StatelessWidget {
  const _BadgeRow({
    required this.badge,
    required this.earned,
    required this.language,
  });
  final LearnBadge badge;
  final bool earned;
  final LearnLanguage language;

  @override
  Widget build(BuildContext context) {
    final (icon, accent) = switch (badge) {
      LearnBadge.firstCircuit => (Icons.bolt_rounded, AppColors.cyan),
      LearnBadge.ledMaster => (
        Icons.lightbulb_outline_rounded,
        AppColors.amber,
      ),
      LearnBadge.sensorExplorer => (Icons.sensors, AppColors.violet),
      LearnBadge.servoStarter => (Icons.settings_outlined, AppColors.mint),
      LearnBadge.espCreator => (Icons.emoji_events_outlined, AppColors.blue),
    };
    final text = Theme.of(context).textTheme;
    return Panel(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          MotionPulse(
            active: earned,
            child: IconTile(
              icon,
              color: earned ? accent : AppColors.muted,
              size: 39,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(badge.title(language), style: text.titleMedium),
                Text(badge.goal(language), style: text.bodySmall),
                Text(
                  earned
                      ? language.pick('Earned', 'অর্জিত')
                      : language.pick('In progress', 'চলছে'),
                  style: text.bodySmall?.copyWith(
                    color: earned ? accent : AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LearnCompletionPanel extends StatelessWidget {
  const LearnCompletionPanel({
    required this.project,
    required this.language,
    required this.next,
    required this.animate,
    super.key,
  });

  final LearnProject project;
  final LearnLanguage language;
  final LearnProject? next;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final upcoming = next;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.tint(AppColors.cyan, .20), AppColors.surface],
        ),
        border: Border.all(color: AppColors.mint.withValues(alpha: .42)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: .72, end: 1),
                duration: animate
                    ? AppMotion.duration(context, AppMotion.celebration)
                    : Duration.zero,
                curve: Curves.easeOutBack,
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: IconTile(
                  Icons.emoji_events_rounded,
                  color: AppColors.mint,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      language.pick(
                        'You finished ${project.title.en}',
                        '${project.title.bn} শেষ করেছেন',
                      ),
                      style: text.titleMedium,
                    ),
                    Text(
                      language.pick(
                        '${LearnRewards.xpPerProject} XP earned',
                        '${LearnRewards.xpPerProject} XP অর্জিত',
                      ),
                      style: text.bodySmall?.copyWith(color: AppColors.mint),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (upcoming != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => context.push('/learn/${upcoming.id}'),
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: Text(
                language.pick(
                  'Build next · ${upcoming.title.en}',
                  'পরের প্রকল্প · ${upcoming.title.bn}',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
