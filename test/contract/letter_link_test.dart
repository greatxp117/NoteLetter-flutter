// A letter's passage link opens the app (2026-11-11). Four files in three repos
// have to agree, and none of them can fail when they do not: the link only
// opens Safari instead.
//
//   1. The backend builds every letter link as
//      `{APP_BASE_URL}/reader/{document_id}?p={chunk_id}` (INV-21), its base
//      `https://noteletter.com`.
//   2. noteletter.com serves `/.well-known/apple-app-site-association`
//      (NoteLetter-web/public/) claiming exactly `/reader/*` for this app's id.
//   3. Runner.entitlements declares `applinks:` for that host.
//   4. This router has the route the link lands on, and reads `?p=` there.
//
// What this cannot see: Apple's CDN fetching the file, the App ID's Associated
// Domains capability, and a tap in Mail on a device — Xavier's (TODO).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_app/router.dart';

const _host = 'noteletter.com';
const _team = '3SA8A2JP3T';
const _bundle = 'xp.NoteLetter.Flutter';

String _read(String path) => File(path).readAsStringSync();

/// Every GoRoute path in the table, nested routes joined to their parents.
List<String> _paths(List<RouteBase> routes, [String base = '']) => [
      for (final r in routes) ...[
        if (r is GoRoute)
          r.path.startsWith('/') ? r.path : '$base/${r.path}',
        ..._paths(r.routes, r is GoRoute ? r.path : base),
      ],
    ];

void main() {
  test('the entitlement names the host every letter link is built on', () {
    final ent = _read('ios/Runner/Runner.entitlements');
    final key = RegExp(
        r'<key>com\.apple\.developer\.associated-domains</key>\s*<array>([\s\S]*?)</array>');
    final m = key.firstMatch(ent);
    expect(m, isNotNull, reason: 'Runner.entitlements declares no associated domains');
    final domains = RegExp(r'<string>([^<]*)</string>')
        .allMatches(m!.group(1)!)
        .map((x) => x.group(1))
        .toList();
    expect(domains, ['applinks:$_host']);

    final core = _read('../NoteLetter-Firebase-Functions/functions/core_app.py');
    expect(core, contains('APP_BASE_URL = os.environ.get("APP_BASE_URL", "https://$_host")'),
        reason: "the letter's links are built on APP_BASE_URL; its host is the one this app claims");
    final letter = _read('../NoteLetter-Firebase-Functions/functions/area_letter.py');
    expect(letter, contains(r'f"{APP_BASE_URL}/reader/{doc_id}?p={chunk_id}"'),
        reason: "a letter's passage link is /reader/{id}?p={chunk} (INV-21)");
  });

  test("web's association file claims the reader route, for this app, and nothing else", () {
    final aasa = jsonDecode(
            _read('../NoteLetter-web/public/.well-known/apple-app-site-association'))
        as Map<String, dynamic>;
    final details = (aasa['applinks']['details'] as List).cast<Map<String, dynamic>>();
    expect(details, hasLength(1));
    expect(details.single['appIDs'], ['$_team.$_bundle']);
    final paths = (details.single['components'] as List).map((c) => c['/']).toList();
    // Exactly the reader: claiming `/*` would take sign-in's handler and the
    // OAuth callback out of the browser on a phone that has the app.
    expect(paths, ['/reader/*']);

    final pbx = _read('ios/Runner.xcodeproj/project.pbxproj');
    expect(pbx, contains('DEVELOPMENT_TEAM = $_team;'));
    expect(pbx, contains('PRODUCT_BUNDLE_IDENTIFIER = $_bundle;'));
  });

  test('the link lands on a route this app has, and that route reads ?p=', () {
    final paths = _paths(appRoutes());
    expect(paths, contains('/reader/:docId'));
    final router = _read('lib/router.dart');
    expect(router, contains("passageId: state.uri.queryParameters['p']"));
    // Flutter hands a universal link to the router only with deep linking on
    // (the default since 3.27); a plist that turns it off drops every link.
    expect(_read('ios/Runner/Info.plist'), isNot(contains('FlutterDeepLinkingEnabled')),
        reason: 'FlutterDeepLinkingEnabled is set: read its value before trusting the default');
  });
}
