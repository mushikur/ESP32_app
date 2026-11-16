import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'learn_catalog.dart';

enum LearnMilestone { parts, wiring, upload, test }

enum LearnChecklist {
  parts(LearnMilestone.parts),
  wiring(LearnMilestone.wiring),
  test(LearnMilestone.test),
  practice(null);

  const LearnChecklist(this.milestone);
  final LearnMilestone? milestone;

  Set<String> ids(LearnProject project) => switch (this) {
    parts => project.parts.keys.toSet(),
    wiring || practice => project.wires.map((wire) => wire.id).toSet(),
    test => project.checks.map((check) => check.id).toSet(),
  };
}

class ProjectProgress {
  const ProjectProgress({
    this.opened,
    this.checked = const {},
    this.items = const {},
  });

  final DateTime? opened;
  final Set<LearnMilestone> checked;
  final Map<LearnChecklist, Set<String>> items;

  bool get completed => checked.length == LearnMilestone.values.length;

  Set<String> checkedItems(LearnProject project, LearnChecklist list) {
    final known = list.ids(project);
    final saved = items[list];
    if (saved != null) return saved.intersection(known);
    return checked.contains(list.milestone) ? known : {};
  }

  Map<String, Object?> toJson() => {
    'opened': opened?.toIso8601String(),
    'checked': [for (final milestone in checked) milestone.name],
    if (items.isNotEmpty)
      'items': {
        for (final entry in items.entries) entry.key.name: entry.value.toList(),
      },
  };

  factory ProjectProgress.fromJson(Map<String, Object?> data) =>
      ProjectProgress(
        opened: DateTime.tryParse(data['opened'] as String? ?? ''),
        checked: Set.unmodifiable(
          LearnMilestone.values.where(
            (milestone) =>
                (data['checked'] as List?)?.contains(milestone.name) ?? false,
          ),
        ),
        items: Map.unmodifiable({
          for (final list in LearnChecklist.values)
            if ((data['items'] as Map?)?[list.name] case final List saved)
              list: Set<String>.unmodifiable(saved.whereType<String>()),
        }),
      );
}

class LearnProgress {
  const LearnProgress({
    this.language = LearnLanguage.en,
    this.projects = const {},
    this.earnedProjects = const {},
    this.activityDays = const {},
  });

  final LearnLanguage language;
  final Map<String, ProjectProgress> projects;
  final Set<String> earnedProjects;
  final Set<int> activityDays;

  ProjectProgress forProject(String id) =>
      projects[id] ?? const ProjectProgress();

  LearnProgress _withProject(
    String id,
    ProjectProgress progress, {
    int? activityDay,
  }) => LearnProgress(
    language: language,
    projects: Map.unmodifiable({...projects, id: progress}),
    earnedProjects: progress.completed
        ? Set.unmodifiable({...earnedProjects, id})
        : earnedProjects,
    activityDays: activityDay == null
        ? activityDays
        : Set.unmodifiable({...activityDays, activityDay}),
  );

  String encode() => jsonEncode({
    'version': 1,
    'language': language.name,
    'projects': {
      for (final entry in projects.entries) entry.key: entry.value.toJson(),
    },
    if (earnedProjects.isNotEmpty) 'earnedProjects': earnedProjects.toList(),
    if (activityDays.isNotEmpty) 'activityDays': activityDays.toList(),
  });

  factory LearnProgress.decode(String source) {
    final data = jsonDecode(source) as Map<String, Object?>;
    if (data['version'] != 1) {
      throw const FormatException('Unknown learning progress version.');
    }
    final projects = Map<String, ProjectProgress>.unmodifiable({
      for (final entry in (data['projects'] as Map<String, Object?>).entries)
        entry.key: ProjectProgress.fromJson(
          entry.value as Map<String, Object?>,
        ),
    });
    return LearnProgress(
      language: data['language'] == 'bn' ? LearnLanguage.bn : LearnLanguage.en,
      projects: projects,
      earnedProjects: Set.unmodifiable({
        ...(data['earnedProjects'] as List?)?.whereType<String>() ??
            const <String>[],
        for (final entry in projects.entries)
          if (entry.value.completed) entry.key,
      }),
      activityDays: Set.unmodifiable(
        (data['activityDays'] as List?)?.whereType<int>() ?? const <int>[],
      ),
    );
  }
}

