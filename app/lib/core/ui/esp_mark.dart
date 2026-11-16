part of 'esp_artwork.dart';

enum EspLogoMotion { still, entrance, launch }

/// The brand tile. With motion it draws its traces in, then floats gently
/// while its halo breathes, a soft light crosses the plate, and the node pulses.
class AnimatedEspIoTLogo extends StatelessWidget {
  const AnimatedEspIoTLogo({
    this.size = 44,
    this.motion = EspLogoMotion.entrance,
    super.key,
  });

  final double size;
  final EspLogoMotion motion;

  @override
  Widget build(BuildContext context) => DecorativeMotion(
    period: const Duration(milliseconds: 5600),
    active: motion != EspLogoMotion.still,
    repeat: motion == EspLogoMotion.launch,
    builder: (clock) {
      if (clock == null) return EspMark(size: size);
      final loops = motion == EspLogoMotion.launch;
      final spill = size * .22;
      return Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned(
            left: -spill,
            top: -spill,
            right: -spill,
            bottom: -spill,
            child: ExcludeSemantics(
              child: RepaintBoundary(
                child: CustomPaint(painter: _HaloPainter(clock, loops)),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: clock,
            child: RepaintBoundary(
              child: EspMark(size: size, motion: clock, loops: loops),
            ),
            builder: (context, child) {
              final t = clock.value;
              final life = _life(t, loops);
              final breath = math.sin(t * math.pi * 4);
              final arrival = AppMotion.ease.transform((t * 5).clamp(0.0, 1.0));
              return Transform.translate(
                offset: Offset(0, -breath * size * .028 * life),
                child: Transform.scale(
                  scale: loops ? 1 : .92 + .08 * arrival,
                  child: child,
                ),
              );
            },
          ),
        ],
      );
    },
  );
}

/// A one-shot entrance settles back to rest; the launch loop keeps moving.
double _life(double t, bool loops) =>
    loops ? 1 : math.sin(math.pi * t).clamp(0.0, 1.0);

class _HaloPainter extends CustomPainter {
  _HaloPainter(this.clock, this.loops) : super(repaint: clock);

  final Animation<double> clock;
  final bool loops;

  @override
  void paint(Canvas canvas, Size size) {
    final life = _life(clock.value, loops);
    if (life <= .001) return;
    final breath = math.sin(clock.value * math.pi * 4);
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            _markCyan.withValues(alpha: (.20 + .10 * breath) * life),
            _markCyan.withValues(alpha: 0),
          ],
          stops: const [.4, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_HaloPainter oldDelegate) => oldDelegate.clock != clock;
}

class EspMark extends StatelessWidget {
  const EspMark({this.size = 44, this.motion, this.loops = false, super.key});

  final double size;

  /// Drives the trace reveal, node pulse, and light sweep when present.
  final Animation<double>? motion;
  final bool loops;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: _MarkPainter(motion, loops),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.motion, this.loops) : super(repaint: motion);

  final Animation<double>? motion;
  final bool loops;

  @override
  void paint(Canvas canvas, Size size) {
    final t = motion?.value;
    if (t == null) {
      paintEspMark(canvas, size.width);
      return;
    }
    paintEspMark(
      canvas,
      size.width,
      draw: loops
          ? 1
          : Curves.easeInOutCubic.transform((t * 3.2).clamp(0.0, 1.0)),
      node: .5 + .5 * math.sin(t * math.pi * 6),
      sweep: (t * 2) % 1,
      sweepStrength: _life(t, loops),
    );
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) =>
      oldDelegate.motion != motion || oldDelegate.loops != loops;
}

const _markCyan = Color(0xFF7CEFFA);
const _markBlue = Color(0xFF6F9BFF);
const _markViolet = Color(0xFFC9BDFF);

/// Paints the brand tile into a [size] square at the canvas origin.
///
/// [draw] reveals the traces from 0 to 1, [node] brightens the solid node, and
/// [sweep] moves a soft highlight across the plate.
void paintEspMark(
  Canvas canvas,
  double size, {
  double draw = 1,
  double node = 0,
  double? sweep,
  double sweepStrength = 1,
}) {
  canvas.save();
  canvas.scale(size / 48);
  final bounds = const Rect.fromLTWH(0, 0, 48, 48).deflate(.5);
  final frame = RRect.fromRectAndRadius(bounds, const Radius.circular(12.5));
  canvas.drawRRect(
    frame,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF17365A), Color(0xFF0E1630)],
      ).createShader(bounds),
  );
  if (sweep != null && sweepStrength > 0) {
    canvas.save();
    canvas.clipRRect(frame);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: .13 * sweepStrength),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(-30 + 110 * sweep, 0, 30, 48)),
    );
    canvas.restore();
  }
  canvas.drawRRect(
    frame,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF3F6392), Color(0xFF1D2C4E)],
      ).createShader(bounds)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1,
  );
  _drawMark(canvas, const Offset(24, 24), 1, null, draw: draw, node: node);
  canvas.restore();
}

/// The E-trace symbol on a 48 unit grid centred on [center].
///
/// A null [color] uses the brand gradient. A colour draws a flat single-ink
/// version for use inside illustrations.
void _drawMark(
  Canvas canvas,
  Offset center,
  double scale,
  Color? color, {
  double draw = 1,
  double node = 0,
}) {
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.scale(scale);
  final shader = color == null
      ? const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_markCyan, _markBlue],
        ).createShader(const Rect.fromLTRB(-10, -14, 11, 14))
      : null;
  Paint ink(double width) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = width;
    if (shader != null) {
      paint.shader = shader;
    } else {
      paint.color = color!;
    }
    return paint;
  }

  final spine = Path()
    ..moveTo(5.3, -11.5)
    ..lineTo(-5.5, -11.5)
    ..quadraticBezierTo(-9.5, -11.5, -9.5, -7.5)
    ..lineTo(-9.5, 7.5)
    ..quadraticBezierTo(-9.5, 11.5, -5.5, 11.5)
    ..lineTo(5.3, 11.5);
  if (draw >= 1) {
    canvas.drawPath(spine, ink(3.2));
    canvas.drawLine(const Offset(-9.5, 0), const Offset(-1.5, 0), ink(3.2));
  } else {
    // Grow the spine outward from its middle, then extend the short arm.
    final metric = spine.computeMetrics().first;
    final half = metric.length / 2;
    final reach = half * (draw / .7).clamp(0.0, 1.0);
    canvas.drawPath(metric.extractPath(half - reach, half + reach), ink(3.2));
    final arm = ((draw - .35) / .4).clamp(0.0, 1.0);
    if (arm > 0) {
      canvas.drawLine(
        const Offset(-9.5, 0),
        Offset(-9.5 + 8 * arm, 0),
        ink(3.2),
      );
    }
  }
  final pads = ((draw - .62) / .38).clamp(0.0, 1.0);
  if (pads > 0) {
    for (final y in const [-11.5, 11.5]) {
      canvas.drawCircle(Offset(8.2, y), 2.9 * pads, ink(2.2));
    }
    if (node > 0 && color == null) {
      canvas.drawCircle(
        const Offset(4.4, 0),
        3.1 + 3.2 * node,
        Paint()..color = _markViolet.withValues(alpha: .22 * (1 - node)),
      );
    }
    canvas.drawCircle(
      const Offset(4.4, 0),
      3.1 * pads,
      Paint()..color = color ?? _markViolet,
    );
  }
  canvas.restore();
}
