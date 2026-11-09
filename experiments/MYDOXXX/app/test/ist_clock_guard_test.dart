import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The app shows and compares times in India time on every device (see
/// lib/utils/ist_clock.dart). Raw device-clock APIs answer in the DEVICE's zone,
/// so only the two clock files may call them. This test fails the build if any
/// other file in lib/ does, so neither a person nor an agent can quietly bring
/// the device-timezone bugs back.
///
/// Fix a failure by using IstClock.now() / IstClock.instant() / IstClock.parse /
/// IstClock.tryParse / IstClock.fromInstant / IstClock.toInstant, or the Firestore
/// helpers in lib/utils/ist_timestamp.dart (toIst, toInstant, timestampOf, istTimeOf).
const allowed = {
  'lib/utils/ist_clock.dart',
  'lib/utils/ist_timestamp.dart',
};

/// Each pattern is a raw API that reads or converts with the device zone.
final forbidden = <String, RegExp>{
  'DateTime.now (use IstClock.now() or IstClock.instant())':
      RegExp(r'DateTime\.now\b'),
  'DateTime.parse / tryParse (use IstClock.parse / tryParse)':
      RegExp(r'DateTime\.(try)?[pP]arse\b'),
  '.toUtc() (use IstClock.toInstant / instantOf)': RegExp(r'\.toUtc\(\)'),
  '.toLocal()': RegExp(r'\.toLocal\(\)'),
  'Timestamp.toDate() (use .toIst() or .toInstant())':
      RegExp(r'\.toDate\(\)'),
  'Timestamp.fromDate (use timestampOf)': RegExp(r'Timestamp\.fromDate\b'),
  'TimeOfDay.now()': RegExp(r'TimeOfDay\.now\b'),
  'DateTime.fromMillisecondsSinceEpoch (use IstClock.fromEpochMs)':
      RegExp(r'DateTime\.from(Milli|Micro)secondsSinceEpoch\b'),
  '.timeZoneOffset / .timeZoneName':
      RegExp(r'\.timeZone(Offset|Name)\b'),
};

/// The code of [source] without comments. A `//` only starts a comment when the
/// quotes before it on the line balance (so `'https://...'` is kept). Code inside
/// string interpolation such as '${...}' is kept, so it is checked too.
String withoutComments(String source) {
  final noBlocks = source.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  final out = StringBuffer();
  for (final line in noBlocks.split('\n')) {
    var cut = -1;
    for (var i = 0; i + 1 < line.length; i++) {
      if (line[i] == '/' && line[i + 1] == '/') {
        final before = line.substring(0, i);
        final single = "'".allMatches(before).length;
        final double = '"'.allMatches(before).length;
        if (single.isEven && double.isEven) {
          cut = i;
          break;
        }
      }
    }
    out.writeln(cut < 0 ? line : line.substring(0, cut));
  }
  return out.toString();
}

List<File> libFiles() => [
      for (final e in Directory('lib').listSync(recursive: true))
        if (e is File && e.path.endsWith('.dart')) e
    ];

String relative(File f) => f.path.replaceAll('\\', '/');

void main() {
  test('only the two clock files use raw device-clock APIs', () {
    final problems = <String>[];
    for (final file in libFiles()) {
      final path = relative(file);
      if (allowed.contains(path)) continue;
      final code = withoutComments(file.readAsStringSync());
      final lines = code.split('\n');
      for (var i = 0; i < lines.length; i++) {
        for (final entry in forbidden.entries) {
          if (entry.value.hasMatch(lines[i])) {
            problems.add('$path:${i + 1}  ${entry.key}\n    ${lines[i].trim()}');
          }
        }
      }
    }
    expect(problems, isEmpty,
        reason: 'Use the India clock (lib/utils/ist_clock.dart):\n'
            '${problems.join('\n')}');
  });

  test('every date picker highlights India\'s today', () {
    final problems = <String>[];
    for (final file in libFiles()) {
      final code = withoutComments(file.readAsStringSync());
      for (final m in RegExp(r'showDatePicker\(').allMatches(code)) {
        final call = code.substring(m.end, (m.end + 200).clamp(0, code.length));
        if (!call.contains('currentDate: IstClock.now()')) {
          final line = code.substring(0, m.start).split('\n').length;
          problems.add('${relative(file)}:$line');
        }
      }
    }
    expect(problems, isEmpty,
        reason: 'Pass currentDate: IstClock.now() to showDatePicker:\n'
            '${problems.join('\n')}');
  });

  test('the allowed clock files exist and are the only ones listed', () {
    for (final path in allowed) {
      expect(File(path).existsSync(), isTrue, reason: '$path is missing');
    }
    expect(allowed.length, 2);
  });

  group('the scanner itself', () {
    test('ignores comments but keeps code and string interpolation', () {
      const code = '''
// DateTime.now() in a comment
/// DateTime.now() in a doc comment
/* DateTime.now() in a block */
final a = 'https://example.com'; final b = DateTime.now();
final c = '\${DateTime.now().year}';
''';
      final stripped = withoutComments(code);
      final hits = forbidden.values.first.allMatches(stripped).length;
      expect(hits, 2, reason: 'the real call and the interpolated call');
    });

    test('every forbidden pattern matches its own example', () {
      const examples = {
        'DateTime.now()': 0,
        'DateTime.parse(x)': 1,
        'DateTime.tryParse(x)': 1,
        'a.toUtc()': 2,
        'a.toLocal()': 3,
        'ts.toDate()': 4,
        'Timestamp.fromDate(a)': 5,
        'TimeOfDay.now()': 6,
        'DateTime.fromMillisecondsSinceEpoch(0)': 7,
        'a.timeZoneOffset': 8,
      };
      final patterns = forbidden.values.toList();
      examples.forEach((text, index) {
        expect(patterns[index].hasMatch(text), isTrue, reason: text);
      });
    });
  });
}
