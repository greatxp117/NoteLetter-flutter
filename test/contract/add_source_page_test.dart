import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/pages/add_source_page.dart';
import 'package:flutter_app/pages/sources/browse_section.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/shared/local_flags.dart';
import 'package:flutter_app/state/activity_notifier.dart';
import 'package:flutter_app/state/documents_notifier.dart';
import 'package:flutter_app/state/tags_notifier.dart';
import 'package:flutter_app/state/upload_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

import 'sources_harness.dart';

/// Add a source in direction D (screens/sources.md §Composition, *Add a
/// source*; web `AddSource.jsx`, `library-d.test.js`'s Add cases): the frame
/// and its words, the sheet's *What you can add*, and **Just added** — the
/// documents THIS visit created, read from the documents subscription (never
/// a timer): a document the subscription has not delivered is not drawn, one
/// in the pipeline is a processing row, one complete a register row, and one
/// created before the visit is not this visit's.

/// Answers every request with `fn_ingest_url`'s single-link answer, a new id
/// each time, and records nothing else.
class _Ingest implements HttpClientAdapter {
  final ids = <String>[];
  int _n = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final id = 'n${++_n}';
    ids.add(id);
    return ResponseBody.fromString(jsonEncode({'docId': id}), 201, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

Document _doc(String id, String status, {String title = 'A source'}) =>
    Document.fromJson(id, {
      'user_id': 'u1',
      'title': title,
      'type': 'article',
      'status': status,
      'chunk_count': status == 'complete' ? 4 : null,
      'source_url': 'https://example.com/$id',
      'created_at': DateTime(2026, 10, 30).millisecondsSinceEpoch,
    });

void main() {
  late StreamController<List<Document>> docs;
  late UploadNotifier upload;
  late _Ingest ingest;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalFlags.resetForTest();
    KitPageTools.instance.reset();
    ApiService.instance.tokenProvider = () async => 'test-token';
    ingest = _Ingest();
    ApiService.instance.httpClientAdapter = ingest;
    docs = StreamController<List<Document>>.broadcast();
    upload = UploadNotifier();
  });
  tearDown(() {
    ApiService.instance.resetTestSeams();
    FirestoreService.resetInstance();
  });

