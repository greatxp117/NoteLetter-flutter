import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **The seam's own hazard (C1g).**
///
/// `FirestoreService.instance` is settable so a notifier can be started
/// against a stream that fails on command (C1). A static that outlives its
/// test is the leak that makes the NEXT one flaky — and flaky in the worst
/// direction: the file that sets it stays green, and the file after it goes
/// red, which is where anyone will look. This suite has no isolation to fall
/// back on; nothing resets between files, and `flutter test` is free to order
/// them however it likes.
///
/// So the rule is asserted over the suite rather than trusted to the next
/// person reading a docstring: a file that assigns the instance names
/// `resetInstance` too. It cannot prove the reset actually RUNS — that needs
/// the ordering this test exists because we do not have — but an assignment
/// with no reset anywhere in the file is unambiguous, and it is the shape the
/// leak takes.
///
/// A gate that reads nothing reports PASS on the silence (4.34.7), so the
/// file count is asserted first: a moved test directory is not a clean suite.
void main() {
  test('a test that swaps FirestoreService.instance also resets it', () {
    final dir = Directory('test');
    expect(dir.existsSync(), isTrue, reason: 'the suite moved');

    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(files.length, greaterThan(5),
        reason: 'read ${files.length} test file(s) — an unread suite is not '
            'a clean one (4.34.7)');

    final offenders = <String>[];
    for (final f in files) {
      final src = f.readAsStringSync();
      final assigns = RegExp(r'FirestoreService\.instance\s*=').hasMatch(src);
      if (assigns && !src.contains('resetInstance')) {
        offenders.add(f.path);
      }
    }

    expect(offenders, isEmpty,
        reason: 'these swap the singleton and never put it back, so the file '
            'that fails is the one AFTER them: ${offenders.join(", ")}');
  });
}
