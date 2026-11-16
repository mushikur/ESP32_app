import 'learn_catalog.dart';
import 'learn_progress.dart';

enum LearnBadge {
  firstCircuit(
    'First Circuit',
    'প্রথম সার্কিট',
    'Finish one project.',
    'একটি প্রকল্প শেষ করুন।',
  ),
  ledMaster(
    'LED Master',
    'LED মাস্টার',
    'Finish three lighting projects.',
    'আলোর তিনটি প্রকল্প শেষ করুন।',
  ),
  sensorExplorer(
    'Sensor Explorer',
    'সেন্সর অভিযাত্রী',
    'Finish a sensor project.',
    'একটি সেন্সর প্রকল্প শেষ করুন।',
  ),
  servoStarter(
    'Servo Starter',
    'সার্ভোর শুরু',
    'Finish a motor or servo project.',
    'একটি মোটর বা সার্ভো প্রকল্প শেষ করুন।',
  ),
  espCreator(
    'ESP32 Creator',
    'ESP32 নির্মাতা',
    'Finish five projects.',
    'পাঁচটি প্রকল্প শেষ করুন।',
  );

  const LearnBadge(this.en, this.bn, this.goalEn, this.goalBn);
  final String en, bn, goalEn, goalBn;
  String title(LearnLanguage language) => language.pick(en, bn);
  String goal(LearnLanguage language) => language.pick(goalEn, goalBn);
}

typedef LearnSkill = ({LearnCategory category, int completed, int total});

class LearnRewards {
  const LearnRewards._(
    this.xp,
    this.streak,
    this.goalMet,
    this.badges,
    this.skills,
  );

  static const xpPerProject = 100;
  final int xp, streak;
  final bool goalMet;
  final Set<LearnBadge> badges;
  final List<LearnSkill> skills;

  factory LearnRewards.calculate(
    LearnCatalog catalog,
    LearnProgress progress,
    DateTime now,
  ) {
    final projects = catalog.projects.values;
    final earned = projects
        .where((project) => progress.earnedProjects.contains(project.id))
        .toList();
    int awardsIn(LearnCategory category) =>
        earned.where((project) => project.categories.contains(category)).length;

    final today = learnDay(now);
    final goalMet = progress.activityDays.contains(today);
    var day = goalMet ? today : today - 1;
    var streak = 0;
    while (progress.activityDays.contains(day)) {
      streak++;
      day--;
    }

    final skills = <LearnSkill>[];
    for (final category in [
      LearnCategory.lighting,
      LearnCategory.sensors,
      LearnCategory.motors,
    ]) {
      final entries = projects
          .where((project) => project.categories.contains(category))
          .toList();
      if (entries.isEmpty) continue;
      skills.add((
        category: category,
        completed: entries
            .where((project) => progress.forProject(project.id).completed)
            .length,
        total: entries.length,
      ));
    }
    return LearnRewards._(
      earned.length * xpPerProject,
      streak,
      goalMet,
      Set.unmodifiable({
        if (earned.isNotEmpty) LearnBadge.firstCircuit,
        if (awardsIn(LearnCategory.lighting) >= 3) LearnBadge.ledMaster,
        if (awardsIn(LearnCategory.sensors) > 0) LearnBadge.sensorExplorer,
        if (awardsIn(LearnCategory.motors) > 0) LearnBadge.servoStarter,
        if (earned.length >= 5) LearnBadge.espCreator,
      }),
      List.unmodifiable(skills),
    );
  }
}
