import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/models/cloud_integration.dart';
import 'package:flutter_app/models/import_job.dart';
import 'package:flutter_app/pages/sources/sync_settings_panel.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/state/cloud_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

import 'sources_harness.dart';

/// The cloud-sync audit, 2026-09-25 — CS-6 (TODO.md). Each group is one item
/// that was wrong with nothing failing: a 202 read as success, a field whose
/// only save path no reader could reach, a type pill for the wrong provider,
/// a plate that called every PDF a web page, a Retry on rows the spec leaves
/// action-less, a progress list that was the whole window, and a sync control
/// that could only fail after the tap.

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

class _JobsOnly extends FirestoreService {
  _JobsOnly(this.jobs) : super.stub();
  final Stream<List<ImportJob>> jobs;

  @override
  String? get currentUid => 'u1';

  @override
  Stream<List<ImportJob>> subscribeCloudImportJobs({int limit = 50}) => jobs;
}

/// A connected provider, without a network read.
class _ConnectedCloud extends QuietCloud {
  _ConnectedCloud(this.integration);
  final CloudIntegration integration;

  @override
  CloudIntegration? integrationFor(String provider) =>
      provider == integration.provider ? integration : null;
}

const _pdf = 'application/pdf';
const _docx =
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

ImportJob _job(String id,
        {String status = 'skipped',
        String? skip,
        String mime = _pdf,
        int? createdAt,
        String name = ''}) =>
    ImportJob(
      id: id,
      provider: 'google_drive',
      status: status,
      skipReason: skip,
      mimeType: mime,
      createdAt: createdAt,
      providerFileName: name,
    );

