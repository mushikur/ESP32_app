import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/protocol/strict_json.dart';

part 'learn_circuit.dart';

enum LearnLanguage { en, bn }

typedef LearnText = ({String en, String bn});
typedef LearnPin = ({String header, String mark});
typedef LearnPart = ({LearnText title, LearnText about, Set<String> pins});
typedef LearnTerminal = ({String part, String pin});
typedef LearnWire = ({
  LearnTerminal from,
  LearnTerminal to,
  String color,
  LearnText why,
});
typedef LearnCodeNote = ({
  int firstLine,
  int lastLine,
  String anchor,
  LearnText title,
  LearnText text,
});
typedef LearnIssue = ({LearnText symptom, LearnText cause, LearnText fix});
typedef LearnTestCheck = ({
  String id,
  LearnText title,
  LearnText action,
  LearnText expected,
});
typedef LearnProjectIssue = ({
  LearnIssue issue,
  LearnText inspect,
  String wireId,
});

enum LearnSetupStage {
  install,
  preferences,
  boards,
  connect,
  boardPort,
  libraries,
  sketch,
  upload,
  serial,
}

typedef LearnSetupStep = ({
  LearnSetupStage stage,
  LearnText title,
  LearnText text,
});

extension LearnConnectionIdentity on LearnWire {
  String get id => '${from.part}.${from.pin}>${to.part}.${to.pin}';
}

extension LearnTranslation on LearnLanguage {
  String pick(String en, String bn) => this == LearnLanguage.en ? en : bn;
  String text(LearnText value) => pick(value.en, value.bn);
}

enum LearnCategory {
  beginner('Beginner Projects', 'শুরুর প্রকল্প'),
  lighting('LED & Lighting', 'LED ও আলো'),
  sensors('Sensors', 'সেন্সর'),
  smartHome('Smart Home', 'স্মার্ট হোম'),
  motors('Motors & Robotics', 'মোটর ও রোবটিক্স'),
  displays('Displays', 'ডিসপ্লে'),
  wifi('Wi-Fi & IoT', 'Wi-Fi ও IoT'),
  advanced('Advanced Projects', 'উন্নত প্রকল্প');

  const LearnCategory(this.en, this.bn);
  final String en, bn;
  String label(LearnLanguage language) => language.pick(en, bn);
}

enum LearnDifficulty {
  beginner('Beginner', 'শুরুর স্তর'),
  easy('Easy', 'সহজ'),
  intermediate('Intermediate', 'মাঝারি'),
  advanced('Advanced', 'উন্নত');

  const LearnDifficulty(this.en, this.bn);
  final String en, bn;
  String label(LearnLanguage language) => language.pick(en, bn);
}

enum LearnArtwork { blink, button, traffic, night, servo, dual, meter }

final learnCatalogProvider = FutureProvider<LearnCatalog>(
  (ref) => LearnCatalog.load(rootBundle),
);

class LearnCatalog {
  LearnCatalog._(
    this.board,
    this.parts,
    this.setup,
    this.uploadIssues,
    this.safety,
    this.projects,
  );

  final LearnBoard board;
  final Map<String, LearnPart> parts;
  final List<LearnSetupStep> setup;
  final List<LearnIssue> uploadIssues;
  final LearnText safety;
  final Map<String, LearnProject> projects;

  static const assetDirectory = 'assets/learn';

