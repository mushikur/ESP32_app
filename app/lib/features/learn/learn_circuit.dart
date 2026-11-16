part of 'learn_catalog.dart';

typedef CircuitSegment = ({Offset from, Offset to});

class LearnCircuitNode {
  const LearnCircuitNode._(this.bounds, this.left, this.right, this.terminals);

  final Rect bounds;
  final List<String> left, right;
  final Map<String, Offset> terminals;
}

class LearnCircuit {
  const LearnCircuit._(
    this.size,
    this.nodes,
    this.routes,
    this.junctions,
    this._nets,
  );

  final Size size;
  final Map<String, LearnCircuitNode> nodes;
  final Map<String, List<Offset>> routes;
  final Map<String, Set<Offset>> junctions;
  final List<Set<LearnTerminal>> _nets;

  bool sharesNet(LearnTerminal first, LearnTerminal second) =>
      _nets.any((net) => net.contains(first) && net.contains(second));

  static LearnCircuit _read(Object? source, LearnProject project) {
    final data = _map(source);
    final extent = _coordinates(data['size'], 2);
    final size = Size(extent[0], extent[1]);
    if (size.width < 300 || size.height < 180) _invalid('circuit size');
    final terminals = <String, Set<String>>{};
    for (final wire in project.wires) {
      for (final end in [wire.from, wire.to]) {
        terminals.putIfAbsent(end.part, () => {}).add(end.pin);
      }
    }
    final nodeData = _map(data['nodes']);
    if (nodeData.length != terminals.length ||
        !terminals.keys.every(nodeData.containsKey)) {
      _invalid('circuit parts');
    }
    final nodes = <String, LearnCircuitNode>{};
    for (final entry in nodeData.entries) {
      final node = _readNode(_map(entry.value), terminals[entry.key]!);
      if (!(Offset.zero & size).contains(node.bounds.topLeft) ||
          !(Offset.zero & size).contains(node.bounds.bottomRight) ||
          nodes.values.any((other) => other.bounds.overlaps(node.bounds))) {
        _invalid('circuit part position');
      }
      nodes[entry.key] = node;
    }

    final bends = _map(data['bends']);
    final routes = <String, List<Offset>>{};
    final segments = <String, List<CircuitSegment>>{};
    Offset point(LearnTerminal terminal) =>
        nodes[terminal.part]!.terminals[terminal.pin]!;
    for (final wire in project.wires) {
      final points = [
        point(wire.from),
        if (bends.containsKey(wire.id)) ..._list(bends[wire.id], _point),
        point(wire.to),
      ];
      final edges = circuitSegments(points).toList();
      if (edges.any(
            (edge) =>
                edge.from == edge.to ||
                (edge.from.dx != edge.to.dx && edge.from.dy != edge.to.dy) ||
                nodes.values.any((node) => _overlapsPart(edge, node.bounds)),
          ) ||
          points.any((point) => !(Offset.zero & size).contains(point))) {
        _invalid('circuit path for ${wire.id}');
      }
      routes[wire.id] = List.unmodifiable(points);
      segments[wire.id] = edges;
    }
    if (!bends.keys.every(routes.containsKey)) _invalid('unknown circuit path');

    // Group connections through shared terminals. Crossings between separate
    // groups get no junction marker.
    final nets = <Set<LearnTerminal>>[];
    for (final wire in project.wires) {
      final net = {wire.from, wire.to};
      nets.removeWhere((other) {
        if (other.intersection(net).isEmpty) return false;
        net.addAll(other);
        return true;
      });
      nets.add(net);
    }
    final junctions = <String, Set<Offset>>{};
    for (final (index, wire) in project.wires.indexed) {
      final net = nets.firstWhere((net) => net.contains(wire.from));
      for (final other in project.wires.skip(index + 1)) {
        final a = segments[wire.id]!;
        final b = segments[other.id]!;
        if (!net.contains(other.from)) {
          if (a.any(
            (line) => b.any((other) => _collinearOverlap(line, other)),
          )) {
            _invalid('overlapping circuit paths on separate nets');
          }
          continue;
        }
        final points =
            <Offset>{
              ...routes[wire.id]!.where(
                (point) => b.any((edge) => _onSegment(point, edge)),
              ),
              ...routes[other.id]!.where(
                (point) => a.any((edge) => _onSegment(point, edge)),
              ),
            }..removeWhere(
              (p) =>
                  nodes.values.any((node) => node.terminals.containsValue(p)),
            );
        junctions.putIfAbsent(wire.id, () => {}).addAll(points);
        junctions.putIfAbsent(other.id, () => {}).addAll(points);
      }
    }
    return LearnCircuit._(
      size,
      Map.unmodifiable(nodes),
      Map.unmodifiable(routes),
      Map.unmodifiable(
        junctions.map((id, dots) => MapEntry(id, Set.unmodifiable(dots))),
      ),
      List.unmodifiable(nets.map(Set<LearnTerminal>.unmodifiable)),
    );
  }
}

LearnCircuitNode _readNode(Map<String, Object?> data, Set<String> expected) {
  final rect = _coordinates(data['rect'], 4);
  final bounds = Rect.fromLTWH(rect[0], rect[1], rect[2], rect[3]);
  List<String> pins(String side) {
    final value = data[side];
    return value is List
        ? List.unmodifiable(value.map(_string))
        : _invalid('circuit side');
  }

  final left = pins('left');
  final right = pins('right');
  final all = [...left, ...right];
  if (bounds.width < 90 ||
      bounds.height < 50 ||
      all.length != expected.length ||
      !all.toSet().containsAll(expected)) {
    _invalid('circuit terminals');
  }
  final terminals = <String, Offset>{
    for (final (x, names) in [(bounds.left, left), (bounds.right, right)])
      for (final (index, pin) in names.indexed)
        pin: Offset(
          x,
          bounds.top + bounds.height * (index + 1) / (names.length + 1),
        ),
  };
  return LearnCircuitNode._(bounds, left, right, Map.unmodifiable(terminals));
}

List<double> _coordinates(Object? value, int length) {
  if (value is! List ||
      value.length != length ||
      !value.every((item) => item is num && item >= 0 && item <= 1200)) {
    _invalid('circuit coordinates');
  }
  return value.cast<num>().map((coordinate) => coordinate.toDouble()).toList();
}

Offset _point(Object? value) {
  final pair = _coordinates(value, 2);
  return Offset(pair[0], pair[1]);
}

Iterable<CircuitSegment> circuitSegments(List<Offset> points) sync* {
  for (var i = 1; i < points.length; i++) {
    yield (from: points[i - 1], to: points[i]);
  }
}

bool _overlapsPart(CircuitSegment edge, Rect part) {
  final line = Rect.fromPoints(edge.from, edge.to);
  return line.left < part.right &&
      line.right > part.left &&
      line.top < part.bottom &&
      line.bottom > part.top;
}

bool _onSegment(Offset point, CircuitSegment edge) {
  final line = Rect.fromPoints(edge.from, edge.to);
  return point.dx >= line.left &&
      point.dx <= line.right &&
      point.dy >= line.top &&
      point.dy <= line.bottom;
}

bool _collinearOverlap(CircuitSegment a, CircuitSegment b) {
  final first = Rect.fromPoints(a.from, a.to);
  final second = Rect.fromPoints(b.from, b.to);
  return (first.width == 0 &&
          second.width == 0 &&
          first.left == second.left &&
          first.top < second.bottom &&
          first.bottom > second.top) ||
      (first.height == 0 &&
          second.height == 0 &&
          first.top == second.top &&
          first.left < second.right &&
          first.right > second.left);
}
