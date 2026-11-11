/// F-194 — a refusal under a control comes into view when it arrives
/// (component-kit.md §14.2; web 19003d4: `sources/intake.jsx` useIntoView,
/// `reader/UpdateFromSourceBar.jsx` errRef; tests/contract/refusal-into-view).
///
/// On a 390 phone web's refusals drew below the page scroller's edge, under
/// the tab bar: Add's rejection row (its Shelves block pushed it below the
/// fold) and the reader's *Update from {provider}* line under a bar at the
/// page's foot. Each now brings itself into view, `block: 'nearest'`, ONCE
/// PER ARRIVAL: a remount (the Library moves what adding answered between the
/// empty catalogue and its slot) never scrolls the page back to an old
/// refusal nobody just made.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/models/chunk.dart';
import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/study.dart';
import 'package:flutter_app/models/tag.dart';
import 'package:flutter_app/pages/add_source_page.dart';
import 'package:flutter_app/pages/reader/update_from_source_bar.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/shared/local_flags.dart';
import 'package:flutter_app/state/activity_notifier.dart';
import 'package:flutter_app/state/documents_notifier.dart';
import 'package:flutter_app/state/tags_notifier.dart';
import 'package:flutter_app/state/upload_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/file_uploader.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

import 'sources_harness.dart';

const _phone = Size(390, 844);