  Future<void> pump(WidgetTester tester,
      {Size size = const Size(800, 2400), bool dark = false}) async {
    FirestoreService.instance = SourcesStubService(documents: docs.stream);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<DocumentsNotifier>(
            create: (_) => DocumentsNotifier()),
        ChangeNotifierProvider<TagsNotifier>(create: (_) => StubTags()),
        ChangeNotifierProvider<ActivityNotifier>(create: (_) => StubActivity()),
        ChangeNotifierProvider<UploadNotifier>.value(value: upload),
      ],
      child: MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: const Scaffold(body: AddSourcePage()),
      ),
    ));
    await tester.pump();
    await tester.pump();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  Future<void> deliver(WidgetTester tester, List<Document> list) async {
    docs.add(list);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('the frame: crumb, folio, title, standfirst; the sheet',
      (tester) async {
    await pump(tester);
    await deliver(tester, const []);
    expect(find.text('THE LIBRARY'), findsOneWidget, reason: 'the back crumb');
    expect(find.textContaining('ADD A SOURCE'), findsOneWidget);
    expect(find.text('Add to Your Library'), findsOneWidget);
    expect(find.text(AddSourcePage.stand), findsOneWidget);
    // No tools but Search: no page action, no settings.
    expect(KitPageTools.instance.action, isNull);
    expect(KitPageTools.instance.settings, isNull);
    // The sheet: what the library takes, both size rows, and Also.
    expect(find.text('WHAT YOU CAN ADD'), findsOneWidget);
    expect(find.text('EACH UP TO'), findsOneWidget);
    expect(find.text('100 MB'), findsOneWidget);
    expect(find.text('A VIDEO UP TO'), findsOneWidget);
    expect(find.text('2 GB'), findsOneWidget);
    expect(find.text('Go to the library'), findsOneWidget);
    expect(find.text('What can I add?'), findsOneWidget);
    // The column: the drop zone in touch copy, the link row, no Just added.
    expect(find.text('Drop files, or tap to add a few'), findsOneWidget);
    expect(find.textContaining('up to 100 MB each, 2 GB for video'),
        findsOneWidget);
    expect(find.text('Add an image set (up to 20)'), findsOneWidget,
        reason: 'the device capability web lacks stays on the add surface');
    expect(find.text('Just added'), findsNothing);
  });

  testWidgets('Just added is this visit\'s, read from the subscription',
      (tester) async {
    // Created BEFORE the visit: a record, but not this visit's.
    await tester.runAsync(() => upload.addUrl('https://example.com/before'));
    expect(ingest.ids, ['n1']);

    await pump(tester);
    await deliver(tester, [_doc('n1', 'complete', title: 'Before')]);
    expect(find.text('Just added'), findsNothing);

    await tester.enterText(find.byType(TextField), 'https://example.com/now');
    await tester.pump();
    await tester.tap(find.widgetWithText(KitButton, 'Add link'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(ingest.ids, ['n1', 'n2']);

    // The answer is in, the subscription has not delivered n2: nothing drawn.
    expect(find.text('Just added'), findsNothing,
        reason: 'a document the subscription has not delivered is not drawn');

    await deliver(tester, [
      _doc('n1', 'complete', title: 'Before'),
      _doc('n2', 'processing', title: 'Now'),
    ]);
    expect(find.text('Just added'), findsOneWidget);
    expect(find.text('0 OF 1 READY'), findsOneWidget);
    expect(find.byType(ProcessingRow), findsOneWidget);
    expect(find.byType(KitLibProcRow), findsOneWidget);
    expect(find.text('Before'), findsNothing);
    expect(find.text('Go to library →'), findsOneWidget);
    // The sheet says it too.
    expect(find.text('JUST ADDED'), findsOneWidget);
    expect(find.text('BEING READ'), findsOneWidget);

    await deliver(tester, [
      _doc('n1', 'complete', title: 'Before'),
      _doc('n2', 'complete', title: 'Now'),
    ]);
    expect(find.text('1 OF 1 READY'), findsOneWidget);
    expect(find.byType(ProcessingRow), findsNothing);
    expect(find.byType(KitRegisterRow), findsOneWidget);
    expect(find.text('Now'), findsOneWidget);
  });

  testWidgets('a refused link is said by name, and the field keeps it',
      (tester) async {
    await pump(tester);
    await deliver(tester, const []);
    await tester.enterText(find.byType(TextField), 'not a link');
    await tester.pump();
    await tester.tap(find.widgetWithText(KitButton, 'Add link'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(KitRefusedNotice), findsOneWidget);
    expect(find.textContaining('doesn’t look like a link'), findsWidgets);
    expect(ingest.ids, isEmpty, reason: 'refused at the door: nothing sent');
    expect(find.text('not a link'), findsOneWidget,
        reason: 'keep the field, keep the text, say why (4.19.3)');
  });

  testWidgets('on a phone, in the dark: the peek says what this visit added',
      (tester) async {
    await pump(tester, size: const Size(390, 844), dark: true);
    await deliver(tester, const []);
    expect(tester.takeException(), isNull);
    final peek = find.byType(KitLibPeek);
    expect(find.descendant(of: peek, matching: find.text('What you can add')),
        findsOneWidget);
    await tester.enterText(find.byType(TextField), 'https://example.com/p');
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(KitButton, 'Add link'));
    await tester.pump();
    await tester.tap(find.widgetWithText(KitButton, 'Add link'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await deliver(tester, [_doc('n1', 'queued', title: 'Queued here')]);
    expect(find.descendant(of: peek, matching: find.text('Just added')),
        findsOneWidget);
    expect(find.descendant(of: peek, matching: find.text('0 of 1 ready')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
