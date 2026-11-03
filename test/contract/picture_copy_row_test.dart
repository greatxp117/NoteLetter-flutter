/// A picture already in the library (5.50.0–5.51.0, ADR-202, INV-37) — the
/// copy's row, its Compare sheet, its labels and its merge; web
/// `tests/contract/picture-copy-row.test.js`.
///
/// The copy is a `skipped` document whose CLOSED `skip_reason` says so, and it
/// is listed, never dropped (Xavier, 2026-11-02). These assert the row this
/// client draws for the document shapes the backend captured
/// (fixtures/scenarios/picture-dedupe, fixtures/api/uploads), in all three
/// looks (For your review's card, the Library's D row and its Grid arrival):
///   - muted (opacity 0.55), never failure-styled: no alert glyph, the stage
///     and stamp say "Already in your library";
///   - one quiet line from the original's own record: *In your library since
///     {date} · {how}*, or that it was removed, or could not be read;
///   - `already_in_library` offers Add anyway (a forced retry in its own
///     words), never Index it anyway and never Retry;
///   - `already_in_library_not_uploaded` offers Add anyway ONLY on the phone
///     whose camera-roll ledger holds the photo, and then it is the capture
///     session's `force`, never `fn_retry_document` (which 409s it:
///     `uploads:retry-not-uploaded-duplicate-refused`);
///   - Compare (5.51.0, replacing View) opens both pictures side by side with
///     when, how and size, and the row's three choices.
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
import 'package:flutter_app/pages/sources/compare_sheet.dart';
import 'package:flutter_app/services/activity_merge.dart';
import 'package:flutter_app/services/api.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/source_history.dart';
import 'package:flutter_app/services/sweep_ledger.dart';
import 'package:flutter_app/shared/picture_copy.dart';
import 'package:flutter_app/state/activity_notifier.dart';
import 'package:flutter_app/state/camera_sweep_host.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

import 'fixtures.dart';
import 'sweep_fakes.dart';

/// Records every request; answers `fn_get_raw_document_url` with a signed URL
/// per document (or [rawUrl]'s answer), everything else 200.
class _Router implements HttpClientAdapter {
  final List<RequestOptions> sent = [];

  /// docId → (status, body) for fn_get_raw_document_url; default: a URL.
  final Map<String, (int, Object)> raw = {};

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    sent.add(options);
    var answer = (200, <String, Object?>{'ok': true} as Object);
    if (options.path.endsWith('/fn_get_raw_document_url')) {
      final id = (options.data as Map)['docId'] as String;
      answer = raw[id] ?? (200, {'signed_url': 'https://signed.example/$id.jpg'});
    }
    return ResponseBody.fromString(jsonEncode(answer.$2), answer.$1, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}

  List<RequestOptions> to(String endpoint) =>
      [for (final o in sent) if (o.path.endsWith('/$endpoint')) o];
}

Map<String, dynamic> _case(String suite, String id) =>
    ((loadSuite(suite)!['cases'] as List).firstWhere((c) => c['id'] == id) as Map)
        .cast<String, dynamic>();

/// The original, as its record answers (web's ORIGINAL): a camera-roll photo
/// added Oct 12 at 9:03 AM, on this machine's clock.
final _octTwelve = DateTime(2026, 10, 12, 9, 3).millisecondsSinceEpoch;
Document _original(String id) => Document.fromJson(id, {
      'user_id': 'u1',
      'title': 'IMG_0420.HEIC',
      'type': 'image',
      'status': 'complete',
      'created_at': _octTwelve,
      'source_capture': {'source': 'camera_roll'},
      'picture': {'width': 3024, 'height': 4032},
    });

