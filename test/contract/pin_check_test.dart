import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'fixtures.dart';

/// The /conformance version-pin guard. Flutter is caught up to the contracts
/// VERSION (2.3.0 as of 2026-07-26), so this is GREEN; it FAILS LOUDLY the
/// moment the pin and VERSION diverge — the standing skew guard for any future
/// contract bump the client hasn't absorbed.
///
/// The target is the canonical `VERSION` file, matching the web reference's
/// pin-check — NOT `manifest.contractVersion` (which tracks fixture capture and
/// can legitimately lag VERSION; using it was a harness bug that validated the
/// pin against the wrong, stale target).
void main() {
  test('flutter pin matches contracts VERSION', () {
    final version = contractsVersion();
    final claude = File('CLAUDE.md').readAsStringSync();
    final m = RegExp(r'[Cc]ontract version[:*\s]+([0-9]+\.[0-9]+\.[0-9]+)')
        .firstMatch(claude);
    expect(m, isNotNull, reason: 'CLAUDE.md must declare a contract version');
    expect(m!.group(1), version,
        reason: 'Flutter pin ${m.group(1)} != contracts $version — '
            'realign (Milestone 2) then advance the pin with a green run.');
  });
}
