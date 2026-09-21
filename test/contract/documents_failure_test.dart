import 'dart:async';

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/newsletter.dart';
import 'package:flutter_app/models/tag.dart';
import 'package:flutter_app/models/activity_item.dart';
import 'package:flutter_app/pages/library_page.dart';
import 'package:flutter_app/pages/sources_page.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/state/activity_notifier.dart';
import 'package:flutter_app/state/cloud_notifier.dart';
import 'package:flutter_app/state/documents_notifier.dart';
import 'package:flutter_app/state/org_notifier.dart';
import 'package:flutter_app/state/upload_notifier.dart';
import 'package:flutter_app/state/newsletter_notifier.dart';
import 'package:flutter_app/state/tags_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

/// **C2 — the documents subscription is what every figure on two screens is
/// derived from, and neither screen read its error.**
///
/// `DocumentsNotifier` has carried `error` since F-08 (INV-24, ADR-071) and
/// exactly three surfaces read it: Tags, Shelf and the wizard. Library and
/// Sources branched on `loading`, then on `isEmpty` — and `isEmpty` is true of
/// a subscription that FAILED exactly as it is of a library with nothing in
/// it. So a reader whose rules or index had failed was shown §7: an offer to
/// add their first source, on an account full of them.
///
/// Sources was worse than Library, because it does not merely omit the notice
/// — it asserts the opposite: `0 volumes` in the folio and "Nothing indexed
/// yet" in the standfirst, both derived from an unread subscription. **Unread
/// is not zero** (§8, ADR-109), and 0 stays drawable for a library that really
/// is empty, which is why the fix suppresses the figure rather than zeroing it.
///
/// Driven through C1's seam: the REAL `DocumentsNotifier` runs, against a
/// stream that fails on command. A stub notifier would assert the stub.

class _StubService extends FirestoreService {
  _StubService(this.documents) : super.stub();

  final Stream<List<Document>> documents;

  /// How many times the notifier has SUBSCRIBED. Asserting that the error
  /// clears is not enough and was wrong here first: the old subscription is
  /// still live on the same stream, so a later value clears the error whether
  /// or not Retry re-subscribed, and the test passed with `_sub` kept.
  int subscribed = 0;

  @override
  String? get currentUid => 'u1';

  @override
  Stream<List<Document>> subscribeDocuments({int limit = 200}) {
    subscribed++;
    return documents;
  }

  @override
  Stream<List<Tag>> subscribeTags() => Stream.value(const []);
}

class _StubTags extends TagsNotifier {
  @override
  void start() {}
  @override
  List<Tag> get tags => const [];
}

class _StubLetters extends NewsletterNotifier {
  @override
  Future<void> load({int limit = 30}) async {}
  @override
  Newsletter? get latest => null;
}

Document _doc(String id) => Document(
      id: id,
      userId: 'u1',
      title: 'A volume',
      type: 'pdf',
      status: DocumentStatus.complete,
      createdAt: 1757000000000,
      chunkCount: 12,
    );

/// The double the pumps install, so a test can ask how many times the
/// notifier SUBSCRIBED — the only question that distinguishes a Retry that
/// re-subscribed from a live subscription that simply carried on.
late _StubService _stub;

Future<DocumentsNotifier> _pumpLibrary(
    WidgetTester tester, Stream<List<Document>> source) async {
  _stub = _StubService(source);
  FirestoreService.instance = _stub;
  final docs = DocumentsNotifier();
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<DocumentsNotifier>.value(value: docs),
      ChangeNotifierProvider<TagsNotifier>(create: (_) => _StubTags()),
      ChangeNotifierProvider<NewsletterNotifier>(create: (_) => _StubLetters()),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(body: LibraryPage()),
    ),
  ));
  await tester.pump();   // lets the post-frame `start()` run
  await tester.pump();
  return docs;
}

class _StubCloud extends CloudNotifier {
  @override
  void start() {}
  @override
  Future<void> loadIntegrations() async {}
}

class _StubOrg extends OrgNotifier {
  @override
  void start() {}
}

class _StubActivity extends ActivityNotifier {
  @override
  void start({int limit = 100}) {}
  @override
  List<ActivityItem> get items => const [];
}

