import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/ui/app_motion.dart';
import '../../core/ui/status_visuals.dart';
import '../../core/ui/surfaces.dart';
import 'learn_catalog.dart';

/// One checkpoint question with its answers and the reason for the right one.
typedef LearnQuestion = ({
  String id,
  LearnText prompt,
  List<LearnText> options,
  int answer,
  LearnText because,
});

/// Builds checkpoint questions from a project's own validated data.
///
/// Every question and every wrong answer is drawn from the lesson's real
/// parts, pins and wires, so nothing here can contradict the circuit.
List<LearnQuestion> learnQuestionsFor(
  LearnCatalog catalog,
  LearnProject project,
) {
  final questions = <LearnQuestion>[];
  final wires = project.wires;
  final choiceOffset = project.id.codeUnits.fold(0, (sum, unit) => sum + unit);

  void addQuestion({
    required String id,
    required LearnText prompt,
    required LearnText correct,
    required List<LearnText> distractors,
    required LearnText because,
  }) {
    final answer = (choiceOffset + questions.length) % (distractors.length + 1);
    final options = [...distractors]..insert(answer, correct);
    questions.add((
      id: id,
      prompt: prompt,
      options: options,
      answer: answer,
      because: because,
    ));
  }

  // 1. Which pin does the first connection start from?
  final first = wires.first;
  final pins = project.circuit.nodes[first.from.part]!.terminals.keys.toList();
  final decoys = <String>[
    ...pins.where((pin) => pin != first.from.pin),
    ...project.circuit.nodes.entries
        .where((entry) => entry.key != first.from.part)
        .expand((entry) => entry.value.terminals.keys),
  ].take(2).toList();
  if (decoys.length == 2) {
    addQuestion(
      id: 'start-pin',
      prompt: (
        en: 'Which terminal does the first connection start from?',
        bn: 'প্রথম সংযোগটি কোন প্রান্ত থেকে শুরু হয়?',
      ),
      correct: (en: first.from.pin, bn: first.from.pin),
      distractors: [for (final pin in decoys) (en: pin, bn: pin)],
      because: (
        en: 'The first wire runs from ${first.from.part} ${first.from.pin} to ${first.to.part} ${first.to.pin}.',
        bn: 'প্রথম তারটি ${first.from.part} ${first.from.pin} থেকে ${first.to.part} ${first.to.pin} পর্যন্ত যায়।',
      ),
    );
  }

  // 2. Where does a named wire end? Tests the wiring the lesson just showed.
  if (wires.length > 1) {
    final wire = wires[1];
    final others = project.circuit.nodes.keys
        .where((part) => part != wire.to.part)
        .take(2)
        .toList();
    if (others.length == 2) {
      LearnText partLabel(String part) {
        final title = catalog.parts[project.parts[part]]!.title;
        return (en: '$part · ${title.en}', bn: '$part · ${title.bn}');
      }

      addQuestion(
        id: 'wire-end',
        prompt: (
          en: 'The wire leaving ${wire.from.part} ${wire.from.pin} connects to which component?',
          bn: '${wire.from.part} ${wire.from.pin} থেকে যাওয়া তারটি কোন উপকরণে যুক্ত হয়?',
        ),
        correct: partLabel(wire.to.part),
        distractors: [for (final part in others) partLabel(part)],
        because: (en: wire.why.en, bn: wire.why.bn),
      );
    }
  }

  // 3. A safety or polarity point, taken from the lesson's own warnings.
  if (project.safety.isNotEmpty) {
    addQuestion(
      id: 'safety',
      prompt: (
        en: 'Before you change any wiring, what should you do first?',
        bn: 'তার বদলানোর আগে প্রথমে কী করা উচিত?',
      ),
      correct: (
        en: 'Unplug USB and switch off any external supply',
        bn: 'USB খুলুন ও বাহ্যিক সাপ্লাই বন্ধ করুন',
      ),
      distractors: const [
        (
          en: 'Leave it powered so you can watch the change',
          bn: 'পরিবর্তন দেখতে চালু রাখুন',
        ),
        (en: 'Only close the Arduino IDE', bn: 'শুধু Arduino IDE বন্ধ করুন'),
      ],
      because: (en: catalog.safety.en, bn: catalog.safety.bn),
    );
  }

  return questions;
}

