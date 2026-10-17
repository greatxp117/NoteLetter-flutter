/// A changed cloud file updates its document in place (5.12.0, ADR-172). The
/// reader's half of it, two controls (web: tests/contract/update-in-place.test.js):
///   · screens/sources.md §Sync settings panel — "Update changed files
///     automatically", `sync_config.auto_update`, absent reading as ON, sent
///     alone and drawn only from the returned integration;
///   · screens/reader.md §Source freshness — "Update from {Provider}" in the
///     Original section for every complete cloud document, whatever freshness
///     says, through the same confirm as the banner.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/models/chunk.dart';
import 'package:flutter_app/models/cloud_integration.dart';
import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/study.dart';
import 'package:flutter_app/pages/reader/update_from_source_bar.dart';
import 'package:flutter_app/pages/sources/sync_settings_panel.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/state/cloud_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

import 'sources_harness.dart';

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

/// The edit fact, read quietly (the Original panel holds no chunks), and a
/// programs stream that would ask the study question if anything read it.
class _Reads extends FirestoreService {
  _Reads({this.edited = false}) : super.stub();
  final bool edited;
  int programReads = 0;

  @override
  Future<(Document, List<Chunk>)?> getReaderDocumentQuietly(
      String docId) async {
    return (
      _doc(),
      [
        Chunk.fromJson({
          'chunk_id': 'c1',
          'document_id': docId,
          'chunk_index': 0,
          'text': 'A passage.',
          'user_edited': edited,
        }),
      ]
    );
  }

  @override
  Stream<List<StudyProgram>> subscribeStudyPrograms() {
    programReads++;
    return Stream.value(const [
      StudyProgram(
          id: 'p1',
          title: 'Board',
          documentIds: ['doc-1'],
          enabled: true,
          status: 'active'),
    ]);
  }
}

Document _doc({String status = 'complete', bool cloud = true}) =>
    Document.fromJson('doc-1', {
      'user_id': 'u1',
      'title': 'Board deck',
      'type': 'pptx',
      'status': status,
      'gcs_path': 'raw/u1/cloud/google_drive/j1_deck.pptx',
      if (cloud) 'source_integration': {'provider': 'google_drive', 'job_id': 'j1'},
    });

Future<void> _pumpBar(WidgetTester tester, Document doc) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: UpdateFromSourceBar(docId: 'doc-1', doc: doc)),
  ));
  await tester.pumpAndSettle();
}

Map<String, dynamic> _integration({bool? autoUpdate}) => {
      'provider': 'google_drive',
      'token_valid': true,
      'auto_sync_enabled': true,
      'sync_frequency': 'hourly',
      'sync_config': {
        'folder_ids': ['f1'],
        'include_types': ['pdf'],
        if (autoUpdate != null) 'auto_update': autoUpdate,
      },
    };

