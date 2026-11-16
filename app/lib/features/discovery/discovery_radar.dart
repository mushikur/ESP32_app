import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/ui/app_motion.dart';
import '../../core/ui/surfaces.dart';

class DiscoveryRadar extends StatelessWidget {
  const DiscoveryRadar({required this.active, super.key});

  final bool active;

  @override
  Widget build(BuildContext context) => DecorativeMotion(
    period: const Duration(milliseconds: 2800),
    active: active,
    repeat: true,
    builder: (clock) {
      if (clock == null) return const IconTile(Icons.radar_rounded);
      return ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _RadarPainter(clock),
            child: SizedBox.square(
              dimension: 64,
              child: Center(
                child: Icon(
                  Icons.radar_rounded,
                  color: AppColors.cyan,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _RadarPainter extends CustomPainter {
  _RadarPainter(this.clock) : super(repaint: clock);

  final Animation<double> clock;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width * .47;
    final sweep = clock.value * math.pi * 2 - math.pi / 2;
    final bounds = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(center, radius, Paint()..color = AppColors.elevated);
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.blue.withValues(alpha: .32);
    for (final fraction in [.43, .73, 1.0]) {
      canvas.drawCircle(center, radius * fraction, pen);
    }
    const angle = math.pi * .55;
    canvas.drawArc(
      bounds,
      sweep - angle,
      angle,
      true,
      Paint()
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: angle,
          transform: GradientRotation(sweep - angle),
          colors: [Colors.transparent, AppColors.cyan.withValues(alpha: .34)],
        ).createShader(bounds),
    );
    pen.color = AppColors.cyan.withValues(alpha: .76);
    final tip = Offset(math.cos(sweep), math.sin(sweep));
    canvas.drawLine(center + tip * 8, center + tip * radius, pen);
    for (final (index, angle) in [-1.2, .65, 2.6].indexed) {
      final position = Offset(math.cos(angle), math.sin(angle));
      final light = (.5 + .5 * math.cos(sweep - angle)) * .54;
      canvas.drawCircle(
        center + position * radius * (.58 + index * .1),
        1.45,
        Paint()..color = AppColors.cyan.withValues(alpha: light),
      );
    }
  }

  @override
  bool shouldRepaint(_RadarPainter oldDelegate) => oldDelegate.clock != clock;
}
