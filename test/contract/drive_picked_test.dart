// F-203 — Google Drive reads only the files you pick (ADR-275, INV-44;
// screens/sources.md §The OAuth return and §A service's page; settings.md
// §Sources section). A Drive connection is drawn from its own `access` —
// never from the mode alone: a picked one has no file browser, no sync
// settings and no filing, its import action is Add files (the one connect
// entry point, which opens Google's picker), Settings → Sources has no row for
// it, and the connect page answers a picker consent by what the claim
// imported, never by a listing.
//
// The port of the reference's `tests/contract/drive-picked.test.js`, case for
// case and in its order, plus the Settings row and the Disconnect confirm the
// reference asserts elsewhere. Every connect-page state is reached the way a
// reader reaches it — a held return spent by the real connect page under a
// real GoRouter — and only the transport is canned.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/models/cloud_integration.dart';
import 'package:flutter_app/pages/settings/sources_section.dart';
import 'package:flutter_app/pages/sources/cloud_sync_copy.dart';
import 'package:flutter_app/pages/sources/oauth_return.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/shared/cloud_return.dart';
import 'package:flutter_app/state/cloud_notifier.dart';
import 'package:flutter_app/state/org_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

import 'sources_harness.dart';

const _picked = CloudIntegration(
  provider: 'google_drive',
  tokenValid: true,
  providerEmail: 'reader@example.com',
  access: 'picked',
  grantedAccess: 'picked',
  includeTypes: ['pdf'],
);

const _full = CloudIntegration(
  provider: 'google_drive',
  tokenValid: true,
  providerEmail: 'reader@example.com',
  access: 'full',
  grantedAccess: 'full',
  includeTypes: ['pdf'],
);

const _notion = CloudIntegration(provider: 'notion', tokenValid: true);

Map<String, dynamic> _answer([Map<String, dynamic> over = const {}]) => {
      'cloud_connect': 'success',
      'provider': 'google_drive',
      'connection': 'new',
      'picked_files': 2,
      'queued_files': 2,
      'import_error': null,
      ...over,
    };

/// The integrations read, answered: [connected] and nothing else, under the
/// Drive [mode] (`drive_access`).
class _Cloud extends QuietCloud {
  _Cloud([this.connected = const [], this.mode = 'picked']);
  final List<CloudIntegration> connected;
  final String mode;

  @override
  String? get driveAccess => mode;

  @override
  bool get integrationsLoaded => true;
  @override
  List<CloudIntegration> get integrations => connected;
  @override
  CloudIntegration? integrationFor(String provider) {
    for (final i in connected) {
      if (i.provider == provider) return i;
    }
    return null;
  }
}

/// The backend, canned: the claim's [answer], the connect's [connect] reply
/// (no sign-in link by default), and a listing that must never be asked for.
/// Records every request.
class _Backend implements HttpClientAdapter {
  _Backend({this.answer, this.connect});

  final Map<String, dynamic>? answer;
  final (int, Object)? connect;
  final sent = <RequestOptions>[];

  int get listed =>
      sent.where((o) => o.path.endsWith('/fn_list_cloud_files')).length;

  List<Map<String, dynamic>> bodies(String fn) => [
        for (final o in sent)
          if (o.path.endsWith('/$fn')) (o.data as Map).cast<String, dynamic>()
      ];

