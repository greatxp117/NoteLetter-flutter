import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/models/cloud_file.dart';
import 'package:flutter_app/models/cloud_integration.dart';
import 'package:flutter_app/models/import_job.dart';
import 'package:flutter_app/models/organization_settings.dart';
import 'package:flutter_app/models/organization_suggestion.dart';
import 'package:flutter_app/pages/reader/reorganize_sheet.dart';
import 'package:flutter_app/pages/sources/cloud_sync_copy.dart';
import 'package:flutter_app/pages/sources/sync_settings_panel.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/shared/upload_types.dart';
import 'package:flutter_app/state/cloud_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

import 'sources_harness.dart';

/// The Flutter tandem of contracts 4.89.0–4.92.0 (the cloud-sync audit,
/// CS-1..CS-4, ADR-123..126; QUEUE F-48). The reference is
/// `NoteLetter-web@12daabd` and its `cloud-sync-tandem.test.js`. Each case is
/// a sentence or a control the backend now answers and this client did not
/// draw: a disconnect that promised a revocation OneDrive and Notion cannot
/// perform, a checkbox on a file the import classifier refuses, an import
/// refusal that was a toast, a `skipped` approve that blamed another tab when
/// the provider was gone, a reorganization that read "created" with no file
/// written, a stale plan whose 409 left the same button on screen, and an
/// approved move whose failure never reached the screen.

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

/// A connected provider, without a network read.
class _ConnectedCloud extends QuietCloud {
  _ConnectedCloud(this.integration);
  final CloudIntegration integration;

  @override
  CloudIntegration? integrationFor(String provider) =>
      provider == integration.provider ? integration : null;
}

/// The Sources stub, plus the one-document suggestion listener.
class _OrgStub extends SourcesStubService {
  _OrgStub({super.suggestions, this.one});
  final Stream<OrganizationSuggestion?> Function(String id)? one;

  @override
  Stream<OrganizationSuggestion?> subscribeOrganizationSuggestion(String id) =>
      one?.call(id) ?? const Stream.empty();
}

const _xlsx = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