/// A short set of checkpoint questions with an explanation after each answer.
class LearnQuiz extends StatefulWidget {
  const LearnQuiz({
    required this.catalog,
    required this.project,
    required this.language,
    super.key,
  });

  final LearnCatalog catalog;
  final LearnProject project;
  final LearnLanguage language;

  @override
  State<LearnQuiz> createState() => _LearnQuizState();
}

class _LearnQuizState extends State<LearnQuiz> {
  late final List<LearnQuestion> _questions = learnQuestionsFor(
    widget.catalog,
    widget.project,
  );
  final _chosen = <String, int>{};

  int get _correct => _questions
      .where((question) => _chosen[question.id] == question.answer)
      .length;

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final text = Theme.of(context).textTheme;
    if (_questions.isEmpty) return const SizedBox.shrink();
    final done = _chosen.length == _questions.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                language.pick('Check yourself', 'নিজেকে যাচাই করুন'),
                style: text.titleMedium,
              ),
            ),
            if (done)
              StatusChip(
                tone: _correct == _questions.length
                    ? StatusTone.live
                    : StatusTone.waiting,
                label: language.pick(
                  '$_correct of ${_questions.length} correct',
                  '${_questions.length} টির মধ্যে $_correct টি সঠিক',
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          language.pick(
            'Answer from what the diagram showed. Every answer explains itself.',
            'ডায়াগ্রামে যা দেখলেন সেখান থেকে উত্তর দিন। প্রতিটি উত্তরের ব্যাখ্যা দেওয়া আছে।',
          ),
          style: text.bodySmall?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 10),
        for (final (index, question) in _questions.indexed) ...[
          _QuestionCard(
            number: index + 1,
            total: _questions.length,
            question: question,
            language: language,
            chosen: _chosen[question.id],
            onChoose: (value) => setState(() => _chosen[question.id] = value),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.number,
    required this.total,
    required this.question,
    required this.language,
    required this.chosen,
    required this.onChoose,
  });

  final int number, total;
  final LearnQuestion question;
  final LearnLanguage language;
  final int? chosen;
  final ValueChanged<int> onChoose;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final answered = chosen != null;
    final right = chosen == question.answer;
    return Panel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            language.pick(
              'Question $number of $total',
              '$total টির মধ্যে প্রশ্ন $number',
            ),
            style: text.bodySmall?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 4),
          Text(language.text(question.prompt), style: text.titleSmall),
          const SizedBox(height: 10),
          for (final (index, option) in question.options.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: _Option(
                label: language.text(option),
                // The right answer is only revealed once something is chosen.
                state: !answered
                    ? _OptionState.open
                    : index == question.answer
                    ? _OptionState.correct
                    : index == chosen
                    ? _OptionState.wrong
                    : _OptionState.dimmed,
                onTap: answered ? null : () => onChoose(index),
              ),
            ),
          if (answered) ...[
            const SizedBox(height: 2),
            MotionReveal(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1, right: 8),
                    child: right
                        ? const SuccessTick(celebrate: true, size: 18)
                        : Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                            color: AppColors.amber,
                          ),
                  ),
                  Expanded(
                    child: Text(
                      language.text(question.because),
                      style: text.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum _OptionState { open, correct, wrong, dimmed }

class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    required this.state,
    required this.onTap,
  });

  final String label;
  final _OptionState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = switch (state) {
      _OptionState.correct => AppColors.mint,
      _OptionState.wrong => AppColors.coral,
      _ => AppColors.line,
    };
    final shown = state == _OptionState.correct || state == _OptionState.wrong;
    return Semantics(
      button: onTap != null,
      selected: shown,
      child: AnimatedContainer(
        duration: AppMotion.duration(context, AppMotion.quick),
        curve: AppMotion.ease,
        decoration: BoxDecoration(
          color: shown ? AppColors.tint(accent, .12) : Colors.transparent,
          border: Border.all(
            color: shown ? AppColors.tintLine(accent, .4) : AppColors.line,
          ),
          borderRadius: BorderRadius.circular(AppShape.control),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppShape.control),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: state == _OptionState.dimmed
                            ? AppColors.muted
                            : AppColors.text,
                      ),
                    ),
                  ),
                  if (state == _OptionState.correct)
                    Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: AppColors.mint,
                    ),
                  if (state == _OptionState.wrong)
                    Icon(
                      Icons.cancel_rounded,
                      size: 18,
                      color: AppColors.coral,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