  static Future<LearnCatalog> load(AssetBundle assets) async {
    final catalog = _json(
      await assets.loadString('$assetDirectory/catalog.json'),
    );
    if (catalog['version'] != 1) _invalid('catalog version');
    final board = LearnBoard._(_map(catalog['board']));
    final parts = Map<String, LearnPart>.unmodifiable({
      for (final entry in _map(catalog['parts']).entries)
        entry.key: _part(_map(entry.value)),
    });
    final boardPart = parts['board'];
    if (boardPart == null ||
        boardPart.pins.length != board.pinout.length ||
        !boardPart.pins.containsAll(board.pinout.keys)) {
      _invalid('board part pinout');
    }
    final ids = _list(catalog['projects'], _string);
    if (ids.toSet().length != ids.length ||
        !ids.every(RegExp(r'^[a-z][a-z0-9_]{1,39}$').hasMatch)) {
      _invalid('project IDs');
    }
    final projects = await Future.wait(
      ids.map((id) async {
        final data = _json(
          await assets.loadString('$assetDirectory/projects/$id.json'),
        );
        final sketch = await assets.loadString(
          '$assetDirectory/sketches/$id.ino',
        );
        final project = LearnProject._(data, sketch);
        if (project.id != id || project.boardId != board.id) {
          _invalid('project or board ID in $id');
        }
        project._validate(parts, board);
        project._circuit = LearnCircuit._read(data['wiringLayout'], project);
        return MapEntry(id, project);
      }),
    );
    final setup = _list(catalog['setup'], _setupStep);
    if (setup.length != LearnSetupStage.values.length ||
        setup.indexed.any((item) => item.$2.stage.index != item.$1)) {
      _invalid('upload walkthrough order');
    }
    return LearnCatalog._(
      board,
      parts,
      setup,
      _list(catalog['uploadIssues'], _issue),
      _translation(catalog['safety']),
      Map.unmodifiable(Map.fromEntries(projects)),
    );
  }

  String terminalLabel(
    LearnProject project,
    LearnTerminal terminal,
    LearnLanguage language,
  ) {
    if (project.parts[terminal.part] == 'board') {
      final pin = board.pinout[terminal.pin]!;
      return 'ESP32 ${pin.mark} (${pin.header})';
    }
    final part = parts[project.parts[terminal.part]]!;
    return '${language.text(part.title)} ${terminal.part} · ${terminal.pin}';
  }
}

class LearnBoard {
  LearnBoard._(Map<String, Object?> data)
    : id = _string(data['id']),
      name = _string(data['name']),
      fqbn = _string(data['fqbn']),
      coreVersion = _string(data['coreVersion']),
      ideBoard = _string(data['ideBoard']),
      packageIndex = _string(data['packageIndex']),
      orientation = _translation(data['orientation']),
      headers = _headers(_map(data['headers'])) {
    final lessonPins = <String, LearnPin>{};
    for (final pin in headers.values.expand((pins) => pins)) {
      final terminal = pin.terminal;
      if (terminal == null) continue;
      if (lessonPins.containsKey(terminal) ||
          (terminal.startsWith('GPIO') &&
              pin.mark != 'IO${terminal.substring(4)}')) {
        _invalid('board lesson pin');
      }
      lessonPins[terminal] = (header: pin.header, mark: pin.mark);
    }
    pinout = Map.unmodifiable(lessonPins);
  }

  final String id, name, fqbn, coreVersion, ideBoard, packageIndex;
  final LearnText orientation;
  final Map<String, List<LearnBoardPin>> headers;
  late final Map<String, LearnPin> pinout;
}

enum LearnPinRole {
  gpio,
  ground,
  power3v3,
  power5v,
  analogInput,
  adc1,
  adc2,
  reset,
  serial,
  strap,
  boot,
  flash,
}

typedef LearnBoardPin = ({
  String header,
  String mark,
  LearnPinRole role,
  String? terminal,
});

Map<String, List<LearnBoardPin>> _headers(Map<String, Object?> data) {
  List<LearnBoardPin> read(String name) {
    final rows = _list(data[name], _map);
    if (rows.length != 19) _invalid('board header $name');
    return List.unmodifiable([
      for (final (index, row) in rows.indexed)
        (
          header: '$name · ${index + 1}',
          mark: _string(row['mark']),
          role: _enum(row['role'], LearnPinRole.values),
          terminal: row['terminal'] == null ? null : _string(row['terminal']),
        ),
    ]);
  }

  return Map.unmodifiable({'J2': read('J2'), 'J3': read('J3')});
}

