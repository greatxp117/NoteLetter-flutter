import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'fixtures.dart';

/// The /conformance version-pin guard. Flutter is pinned at contract 1.0.0
/// (Milestone-2 realignment is not complete), so this FAILS LOUDLY against the
/// current contracts VERSION — the deliberate catch-up signal. It turns green
/// only when the Flutter pin is advanced together with a clean conformance run.
void main() {
  test('flutter pin matches contracts VERSION (red until catch-up)', () {
    final version = contractVersion();
    final claude = File('CLAUDE.md').readAsStringSync();
    final m = RegExp(r'[Cc]ontract version[:*\s]+([0-9]+\.[0-9]+\.[0-9]+)')
        .firstMatch(claude);
    expect(m, isNotNull, reason: 'CLAUDE.md must declare a contract version');
    expect(m!.group(1), version,
        reason: 'Flutter pin ${m.group(1)} != contracts $version — '
            'realign (Milestone 2) then advance the pin with a green run.');
  });
}
