/// A picture already in the library (5.50.0, ADR-202, INV-37) — the copy's
/// row, its labels and its merge; web `tests/contract/picture-copy-row.test.js`.
///
/// The copy is a `skipped` document whose CLOSED `skip_reason` says so, and it
/// is listed, never dropped (Xavier, 2026-11-02). These assert the row this
/// client draws for the document shapes the backend captured
/// (fixtures/scenarios/picture-dedupe, fixtures/api/uploads), in all three
/// looks (For your review's card, the Library's D row and its Grid arrival):
///   - muted (opacity 0.55), never failure-styled: no alert glyph, the stage
///     and stamp say "Already in your library";
///   - `already_in_library` offers Add anyway (a forced retry in its own
///     words), never Index it anyway and never Retry;
///   - `already_in_library_not_uploaded` offers Add anyway ONLY on the phone
///     whose camera-roll ledger holds the photo, and then it is the capture
///     session's `force`, never `fn_retry_document` (which 409s it:
///     `uploads:retry-not-uploaded-duplicate-refused`);
///   - View opens the ORIGINAL, never the copy.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/models/activity_item.dart';
import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/pages/sources/browse_section.dart';
import 'package:flutter_app/services/activity_merge.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/source_history.dart';
import 'package:flutter_app/services/sweep_ledger.dart';
import 'package:flutter_app/state/activity_notifier.dart';
import 'package:flutter_app/state/camera_sweep_host.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

import 'fixtures.dart';
import 'sweep_fakes.dart';

