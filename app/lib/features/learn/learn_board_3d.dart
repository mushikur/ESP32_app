import 'dart:math' as math;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/ui/app_motion.dart';
import '../../core/ui/surfaces.dart';
import 'learn_catalog.dart';
import 'learn_pin_explorer.dart';

/// A rotatable view of the lesson board with its real pin headers.
///
/// Geometry is projected by hand rather than through a 3D engine: the board is
/// a small set of flat faces, which keeps it cheap enough for a mid-range
/// phone while still letting a beginner see which physical side a pin is on.
class LearnBoard3D extends StatefulWidget {
  const LearnBoard3D({
    required this.board,
    required this.project,
    required this.language,
    super.key,
  });

  final LearnBoard board;
  final LearnProject project;
  final LearnLanguage language;

  @override
  State<LearnBoard3D> createState() => _LearnBoard3DState();
}

class _LearnBoard3DState extends State<LearnBoard3D> {
  // Yaw turns the board around its long axis; pitch tips it toward the viewer.
  double _yaw = 0;
  double _pitch = .72;
  double _zoom = 1;
  LearnBoardPin? _selected;
  List<_PinHit> _hits = const [];

  Set<String> get _usedHeaders => {
    for (final wire in widget.project.wires)
      for (final terminal in [wire.from, wire.to])
        if (widget.project.parts[terminal.part] == 'board')
          if (widget.board.pinout[terminal.pin] case final pin?) pin.header,
  };

  void _drag(DragUpdateDetails details) {
    setState(() {
      _yaw = (_yaw + details.delta.dx * .010).clamp(-.9, .9);
      _pitch = (_pitch - details.delta.dy * .010).clamp(.25, 1.4);
      _selected = null;
    });
  }

  void _tap(Offset point) {
    // Only prefer the closer face when two projected pins overlap.
    _PinHit? best;
    var nearestDistance = 16.0 * 16;
    for (final hit in _hits) {
      final distance = (hit.at - point).distanceSquared;
      if (distance < nearestDistance ||
          (distance == nearestDistance &&
              (best == null || hit.depth > best.depth))) {
        best = hit;
        nearestDistance = distance;
      }
    }
    setState(() => _selected = best?.pin);
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final text = Theme.of(context).textTheme;
    final selected = _selected;
    final usedHeaders = _usedHeaders;
    return Panel(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            language.pick('Board in 3D', 'ত্রিমাত্রিক বোর্ড'),
            style: text.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            language.pick(
              'Drag to turn the board. Tap a pin to read what it does. Pins this project uses are highlighted.',
              'বোর্ড ঘোরাতে টানুন। পিনে ট্যাপ করে কাজ জানুন। এই প্রকল্পে ব্যবহৃত পিনগুলো আলাদা রঙে আছে।',
            ),
            style: text.bodySmall?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppShape.well),
            child: ColoredBox(
              color: AppColors.sunken,
              child: AspectRatio(
                aspectRatio: 1.35,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: _drag,
                  onTapUp: (details) => _tap(details.localPosition),
                  child: CustomPaint(
                    key: const ValueKey('learn-board-preview'),
                    painter: _BoardPainter(
                      board: widget.board,
                      yaw: _yaw,
                      pitch: _pitch,
                      zoom: _zoom,
                      usedHeaders: usedHeaders,
                      selected: selected,
                      onLayout: (hits) => _hits = hits,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                tooltip: language.pick('Zoom out', 'ছোট করুন'),
                onPressed: _zoom > .7
                    ? () => setState(() => _zoom = (_zoom - .2).clamp(.7, 1.8))
                    : null,
                icon: const Icon(Icons.remove),
              ),
              IconButton(
                tooltip: language.pick('Zoom in', 'বড় করুন'),
                onPressed: _zoom < 1.8
                    ? () => setState(() => _zoom = (_zoom + .2).clamp(.7, 1.8))
                    : null,
                icon: const Icon(Icons.add),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() {
                  _yaw = 0;
                  _pitch = .72;
                  _zoom = 1;
                  _selected = null;
                }),
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: Text(language.pick('Reset view', 'ভিউ রিসেট')),
              ),
            ],
          ),
          if (selected != null)
            MotionReveal(
              key: ValueKey(selected.header),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.tint(AppColors.cyan, .10),
                  border: Border.all(
                    color: AppColors.tintLine(AppColors.cyan, .28),
                  ),
                  borderRadius: BorderRadius.circular(AppShape.well),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${selected.header} · ${selected.mark}',
                      style: text.titleSmall?.copyWith(color: AppColors.cyan),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      learnPinDescription(selected.role, language),
                      style: text.bodySmall,
                    ),
                    if (usedHeaders.contains(selected.header)) ...[
                      const SizedBox(height: 4),
                      Text(
                        language.pick(
                          'This project uses this pin.',
                          'এই প্রকল্পে এই পিনটি ব্যবহার হয়।',
                        ),
                        style: text.bodySmall?.copyWith(color: AppColors.mint),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else
            Text(
              language.pick('No pin selected.', 'কোনো পিন বাছাই করা হয়নি।'),
              style: text.bodySmall?.copyWith(color: AppColors.muted),
            ),
        ],
      ),
    );
  }
}

typedef _PinHit = ({LearnBoardPin pin, Offset at, double depth});

/// Colours that separate power, ground and signal at a glance.
Color _roleColor(LearnPinRole role) => switch (role) {
  LearnPinRole.ground => AppColors.muted,
  LearnPinRole.power3v3 || LearnPinRole.power5v => AppColors.coral,
  LearnPinRole.analogInput ||
  LearnPinRole.adc1 ||
  LearnPinRole.adc2 => AppColors.violet,
  LearnPinRole.serial || LearnPinRole.reset => AppColors.amber,
  LearnPinRole.flash ||
  LearnPinRole.strap ||
  LearnPinRole.boot => AppColors.line,
  LearnPinRole.gpio => AppColors.cyan,
};