class LearnProgressStore {
  LearnProgressStore(this._preferences);

  static const key = 'learn_progress_v1';
  final SharedPreferencesAsync _preferences;

  Future<LearnProgress> load() async {
    final value = await _preferences.getString(key);
    return value == null ? const LearnProgress() : LearnProgress.decode(value);
  }

  Future<void> save(LearnProgress progress) =>
      _preferences.setString(key, progress.encode());
}

final learnProgressStoreProvider = Provider<LearnProgressStore>(
  (ref) => LearnProgressStore(SharedPreferencesAsync()),
);

final learnProgressProvider =
    AsyncNotifierProvider<LearnProgressNotifier, LearnProgress>(
      LearnProgressNotifier.new,
    );

final learnClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

// A civil-date ordinal keeps consecutive dates adjacent across DST changes.
int learnDay(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

class LearnProgressNotifier extends AsyncNotifier<LearnProgress> {
  Future<void> _writes = Future.value();

  @override
  Future<LearnProgress> build() => ref.watch(learnProgressStoreProvider).load();

  Future<void> changeLanguage(LearnLanguage language) => _update(
    (current) => LearnProgress(
      language: language,
      projects: current.projects,
      earnedProjects: current.earnedProjects,
      activityDays: current.activityDays,
    ),
  );

  Future<void> openProject(String id) => _update(
    (current) => current._withProject(
      id,
      ProjectProgress(
        opened: ref.read(learnClockProvider)().toUtc(),
        checked: current.forProject(id).checked,
        items: current.forProject(id).items,
      ),
    ),
  );

  Future<void> check(String id, LearnMilestone milestone, bool value) =>
      _update((current) {
        final project = current.forProject(id);
        final checked = {...project.checked};
        final changed = value
            ? checked.add(milestone)
            : checked.remove(milestone);
        if (!changed) return current;
        final now = ref.read(learnClockProvider)();
        return current._withProject(
          id,
          ProjectProgress(
            opened: project.opened ?? now.toUtc(),
            checked: Set.unmodifiable(checked),
            items: project.items,
          ),
          activityDay: value ? learnDay(now) : null,
        );
      });

  Future<void> checkItem(
    LearnProject project,
    LearnChecklist list,
    String id,
    bool value,
  ) {
    final known = list.ids(project);
    if (!known.contains(id)) {
      throw ArgumentError.value(id, 'id', 'Unknown checklist item');
    }
    return _update((current) {
      final previous = current.forProject(project.id);
      final items = previous.checkedItems(project, list);
      final changed = value ? items.add(id) : items.remove(id);
      if (!changed) return current;
      final now = ref.read(learnClockProvider)();
      final checked = {...previous.checked};
      final milestone = list.milestone;
      if (milestone != null) {
        if (items.length == known.length) {
          checked.add(milestone);
        } else {
          checked.remove(milestone);
        }
      }
      return current._withProject(
        project.id,
        ProjectProgress(
          opened: previous.opened ?? now.toUtc(),
          checked: Set.unmodifiable(checked),
          items: Map.unmodifiable({
            ...previous.items,
            list: Set.unmodifiable(items),
          }),
        ),
        activityDay: value && milestone != null ? learnDay(now) : null,
      );
    });
  }

  Future<void> resetPractice(String projectId) => _update((current) {
    final previous = current.forProject(projectId);
    if (!previous.items.containsKey(LearnChecklist.practice)) return current;
    return current._withProject(
      projectId,
      ProjectProgress(
        opened: previous.opened,
        checked: previous.checked,
        items: Map.unmodifiable(
          {...previous.items}..remove(LearnChecklist.practice),
        ),
      ),
    );
  });

  Future<void> _update(LearnProgress Function(LearnProgress) change) {
    final operation = _writes.then((_) async {
      if (!ref.mounted) return;
      final current = await future;
      if (!ref.mounted) return;
      final next = change(current);
      if (identical(next, current)) return;
      await ref.read(learnProgressStoreProvider).save(next);
      if (ref.mounted) state = AsyncData(next);
    });
    _writes = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }
}
