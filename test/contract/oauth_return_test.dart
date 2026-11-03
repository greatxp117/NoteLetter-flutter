// F-151, F-156 — the connect page (5.46.0, ADR-201; 5.52.0, ADR-203;
// screens/sources.md §The OAuth return). Mirrors web
// `tests/contract/oauth-return.test.js`: every state is reached the way a
// reader reaches it — a held return (an app's `noteletter://cloud-connect`,
// opened as its own route by the app shell) or a web build's /connect params
// (held by the router's redirect), spent by the real connect page under a
// real GoRouter — never by mounting the page with a hand-made view. The
// notifier is the real one; only the transport is canned, so what Bring in
// SENDS is asserted, not assumed. Since 5.52.0 the page has its own address,
// Notion's offer arrives ticked, and nothing offers File under.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/cloud_file.dart';
import 'package:flutter_app/models/cloud_integration.dart';
import 'package:flutter_app/models/tag.dart';
import 'package:flutter_app/pages/sources/oauth_return.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/shared/cloud_return.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

import 'sources_harness.dart';

const _shelves = [
  Tag(id: 'sh-theo', userId: 'u1', title: 'Theology'),
  Tag(id: 'sh-pat', userId: 'u1', title: 'Patristics', parentTagId: 'sh-theo'),
];

const _drive = CloudIntegration(
  provider: 'google_drive',
  tokenValid: true,
  providerEmail: 'reader@example.com',
  autoSyncEnabled: false,
  syncFrequency: 'daily',
  includeTypes: ['pdf', 'docx'],
);

const _items = [
  {'id': 'fo-1', 'name': 'Reading', 'type': 'folder', 'mime_type': '', 'size': 0, 'modified_at': ''},
  {
    'id': 'fi-1',
    'name': 'Essay.pdf',
    'type': 'file',
    'mime_type': 'application/pdf',
    'size': 2048,
    'modified_at': '2026-10-01T12:00:00Z'
  },
  {
    'id': 'fi-2',
    'name': 'Budget.xlsx',
    'type': 'file',
    'mime_type':
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'size': 100,
    'modified_at': ''
  },
];

/// The backend, canned: the claim's [answer], the root [listing] (or a 400
/// with [listingError]; [more] is a second page behind token `t2`), an import
/// that counts what it was asked for, and a sync write that answers the
/// integration. Records every request.
class _Backend implements HttpClientAdapter {
  _Backend({this.answer, this.listing = _items, this.listingError, this.more});

  final Map<String, dynamic>? answer;
  final List<Map<String, dynamic>> listing;
  final List<Map<String, dynamic>>? more;
  final String? listingError;
  final sent = <RequestOptions>[];

  List<Map<String, dynamic>> bodies(String fn) => [
        for (final o in sent)
          if (o.path.endsWith('/$fn')) (o.data as Map).cast<String, dynamic>()
      ];

  (int, Object) _reply(RequestOptions o) {
    final fn = o.path.split('/').last;
    switch (fn) {
      case 'fn_claim_cloud_connection':
        return (200, answer ?? const {});
      case 'fn_list_cloud_files':
        if (listingError != null) return (400, {'error': listingError});
        if (o.queryParameters['pageToken'] == 't2') {
          return (200, {'items': more ?? const [], 'nextPageToken': null});
        }
        return (200, {
          'items': listing,
          'nextPageToken': more != null ? 't2' : null,
        });
      case 'fn_import_from_cloud':
        final b = o.data as Map;
        return (202, {
          'queued_folders': (b['folder_ids'] as List).length,
          'queued_files': (b['file_ids'] as List).length,
        });
      case 'fn_sync_settings':
        return (200, {
          'integration': {
            'provider': 'google_drive',
            'token_valid': true,
            'auto_sync_enabled': true,
          }
        });
    }
    return (404, {'error': 'not stubbed: $fn'});
  }

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    sent.add(options);
    final (status, body) = _reply(options);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

/// The real notifier with its integrations read quieted and answered.
class _Cloud extends QuietCloud {
  _Cloud([this.connected = const []]);
  final List<CloudIntegration> connected;