class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.board,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.usedHeaders,
    required this.selected,
    required this.onLayout,
  });

  final LearnBoard board;
  final double yaw, pitch, zoom;
  final Set<String> usedHeaders;
  final LearnBoardPin? selected;
  final ValueChanged<List<_PinHit>> onLayout;

  // Board dimensions in arbitrary units; the DevKitC is roughly 2.3:1.
  static const _halfLength = 54.0;
  static const _halfWidth = 23.0;
  static const _thickness = 2.6;

  /// Projects a board-space point to the canvas with a simple perspective.
  Offset _project(Size size, double x, double y, double z) {
    final cosYaw = math.cos(yaw), sinYaw = math.sin(yaw);
    final cosPitch = math.cos(pitch), sinPitch = math.sin(pitch);
    final rx = x * cosYaw - y * sinYaw;
    final ry = x * sinYaw + y * cosYaw;
    final depth = ry * cosPitch - z * sinPitch;
    final height = ry * sinPitch + z * cosPitch;
    final scale = size.width / 138 * zoom * (1 + depth / 900);
    return size.center(Offset.zero) + Offset(rx * scale, -height * scale * .9);
  }

  double _depthOf(double x, double y, double z) {
    final ry = x * math.sin(yaw) + y * math.cos(yaw);
    return ry * math.cos(pitch) - z * math.sin(pitch);
  }

  @override
  void paint(Canvas canvas, Size size) {
    Offset top(double x, double y) => _project(size, x, y, _thickness);
    Offset bottom(double x, double y) => _project(size, x, y, 0);

    final corners = [
      (-_halfLength, -_halfWidth),
      (_halfLength, -_halfWidth),
      (_halfLength, _halfWidth),
      (-_halfLength, _halfWidth),
    ];

    // Side walls first, so the top face always covers them.
    for (var i = 0; i < 4; i++) {
      final a = corners[i];
      final b = corners[(i + 1) % 4];
      canvas.drawPath(
        Path()..addPolygon([
          top(a.$1, a.$2),
          top(b.$1, b.$2),
          bottom(b.$1, b.$2),
          bottom(a.$1, a.$2),
        ], true),
        Paint()..color = const Color(0xFF13233B),
      );
    }

    final face = Path()
      ..addPolygon([for (final c in corners) top(c.$1, c.$2)], true);
    canvas.drawPath(
      face,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.tint(AppColors.blue, .26),
            AppColors.tint(AppColors.blue, .12),
          ],
        ).createShader(face.getBounds()),
    );
    canvas.drawPath(
      face,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = AppColors.tintLine(AppColors.blue, .4),
    );

    // The shield can, USB connector and antenna, so the board is recognisable.
    _quad(canvas, size, -34, -13, 16, 26, const Color(0xFF9FB3CE));
    _quad(canvas, size, -52, -7, 9, 14, const Color(0xFF6C809A));
    _quad(canvas, size, 44, -8, 12, 16, const Color(0xFF42536B));

    final hits = <_PinHit>[];
    final headers = board.headers.entries.toList();
    for (final (headerIndex, entry) in headers.indexed) {
      final pins = entry.value;
      // J2 runs along one long edge, J3 along the other.
      final y = headerIndex == 0 ? -_halfWidth + 3.5 : _halfWidth - 3.5;
      for (final (index, pin) in pins.indexed) {
        final x =
            -_halfLength +
            6 +
            (index * (_halfLength * 2 - 12) / (pins.length - 1));
        final base = _project(size, x, y, _thickness + .4);
        final head = _project(size, x, y, _thickness + 4.4);
        final depth = _depthOf(x, y, _thickness);
        final isUsed = usedHeaders.contains(pin.header);
        final isSelected = selected?.header == pin.header;
        final color = _roleColor(pin.role);
        canvas.drawLine(
          base,
          head,
          Paint()
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round
            ..color = const Color(0xFFB9A06A),
        );
        if (isSelected || isUsed) {
          canvas.drawCircle(
            head,
            isSelected ? 7.5 : 6,
            Paint()..color = color.withValues(alpha: isSelected ? .34 : .20),
          );
        }
        canvas.drawCircle(
          head,
          3.1,
          Paint()..color = isUsed || isSelected ? color : AppColors.line,
        );
        if (isSelected) {
          canvas.drawCircle(
            head,
            6.5,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.8
              ..color = color,
          );
          _label(canvas, pin.mark, head - const Offset(0, 17), color);
        }
        hits.add((pin: pin, at: head, depth: depth));
      }
    }
    onLayout(hits);
  }

  void _quad(
    Canvas canvas,
    Size size,
    double x,
    double y,
    double width,
    double height,
    Color color,
  ) {
    canvas.drawPath(
      Path()..addPolygon([
        _project(size, x, y, _thickness + .6),
        _project(size, x + width, y, _thickness + .6),
        _project(size, x + width, y + height, _thickness + .6),
        _project(size, x, y + height, _thickness + .6),
      ], true),
      Paint()..color = color.withValues(alpha: .55),
    );
  }

  void _label(Canvas canvas, String text, Offset at, Color color) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at - Offset(painter.width / 2, painter.height / 2));
    painter.dispose();
  }

  @override
  bool shouldRepaint(_BoardPainter oldDelegate) =>
      oldDelegate.yaw != yaw ||
      oldDelegate.pitch != pitch ||
      oldDelegate.zoom != zoom ||
      oldDelegate.selected != selected ||
      oldDelegate.board != board ||
      !setEquals(oldDelegate.usedHeaders, usedHeaders);
}
