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

  /// The same rule for the HTTP seams (C4g).
  ///
  /// `ApiService.instance` is a static singleton with two mutable seams —
  /// `httpClientAdapter` and `tokenProvider` — and until C4g there was no way
  /// to undo either. A suite that installed a canned transport left it
  /// installed for everything that ran after it in the same process: green as
  /// long as nothing else made a request, and a mystery on the day something
  /// did. That is the same one-way door the check above exists for, and a
  /// second settable static needs the same rule in the same place or the rule
  /// is about one name rather than about the hazard.
  test('a test that installs an HTTP seam also resets it', () {
    final files = Directory('test')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    final seam = RegExp(
        r'ApiService\.instance\.(httpClientAdapter|tokenProvider)\s*=');
    final offenders = <String>[];
    var checked = 0;
    for (final f in files) {
      final src = f.readAsStringSync();
      if (!seam.hasMatch(src)) continue;
      checked++;
      if (!src.contains('resetTestSeams')) offenders.add(f.path);
    }

    expect(checked, greaterThan(0),
        reason: 'no file installs an HTTP seam — either the suite moved or '
            'the seam was renamed, and both read like a clean result');
    expect(offenders, isEmpty,
        reason: 'these install a canned transport on the shared singleton and '
            'never remove it: ${offenders.join(", ")}');
  });
}
