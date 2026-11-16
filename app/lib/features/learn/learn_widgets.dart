import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/ui/app_motion.dart';
import '../../core/ui/surfaces.dart';
import 'learn_catalog.dart';

class LearnProgressBar extends StatelessWidget {
  const LearnProgressBar({
    required this.fraction,
    required this.label,
    super.key,
  });

  final double fraction;
  final String label;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: fraction),
    duration: AppMotion.duration(context, AppMotion.reveal),
    curve: AppMotion.ease,
    builder: (context, value, child) => LinearProgressIndicator(
      value: value,
      minHeight: 6,
      borderRadius: BorderRadius.circular(8),
      backgroundColor: AppColors.line,
      color: AppColors.mint,
      semanticsLabel: label,
      semanticsValue: '${(fraction * 100).round()}%',
    ),
  );
}

class LearnLoadState extends StatelessWidget {
  const LearnLoadState({
    required this.language,
    required this.failed,
    required this.retry,
    super.key,
  });

  final LearnLanguage language;
  final bool failed;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => ScreenScroll(
    children: [
      EmptyPanel(
        icon: failed ? Icons.error_outline : Icons.school_outlined,
        title: failed
            ? language.pick(
                'Could not open the learning library',
                'শেখার লাইব্রেরি খোলা যায়নি',
              )
            : language.pick(
                'Opening the learning library',
                'শেখার লাইব্রেরি খোলা হচ্ছে',
              ),
        description: failed
            ? language.pick(
                'Try loading the lessons and saved progress again.',
                'পাঠ ও সংরক্ষিত অগ্রগতি আবার লোড করুন।',
              )
            : language.pick(
                'Loading lessons and your saved progress.',
                'পাঠ ও আপনার সংরক্ষিত অগ্রগতি লোড হচ্ছে।',
              ),
        action: failed
            ? OutlinedButton(
                onPressed: retry,
                child: Text(language.pick('Try again', 'আবার চেষ্টা করুন')),
              )
            : null,
      ),
    ],
  );
}

Future<void> saveLearnChange(
  BuildContext context,
  Future<void> change,
  LearnLanguage language,
) async {
  try {
    await change;
  } on Object {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          language.pick(
            'Could not save your learning progress. Try again.',
            'শেখার অগ্রগতি সংরক্ষণ করা যায়নি। আবার চেষ্টা করুন।',
          ),
        ),
      ),
    );
  }
}

void revealLearnContent(GlobalKey key) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final target = key.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: AppMotion.duration(target, AppMotion.reverse),
      curve: AppMotion.ease,
    );
  });
}
