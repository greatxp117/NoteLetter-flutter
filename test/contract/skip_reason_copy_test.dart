import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/pages/study/syllabus_plan_editor.dart';

/// What the syllabus parse left out, in words (2.37.0, ADR-037; 4.112.0,
/// ADR-149) — held to the reference's own table, `SKIP_REASONS` in web
/// `pages/study/schedule.js`, copy for copy.
///
/// Until 4.112.0 every row here was this client's paraphrase ("not a teaching
/// week" where `screens/study.md` quotes "a week that teaches nothing"), and
/// the new `assessment` reason fell to the generic line. Reading the web file
/// is what keeps a fifth paraphrase from passing: a hand-copied expectation
/// would only agree with itself.
void main() {
  final src = File('../NoteLetter-web/src/pages/study/schedule.js');

  Map<String, String> referenceTable() {
    expect(src.existsSync(), isTrue,
        reason: 'schedule.js moved — this gate reads nothing');
    final text = src.readAsStringSync();
    final block = RegExp(r'const SKIP_REASONS = \{([\s\S]*?)\n\};')
        .firstMatch(text)
        ?.group(1);
    expect(block, isNotNull, reason: 'SKIP_REASONS not found in schedule.js');
    String unescape(String s) => s
        .replaceAllMapped(RegExp(r'\\u([0-9a-fA-F]{4})'),
            (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)))
        .replaceAll(r"\'", "'");
    final rows = <String, String>{};
    for (final m in RegExp(r"^\s*(\w+):\s*'((?:[^'\\]|\\.)*)',?\s*$",
            multiLine: true)
        .allMatches(block!)) {
      rows[m[1]!] = unescape(m[2]!);
    }
    return rows;
  }

  test('every reason the reference names reads as the reference reads it', () {
    final rows = referenceTable();
    expect(rows.keys, containsAll(<String>['non_teaching', 'assessment']),
        reason: 'parsed ${rows.length} rows — the table did not read');
    for (final e in rows.entries) {
      expect(skipReasonCopy(e.key), e.value, reason: 'reason ${e.key}');
    }
  });

  test('an unknown reason still renders — the reference’s generic line', () {
    final text = src.readAsStringSync();
    final fallback = RegExp(r"SKIP_REASONS\[reason\] \|\| '([^']*)'")
        .firstMatch(text)
        ?.group(1);
    expect(fallback, isNotNull, reason: 'skipReasonCopy fallback not found');
    expect(skipReasonCopy('a_reason_no_release_has_heard_of'), fallback);
    expect(skipReasonCopy(null), fallback);
  });
}
