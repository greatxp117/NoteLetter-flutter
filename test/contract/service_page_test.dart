// A service's own page and the import row (5.59.0, ADR-213;
// screens/sources.md §A service's page, §Trust & feedback). Xavier,
// 2026-11-04: rows should show their shelves and open their source, a
// connected service says Manage and lives on its own page, the Notion mark is
// white in dark mode, and "Import these types" was unclear.
//
// The port of the reference's `tests/contract/service-page.test.js`, case for
// case and in its order: it is F-160's acceptance list.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/models/cloud_integration.dart';
import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/import_job.dart';
import 'package:flutter_app/models/tag.dart';
import 'package:flutter_app/pages/sources/cloud_imports.dart';
import 'package:flutter_app/pages/sources/cloud_sync_copy.dart';
import 'package:flutter_app/pages/sources/sync_settings_panel.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/shared/reader_origin.dart';
import 'package:flutter_app/state/cloud_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/theme/tokens.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

import 'sources_harness.dart';

const _notion = CloudIntegration(
  provider: 'notion',
  tokenValid: true,
  providerEmail: 'x@example.com',
  includeTypes: ['notion'],
);

/// The integrations read, answered: [connected] and nothing else.
class _Read extends QuietCloud {
  _Read([this.connected = const [_notion]]);
  final List<CloudIntegration> connected;

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

/// Answers each request from [reply] and records what was sent.
class _Recorder implements HttpClientAdapter {
  _Recorder(this.reply);

