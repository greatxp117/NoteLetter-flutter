@Tags(['pin'])
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/build_info.dart';
import 'fixtures.dart';

/// The /conformance version-pin guard. It FAILS LOUDLY the moment the pin and
/// VERSION diverge — the standing skew guard for any contract bump the client
/// has not absorbed.
///
/// Tagged `pin` (dart_test.yaml): while `QUEUE.md` has open items the pin is
/// HELD at 4.4.0 by policy (spec/clients/flutter.md §Pin) and queue-mode
/// /conformance runs `-x pin`, reporting the exclusion as its own row. That is
/// a policy, not a pass — the pin moves once, on the last queue item, with
/// this test included and green.
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
            'work QUEUE.md to empty (/flutter-next), then advance the pin with a '
            'green FULL run — never by hand (spec/clients/flutter.md §Pin).');
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
