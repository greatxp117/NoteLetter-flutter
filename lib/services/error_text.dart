import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import 'api_service.dart' show ApiException;

/// A sentence a reader can act on, for a failure that came from the SDK rather
/// than from one of our endpoints (C7).
///
/// Half this app's data arrives by subscription (INV-02), and a subscription
/// failure carries no envelope of ours: no `error`, no `request_id`, nothing
/// ADR-070 §14 was written around. What it carries is a `FirebaseException`,
/// and `'$e'` on one renders
///
///     [cloud_firestore/permission-denied] The caller does not have
///     permission to execute the specified operation.
///
/// verbatim into the §14 detail slot — the plugin's own words, the plugin's
/// own brackets, and no next move for the person reading them. Fifteen screens
/// and notifiers put that string on the glass.
///
/// Only the three codes a client listener actually raises are named. A map of
/// every code in the SDK would be a list of sentences nothing can produce, and
/// the ones that stay unproven are the ones that end up wrong:
///
///   * `permission-denied` — the rules refused this read. From a signed-in
///     reader that is a stale token far more often than a real ownership
///     failure, so the move is to sign out and back in before support.
///   * `unavailable` — no route to Firestore. Offline is what that is, from
///     the reader's side, whichever end is down.
///   * `failed-precondition` — a composite or vector index the query needs
///     does not exist in this database. Nothing the reader can do; it is ours,
///     and it is the shape that shipped dark seven times (`deploy_check.py`).
///
/// An `ApiException` passes through with its own message, because the server's
/// sentence is never replaced by one of ours (ADR-070) — the arms that route
/// here already handle that case above, and this is the belt for a site that
/// forgets to.
///
/// The raw text is not thrown away: it goes to the debug log, once per call.
/// Some call sites are inside `build`, so in release it is not printed at all
/// rather than printed on every rebuild.
String describeFirestoreError(Object e) {
  if (kDebugMode) debugPrint('describeFirestoreError: $e');
  if (e is ApiException) return e.message;
  if (e is FirebaseException) {
    switch (e.code) {
      case 'permission-denied':
        return 'NoteLetter could not read this. Sign out and back in, or '
            'contact support.';
      case 'unavailable':
        return 'You appear to be offline.';
      case 'failed-precondition':
        return 'This view is not ready on the server yet. Contact support.';
    }
  }
  return 'This could not be read right now. Please try again.';
}
