import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import 'learn_catalog.dart';

class LearnArt extends StatelessWidget {
  const LearnArt(this.artwork, {super.key});

  final LearnArtwork artwork;

  static Color colorFor(LearnArtwork artwork) => switch (artwork) {
    LearnArtwork.blink => AppColors.cyan,
    LearnArtwork.button => AppColors.violet,
    LearnArtwork.traffic => const Color(0xFFF6BF70),
    LearnArtwork.night => AppColors.blue,
    LearnArtwork.servo => AppColors.mint,
    LearnArtwork.dual => const Color(0xFFF6BF70),
    LearnArtwork.meter => AppColors.violet,
  };

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: ExcludeSemantics(
      child: CustomPaint(
        painter: _ProjectPainter(artwork, colorFor(artwork)),
        size: Size.infinite,
      ),
    ),
  );
}

class _ProjectPainter extends CustomPainter {
  const _ProjectPainter(this.artwork, this.accent);
  final LearnArtwork artwork;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final area = Offset.zero & size;
    canvas.drawRect(
      area,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(.46, -.35),
          radius: .93,
          colors: [
            Color.lerp(AppColors.surface, accent, .27)!,
            const Color(0xFF091324),
          ],
        ).createShader(area),
    );
    final grid = Paint()..color = accent.withValues(alpha: .14);
    for (double x = 10; x < size.width; x += 12) {
      for (double y = 9; y < size.height; y += 12) {
        canvas.drawCircle(Offset(x, y), .75, grid);
      }
    }
    final scale = math.min(size.width / 190, size.height / 116);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.rotate(-.13);
    final trace = Paint()
      ..color = accent.withValues(alpha: .45)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    for (final y in [-24.0, 0.0, 24.0]) {
      canvas.drawPath(
        Path()
          ..moveTo(-80, y)
          ..lineTo(-64, y)
          ..lineTo(-50, y + 14)
          ..lineTo(63, y + 14)
          ..lineTo(76, y + 1),
        trace,
      );
      canvas.drawCircle(Offset(-82, y), 2.2, trace);
      canvas.drawCircle(Offset(78, y + 1), 2.2, trace);
    }
    _board(canvas);
    canvas.translate(30, -4);
    switch (artwork) {
      case LearnArtwork.blink:
        _led(canvas, const Offset(0, -3), 18, const Color(0xFFFF777C));
      case LearnArtwork.dual:
        _led(canvas, const Offset(-13, -15), 12, const Color(0xFFFF777C));
        _led(canvas, const Offset(19, 14), 12, AppColors.mint);
      case LearnArtwork.meter:
        final waveform = Path()
          ..moveTo(-24, 12)
          ..lineTo(-12, 12)
          ..lineTo(-3, -10)
          ..lineTo(8, 3)
          ..lineTo(18, -20)
          ..lineTo(32, -20);
        canvas.drawPath(
          waveform,
          Paint()
            ..color = accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
        canvas.drawCircle(const Offset(32, -20), 4, Paint()..color = accent);
      case LearnArtwork.button:
        _body(
          canvas,
          const Rect.fromLTWH(-22, -21, 44, 44),
          const Color(0xFF283451),
          8,
        );
        canvas.drawCircle(
          Offset.zero,
          15,
          Paint()..color = const Color(0xFF121827),
        );
        canvas.drawCircle(const Offset(0, -2), 13, Paint()..color = accent);
        canvas.drawCircle(
          const Offset(-4, -7),
          4,
          Paint()..color = Colors.white24,
        );
      case LearnArtwork.traffic:
        _body(
          canvas,
          const Rect.fromLTWH(-16, -38, 32, 75),
          const Color(0xFF1A2435),
          9,
        );
        for (final (index, color) in [
          const Color(0xFFFF777C),
          const Color(0xFFFFC769),
          AppColors.mint,
        ].indexed) {
          _led(canvas, Offset(0, -23 + index * 23), 7.5, color);
        }
      case LearnArtwork.night:
        _body(
          canvas,
          const Rect.fromLTWH(-22, -22, 44, 44),
          const Color(0xFFE6B986),
          22,
        );
        final track = Paint()
          ..color = const Color(0xFF8C513C)
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        canvas.drawPath(
          Path()
            ..moveTo(-13, 9)
            ..lineTo(-13, -8)
            ..lineTo(-6, -8)
            ..lineTo(-6, 8)
            ..lineTo(1, 8)
            ..lineTo(1, -8)
            ..lineTo(8, -8)
            ..lineTo(8, 8)
            ..lineTo(14, 8)
            ..lineTo(14, -8),
          track,
        );
      case LearnArtwork.servo:
        _body(
          canvas,
          const Rect.fromLTWH(-24, -23, 48, 46),
          const Color(0xFF306EA2),
          8,
        );
        canvas.drawCircle(
          const Offset(1, -7),
          12,
          Paint()..color = const Color(0xFF17405E),
        );
        canvas.save();
        canvas.translate(1, -7);
        canvas.rotate(.47);
        _body(
          canvas,
          const Rect.fromLTWH(-6, -28, 12, 39),
          const Color(0xFFCCE1EA),
          5,
        );
        for (final y in [-22.0, -16.0, -10.0, 0.0]) {
          canvas.drawCircle(
            Offset(0, y),
            1.5,
            Paint()..color = const Color(0xFF547483),
          );
        }
        canvas.restore();
    }
    canvas.restore();
  }

  void _board(Canvas canvas) {
    _body(
      canvas,
      const Rect.fromLTWH(-61, -31, 40, 65),
      const Color(0xFF23374C),
      5,
    );
    _body(
      canvas,
      const Rect.fromLTWH(-51, -25, 20, 25),
      const Color(0xFF91A2AB),
      3,
    );
    _body(
      canvas,
      const Rect.fromLTWH(-47, 23, 12, 15),
      const Color(0xFF9AB0B9),
      2,
    );
    canvas.drawRect(
      const Rect.fromLTWH(-46, 7, 10, 10),
      Paint()..color = const Color(0xFF0B1220),
    );
    for (var i = 0; i < 8; i++) {
      for (final x in [-57.0, -25.0]) {
        canvas.drawCircle(
          Offset(x, -23 + i * 6.5),
          1.35,
          Paint()..color = const Color(0xFFD9B876),
        );
      }
    }
    canvas.drawCircle(const Offset(-32, 15), 1.8, Paint()..color = accent);
  }

  void _body(Canvas canvas, Rect bounds, Color color, double radius) {
    final shape = RRect.fromRectAndRadius(bounds, Radius.circular(radius));
    canvas.drawRRect(
      shape.shift(const Offset(3, 5)),
      Paint()..color = const Color(0x66030A12),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(color, Colors.white, .24)!, color],
        ).createShader(bounds),
    );
  }

  void _led(Canvas canvas, Offset center, double radius, Color color) {
    final glow = Rect.fromCircle(center: center, radius: radius * 2);
    canvas.drawCircle(
      center,
      radius * 2,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: .45), color.withValues(alpha: 0)],
        ).createShader(glow),
    );
    canvas.drawCircle(center, radius, Paint()..color = color);
    canvas.drawCircle(
      center - Offset(radius * .26, radius * .32),
      radius * .34,
      Paint()..color = Colors.white54,
    );
  }

  @override
  bool shouldRepaint(_ProjectPainter oldDelegate) =>
      oldDelegate.artwork != artwork;
}
