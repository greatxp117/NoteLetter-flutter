/// F-54 — what the reference draws under the Library's chapter opening and
/// in its two sections (web `LibraryHome.jsx`, `shared/OnboardingChecklist
/// .jsx`): the setup checklist strip, the search field row with Add a source,
/// and the list / shelf and shelf / card toggles.
///
/// Each case is a clause of the reference: the checklist's steps come from
/// live data plus ONE client-local flag, Hide and the disclosure are written
/// per viewer before anything moves, a completed or hidden checklist is gone,
/// and each toggle is kept under the reference's own key.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/newsletter.dart';
import 'package:flutter_app/models/newsletter_settings.dart';
import 'package:flutter_app/models/tag.dart';
import 'package:flutter_app/pages/library_page.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/shared/local_flags.dart';
import 'package:flutter_app/state/documents_notifier.dart';
import 'package:flutter_app/state/newsletter_notifier.dart';
import 'package:flutter_app/state/settings_notifier.dart';
import 'package:flutter_app/state/tags_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

class _Reads extends FirestoreService {
  _Reads({this.shelved = true}) : super.stub();
  final bool shelved;

  @override
  String? get currentUid => 'u1';

  @override
  Future<List<Newsletter>> listAllNewsletters({int limit = 30}) async =>
      const [];

  @override
  Stream<List<Document>> subscribeDocuments({int limit = 200}) =>
      Stream.value([
        for (var i = 0; i < 3; i++)
          Document(
              id: 'd$i',
              userId: 'u1',
              title: 'Volume $i',
              type: 'pdf',
              status: DocumentStatus.complete,
              createdAt: 1757000000000 - i,
              chunkCount: 3,
              tagIds: shelved && i == 0 ? const ['t1'] : const []),
      ]);

  @override
  Stream<List<Tag>> subscribeTags() => Stream.value(const [
        Tag(id: 't1', userId: 'u1', title: 'Finance', color: 'sage-500'),
      ]);
}

class _Settings extends SettingsNotifier {
  _Settings(this.value);
  final NewsletterSettings? value;
  @override
  Future<void> loadAll() async {}
  @override
  NewsletterSettings? get newsletter => value;
}

Future<void> _pump(WidgetTester tester,
    {bool shelved = true, NewsletterSettings? settings}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  FirestoreService.instance = _Reads(shelved: shelved);
  final letters = NewsletterNotifier();
  await letters.load();
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => DocumentsNotifier()),
      ChangeNotifierProvider(create: (_) => TagsNotifier()),
      ChangeNotifierProvider<NewsletterNotifier>.value(value: letters),
      ChangeNotifierProvider<SettingsNotifier>(
          create: (_) => _Settings(settings)),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(body: LibraryPage()),
    ),
  ));
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
}

Finder _named(String label) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.label == label);

void _reset() {
  LocalFlags.resetForTest();
  LocalFlags.recentView.value = 'shelf';
  LocalFlags.shelvesView.value = 'shelf';
  LocalFlags.onboardDismissed.value = false;
  LocalFlags.onboardExpanded.value = null;
  LocalFlags.onboardAsked.value = false;
}

void main() {
  setUp(_reset);
  tearDown(FirestoreService.resetInstance);

  group('the setup checklist', () {
    testWidgets('steps from live data: 4 of 5, the question the one left',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pump(tester, settings: const NewsletterSettings());
      expect(find.byType(KitSetupChecklist), findsOneWidget);
      expect(find.text('4 of 5 set up'), findsOneWidget);
      expect(find.text('Ask your library a question'), findsOneWidget,
          reason: 'the closed strip lists the remaining step as a pill');
      expect(find.text('Add your first source'), findsNothing);
    });

    testWidgets('no settings doc and no shelved volume are two open steps',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pump(tester, shelved: false);
      expect(find.text('2 of 5 set up'), findsOneWidget);
      expect(find.text('File a volume onto a shelf'), findsOneWidget);
      expect(find.text('Set up your daily letter'), findsOneWidget);
    });

    testWidgets('a first question asked completes it, and it is gone',
        (tester) async {
      SharedPreferences.setMockInitialValues({'nl-onboard-asked': true});
      await _pump(tester, settings: const NewsletterSettings());
      expect(find.byType(KitSetupChecklist), findsNothing);
    });

    testWidgets('Hide is written under nl-onboard-dismissed, then it goes',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pump(tester, settings: const NewsletterSettings());
      await tester.tap(_named('Hide setup checklist'));
      await tester.pump();
      await tester.pump();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('nl-onboard-dismissed'), isTrue);
      expect(find.byType(KitSetupChecklist), findsNothing);
    });

    testWidgets('opening it shows every step, the done ones crossed off',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pump(tester, settings: const NewsletterSettings());
      await tester.tap(find.text('4 of 5 set up'));
      await tester.pump();
      await tester.pump();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('nl-onboard-expanded'), isTrue);
      expect(find.text('Create your account'), findsOneWidget);
      expect(find.text('Add your first source'), findsOneWidget);
    });
  });

  testWidgets('the search field and Add a source replace the header actions',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester, settings: const NewsletterSettings());
    expect(find.byType(KitLibraryActions), findsOneWidget);
    expect(find.text('Search your library by meaning…'), findsOneWidget);
    expect(find.text('Add a source'), findsOneWidget);
    expect(find.widgetWithText(KitButton, 'Search'), findsNothing,
        reason: 'the ghost Search in the actions slot is gone');
  });

  group('the toggles', () {
    testWidgets('Recently read is a shelf by default, a list on pick',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pump(tester, settings: const NewsletterSettings());
      expect(find.byType(KitShelfView), findsOneWidget);
      await tester.tap(_named('List view'));
      await tester.pump();
      await tester.pump();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('nl-recent-view'), 'list');
      expect(find.byType(KitShelfView), findsNothing);
      expect(find.text('Volume 0'), findsWidgets);
    });

    testWidgets('Shelves are ledges by default, cards on pick', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pump(tester, settings: const NewsletterSettings());
      // The named ledge: plate, serif name, mono count.
      expect(find.text('1 volume · 3 passages'), findsOneWidget);
      expect(find.byType(KitShelfCard), findsNothing);
      await tester.tap(_named('Card view'));
      await tester.pump();
      await tester.pump();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('nl-shelves-view'), 'card');
      expect(find.byType(KitShelfCard), findsOneWidget);
    });
  });
}
