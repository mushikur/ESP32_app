import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import 'learn_catalog.dart';

const _canvas = Color(0xFF0A1424);

Color learnWireColor(String color) => switch (color) {
  'red' => const Color(0xFFFF848C),
  'green' => AppColors.mint,
  'yellow' => const Color(0xFFFFCF76),
  'violet' => AppColors.violet,
  'black' => const Color(0xFFBAC7D8),
  _ => AppColors.cyan,
};

class LearnWiringDiagram extends StatefulWidget {
  const LearnWiringDiagram({
    required this.project,
    required this.language,
    required this.activeWire,
    this.onWire,
    required this.onPart,
    required this.inspected,
    required this.inspectedPart,
    this.visibleWires,
    this.prompt,
    this.traceOverride,
    this.pathPulse = 0,
    this.viewerKey = const ValueKey('wiring-diagram'),
    this.showZoomControls = true,
    super.key,
  });

  final LearnProject project;
  final LearnLanguage language;
  final String? activeWire;
  final ValueChanged<String>? onWire;
  final void Function(String part, String? pin) onPart;
  final LearnTerminal? inspected;
  final String? inspectedPart;
  final Set<String>? visibleWires;
  final String? prompt;

  /// Replaces the built-in reveal with an externally driven 0..1 progress,
  /// so a playback controller can draw a wire at its own pace.
  final double? traceOverride;

  /// Decorative 0..1 highlight along the recorded wire paths.
  /// Zero leaves the circuit still.
  final double pathPulse;

  /// Identifies this diagram's viewport; distinct per diagram on a page.
  final Key viewerKey;
  final bool showZoomControls;

  @override
  State<LearnWiringDiagram> createState() => _LearnWiringDiagramState();
}

