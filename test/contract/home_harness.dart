// The harness Home's tests share (F-141, screens/library.md §Composition,
// direction D): the REAL notifiers over a FirestoreService double, a settings
// notifier that answers what the test says, and the shell's one inbox over
// streams the test hands it. Not a test file itself.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/models/background_task.dart';
import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/import_job.dart';
import 'package:flutter_app/models/newsletter.dart';
import 'package:flutter_app/models/newsletter_settings.dart';
import 'package:flutter_app/models/organization_suggestion.dart';
import 'package:flutter_app/models/study.dart';
import 'package:flutter_app/models/tag.dart';
import 'package:flutter_app/pages/library_page.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/state/documents_notifier.dart';
import 'package:flutter_app/state/newsletter_notifier.dart';
import 'package:flutter_app/state/review_inbox.dart';
import 'package:flutter_app/state/settings_notifier.dart';
import 'package:flutter_app/state/tags_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';

/// Every read Home makes, answered by the test. [docsStream] overrides
/// [docs] (a stream the test drives); [hangLetters] is a letters read that
/// never answers; [sessions] null is a study read that never answers.
class HomeReads extends FirestoreService {
  HomeReads({
    this.docs = const [],
    this.tags = const [],
    this.letters = const [],
    this.sessions = const [],
    this.docsStream,
    this.failLetters = false,
    this.hangLetters = false,
    this.failTags = false,
  }) : super.stub();

  final List<Document> docs;
  final List<Tag> tags;
  final List<Newsletter> letters;
  final List<StudySession>? sessions;
  final Stream<List<Document>>? docsStream;
  final bool failLetters;
  final bool hangLetters;
  final bool failTags;

  /// How many times the documents notifier SUBSCRIBED.
  int subscribed = 0;

  @override
  String? get currentUid => 'u1';

  @override
  Future<List<Newsletter>> listAllNewsletters({int limit = 30}) async {
    if (hangLetters) return Completer<List<Newsletter>>().future;
    if (failLetters) throw StateError('permission-denied');
    return letters;
  }

  @override
  Stream<List<Document>> subscribeDocuments({int limit = 200}) {
    subscribed++;
    return docsStream ?? Stream.value(docs);
  }

  @override
  Stream<List<Tag>> subscribeTags() => failTags
      ? Stream.error(StateError('permission-denied'))
      : Stream.value(tags);

  @override
  Stream<List<StudySession>> subscribeStudySessions({
    String? programId,
    int limit = 30,
  }) => sessions == null
      ? const Stream.empty()
      : Stream.value(sessions!.take(limit).toList());
}

/// The settings document as the test says it is: [value] null and [failed]
/// false is a read still out; [failed] is a refused read.
class HomeSettings extends SettingsNotifier {
  HomeSettings(this.value, {this.failed = false});
  final NewsletterSettings? value;
  final bool failed;
  int loads = 0;

  @override
  Future<void> loadAll() async => loads++;

  @override
  NewsletterSettings? get newsletter => value;

  @override
  String? get error => failed ? 'Could not load newsletter settings.' : null;
}

/// The shell's one inbox over fixed lists — all four answered.
ReviewInbox homeInbox({
  List<Document> sources = const [],
  List<ImportJob> holds = const [],
  List<OrganizationSuggestion> suggestions = const [],
  List<BackgroundTask> tasks = const [],
  bool fail = false,
}) => ReviewInbox(
  docs: () => fail
      ? Stream<List<Document>>.error(StateError('permission-denied'))
      : Stream.value(sources),
  holds: () => Stream.value(holds),
  suggestions: () => Stream.value(suggestions),
  tasks: () => Stream.value(tasks),
);

Document homeDoc(
  String id, {
  String title = 'A volume',
  String type = 'pdf',
  DocumentStatus status = DocumentStatus.complete,
  int? chunks = 3,
  int views = 1,
  List<String> tags = const [],
  int? created,
  String? author,
  String? stage,
}) => Document(
  id: id,
  userId: 'u1',
  title: title,
  type: type,
  status: status,
  createdAt: created ?? DateTime(2026, 10, 20).millisecondsSinceEpoch,
  chunkCount: chunks,
  viewCount: views,
  tagIds: tags,
  author: author,
  processingStage: stage,
);

Newsletter homeLetter(String id, Map<String, dynamic> json) =>
    Newsletter.fromJson(id, {'user_id': 'u1', ...json});

/// Pumps Home under the providers the app holds it under, at [size], in
/// [brightness], then a bounded run of frames (a live shimmer or stage bar
/// never settles). [inbox] null is a shell with no inbox (unmeasured).
Future<void> pumpHome(
  WidgetTester tester,
  HomeReads reads, {
  HomeSettings? settings,
  ReviewInbox? inbox,
  Size size = const Size(1280, 2400),
  Brightness brightness = Brightness.light,
  bool preloadLetters = true,
  Widget Function(Widget page)? wrap,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  FirestoreService.instance = reads;
  addTearDown(FirestoreService.resetInstance);
  final letters = NewsletterNotifier();
  if (preloadLetters && !reads.hangLetters) {
    try {
      await letters.load();
    } catch (_) {}
  }
  const page = Scaffold(body: LibraryPage());
  // A fresh tree: providers' `create` runs again, the page's state is new.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DocumentsNotifier()),
        ChangeNotifierProvider(create: (_) => TagsNotifier()),
        ChangeNotifierProvider<NewsletterNotifier>.value(value: letters),
        ChangeNotifierProvider<SettingsNotifier>(
          create: (_) => settings ?? HomeSettings(null),
        ),
        if (inbox != null)
          ChangeNotifierProvider<ReviewInbox>(create: (_) => inbox),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
        home: wrap == null ? page : wrap(page),
      ),
    ),
  );
  await pumpFrames(tester);
}

/// A bounded run of frames — never `pumpAndSettle` over a live animation.
Future<void> pumpFrames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The bundled faces, so widths are the real type's.
Future<void> loadHomeFonts() async {
  const faces = {
    'Geist': [
      'Geist-Light.ttf',
      'Geist-Regular.ttf',
      'Geist-Medium.ttf',
      'Geist-SemiBold.ttf',
      'Geist-Bold.ttf',
    ],
    'Geist Mono': ['GeistMono-Regular.ttf', 'GeistMono-Medium.ttf'],
    'Source Serif 4': [
      'SourceSerif4-Variable.ttf',
      'SourceSerif4-Italic-Variable.ttf',
    ],
  };
  for (final e in faces.entries) {
    final loader = FontLoader(e.key);
    for (final f in e.value) {
      loader.addFont(rootBundle.load('assets/fonts/$f'));
    }
    await loader.load();
  }
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}