class _Refuse implements HttpClientAdapter {
  final List<RequestOptions> sent = [];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    sent.add(options);
    return ResponseBody.fromString(
      jsonEncode({
        'error': 'An import for this document is already in progress.',
        'error_code': 'CONFLICT',
      }),
      409,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Document _cloudDoc() => Document.fromJson('doc-1', {
  'user_id': 'u1',
  'title': 'Board deck',
  'type': 'pptx',
  'status': 'complete',
  'gcs_path': 'raw/u1/cloud/google_drive/j1_deck.pptx',
  'source_integration': {'provider': 'google_drive', 'job_id': 'j1'},
});

/// No edited passage and no study program: the update needs no confirm.
class _Plain extends FirestoreService {
  _Plain() : super.stub();
  @override
  Future<(Document, List<Chunk>)?> getReaderDocumentQuietly(
    String docId,
  ) async => (
    _cloudDoc(),
    [
      Chunk.fromJson({
        'chunk_id': 'c1',
        'document_id': docId,
        'chunk_index': 0,
        'text': 'A passage.',
      }),
    ],
  );

  @override
  Stream<List<StudyProgram>> subscribeStudyPrograms() =>
      Stream.value(const []);
}

/// The nearest scroller's viewport and [f]'s rect: [f] is in view when it
/// lies inside it.
bool _inView(WidgetTester tester, Finder f) {
  final scroller = find
      .ancestor(of: f, matching: find.byType(Scrollable))
      .first;
  final view = tester.getRect(scroller);
  final r = tester.getRect(f);
  return r.top >= view.top - 0.5 && r.bottom <= view.bottom + 0.5;
}

ScrollPosition _position(WidgetTester tester, Finder inside) => tester
    .state<ScrollableState>(
      find.ancestor(of: inside, matching: find.byType(Scrollable)).first,
    )
    .position;

/// [f] at the FOOT of its scroller (a phone's last visible line, above the
/// tab bar), so whatever draws under it starts below the edge.
Future<void> _toFoot(WidgetTester tester, Finder f) async {
  await Scrollable.ensureVisible(tester.element(f), alignment: 1.0);
  await tester.pump();
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// What adding answered at the foot of a tall page, under a host that can
/// move it to another parent (a remount, as the Library's empty catalogue and
/// its slot do).
class _Foot extends StatefulWidget {
  const _Foot({super.key});
  @override
  State<_Foot> createState() => _FootState();
}

class _FootState extends State<_Foot> {
  bool moved = false;
  void move() => setState(() => moved = !moved);

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 1600, child: Placeholder()),
        if (moved)
          const Padding(padding: EdgeInsets.zero, child: AddAnswered())
        else
          const AddAnswered(),
        const SizedBox(height: 600),
      ],
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalFlags.resetForTest();
    KitPageTools.instance.reset();
    ApiService.instance.tokenProvider = () async => 'test-token';
  });
  tearDown(() {
    ApiService.instance.resetTestSeams();
    FirestoreService.resetInstance();
  });

  testWidgets('Add a source on a 390 phone, with shelves: a refused link\'s '
      'row comes into view', (tester) async {
    final docs = StreamController<List<Document>>.broadcast();
    addTearDown(docs.close);
    final upload = UploadNotifier();
    FirestoreService.instance = SourcesStubService(documents: docs.stream);
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<DocumentsNotifier>(
            create: (_) => DocumentsNotifier(),
          ),
          ChangeNotifierProvider<TagsNotifier>(
            create: (_) => StubTags(const [
              Tag(id: 's1', userId: 'u1', title: 'Reading list'),
              Tag(id: 's2', userId: 'u1', title: 'Finance'),
              Tag(id: 's3', userId: 'u1', title: 'Theology'),
            ]),
          ),
          ChangeNotifierProvider<ActivityNotifier>(
            create: (_) => StubActivity(),
          ),
          ChangeNotifierProvider<UploadNotifier>.value(value: upload),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: AddSourcePage()),
        ),
      ),
    );
    docs.add(const []);
    await _frames(tester);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    final button = find.widgetWithText(KitButton, 'Add link');
    await _toFoot(tester, button);
    await _frames(tester);
    await tester.enterText(find.byType(TextField).first, 'not a link');
    // The caret's own scroll settles first: a scroller mid-animation takes
    // no tap.
    await _frames(tester);
    final before = _position(tester, button).pixels;
    expect(_inView(tester, button), isTrue);
    await tester.tap(button);
    await _frames(tester);

    final row = find.byType(KitRefusedNotices);
    expect(row, findsOneWidget);
    expect(_position(tester, row).pixels, greaterThan(before));
    expect(_inView(tester, row), isTrue,
        reason: 'the row the Shelves block pushed below the fold is brought '
            'into view when it arrives');
  });

  testWidgets('once per arrival: a remount never scrolls back to an old '
      'refusal; a new one does', (tester) async {
    final upload = UploadNotifier();
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final host = GlobalKey<_FootState>();
    await tester.pumpWidget(
      ChangeNotifierProvider<UploadNotifier>.value(
        value: upload,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: _Foot(key: host)),
        ),
      ),
    );
    await _frames(tester);
    final scroller = find.byType(Scrollable).first;
    expect(tester.state<ScrollableState>(scroller).position.pixels, 0);

    upload.refuse('notes.xyz', 'NoteLetter cannot read .xyz files.');
    await _frames(tester);
    final row = find.byType(KitRefusedNotices);
    expect(_inView(tester, row), isTrue, reason: 'it arrived: into view');

    // The reader scrolls away; the row moves to another parent (a remount).
    tester.state<ScrollableState>(scroller).position.jumpTo(0);
    await tester.pump();
    host.currentState!.move();
    await _frames(tester);
    expect(find.byType(KitRefusedNotices), findsOneWidget);
    expect(
      tester.state<ScrollableState>(scroller).position.pixels,
      0,
      reason: 'a remount is not an arrival: nobody just made this refusal',
    );

    // A new refusal is a new arrival.
    upload.refuse('clip.abc', 'NoteLetter cannot read .abc files.');
    await _frames(tester);
    expect(_inView(tester, find.byType(KitRefusedNotices)), isTrue);
  });

  testWidgets('onboarding\'s panel: the door\'s own refusal comes into view',
      (tester) async {
    final upload = UploadNotifier();
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<UploadNotifier>.value(
        value: upload,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: 560),
                  FileUploader(),
                  SizedBox(height: 600),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await _frames(tester);
    final button = find.widgetWithText(KitButton, 'Add link');
    await _toFoot(tester, button);
    await _frames(tester);
    await tester.enterText(find.byType(TextField).first, 'not a link');
    // The caret's own scroll settles first: a scroller mid-animation takes
    // no tap.
    await _frames(tester);
    final before = _position(tester, button).pixels;
    expect(_inView(tester, button), isTrue);
    await tester.tap(button);
    await _frames(tester);
    final line = find.byType(KitFailureInline);
    expect(line, findsOneWidget);
    expect(_position(tester, line).pixels, greaterThan(before));
    expect(_inView(tester, line), isTrue,
        reason: 'the line under the link row was below the scroller\'s edge');
  });

  testWidgets('the reader: Update from Google Drive\'s refusal, under a bar '
      'at the scroller\'s foot, comes into view', (tester) async {
    final api = _Refuse();
    ApiService.instance.httpClientAdapter = api;
    FirestoreService.instance = _Plain();
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 1200),
                UpdateFromSourceBar(docId: 'doc-1', doc: _cloudDoc()),
                const SizedBox(height: 400),
              ],
            ),
          ),
        ),
      ),
    );
    await _frames(tester);
    final button = find.widgetWithText(KitButton, 'Update from Google Drive');
    await _toFoot(tester, button);
    await _frames(tester);
    expect(_inView(tester, button), isTrue, reason: 'the bar is at the foot');
    final before = _position(tester, button).pixels;
    await tester.tap(button);
    await _frames(tester);
    expect(api.sent, hasLength(1));
    final line = find.byType(KitFailureInline);
    expect(line, findsOneWidget);
    expect(find.textContaining('already in progress'), findsOneWidget);
    expect(_position(tester, line).pixels, greaterThan(before));
    expect(_inView(tester, line), isTrue,
        reason: 'the line under the bar was below the scroller\'s edge');
  });
}
