/// Measurement (4.41.0, ADR-079, INV-25) — the half a Python gate cannot read.
///
/// `analytics_vocab_check.py` (`/conformance` 5q) compares the catalog, this
/// client's `events` map, every call site and both native manifests. What it
/// cannot do is WALK THE ROUTE TABLE: `appRoutes()` is a list of closures, and
/// the only thing that can ask it what routes exist is this client.
///
/// That is the direction that matters. `screenNames` is a table, and a table
/// beside a route list is the `docKind()`/`KIND_ORDER` split that has cost this
/// workspace a feature twice — a route added without a token would report
/// `unknown` forever, and `unknown` is indistinguishable from a screen nobody
/// opens.
library;

import 'package:flutter_app/router.dart';
import 'package:flutter_app/services/analytics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Every `GoRoute` path in the table the app actually runs.
Set<String> _routePaths(List<RouteBase> routes) {
  final out = <String>{};
  void walk(List<RouteBase> rs) {
    for (final r in rs) {
      if (r is GoRoute) out.add(r.path);
      walk(r.routes);
    }
  }

  walk(routes);
  return out;
}

void main() {
  group('screen_name covers the route table', () {
    final paths = _routePaths(appRoutes());

    test('the reader reads something', () {
      // A walk that finds nothing agrees with everything (4.34.7). This client
      // has more than a dozen routes; five is a floor, not a count.
      expect(paths.length, greaterThan(5));
    });

    test('every route has a token, or an explicit silence', () {
      final missing = paths.where((p) => !screenNames.containsKey(p)).toList()
        ..sort();
      expect(missing, isEmpty,
          reason: 'these routes are in the app and not in `screenNames`, so '
              'they would report `unknown` — which reads exactly like a screen '
              'nobody opens:\n  ${missing.join('\n  ')}\n'
              'Give each one a token from the reference vocabulary, or the '
              "empty string to say it deliberately reports nothing.");
    });

    test('no token names a route that no longer exists', () {
      final stale = screenNames.keys.where((p) => !paths.contains(p)).toList()
        ..sort();
      expect(stale, isEmpty,
          reason: 'these rows name no route in this app — a table that has '
              'stopped matching the thing it describes:\n  '
              '${stale.join('\n  ')}');
    });

    test('a route that carries an id carries it as a PARAMETER', () {
      // The whole id-free argument: the key is go_router's pattern, so the id
      // position is `:docId` and never a Firestore id. A key with a long
      // opaque segment would mean somebody wrote a concrete location into the
      // table, which is the one way this table could leak.
      for (final key in screenNames.keys) {
        for (final seg in key.split('/')) {
          if (seg.isEmpty || seg.startsWith(':')) continue;
          expect(seg, matches(RegExp(r'^[a-z][a-z-]*$')),
              reason: '`$key` has a segment that is not a literal path word. '
                  'An id belongs in the pattern as `:name`, never spelled out.');
        }
      }
    });
  });

  group('screenName', () {
    test('an empty token is a silence, not a screen', () {
      expect(Analytics.screenName('/landing'), isNull);
      // Signed out as well (F-44a) — named, so it never falls through to
      // `unknown` and reports a hit with no session behind it.
      expect(Analytics.screenName('/signin'), isNull);
    });

    test('a route the table does not know reports `unknown`', () {
      expect(Analytics.screenName('/nothing/here'), 'unknown');
    });

    test('null in, null out — there is nothing to report', () {
      expect(Analytics.screenName(null), isNull);
    });

    test('the reader opens on a token, not on a document id', () {
      expect(Analytics.screenName('/reader/:docId'), 'reader');
      expect(Analytics.screenName('/shelves/:shelfId'), 'shelf');
      expect(Analytics.screenName('/study/session/:sessionId'), 'study-session');
    });
  });

  group('endpointName', () {
    test('the query string is stripped', () {
      // Six builders put one on the path, and the params of
      // `fn_list_cloud_files` are the reader's own cloud folder ids (INV-25b).
      expect(
          Analytics.endpointName('/fn_list_cloud_files?provider=gdrive&'
              'folderId=1AbC_realFolderId'),
          '/fn_list_cloud_files');
    });

    test('a path with no query survives whole', () {
      expect(Analytics.endpointName('/fn_search_notes'), '/fn_search_notes');
    });

    test('nothing in is `unknown`, never an empty string', () {
      expect(Analytics.endpointName(null), 'unknown');
      expect(Analytics.endpointName(''), 'unknown');
      expect(Analytics.endpointName('?a=b'), 'unknown');
    });
  });

  group('bucket', () {
    test('the five buckets, at their boundaries', () {
      expect(Analytics.bucket(0), '0');
      expect(Analytics.bucket(1), '1');
      expect(Analytics.bucket(2), '2-3');
      expect(Analytics.bucket(3), '2-3');
      expect(Analytics.bucket(4), '4-10');
      expect(Analytics.bucket(10), '4-10');
      expect(Analytics.bucket(11), '11+');
      // A library of nine hundred documents is still `11+`. That is the point:
      // a raw count is a number about the size of someone's library.
      expect(Analytics.bucket(912), '11+');
    });

    test('nothing measurable is `unknown`, never 0', () {
      // `0` is an answer — no results came back. A missing figure is not that,
      // and reporting it as zero is the umbrella's own rule about showing only
      // what was measured.
      expect(Analytics.bucket(null), 'unknown');
      expect(Analytics.bucket(double.nan), 'unknown');
      expect(Analytics.bucket(-1), 'unknown');
    });
  });

  group('INV-25(a) — there is no provider under test', () {
    test('permitted is false here, and so is enabled', () {
      // If this ever passes, this suite is posting into the production
      // property and GA4 has no delete for a single event.
      expect(Analytics.permitted, isFalse);
      expect(Analytics.enabled, isFalse);
    });

    test('track() is a no-op with no provider, and never throws', () {
      expect(() => Analytics.track('screen_view', {'screen_name': 'library'}),
          returnsNormally);
      // An uncatalogued name must not break a screen either — it is a contract
      // break the gate fails on, not a crash for the reader.
      expect(() => Analytics.track('not_a_real_event'), returnsNormally);
    });
  });

  group('the catalog', () {
    test('every event declares its params as a list', () {
      expect(events, isNotEmpty);
      for (final entry in events.entries) {
        expect(entry.value, isA<List<String>>(),
            reason: '${entry.key} must declare a param list, even an empty one');
      }
    });

    test('no event name is reserved by the SDK', () {
      // `logEvent` throws `ArgumentError` on a reserved name, and the throw
      // would happen on the reader's device rather than here. `screen_view` is
      // NOT reserved — it is a standard event — which is why it may be
      // catalogued; `session_start` and `first_open` are, and are not.
      const reserved = {
        'app_clear_data', 'app_exception', 'app_remove', 'app_update',
        'error', 'first_open', 'first_visit', 'in_app_purchase',
        'notification_dismiss', 'notification_foreground', 'notification_open',
        'notification_receive', 'os_update', 'session_start', 'user_engagement',
      };
      for (final name in events.keys) {
        expect(reserved.contains(name), isFalse,
            reason: '`$name` is reserved by the Analytics SDK — logEvent would '
                'throw on the reader\'s device');
        expect(name.startsWith('firebase_'), isFalse);
        expect(name.startsWith('google_'), isFalse);
        expect(name.startsWith('ga_'), isFalse);
      }
    });
  });
}
