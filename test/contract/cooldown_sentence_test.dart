import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/study.dart';
import 'package:flutter_app/pages/reader/summary_panel.dart';
import 'package:flutter_app/pages/study_page.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/state/org_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

/// **C11 — a cooldown's sentence is the server's, and a client constant is a
/// guess that goes stale invisibly.**
///
/// Every cooldown branch in the backend computes the exact remaining wait and
/// says it. Three surfaces here overwrote that with a constant: "give it a
/// minute" (60s), "requested less than a minute ago" (60s) and "try again in
/// a few minutes" (300s). A guess is wrong in BOTH directions at once — it
/// reads as a minute when three seconds remain and as a minute when
/// fifty-five do — and nothing ties the copy to `_SUMMARY_REGEN_COOLDOWN_
/// SECONDS`, so the day that constant moves the screen lies with no gate
/// going red.
///
/// The thing this client needed first is the one the reference never did:
/// `ApiException.message` holds either the envelope's sentence or one of
/// `_handle`'s own constants, and before `serverSentence` a site could not
/// tell which. So each case below has its CONTROL — the same status with no
/// envelope — because a helper that renders `message` unconditionally passes
/// the first half of every test here and puts "The server did not answer as
/// expected (HTTP 429)." in the calm-copy slot.
class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.status, this.body, {this.json = true});

  final int status;
  final Object body;
  final bool json;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return ResponseBody.fromString(
      json ? jsonEncode(body) : body.toString(),
      status,
      headers: {
        Headers.contentTypeHeader: [
          json ? Headers.jsonContentType : Headers.textPlainContentType
        ]
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _StudyStub extends FirestoreService {
  _StudyStub(this.programs) : super.stub();
  final List<StudyProgram> programs;

  @override
  String? get currentUid => 'u1';

  @override
  Stream<List<StudyProgram>> subscribeStudyPrograms() => Stream.value(programs);

  @override
  Stream<List<StudySession>> subscribeStudySessions(
          {String? programId, int limit = 30}) =>
      Stream.value(const []);
}

Document _doc() => Document(
      id: 'd1',
      userId: 'u1',
      title: 'A stored volume',
      type: 'pdf',
      status: DocumentStatus.complete,
      createdAt: 1757000000000,
      summary: 'A stored summary.',
    );

Widget _summary() => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: SummaryPanel(doc: _doc(), onRegenerated: (_) {}),
        ),
      ),
    );

Widget _study() => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: StudyPage(),
        ),
      ),
    );