  final (int, Object) Function(RequestOptions o) reply;
  final List<RequestOptions> sent = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    sent.add(options);
    final (status, body) = reply(options);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

final _day = DateTime.utc(2026, 11, 4, 12).millisecondsSinceEpoch;

ImportJob _job({
  String status = 'complete',
  String? documentId,
  String mime = 'application/x-notion-page',
  String? skip,
}) =>
    ImportJob(
      id: 'j1',
      provider: 'notion',
      providerFileName: 'A page',
      status: status,
      documentId: documentId,
      mimeType: mime,
      skipReason: skip,
      createdAt: _day,
    );

Document _doc(String id,
        {String type = 'plain',
        DocumentStatus status = DocumentStatus.complete,
        List<String> tagIds = const []}) =>
    Document(
        id: id,
        userId: 'u1',
        title: 'A page',
        type: type,
        status: status,
        tagIds: tagIds);

Finder _row() => find.byType(ImportJobRow);

/// The bundled faces, so a width is a real width: the test font draws every
/// glyph as a full em box (the loader connect_card_test.dart uses).
Future<void> _loadRealFonts() async {
  const faces = {
    'Geist': ['Geist-Regular.ttf', 'Geist-Medium.ttf', 'Geist-SemiBold.ttf'],
    'Geist Mono': ['GeistMono-Regular.ttf', 'GeistMono-Medium.ttf'],
    'Source Serif 4': [
      'SourceSerif4-Variable.ttf',
      'SourceSerif4-Italic-Variable.ttf',
    ],
  };
  for (final e in faces.entries) {
    final loader = FontLoader(e.key);
    for (final f in e.value) {
      loader.addFont(rootBundle.load('assets/fonts/$f'));
    }
    await loader.load();
  }
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}

void main() {
  setUp(() => ApiService.instance.tokenProvider = () async => 'test-token');
  tearDown(() {
    ApiService.instance.resetTestSeams();
    FirestoreService.resetInstance();
  });

  group('the address', () {
    test('/sources/{provider} is the service; add and the bare path keep their '
        'meaning', () {
      final src = File('lib/router.dart').readAsStringSync();
      final add = src.indexOf("path: '/sources/add'");
      final service = src.indexOf("path: '/sources/:provider'");
      final bare = src.indexOf("path: '/sources',");
      expect(add, isNonNegative);
      expect(service, isNonNegative);
      expect(bare, isNonNegative);
      expect(add, lessThan(service),
          reason: '/sources/add is declared ahead of /sources/:provider');
    });

    test('a Reader opened from it names the service as the way back', () {
      final o = readerOrigin('/sources/notion');
      expect((o.label, o.path), ('Notion', '/sources/notion'));
      expect(readerOrigin('/sources/add').label, 'Add a source');
      expect(readerOrigin('/sources/gdrive').path, '/sources',
          reason: 'a provider this app does not have is no origin');
    });
  });

  group('the page stands only for a connected service', () {
    testWidgets('opens the Library when the service is not connected',
        (tester) async {
      final router = await pumpServicePage(tester, SourcesStubService(),
          provider: 'notion', cloud: _Read(const []));
      await tester.pump();
      expect(routerPath(router), '/sources');
    });

    testWidgets('opens the Library for an id that names no service',
        (tester) async {
      final router = await pumpServicePage(tester, SourcesStubService(),
          provider: 'gdrive', cloud: _Read());
      await tester.pump();
      expect(routerPath(router), '/sources');
    });

    testWidgets(
        'a refused read is said here, and is not read as "not connected" (§14)',
        (tester) async {
      final router = await pumpServicePage(tester, SourcesStubService(),
          provider: 'notion',
          cloud: UnreadCloud('The request did not complete.'));
      await tester.pump();
      expect(find.text('Your connected accounts could not be read.'),
          findsOneWidget);
      expect(routerPath(router), '/sources/notion');
    });

    testWidgets('holds its five sections, in order', (tester) async {
      await pumpServicePage(tester, SourcesStubService(),
          provider: 'notion', cloud: _Read());
      expect(find.widgetWithText(KitSettingLink, 'Browse pages…'),
          findsOneWidget);
      expect([
        for (final e in find.byType(KitSecHead).evaluate())
          (e.widget as KitSecHead).title
      ], ['Bring in', 'Sync settings', 'Filing', 'Import history', 'Connection']);
    });
  });

  group('the door to Settings → Sources', () {
    testWidgets(
        'stands on the page whether or not organizing is on, because Settings '
        'is where it is turned on', (tester) async {
      final router = await pumpServicePage(tester, SourcesStubService(),
          provider: 'notion', cloud: _Read());
      expect(find.text('NoteLetter files what comes in from Notion on your '
              'shelves as it reads it. Organizing the folders in Notion itself '
              'is off.'),
          findsOneWidget);
      final door = find.widgetWithText(KitSettingLink, 'Organization settings');
      await tester.ensureVisible(door);
      await tester.tap(door);
      await tester.pumpAndSettle();
      expect(routerPath(router), '/settings/sources');
    });
  });

  group('Disconnect lives on the page, behind its §18 confirm', () {
    setUpAll(_loadRealFonts);
    Future<void> openConfirm(WidgetTester tester) async {
      // A phone, where the confirm has to fit.
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pump();
      final control = find.widgetWithText(KitLibAct, 'Disconnect');
      await tester.ensureVisible(control);
      await tester.tap(control);
      await tester.pumpAndSettle();
    }

    testWidgets(
        'names the service; its answer is the Library\'s to say, and the page '
        'leaves', (tester) async {
      final rec = _Recorder((_) => (200, {'revoked': null}));
      ApiService.instance.httpClientAdapter = rec;
      final cloud = _Read();
      final router = await pumpServicePage(tester, SourcesStubService(),
          provider: 'notion', cloud: cloud);
      await openConfirm(tester);
      expect(find.text('Disconnect Notion?'), findsOneWidget);
      expect(rec.sent, isEmpty, reason: 'nothing is sent before the confirm');
      await tester.tap(find.widgetWithText(KitButton, 'Disconnect').last);
      await tester.pumpAndSettle();
      expect(routerPath(router), '/sources');
      expect(rec.sent.single.path, endsWith('/fn_disconnect_cloud_storage'));
      expect((rec.sent.single.data as Map)['provider'], 'notion');
      expect(
          disconnectOutcome('notion', 'Notion', cloud.lastDisconnect!.$2),
          contains('Notion is disconnected.'));
    });

    testWidgets('a refusal stays in the confirm, with the server\'s sentence',
        (tester) async {
      ApiService.instance.httpClientAdapter = _Recorder((_) => (
            502,
            {'error': 'The provider did not answer.', 'error_code': 'UPSTREAM'}
          ));
      final router = await pumpServicePage(tester, SourcesStubService(),
          provider: 'notion', cloud: _Read());
      await openConfirm(tester);
      await tester.tap(find.widgetWithText(KitButton, 'Disconnect').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('The provider did not answer.'), findsOneWidget);
      expect(find.text('Disconnect Notion?'), findsOneWidget,
          reason: 'the confirm stays open on a refusal');
      expect(routerPath(router), '/sources/notion');
    });
  });

  group('the Library\'s service row', () {
    testWidgets('says Manage, and an expired sign-in says so with Reconnect '
        'beside it', (tester) async {
      await pumpSources(tester, SourcesStubService(),
          cloud: _Read(const [
            _notion,
            CloudIntegration(
                provider: 'google_drive',
                tokenValid: false,
                status: 'reconnect_required'),
          ]));
      Finder row(String name) => find.widgetWithText(KitServiceRow, name);
      List<String> acts(String name) => [
            for (final e in find
                .descendant(of: row(name), matching: find.byType(KitLibAct))
                .evaluate())
              (e.widget as KitLibAct).label
          ];
      expect(acts('Notion'), ['Manage']);
      expect(find.descendant(of: row('Notion'), matching: find.text('x@example.com')),
          findsOneWidget);
      expect(acts('Google Drive'), ['Reconnect', 'Manage']);
      expect(
          find.descendant(
              of: row('Google Drive'), matching: find.text('Sign-in expired')),
          findsOneWidget);
      expect(find.text('Disconnect'), findsNothing);
    });
  });

  group('an import row', () {
    Future<void> page(WidgetTester tester, List<ImportJob> jobs,
        {List<Document> documents = const [],
        List<Tag> shelves = const []}) async {
      await pumpServicePage(
          tester,
          SourcesStubService(
              jobs: Stream.value(jobs), documents: Stream.value(documents)),
          provider: 'notion',
          cloud: _Read(),
          shelves: shelves);
      // Bounded: a working row's pill spins, and a live spinner never
      // settles.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    List<String> tags() => [
          for (final e in find
              .descendant(of: _row(), matching: find.byType(KitShelfTag))
              .evaluate())
            (e.widget as KitShelfTag).title ?? 'Unshelved'
        ];

    Finder link() => find.byKey(const ValueKey('import-row-link-j1'));

    testWidgets(
        'opens its source, and says every shelf holding it, the home shelf '
        'first', (tester) async {
      await page(tester, [_job(documentId: 'd1')],
          documents: [_doc('d1', tagIds: ['s2', 's1'])],
          shelves: const [
            Tag(id: 's1', userId: 'u1', title: 'Essays', color: 'sage'),
            Tag(id: 's2', userId: 'u1', title: 'Theology', color: 'brick'),
          ]);
      expect(_row(), findsWidgets);
      expect(tags()..sort(), ['Essays', 'Theology']);
      final lead = tester.widget<KitCoverLead>(
          find.descendant(of: _row().first, matching: find.byType(KitCoverLead)));
      expect(kitCoverOf(lead.type).$2, 'Note');
      expect(
          find.descendant(
              of: _row().first, matching: find.textContaining('Notion')),
          findsWidgets);
      expect(link(), findsOneWidget);
    });

    testWidgets('a complete source on no shelf says Unshelved', (tester) async {
      await page(tester, [_job(documentId: 'd1')],
          documents: [_doc('d1')]);
      expect(tags(), ['Unshelved']);
    });

    testWidgets('a job whose document is gone is no link and claims no shelf',
        (tester) async {
      await page(tester, [_job(documentId: 'removed')]);
      expect(link(), findsNothing);
      expect(find.byType(KitImportShelves), findsNothing);
    });

    testWidgets(
        'a source still being read draws no shelf (kit §32), and is already a '
        'link', (tester) async {
      await page(tester, [_job(documentId: 'd1', status: 'processing')],
          documents: [
            _doc('d1', status: DocumentStatus.processing, tagIds: ['s1'])
          ],
          shelves: const [Tag(id: 's1', userId: 'u1', title: 'Essays')]);
      expect(link(), findsOneWidget);
      expect(find.byType(KitImportShelves), findsNothing);
    });

    testWidgets(
        'before a document exists its object comes from the file; once it '
        'does, from the document', (tester) async {
      await page(tester, [_job(status: 'downloading')]);
      KitCoverLead lead() => tester.widget<KitCoverLead>(
          find.descendant(of: _row().first, matching: find.byType(KitCoverLead)));
      expect(kitCoverOf(lead().type).$2, 'Note');
      await tester.pumpWidget(const SizedBox.shrink());
      await page(tester, [_job(documentId: 'd1', mime: 'application/pdf')],
          documents: [_doc('d1', type: 'pptx')]);
      expect(kitCoverOf(lead().type).$2, 'Slides');
    });

    testWidgets('Duplicate rows lose View once the row itself opens the source',
        (tester) async {
      await page(tester,
          [_job(documentId: 'd1', status: 'skipped', skip: 'duplicate')],
          documents: [_doc('d1')]);
      expect(
          find.descendant(
              of: _row(), matching: find.widgetWithText(KitSettingLink, 'View')),
          findsNothing);
      expect(link(), findsOneWidget);
    });

    test('the object before a document is the backend\'s mime rule', () {
      expect(mimeSourceType(null), 'plain');
      expect(mimeSourceType('application/x-notion-page'), 'plain');
      expect(mimeSourceType('application/pdf'), 'pdf');
      expect(mimeSourceType('application/msword'), 'docx');
      expect(mimeSourceType('application/vnd.ms-powerpoint'), 'pptx');
      expect(mimeSourceType('application/epub+zip'), 'epub');
      expect(mimeSourceType('image/png'), 'image');
      expect(mimeSourceType('audio/mpeg'), 'audio');
      expect(mimeSourceType('video/mp4'), 'video');
    });
  });

  // F-160's deviation, closed in round 2: the 202's count is §Bring in's
  // notice under the closed picker (web `CloudImportPanel`'s `notice`), never
  // a toast. Mutant: the toast back in `_confirm` — red.
  group('what an import queued', () {
    testWidgets('is said in Bring in, in the server\'s figures, not a toast',
        (tester) async {
      ApiService.instance.httpClientAdapter = _Recorder((o) {
        if (o.path.contains('fn_list_cloud_files')) {
          return (200, {
            'items': [
              {'id': 'f1', 'name': 'Essay.pdf', 'type': 'file',
               'mime_type': 'application/pdf'},
            ],
            'nextPageToken': null,
          });
        }
        return (202, {'queued_folders': 0, 'queued_files': 1});
      });
      final cloud = _Read(const [
        CloudIntegration(provider: 'google_drive', tokenValid: true),
      ]);
      await pumpServicePage(tester, SourcesStubService(),
          provider: 'google_drive', cloud: cloud);
      // Opened without awaiting it inside the fake-async zone, as the
      // tandem suite's picker cases do; the listing lands over bounded pumps.
      unawaited(cloud.openPicker('google_drive'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.ensureVisible(find.byType(KitCheckbox));
      await tester.tap(find.byType(KitCheckbox));
      await tester.pump();
      await tester.ensureVisible(find.text('Import 1 item'));
      await tester.tap(find.text('Import 1 item'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Queued 0 folders and 1 file from Google Drive.'),
          findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(cloudQueuedNotice(1, 1, 'Notion'),
          'Queued 1 folder and 1 file from Notion.');
      await tester.pump(const Duration(seconds: 61));
    });
  });

  group('the Notion mark', () {
    test('a mono mark takes its colour from the page; a colour mark keeps its '
        'own', () {
      expect(KitProviderLogo.isMono('notion'), isTrue);
      for (final p in ['google_drive', 'onedrive', 'dropbox']) {
        expect(KitProviderLogo.isMono(p), isFalse, reason: p);
      }
    });

    Future<BuildContext> themed(WidgetTester tester, bool dark,
        [Widget child = const SizedBox()]) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        // A fresh app per theme: a theme change animates, and the first frame
        // after it is still the old theme.
        key: ValueKey(dark),
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: Scaffold(
          body: Builder(builder: (c) {
            ctx = c;
            return child;
          }),
        ),
      ));
      return ctx;
    }

    testWidgets('white in both dark paths, and a plate holding it follows the '
        'page', (tester) async {
      var c = await themed(tester, false);
      expect(KitProviderLogo.monoColor(c), const Color(0xFF000000));
      expect(KitProviderLogo.plateColor(c, 'notion'), const Color(0xFFFFFFFF));
      c = await themed(tester, true);
      expect(KitProviderLogo.monoColor(c), const Color(0xFFFFFFFF));
      expect(KitProviderLogo.plateColor(c, 'notion'), Tokens.of(c).surface);
      expect(KitProviderLogo.plateColor(c, 'dropbox'), const Color(0xFFFFFFFF),
          reason: 'a colour mark keeps its white plate');

      // Every plate that holds a vendor's mark: the service row, a setting
      // row, the quick-add chip and the connect card all ask the one rule.
      for (final f in [
        'lib/widgets/kit/kit_d_library.dart',
        'lib/widgets/kit/kit_rows.dart',
        'lib/widgets/kit/kit_quick_add.dart',
        'lib/widgets/kit/kit_cards.dart',
      ]) {
        expect(File(f).readAsStringSync(), contains('KitProviderLogo.plateColor('),
            reason: f);
      }
      // And the service row's plate, drawn dark.
      await themed(
          tester,
          true,
          const KitServiceRow(
              provider: 'notion', name: 'Notion', connected: true));
      final plate = tester.widget<Container>(find
          .ancestor(
              of: find.byType(KitProviderLogo), matching: find.byType(Container))
          .first);
      expect((plate.decoration as BoxDecoration).color,
          Tokens.of(tester.element(find.byType(KitServiceRow))).surface);
    });
  });

  group('what a sync brings in', () {
    Future<void> panel(WidgetTester tester, CloudIntegration i) async {
      await tester.pumpWidget(ChangeNotifierProvider<CloudNotifier>.value(
        value: QuietCloud(),
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: SyncSettingsPanel(
                  providerId: i.provider, integration: i, embedded: true),
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    List<(String, bool)> choices(WidgetTester tester) => [
          for (final e in find.byType(KitTypeChoice).evaluate())
            ((e.widget as KitTypeChoice).label, (e.widget as KitTypeChoice).checked)
        ];

    testWidgets('says it filters a sync, not what is picked by hand, and ticks '
        'rather than lights', (tester) async {
      await panel(
          tester,
          const CloudIntegration(
              provider: 'google_drive', tokenValid: true, includeTypes: ['pdf']));
      expect(find.textContaining('IMPORT THESE TYPES'), findsNothing);
      expect(find.textContaining('skipped entirely'), findsNothing);
      expect(find.text('FILE TYPES A SYNC BRINGS IN'), findsOneWidget);
      expect(
          find.textContaining(
              'Files you pick with Browse files… come in either way.'),
          findsOneWidget);
      expect(choices(tester), [
        ('PDF', true),
        ('Word', false),
        ('PowerPoint', false),
        ('EPUB', false),
      ]);
      // A checkbox to assistive technology.
      expect(tester.getSemantics(find.byType(KitTypeChoice).first),
          isSemantics(hasCheckedState: true, isChecked: true, label: 'PDF'));
      expect(tester.getSemantics(find.byType(KitTypeChoice).at(1)),
          isSemantics(hasCheckedState: true, isChecked: false, label: 'Word'));
    });

    testWidgets('Notion says pages, in the plural, and its one choice explains '
        'itself', (tester) async {
      await panel(tester, _notion);
      expect(find.text('WHAT A SYNC BRINGS IN'), findsOneWidget);
      expect(choices(tester).map((c) => c.$1), ['Notion pages']);
    });

    testWidgets('nothing ticked does not say nothing can come in: a hand-pick '
        'still does', (tester) async {
      await panel(
          tester,
          const CloudIntegration(
              provider: 'dropbox', tokenValid: true, includeTypes: []));
      expect(
          find.text('Nothing is ticked, so a sync brings in nothing. Files you '
              'pick with Browse files… still come in.'),
          findsOneWidget);
    });
  });
}