void main() {
  setUp(() => ApiService.instance.tokenProvider = () async => 'test-token');
  tearDown(() {
    ApiService.instance.resetTestSeams();
    FirestoreService.resetInstance();
  });

  group('sync_config.auto_update (sources.md §Sync settings panel)', () {
    test('absent reads as on — every config stored before 5.12.0', () {
      expect(CloudIntegration.fromJson(_integration()).autoUpdate, isTrue);
      expect(CloudIntegration.fromJson(_integration(autoUpdate: false)).autoUpdate,
          isFalse);
    });

    testWidgets(
        'the switch sends auto_update alone and draws what came back',
        (tester) async {
      final rec = _Recorder((o) => (200, {
            'integration': _integration(
                autoUpdate: (o.data as Map)['auto_update'] as bool?)
          }));
      ApiService.instance.httpClientAdapter = rec;
      await tester.pumpWidget(ChangeNotifierProvider<CloudNotifier>.value(
        value: QuietCloud(),
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: SyncSettingsPanel(
                  providerId: 'google_drive',
                  integration: CloudIntegration.fromJson(_integration())),
            ),
          ),
        ),
      ));
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pump();
      expect(find.text('Update changed files automatically'), findsOneWidget);
      expect(
          find.textContaining('updated once it has gone 30 minutes without an '
              'edit. Off: use Update from Google Drive in the reader.'),
          findsOneWidget);
      final row = find.ancestor(
          of: find.text('Update changed files automatically'),
          matching: find.byType(Row));
      final sw =
          find.descendant(of: row.first, matching: find.byType(KitSwitch));
      expect(tester.widget<KitSwitch>(sw).value, isTrue);
      await tester.tap(sw);
      await tester.pumpAndSettle();
      expect(rec.sent.single.path, endsWith('/fn_sync_settings'));
      expect(rec.sent.single.data,
          {'provider': 'google_drive', 'auto_update': false});
    });
  });

  // F-119: the auto-sync group as the spec names it and web draws it — the
  // first switch "Sync new files automatically" (sources.md since 5.12.0;
  // Flutter said "Automatic sync"), the group's last sync as "Last synced …"
  // (it said "Synced 106d ago"), and both switches the kit's.
  group('the auto-sync group (sources.md §Sync settings panel)', () {
    test('the last sync is "Last synced {Mon} {d}, {h}:{mm} {AM|PM}", web\'s '
        '(the time held to its AM/PM by a no-break space)',
        () {
      int at(int h, int m) => DateTime(2026, 7, 3, h, m).millisecondsSinceEpoch;
      expect(lastSyncedLine(at(1, 0)), 'Last synced Jul 3, 1:00\u00a0AM');
      expect(lastSyncedLine(at(0, 5)), 'Last synced Jul 3, 12:05\u00a0AM');
      expect(lastSyncedLine(at(12, 0)), 'Last synced Jul 3, 12:00\u00a0PM');
      expect(lastSyncedLine(at(23, 59)), 'Last synced Jul 3, 11:59\u00a0PM');
      expect(lastSyncedLine(null), 'Never synced automatically');
      expect(lastSyncedLine(0), 'Never synced automatically');
    });

    test('the connect card\'s relative label is left as it was', () {
      final ms = DateTime.now()
          .subtract(const Duration(days: 3))
          .millisecondsSinceEpoch;
      final i = CloudIntegration.fromJson(
          {..._integration(), 'last_sync_at': ms});
      expect(i.lastSyncLabel, 'Synced 3d ago');
    });

    testWidgets(
        'embedded: AUTO-SYNC beside "Last synced …", two named rows, two '
        'kit switches and no Material one', (tester) async {
      final ms = DateTime(2026, 7, 3, 1, 0).millisecondsSinceEpoch;
      await tester.pumpWidget(ChangeNotifierProvider<CloudNotifier>.value(
        value: QuietCloud(),
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: SyncSettingsPanel(
                  providerId: 'google_drive',
                  embedded: true,
                  integration: CloudIntegration.fromJson(
                      {..._integration(), 'last_sync_at': ms})),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(find.text('Last synced Jul 3, 1:00\u00a0AM'), findsOneWidget);
      expect(find.textContaining('Synced 1'), findsNothing);
      expect(find.text('Sync new files automatically'), findsOneWidget);
      expect(find.text('Automatic sync'), findsNothing);
      expect(find.byType(Switch), findsNothing);
      for (final name in [
        'Sync new files automatically',
        'Update changed files automatically',
      ]) {
        final row = find.ancestor(of: find.text(name), matching: find.byType(Row));
        expect(
            find.descendant(of: row.first, matching: find.byType(KitSwitch)),
            findsOneWidget,
            reason: name);
      }
    });

    testWidgets('the first switch sends auto_sync_enabled alone',
        (tester) async {
      final rec = _Recorder((o) => (200, {'integration': _integration()}));
      ApiService.instance.httpClientAdapter = rec;
      await tester.pumpWidget(ChangeNotifierProvider<CloudNotifier>.value(
        value: QuietCloud(),
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: SyncSettingsPanel(
                  providerId: 'google_drive',
                  embedded: true,
                  integration: CloudIntegration.fromJson(_integration())),
            ),
          ),
        ),
      ));
      await tester.pump();
      final row = find.ancestor(
          of: find.text('Sync new files automatically'),
          matching: find.byType(Row));
      await tester.tap(
          find.descendant(of: row.first, matching: find.byType(KitSwitch)));
      await tester.pumpAndSettle();
      expect(rec.sent.single.path, endsWith('/fn_sync_settings'));
      expect(rec.sent.single.data,
          {'provider': 'google_drive', 'auto_sync_enabled': false});
    });
  });

  group('Update from {Provider}, any time (reader.md §Source freshness)', () {
    testWidgets('a complete cloud document offers it, named for its provider',
        (tester) async {
      await _pumpBar(tester, _doc());
      expect(find.text('Imported from Google Drive'), findsOneWidget);
      expect(find.widgetWithText(KitButton, 'Update from Google Drive'),
          findsOneWidget);
    });

    testWidgets('nothing for a non-cloud or not-complete document',
        (tester) async {
      await _pumpBar(tester, _doc(cloud: false));
      expect(find.textContaining('Update from'), findsNothing);
      await _pumpBar(tester, _doc(status: 'processing'));
      expect(find.textContaining('Update from'), findsNothing);
    });

    testWidgets(
        'no edits → straight through, the study question not asked, then '
        '"Update queued"', (tester) async {
      final reads = _Reads();
      FirestoreService.instance = reads;
      final rec = _Recorder((_) => (202, {'docId': 'doc-1', 'job_id': 'j1'}));
      ApiService.instance.httpClientAdapter = rec;
      await _pumpBar(tester, _doc());
      await tester.tap(find.widgetWithText(KitButton, 'Update from Google Drive'));
      await tester.pumpAndSettle();
      expect(find.byType(KitConfirm), findsNothing);
      expect(rec.sent.single.path, endsWith('/fn_update_from_source'));
      expect(rec.sent.single.data, {'document_id': 'doc-1'});
      expect(reads.programReads, 0);
      expect(
          find.textContaining(
              'Update queued — this source is being re-imported from Google Drive'),
          findsOneWidget);
    });

    testWidgets('an edited passage → the danger confirm first, naming what '
        'replaces the edits', (tester) async {
      FirestoreService.instance = _Reads(edited: true);
      final rec = _Recorder((_) => (202, {'docId': 'doc-1', 'job_id': 'j1'}));
      ApiService.instance.httpClientAdapter = rec;
      await _pumpBar(tester, _doc());
      await tester.tap(find.widgetWithText(KitButton, 'Update from Google Drive'));
      await tester.pumpAndSettle();
      expect(find.byType(KitConfirm), findsOneWidget);
      expect(rec.sent, isEmpty, reason: 'nothing leaves before the confirm');
      expect(
          find.textContaining('Your edits to these passages will be replaced by '
              'the version in Google Drive.'),
          findsOneWidget);
      await tester.tap(find.descendant(
          of: find.byType(KitConfirm),
          matching: find.widgetWithText(KitButton, 'Update from source')));
      await tester.pumpAndSettle();
      expect(rec.sent.single.data, {'document_id': 'doc-1'});
      expect(find.textContaining('Update queued'), findsOneWidget);
    });

    testWidgets('a refusal is §14.2 under the button; nothing says queued',
        (tester) async {
      FirestoreService.instance = _Reads();
      ApiService.instance.httpClientAdapter = _Recorder((_) => (409, {
            'error': 'An import for this document is already in progress.',
            'error_code': 'CONFLICT'
          }));
      await _pumpBar(tester, _doc());
      await tester.tap(find.widgetWithText(KitButton, 'Update from Google Drive'));
      await tester.pumpAndSettle();
      expect(find.byType(KitFailureInline), findsOneWidget);
      expect(find.textContaining('already in progress'), findsOneWidget);
      expect(find.textContaining('Update queued'), findsNothing);
    });
  });
}
