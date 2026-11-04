// TODO L5895: a device test never calls `pumpAndSettle`. On a screen with a
// live animation (a pulsing node, a spinner) it does not fail, it HANGS, and
// its Duration is the interval between pumps, not a timeout, so the hang
// looks like a slow test; the activity test read green this way until a
// processing document happened to be in the feed. Nothing held the rule, so
// this does: it reads every file under integration_test/, comments taken
// out (the files explain the rule in their comments), and refuses a call.
//
// Mutants run against it (each red): a real `await tester.pumpAndSettle();`
// added to device_run_test.dart; the same call behind a tear-off
// (`final s = tester.pumpAndSettle;`). A comment naming it stays green.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// [src] with its `//` and `/* */` comments removed. A `//` inside a string
/// is cut too, which can only HIDE a call, never invent one.
String withoutComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i < 0 ? l : l.substring(0, i);
    })
    .join('\n');

List<String> settles(String src) {
  final out = <String>[];
  final lines = withoutComments(src).split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (RegExp(r'\bpumpAndSettle\b').hasMatch(lines[i])) {
      out.add('${i + 1}: ${lines[i].trim()}');
    }
  }
  return out;
}

void main() {
  test('no device test calls pumpAndSettle', () {
    final files = Directory('integration_test')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(files, isNotEmpty, reason: 'a gate that reads nothing is no gate');
    final found = <String>[
      for (final f in files)
        for (final hit in settles(f.readAsStringSync())) '${f.path}:$hit',
    ];
    expect(found, isEmpty,
        reason: 'bounded pump loops (pumpFor), never pumpAndSettle:\n'
            '${found.join('\n')}');
  });

  test('the reader itself: a call is found, a comment is not', () {
    expect(settles('  await tester.pumpAndSettle();'), hasLength(1));
    expect(settles('  final s = tester.pumpAndSettle;'), hasLength(1));
    expect(settles('  // Bounded pumps, never `pumpAndSettle`.'), isEmpty);
    expect(settles('  /// never pumpAndSettle'), isEmpty);
    expect(settles('/* pumpAndSettle */ await tester.pump();'), isEmpty);
  });
}
