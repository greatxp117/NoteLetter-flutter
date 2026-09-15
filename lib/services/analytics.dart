// Product-usage measurement (contract 4.41.0, ADR-079, INV-25) — this client.
//
// The reference is `NoteLetter-web/src/analytics.js` and this is its mirror,
// not a second design. [events] below mirrors
// `spec/features/analytics-events.md`, and `harness/analytics_vocab_check.py`
// (`/conformance` 5q) compares the spec, this map and the actual [track] call
// sites in every direction — a name here the spec does not list fails exactly
// as loudly as one the spec lists and nothing emits.
//
// This is the SECOND event vocabulary in the app. `activity_events` is the
// backend's record of what happened to a document, read by the reader as their
// own feed, and it carries content on purpose (INV-22). This is the client's
// record of what was USED, read by the operator in aggregate, and it carries no
// content at all. They share no key and none should be invented.
//
// ── What is DIFFERENT here, and why it is not a smaller job ──────────────────
//
// On the web a provider is something you construct: no construction, no
// measurement, and INV-25(a) is satisfied by an `if`. On mobile the Analytics
// SDK collects **on its own** the moment a Firebase app is initialised — a
// `first_open`, a `session_start`, `user_engagement` — with no call site
// anywhere and nothing for a code reader to find. So the emulator build that
// law 1 requires would post development sessions to the production property
// without this file existing at all.
//
// That inverts the control. Collection is switched OFF in the two native
// manifests as the shipped default (`FIREBASE_ANALYTICS_COLLECTION_ENABLED` in
// `ios/Runner/Info.plist`, `firebase_analytics_collection_enabled` in
// `android/app/src/main/AndroidManifest.xml`) and turned on at runtime by
// [start], only when the same two conditions the reference tests hold. A build
// that never reaches [start] measures nothing, which is the posture INV-25(a)
// asks for and the opposite of the platform default.
//
// The other half is automatic screen reporting, off in both manifests for a
// different reason: it stamps `firebase_screen_class` from the platform view,
// and every screen this app has is one `FlutterViewController`. It is not a
// leak — it is a constant, reported as though it were a measurement, which is
// the umbrella's rule about showing only what was measured pointed at our own
// telemetry.
import 'dart:io' show Platform;

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

import 'api_service.dart';

/// Event name -> the params it may carry. This map IS the contract mirror; a
/// param passed at a call site and not named here must fail, not pass.
const Map<String, List<String>> events = <String, List<String>>{
  'screen_view': ['screen_name'],
  'capture_started': ['surface'],
  'capture_completed': ['surface'],
  'search_run': ['mode', 'breadth', 'results_bucket'],
  'ask_run': ['results_bucket'],
  'result_opened': ['rank_bucket'],
  'reader_opened': ['kind'],
  'reader_mode_used': ['mode'],
  'doc_finished': ['kind'],
  'letter_opened': [],
  'letter_settings_saved': [],
  'shelf_created': ['origin'],
  'shelf_split': [],
  'study_session_started': [],
  'study_answer_submitted': ['grade'],
  'support_message_sent': [],
  'theme_changed': ['theme'],
  'onboarding_step': ['step'],
  'request_failed': ['endpoint', 'error_code', 'status'],
};

/// The route-pattern -> `screen_name` table, in the reference's own vocabulary.
///
/// Keyed on go_router's **pattern** (`GoRouterState.fullPath`), never on the
/// location the reader is at. That is the whole argument for its correctness
/// and it is the reference's argument transposed: `analytics.js` builds the
/// id-free path with the same `buildPath` the app uses and simply does not pass
/// the ids, so a route that gains an id later cannot leak one. Here the pattern
/// is `/reader/:docId` whatever document is open — id-free by construction, not
/// by a list of the routes that happen to carry one today.
///
/// The VALUES are the reference's route tokens (`shell/useRoute.js`), not this
/// client's paths: `screen_name` is one closed set across clients, and two
/// spellings of one screen is two screens to whoever reads the property.
/// `analytics_test.dart` walks `appRoutes()` and fails on a pattern this table
/// does not name, which is the direction that matters — a screen added here
/// later must be given a token rather than quietly becoming `unknown`.
const Map<String, String> screenNames = <String, String>{
  '/': 'library',
  '/library': 'library',
  '/search': 'search',
  '/ask': 'ask',
  '/chat': 'ask',
  '/activity': 'activity',
  '/sources': 'sources',
  '/settings': 'settings',
  '/settings/notifications': 'notification-settings',
  '/letters': 'letter',
  '/letters/settings': 'letter-settings',
  '/shelves': 'shelves',
  '/shelves/:shelfId': 'shelf',
  '/tags': 'shelves',
  '/reader/:docId': 'reader',
  '/study': 'study',
  '/study/new': 'study',
  '/study/:programId': 'study',
  '/study/session/:sessionId': 'study-session',
  '/support': 'support',
  // Signed out. The reference measures nothing here either — its route effect
  // lives inside the authenticated app — and a landing screen_view would be the
  // only hit in the property with no session behind it.
  '/landing': '',
  // This client's own design surface; the reference has no counterpart and the
  // vocabulary has no token for one. Named rather than left to fall through, so
  // that a missing token is always a mistake and never a silence.
  '/branding': '',
};

