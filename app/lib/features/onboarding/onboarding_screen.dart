import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_theme.dart';
import '../../core/ui/esp_artwork.dart';
import '../../core/ui/surfaces.dart';
import '../devices/device_card.dart';
import 'onboarding_store.dart';

const _slides = [
  (
    label: 'THE LOCAL WORKSPACE',
    title: 'One home for your ESP32s.',
    description: 'Bring your lights, sensors, and custom projects into one workspace on your local Wi-Fi.',
  ),
  (
    label: 'YOUR INVENTORY',
    title: 'A dashboard for each project.',
    description: 'Compatible devices can describe their own controls. Existing projects can use a configured API profile.',
  ),
  (
    label: 'CONNECT WITH CONFIDENCE',
    title: 'Local by design.',
    description: 'ESP IoT starts on your Wi-Fi and works without a cloud account. Pair devices you recognize and trust.',
  ),
];

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({required this.replay, super.key});

  final bool replay;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  int _index = 0;
  bool _saving = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _showPage(int index) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(index);
    } else {
      _pages.animateToPage(
        index,
        duration: const Duration(milliseconds: 330),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _finish() async {
    if (_saving) return;
    if (widget.replay && context.canPop()) {
      context.pop();
      return;
    }
    setState(() => _saving = true);
    var saved = true;
    try {
      await ref.read(onboardingStoreProvider).markComplete();
    } on Exception {
      saved = false;
    }
    if (!mounted) return;
    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tour completion could not be saved. The tour may appear next time.',
          ),
        ),
      );
    }
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final last = _index == _slides.length - 1;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return AnnotatedRegion(
      value: AppTheme.overlays,
      child: Scaffold(
        body: ScreenCanvas(
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 12, 14, 0),
                      child: Row(
                        children: [
                          const EspMark(size: 40),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'ESP IoT',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          TextButton(
                            onPressed: _saving ? null : _finish,
                            child: Text(widget.replay ? 'Close' : 'Skip'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: PageView.builder(
                        controller: _pages,
                        onPageChanged: (index) =>
                            setState(() => _index = index),
                        itemCount: _slides.length,
                        itemBuilder: (context, index) =>
                            _Slide(index: index, active: index == _index),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 10, 22, 18),
                      child: Column(
                        children: [
                          Semantics(
                            label: 'Introduction page',
                            value: [_index + 1, _slides.length].join(' of '),
                            excludeSemantics: true,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(_slides.length, (index) {
                                final current = index == _index;
                                return AnimatedContainer(
                                  duration: reducedMotion
                                      ? Duration.zero
                                      : const Duration(milliseconds: 220),
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  width: current ? 24 : 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: current
                                        ? AppColors.cyan
                                        : AppColors.line,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                );
                              }),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              if (_index > 0) ...[
                                IconButton.outlined(
                                  tooltip: 'Previous page',
                                  onPressed: _saving
                                      ? null
                                      : () => _showPage(_index - 1),
                                  icon: const Icon(Icons.arrow_back_rounded),
                                ),
                                const SizedBox(width: 10),
                              ],
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _saving
                                      ? null
                                      : (last
                                            ? _finish
                                            : () => _showPage(_index + 1)),
                                  icon: const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 20,
                                  ),
                                  iconAlignment: IconAlignment.end,
                                  label: Text(
                                    last
                                        ? (widget.replay
                                              ? 'Done'
                                              : 'Open ESP IoT')
                                        : 'Next',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({required this.index, required this.active});

  final int index;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final slide = _slides[index];
    final text = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final artworkHeight = math
            .min(constraints.maxHeight * .55, constraints.maxHeight - 220)
            .clamp(90.0, 320.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (index == 1)
                ConstrainedBox(
                  constraints: BoxConstraints(minHeight: artworkHeight),
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: SizedBox(
                        width: 340,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Eyebrow(
                              'ILLUSTRATIVE DEVICE CARD',
                              color: AppColors.violet,
                            ),
                            SizedBox(height: 10),
                            DeviceCard(
                              name: 'ESP32 project',
                              category: 'Example controller',
                              presence: DevicePresence.unknown,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              else
                SizedBox(
                  height: artworkHeight,
                  child: OrbitArtwork(animate: active),
                ),
              Eyebrow(slide.label),
              const SizedBox(height: 10),
              Semantics(
                header: true,
                child: Text(slide.title, style: text.displaySmall),
              ),
              const SizedBox(height: 12),
              Text(
                slide.description,
                style: text.bodyLarge?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        );
      },
    );
  }
}