class _LearnWiringDiagramState extends State<LearnWiringDiagram> {
  final _transform = TransformationController();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _zoom(Size viewport, double amount) {
    final current = _transform.value.getMaxScaleOnAxis();
    final scale = (current * amount).clamp(1.0, 4.0).toDouble();
    final center = viewport.center(Offset.zero);
    final scene = _transform.toScene(center);
    final x = (center.dx - scene.dx * scale).clamp(
      viewport.width * (1 - scale),
      0.0,
    );
    final y = (center.dy - scene.dy * scale).clamp(
      viewport.height * (1 - scale),
      0.0,
    );
    _transform.value = Matrix4.identity()
      ..translateByDouble(x.toDouble(), y.toDouble(), 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  void _inspect(Offset point) {
    final circuit = widget.project.circuit;
    for (final entry in circuit.nodes.entries) {
      for (final terminal in entry.value.terminals.entries) {
        if ((point - terminal.value).distance <= 12) {
          widget.onPart(entry.key, terminal.key);
          return;
        }
      }
      if (entry.value.bounds.contains(point)) {
        widget.onPart(entry.key, null);
        return;
      }
    }
    final onWire = widget.onWire;
    if (onWire == null) return;
    String? closest;
    var distance = 11.0;
    for (final entry in circuit.routes.entries) {
      if (widget.visibleWires?.contains(entry.key) == false) continue;
      for (final edge in circuitSegments(entry.value)) {
        final box = Rect.fromPoints(edge.from, edge.to);
        final x = point.dx.clamp(box.left, box.right).toDouble();
        final y = point.dy.clamp(box.top, box.bottom).toDouble();
        final nearest = (point - Offset(x, y)).distance;
        if (nearest < distance) {
          distance = nearest;
          closest = entry.key;
        }
      }
    }
    if (closest != null) onWire(closest);
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final project = widget.project;
    final circuit = project.circuit;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(
          constraints.maxWidth,
          (constraints.maxWidth * .64).clamp(200.0, 340.0).toDouble(),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: ColoredBox(
                color: _canvas,
                child: SizedBox.fromSize(
                  size: viewport,
                  child: InteractiveViewer(
                    key: widget.viewerKey,
                    transformationController: _transform,
                    maxScale: 4,
                    child: FittedBox(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) => _inspect(details.localPosition),
                        excludeFromSemantics: true,
                        child: SizedBox.fromSize(
                          size: circuit.size,
                          child: widget.traceOverride != null
                              ? CustomPaint(
                                  painter: _CircuitPainter(
                                    project,
                                    widget.activeWire,
                                    widget.inspected,
                                    widget.inspectedPart,
                                    widget.visibleWires,
                                    widget.prompt != null &&
                                        widget.activeWire == null,
                                    widget.traceOverride!,
                                    widget.pathPulse,
                                  ),
                                )
                              : TweenAnimationBuilder<double>(
                                  key: ValueKey((
                                    widget.activeWire,
                                    widget.prompt,
                                  )),
                                  tween: Tween(begin: 0, end: 1),
                                  curve: Curves.easeOutCubic,
                                  duration:
                                      MediaQuery.disableAnimationsOf(context)
                                      ? Duration.zero
                                      : const Duration(milliseconds: 560),
                                  builder: (context, trace, child) =>
                                      CustomPaint(
                                        painter: _CircuitPainter(
                                          project,
                                          widget.activeWire,
                                          widget.inspected,
                                          widget.inspectedPart,
                                          widget.visibleWires,
                                          widget.prompt != null &&
                                              widget.activeWire == null,
                                          trace,
                                          widget.pathPulse,
                                        ),
                                      ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.showZoomControls)
              Wrap(
                alignment: WrapAlignment.end,
                children: [
                  IconButton(
                    tooltip: language.pick('Zoom out', 'ছোট করুন'),
                    onPressed: () => _zoom(viewport, .75),
                    icon: const Icon(Icons.remove),
                  ),
                  IconButton(
                    tooltip: language.pick('Zoom in', 'বড় করুন'),
                    onPressed: () => _zoom(viewport, 1.35),
                    icon: const Icon(Icons.add),
                  ),
                  IconButton(
                    tooltip: language.pick('Fit circuit', 'পুরো সার্কিট দেখুন'),
                    onPressed: () => _transform.value = Matrix4.identity(),
                    icon: const Icon(Icons.fit_screen_rounded),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _CircuitPainter extends CustomPainter {
  const _CircuitPainter(
    this.project,
    this.active,
    this.inspected,
    this.inspectedPart,
    this.visibleWires,
    this.pulse,
    this.trace,
    this.pathPulse,
  );
  final LearnProject project;
  final String? active;
  final LearnTerminal? inspected;
  final String? inspectedPart;
  final Set<String>? visibleWires;
  final bool pulse;
  final double trace;
  final double pathPulse;

  @override
  void paint(Canvas canvas, Size size) {
    final circuit = project.circuit;
    final grid = Paint()..color = const Color(0xFF26364B);
    for (double x = 12; x < size.width; x += 18) {
      for (double y = 12; y < size.height; y += 18) {
        canvas.drawCircle(Offset(x, y), 1, grid);
      }
    }
    final visible = project.wires
        .where((wire) => visibleWires?.contains(wire.id) ?? true)
        .toList();
    LearnWire? selected;
    for (final wire in visible) {
      if (wire.id == active) {
        selected = wire;
      } else {
        _drawWire(canvas, wire, false);
      }
    }
    if (selected != null) _drawWire(canvas, selected, true);
    final dotCounts = <Offset, int>{};
    if (visibleWires != null) {
      for (final wire in visible) {
        for (final dot in circuit.junctions[wire.id] ?? const <Offset>{}) {
          dotCounts.update(dot, (value) => value + 1, ifAbsent: () => 1);
        }
      }
    }
    Iterable<Offset> dotsFor(String? id) =>
        (circuit.junctions[id] ?? const <Offset>{}).where(
          (dot) => visibleWires == null || (dotCounts[dot] ?? 0) >= 2,
        );
    final activeDots = dotsFor(active).toSet();
    for (final wire in visible) {
      final tint = learnWireColor(wire.color);
      for (final dot in dotsFor(
        wire.id,
      ).where((dot) => !activeDots.contains(dot))) {
        canvas.drawCircle(
          dot,
          5,
          Paint()..color = Color.lerp(_canvas, tint, .52)!,
        );
      }
    }
    if (selected != null) {
      for (final dot in activeDots) {
        canvas.drawCircle(
          dot,
          5.5,
          Paint()..color = learnWireColor(selected.color),
        );
      }
    }
    for (final entry in circuit.nodes.entries) {
      _drawNode(canvas, entry.key, entry.value, selected);
    }
    if (pathPulse > 0) _drawPathPulse(canvas, visible);
  }

  void _drawPathPulse(Canvas canvas, List<LearnWire> wires) {
    final tint = AppColors.cyan;
    for (final wire in wires) {
      final path = Path()..addPolygon(project.circuit.routes[wire.id]!, false);
      final metric = path.computeMetrics().first;
      const spacing = 56.0;
      final count = (metric.length / spacing).ceil().clamp(1, 24);
      for (var i = 0; i < count; i++) {
        final at = ((i + pathPulse) / count) * metric.length;
        final position = metric.getTangentForOffset(at)?.position;
        if (position == null) continue;
        canvas.drawCircle(
          position,
          3.4,
          Paint()..color = tint.withValues(alpha: .9),
        );
        canvas.drawCircle(
          position,
          7,
          Paint()..color = tint.withValues(alpha: .18),
        );
      }
    }
  }

  void _drawWire(Canvas canvas, LearnWire wire, bool selected) {
    final points = project.circuit.routes[wire.id]!;
    final route = Path()..addPolygon(points, false);
    final tint = learnWireColor(wire.color);
    Paint stroke(Color color, double width) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = width;
    canvas.drawPath(route, stroke(_canvas, selected ? 12 : 9));
    canvas.drawPath(
      route,
      stroke(
        Color.lerp(_canvas, tint, selected ? .8 : .52)!,
        selected ? 5 : 3.5,
      ),
    );
    if (selected) {
      final metric = route.computeMetrics().first;
      final revealed = metric.extractPath(0, metric.length * trace);
      canvas.drawPath(revealed, stroke(tint.withValues(alpha: .23), 13));
      canvas.drawPath(revealed, stroke(tint, 6));
    }
  }

  void _drawNode(
    Canvas canvas,
    String id,
    LearnCircuitNode node,
    LearnWire? selected,
  ) {
    final bounds = node.bounds;
    final kind = project.parts[id];
    final focus = inspectedPart == id;
    final border = focus ? AppColors.violet : const Color(0xFF39516C);
    final shape = RRect.fromRectAndRadius(bounds, const Radius.circular(12));
    canvas.drawRRect(shape, Paint()..color = const Color(0xFF15253B));
    canvas.drawRRect(
      shape,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final title = switch (kind) {
      'board' => 'ESP32',
      'resistor330' => '$id  330 Ω',
      'resistor10k' => '$id  10 kΩ',
      'ldr' => '$id  LDR',
      'supply' => '$id  5 V DC',
      'servo' => '$id  FS90',
      'button' => '$id  NO',
      _ => id,
    };
    _text(
      canvas,
      title,
      Offset(bounds.center.dx, bounds.top + 5),
      AppColors.text,
      centered: true,
    );
    _drawSymbol(canvas, kind, bounds.center, board: kind == 'board');
    for (final entry in node.terminals.entries) {
      final terminal = (part: id, pin: entry.key);
      final chosen = selected?.from == terminal || selected?.to == terminal;
      final tint = inspected == terminal
          ? AppColors.violet
          : chosen
          ? learnWireColor(selected!.color)
          : const Color(0xFF91A9C2);
      if (pulse && inspected == terminal) {
        canvas.drawCircle(
          entry.value,
          11 + 12 * trace,
          Paint()
            ..color = tint.withValues(alpha: .15 + .55 * (1 - trace))
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
      canvas.drawCircle(entry.value, 8, Paint()..color = _canvas);
      canvas.drawCircle(entry.value, 5.5, Paint()..color = tint);
      final isLeft = node.left.contains(entry.key);
      _text(
        canvas,
        entry.key.startsWith('GPIO')
            ? 'IO${entry.key.substring(4)}'
            : entry.key,
        entry.value + Offset(isLeft ? 12 : -12, -9),
        chosen ? tint : AppColors.muted,
        right: !isLeft,
        fontSize: 13,
      );
    }
  }

  void _drawSymbol(
    Canvas canvas,
    String? kind,
    Offset center, {
    required bool board,
  }) {
    final ink = Paint()
      ..color = const Color(0xFF8AA5C3)
      ..strokeWidth = 2.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    void line(double x, double y, double a, double b) =>
        canvas.drawLine(center + Offset(x, y), center + Offset(a, b), ink);
    if (board || kind == 'servo' || kind == 'supply') {
      final chip = center + Offset(board ? -28 : 19, 0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: chip, width: 45, height: 36),
          const Radius.circular(6),
        ),
        ink,
      );
      canvas.drawRect(
        Rect.fromCenter(center: chip, width: 20, height: 15),
        ink,
      );
    } else if (kind == 'button') {
      line(-19, 5, -9, 5);
      line(9, 5, 19, 5);
      line(-9, 5, 8, -6);
    } else if (kind?.endsWith('_led') ?? false) {
      ink.color = switch (kind) {
        'green_led' => AppColors.mint,
        'yellow_led' => const Color(0xFFFFCF76),
        _ => const Color(0xFFFF848C),
      };
      canvas.drawPath(
        Path()..addPolygon([
          center + const Offset(-9, -8),
          center + const Offset(-9, 8),
          center + const Offset(7, 0),
        ], true),
        ink,
      );
      line(7, -8, 7, 8);
      line(12, -5, 19, -11);
      line(14, 2, 21, -4);
    } else {
      canvas.drawRect(
        Rect.fromCenter(center: center, width: 30, height: 13),
        ink,
      );
      line(-21, 0, -15, 0);
      line(15, 0, 21, 0);
      if (kind == 'ldr') {
        line(13, -11, 8, -6);
        line(20, -11, 15, -6);
      }
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset origin,
    Color color, {
    bool right = false,
    bool centered = false,
    double fontSize = 15,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      origin -
          Offset(
            right
                ? painter.width
                : centered
                ? painter.width / 2
                : 0,
            0,
          ),
    );
    painter.dispose();
  }

  @override
  bool shouldRepaint(_CircuitPainter oldDelegate) =>
      oldDelegate.project != project ||
      oldDelegate.active != active ||
      oldDelegate.inspected != inspected ||
      oldDelegate.inspectedPart != inspectedPart ||
      oldDelegate.visibleWires != visibleWires ||
      oldDelegate.pulse != pulse ||
      oldDelegate.trace != trace ||
      oldDelegate.pathPulse != pathPulse;
}