void main() {
  setUp(() => ApiService.instance.tokenProvider = () async => 'test-token');
  tearDown(() {
    ApiService.instance.resetTestSeams();
    FirestoreService.resetInstance();
  });

  group('reviewJobs reads BOTH lists of the 202 (F-30, 4.69.0)', () {
    test('failed names the file, skipped is counted, the rest is derived',
        () async {
      final r = _Recorder((_) => (202, {
            'approved': 1,
            'dismissed': 0,
            'failed': ['b'],
            'skipped': ['x'],
          }));
      ApiService.instance.httpClientAdapter = r;
      final c = CloudNotifier();
      final err = await c.reviewJobs(['x', 'a', 'b', 'c'], 'approve');
      expect(err, isNull, reason: 'a 202 is not a refusal');
      final o = c.reviewOutcome!;
      expect(o.skipped, 1);
      expect(o.failedNames, ['b']);
      expect(o.notAttempted, 1,
          reason: '`c` sat past the failed id and was never attempted');
      c.dispose();
    });

    test('a failed chunk stops the batch: the queue is down, not the file',
        () async {
      final r = _Recorder((o) {
        final ids = ((o.data as Map)['job_ids'] as List).cast<String>();
        return (202, {
          'approved': 0,
          'dismissed': 0,
          'failed': [ids[10]],
          'skipped': <String>[],
        });
      });
      ApiService.instance.httpClientAdapter = r;
      final c = CloudNotifier();
      final ids = [for (var i = 0; i < 120; i++) 'j$i'];
      await c.reviewJobs(ids, 'approve');
      expect(r.sent, hasLength(1), reason: 'chunks 2 and 3 were still sent');
      expect(c.reviewOutcome!.notAttempted, 120 - 11);
      c.dispose();
    });

    test('a whole batch leaves no failure to draw', () async {
      ApiService.instance.httpClientAdapter = _Recorder((_) => (202, {
            'approved': 2,
            'dismissed': 0,
            'failed': <String>[],
            'skipped': <String>[],
          }));
      final c = CloudNotifier();
      await c.reviewJobs(['a', 'b'], 'approve');
      expect(c.reviewOutcome!.failedNames, isEmpty);
      expect(c.reviewOutcome!.notAttempted, 0);
      c.dispose();
    });
  });

  group('which rows carry a control (sources.md §Trust & feedback)', () {
    test('legacy and size-cap skips are action-less', () {
      expect(_job('a').canRetry, isFalse,
          reason: 'a pre-1.3.0 skip has no skip_reason and no control');
      expect(_job('b', skip: 'size_limit').canRetry, isFalse);
    });

    test('duplicate, dismissed and plan_limit import AGAIN', () {
      for (final r in ['duplicate', 'dismissed', 'plan_limit']) {
        final j = _job('a', skip: r);
        expect(j.canRetry, isTrue, reason: r);
        expect(j.isImportAgain, isTrue, reason: r);
      }
    });

    test('error and cancelled retry', () {
      for (final s in ['error', 'cancelled']) {
        final j = _job('a', status: s);
        expect(j.canRetry, isTrue);
        expect(j.isImportAgain, isFalse);
      }
    });
  });

  group('the plate is the file, through the one kind table', () {
    test('mime → type → kind', () {
      expect(kitDocKind(_job('a').docType), 'pdf');
      expect(kitDocKind(_job('a', mime: 'text/html').docType), 'web');
      expect(_job('a', mime: _docx).typeKey, 'docx');
      expect(kitDocKind(_job('a', mime: _docx).docType),
          kitDocKind('docx'), reason: 'a docx file plates as a docx document');
    });
  });

  group('the progress section is not the whole window (F-13)', () {
    test('old terminal jobs are history; held jobs are the queue\'s',
        () async {
      final jobs = StreamController<List<ImportJob>>.broadcast();
      FirestoreService.instance = _JobsOnly(jobs.stream);
      final c = QuietCloud()..start();
      jobs.add([
        _job('old', status: 'complete', createdAt: 1),
        _job('work', status: 'downloading', createdAt: 2),
        _job('held', status: 'awaiting_review', createdAt: 3),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect([for (final j in c.progressJobs) j.id], ['work']);
      expect([for (final j in c.historyJobs) j.id], ['old']);

      // Terminal WHILE watched → this session's, so it stays in progress.
      jobs.add([
        _job('old', status: 'complete', createdAt: 1),
        _job('work', status: 'complete', createdAt: 2),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect([for (final j in c.progressJobs) j.id], ['work']);
      c.dispose();
      await jobs.close();
    });

    test('a server stamp a minute behind the phone is still this session',
        () async {
      ApiService.instance.httpClientAdapter =
          _Recorder((_) => (202, {'queued_folders': 1}));
      final jobs = StreamController<List<ImportJob>>.broadcast();
      FirestoreService.instance = _JobsOnly(jobs.stream);
      final c = QuietCloud()..start();
      await c.syncNow('google_drive');
      final behind = DateTime.now().millisecondsSinceEpoch - 60000;
      jobs.add([_job('s', status: 'complete', createdAt: behind)]);
      await Future<void>.delayed(Duration.zero);
      expect([for (final j in c.progressJobs) j.id], ['s'],
          reason: '2s of slack dropped every job whose server stamp trailed '
              'the device clock');
      expect(c.discovering, isFalse);
      c.dispose();
      await jobs.close();
    });
  });

  group('sync settings panel', () {
    Future<CloudNotifier> pumpPanel(
        WidgetTester tester, CloudIntegration i) async {
      final c = QuietCloud();
      await tester.pumpWidget(ChangeNotifierProvider<CloudNotifier>.value(
        value: c,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: SyncSettingsPanel(
                  key: ValueKey(i.provider),
                  providerId: i.provider,
                  integration: i),
            ),
          ),
        ),
      ));
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pump();
      return c;
    }

    testWidgets('Notion offers notion, and only Notion does', (tester) async {
      await pumpPanel(
          tester,
          const CloudIntegration(
              provider: 'notion', tokenValid: true, includeTypes: ['notion']));
      expect(find.text('NOTION'), findsWidgets);
      expect(find.text('PDF'), findsNothing);

      await pumpPanel(
          tester,
          const CloudIntegration(
              provider: 'google_drive',
              tokenValid: true,
              includeTypes: ['pdf']));
      expect(find.text('NOTION'), findsNothing);
      expect(find.text('PPTX'), findsOneWidget);
    });

    testWidgets(
        'patterns save on leaving the field, whole, and a 400 is inline and '
        'reverts', (tester) async {
      final r = _Recorder((_) => (400, {
            'error': 'exclude_patterns must be at most 50 strings',
            'error_code': 'VALIDATION',
          }));
      ApiService.instance.httpClientAdapter = r;
      await pumpPanel(
          tester,
          const CloudIntegration(
              provider: 'google_drive',
              tokenValid: true,
              includeTypes: ['pdf'],
              excludePatterns: ['*.tmp']));

      final field = find.byType(TextField);
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pump();
      await tester.enterText(
          field, [for (var i = 0; i < 51; i++) 'p$i'].join('\n'));
      // Leave the field — no done key, no Enter.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      expect(r.sent, hasLength(1), reason: 'leaving the field never saved');
      expect(((r.sent.single.data as Map)['exclude_patterns'] as List).length,
          51, reason: 'the list was silently truncated to 50');
      expect(find.byType(KitFailureInline), findsOneWidget,
          reason: 'the 400 is inline (§Sync control), not a toast');
      expect(tester.widget<TextField>(field).controller!.text, '*.tmp',
          reason: 'a refused edit reverts to what was last read');
    });

    testWidgets('an unknown frequency selects nothing, and the hour says UTC',
        (tester) async {
      await pumpPanel(
          tester,
          const CloudIntegration(
              provider: 'google_drive',
              tokenValid: true,
              syncFrequency: 'fortnightly'));
      final seg = tester.widget<KitSegmented>(find.byType(KitSegmented).first);
      expect(seg.selected, -1, reason: '.clamp drew an unknown value as Hourly');
      expect(find.textContaining('03:00 UTC'), findsOneWidget,
          reason: 'the default hour is the backend\'s 3, not 9');
    });
  });

  group('sources screen', () {
    testWidgets('sync now is disabled with the reason on screen',
        (tester) async {
      await pumpSources(
          tester, SourcesStubService(),
          cloud: _ConnectedCloud(const CloudIntegration(
              provider: 'google_drive', tokenValid: true)));
      expect(find.text('Nothing to sync — choose sync folders first.'),
          findsOneWidget);
    });

    testWidgets('a sync-now cooldown is the server\'s wait, inline, not a failure',
        (tester) async {
      ApiService.instance.httpClientAdapter = _Recorder((_) => (429, {
            'error': 'Sync was requested 12 seconds ago — try again in 48 seconds.',
            'error_code': 'COOLDOWN',
          }));
      await pumpSources(tester, SourcesStubService(),
          cloud: _ConnectedCloud(const CloudIntegration(
              provider: 'google_drive',
              tokenValid: true,
              folderIds: ['f1'])));
      await tester.ensureVisible(find.text('Sync now'));
      await tester.tap(find.text('Sync now'));
      await tester.pumpAndSettle();
      expect(find.textContaining('48 seconds'), findsOneWidget,
          reason: 'the cooldown copy is user-facing and belongs inline');
      expect(
          find.descendant(
              of: find.byType(KitFailureInline),
              matching: find.textContaining('48 seconds')),
          findsNothing,
          reason: 'a wait is not a failure');
    });

    testWidgets('a held row says its type, size and the threshold',
        (tester) async {
      final jobs = StreamController<List<ImportJob>>.broadcast();
      await pumpSources(tester, SourcesStubService(jobs: jobs.stream),
          cloud: _ConnectedCloud(const CloudIntegration(
              provider: 'google_drive',
              tokenValid: true,
              includeTypes: ['pdf'],
              reviewRules: {'pdf': ReviewRule.overMb(5)})));
      jobs.add([
        const ImportJob(
          id: 'h',
          provider: 'google_drive',
          status: 'awaiting_review',
          providerFileName: 'big.pdf',
          mimeType: _pdf,
          fileSize: 42 * 1024 * 1024,
          reviewReason: 'size',
        ),
      ]);
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('PDF · 42 MB — over your 5 MB review size'),
          findsOneWidget);
      expect(find.textContaining('NOTE ·'), findsNothing);
      await jobs.close();
    });
  });
}
