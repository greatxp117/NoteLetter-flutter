import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/build_info.dart';
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
String _declaredPin() {
  final claude = File('CLAUDE.md').readAsStringSync();
  final m = RegExp(r'[Cc]ontract version[:*\s]+([0-9]+\.[0-9]+\.[0-9]+)')
      .firstMatch(claude);
  expect(m, isNotNull, reason: 'CLAUDE.md must declare a contract version');
  return m!.group(1)!;
}

void main() {
  test('flutter pin matches contracts VERSION', () {
    final version = contractsVersion();
    final pin = _declaredPin();
    expect(pin, version,
        reason: 'Flutter pin $pin != contracts $version — '
            'realign (Milestone 2) then advance the pin with a green run.');
  });

  test('the pin the app SENDS matches the pin it declares', () {
    // `BuildInfo.contractPin` rides out on every support message as
    // `clientVersion` (spec/api/support.md §Validation) — it is what tells
    // whoever answers which build a bug came from. It is a second copy of the
    // line above, so it is compared to it: a pin that drifts here reports the
    // wrong build on every report, and nothing else would ever notice.
    expect(BuildInfo.contractPin, _declaredPin());
  });
}