void main() {
  setUp(() => ApiService.instance.tokenProvider = () async => 'test-token');
  tearDown(() {
    ApiService.instance.resetTestSeams();
    FirestoreService.resetInstance();
  });

  group('disconnect and the grant (4.89.0 ADR-123 §5, 4.90.0 ADR-124 §7)', () {
    test('the confirm never promises a revocation OneDrive or Notion cannot '
        'perform', () {
      for (final (id, name) in [('onedrive', 'OneDrive'), ('notion', 'Notion')]) {
        final copy = disconnectRevokeCopy(id, name)!;
        expect(copy, contains('does not let an app revoke its own access'));
        expect(copy, contains('until you remove it'));
      }
      for (final (id, name) in [
        ('google_drive', 'Google Drive'),
        ('dropbox', 'Dropbox')
      ]) {
        final copy = disconnectRevokeCopy(id, name)!;
        expect(copy, contains('asks $name to revoke'),
            reason: 'best-effort: the confirm says it will ASK');
        expect(copy, isNot(contains('revoked')));
      }
    });

    test('the confirm says downloaded files finish', () {
      final c = disconnectConsequences('Dropbox');
      expect(c, contains('not yet downloaded stop'));
      expect(c, contains('files already downloaded finish importing'));
    });

    test('revoked true · false · null · absent are four sentences', () {
      expect(disconnectOutcome('google_drive', 'Google Drive', true),
          contains('confirmed NoteLetter’s access is revoked'));
      expect(disconnectOutcome('dropbox', 'Dropbox', false),
          contains('did not confirm'));
      expect(disconnectOutcome('notion', 'Notion', null),
          contains('keeps NoteLetter listed until you remove it'));
      expect(disconnectOutcome('notion', 'Notion', revokedAbsent),
          'Notion is disconnected.',
          reason: 'a backend that never asked says nothing about the grant');
    });

    test('the notifier keeps a JSON null apart from an absent key', () async {
      var body = <String, Object?>{'disconnected': 'notion', 'revoked': null};
      ApiService.instance.httpClientAdapter = _Recorder((_) => (200, body));
      final c = QuietCloud();
      expect(await c.disconnect('notion'), isNull);
      expect(c.lastDisconnect!.$1, 'notion');
      expect(c.lastDisconnect!.$2, isNull);

      body = {'disconnected': 'onedrive'};
      await c.disconnect('onedrive');
      expect(identical(c.lastDisconnect!.$2, revokedAbsent), isTrue);
      c.dispose();
    });

    testWidgets('the outcome stands under the grid, not in a toast',
        (tester) async {
      ApiService.instance.httpClientAdapter = _Recorder(
          (_) => (200, {'disconnected': 'google_drive', 'revoked': false}));
      final cloud = _ConnectedCloud(const CloudIntegration(
          provider: 'google_drive', tokenValid: true, folderIds: ['f1']));
      await pumpSources(tester, SourcesStubService(), cloud: cloud);
      await tester.ensureVisible(find.text('Disconnect'));
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();
      expect(find.textContaining('asks Google Drive to revoke'), findsOneWidget);
      expect(find.textContaining('files already downloaded finish'),
          findsOneWidget);
      await tester.tap(find.widgetWithText(KitButton, 'Disconnect').last);
      await tester.pumpAndSettle();
      expect(
          find.descendant(
              of: find.byType(KitProcNote),
              matching: find.textContaining('did not confirm')),
          findsOneWidget);
    });
  });

  group('the import picker (4.91.0, ADR-125)', () {
    test('a file the classifier refuses says why; an import it reads does not',
        () {
      CloudFile f(String name, String? mime, {bool exportable = false}) =>
          CloudFile(
              id: name,
              name: name,
              type: 'file',
              mimeType: mime,
              exportable: exportable);
      expect(cloudFileRefusal('google_drive', f('Budget.xlsx', _xlsx)),
          contains('isn’t a supported file type'));
      expect(cloudFileRefusal('google_drive', f('Old.doc', 'application/msword')),
          contains('re-save as .docx'));
      expect(
          cloudFileRefusal(
              'onedrive', f('Essay.docx', 'application/octet-stream')),
          isNull,
          reason: 'octet-stream is no type — the extension decides');
      expect(
          cloudFileRefusal('google_drive',
              f('Notes', 'application/vnd.google-apps.document', exportable: true)),
          isNull,
          reason: 'a Google-native file Drive exports is never classified');
      expect(cloudFileRefusal('notion', f('Page', null)), isNull);
      expect(
          cloudFileRefusal('google_drive',
              const CloudFile(id: 'd', name: 'Docs', type: 'folder')),
          isNull);
    });

    (int, Object) listing(RequestOptions o) {
      if (o.path.contains('fn_list_cloud_files')) {
        return (200, {
          'items': [
            {'id': 'a', 'name': 'Budget.xlsx', 'type': 'file', 'mime_type': _xlsx},
            {'id': 'b', 'name': 'Essay.pdf', 'type': 'file', 'mime_type': 'application/pdf'},
          ],
          'nextPageToken': null,
        });
      }
      return (400, {
        'error': 'Unknown keys: folder_idz. Accepted: provider, folder_ids, file_ids.',
        'error_code': 'UNKNOWN_KEYS',
      });
    }

    /// Opens the picker without awaiting it inside the fake-async zone, then
    /// lets the listing land with bounded pumps (the picker draws a spinner).
    Future<void> openPicker(WidgetTester tester, CloudNotifier c, String p) async {
      unawaited(c.openPicker(p));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('the Notion advisory stands on the IMPORT picker',
        (tester) async {
      ApiService.instance.httpClientAdapter = _Recorder(listing);
      final cloud = _ConnectedCloud(
          const CloudIntegration(provider: 'notion', tokenValid: true));
      await pumpSources(tester, SourcesStubService(), cloud: cloud);
      await openPicker(tester, cloud, 'notion');
      expect(find.textContaining('Notion passes along only the pages you ticked'),
          findsOneWidget,
          reason: 'ADR-026 §3, as the sync picker has it');
      expect(find.textContaining('isn’t a supported file type'), findsNothing,
          reason: 'a Notion page is read as text, never classified');
    });

    testWidgets(
        'a refused file has no checkbox, and the import\'s 400 is inline, not '
        'a toast', (tester) async {
      ApiService.instance.httpClientAdapter = _Recorder(listing);
      final drive = _ConnectedCloud(const CloudIntegration(
          provider: 'google_drive', tokenValid: true));
      await pumpSources(tester, SourcesStubService(), cloud: drive);
      await openPicker(tester, drive, 'google_drive');

      expect(find.textContaining('isn’t a supported file type'), findsOneWidget);
      expect(find.byType(Checkbox), findsOneWidget,
          reason: 'only the PDF is offered a checkbox');
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.ensureVisible(find.text('Import selected'));
      await tester.tap(find.text('Import selected'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(
          find.descendant(
              of: find.byType(KitFailureInline),
              matching: find.textContaining('Unknown keys')),
          findsOneWidget,
          reason: '§14.2: the refusal beside the control that sent it');
      expect(drive.browseProvider, 'google_drive',
          reason: 'a refused import keeps the picker and its selection');
    });
  });

  group('import rows (4.90.0, 4.91.0)', () {
    ImportJob job(String status, {String? skip, String? msg}) => ImportJob(
        id: 'j-$status-$skip',
        provider: 'google_drive',
        status: status,
        skipReason: skip,
        errorMessage: msg,
        providerFileName: 'Budget.xlsx',
        mimeType: _xlsx,
        createdAt: DateTime(2026, 9, 20).millisecondsSinceEpoch);

    test('unsupported_type is a skip with no control', () {
      final j = job('skipped', skip: 'unsupported_type');
      expect(j.isUnsupportedType, isTrue);
      expect(j.canRetry, isFalse,
          reason: 'a retry would meet the same classifier');
    });

    testWidgets('its sentence is drawn; pending and queued are named',
        (tester) async {
      final jobs = [
        job('skipped',
            skip: 'unsupported_type',
            msg: '“Budget.xlsx” isn’t a supported file type.'),
        job('pending'),
        job('queued'),
      ];
      await pumpSources(tester,
          SourcesStubService(jobs: Stream.value(jobs)),
          cloud: _ConnectedCloud(const CloudIntegration(
              provider: 'google_drive', tokenValid: true)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Waiting'), findsWidgets);
      expect(find.text('Queued'), findsOneWidget,
          reason: '`queued` fell to the default branch and read "Waiting"');
      // A terminal row from before this session lives in Import history.
      await tester.ensureVisible(find.text('Show 1'));
      await tester.tap(find.text('Show 1'));
      await tester.pumpAndSettle();
      expect(find.textContaining('isn’t a supported file type'), findsWidgets);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Import again'), findsNothing);
    });

    test('a skipped approve names both causes', () {
      final one = reviewSkippedNote(1);
      expect(one, contains('another tab or device'));
      expect(one, contains('its service is no longer connected'));
      expect(reviewSkippedNote(3), startsWith('3 files were left alone'));
    });
  });

  group('sync settings (TODO CS-5)', () {
    testWidgets('the preferred hour hides on Hourly', (tester) async {
      Future<void> pump(String freq) async {
        await tester.pumpWidget(ChangeNotifierProvider<CloudNotifier>.value(
          value: QuietCloud(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: SingleChildScrollView(
                child: SyncSettingsPanel(
                    key: ValueKey(freq),
                    providerId: 'google_drive',
                    integration: CloudIntegration(
                        provider: 'google_drive',
                        tokenValid: true,
                        syncFrequency: freq)),
              ),
            ),
          ),
        ));
        await tester.tap(find.byIcon(Icons.expand_more));
        await tester.pump();
      }

      await pump('daily');
      expect(find.textContaining(':00 UTC'), findsOneWidget);
      await pump('hourly');
      expect(find.textContaining(':00 UTC'), findsNothing,
          reason: '`_scheduled_sync_due` ignores the hour on hourly');
    });
  });

  group('organization (4.92.0, ADR-126)', () {
    testWidgets(
        'a settings refusal (4.93.0 UNKNOWN_KEYS) is inline in the panel, '
        'not a toast', (tester) async {
      ApiService.instance.httpClientAdapter = _Recorder((_) => (400, {
            'error': 'Unknown keys: foo. Accepted: confidence_threshold, '
                'default_reorg_mode, providers.',
            'error_code': 'UNKNOWN_KEYS',
          }));
      await pumpSources(
          tester,
          SourcesStubService(
              orgSettings: const OrganizationSettings(providers: {
            'dropbox': OrgProviderConfig(enabled: true),
          })));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Copy'));
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(
          find.descendant(
              of: find.byType(KitFailureInline),
              matching: find.textContaining('Unknown keys')),
          findsOneWidget);
    });

    test('created_without_artifact says no file was written, and why', () {
      final sections = [
        {'section_id': 's1', 'title': 'Intro'}
      ];
      final dest = {'kind': 'folder', 'folder_id': 'f1', 'path': '/Work'};
      expect(
          operationOutcome({
            'section_id': 's1',
            'destination': dest,
            'result': 'created_without_artifact',
            'artifact_reason': 'organization is paused',
          }, sections),
          'Intro → a new document in your library, but no file was written '
          'to /Work — organization is paused.');
      expect(
          operationOutcome(
              {'section_id': 's1', 'destination': dest, 'result': 'created'},
              sections),
          'Intro → a new document, and a file in /Work.');
      expect(
          operationOutcome(
              {'section_id': 'sx', 'result': 'error: destination missing'},
              sections),
          'A section → error: destination missing.',
          reason: 'the vocabulary stays open');
    });

    testWidgets('a 409 offers Analyze again and disables the stale plan',
        (tester) async {
      FirestoreService.instance = SourcesStubService();
      var analyzed = 0;
      ApiService.instance.httpClientAdapter = _Recorder((o) {
        if (o.path.contains('fn_analyze_reorganization')) {
          analyzed++;
          return (200, {
            'plan_id': 'plan-1',
            'sections': [
              {
                'section_id': 's1',
                'chunk_ids': ['c1'],
                'title': 'Intro',
                'summary': 'x',
                'destinations': [
                  {'kind': 'folder', 'folder_id': 'f1', 'path': '/Work', 'confidence': 0.9}
                ],
              }
            ],
          });
        }
        return (409, {
          'error': 'This document changed after the plan was made — analyze it again.',
          'error_code': 'CONFLICT',
        });
      });
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
            body: ReorganizeSheet(docId: 'd1', onExecuted: () {})),
      ));
      await tester.pumpAndSettle();
      expect(analyzed, 1);
      await tester.tap(find.widgetWithText(FilledButton, 'Reorganize 1 section'));
      await tester.pumpAndSettle();
      // The default mode is split, so the destructive confirm comes first.
      await tester.tap(find.text('Yes, reorganize'));
      await tester.pumpAndSettle();

      expect(find.textContaining('changed after the plan was made'),
          findsOneWidget);
      final stale = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Reorganize 1 section'));
      expect(stale.onPressed, isNull,
          reason: 'the stale plan could only 409 again');
      await tester.tap(find.text('Analyze again'));
      await tester.pumpAndSettle();
      expect(analyzed, 2);
      expect(find.textContaining('changed after the plan was made'),
          findsNothing);
    });

    testWidgets(
        'a readme card says it adopts; a failed approval stays with the '
        'worker\'s sentence', (tester) async {
      const card = OrganizationSuggestion(
        id: 's-readme',
        provider: 'dropbox',
        type: 'readme',
        confidence: 0.8,
        reason: 'You edited the README',
        status: 'pending',
        payload: {'folder_id': 'f1', 'proposed_charter_text': 'Tax papers'},
      );
      final one = StreamController<OrganizationSuggestion?>();
      addTearDown(one.close);
      ApiService.instance.httpClientAdapter = _Recorder(
          (_) => (200, {'approved': ['s-readme'], 'declined': [], 'skipped': []}));
      await pumpSources(
          tester,
          _OrgStub(
              suggestions: Stream.value(const [card]),
              one: (_) => one.stream));
      await tester.pumpAndSettle();
      expect(find.text('Adopt README edits'), findsOneWidget);
      expect(find.text('“Tax papers”'), findsOneWidget);
      expect(find.textContaining('nothing in Dropbox is changed'),
          findsOneWidget);

      await tester.ensureVisible(find.text('Approve'));
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      expect(find.text('Adopt README edits as the charter'), findsOneWidget);

      one.add(card.withStatus('failed',
          resolutionError: 'interrupted — check the file\'s location'));
      await tester.pumpAndSettle();
      expect(
          find.descendant(
              of: find.byType(KitFailureInline),
              matching: find.textContaining('interrupted')),
          findsOneWidget);
      await tester.ensureVisible(find.text('Clear'));
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(find.textContaining('interrupted'), findsNothing);
    });
  });

  // 4.94.0 (ADR-125 §Note; cloud-storage.md §fn_list_cloud_files, uploads.md).
  // Web reference NoteLetter-web@42160c1 (`cloudExportLabel`, `uploadTypes.js`).
  group('Google-native files (4.94.0)', () {
    const pptx =
        'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    CloudFile f(String name, String? mime, {bool exportable = false}) =>
        CloudFile(
            id: name,
            name: name,
            type: 'file',
            mimeType: mime,
            exportable: exportable);

    test('an exportable row is labelled by what it imports AS', () {
      expect(cloudExportLabel(f('Notes', 'application/pdf', exportable: true)),
          'Exports as PDF');
      expect(cloudExportLabel(f('Deck', pptx, exportable: true)),
          'Exports as PowerPoint',
          reason: 'a Slides deck lists with the PowerPoint mime');
      expect(
          cloudExportLabel(f('Old', 'application/vnd.google-apps.document',
              exportable: true)),
          'Exports as PDF',
          reason: 'a pre-4.94.0 backend listed Docs by their native mime');
      expect(
          cloudExportLabel(
              f('Odd', 'application/vnd.something', exportable: true)),
          isNull,
          reason: 'an unnamed mime gets no label, never a guessed one');
      expect(cloudExportLabel(f('Essay.pdf', 'application/pdf')), isNull,
          reason: 'only an exportable row says it exports');
    });

    test('the upload rule refuses every Google-native mime', () {
      for (final kind in ['presentation', 'spreadsheet', 'drawing', 'form']) {
        expect(
            uploadRejection(
                name: 'Thing', size: 0,
                mimeType: 'application/vnd.google-apps.$kind'),
            '“Thing” isn’t a supported file type. $uploadAcceptHelp.',
            reason: '`google-apps.presentation` matched "contains presentation"');
      }
      expect(uploadRejection(name: 'Deck.pptx', size: 0, mimeType: pptx),
          isNull,
          reason: 'the export type itself is still accepted');
      expect(
          cloudFileRefusal('google_drive',
              f('Budget', 'application/vnd.google-apps.spreadsheet')),
          contains('isn’t a supported file type'),
          reason: 'a native kind Drive does not export is refused in the picker');
    });

    (int, Object) listing(RequestOptions o) => (200, {
          'items': [
            {'id': 'd', 'name': 'Notes', 'type': 'file',
             'mime_type': 'application/pdf', 'exportable': true},
            {'id': 's', 'name': 'Deck', 'type': 'file',
             'mime_type': pptx, 'exportable': true},
            {'id': 'x', 'name': 'Budget', 'type': 'file',
             'mime_type': 'application/vnd.google-apps.spreadsheet',
             'exportable': false},
            {'id': 'u', 'name': 'Odd', 'type': 'file',
             'mime_type': 'application/vnd.something', 'exportable': true},
          ],
          'nextPageToken': null,
        });

    testWidgets(
        'the import picker says PDF or PowerPoint by mime, and refuses a '
        'native kind', (tester) async {
      ApiService.instance.httpClientAdapter = _Recorder(listing);
      final drive = _ConnectedCloud(const CloudIntegration(
          provider: 'google_drive', tokenValid: true));
      await pumpSources(tester, SourcesStubService(), cloud: drive);
      unawaited(drive.openPicker('google_drive'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.text('Exports as PDF'), findsOneWidget);
      expect(find.text('Exports as PowerPoint'), findsOneWidget,
          reason: 'the deck was labelled PDF before 4.94.0');
      expect(find.textContaining('Exports as'), findsNWidgets(2),
          reason: 'the unmapped exportable row carries no label');
      expect(find.text('“Budget” isn’t a supported file type. $uploadAcceptHelp.'),
          findsOneWidget);
      expect(find.byType(Checkbox), findsNWidgets(3),
          reason: 'the refused native spreadsheet is offered no checkbox');
    });
  });
}