/// Records every request and answers 200.
class _Router implements HttpClientAdapter {
  final List<RequestOptions> sent = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    sent.add(options);
    return ResponseBody.fromString(jsonEncode({'ok': true}), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _case(String suite, String id) =>
    ((loadSuite(suite)!['cases'] as List).firstWhere((c) => c['id'] == id) as Map)
        .cast<String, dynamic>();

/// The copy as the pipeline left it (picture-dedupe, case 1).
Document _after() {
  final copy = (_case('picture-dedupe', 'picture-dedupe:same-file-is-listed-not-read')
          ['response']['body']['copy'] as Map)
      .cast<String, dynamic>();
  return Document.fromJson('copy-1', {
    'user_id': 'u1',
    'title': 'cap-dedupe-b.png',
    'type': 'image',
    ...copy,
  });
}

/// The copy as the camera roll's check left it (api/uploads), with the
/// `source_capture` the backend writes on it.
Document _before(String assetKey) {
  final pre = (_case('api/uploads', 'uploads:capture-session-precheck-duplicate')
          ['response']['body'] as Map)
      .cast<String, dynamic>();
  return Document.fromJson(pre['docId'] as String, {
    'user_id': 'u1',
    'title': 'IMG_0420.HEIC',
    'type': 'image',
    'status': pre['status'],
    'skip_reason': 'already_in_library_not_uploaded',
    'duplicate_of': pre['duplicateOf'],
    'error_message':
        'This photo is already in your library as “IMG_0420.HEIC”, so it was not uploaded.',
    'source_capture': {'source': 'camera_roll', 'asset_key': assetKey, 'captured_at': null},
  });
}

class _Session extends ChangeNotifier {}

Future<List<String>> _pumpRow(
  WidgetTester tester,
  Document doc, {
  ProcessingLook look = ProcessingLook.card,
  CameraSweepHost? host,
}) async {
  final opened = <String>[];
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ActivityNotifier()),
      if (host != null) ChangeNotifierProvider<CameraSweepHost>.value(value: host),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: look == ProcessingLook.arrival ? 220 : null,
            child: ProcessingRow(
              doc: doc,
              look: look,
              editCheck: (_) async => false,
              studyCheck: (_) async => false,
              openOriginal: opened.add,
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return opened;
}

/// The row's own muting: an [Opacity] wrapping the whole row, at the copy's
/// value (a kit control may draw its own Opacity inside, at 1).
Finder _muted() => find.descendant(
    of: find.byType(ProcessingRow),
    matching: find.byWidgetPredicate((w) => w is Opacity && w.opacity == copyRowOpacity));

void main() {
  setUp(() => ApiService.instance.tokenProvider = () async => 'test-token');
  tearDown(() => ApiService.instance.resetTestSeams());

  group('the document', () {
    test('a copy names its original; skip_reason (closed) says it is one', () {
      final after = _after();
      expect(after.skipReason, 'already_in_library');
      expect(after.duplicateOf, 'cap-dedupe-a');
      expect(after.isPictureCopy, isTrue);
      final before = _before('v1:twin');
      expect(before.isPictureCopy, isTrue);
      expect(before.captureAssetKey, 'v1:twin');
      final skipped = Document.fromJson('s', {
        'status': 'skipped', 'skip_reason': 'no_text_content', 'duplicate_of': 'x'});
      expect(skipped.isPictureCopy, isFalse, reason: 'the reason decides, never a field beside it');
      final complete = Document.fromJson('c', {
        'status': 'complete', 'skip_reason': 'already_in_library'});
      expect(complete.isPictureCopy, isFalse, reason: 'only a skipped row is a copy');
    });
  });

  for (final look in ProcessingLook.values) {
    group('the copy row, ${look.name}', () {
      testWidgets('muted, never failure-styled; the server sentence verbatim', (tester) async {
        await _pumpRow(tester, _after(), look: look);
        expect(_muted(), findsOneWidget);
        expect(copyRowOpacity, 0.55, reason: 'web COPY_STYLE, the import\'s skipped row');
        expect(find.text('ALREADY IN YOUR LIBRARY'), findsWidgets);
        expect(find.byIcon(Icons.warning_amber_rounded), findsNothing,
            reason: 'no alert glyph on a copy');
        expect(find.textContaining('Couldn’t be read'), findsNothing);
        expect(find.text('ERROR'), findsNothing);
        expect(find.text(_after().errorMessage!), findsOneWidget);
        if (look == ProcessingLook.card) {
          expect(tester.widget<KitProcCard>(find.byType(KitProcCard)).failed, isFalse);
          expect(tester.widget<KitProcPill>(find.byType(KitProcPill)).tone, KitProcTone.wait);
        } else {
          expect(tester.widget<KitLibStage>(find.byType(KitLibStage)).tone, KitProcTone.wait);
        }
        if (look == ProcessingLook.arrival) {
          final slip = tester.widget<KitArrivalSlip>(find.byType(KitArrivalSlip));
          expect(slip.muted, isTrue, reason: 'web .lx-arr-copy: the stamp in muted ink');
          expect(slip.stamp, 'Already in your library');
        }
      });

      testWidgets('Add anyway and View (the original); no Retry, no Index it anyway',
          (tester) async {
        final rec = _Router();
        ApiService.instance.httpClientAdapter = rec;
        final opened = await _pumpRow(tester, _after(), look: look);
        expect(find.textContaining('Index it anyway'), findsNothing);
        expect(find.text('Retry'), findsNothing);
        expect(find.text('View file'), findsNothing, reason: 'the copy has nothing to read');
        await tester.tap(find.text('View'));
        await tester.pumpAndSettle();
        expect(opened, ['cap-dedupe-a']);
        await tester.tap(find.text('Add anyway'));
        await tester.pumpAndSettle();
        final sent = rec.sent.single;
        expect(sent.path, endsWith('/fn_retry_document'));
        expect(sent.data, {'docId': 'copy-1', 'force': true},
            reason: 'force on a copy is allow_duplicate, the server\'s reading');
      });
    });
  }

  testWidgets('Add anyway asks in its own words when a confirm is owed', (tester) async {
    final rec = _Router();
    ApiService.instance.httpClientAdapter = rec;
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => ActivityNotifier(),
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ProcessingRow(
            doc: _after(),
            editCheck: (_) async => null,
            studyCheck: (_) async => false,
            openOriginal: (_) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add anyway'));
    await tester.pumpAndSettle();
    expect(find.text('Add “cap-dedupe-b.png” anyway?'), findsOneWidget);
    expect(find.text(sourceCopyLead), findsOneWidget);
    expect(sourceCopyLead,
        'This picture will be read as a source of its own, beside the one already in your library.');
    expect(find.descendant(of: find.byType(KitConfirm), matching: find.text('Add anyway')),
        findsOneWidget);
    expect(rec.sent, isEmpty, reason: 'nothing leaves before the confirm');
  });

  group('a copy recognised before its upload', () {
    testWidgets('no control on a client that does not hold the photo', (tester) async {
      expect(_case('api/uploads', 'uploads:retry-not-uploaded-duplicate-refused')['response']
          ['status'], 409);
      final rec = _Router();
      ApiService.instance.httpClientAdapter = rec;
      final doc = _before('v1:twin');
      final opened = await _pumpRow(tester, doc);
      expect(find.text('Add anyway'), findsNothing);
      expect(find.textContaining('Index it anyway'), findsNothing);
      expect(find.text(doc.errorMessage!), findsOneWidget, reason: 'its sentence says where to go');
      expect(find.text('Remove'), findsOneWidget);
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      expect(opened, ['cap-uploads-original']);
      expect(rec.sent, isEmpty);
    });

    testWidgets('on the phone that holds it: Add anyway is the capture session\'s force',
        (tester) async {
      final store = MemoryLedgerStore();
      final bridge = FakeBridge([asset('p1')]);
      final endpoints = FakeEndpoints();
      final host = CameraSweepHost(
        session: _Session(),
        isSignedIn: () => true,
        bridge: bridge,
        store: store,
        endpoints: endpoints,
        uploader: endpoints.uploader,
        background: FakeBackground(),
        observeLifecycle: false,
      );
      await tester.runAsync(() => host.ready);
      final key = bridge.assets.single.assetKey;
      endpoints.answers[key] =
          (_case('api/uploads', 'uploads:capture-session-force-add-anyway')['response']['body']
                  as Map)
              .cast<String, dynamic>();
      final rec = _Router();
      ApiService.instance.httpClientAdapter = rec;

      // Not yet held: the ledger has no duplicate verdict for this key.
      await _pumpRow(tester, _before(key), host: host);
      expect(find.text('Add anyway'), findsNothing);

      // The ledger records the photo after the row arrived: the row follows.
      await tester.runAsync(() => host.ledger!.record(LedgerVerdict.duplicate(key), 'p1'));
      await tester.pumpAndSettle();
      expect(find.text('Add anyway'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.text('Add anyway'));
        for (var i = 0; i < 50 && endpoints.uploader.starts.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(rec.sent, isEmpty, reason: 'never fn_retry_document: it would 409');
      final call = endpoints.sessions.single;
      expect(call.force, isTrue);
      expect(call.assetKey, key);
      expect(endpoints.uploader.starts, hasLength(1), reason: 'the photo is read and sent');
      host.dispose();
    });
  });

  group('a plain skipped row is unchanged', () {
    testWidgets('Error, the glyph, Index it anyway', (tester) async {
      final doc = Document.fromJson('s1', {
        'user_id': 'u1', 'title': 'beach.jpg', 'type': 'image', 'status': 'skipped',
        'skip_reason': 'no_text_content', 'error_message': 'No text was found.'});
      await _pumpRow(tester, doc);
      expect(_muted(), findsNothing);
      expect(find.text('ERROR'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.text('Index it anyway'), findsOneWidget);
      expect(find.text('Add anyway'), findsNothing);
    });
  });

  group('Added again', () {
    test('doc_duplicate is "Added again" in a source\'s History, its note the detail', () {
      final h = sourceHistory(docId: 'orig', activity: [
        ActivityItem(
          kind: 'event', id: 'e1', type: 'doc_duplicate', status: 'info', level: 'info',
          title: 'IMG_0420.HEIC', createdAt: 1,
          metadata: {
            'doc_id': 'orig', 'duplicate_id': 'copy', 'matched_by': 'same_capture',
            'note': 'The same picture came in again from your camera roll and was kept as one source.',
          }),
      ]);
      expect(h.rows.single.label, 'Added again');
      expect(h.rows.single.detail,
          'The same picture came in again from your camera roll and was kept as one source.');
    });

    test('the Activity feed\'s chip: Added again, family processing', () {
      // The table is private; its shape is what activity_vocab_check parses
      // (one entry per line), so this reads it the same way.
      final src = File('lib/pages/activity_page.dart').readAsStringSync();
      expect(
          RegExp(r"'doc_duplicate': \(family: 'processing', chip: 'Added again',").hasMatch(src),
          isTrue);
    });

    test('the merge covers the copy by metadata.duplicate_id', () {
      ActivityItem doc(String id) => ActivityItem(
          kind: 'document', id: id, type: 'image', status: 'skipped', level: 'info',
          title: id, createdAt: 1);
      final merged = mergeActivity([
        ActivityItem(
            kind: 'event', id: 'e', type: 'doc_duplicate', status: 'info', level: 'info',
            title: 'orig', createdAt: 2,
            metadata: {'doc_id': 'orig', 'duplicate_id': 'copy'}),
      ], [doc('copy'), doc('orig'), doc('other')]);
      expect(merged.map((i) => i.id), ['e', 'other']);
    });
  });
}
