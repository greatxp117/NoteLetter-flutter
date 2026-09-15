/// ADR-101 — the Reader names where it was opened from.
///
/// Two vocabularies meet here and neither tests the other: the ROUTER's paths
/// and the back control's LABELS. A kind the renderer never lists disappears
/// with no error (`docKind()`/`KIND_ORDER`, ADR-064), so both directions are
/// asserted — and the second one walks `appRoutes()`, which only this client
/// can do.
library;

import 'package:flutter_app/models/tag.dart';
import 'package:flutter_app/router.dart';
import 'package:flutter_app/shared/reader_origin.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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
  group('the Reader names where it was opened from', () {
    test('every screen that can open the Reader has a name and a way back', () {
      const origins = <String, String>{
        '/': 'Home',
        '/sources': 'Library',
        '/search': 'Search',
        '/ask': 'Ask',
        '/ask/shelf/tag-1': 'Ask',
        '/ask/thread/th-1': 'Ask',
        '/activity': 'Activity',
        '/letters': 'Letters',
        '/shelves': 'Shelves',
      };
      origins.forEach((path, label) {
        final origin = readerOrigin(path);
        expect(origin.label, label, reason: path);
        expect(origin.path, path, reason: path);
      });
    });

    test('every label in the table belongs to a route the app HAS', () {
      // The other direction. A name for a route that cannot exist is a control
      // nothing can render, which reads as a spec for a screen nobody built.
      final paths = _routePaths(appRoutes());
      expect(paths.length, greaterThan(5), reason: 'the walk read nothing');
      for (final key in readerOriginLabels.keys) {
        expect(paths, contains(key),
            reason: '`$key` is named by the back control and is no route');
      }
    });

    test('a shelf is named by the shelf, and by the index when unknown', () {
      const tags = [
        Tag(id: 'tag-1', userId: 'u1', title: 'Liturgy'),
      ];
      expect(readerOrigin('/shelves/tag-1', tags: tags).label, 'Liturgy');
      expect(readerOrigin('/shelves/tag-1', tags: tags).path, '/shelves/tag-1');
      // A shelf that is gone or still loading is not "no origin": the reader
      // still came from there, so only the NAME falls back.
      expect(readerOrigin('/shelves/tag-9', tags: tags).label, 'Shelves');
      expect(readerOrigin('/shelves/tag-9', tags: tags).path, '/shelves/tag-9');
    });

    test('a cold open falls back to Library, which it can honestly say', () {
      expect(readerOrigin(null).label, 'Library');
      expect(readerOrigin(null).path, '/sources');
      expect(readerOrigin('').label, 'Library');
    });

    test('a `from` this app does not have is dropped, never guessed', () {
      const refused = [
        'https://evil.example/ask', // absolute
        '//evil.example/ask', // protocol-relative
        'ask', // no leading slash
        '/ask/thread', // the thread form with no id
        '/nope', // a path this app does not have
        '/reader/d1?p=c1', // a query is not part of a route
        '/sources/', // a trailing slash is a different string
        '/shelves/../secrets', // not an id
      ];
      for (final from in refused) {
        expect(readerOrigin(from).label, 'Library', reason: from);
        expect(readerOrigin(from).path, '/sources', reason: from);
      }
    });
  });
}