class LearnProject {
  LearnProject._(Map<String, Object?> data, this.sketch)
    : id = _string(data['id']),
      boardId = _string(data['board']),
      title = _translation(data['title']),
      intro = _translation(data['intro']),
      overview = _translation(data['overview']),
      minutes = _minutes(data['minutes']),
      difficulty = _enum(data['difficulty'], LearnDifficulty.values),
      artwork = _enum(data['art'], LearnArtwork.values),
      categories = Set.unmodifiable(
        _list(
          data['categories'],
          (value) => _enum(value, LearnCategory.values),
        ),
      ),
      objectives = _list(data['objectives'], _translation),
      parts = _stringMap(data['parts']),
      gpio = _stringMap(data['gpio']),
      wires = _list(data['wires'], _wire),
      safety = _list(data['safety'], _translation),
      sketchLines = List.unmodifiable(const LineSplitter().convert(sketch)),
      codeNotes = _list(data['codeNotes'], _codeNote),
      checks = _list(data['checks'], _testCheck),
      issues = _list(data['issues'], _projectIssue);

  final String id, boardId, sketch;
  String get sketchFileName => '$id.ino';
  final List<String> sketchLines;
  int? get serialBaud {
    final setting = RegExp(r'\bSerial\.begin\((\d+)\);').firstMatch(sketch);
    return setting == null ? null : int.parse(setting[1]!);
  }

  final LearnText title, intro, overview;
  final int minutes;
  final LearnDifficulty difficulty;
  final LearnArtwork artwork;
  final Set<LearnCategory> categories;
  final List<LearnText> objectives, safety;
  final Map<String, String> parts, gpio;
  final List<LearnWire> wires;
  final List<LearnCodeNote> codeNotes;
  final List<LearnTestCheck> checks;
  final List<LearnProjectIssue> issues;
  late final LearnCircuit _circuit;
  LearnCircuit get circuit => _circuit;

  void _validate(Map<String, LearnPart> knownParts, LearnBoard board) {
    if (parts.values.where((part) => part == 'board').length != 1 ||
        !parts.values.every(knownParts.containsKey)) {
      _invalid('components in $id');
    }
    bool validTerminal(LearnTerminal terminal) =>
        knownParts[parts[terminal.part]]?.pins.contains(terminal.pin) ?? false;
    final connected = <Set<LearnTerminal>>[];
    final wiredGpio = <String>{};
    for (final wire in wires) {
      final pair = {wire.from, wire.to};
      if (!pair.every(validTerminal) ||
          wire.from.part == wire.to.part ||
          connected.any((previous) => previous.containsAll(pair))) {
        _invalid('wire in $id');
      }
      connected.add(pair);
      for (final terminal in pair) {
        if (parts[terminal.part] == 'board' &&
            terminal.pin.startsWith('GPIO')) {
          wiredGpio.add(terminal.pin);
        }
      }
    }
    final pinConstants = {
      for (final match in RegExp(
        r'\bconstexpr\s+uint8_t\s+(\w+Pin)\s*=\s*(\d+)\s*;',
      ).allMatches(sketch))
        match.group(1)!: 'GPIO${match.group(2)!}',
    };
    final checkIds = checks.map((check) => check.id).toSet();
    if (checkIds.length != checks.length ||
        !checkIds.every(RegExp(r'^[a-z][a-z0-9_]{1,39}$').hasMatch)) {
      _invalid('test check IDs in $id');
    }
    final wireIds = wires.map((wire) => wire.id).toSet();
    if (issues.any((issue) => !wireIds.contains(issue.wireId))) {
      _invalid('troubleshooting connection in $id');
    }
    if (gpio.length != pinConstants.length ||
        gpio.length != wiredGpio.length ||
        !gpio.entries.every(
          (entry) =>
              pinConstants[entry.key] == entry.value &&
              board.pinout.containsKey(entry.value) &&
              wiredGpio.contains(entry.value),
        )) {
      _invalid('GPIO constants and wires in $id');
    }
    if (!sketch.contains('void setup()') ||
        !sketch.contains('void loop()') ||
        utf8.encode(sketch).length > 32768) {
      _invalid('sketch or code notes in $id');
    }
    var previousLine = 0;
    final covered = <int>{};
    for (final note in codeNotes) {
      if (note.firstLine <= previousLine ||
          note.lastLine < note.firstLine ||
          note.lastLine > sketchLines.length ||
          sketchLines[note.firstLine - 1].trim() != note.anchor) {
        _invalid('code note range in $id');
      }
      for (var line = note.firstLine; line <= note.lastLine; line++) {
        covered.add(line);
      }
      previousLine = note.lastLine;
    }
    if (sketchLines.indexed.any(
      (line) => line.$2.trim().isNotEmpty && !covered.contains(line.$1 + 1),
    )) {
      _invalid('unexplained sketch line in $id');
    }
  }
}