/// Measurement, as the reference has it: never throws, never blocks, and does
/// nothing at all when there is no provider.
///
/// Deliberately knows nothing about the router. `screen_view` is emitted from
/// `router.dart`, where the route table is, exactly as the reference emits it
/// from its own route effect rather than from `analytics.js` — a module that
/// emits its own events is a module the vocabulary gate's UNEMITTED direction
/// cannot see past.
class Analytics {
  Analytics._();

  static FirebaseAnalytics? _provider;

  /// INV-25(a), stated once so a test can ask it.
  ///
  /// `useEmulator` is the same compile-time switch every other law-1 guard in
  /// this client reads. `FLUTTER_TEST` is set by the `flutter test` harness and
  /// by nothing else — an integration run on a device is a real app and is
  /// covered by the first condition, because the device run points at the
  /// emulator.
  static bool get permitted =>
      !ApiService.useEmulator && !Platform.environment.containsKey('FLUTTER_TEST');

  /// Whether anything is being measured. False until [start] has both been
  /// called and been permitted.
  static bool get enabled => _provider != null;

  /// Turn collection on, from `main()`, after `Firebase.initializeApp`.
  ///
  /// The manifests ship collection OFF, so this is the only thing that turns it
  /// on — and it is awaited rather than fired, because the SDK queues nothing
  /// while disabled and an event logged before the switch lands is an event
  /// that never happened.
  static Future<void> start() async {
    if (!permitted) return;
    final a = FirebaseAnalytics.instance;
    await a.setAnalyticsCollectionEnabled(true);
    _provider = a;
  }

  /// Emit one catalogued event.
  static void track(String name, [Map<String, Object> params = const {}]) {
    final allowed = events[name];
    if (allowed == null) {
      // Loud in debug, silent in release: an uncatalogued name is a contract
      // break the gate fails on, and it must never break a shipped screen.
      assert(() {
        debugPrint('analytics: "$name" is not in events — see '
            'spec/features/analytics-events.md');
        return true;
      }());
      return;
    }
    assert(() {
      for (final k in params.keys) {
        if (!allowed.contains(k)) {
          debugPrint('analytics: "$name" has no param "$k" '
              '(allowed: ${allowed.isEmpty ? 'none' : allowed.join(', ')})');
        }
      }
      return true;
    }());
    final p = _provider;
    if (p == null) return;
    // `screen_view` goes through the SDK's own helper so that `screen_class` is
    // a value we chose rather than whatever the platform reports. Everything
    // else is a plain event; `screen_view` is not on the SDK's reserved list,
    // but the helper is what the SDK means by it and the two paths cost three
    // lines.
    final f = name == 'screen_view'
        ? p.logScreenView(
            screenName: params['screen_name'] as String?,
            screenClass: 'NoteLetter')
        : p.logEvent(name: name, parameters: params.isEmpty ? null : params);
    // Measurement is never in the way of the screen that triggered it.
    f.catchError((_) {});
  }

  /// The screen a route pattern reports, or null when it reports none.
  static String? screenName(String? pattern) {
    if (pattern == null) return null;
    final token = screenNames[pattern];
    if (token == null) return 'unknown';
    return token.isEmpty ? null : token;
  }

  /// `request_failed.endpoint` is a path, and six of this client's call sites
  /// build one with a query string carrying the reader's own cloud folder ids.
  static String endpointName(String? path) {
    final head = (path ?? '').split('?').first;
    return head.isEmpty ? 'unknown' : head;
  }

  /// A raw count is a number about the size of someone's library. A bucket is
  /// not. The same five buckets as the reference, from one function.
  static String bucket(num? n) {
    if (n == null || n.isNaN || n.isNegative) return 'unknown';
    if (n == 0) return '0';
    if (n == 1) return '1';
    if (n <= 3) return '2-3';
    if (n <= 10) return '4-10';
    return '11+';
  }
}