void main() {
  setUp(() => ApiService.instance.tokenProvider = () async => 'test-token');
  tearDown(() {
    ApiService.instance.resetTestSeams();
    FirestoreService.resetInstance();
  });

  group('the helper', () {
    test('quotes the envelope', () {
      const e = ApiException(429, 'Please wait 43 seconds before regenerating.',
          errorCode: 'COOLDOWN', serverSentence: true);
      expect(cooldownSentence(e, 'give it a minute'),
          'Please wait 43 seconds before regenerating.');
    });

    test('falls back where the refusal carried no sentence', () {
      // `_handle`'s own words arrive in the SAME field. Rendering them would
      // put "The server did not answer as expected (HTTP 429)." where a wait
      // belongs — which is why the flag exists and a non-empty check does not
      // suffice.
      const e = ApiException(429, 'The server did not answer as expected.');
      expect(cooldownSentence(e, 'give it a minute'), 'give it a minute');
    });

    test('an empty envelope sentence is not a sentence', () {
      const e = ApiException(429, '   ', serverSentence: true);
      expect(cooldownSentence(e, 'give it a minute'), 'give it a minute');
    });
  });

  group('reader · regenerate summary (60s)', () {
    testWidgets('the seconds are the server\'s and the constant is absent',
        (tester) async {
      ApiService.instance.httpClientAdapter = _CannedAdapter(429, {
        'error': 'Please wait 43 seconds before regenerating again.',
        'error_code': 'COOLDOWN',
      });

      await tester.pumpWidget(_summary());
      await tester.tap(find.textContaining('Regenerate'));
      await tester.pumpAndSettle();

      expect(find.textContaining('43 seconds'), findsOneWidget);
      expect(find.textContaining('give it a minute'), findsNothing);
      expect(find.byType(KitFailureInline), findsNothing,
          reason: 'a wait is not a failure — the summary on screen is still '
              'correct and nothing was blanked');
    });

    testWidgets('CONTROL · a 429 with no envelope keeps our words',
        (tester) async {
      ApiService.instance.httpClientAdapter =
          _CannedAdapter(429, '<html>429</html>', json: false);

      await tester.pumpWidget(_summary());
      await tester.tap(find.textContaining('Regenerate'));
      await tester.pumpAndSettle();

      expect(find.textContaining('give it a minute'), findsOneWidget);
      expect(find.textContaining('did not answer as expected'), findsNothing,
          reason: 'a transport sentence in the calm-copy slot says nothing '
              'about the wait');
    });

    testWidgets('anything else is §14.2 beside the control that refused',
        (tester) async {
      ApiService.instance.httpClientAdapter = _CannedAdapter(
          500, {'error': 'The summarizer is unavailable', 'request_id': 'r-9'});

      await tester.pumpWidget(_summary());
      await tester.tap(find.textContaining('Regenerate'));
      await tester.pumpAndSettle();

      expect(find.byType(KitFailureInline), findsOneWidget);
      expect(find.textContaining('The summarizer is unavailable'),
          findsOneWidget);
      expect(find.textContaining('The existing one is unchanged.'),
          findsOneWidget,
          reason: 'the reassurance is the caption, not a second clause glued '
              'to a server fragment with no full stop');
    });
  });

  group('study · request a session (60s)', () {
    testWidgets('the seconds are the server\'s and the constant is absent',
        (tester) async {
      FirestoreService.instance = _StudyStub([
        StudyProgram.fromJson('p1', {
          'title': 'Anatomy',
          'document_ids': ['d1'],
          'enabled': true,
          'status': 'active',
        })
      ]);
      ApiService.instance.httpClientAdapter = _CannedAdapter(429, {
        'error': 'Please wait 38 seconds before requesting another session.',
        'error_code': 'COOLDOWN',
      });

      await tester.pumpWidget(_study());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Study now'));
      await tester.pumpAndSettle();

      expect(find.textContaining('38 seconds'), findsOneWidget);
      expect(find.textContaining('less than a minute ago'), findsNothing);
    });

    testWidgets('CONTROL · a 429 with no envelope keeps our words',
        (tester) async {
      FirestoreService.instance = _StudyStub([
        StudyProgram.fromJson('p1', {
          'title': 'Anatomy',
          'document_ids': ['d1'],
          'enabled': true,
          'status': 'active',
        })
      ]);
      ApiService.instance.httpClientAdapter =
          _CannedAdapter(429, '<html>429</html>', json: false);

      await tester.pumpWidget(_study());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Study now'));
      await tester.pumpAndSettle();

      expect(find.textContaining('less than a minute ago'), findsOneWidget);
      expect(find.textContaining('did not answer as expected'), findsNothing);
    });
  });

  group('sources · rescan an organized folder (5 min, and a 409)', () {
    test('the wait is the server\'s', () async {
      // The cooldown arrives as a 409 COOLDOWN here, not a 429 — which is why
      // this site is keyed on `errorCode` and not on the status.
      ApiService.instance.httpClientAdapter = _CannedAdapter(409, {
        'error': 'Scanned 2 minutes ago — please wait 3 more minutes.',
        'error_code': 'COOLDOWN',
      });

      final msg = await OrgNotifier().scan('google_drive', folderId: 'f1');
      expect(msg, 'Scanned 2 minutes ago — please wait 3 more minutes.');
    });

    test('CONTROL · a COOLDOWN with no sentence keeps our words', () async {
      // The code without the words. A 409 carrying neither is NOT known to be
      // a cooldown and keeps `e.message`, which is the reference's rule too —
      // this is the case where we know it is a wait and were told nothing
      // about how long.
      ApiService.instance.httpClientAdapter =
          _CannedAdapter(409, {'error_code': 'COOLDOWN'});

      final msg = await OrgNotifier().scan('google_drive', folderId: 'f1');
      expect(msg, 'Scanned recently — try again in a few minutes.');
    });
  });
}
