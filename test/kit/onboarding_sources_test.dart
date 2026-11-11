/// F-190 · Onboarding's sources step in web's composition (steps.jsx `Sources`,
/// app-onboarding-wizard.css `.ob-added`; onboarding.md §Rules).
///
/// Web draws *In your library* with *{indexed} indexed · {total} total* as the
/// HEAD of the box that holds what this run added, and only when it holds
/// something. This client drew the uploader's rows first and the label after
/// them — under the uploads it counts — and on a replay with a library and
/// nothing added it stood over nothing. A finished row said *Queued for
/// processing* beside a remove ✕; web says *added — indexing continues in the
/// background* under the name, with an Uploading / Added / Failed pill.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/pages/onboarding/steps.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/state/upload_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';

class _Ingest implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody.fromString(jsonEncode({'docId': 'd-new'}), 201, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  @override
  void close({bool force = false}) {}
}

Document _doc(String id, String status) => Document.fromJson(id, {
      'user_id': 'u1',
      'title': id,
      'type': 'article',
      'status': status,
    });

final _library = [_doc('a', 'complete'), _doc('b', 'processing')];

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider<UploadNotifier>(
    create: (_) => UploadNotifier(),
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(child: SourcesStep(documents: _library)),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  setUp(() {
    ApiService.instance.tokenProvider = () async => 'test-token';
    ApiService.instance.httpClientAdapter = _Ingest();
  });
  tearDown(ApiService.instance.resetTestSeams);

  testWidgets('a replay with a library and nothing added draws no count',
      (tester) async {
    await _pump(tester);
    expect(find.text('IN YOUR LIBRARY'), findsNothing,
        reason: 'web draws the head only over what this run added');
    expect(find.text('In your library'), findsNothing);
  });

  testWidgets('In your library heads the rows it counts, in web\'s words',
      (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), 'https://example.com/essay');
    await tester.pump();
    await tester.tap(find.text('Add link'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    final head = find.text('IN YOUR LIBRARY');
    expect(head, findsOneWidget);
    expect(find.text('1 indexed · 2 total'), findsOneWidget);
    final sub = find.text('added — indexing continues in the background');
    expect(sub, findsOneWidget);
    expect(tester.getTopLeft(head).dy < tester.getTopLeft(sub).dy, isTrue,
        reason: 'the count stands over the uploads it counts');
    expect(find.text('ADDED'), findsOneWidget, reason: 'web\'s state pill');
    expect(find.text('Queued for processing'), findsNothing);
    expect(find.byTooltip('Remove'), findsNothing,
        reason: 'web\'s onboarding row has no remove');
    final note = find.textContaining('Indexing runs in the background');
    expect(tester.getTopLeft(sub).dy < tester.getTopLeft(note).dy, isTrue);
  });
}
