import 'package:flutter/widgets.dart';

/// Leaving a screen that holds unsaved work (C10 — the Flutter half of B13).
///
/// The reader's manuscript editor keeps every edit in local state until
/// **Save & re-index** is pressed. Nothing asked before throwing that away: the
/// back control navigated on tap, the system back button and the iOS swipe
/// gesture did it without a render, and a `go()` from anywhere replaced the
/// route outright. The only signal was the "Text edited" dock in the
/// manuscript's own footer — which a reader part way through five thousand
/// words is not looking at, and which says nothing at the moment it matters. A
/// reader who retyped a mangled paragraph and pressed Back lost it with no
/// error, no toast and nothing in any log: the app did exactly what it was
/// asked, which is why no gate here could ever have seen it.
///
/// **Guard the ROUTER, not the back button.** Every way out of the reader ends
/// in go_router removing that route — a `pop()` from the back control, a
/// `go()` that replaces the stack, the platform's own back — and `GoRoute.
/// onExit` is the one place all three pass through. A check on `KitBackControl`
/// would guard the control this client happens to draw and miss the two nobody
/// writes code for, which is the guarded-twin shape this workspace keeps
/// finding: the covered path looks like the whole answer.
///
/// **ONE guard at a time, deliberately** — the same call the reference makes.
/// Two screens holding unsaved work cannot both be on screen, and a registry
/// would invite a stale entry to answer for a screen that has gone: a leave
/// nobody can complete, which is worse than the defect this closes.
///
/// The guard is asked a QUESTION and answers it, rather than being handed the
/// navigation to run itself. That is where this deliberately parts from the
/// reference: `setNav` there is synchronous, so its guard has to take custody
/// of the move and call `proceed` later, and `ReaderView` renders the dialog
/// because the closure cannot await one. `onExit` is a `Future<bool>`, so the
/// screen holding the edits both asks and answers, and there is no stored
/// continuation to drop on the floor.
class LeaveGuard {
  LeaveGuard._();

  /// Asked whether the screen may be left NOW. `true` means go.
  static Future<bool> Function(BuildContext context)? _guard;

  /// Registers [ask] and returns the disposer. The disposer clears it only if
  /// it is still the registered one — a screen tearing down after its
  /// replacement has registered must not silently unguard the new screen.
  static VoidCallback register(Future<bool> Function(BuildContext) ask) {
    _guard = ask;
    return () {
      if (identical(_guard, ask)) _guard = null;
    };
  }

  /// Whether anything is holding work right now. For the router's own
  /// reporting and for tests; never a substitute for [mayLeave], which is the
  /// only thing that asks the reader.
  static bool get isGuarded => _guard != null;

  /// The router's question. With no guard registered the answer is always yes,
  /// which is what makes this safe to hang off a route that is usually clean.
  static Future<bool> mayLeave(BuildContext context) async {
    final ask = _guard;
    if (ask == null) return true;
    return ask(context);
  }

  /// For tests, and for a screen torn down outside the framework's own order.
  @visibleForTesting
  static void clear() => _guard = null;
}
