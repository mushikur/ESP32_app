import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/ui/surfaces.dart';
import 'learn_catalog.dart';

class LearnPinExplorerButton extends StatelessWidget {
  const LearnPinExplorerButton({
    required this.board,
    required this.project,
    required this.language,
    super.key,
  });

  final LearnBoard board;
  final LearnProject project;
  final LearnLanguage language;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: () => showDialog<void>(
      context: context,
      builder: (context) =>
          _PinExplorer(board: board, project: project, language: language),
    ),
    icon: const Icon(Icons.developer_board_outlined),
    label: Text(language.pick('Explore board pins', 'বোর্ডের পিন দেখুন')),
  );
}

class _PinExplorer extends StatefulWidget {
  const _PinExplorer({
    required this.board,
    required this.project,
    required this.language,
  });

  final LearnBoard board;
  final LearnProject project;
  final LearnLanguage language;

  @override
  State<_PinExplorer> createState() => _PinExplorerState();
}

class _PinExplorerState extends State<_PinExplorer> {
  LearnBoardPin? _selected;

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final board = widget.board;
    final used = {
      for (final wire in widget.project.wires)
        for (final terminal in [wire.from, wire.to])
          if (widget.project.parts[terminal.part] == 'board') terminal.pin,
    };
    final allPins = board.headers.values.expand((pins) => pins);
    final selected =
        _selected ??
        allPins.firstWhere(
          (pin) => used.contains(pin.terminal),
          orElse: () => allPins.first,
        );
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(language.pick('Board pin explorer', 'বোর্ডের পিন')),
          leading: IconButton(
            tooltip: language.pick(
              'Close pin explorer',
              'পিনের তালিকা বন্ধ করুন',
            ),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ),
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight * .4,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 550),
                        child: SizedBox(
                          width: double.infinity,
                          child: Panel(
                            padding: const EdgeInsets.all(13),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${selected.header} · ${selected.mark}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  learnPinDescription(selected.role, language),
                                ),
                                if (used.contains(selected.terminal)) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    language.pick(
                                      'Used in this lesson',
                                      'এই পাঠে ব্যবহৃত',
                                    ),
                                    style: TextStyle(color: AppColors.cyan),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 490),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              board.name,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              language.text(board.orientation),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 10),
                            _PinRows(
                              board: board,
                              used: used,
                              selected: selected,
                              onSelected: (pin) =>
                                  setState(() => _selected = pin),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PinRows extends StatelessWidget {
  const _PinRows({
    required this.board,
    required this.used,
    required this.selected,
    required this.onSelected,
  });

  final LearnBoard board;
  final Set<String> used;
  final LearnBoardPin selected;
  final ValueChanged<LearnBoardPin> onSelected;

  @override
  Widget build(BuildContext context) {
    final left = board.headers['J2']!;
    final right = board.headers['J3']!;
    Widget button(LearnBoardPin pin) {
      final inLesson = used.contains(pin.terminal);
      final active = pin == selected;
      final tint = active || inLesson
          ? AppColors.cyan
          : pin.role == LearnPinRole.flash
          ? AppColors.violet
          : AppColors.muted;
      return OutlinedButton(
        key: ValueKey('board-pin-${pin.header}'),
        onPressed: () => onSelected(pin),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          backgroundColor: active
              ? AppColors.tint(AppColors.cyan, .22)
              : AppColors.surface,
          foregroundColor: tint,
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
          side: BorderSide(color: active || inLesson ? tint : AppColors.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '${pin.header.split(' · ').last}  ${pin.mark}',
            maxLines: 1,
          ),
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          top: 36,
          bottom: 19,
          child: Center(
            child: FractionallySizedBox(
              widthFactor: .4,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.tint(AppColors.blue, .12),
                  border: Border.all(
                    color: AppColors.tintLine(AppColors.blue, .30),
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 14),
                    Icon(
                      Icons.memory_rounded,
                      color: AppColors.muted,
                      size: 44,
                    ),
                    const Spacer(),
                    Container(
                      width: 42,
                      height: 18,
                      decoration: BoxDecoration(
                        color: AppColors.muted,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Column(
          children: [
            const Row(
              children: [
                Expanded(child: Center(child: Text('J2'))),
                Expanded(child: SizedBox()),
                Expanded(child: Center(child: Text('J3'))),
              ],
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < left.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(child: button(left[i])),
                    const Spacer(flex: 1),
                    Expanded(child: button(right[i])),
                  ],
                ),
              ),
            Text('USB', style: TextStyle(color: AppColors.muted)),
          ],
        ),
      ],
    );
  }
}

/// A beginner-facing explanation of what a pin is for.
String learnPinDescription(
  LearnPinRole role,
  LearnLanguage language,
) => switch (role) {
  LearnPinRole.ground => language.pick(
    'Common ground. It provides the current return path.',
    'সাধারণ গ্রাউন্ড। কারেন্ট ফেরার পথ দেয়।',
  ),
  LearnPinRole.power3v3 => language.pick(
    '3.3 V rail. In these lessons, power the board by USB and use this rail only where the circuit calls for it.',
    '৩.৩ V রেল। এই পাঠে USB দিয়ে বোর্ড চালান। সার্কিটে বলা থাকলেই এই রেল ব্যবহার করুন।',
  ),
  LearnPinRole.power5v => language.pick(
    '5 V power header. Keep external power off this pin while the board is powered by USB.',
    '৫ V পাওয়ার পিন। USB দিয়ে বোর্ড চালানোর সময় এখানে বাহ্যিক পাওয়ার দেবেন না।',
  ),
  LearnPinRole.analogInput => language.pick(
    'ADC1 input. Reads voltage and cannot drive an output.',
    'ADC1 ইনপুট। ভোল্টেজ পড়ে, আউটপুট চালাতে পারে না।',
  ),
  LearnPinRole.adc1 => language.pick(
    'GPIO with ADC1. It can read an analog voltage or work as a digital pin.',
    'ADC1-যুক্ত GPIO। অ্যানালগ ভোল্টেজ পড়তে বা ডিজিটাল পিন হিসেবে কাজ করতে পারে।',
  ),
  LearnPinRole.adc2 => language.pick(
    'GPIO with ADC2. The classic ESP32 shares ADC2 with Wi-Fi.',
    'ADC2-যুক্ত GPIO। ক্লাসিক ESP32-তে ADC2 Wi-Fi-এর সঙ্গে ভাগ হয়।',
  ),
  LearnPinRole.reset => language.pick(
    'Board enable and reset. Leave it free for these lessons.',
    'বোর্ড চালু ও রিসেট করার পিন। এই পাঠে খালি রাখুন।',
  ),
  LearnPinRole.serial => language.pick(
    'USB serial communication. Keep it free during sketch upload and Serial Monitor use.',
    'USB সিরিয়াল যোগাযোগ। স্কেচ আপলোড ও Serial Monitor ব্যবহারের সময় খালি রাখুন।',
  ),
  LearnPinRole.strap => language.pick(
    'A startup configuration pin. Leave it free for these starter circuits.',
    'চালুর সময় কনফিগারেশনের পিন। শুরুর সার্কিটে খালি রাখুন।',
  ),
  LearnPinRole.boot => language.pick(
    'BOOT pin. Pulling it low during reset selects the serial downloader.',
    'BOOT পিন। রিসেটের সময় লো করলে সিরিয়াল ডাউনলোড মোড চালু হয়।',
  ),
  LearnPinRole.flash => language.pick(
    'Reserved for onboard flash. Leave this pin disconnected.',
    'বোর্ডের ফ্ল্যাশের জন্য সংরক্ষিত। এই পিনে সংযোগ দেবেন না।',
  ),
  LearnPinRole.gpio => language.pick(
    '3.3 V GPIO. Reads digital input or drives an output when configured in code.',
    '৩.৩ V GPIO। কোডে সেট করলে ডিজিটাল ইনপুট পড়ে বা আউটপুট চালায়।',
  ),
};
