// F-151 — the OAuth return page and File under (5.46.0, ADR-201;
// screens/sources.md §The OAuth return). Mirrors web
// `tests/contract/oauth-return.test.js`: every state is reached the way a
// reader reaches it — a held return (an app's `noteletter://cloud-connect`
// or a web build's /sources params) spent by the real Sources — never by
// mounting the page with a hand-made view. The notifier is the real one; only
// the transport is canned, so what Bring in SENDS is asserted, not assumed.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
/// with [listingError]), an import that counts what it was asked for, and a
/// sync write that answers the integration. Records every request.
class _Backend implements HttpClientAdapter {
  _Backend({this.answer, this.listing = _items, this.listingError});

  final Map<String, dynamic>? answer;
  final List<Map<String, dynamic>> listing;
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
        return listingError != null
            ? (400, {'error': listingError})
            : (200, {'items': listing, 'nextPageToken': null});
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
    });
  });

  group('{Provider}, Connected', () {
    testWidgets(
        'lists what the provider offers with measured figures only, and '
        'refuses an unreadable file', (tester) async {
      final backend = _Backend(answer: _granted);
      ApiService.instance.httpClientAdapter = backend;
      _claimReturn();
      await pumpSources(tester, SourcesStubService(),
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
      final none = find.widgetWithText(KitButton, 'Nothing selected');
      expect(tester.widget<KitButton>(none).onPressed, isNull);
    });

    testWidgets(
        'brings in what was ticked, filed under the chosen shelf, and keeps a '
        'folder in sync', (tester) async {
      final backend = _Backend(answer: _granted);
      ApiService.instance.httpClientAdapter = backend;
      _claimReturn();
      await pumpSources(tester, SourcesStubService(),
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
      // The nested shelf is spelled by its path.
      await _tap(tester, find.byType(DropdownButton<String>));
      expect(find.text('Theology › Patristics'), findsWidgets);
      await tester.tap(find.text('Theology › Patristics').last);
      await _settle(tester);
      await _tap(tester, find.text('Bring in 2 items'));
      expect(
          find.text('Queued 1 folder and 1 file from Google Drive, filed '
              'under Theology › Patristics.'),
          findsOneWidget);
      expect(find.text('The Library'), findsWidgets);
      expect(backend.bodies('fn_import_from_cloud'), [
        {
          'provider': 'google_drive',
          'folder_ids': ['fo-1'],
          'file_ids': ['fi-1'],
          'folder_names': {'fo-1': 'Reading'},
          'tag_ids': ['sh-pat'],
        }
      ]);
      expect(backend.bodies('fn_sync_settings'), [
        {'provider': 'google_drive', 'auto_sync_enabled': true}
      ]);
      await tester.pump(const Duration(seconds: 61));
    });

    testWidgets('files nothing and turns on no sync when the reader chose '
        'neither', (tester) async {
      final backend = _Backend(answer: _granted);
      ApiService.instance.httpClientAdapter = backend;
      _claimReturn();
      await pumpSources(tester, SourcesStubService(),
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
          reason: 'absent, not [] — the import shelves as any other');
      expect(backend.bodies('fn_sync_settings'), isEmpty);
      await tester.pump(const Duration(seconds: 61));
    });

    testWidgets('says Nothing to Bring In when the listing answers empty',
        (tester) async {
      ApiService.instance.httpClientAdapter =
          _Backend(answer: _granted, listing: const []);
      _claimReturn();
      await pumpSources(tester, SourcesStubService(),
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
      await pumpSources(tester, SourcesStubService(),
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
      await pumpSources(tester, SourcesStubService(),
          cloud: _Cloud(const [
            CloudIntegration(provider: 'notion', tokenValid: true)
          ]),
          shelves: _shelves);
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

  group('the notices', () {
    testWidgets('Already Connected for a re-authorised account, and opens '
        'the manifest on request', (tester) async {
      ApiService.instance.httpClientAdapter =
          _Backend(answer: {..._granted, 'connection': 'reconnected'});
      _claimReturn();
      await pumpSources(tester, SourcesStubService(),
          cloud: _Cloud([_drive]), shelves: _shelves);
      await _settle(tester);
      expect(find.text('Already Connected'), findsOneWidget);
      expect(find.text('no sync folders · auto-sync off'), findsOneWidget);
      await _tap(tester, find.text('Choose what comes across'));
      expect(find.text('Google Drive, Connected'), findsOneWidget);
    });

    testWidgets('Nothing Was Shared names the provider this client sent to '
        'consent', (tester) async {
      CloudReturn.noteConnecting('dropbox');
      _errorReturn('access_denied');
      await pumpSources(tester, SourcesStubService(), cloud: _Cloud());
      await _settle(tester);
      expect(find.text('Nothing Was Shared'), findsOneWidget);
      expect(
          find.text('You declined access in the Dropbox window, so nothing '
              'came across. Your library is exactly as you left it.'),
          findsOneWidget);
      expect(find.text('Try Dropbox again'), findsOneWidget);
      expect(find.text('error: access_denied'), findsOneWidget);
    });

    testWidgets('The Link Expired says the TTL the code enforces, ten minutes',
        (tester) async {
      CloudReturn.noteConnecting('onedrive');
      _errorReturn('invalid_state');
      await pumpSources(tester, SourcesStubService(), cloud: _Cloud());
      await _settle(tester);
      expect(find.text('The Link Expired'), findsOneWidget);
      expect(find.textContaining('longer than ten minutes'), findsOneWidget);
      expect(find.textContaining('fifteen'), findsNothing);
      expect(returnTtlMinutes, 10);
      expect(find.text('Start again'), findsOneWidget);
    });

    testWidgets('keeps an organization answer on the Library, not the return '
        'page', (tester) async {
      CloudReturn.noteConnecting('google_drive');
      _errorReturn('insufficient_scope');
      await pumpSources(tester, SourcesStubService(), cloud: _Cloud());
      await _settle(tester);
      expect(
          find.textContaining('didn’t grant the permissions needed for '
              'auto-organization'),
          findsOneWidget);
      expect(find.text('Not Connected'), findsNothing);
      expect(find.text('The Library'), findsWidgets);
    });

    testWidgets('an error return with no remembered provider still reads, as '
        'the service', (tester) async {
      _errorReturn('access_denied');
      await pumpSources(tester, SourcesStubService(), cloud: _Cloud());
      await _settle(tester);
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

  group('the connect card', () {
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
  });

  group('the import picker', () {
    testWidgets('carries File under, and files what it imports',
        (tester) async {
      final backend = _Backend();
      ApiService.instance.httpClientAdapter = backend;
      final cloud = _Cloud([_drive]);
      await pumpSources(tester, SourcesStubService(),
          cloud: cloud, shelves: _shelves);
      await _tap(tester, find.text('Browse files…'));
      expect(find.text('File under'), findsOneWidget);
      expect(find.text('NoteLetter chooses'), findsOneWidget);
      expect(find.text('Applies to what you import now.'), findsOneWidget);
      await _tap(tester, find.byType(DropdownButton<String>));
      await tester.tap(find.text('Theology').last);
      await _settle(tester);
      await _tap(tester, find.text('Essay.pdf'));
      await _tap(tester, find.text('Import 1 item'));
      expect(backend.bodies('fn_import_from_cloud').single['tag_ids'],
          ['sh-theo']);
      await tester.pump(const Duration(seconds: 61));
    });
  });

  group('leaving the page', () {
    testWidgets('Not now returns to the Library with nothing queued',
        (tester) async {
      final backend = _Backend(answer: _granted);
      ApiService.instance.httpClientAdapter = backend;
      _claimReturn();
      await pumpSources(tester, SourcesStubService(),
          cloud: _Cloud([_drive]), shelves: _shelves);
      await _settle(tester);
      expect(find.text('Essay.pdf'), findsOneWidget);
      await _tap(tester, find.widgetWithText(KitButton, 'Not now'));
      expect(find.text('The Library'), findsWidgets);
      expect(backend.bodies('fn_import_from_cloud'), isEmpty);
      expect(find.textContaining('Connected to Google Drive'), findsNothing,
          reason: 'the Library nudge is retired (ADR-201)');
    });
  });
}