  (int, Object) _reply(RequestOptions o) {
    switch (o.path.split('/').last) {
      case 'fn_claim_cloud_connection':
        return (200, answer ?? const {});
      case 'fn_connect_cloud_storage':
        return connect ?? (200, const {'authUrl': null});
      case 'fn_list_cloud_files':
        return (200, {'items': const [], 'nextPageToken': null});
      case 'fn_get_cloud_integrations':
        return (200, {
          'integrations': [
            {
              'provider': 'google_drive',
              'token_valid': true,
              'access': 'picked',
              'granted_access': 'picked',
            }
          ],
          'drive_access': 'full',
        });
    }
    return (404, {'error': 'not stubbed'});
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

void _claimReturn() => CloudReturn.hold(
    const CloudReturn('claim', claim: 'c1', provider: 'google_drive'));

/// A view wide enough that the D sheet (Contents, Figures) is drawn beside
/// the column, and a §18 confirm fits.
void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(1440, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

List<String> _heads() => [
      for (final e in find.byType(KitSecHead).evaluate())
        (e.widget as KitSecHead).title
    ];

void main() {
  setUp(() => ApiService.instance.tokenProvider = () async => 'test-token');
  tearDown(() {
    ApiService.instance.resetTestSeams();
    CloudReturn.take();
    CloudReturn.forgetConnecting();
    ConnectHandoff.take();
  });

  group('a Drive connection says its own access', () {
    test('`access` and `granted_access` are read; absent is not picked', () {
      final p = CloudIntegration.fromJson(const {
        'provider': 'google_drive',
        'access': 'picked',
        'granted_access': 'picked',
      });
      expect((p.access, p.grantedAccess, p.picked), ('picked', 'picked', true));
      // The mode alone never draws a connection: a full grant is full.
      expect(
          CloudIntegration.fromJson(const {
            'provider': 'google_drive',
            'access': 'full',
            'granted_access': 'full',
          }).picked,
          isFalse);
      expect(
          CloudIntegration.fromJson(const {'provider': 'notion'}).picked,
          isFalse);
      expect(
          CloudIntegration.fromJson(const {
            'provider': 'google_drive',
            'access': 7,
          }).access,
          isNull,
          reason: 'an unreadable value is no access, never a crash');
    });

    test('the integrations read keeps the mode, `drive_access`, beside each '
        'connection’s own access', () async {
      ApiService.instance.httpClientAdapter = _Backend();
      final cloud = CloudNotifier();
      addTearDown(cloud.dispose);
      expect(cloud.driveAccess, isNull);
      await cloud.loadIntegrations();
      expect(cloud.driveAccess, 'full');
      expect(cloud.integrationFor('google_drive')!.picked, isTrue,
          reason: 'picked by its grant: the mode never draws a connection');
    });
  });

  group('a picker consent is answered by its import', () {
    test('is told apart by `picked_files`, and `connection` never chooses its '
        'view', () {
      ReturnView v(Map<String, dynamic> a) =>
          returnView(OAuthReturn(ReturnPhase.claimed, answer: a));
      expect(pickedClaim(_answer()), isNotNull);
      expect(
          pickedClaim(const {'cloud_connect': 'success', 'connection': 'new'}),
          isNull);
      expect(pickedClaim(_answer({'cloud_connect': 'error'})), isNull);
      for (final connection in ['new', 'reconnected']) {
        expect(v(_answer({'connection': connection})), ReturnView.pickedQueued);
        expect(
            v(_answer({
              'connection': connection,
              'queued_files': 0,
              'import_error': 'No room.',
            })),
            ReturnView.pickedRefused);
        expect(
            v(_answer({
              'connection': connection,
              'picked_files': 0,
              'queued_files': 0,
            })),
            ReturnView.pickedEmpty);
      }
      // A consent with no picker is what it was.
      expect(
          v(const {'cloud_connect': 'success', 'connection': 'reconnected'}),
          ReturnView.already);
    });

    test('leaves for the Library with the counted files and the import '
        'kickoff, as Bring in does', () {
      final l = pickedLeave(_answer(), 'Google Drive')!;
      expect((l.note, l.provider, l.queuedFiles),
          ('Queued 2 files from Google Drive.', 'google_drive', 2));
      expect(pickedLeave(_answer({'queued_files': 1}), 'Google Drive')!.note,
          'Queued 1 file from Google Drive.');
      // A half-queued import says the server's sentence after the count,
      // verbatim.
      expect(
          pickedLeave(
                  _answer({
                    'queued_files': 50,
                    'picked_files': 60,
                    'import_error': 'Use Add files to pick the other 10.',
                  }),
                  'Google Drive')!
              .note,
          'Queued 50 files from Google Drive. Use Add files to pick the other '
          '10.');
      expect(pickedLeave(_answer({'queued_files': 0}), 'Google Drive'), isNull);
      expect(
          pickedLeave(const {'cloud_connect': 'success', 'connection': 'new'},
              'Google Drive'),
          isNull);
    });

    testWidgets('a claim that queued files lands on the Library at once, '
        'never listing', (tester) async {
      final backend =
          _Backend(answer: _answer({'connection': 'reconnected'}));
      ApiService.instance.httpClientAdapter = backend;
      final cloud = _Cloud(const [_picked]);
      _claimReturn();
      final router =
          await pumpConnectApp(tester, SourcesStubService(), cloud: cloud);
      await _settle(tester);
      expect(routerPath(router), '/sources');
      expect(find.text('Queued 2 files from Google Drive.'), findsOneWidget);
      final k = cloud.kickoff!;
      expect((k.provider, k.queuedFolders, k.queuedFiles),
          ('google_drive', 0, 2));
      expect(backend.listed, 0);
      // The kickoff's discovery window.
      await tester.pump(const Duration(seconds: 61));
    });

    testWidgets('nothing queued with a sentence is Not Brought In: the '
        'server’s sentence verbatim, and Add files again', (tester) async {
      const sentence = 'Your library holds 100 of the Free plan’s 100 sources, '
          'so 2 more will not fit. Remove some to add others, or ask about '
          'upgrading.';
      final backend = _Backend(
          answer: _answer({'queued_files': 0, 'import_error': sentence}));
      ApiService.instance.httpClientAdapter = backend;
      _claimReturn();
      final router = await pumpConnectApp(tester, SourcesStubService(),
          cloud: _Cloud(const [_picked]));
      await _settle(tester);
      expect(routerPath(router), '/connect/google_drive');
      expect(find.text('Not Brought In'), findsOneWidget);
      expect(
          find.text('Google Drive is connected, but the files you picked were '
              'not brought in.'),
          findsOneWidget);
      // The folio is the Connected/Already views', set in capitals with D's
      // no-break space before each dot.
      expect(find.textContaining('CONNECTED\u00a0· '), findsOneWidget);
      expect(find.textContaining('READER@EXAMPLE.COM'), findsOneWidget);
      expect(find.textContaining('RETURNED FROM'), findsNothing);
      final block = find.byType(KitFailureBlock);
      expect(
          find.descendant(
              of: block,
              matching: find.text('The picked files were not brought in.')),
          findsOneWidget);
      expect(find.descendant(of: block, matching: find.textContaining(sentence)),
          findsOneWidget);
      await _tap(tester, find.widgetWithText(KitButton, 'Add files'));
      expect(backend.bodies('fn_connect_cloud_storage'), [
        {'provider': 'google_drive', 'return': 'app'}
      ], reason: 'the one connect entry point, the in-app auth session');
      expect(
          find.text('The sign-in link did not come back. Try connecting '
              'again.'),
          findsOneWidget);
      expect(backend.listed, 0);
    });

    testWidgets('nothing picked is Nothing Picked, with Add files and the '
        'Library', (tester) async {
      final backend =
          _Backend(answer: _answer({'picked_files': 0, 'queued_files': 0}));
      ApiService.instance.httpClientAdapter = backend;
      _claimReturn();
      final router = await pumpConnectApp(tester, SourcesStubService(),
          cloud: _Cloud(const [_picked]));
      await _settle(tester);
      expect(find.text('Nothing Picked'), findsOneWidget);
      expect(
          find.text('Google Drive is connected, but no files came back from '
              'its picker.'),
          findsOneWidget);
      expect(
          find.text('Use Add files to open Google Drive’s picker again. The '
              'connection stays live in the meantime.'),
          findsOneWidget);
      expect(find.text('0 files picked'), findsOneWidget);
      expect(find.widgetWithText(KitButton, 'Add files'), findsOneWidget);
      expect(find.byType(KitFailureBlock), findsNothing);
      await _tap(tester, find.widgetWithText(KitButton, 'Back to library'));
      expect(routerPath(router), '/sources');
      expect(backend.listed, 0);
    });

    testWidgets('reopened with nothing to answer, a picked Drive’s connect '
        'page is the Library’s', (tester) async {
      final backend = _Backend();
      ApiService.instance.httpClientAdapter = backend;
      final router = await pumpConnectApp(tester, SourcesStubService(),
          cloud: _Cloud(const [_picked]), initial: '/connect/google_drive');
      await _settle(tester);
      expect(routerPath(router), '/sources');
      expect(backend.listed, 0);
    });
  });

  group('a picked Drive’s own page (INV-44)', () {
    testWidgets('holds three sections — no Sync settings, no Filing — and '
        'offers Add files, not a browser', (tester) async {
      _wide(tester);
      await pumpServicePage(tester, SourcesStubService(),
          provider: 'google_drive', cloud: _Cloud(const [_picked]));
      expect(find.widgetWithText(KitSettingLink, 'Add files…'), findsOneWidget);
      expect(_heads(), ['Bring in', 'Import history', 'Connection']);
      expect([
        for (final e in find.byType(KitSecHead).evaluate())
          (e.widget as KitSecHead).n
      ], [0, 1, 2], reason: 'numbered without the two it lacks');
      final contents =
          tester.widget<KitContents>(find.byType(KitContents).first);
      expect([for (final c in contents.items) c.label],
          ['Bring in', 'Import history', 'Connection']);
      expect(find.text('Browse files…'), findsNothing);
      expect(find.textContaining('Sync now'), findsNothing);
      expect(find.text('Organization settings'), findsNothing);
      expect(
          find.text('Pick files in Google Drive’s own window. NoteLetter reads '
              'only the files you pick there — nothing else in your Drive.'),
          findsOneWidget);
      final figures = tester.widget<KitFigures>(find.byType(KitFigures));
      expect(figures.rows, [
        ('Account', 'reader@example.com'),
        ('Access', 'Files you pick'),
      ], reason: 'no Auto-sync and no Last synced');
    });

    testWidgets('Add files is the one connect entry point; a refusal is the '
        'server’s sentence under it', (tester) async {
      final backend = _Backend(
          connect: (502, {'error': 'Could not reach Google Drive.'}));
      ApiService.instance.httpClientAdapter = backend;
      await pumpServicePage(tester, SourcesStubService(),
          provider: 'google_drive', cloud: _Cloud(const [_picked]));
      await _tap(tester, find.widgetWithText(KitSettingLink, 'Add files…'));
      expect(backend.bodies('fn_connect_cloud_storage'), [
        {'provider': 'google_drive', 'return': 'app'}
      ]);
      expect(
          find.descendant(
              of: find.byType(KitFailureInline),
              matching: find.textContaining('Could not reach Google Drive.')),
          findsOneWidget);
      expect(find.widgetWithText(KitSettingLink, 'Add files…'), findsOneWidget,
          reason: 'not busy once it answered');
      expect(backend.listed, 0);
    });

    testWidgets('a connect with no sign-in link says so under the head',
        (tester) async {
      ApiService.instance.httpClientAdapter = _Backend();
      await pumpServicePage(tester, SourcesStubService(),
          provider: 'google_drive', cloud: _Cloud(const [_picked]));
      await _tap(tester, find.widgetWithText(KitSettingLink, 'Add files…'));
      expect(
          find.text('The sign-in link did not come back. Try connecting '
              'again.'),
          findsOneWidget);
    });

    testWidgets('picked by its grant while the mode is full, the action says '
        'Connect asks for the whole Drive', (tester) async {
      final backend = _Backend();
      ApiService.instance.httpClientAdapter = backend;
      await pumpServicePage(tester, SourcesStubService(),
          provider: 'google_drive', cloud: _Cloud(const [_picked], 'full'));
      expect(find.widgetWithText(KitSettingLink, 'Connect for folders…'),
          findsOneWidget);
      expect(_heads(), ['Bring in', 'Import history', 'Connection']);
      expect(
          find.text('Google Drive was connected for the files you pick only. '
              'Connect it again to let NoteLetter open its folders.'),
          findsOneWidget);
      expect(find.text('Add files…'), findsNothing);
      await _tap(
          tester, find.widgetWithText(KitSettingLink, 'Connect for folders…'));
      expect(backend.bodies('fn_connect_cloud_storage'), [
        {'provider': 'google_drive', 'return': 'app'}
      ], reason: 'the same connect entry point');
    });

    testWidgets('a Drive with full access keeps every section it had',
        (tester) async {
      _wide(tester);
      await pumpServicePage(tester, SourcesStubService(),
          provider: 'google_drive', cloud: _Cloud(const [_full], 'full'));
      expect(find.widgetWithText(KitSettingLink, 'Browse files…'),
          findsOneWidget);
      expect(_heads(), [
        'Bring in',
        'Sync settings',
        'Filing',
        'Import history',
        'Connection'
      ]);
      expect(find.text('Add files…'), findsNothing);
      final figures = tester.widget<KitFigures>(find.byType(KitFigures));
      expect([for (final (k, _) in figures.rows) k],
          ['Account', 'Access', 'Auto-sync', 'Last synced']);
    });

    for (final (what, drive, organized, fresh) in [
      ('picked', _picked, false, 'files'),
      ('full', _full, true, 'folders'),
    ]) {
      testWidgets('the Disconnect confirm of a $what Drive', (tester) async {
        _wide(tester);
        await pumpServicePage(tester, SourcesStubService(),
            provider: 'google_drive', cloud: _Cloud([drive]));
        final control = find.widgetWithText(KitLibAct, 'Disconnect');
        await tester.ensureVisible(control);
        await tester.tap(control);
        await tester.pumpAndSettle();
        expect(find.text('Disconnect Google Drive?'), findsOneWidget);
        expect(
            find.textContaining('The folders it organized are archived, and '
                'its suggestions expire.'),
            organized ? findsOneWidget : findsNothing);
        expect(
            find.textContaining('Reconnecting starts a fresh pick of $fresh.'),
            findsOneWidget);
        await tester.tap(find.widgetWithText(KitButton, 'Stay connected'));
        await tester.pumpAndSettle();
      });
    }

    test('the confirm’s consequences drop the organized folders for a picked '
        'Drive only', () {
      expect(
          disconnectConsequences('Google Drive', picked: true),
          'Imports from Google Drive that are waiting for your review or not '
          'yet downloaded stop; files already downloaded finish importing.');
      expect(disconnectConsequences('Google Drive'),
          endsWith(' The folders it organized are archived, and its '
              'suggestions expire.'));
    });
  });

  group('Settings → Sources', () {
    Future<void> mount(WidgetTester tester, List<CloudIntegration> connected) async {
      FirestoreService.instance = SourcesStubService();
      addTearDown(FirestoreService.resetInstance);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<CloudNotifier>(
              create: (_) => _Cloud(connected)),
          ChangeNotifierProvider<OrgNotifier>(create: (_) => QuietOrg()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
              body: KitPage(
                  width: KitFrameWidth.reading, child: SourcesSection())),
        ),
      ));
      await tester.pumpAndSettle();
    }

    List<String> rows() => [
          for (final e in find.byType(KitSettingRow).evaluate())
            (e.widget as KitSettingRow).title
        ];

    testWidgets('a picked Drive has no organization row; another provider '
        'keeps its own', (tester) async {
      await mount(tester, const [_picked, _notion]);
      expect(rows(), contains('Notion'));
      expect(rows(), isNot(contains('Google Drive')));
    });

    testWidgets('a picked Drive alone draws no section at all',
        (tester) async {
      await mount(tester, const [_picked]);
      expect(SourcesSection.shownFor(_Cloud(const [_picked])), isFalse);
      expect(find.byType(KitSettingRow), findsNothing);
      expect(find.text('Confidence threshold'), findsNothing);
    });

    testWidgets('a Drive with full access keeps its row', (tester) async {
      await mount(tester, const [_full]);
      expect(SourcesSection.shownFor(_Cloud(const [_full])), isTrue);
      expect(rows(), contains('Google Drive'));
    });
  });
}
