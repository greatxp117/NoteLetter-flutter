import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/pages/letters/pinned_sources.dart';
import 'package:flutter_app/pages/reader/summary_panel.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

/// **C6 — the server's sentence, not a constant of ours.**
///
/// Six handlers caught an `ApiException`, dropped `e.message` and rendered
/// four words of their own. Two things failed together at most of them: the
/// sentence was replaced, and it was put in a toast that dismisses itself
/// after four seconds — both of which fail the same reader, the one who has
/// to CORRECT something.
///
/// The sharpest was `summary_panel`, which pattern-matched a **429** into
/// "give it a minute before trying again". The cooldown sentence is the
/// server's, because the endpoint knows how long is left; a constant here is
/// a guess that goes stale invisibly the day the window changes. ADR-070:
/// quote what was sent, never translate a status into copy of ours.
///
/// Driven through C4g's transport seam, so the real handlers run against a
/// real status and body.

class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.status, this.body);

  final int status;
  final Object body;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

class _StubService extends FirestoreService {
  _StubService(this.pinned) : super.stub();
  final Stream<List<Document>> pinned;

  @override
  String? get currentUid => 'u1';

  @override
  Stream<List<Document>> subscribePinnedDocuments() => pinned;
}

Document _doc(String id, {String? summary}) => Document(
      id: id,
      userId: 'u1',
      title: 'A pinned volume',
      type: 'pdf',
      status: DocumentStatus.complete,
      createdAt: 1757000000000,
      summary: summary,
    );

void main() {
  setUp(() => ApiService.instance.tokenProvider = () async => 'test-token');
  tearDown(() {
    ApiService.instance.resetTestSeams();
    FirestoreService.resetInstance();
  });

  testWidgets('a 429 cooldown is quoted, not guessed at', (tester) async {
    ApiService.instance.httpClientAdapter = _CannedAdapter(429, {
      'error': 'Already regenerated — 4 minutes 12 seconds left.',
      'error_code': 'COOLDOWN',
    });

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: SummaryPanel(
              doc: _doc('d1', summary: 'A stored summary.'),
              onRegenerated: (_) {}),
        ),
      ),
    ));

    await tester.tap(find.textContaining('Regenerate'));
    // The canned adapter still resolves through Dio's own futures, so the
    // request needs a turn of the loop before the note can be set.
    await tester.pumpAndSettle();

    expect(find.textContaining('4 minutes 12 seconds'), findsOneWidget,
        reason: 'the endpoint knows how long is left; a constant "give it a '
            'minute" is a guess that goes stale invisibly');
    expect(find.textContaining('give it a minute'), findsNothing);
  });

  testWidgets('a non-429 refusal is quoted too', (tester) async {
    ApiService.instance.httpClientAdapter = _CannedAdapter(
        409, {'error': 'That summary is being rebuilt right now.'});

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: SummaryPanel(
              doc: _doc('d1', summary: 'A stored summary.'),
              onRegenerated: (_) {}),
        ),
      ),
    ));

    await tester.tap(find.textContaining('Regenerate'));
    // The canned adapter still resolves through Dio's own futures, so the
    // request needs a turn of the loop before the note can be set.
    await tester.pumpAndSettle();

    expect(find.textContaining('being rebuilt right now'), findsOneWidget);
  });

  testWidgets('unpinning quotes the refusal, in §14.2 and not a toast',
      (tester) async {
    FirestoreService.instance = _StubService(Stream.value([_doc('d1')]));
    ApiService.instance.httpClientAdapter = _CannedAdapter(
        409, {'error': 'That letter has already been sent.'});

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: PinnedSources(settings: null)),
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('Unpin'));
    await tester.pumpAndSettle();

    expect(find.textContaining('already been sent'), findsOneWidget,
        reason: '"Could not unpin that." is four words for three different '
            'answers');
    expect(find.byType(KitFailureInline), findsOneWidget,
        reason: 'the kit\'s §14.2, not a hand-spelled critical Text');
  });
}