const learnWireColors = {'cyan', 'violet', 'red', 'green', 'yellow', 'black'};

LearnWire _wire(Object? value) {
  final data = _map(value);
  final color = _string(data['color']);
  if (!learnWireColors.contains(color)) _invalid('wire color');
  return (
    from: _terminal(data['from']),
    to: _terminal(data['to']),
    color: color,
    why: _translation(data['why']),
  );
}

LearnTerminal _terminal(Object? value) {
  final values = _list(value, _string);
  if (values.length != 2) _invalid('wire terminal');
  return (part: values[0], pin: values[1]);
}

LearnPart _part(Map<String, Object?> value) {
  final pins = value['pins'];
  if (pins is! List) _invalid('part pins');
  return (
    title: _translation(value['title']),
    about: _translation(value['about']),
    pins: Set.unmodifiable(pins.map(_string)),
  );
}

LearnCodeNote _codeNote(Object? value) {
  final data = _map(value);
  final lines = data['lines'];
  if (lines is! List ||
      lines.length != 2 ||
      !lines.every((line) => line is int)) {
    _invalid('code note lines');
  }
  return (
    firstLine: lines[0] as int,
    lastLine: lines[1] as int,
    anchor: _string(data['anchor']),
    title: _translation(data['title']),
    text: _translation(data['text']),
  );
}

LearnSetupStep _setupStep(Object? value) {
  final data = _map(value);
  return (
    stage: _enum(data['stage'], LearnSetupStage.values),
    title: _translation(data['title']),
    text: _translation(data['text']),
  );
}

LearnIssue _issue(Object? value) {
  final data = _map(value);
  return (
    symptom: _translation(data['symptom']),
    cause: _translation(data['cause']),
    fix: _translation(data['fix']),
  );
}

LearnTestCheck _testCheck(Object? value) {
  final data = _map(value);
  return (
    id: _string(data['id']),
    title: _translation(data['title']),
    action: _translation(data['action']),
    expected: _translation(data['expected']),
  );
}

LearnProjectIssue _projectIssue(Object? value) {
  final data = _map(value);
  return (
    issue: _issue(data),
    inspect: _translation(data['inspect']),
    wireId: _string(data['wireId']),
  );
}

Map<String, Object?> _json(String source) => _map(decodeStrictJson(source));

Map<String, Object?> _map(Object? value) =>
    value is Map<String, Object?> ? value : _invalid('object');

String _string(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : _invalid('text');

Map<String, String> _stringMap(Object? value) => Map.unmodifiable({
  for (final entry in _map(value).entries) entry.key: _string(entry.value),
});

List<T> _list<T>(Object? value, T Function(Object?) read) =>
    value is List && value.isNotEmpty
    ? List.unmodifiable(value.map(read))
    : _invalid('non-empty list');

LearnText _translation(Object? value) {
  final data = _map(value);
  return (en: _string(data['en']), bn: _string(data['bn']));
}

int _minutes(Object? value) =>
    value is int && value > 0 && value <= 600 ? value : _invalid('duration');

T _enum<T extends Enum>(Object? value, List<T> options) =>
    options.byName(_string(value));

Never _invalid(String field) => throw FormatException('Invalid lesson $field.');
