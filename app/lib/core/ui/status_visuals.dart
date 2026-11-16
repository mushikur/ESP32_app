import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import 'app_motion.dart';

/// How a device or connection is doing, reduced to the four states the UI
/// needs to look different for.
enum StatusTone { live, waiting, idle, fault }

extension StatusToneColor on StatusTone {
  Color get color => switch (this) {
    StatusTone.live => AppColors.mint,
    StatusTone.waiting => AppColors.cyan,
    StatusTone.idle => AppColors.muted,
    StatusTone.fault => AppColors.coral,
  };
}

/// A small status light.
///
/// A steady state plays one short pulse when it arrives and then rests, so the
/// eye is drawn to a change without a loop running forever. Only
/// [StatusTone.waiting] keeps animating, because something really is in
/// progress while it shows.
class StatusDot extends StatelessWidget {
  const StatusDot(this.tone, {this.size = 10, super.key});

  final StatusTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final waiting = tone == StatusTone.waiting;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size * 2.2,
        child: DecorativeMotion(
          // Re-keying on the tone replays the arrival pulse on every change.
          key: ValueKey(tone),
          period: Duration(milliseconds: waiting ? 1800 : 900),
          repeat: waiting,
          builder: (clock) => CustomPaint(
            painter: _StatusDotPainter(clock, tone.color, tone, size),
          ),
        ),
      ),
    );
  }
}

class _StatusDotPainter extends CustomPainter {
  _StatusDotPainter(this.clock, this.color, this.tone, this.dot)
    : super(repaint: clock);

  final Animation<double>? clock;
  final Color color;
  final StatusTone tone;
  final double dot;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = dot / 2;
    final t = clock?.value ?? 1;
    if (clock != null) {
      // A ring travelling outward reads as reaching for the device.
      final spread = Curves.easeOut.transform(t);
      canvas.drawCircle(
        center,
        radius + (size.shortestSide / 2 - radius) * spread,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = color.withValues(alpha: .55 * (1 - spread)),
      );
    }
    canvas.drawCircle(
      center,
      radius * 1.9,
      Paint()
        ..color = color.withValues(alpha: tone == StatusTone.idle ? .14 : .22),
    );
    canvas.drawCircle(center, radius, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_StatusDotPainter oldDelegate) =>
      oldDelegate.clock != clock ||
      oldDelegate.color != color ||
      oldDelegate.tone != tone;
}

/// A status label: a dot, the state, and optional supporting detail.
class StatusChip extends StatelessWidget {
  const StatusChip({
    required this.tone,
    required this.label,
    this.detail,
    super.key,
  });

  final StatusTone tone;
  final String label;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final color = tone.color;
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: detail == null ? label : '$label. $detail',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(7, 5, 11, 5),
        decoration: BoxDecoration(
          color: AppColors.tint(color, .12),
          border: Border.all(color: AppColors.tintLine(color, .30)),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusDot(tone, size: 8),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                detail == null ? label : '$label · $detail',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A shimmering placeholder used while real content loads.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({this.height = 14, this.width, this.radius = 8, super.key});

  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: DecorativeMotion(
      period: const Duration(milliseconds: 1400),
      repeat: true,
      builder: (clock) => SizedBox(
        height: height,
        width: width,
        child: CustomPaint(painter: _SkeletonPainter(clock, radius)),
      ),
    ),
  );
}

class _SkeletonPainter extends CustomPainter {
  _SkeletonPainter(this.clock, this.radius) : super(repaint: clock);

  final Animation<double>? clock;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final area = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(area, Radius.circular(radius));
    canvas.drawRRect(
      shape,
      Paint()..color = AppColors.tint(AppColors.blue, .09),
    );
    final t = clock?.value;
    if (t == null) return;
    canvas.save();
    canvas.clipRRect(shape);
    final band = size.width * .45;
    canvas.drawRect(
      area,
      Paint()
        ..shader =
            LinearGradient(
              colors: [
                AppColors.blue.withValues(alpha: 0),
                AppColors.blue.withValues(alpha: .13),
                AppColors.blue.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromLTWH(
                -band + (size.width + band * 2) * t,
                0,
                band,
                size.height,
              ),
            ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SkeletonPainter oldDelegate) =>
      oldDelegate.clock != clock;
}

/// Shows a brief tick when [celebrate] turns true, for a confirmed action.
class SuccessTick extends StatelessWidget {
  const SuccessTick({required this.celebrate, this.size = 20, super.key});

  final bool celebrate;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: DecorativeMotion(
        period: AppMotion.celebration,
        active: celebrate,
        builder: (clock) => clock == null
            ? Icon(Icons.check_rounded, size: size, color: AppColors.mint)
            : AnimatedBuilder(
                animation: clock,
                builder: (context, _) =>
                    CustomPaint(painter: _TickPainter(clock.value)),
              ),
      ),
    ),
  );
}

class _TickPainter extends CustomPainter {
  const _TickPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final draw = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    final path = Path()
      ..moveTo(size.width * .2, size.height * .54)
      ..lineTo(size.width * .43, size.height * .76)
      ..lineTo(size.width * .81, size.height * .26);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * draw),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = size.width * .13
        ..color = AppColors.mint,
    );
  }

  @override
  bool shouldRepaint(_TickPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// The large connection indicator at the top of a device screen.
///
/// Like [StatusDot], only the waiting state loops; the others pulse once on
/// arrival and rest.
class ConnectionBeacon extends StatelessWidget {
  const ConnectionBeacon({required this.tone, this.size = 44, super.key});

  final StatusTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = tone.color;
    final waiting = tone == StatusTone.waiting;
    final icon = switch (tone) {
      StatusTone.live => Icons.link_rounded,
      StatusTone.waiting => Icons.sensors_rounded,
      StatusTone.idle => Icons.portable_wifi_off_rounded,
      StatusTone.fault => Icons.error_outline_rounded,
    };
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: DecorativeMotion(
          key: ValueKey(tone),
          period: Duration(milliseconds: waiting ? 1700 : 1000),
          repeat: waiting,
          builder: (clock) => CustomPaint(
            painter: _BeaconPainter(clock, color, tone),
            child: Center(
              child: Icon(icon, color: color, size: size * .48),
            ),
          ),
        ),
      ),
    );
  }
}

class _BeaconPainter extends CustomPainter {
  _BeaconPainter(this.clock, this.color, this.tone) : super(repaint: clock);

  final Animation<double>? clock;
  final Color color;
  final StatusTone tone;

  @override
  void paint(Canvas canvas, Size size) {
    final area = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(
      area,
      Radius.circular(size.shortestSide * .31),
    );
    if (clock != null) {
      final spread = Curves.easeOut.transform(clock!.value);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          area.inflate(size.shortestSide * .22 * spread),
          Radius.circular(size.shortestSide * (.31 + .2 * spread)),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color.withValues(alpha: .5 * (1 - spread)),
      );
    }
    canvas.drawRRect(shape, Paint()..color = AppColors.tint(color, .12));
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.tintLine(color, .30),
    );
  }

  @override
  bool shouldRepaint(_BeaconPainter oldDelegate) =>
      oldDelegate.clock != clock ||
      oldDelegate.color != color ||
      oldDelegate.tone != tone;
}
