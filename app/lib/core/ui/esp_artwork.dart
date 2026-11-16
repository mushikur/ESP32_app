import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import 'app_motion.dart';

part 'esp_mark.dart';

class LaunchParticles extends StatelessWidget {
  const LaunchParticles({super.key});

  @override
  Widget build(BuildContext context) => DecorativeMotion(
    period: const Duration(seconds: 9),
    repeat: true,
    builder: (clock) => clock == null
        ? const SizedBox.expand()
        : RepaintBoundary(child: CustomPaint(painter: _ParticlePainter(clock))),
  );
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter(this.clock) : super(repaint: clock);

  final Animation<double> clock;
  static const _points = [
    Offset(.19, .24),
    Offset(.72, .19),
    Offset(.87, .38),
    Offset(.15, .57),
    Offset(.75, .72),
    Offset(.32, .81),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint();
    for (final (index, point) in _points.indexed) {
      final phase = math.pi * 2 * clock.value + index;
      canvas.drawCircle(
        Offset(
          size.width * point.dx + math.cos(phase) * 6,
          size.height * point.dy + math.sin(phase) * 9,
        ),
        index.isEven ? 1.8 : 1.1,
        pen
          ..color = AppColors.blue.withValues(
            alpha: .30 + .16 * math.sin(phase),
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter oldDelegate) =>
      oldDelegate.clock != clock;
}

class OrbitArtwork extends StatelessWidget {
  const OrbitArtwork({this.animate = false, this.repeat = true, super.key});

  final bool animate;
  final bool repeat;

  @override
  Widget build(BuildContext context) => DecorativeMotion(
    period: const Duration(seconds: 7),
    active: animate,
    repeat: repeat,
    builder: (clock) => ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _OrbitPainter(clock),
          child: const SizedBox.expand(),
        ),
      ),
    ),
  );
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter(this.motion) : super(repaint: motion);

  final Animation<double>? motion;

  @override
  void paint(Canvas canvas, Size size) {
    final phase = (motion?.value ?? 0) * math.pi * 2;
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(math.min(size.width, size.height) / 220);
    final glowBounds = const Rect.fromLTWH(
      -112,
      -108,
      224,
      216,
    ).shift(Offset(math.sin(phase) * 7, (1 - math.cos(phase)) * 4));
    canvas.drawOval(
      glowBounds,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x664B7DDB), Color(0x28145498), Color(0x00145498)],
        ).createShader(glowBounds),
    );

    canvas.save();
    canvas.rotate(-.35);
    final orbit = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final radius in [62.0, 83.0, 104.0]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: radius * 2,
          height: radius * 1.27,
        ),
        orbit
          ..color = AppColors.blue.withValues(alpha: radius == 83 ? .42 : .24),
      );
    }
    final nodeAngle = -.53 + phase;
    canvas.drawCircle(
      Offset(83 * math.cos(nodeAngle), 52.7 * math.sin(nodeAngle)),
      4,
      Paint()..color = AppColors.cyan,
    );
    canvas.drawCircle(
      const Offset(-76, 46),
      3,
      Paint()..color = AppColors.violet,
    );
    canvas.drawCircle(
      const Offset(48, -24),
      2.3,
      Paint()..color = AppColors.blue,
    );
    canvas.restore();

    for (final point in const [
      Offset(-76, -72),
      Offset(78, -72),
      Offset(82, 68),
      Offset(-90, 14),
      Offset(54, 82),
    ]) {
      canvas.drawCircle(point, 1.5, Paint()..color = const Color(0xFF5C81BA));
    }

    canvas.save();
    canvas.translate(0, math.sin(phase) * 5);
    canvas.rotate(-.23 + math.sin(phase) * .045);
    const chip = Rect.fromLTWH(-40, -36, 80, 72);
    const edge = Radius.circular(15);
    canvas.drawRRect(
      RRect.fromRectAndRadius(chip.shift(const Offset(2, 8)), edge),
      Paint()..color = const Color(0xFF0C1531),
    );
    final pin = Paint()
      ..color = const Color(0xFF7396D0)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    for (final x in [-22.0, -11.0, 0.0, 11.0, 22.0]) {
      canvas.drawLine(Offset(x, -43), Offset(x, -35), pin);
      canvas.drawLine(Offset(x, 38), Offset(x, 48), pin);
    }
    for (final y in [-19.0, -9.0, 1.0, 11.0, 21.0]) {
      canvas.drawLine(Offset(-48, y), Offset(-39, y), pin);
      canvas.drawLine(Offset(40, y), Offset(49, y), pin);
    }
    final body = RRect.fromRectAndRadius(chip, edge);
    canvas.drawRRect(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF28537D), Color(0xFF111C39)],
        ).createShader(chip),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..color = const Color(0xFF6F98D2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    _drawMark(canvas, Offset.zero, 1.5, _markCyan);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OrbitPainter oldDelegate) => oldDelegate.motion != motion;
}