/// The copy as the pipeline left it (picture-dedupe, case 1), uploaded from a
/// computer just now.
Document _after() {
  final copy = (_case('picture-dedupe', 'picture-dedupe:same-file-is-listed-not-read')
          ['response']['body']['copy'] as Map)
      .cast<String, dynamic>();
  return Document.fromJson('copy-1', {
    'user_id': 'u1',
    'title': 'cap-dedupe-b.png',
    'type': 'image',
    ...copy,
    'created_at': DateTime.now().millisecondsSinceEpoch,
    'upload_origin': 'computer',
    'picture': {'width': 1512, 'height': 2016},
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
  Future<bool?> Function(String)? editCheck,
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
              editCheck: editCheck ?? (_) async => false,
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

Finder _stage({String? url, bool bytes = false}) => find.byWidgetPredicate((w) =>
    w is KitCompareStage && (url == null || w.url == url) && (!bytes || w.bytes != null));

Finder _inSheet(Finder f) =>
    find.descendant(of: find.byType(KitOverlaySheet), matching: f);

Future<_Router> _openCompare(WidgetTester tester, Document doc,
    {CameraSweepHost? host}) async {
  final rec = _Router();
  ApiService.instance.httpClientAdapter = rec;
  await _pumpRow(tester, doc, host: host);
  await tester.tap(find.text(compareLabel));
  await tester.pumpAndSettle();
  return rec;
}

void main() {
  setUp(() {
    ApiService.instance.tokenProvider = () async => 'test-token';
    OriginalRecords.reset();
    OriginalRecords.read = (id) async => _original(id);
  });
  tearDown(() {
    ApiService.instance.resetTestSeams();
    OriginalRecords.reset();
  });

  group('the document', () {
    test('a copy names its original; skip_reason (closed) says it is one', () {
      final after = _after();
      expect(after.skipReason, 'already_in_library');
      expect(after.duplicateOf, 'cap-dedupe-a');
      expect(after.isPictureCopy, isTrue);
      expect(after.uploadOrigin, 'computer');
      expect((after.pictureWidth, after.pictureHeight), (1512, 2016));
      final before = _before('v1:twin');
      expect(before.isPictureCopy, isTrue);
      expect(before.captureAssetKey, 'v1:twin');
      expect(before.fromCameraRoll, isTrue);
      final skipped = Document.fromJson('s', {
        'status': 'skipped', 'skip_reason': 'no_text_content', 'duplicate_of': 'x'});
      expect(skipped.isPictureCopy, isFalse, reason: 'the reason decides, never a field beside it');
      final complete = Document.fromJson('c', {
        'status': 'complete', 'skip_reason': 'already_in_library'});
      expect(complete.isPictureCopy, isFalse, reason: 'only a skipped row is a copy');
      expect(Document.fromJson('d', {'cloud_placement': {'provider': 'dropbox'}}).cloudProvider,
          'dropbox');
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

      testWidgets('the original\'s own record, in one quiet line', (tester) async {
        await _pumpRow(tester, _after(), look: look);
        expect(find.text('In your library since Oct 12 · from your camera roll'),
            findsOneWidget);
        expect(find.byType(KitProcOriginLine), findsOneWidget);
      });

      testWidgets('Add anyway and Compare; no Retry, no Index it anyway, no View',
          (tester) async {
        final rec = _Router();
        ApiService.instance.httpClientAdapter = rec;
        await _pumpRow(tester, _after(), look: look);
        expect(find.textContaining('Index it anyway'), findsNothing);
        expect(find.text('Retry'), findsNothing);
        expect(find.text('View'), findsNothing, reason: '5.51.0: Compare replaced it');
        expect(find.text('View file'), findsNothing, reason: 'the copy has nothing to read');
        expect(find.text(compareLabel), findsOneWidget);
        await tester.tap(find.text('Add anyway'));
        await tester.pumpAndSettle();
        final sent = rec.to('fn_retry_document').single;
        expect(sent.data, {'docId': 'copy-1', 'force': true},
            reason: 'force on a copy is allow_duplicate, the server\'s reading');
      });
    });
  }

  group('the line, when the original cannot be drawn from', () {
    testWidgets('removed since: said, never "couldn\'t be read"', (tester) async {
      OriginalRecords.read = (_) async => null;
      await _pumpRow(tester, _after());
      expect(find.text(originalGone), findsOneWidget);
      expect(originalGone, 'The original is no longer in your library.');
    });

    testWidgets('a read that failed: said, never "removed"', (tester) async {
      OriginalRecords.read = (_) async => throw StateError('offline');
      await _pumpRow(tester, _after());
      expect(find.text(originalUnread), findsOneWidget);
      expect(originalUnread, 'The original couldn’t be read.');
    });

    testWidgets('one read per original, shared by every row that names it', (tester) async {
      var reads = 0;
      OriginalRecords.read = (id) async {
        reads++;
        return _original(id);
      };
      await tester.pumpWidget(MultiProvider(
        providers: [ChangeNotifierProvider(create: (_) => ActivityNotifier())],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(children: [
                for (final id in ['c1', 'c2', 'c3'])
                  ProcessingRow(
                      key: ValueKey(id),
                      doc: Document.fromJson(id, {
                        'title': id, 'type': 'image', 'status': 'skipped',
                        'skip_reason': 'already_in_library', 'duplicate_of': 'orig',
                        'error_message': 'A copy.'})),
              ]),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(KitProcOriginLine), findsNWidgets(3));
      expect(reads, 1);
    });
  });

  group('Compare', () {
    testWidgets('both pictures with when, how and size, and the three choices', (tester) async {
      final copy = _after();
      final rec = await _openCompare(tester, copy);
      expect(_inSheet(find.text(CompareCopySheet.title)), findsOneWidget);
      expect(CompareCopySheet.title, 'Is this the same picture?');
      expect(_inSheet(find.text(copy.errorMessage!)), findsOneWidget,
          reason: 'its sub-line is the copy\'s sentence');
      expect(_inSheet(find.text('THIS ONE')), findsOneWidget);
      expect(_inSheet(find.text('ALREADY IN YOUR LIBRARY')), findsOneWidget);
      // Read only now, each through fn_get_raw_document_url.
      expect(rec.to('fn_get_raw_document_url').map((o) => (o.data as Map)['docId']).toSet(),
          {'copy-1', 'cap-dedupe-a'});
      expect(_stage(url: 'https://signed.example/copy-1.jpg'), findsOneWidget);
      expect(_stage(url: 'https://signed.example/cap-dedupe-a.jpg'), findsOneWidget);
      expect(find.text('Uploaded from your computer'), findsOneWidget);
      expect(find.text('1512 × 2016'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^Added today, \d{1,2}:\d\d (AM|PM)$')), findsOneWidget);
      expect(find.text('From your camera roll'), findsOneWidget);
      expect(find.text('3024 × 4032'), findsOneWidget);
      expect(find.text('Added Oct 12, 9:03 AM'), findsOneWidget);
      expect(_inSheet(find.text(CompareCopySheet.openOriginal)), findsOneWidget);
      expect(_inSheet(find.text(CompareCopySheet.removeCopy)), findsOneWidget);
      expect(_inSheet(find.text(CompareCopySheet.addAnyway)), findsOneWidget);
    });

    testWidgets('Open the original closes the sheet and opens it', (tester) async {
      final rec = _Router();
      ApiService.instance.httpClientAdapter = rec;
      final opened = await _pumpRow(tester, _after());
      await tester.tap(find.text(compareLabel));
      await tester.pumpAndSettle();
      await tester.tap(_inSheet(find.text(CompareCopySheet.openOriginal)));
      await tester.pumpAndSettle();
      expect(find.byType(KitOverlaySheet), findsNothing);
      expect(opened, ['cap-dedupe-a']);
    });

    testWidgets('Remove this copy is the row\'s Remove, with its confirm', (tester) async {
      final rec = await _openCompare(tester, _after());
      await tester.tap(_inSheet(find.text(CompareCopySheet.removeCopy)));
      await tester.pumpAndSettle();
      expect(find.byType(KitOverlaySheet), findsNothing);
      expect(find.text('Remove “cap-dedupe-b.png”?'), findsOneWidget, reason: '§18 first');
      expect(rec.to('fn_delete_document'), isEmpty, reason: 'nothing leaves before the confirm');
    });

    testWidgets('Add anyway is the row\'s: a forced retry', (tester) async {
      final rec = await _openCompare(tester, _after());
      await tester.tap(_inSheet(find.text(CompareCopySheet.addAnyway)));
      await tester.pumpAndSettle();
      expect(find.byType(KitOverlaySheet), findsNothing);
      expect(rec.to('fn_retry_document').single.data, {'docId': 'copy-1', 'force': true});
    });

    testWidgets('a picture whose request failed: §14.1 with Try again', (tester) async {
      final rec = _Router()
        ..raw['copy-1'] = (500, {'error': 'Storage is unavailable.', 'request_id': 'req-9'});
      ApiService.instance.httpClientAdapter = rec;
      await _pumpRow(tester, _after());
      await tester.tap(find.text(compareLabel));
      await tester.pumpAndSettle();
      final block = find.widgetWithText(KitFailureBlock, CompareCopySheet.unopened);
      expect(block, findsOneWidget);
      expect(CompareCopySheet.unopened, 'This picture couldn’t be opened.');
      rec.raw.remove('copy-1');
      final before = rec.to('fn_get_raw_document_url').length;
      await tester.tap(find.descendant(of: block, matching: find.text('Try again')));
      await tester.pumpAndSettle();
      expect(rec.to('fn_get_raw_document_url').length - before, 1, reason: 'asked again');
      expect(_stage(url: 'https://signed.example/copy-1.jpg'), findsOneWidget);
    });

    testWidgets('a successful answer with no object is said, not a failure', (tester) async {
      final rec = _Router()..raw['copy-1'] = (200, {'signed_url': null});
      ApiService.instance.httpClientAdapter = rec;
      await _pumpRow(tester, _after());
      await tester.tap(find.text(compareLabel));
      await tester.pumpAndSettle();
      expect(find.text('No picture is stored for this source.'), findsOneWidget);
      expect(find.byType(KitFailureBlock), findsNothing);
    });

    testWidgets('an original removed since: said, and no Open the original', (tester) async {
      OriginalRecords.read = (_) async => null;
      await _openCompare(tester, _after());
      expect(_inSheet(find.text(originalGone)), findsOneWidget);
      expect(_inSheet(find.text(CompareCopySheet.openOriginal)), findsNothing);
      expect(_inSheet(find.text(CompareCopySheet.removeCopy)), findsOneWidget);
    });

    testWidgets('an original that could not be read: §14.1, Open the original stays',
        (tester) async {
      OriginalRecords.read = (_) async => throw StateError('offline');
      await _openCompare(tester, _after());
      final block = find.widgetWithText(KitFailureBlock, originalUnread);
      expect(block, findsOneWidget);
      expect(_inSheet(find.text(CompareCopySheet.openOriginal)), findsOneWidget);
      // Try again reads again (a failure is never kept as the answer).
      OriginalRecords.read = (id) async => _original(id);
      await tester.tap(find.descendant(of: block, matching: find.text('Try again')));
      await tester.pumpAndSettle();
      expect(find.text('From your camera roll'), findsOneWidget);
      // Its picture is asked for only now; let the answer arrive.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(_stage(url: 'https://signed.example/cap-dedupe-a.jpg'), findsOneWidget);
    });

    testWidgets('a copy never uploaded, off the phone that holds it', (tester) async {
      final rec = await _openCompare(tester, _before('v1:twin'));
      expect(find.text(CompareCopySheet.stayedOnPhone), findsOneWidget);
      expect(CompareCopySheet.stayedOnPhone, 'This photo stayed on your phone.');
      expect(rec.to('fn_get_raw_document_url').map((o) => (o.data as Map)['docId']),
          ['cap-uploads-original'], reason: 'nothing on the server to read for the copy');
      expect(_inSheet(find.text(CompareCopySheet.addAnyway)), findsNothing);
    });
  });

  testWidgets('Add anyway asks in its own words when a confirm is owed', (tester) async {
    final rec = _Router();
    ApiService.instance.httpClientAdapter = rec;
    await _pumpRow(tester, _after(), editCheck: (_) async => null);
    await tester.tap(find.text('Add anyway'));
    await tester.pumpAndSettle();
    expect(find.text('Add “cap-dedupe-b.png” anyway?'), findsOneWidget);
    expect(find.text(sourceCopyLead), findsOneWidget);
    expect(sourceCopyLead,
        'This picture will be read as a source of its own, beside the one already in your library.');
    expect(find.descendant(of: find.byType(KitConfirm), matching: find.text('Add anyway')),
        findsOneWidget);
    expect(rec.to('fn_retry_document'), isEmpty, reason: 'nothing leaves before the confirm');
  });

  group('a copy recognised before its upload', () {
    testWidgets('no control on a client that does not hold the photo', (tester) async {
      expect(_case('api/uploads', 'uploads:retry-not-uploaded-duplicate-refused')['response']
          ['status'], 409);
      final rec = _Router();
      ApiService.instance.httpClientAdapter = rec;
      final doc = _before('v1:twin');
      await _pumpRow(tester, doc);
      expect(find.text('Add anyway'), findsNothing);
      expect(find.textContaining('Index it anyway'), findsNothing);
      expect(find.text(doc.errorMessage!), findsOneWidget, reason: 'its sentence says where to go');
      expect(find.text('Remove'), findsOneWidget);
      expect(find.text(compareLabel), findsOneWidget);
      expect(rec.sent, isEmpty);
    });

    testWidgets('on the phone that holds it: Add anyway is the capture session\'s force, '
        'and Compare draws its own thumbnail', (tester) async {
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

      // Compare: on this phone, the copy's slot is its own thumbnail.
      bridge.thumbnailBytes['p1'] = Uint8List.fromList(
          base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='));
      await tester.runAsync(() async {
        await tester.tap(find.text(compareLabel));
        for (var i = 0; i < 50 && bridge.thumbnailsAsked.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(bridge.thumbnailsAsked, ['p1']);
      expect(_stage(bytes: true), findsOneWidget);
      expect(find.text(CompareCopySheet.stayedOnPhone), findsNothing);
      expect(_inSheet(find.text(CompareCopySheet.addAnyway)), findsOneWidget,
          reason: 'the row\'s condition: this phone holds it');
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.text('Add anyway'));
        for (var i = 0; i < 50 && endpoints.uploader.starts.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(rec.to('fn_retry_document'), isEmpty, reason: 'never fn_retry_document: it would 409');
      final call = endpoints.sessions.single;
      expect(call.force, isTrue);
      expect(call.assetKey, key);
      expect(endpoints.uploader.starts, hasLength(1), reason: 'the photo is read and sent');
      host.dispose();
    });
  });

  group('a plain skipped row is unchanged', () {
    testWidgets('Error, the glyph, Index it anyway, its own source', (tester) async {
      final doc = Document.fromJson('s1', {
        'user_id': 'u1', 'title': 'beach.jpg', 'type': 'image', 'status': 'skipped',
        'skip_reason': 'no_text_content', 'error_message': 'No text was found.'});
      await _pumpRow(tester, doc);
      expect(_muted(), findsNothing);
      expect(find.text('ERROR'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.text('Index it anyway'), findsOneWidget);
      expect(find.text('Add anyway'), findsNothing);
      expect(find.text(compareLabel), findsNothing);
      expect(find.byType(KitProcOriginLine), findsNothing);
    });
  });

  group('how and when', () {
    Document d(Map<String, dynamic> j) => Document.fromJson('x', j);

    test('how: camera roll, a cloud service, the upload origin, else Uploaded', () {
      expect(howPhrase(d({'source_capture': {}})), 'From your camera roll');
      expect(howPhrase(d({'cloud_placement': {'provider': 'google_drive'}})), 'From Google Drive');
      expect(howPhrase(d({'upload_origin': 'computer'})), 'Uploaded from your computer');
      expect(howPhrase(d({'upload_origin': 'phone'})), 'Uploaded from your phone');
      expect(howPhrase(d({'upload_origin': 'share_sheet'})), 'Shared from your phone');
      expect(howPhrase(d({'upload_origin': null})), 'Uploaded');
      expect(howPhrase(d({'source_capture': {}, 'upload_origin': 'phone'})),
          'From your camera roll', reason: 'most specific first');
    });

    test('when: today, this year, another year — on the reader\'s clock', () {
      final now = DateTime(2026, 11, 2, 18);
      expect(addedLine(DateTime(2026, 11, 2, 14, 14).millisecondsSinceEpoch, now: now),
          'Added today, 2:14 PM');
      expect(addedLine(DateTime(2026, 10, 12, 9, 3).millisecondsSinceEpoch, now: now),
          'Added Oct 12, 9:03 AM');
      expect(addedLine(DateTime(2025, 10, 12, 0, 5).millisecondsSinceEpoch, now: now),
          'Added Oct 12, 2025, 12:05 AM');
      expect(addedLine(null), isNull);
      expect(
          sinceLine(d({'created_at': DateTime(2025, 3, 4, 12).millisecondsSinceEpoch,
              'upload_origin': 'phone'}), now: now),
          'In your library since Mar 4, 2025 · uploaded from your phone');
      expect(sizeLine(d({'picture': {'width': 3024, 'height': 4032}})), '3024 × 4032');
      expect(sizeLine(d({})), isNull);
    });

    test('this client sends an origin of the closed set the server takes', () {
      final taken = [
        for (final c in (loadSuite('api/uploads')!['cases'] as List))
          if ((c['id'] as String).startsWith('uploads:create-origin-') &&
              c['response']['status'] == 201)
            c['request']['body']['origin'] as String
      ]..sort();
      expect(taken, ['computer', 'phone', 'share_sheet']);
      expect(taken, contains(UploadOrigin.app));
      expect(UploadOrigin.app, UploadOrigin.phone, reason: 'the app\'s picker and quick add');
      expect(taken, contains(UploadOrigin.shareSheet));
      // What the server stored, read back (`uploads:origin-stored`): each
      // origin as sent, null where none was — and each reads as its phrase.
      final stored = (_case('api/uploads', 'uploads:origin-stored')['response']['body']
          ['upload_origin_by_title'] as Map);
      expect(stored.values.toSet(), {'computer', 'phone', 'share_sheet', null});
      expect({
        for (final e in stored.entries)
          e.key: howPhrase(Document.fromJson('x', {'upload_origin': e.value}))
      }, {
        'from-computer.jpg': 'Uploaded from your computer',
        'from-phone.jpg': 'Uploaded from your phone',
        'from-share_sheet.jpg': 'Shared from your phone',
        'photo.jpg': 'Uploaded',
      });
      // The share screen says so; the picker and quick add take the app's word.
      expect(File('lib/pages/share_page.dart').readAsStringSync(),
          contains('origin: UploadOrigin.shareSheet'));
      expect(File('lib/state/upload_notifier.dart').readAsStringSync(),
          contains('origin ?? UploadOrigin.app'));
    });
  });

  group('Added again', () {
    test('doc_duplicate is "Added again" in a source\'s History, its note the detail', () {
      final h = sourceHistory(docId: 'orig', activity: [
        const ActivityItem(
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
        const ActivityItem(
            kind: 'event', id: 'e', type: 'doc_duplicate', status: 'info', level: 'info',
            title: 'orig', createdAt: 2,
            metadata: {'doc_id': 'orig', 'duplicate_id': 'copy'}),
      ], [doc('copy'), doc('orig'), doc('other')]);
      expect(merged.map((i) => i.id), ['e', 'other']);
    });
  });
}
