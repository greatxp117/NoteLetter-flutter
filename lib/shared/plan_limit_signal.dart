/// The one signal a plan refusal sends across the app (4.79.0, ADR-113).
///
/// A `PLAN_LIMIT` rejection is the one failure another screen draws a
/// consequence of: the Settings Plan row refetches its **measured** figures
/// rather than counting anything itself (§12). The reference dispatches a
/// `nl-plan-limit` window event from its single `call()` seam; this client's
/// seam is `ApiService._handle`, and this is its bus.
///
/// It carries no payload on purpose. The event says *the figures you hold are
/// stale*, never what the new ones are — a client that learned a figure from a
/// refusal would be holding a number no endpoint reported.
library;

import 'dart:async';

class PlanLimitSignal {
  PlanLimitSignal._();

  static final StreamController<void> _c = StreamController<void>.broadcast();

  /// Fired by `ApiService._handle` on any `PLAN_LIMIT`, from any verb.
  static void fire() {
    if (!_c.isClosed) _c.add(null);
  }

  static Stream<void> get stream => _c.stream;
}