  @override
  CloudIntegration? integrationFor(String provider) {
    for (final i in connected) {
      if (i.provider == provider) return i;
    }
    return null;
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _settle(tester);
}

void _claimReturn([String provider = 'google_drive']) => CloudReturn.hold(
    CloudReturn('claim', claim: 'c1', provider: provider));

const _notion = CloudIntegration(provider: 'notion', tokenValid: true);

Map<String, dynamic> _page(String id, String name) => {
      'id': id,
      'name': name,
      'type': 'file',
      'mime_type': 'application/x-notion-page',
      'size': 0,
      'modified_at': '',
    };

final _notionItems = [
  _page('np-1', 'Sermon notes'),
  _page('np-2', 'Reading log'),
  {
    'id': 'nd-1',
    'name': 'Quotes',
    'type': 'folder',
    'mime_type': 'application/x-notion-database',
    'size': 0,
    'modified_at': '',
  },
];

/// Whether the offer card for [name] is ticked (its checkbox's semantics).
bool _ticked(WidgetTester tester, String name) => tester
    .widget<KitCheckbox>(find.byWidgetPredicate(
        (w) => w is KitCheckbox && w.semanticsLabel == 'Bring in $name'))
    .value;

void _errorReturn(String reason) =>
    CloudReturn.hold(CloudReturn('error', reason: reason));

const _granted = {
  'cloud_connect': 'success',
  'provider': 'google_drive',
  'connection': 'new',
};

void main() {
  setUp(() => ApiService.instance.tokenProvider = () async => 'test-token');
  tearDown(() {
    ApiService.instance.resetTestSeams();
    CloudReturn.take();
    CloudReturn.forgetConnecting();
    ConnectHandoff.take();
  });

  group('which view a return opens on', () {
    test('reads the claim answer and the redirect reason; open vocabulary '
        'falls to failed', () {
      ReturnView v(ReturnPhase p, {Map<String, dynamic>? answer, String? reason}) =>
          returnView(OAuthReturn(p, answer: answer, reason: reason));
      expect(v(ReturnPhase.claiming), ReturnView.claiming);
      expect(v(ReturnPhase.claimed, answer: _granted), ReturnView.granted);
      expect(
          v(ReturnPhase.claimed,
              answer: {..._granted, 'connection': 'someday'}),
          ReturnView.granted);
      expect(
          v(ReturnPhase.claimed,
              answer: {..._granted, 'connection': 'reconnected'}),
          ReturnView.already);
      expect(
          v(ReturnPhase.claimed,
              answer: {'cloud_connect': 'error', 'reason': 'connect_failed'}),
          ReturnView.failed);
      expect(v(ReturnPhase.error, reason: 'access_denied'), ReturnView.denied);
      expect(v(ReturnPhase.error, reason: 'invalid_state'), ReturnView.expired);
      expect(v(ReturnPhase.error, reason: 'missing_params'), ReturnView.failed);
      expect(v(ReturnPhase.error, reason: 'server_error'), ReturnView.failed);
      expect(v(ReturnPhase.refused), ReturnView.refused);
      // 5.52.0: reopened with nothing to answer, for a connected provider.
      expect(v(ReturnPhase.direct), ReturnView.granted);
    });
  });

  group('its own address (5.52.0, ADR-203)', () {
    test('the page\'s address is the provider\'s stored id, or /connect', () {
      expect(CloudReturn.location('notion'), '/connect/notion');
      expect(CloudReturn.location('google_drive'), '/connect/google_drive');
      expect(CloudReturn.location(null), '/connect');
      expect(CloudReturn.location('gdrive'), '/connect',
          reason: 'never a second spelling of the four');
      expect(CloudReturn.isConnectPath('/connect'), isTrue);
      expect(CloudReturn.isConnectPath('/connect/notion'), isTrue);
      expect(CloudReturn.isConnectPath('/connections'), isFalse);
    });

    testWidgets('an app\'s return opens /connect/{provider} over Sources, and '
        'Back leaves it for Sources', (tester) async {
      ApiService.instance.httpClientAdapter = _Backend(answer: _granted);
      final router = await pumpConnectApp(tester, SourcesStubService(),
          cloud: _Cloud([_drive]));
      expect(find.text('The Library'), findsWidgets);
      _claimReturn();
      await _settle(tester);
      expect(routerPath(router), '/connect/google_drive');
      expect(find.text('Google Drive, Connected'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1)); // the page transition
      expect(find.text('The Library'), findsNothing,
          reason: 'never drawn in place on Sources: it is under the page');
      router.pop();
      await _settle(tester);
      expect(routerPath(router), '/sources');
      expect(find.text('The Library'), findsWidgets);
    });

    testWidgets('a return that arrives elsewhere goes to Sources first, so '
        'Back still lands there', (tester) async {
      ApiService.instance.httpClientAdapter = _Backend(answer: _granted);
      final router = await pumpConnectApp(tester, SourcesStubService(),
          cloud: _Cloud([_drive]), initial: '/');
      expect(find.text('Home'), findsOneWidget);
      _claimReturn();
      await _settle(tester);
      expect(routerPath(router), '/connect/google_drive');
      expect(find.text('Google Drive, Connected'), findsOneWidget);
      router.pop();
      await _settle(tester);
      expect(routerPath(router), '/sources');
    });

    testWidgets('a web build\'s /connect?cloud_connect=claim is held and '
        'leaves the address before anything draws', (tester) async {
      final backend = _Backend(
          answer: {..._granted, 'provider': 'notion'}, listing: _notionItems);
      ApiService.instance.httpClientAdapter = backend;
      final router = await pumpConnectApp(tester, SourcesStubService(),
          cloud: _Cloud(const [_notion]),
          initial: '/connect?cloud_connect=claim&claim=c9&provider=notion');
      await _settle(tester);
      expect(routerPath(router), '/connect/notion');
      expect(router.state.uri.query, isEmpty);
      expect(find.text('Notion, Connected'), findsOneWidget);
      expect(backend.bodies('fn_claim_cloud_connection'), [
        {'claim': 'c9'}
      ], reason: 'spent once');
    });

    testWidgets('forwards the callback\'s old target, /sources?cloud_connect='
        '…, to the connect page', (tester) async {
      CloudReturn.noteConnecting('dropbox');
      final router = await pumpConnectApp(tester, SourcesStubService(),
          cloud: _Cloud(),
          initial: '/sources?cloud_connect=error&reason=access_denied');
      await _settle(tester);
      expect(routerPath(router), '/connect/dropbox');
      expect(find.text('Nothing Was Shared'), findsOneWidget);
      expect(find.text('Try Dropbox again'), findsOneWidget);
    });

    testWidgets('reopened with nothing to claim, shows {Provider}, Connected '
        'for a connected provider', (tester) async {
      final backend = _Backend(listing: _notionItems);
      ApiService.instance.httpClientAdapter = backend;
      final router = await pumpConnectApp(tester, SourcesStubService(),
          cloud: _Cloud(const [_notion]), initial: '/connect/notion');
      await _settle(tester);
      expect(routerPath(router), '/connect/notion');
      expect(find.text('Notion, Connected'), findsOneWidget);
      expect(find.text('Sermon notes'), findsOneWidget);
      expect(backend.bodies('fn_claim_cloud_connection'), isEmpty);
    });

    for (final (why, connected, at) in [
      ('not connected', [_drive], '/connect/notion'),
      (
        'its sign-in expired',
        const [
          CloudIntegration(
              provider: 'notion', tokenValid: true, status: 'reconnect_required')
        ],
        '/connect/notion'
      ),
      ('an unknown provider', [_drive], '/connect/dropbx'),
      ('no provider at all', [_drive], '/connect'),
    ]) {
      testWidgets('reopened for $why is the Library', (tester) async {
        ApiService.instance.httpClientAdapter = _Backend();
        final router = await pumpConnectApp(tester, SourcesStubService(),
            cloud: _Cloud(connected), initial: at);
        await _settle(tester);
        expect(routerPath(router), '/sources');
        expect(find.text('The Library'), findsWidgets);
      });
    }
  });

  group('{Provider}, Connected', () {
    testWidgets(
        'lists what the provider offers with measured figures only, nothing '
        'ticked, no File under, and refuses an unreadable file', (tester) async {
      final backend = _Backend(answer: _granted);
      ApiService.instance.httpClientAdapter = backend;
      _claimReturn();
      await pumpConnectApp(tester, SourcesStubService(),
          cloud: _Cloud([_drive]), shelves: _shelves);
      await _settle(tester);
      expect(find.text('Google Drive, Connected'), findsOneWidget);
      expect(find.text('Essay.pdf'), findsOneWidget);
      expect(find.text('3 ITEMS'), findsOneWidget,
          reason: 'the SectionHead meta, from the listing');
      // The root listing, nothing else.
      final q = backend.sent
          .firstWhere((o) => o.path.endsWith('/fn_list_cloud_files'))
          .queryParameters;
      expect(q, {'provider': 'google_drive'});
      // Measured meta only: size and the modified date, never a page or
      // passage count or an indexing estimate.
      expect(find.text('2 KB · updated Oct 1, 2026'), findsOneWidget);
      expect(find.textContaining('passages, about'), findsNothing);
      expect(find.textContaining('takes about'), findsNothing);
      // A spreadsheet has no checkbox, and says why in the classifier's words.
      expect(find.bySemanticsLabel('Bring in Budget.xlsx'), findsNothing);
      expect(find.bySemanticsLabel('Bring in Essay.pdf'), findsWidgets);
      expect(find.textContaining('isn’t a supported file type'), findsOneWidget);
      // A drive's root is not a choice the reader made: nothing arrives ticked.
      expect(_ticked(tester, 'Essay.pdf'), isFalse);
      expect(_ticked(tester, 'Reading'), isFalse);
      final none = find.widgetWithText(KitButton, 'Nothing selected');
      expect(tester.widget<KitButton>(none).onPressed, isNull);
      // No File under (ADR-203), and no shelf to choose anywhere.
      expect(find.text('File under'), findsNothing);
      expect(find.text('NoteLetter chooses'), findsNothing);
      expect(find.byType(DropdownButton<String>), findsNothing);
      expect(find.textContaining('are ticked — one import takes'), findsNothing);
    });

    testWidgets(
        'brings in what was ticked, never sends a shelf, keeps a folder in '
        'sync, and the Library says its sentence', (tester) async {
      final backend = _Backend(answer: _granted);
      ApiService.instance.httpClientAdapter = backend;
      _claimReturn();
      final router = await pumpConnectApp(tester, SourcesStubService(),
          cloud: _Cloud([_drive]), shelves: _shelves);
      await _settle(tester);
      await _tap(tester, find.text('Reading'));
      await _tap(tester, find.text('Essay.pdf'));
      // Measured: what a folder takes is the integration's include_types.
      expect(
          find.text('From folders, NoteLetter takes these kinds: PDF and '
              'Word. Change which in Sync settings.'),
          findsOneWidget);
      expect(find.text('New files in this folder come in once a day.'),
          findsOneWidget);
      await _tap(tester, find.text('Bring in 2 items'));
      expect(routerPath(router), '/sources');
      expect(find.text('Queued 1 folder and 1 file from Google Drive.'),
          findsOneWidget);
      expect(find.text('The Library'), findsWidgets);
      expect(backend.bodies('fn_import_from_cloud'), [
        {
          'provider': 'google_drive',
          'folder_ids': ['fo-1'],
          'file_ids': ['fi-1'],
          'folder_names': {'fo-1': 'Reading'},
        }
      ]);
      expect(backend.bodies('fn_sync_settings'), [
        {'provider': 'google_drive', 'auto_sync_enabled': true}
      ]);
      expect(ConnectHandoff.pending.value, isNull,
          reason: 'the Library took it, once');
      await tester.pump(const Duration(seconds: 61));
    });

    testWidgets('turns on no sync when only a file was ticked',
        (tester) async {
      final backend = _Backend(answer: _granted);
      ApiService.instance.httpClientAdapter = backend;
      _claimReturn();
      await pumpConnectApp(tester, SourcesStubService(),
          cloud: _Cloud([_drive]), shelves: _shelves);
      await _settle(tester);
      await _tap(tester, find.text('Essay.pdf'));
      // Only folders stay in sync: the switch is held with a file alone.
      final sw = tester.widget<KitSwitch>(find.byType(KitSwitch));
      expect(sw.onChanged, isNull);
      expect(sw.value, isFalse);
      expect(find.text('Only folders stay in sync — tick one to keep it.'),
          findsOneWidget);
      await _tap(tester, find.text('Bring in 1 item'));
      expect(find.text('Queued 0 folders and 1 file from Google Drive.'),
          findsOneWidget);
      final body = backend.bodies('fn_import_from_cloud').single;
      expect(body.containsKey('tag_ids'), isFalse,
          reason: 'never sent (ADR-203) — the import shelves as any other');
      expect(backend.bodies('fn_sync_settings'), isEmpty);
      await tester.pump(const Duration(seconds: 61));
    });

    testWidgets('says Nothing to Bring In when the listing answers empty',
        (tester) async {
      ApiService.instance.httpClientAdapter =
          _Backend(answer: _granted, listing: const []);
      _claimReturn();
      await pumpConnectApp(tester, SourcesStubService(),
          cloud: _Cloud([_drive]), shelves: _shelves);
      await _settle(tester);
      expect(find.text('Nothing to Bring In'), findsOneWidget);
      expect(find.text('0 items listed'), findsOneWidget);
      expect(find.widgetWithText(KitButton, 'Back to library'), findsOneWidget);
    });

    testWidgets('says the listing failed rather than drawing an empty offer',
        (tester) async {
      ApiService.instance.httpClientAdapter = _Backend(
          answer: _granted, listingError: 'Google Drive did not answer.');
      _claimReturn();
      await pumpConnectApp(tester, SourcesStubService(),
          cloud: _Cloud([_drive]), shelves: _shelves);
      await _settle(tester);
      expect(
          find.text('What Google Drive offers could not be listed — Google '
              'Drive did not answer.'),
          findsOneWidget);
      expect(find.widgetWithText(KitHxLink, 'Try again'), findsOneWidget);
      expect(find.text('Nothing to Bring In'), findsNothing);
    });

    testWidgets('Notion gets the standing guidance, never a finding',
        (tester) async {
      ApiService.instance.httpClientAdapter = _Backend(answer: {
        ..._granted,
        'provider': 'notion',
      }, listing: const [
        {'id': 'p1', 'name': 'Reading notes', 'type': 'file', 'mime_type': ''},
      ]);
      _claimReturn('notion');
      await pumpConnectApp(tester, SourcesStubService(),
          cloud: _Cloud(const [_notion]), shelves: _shelves);
      await _settle(tester);
      expect(find.text('Notion, Connected'), findsOneWidget);
      expect(
          find.text('Notion passes along only the pages you ticked on its '
              'permission screen — to bring more in, grant access in Notion '
              'and return.'),
          findsOneWidget);
      expect(find.textContaining('isn’t a supported file type'), findsNothing,
          reason: 'a Notion page is read as text, never classified');
      expect(find.text('Page'), findsOneWidget);
    });
  });

  group('Notion\'s offer arrives ticked (5.52.0, ADR-203)', () {
    testWidgets('ticks every page and database Notion shared; the reader '
        'unticks what does not belong', (tester) async {
      final backend = _Backend(
          answer: {..._granted, 'provider': 'notion'}, listing: _notionItems);
      ApiService.instance.httpClientAdapter = backend;
      _claimReturn('notion');
      final router = await pumpConnectApp(tester, SourcesStubService(),
          cloud: _Cloud(const [_notion]));
      await _settle(tester);
      expect(routerPath(router), '/connect/notion');
      expect(_ticked(tester, 'Sermon notes'), isTrue);
      expect(_ticked(tester, 'Reading log'), isTrue);
      expect(_ticked(tester, 'Quotes'), isTrue);
      expect(find.text('Bring in 3 items'), findsOneWidget);
      await _tap(tester, find.text('Reading log'));
      expect(_ticked(tester, 'Reading log'), isFalse);
      await _tap(tester, find.text('Bring in 2 items'));
      expect(backend.bodies('fn_import_from_cloud'), [
        {
          'provider': 'notion',
          'folder_ids': ['nd-1'],
          'file_ids': ['np-1'],
          'folder_names': {'nd-1': 'Quotes'},
        }
      ]);
      expect(routerPath(router), '/sources');
      expect(find.text('Queued 1 folder and 1 file from Notion.'),
          findsOneWidget);
      await tester.pump(const Duration(seconds: 61));
    });

    testWidgets('ticks what Load more brings too', (tester) async {
      ApiService.instance.httpClientAdapter = _Backend(
          answer: {..._granted, 'provider': 'notion'},
          listing: [_page('np-1', 'One')],
          more: [_page('np-2', 'Two')]);
      _claimReturn('notion');
      await pumpConnectApp(tester, SourcesStubService(),
          cloud: _Cloud(const [_notion]));
      await _settle(tester);
      expect(_ticked(tester, 'One'), isTrue);
      await _tap(tester, find.widgetWithText(KitHxLink, 'Load more'));
      expect(find.text('Two'), findsOneWidget);
      expect(_ticked(tester, 'Two'), isTrue);
      expect(find.text('Bring in 2 items'), findsOneWidget);
    });

    testWidgets('stops at the import\'s caps and says so; a reader who '
        'unticked has room and is told nothing', (tester) async {
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      ApiService.instance.httpClientAdapter = _Backend(
          answer: {..._granted, 'provider': 'notion'},
          listing: [for (var i = 0; i < 52; i++) _page('np-$i', 'Page $i')]);
      _claimReturn('notion');
      await pumpConnectApp(tester, SourcesStubService(),
          cloud: _Cloud(const [_notion]));
      await _settle(tester);
      expect(find.text('Bring in 50 items'), findsOneWidget);
      expect(_ticked(tester, 'Page 49'), isTrue);
      expect(_ticked(tester, 'Page 50'), isFalse);
      expect(_ticked(tester, 'Page 51'), isFalse);
      const line = 'The first 50 pages are ticked — one import takes 50 at a '
          'time. Bring these in, then choose the rest from the Library.';
      expect(find.text(line), findsOneWidget);
      await _tap(tester, find.text('Page 0'));
      expect(find.text(line), findsNothing);
    });

    test('counts each cap by its own kind, and never ticks a refused item',
        () {
      CloudFile f(String id, String type, [String mime = '']) =>
          CloudFile.fromJson({'id': id, 'name': id, 'type': type, 'mime_type': mime});
      final folders = [for (var i = 0; i < 21; i++) f('d$i', 'folder')];
      final got = tickOffer(const [], folders,
          {for (final d in folders) d.id: true}, 'notion');
      expect(got.length, 20);
      expect(capLines(folders, got, 'notion'), [
        'The first 20 databases are ticked — one import takes 20 at a time. '
            'Bring these in, then choose the rest from the Library.',
      ]);
      // Ticks already made count against the cap of their own kind.
      final pages = [for (var i = 0; i < 3; i++) f('p$i', 'file', 'application/x-notion-page')];
      final more = tickOffer(got, pages,
          {for (final d in folders) d.id: true, for (final p in pages) p.id: false},
          'notion');
      expect(more.length, 23, reason: 'pages count against the file cap');
      // A drive file the upload rule refuses is never ticked.
      final xlsx = f('x', 'file',
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      expect(tickOffer(const [], [xlsx], const {'x': false}, 'google_drive'),
          isEmpty);
    });
  });

  group('the notices', () {
    testWidgets('Already Connected for a re-authorised account, and opens '
        'the manifest on request', (tester) async {
      ApiService.instance.httpClientAdapter =
          _Backend(answer: {..._granted, 'connection': 'reconnected'});
      _claimReturn();
      await pumpConnectApp(tester, SourcesStubService(),
          cloud: _Cloud([_drive]), shelves: _shelves);
      await _settle(tester);
      expect(find.text('Already Connected'), findsOneWidget);
      expect(find.text('no sync folders · auto-sync off'), findsOneWidget);
      await _tap(tester, find.text('Choose what comes across'));
      expect(find.text('Google Drive, Connected'), findsOneWidget);
    });

    testWidgets('Nothing Was Shared names the provider this client sent to '
        'consent, in the address too', (tester) async {
      CloudReturn.noteConnecting('dropbox');
      _errorReturn('access_denied');
      final router =
          await pumpConnectApp(tester, SourcesStubService(), cloud: _Cloud());
      await _settle(tester);
      expect(routerPath(router), '/connect/dropbox');
      expect(find.text('Nothing Was Shared'), findsOneWidget);
      expect(
          find.text('You declined access in the Dropbox window, so nothing '
              'came across. Your library is exactly as you left it.'),
          findsOneWidget);
      expect(find.text('Try Dropbox again'), findsOneWidget);
      expect(find.text('error: access_denied'), findsOneWidget);
      await _tap(tester, find.text('Add files instead'));
      expect(routerPath(router), '/sources/add');
    });

    testWidgets('a return that arrives while the page is open (Try again) is '
        'answered in place, never a second page', (tester) async {
      ApiService.instance.httpClientAdapter =
          _Backend(answer: {..._granted, 'provider': 'dropbox'});
      CloudReturn.noteConnecting('dropbox');
      _errorReturn('access_denied');
      final router = await pumpConnectApp(tester, SourcesStubService(),
          cloud: _Cloud(const [
            CloudIntegration(provider: 'dropbox', tokenValid: true)
          ]));
      await _settle(tester);
      expect(find.text('Nothing Was Shared'), findsOneWidget);
      // What the session hands back when Try Dropbox again comes through.
      CloudReturn.hold(
          const CloudReturn('claim', claim: 'c2', provider: 'dropbox'));
      await _settle(tester);
      expect(find.text('Dropbox, Connected'), findsOneWidget);
      expect(routerPath(router), '/connect/dropbox');
      router.pop();
      await _settle(tester);
      expect(routerPath(router), '/sources',
          reason: 'one connect page, not one per return');
    });

    testWidgets('The Link Expired says the TTL the code enforces, ten minutes',
        (tester) async {
      CloudReturn.noteConnecting('onedrive');
      _errorReturn('invalid_state');
      await pumpConnectApp(tester, SourcesStubService(), cloud: _Cloud());
      await _settle(tester);
      expect(find.text('The Link Expired'), findsOneWidget);
      expect(find.textContaining('longer than ten minutes'), findsOneWidget);
      expect(find.textContaining('fifteen'), findsNothing);
      expect(returnTtlMinutes, 10);
      expect(find.text('Start again'), findsOneWidget);
    });

    testWidgets('hands an organization answer to the Library, which says it',
        (tester) async {
      CloudReturn.noteConnecting('google_drive');
      _errorReturn('insufficient_scope');
      final router =
          await pumpConnectApp(tester, SourcesStubService(), cloud: _Cloud());
      await _settle(tester);
      expect(routerPath(router), '/sources');
      expect(
          find.textContaining('didn’t grant the permissions needed for '
              'auto-organization'),
          findsOneWidget);
      expect(find.text('Not Connected'), findsNothing);
      expect(find.text('The Library'), findsWidgets);
    });

    testWidgets('org: "enabled" is the Library\'s notice too', (tester) async {
      ApiService.instance.httpClientAdapter =
          _Backend(answer: {..._granted, 'org': 'enabled'});
      _claimReturn();
      final router = await pumpConnectApp(tester, SourcesStubService(),
          cloud: _Cloud([_drive]));
      await _settle(tester);
      expect(routerPath(router), '/sources');
      expect(find.text('Auto-organization is now enabled for Google Drive.'),
          findsOneWidget);
    });

    testWidgets('an error return with no remembered provider still reads, as '
        'the service', (tester) async {
      _errorReturn('access_denied');
      final router =
          await pumpConnectApp(tester, SourcesStubService(), cloud: _Cloud());
      await _settle(tester);
      expect(routerPath(router), '/connect');
      expect(find.text('Nothing Was Shared'), findsOneWidget);
      expect(
          find.text('You declined access, so nothing came across. Your '
              'library is exactly as you left it.'),
          findsOneWidget);
      expect(find.textContaining('the the'), findsNothing);
      expect(find.textContaining('Try '), findsNothing,
          reason: 'no provider to try again');
    });
  });

  group('the Library', () {
    testWidgets('carries the account once connected (kit §5.1), and the '
        'invitation before', (tester) async {
      await pumpSources(tester, SourcesStubService(), cloud: _Cloud([_drive]));
      expect(find.text('reader@example.com'), findsOneWidget);
      expect(find.text('Pages & databases'), findsOneWidget,
          reason: 'Notion, not connected');
    });

    testWidgets('no stored address still says Connected', (tester) async {
      await pumpSources(tester, SourcesStubService(),
          cloud: _Cloud(const [
            CloudIntegration(provider: 'dropbox', tokenValid: true)
          ]));
      expect(
          find.descendant(
              of: find.widgetWithText(KitServiceRow, 'Dropbox'),
              matching: find.text('Connected')),
          findsOneWidget);
    });

    testWidgets('says what Bring in queued, once', (tester) async {
      ConnectHandoff.handOff(
          note: 'Queued 1 folder and 1 file from Google Drive.');
      await pumpSources(tester, SourcesStubService(), cloud: _Cloud([_drive]));
      expect(find.text('Queued 1 folder and 1 file from Google Drive.'),
          findsOneWidget);
      expect(ConnectHandoff.pending.value, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpSources(tester, SourcesStubService(), cloud: _Cloud([_drive]));
      expect(find.text('Queued 1 folder and 1 file from Google Drive.'),
          findsNothing);
    });
  });

  group('the import picker', () {
    testWidgets('offers no File under, and sends no shelf', (tester) async {
      final backend = _Backend();
      ApiService.instance.httpClientAdapter = backend;
      final cloud = _Cloud([_drive]);
      await pumpSources(tester, SourcesStubService(),
          cloud: cloud, shelves: _shelves);
      await _tap(tester, find.text('Browse files…'));
      expect(find.text('File under'), findsNothing);
      expect(find.text('NoteLetter chooses'), findsNothing);
      expect(find.byType(DropdownButton<String>), findsNothing);
      await _tap(tester, find.text('Essay.pdf'));
      await _tap(tester, find.text('Import 1 item'));
      final body = backend.bodies('fn_import_from_cloud').single;
      expect(body.containsKey('tag_ids'), isFalse);
      await tester.pump(const Duration(seconds: 61));
    });
  });

  group('leaving the page', () {
    testWidgets('Not now goes to the Library with nothing queued and nothing '
        'to say', (tester) async {
      final backend = _Backend(answer: _granted);
      ApiService.instance.httpClientAdapter = backend;
      _claimReturn();
      final router = await pumpConnectApp(tester, SourcesStubService(),
          cloud: _Cloud([_drive]), shelves: _shelves);
      await _settle(tester);
      expect(find.text('Essay.pdf'), findsOneWidget);
      await _tap(tester, find.widgetWithText(KitButton, 'Not now'));
      expect(routerPath(router), '/sources');
      expect(find.text('The Library'), findsWidgets);
      expect(backend.bodies('fn_import_from_cloud'), isEmpty);
      expect(ConnectHandoff.pending.value, isNull);
      expect(find.textContaining('Queued'), findsNothing);
      expect(find.textContaining('Connected to Google Drive'), findsNothing,
          reason: 'the Library nudge is retired (ADR-201)');
    });
  });
}
