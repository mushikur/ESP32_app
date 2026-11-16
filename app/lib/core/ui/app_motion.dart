import 'package:flutter/material.dart';

abstract final class AppMotion {
  static const quick = Duration(milliseconds: 150);
  static const standard = Duration(milliseconds: 230);
  static const reverse = Duration(milliseconds: 170);
  static const reveal = Duration(milliseconds: 320);
  static const celebration = Duration(milliseconds: 480);
  static const ease = Curves.easeOutCubic;

  static bool enabled(BuildContext context) =>
      !MediaQuery.disableAnimationsOf(context) &&
      TickerMode.valuesOf(context).enabled;

  static Duration duration(BuildContext context, Duration duration) =>
      enabled(context) ? duration : Duration.zero;

  static AnimationStyle dialog(BuildContext context) => enabled(context)
      ? const AnimationStyle(
          duration: standard,
          reverseDuration: reverse,
          curve: ease,
        )
      : AnimationStyle.noAnimation;

  static Widget page(Animation<double> animation, Widget child) {
    final eased = animation.drive(CurveTween(curve: ease));
    return FadeTransition(
      opacity: eased,
      child: SlideTransition(
        position: eased.drive(
          Tween(begin: const Offset(0, .025), end: Offset.zero),
        ),
        child: child,
      ),
    );
  }
}

/// Stops decorative tickers while the application is in the background.
class MotionLifecycle extends StatefulWidget {
  const MotionLifecycle({required this.child, super.key});

  final Widget child;

  @override
  State<MotionLifecycle> createState() => _MotionLifecycleState();
}

class _MotionLifecycleState extends State<MotionLifecycle> {
  bool _visible = true;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () => _setVisible(false),
      onPause: () => _setVisible(false),
      onShow: () => _setVisible(true),
      onResume: () => _setVisible(true),
    );
  }

  void _setVisible(bool visible) {
    if (_visible != visible) setState(() => _visible = visible);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      TickerMode(enabled: _visible, child: widget.child);
}

/// Supplies a painter with a clock only while its decoration is visible.
class DecorativeMotion extends StatefulWidget {
  const DecorativeMotion({
    required this.period,
    required this.builder,
    this.active = true,
    this.repeat = false,
    super.key,
  });

  final Duration period;
  final Widget Function(Animation<double>? motion) builder;
  final bool active;
  final bool repeat;

  @override
  State<DecorativeMotion> createState() => _DecorativeMotionState();
}

class _DecorativeMotionState extends State<DecorativeMotion>
    with SingleTickerProviderStateMixin {
  late final _clock = AnimationController(vsync: this, duration: widget.period);

  bool get _enabled => widget.active && AppMotion.enabled(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant DecorativeMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period != widget.period ||
        oldWidget.repeat != widget.repeat) {
      _clock
        ..reset()
        ..duration = widget.period;
    }
    if (!oldWidget.active && widget.active) _clock.reset();
    _sync();
  }

  void _sync() {
    if (!_enabled) {
      _clock.stop();
    } else if (!_clock.isAnimating) {
      if (widget.repeat) {
        _clock.repeat();
      } else if (!_clock.isCompleted) {
        _clock.forward();
      }
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(_enabled ? _clock : null);
}

class MotionReveal extends StatelessWidget {
  const MotionReveal({
    required this.child,
    this.delay = Duration.zero,
    super.key,
  });

  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final enabled = AppMotion.enabled(context);
    final duration = AppMotion.reveal + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: enabled ? duration : Duration.zero,
      curve: Interval(
        delay.inMicroseconds / duration.inMicroseconds,
        1,
        curve: AppMotion.ease,
      ),
      builder: (context, value, child) {
        final progress = enabled ? value : 1.0;
        return Transform.translate(
          offset: Offset(0, 8 * (1 - progress)),
          transformHitTests: false,
          child: Opacity(opacity: .68 + .32 * progress, child: child),
        );
      },
      child: child,
    );
  }
}

/// Animates display-only changes while retaining a single semantic value.
class MotionValue extends StatelessWidget {
  const MotionValue({required this.identity, required this.child, super.key});

  final Object? identity;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!AppMotion.enabled(context)) return child;
    return AnimatedSwitcher(
      duration: AppMotion.quick,
      switchInCurve: AppMotion.ease,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [
          for (final item in previous)
            Positioned.fill(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: IgnorePointer(child: ExcludeSemantics(child: item)),
              ),
            ),
          ?current,
        ],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: animation.drive(
            Tween(begin: const Offset(0, .12), end: Offset.zero),
          ),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(identity), child: child),
    );
  }
}

class MotionPulse extends StatelessWidget {
  const MotionPulse({required this.child, required this.active, super.key});

  final Widget child;
  final bool active;

  @override
  Widget build(BuildContext context) => DecorativeMotion(
    period: const Duration(milliseconds: 1150),
    active: active,
    builder: (clock) => clock == null
        ? child
        : AnimatedBuilder(
            animation: clock,
            child: child,
            builder: (context, child) => Transform.scale(
              scale:
                  1 +
                  .07 *
                      Curves.easeInOut.transform(
                        clock.value < .5
                            ? clock.value * 2
                            : (1 - clock.value) * 2,
                      ),
              child: child,
            ),
          ),
  );
}
