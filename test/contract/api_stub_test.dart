import 'package:flutter_test/flutter_test.dart';

/// api/* request-construction conformance is NOT implemented for Flutter yet —
/// it is part of the Milestone-2 realignment + contract catch-up. Recorded here
/// so the gap is visible in the test run rather than silently absent. This file
/// intentionally has no assertions against fixtures; it is a marker.
void main() {
  test('api/* Tier-1 conformance — NOT IMPLEMENTED (catch-up milestone)', () {
    // The request-builder conformance (ApiService/dio) lands with the Flutter
    // contract catch-up, alongside advancing the pin past 1.0.0.
    expect(true, isTrue);
  }, skip: 'Flutter api/* conformance deferred to Milestone-2 catch-up');
}