/// Sources mounts `BrowseSection`, so the two are pumped together — which is
/// also what proves there is ONE notice for one failure and not two.
Future<DocumentsNotifier> _pumpSources(
    WidgetTester tester, Stream<List<Document>> source) async {
  _stub = _StubService(source);
  FirestoreService.instance = _stub;
  final docs = DocumentsNotifier();
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<DocumentsNotifier>.value(value: docs),
      ChangeNotifierProvider<TagsNotifier>(create: (_) => _StubTags()),
      ChangeNotifierProvider<CloudNotifier>(create: (_) => _StubCloud()),
      ChangeNotifierProvider<OrgNotifier>(create: (_) => _StubOrg()),
      ChangeNotifierProvider<ActivityNotifier>(create: (_) => _StubActivity()),
      ChangeNotifierProvider<UploadNotifier>(create: (_) => UploadNotifier()),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(body: SourcesPage()),
    ),
  ));
  await tester.pump();
  await tester.pump();
  return docs;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(FirestoreService.resetInstance);

  testWidgets('Library — a failed subscription draws §14, never §7',
      (tester) async {
    final source = StreamController<List<Document>>.broadcast();
    await _pumpLibrary(tester, source.stream);

    source.addError(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(KitFailureBlock), findsOneWidget);
    expect(find.byType(KitDropZone), findsNothing,
        reason: '§7 here is the drop zone — an offer to add a first source — on an account that '
            'may be full of them');
    expect(find.textContaining('Sign out and back in'), findsOneWidget,
        reason: 'C7 — the SDK\'s bracketed code is not a sentence, and the '
            'mapped one still proves the rejection reached the slot');
  });

  testWidgets('Library — §7 still speaks for a library that really is empty',
      (tester) async {
    final source = StreamController<List<Document>>.broadcast();
    await _pumpLibrary(tester, source.stream);

    source.add(const []);
    await tester.pump();
    await tester.pump();

    expect(find.byType(KitDropZone), findsOneWidget,
        reason: 'an empty library is a real measurement and keeps its offer');
    expect(find.byType(KitFailureBlock), findsNothing);
  });

  testWidgets('Library — what loaded before the failure is KEPT, below it',
      (tester) async {
    final source = StreamController<List<Document>>.broadcast();
    await _pumpLibrary(tester, source.stream);

    source.add([_doc('d1')]);
    await tester.pump();
    await tester.pump();
    expect(find.byType(KitFailureBlock), findsNothing);

    source.addError(StateError('unavailable'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(KitFailureBlock), findsOneWidget,
        reason: 'a library that loaded once and then failed is no longer the '
            'whole library, which is what the block says');
    expect(find.byType(KitDropZone), findsNothing);
  });

  testWidgets('Retry re-subscribes — `start` is idempotent on `_sub`',
      (tester) async {
    final source = StreamController<List<Document>>.broadcast();
    final docs = await _pumpLibrary(tester, source.stream);
    expect(_stub.subscribed, 1);

    source.addError(StateError('unavailable'));
    await tester.pump();
    await tester.pump();
    expect(docs.error, isNotNull);

    await tester.tap(find.text('Try again'));
    await tester.pump();

    expect(_stub.subscribed, 2,
        reason: 'a Retry that cannot re-subscribe is a control that lies — '
            'and `start` is idempotent on `_sub`, so it only re-subscribes '
            'because the error path dropped it');
  });

  testWidgets('Sources — a failed subscription draws no FIGURE, and one notice',
      (tester) async {
    final source = StreamController<List<Document>>.broadcast();
    final docs = await _pumpSources(tester, source.stream);
    expect(_stub.subscribed, 1, reason: 'the page never started the notifier');

    source.addError(StateError('permission-denied'));
    await tester.pump();
    await tester.pump();
    expect(docs.error, isNotNull, reason: 'the error never reached it');

    // Unread is not zero (§8, ADR-109). This is the sentence that matters:
    // it is not a missing notice but the opposite one, told to a reader whose
    // library may be full.
    // BOTH figure sites, not one: the folio and `BrowseSection`'s section
    // header are derived from the same subscription, and fixing the header
    // alone would have left "In your library · 0 volumes" beside a block
    // saying the library could not be read (ADR-084's lesson — a figure
    // booked as one copy was five).
    expect(
        find.byWidgetPredicate((w) =>
            w is Text && (w.data ?? '').toLowerCase().contains('0 volumes')),
        findsNothing);
    expect(find.textContaining('Nothing indexed yet'), findsNothing);

    // One failure, one notice — `BrowseSection` is mounted inside this page
    // and suppresses its own §7 rather than drawing a second block.
    expect(find.byType(KitFailureBlock), findsOneWidget);
    // §7 on this screen is `_NothingYet`, not the drop zone: the drop zone is
    // the permanent ADD control and is right to stay. The offer that must not
    // speak is the one that asserts the library is empty.
    expect(find.textContaining('Nothing here yet'), findsNothing);
  });

  testWidgets('Sources — 0 volumes stays drawable when it is MEASURED',
      (tester) async {
    final source = StreamController<List<Document>>.broadcast();
    await _pumpSources(tester, source.stream);

    source.add(const []);
    await tester.pump();
    await tester.pump();

    expect(
        find.byWidgetPredicate((w) =>
            w is Text && (w.data ?? '').toLowerCase().contains('0 volumes')),
        findsNWidgets(2),
        reason: 'an empty library is a real measurement — ADR-109 keeps 0 '
            'drawable at BOTH sites, it only refuses an UNREAD figure');
    expect(find.byType(KitFailureBlock), findsNothing);
  });
}
