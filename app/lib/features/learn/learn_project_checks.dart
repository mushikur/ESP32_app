import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/ui/surfaces.dart';
import 'learn_catalog.dart';

class LearnTestChecklist extends StatelessWidget {
  const LearnTestChecklist({
    required this.project,
    required this.language,
    required this.checked,
    required this.onCheck,
    required this.onTroubleshoot,
    super.key,
  });

  final LearnProject project;
  final LearnLanguage language;
  final Set<String> checked;
  final void Function(String id, bool value) onCheck;
  final VoidCallback onTroubleshoot;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          language.pick(
            '${checked.length} of ${project.checks.length} results confirmed',
            '${project.checks.length}টির মধ্যে ${checked.length}টি ফল নিশ্চিত',
          ),
          style: text.titleMedium?.copyWith(color: AppColors.cyan),
        ),
        const SizedBox(height: 5),
        Text(
          language.pick(
            'Run each check on your circuit and mark the result you observe.',
            'নিজের সার্কিটে প্রতিটি পরীক্ষা করুন। যে ফল দেখেছেন সেটি চিহ্নিত করুন।',
          ),
        ),
        const SizedBox(height: 10),
        for (final check in project.checks)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Panel(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(language.text(check.title), style: text.titleMedium),
                  const SizedBox(height: 6),
                  Text(language.text(check.action)),
                  const SizedBox(height: 9),
                  Text(
                    language.pick('Expected result', 'প্রত্যাশিত ফল'),
                    style: text.labelLarge?.copyWith(color: AppColors.mint),
                  ),
                  Text(language.text(check.expected)),
                  const SizedBox(height: 5),
                  CheckboxListTile(
                    key: ValueKey('test-${check.id}'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: checked.contains(check.id),
                    title: Text(
                      language.pick(
                        'I observed this result',
                        'আমি এই ফল দেখেছি',
                      ),
                    ),
                    onChanged: (value) => onCheck(check.id, value ?? false),
                  ),
                ],
              ),
            ),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: onTroubleshoot,
            icon: const Icon(Icons.build_outlined, size: 18),
            label: Text(
              language.pick('Troubleshoot a result', 'ফলের সমস্যা সমাধান করুন'),
            ),
          ),
        ),
      ],
    );
  }
}

class LearnProjectTroubleshooting extends StatelessWidget {
  const LearnProjectTroubleshooting({
    required this.project,
    required this.language,
    required this.onWire,
    required this.onTests,
    super.key,
  });

  final LearnProject project;
  final LearnLanguage language;
  final ValueChanged<String> onWire;
  final VoidCallback onTests;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final item in project.issues)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Panel(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              leading: Icon(
                Icons.build_circle_outlined,
                color: AppColors.violet,
              ),
              title: Text(language.text(item.issue.symptom)),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              children: [
                _Diagnosis(
                  language.pick('Possible cause', 'সম্ভাব্য কারণ'),
                  language.text(item.issue.cause),
                ),
                _Diagnosis(
                  language.pick('What to check', 'যা মিলিয়ে দেখবেন'),
                  language.text(item.inspect),
                ),
                _Diagnosis(
                  language.pick('How to fix it', 'যেভাবে ঠিক করবেন'),
                  language.text(item.issue.fix),
                ),
                OutlinedButton.icon(
                  onPressed: () => onWire(item.wireId),
                  icon: const Icon(Icons.account_tree_outlined, size: 18),
                  label: Text(
                    language.pick(
                      'Show related wiring',
                      'সংশ্লিষ্ট সংযোগ দেখুন',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: onTests,
          icon: const Icon(Icons.arrow_back_rounded, size: 18),
          label: Text(
            language.pick('Back to project tests', 'প্রকল্প পরীক্ষায় ফিরুন'),
          ),
        ),
      ),
    ],
  );
}

class _Diagnosis extends StatelessWidget {
  const _Diagnosis(this.label, this.text);
  final String label, text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: AppColors.cyan),
        ),
        const SizedBox(height: 3),
        Text(text),
      ],
    ),
  );
}
