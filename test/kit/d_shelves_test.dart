// F-143 — Shelves, a shelf and the shelf map in direction D
// (screens/library.md §Composition — Shelves and a shelf, §The shelf map's
// Composition; kit §26–§32, §42; web pages/ShelvesView.jsx, map/MapView.jsx).
//
// Real notifiers over a stubbed FirestoreService, in both themes, at a phone
// (402) and a wide (1280) window: the frames' parts in order, the sheet's
// shelf rows and their running head, the figures that wait for both reads,
// the shelf's settings in the panel and its delete as the sheet's last Also,
// and *Go to a shelf* re-centring the map already drawn.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/newsletter.dart';
import 'package:flutter_app/models/newsletter_settings.dart';
import 'package:flutter_app/models/tag.dart';
import 'package:flutter_app/pages/tags/shelf_map_page.dart';
import 'package:flutter_app/pages/tags/shelf_page.dart';
import 'package:flutter_app/pages/tags_page.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/shared/local_flags.dart';
import 'package:flutter_app/state/documents_notifier.dart';
import 'package:flutter_app/state/newsletter_notifier.dart';
import 'package:flutter_app/state/settings_notifier.dart';
import 'package:flutter_app/state/tags_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

final _shelves = [
  Tag.fromJson('cook', {
    'user_id': 'u1',
    'title': 'Recipes',
    'color': 'brick-500',
    'description': 'Cooking, recipes and kitchen technique',
  }),
  Tag.fromJson('bake', {
    'user_id': 'u1',
    'title': 'Baking',
    'color': 'ochre-500',
    'parent_tag_id': 'cook',
  }),
  Tag.fromJson('story', {
    'user_id': 'u1',
    'title': 'Stories',
    'color': 'teal-500',
    'source': 'auto_created',
  }),
];

Document _doc(String id, String title, List<String> tags, {int day = 1}) =>
    Document(
      id: id,
      userId: 'u1',
      title: title,
      type: 'pdf',
      status: DocumentStatus.complete,
      createdAt: DateTime(2026, 7, day).millisecondsSinceEpoch,
      chunkCount: 3,
      tagIds: tags,
    );

final _docs = [
  _doc('d-pasta', 'Pasta Fundamentals', ['cook'], day: 5),
  _doc('d-bread', 'Bread at Home', ['bake'], day: 2),
  _doc('d-dragon', 'Dragon Story', ['story'], day: 3),
  _doc('d-loose', 'Loose Notes', const [], day: 4),
];

class _Reads extends FirestoreService {
  _Reads({this.shelves, this.tagsError}) : super.stub();
  final List<Tag>? shelves;
  final Object? tagsError;
  @override
  String? get currentUid => 'u1';
  @override
  Future<List<Newsletter>> listAllNewsletters({int limit = 30}) async =>
      const [];
  @override
  Stream<List<Document>> subscribeDocuments({int limit = 200}) =>
      Stream.value(_docs);
  @override
  Stream<List<Tag>> subscribeTags() => tagsError != null
      ? Stream.error(tagsError!)
      : Stream.value(shelves ?? _shelves);
}

class _Settings extends SettingsNotifier {
  @override
  Future<void> loadAll() async {}
  @override
  NewsletterSettings? get newsletter =>
      const NewsletterSettings(enabled: true);
}

Future<void> _pump(
  WidgetTester tester,
  Widget page, {
  double width = 1280,
  double height = 2400,
  bool dark = false,
  _Reads? reads,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  FirestoreService.instance = reads ?? _Reads();
  final letters = NewsletterNotifier();
  await letters.load();
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => DocumentsNotifier()),
      ChangeNotifierProvider(create: (_) => TagsNotifier()),
      ChangeNotifierProvider<NewsletterNotifier>.value(value: letters),
      ChangeNotifierProvider<SettingsNotifier>(create: (_) => _Settings()),
    ],
    child: MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      home: Scaffold(body: page),
    ),
  ));
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
}

Finder _rich(String text) => find.text(text, findRichText: true);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalFlags.sourceView.value = 'list';
  });
  tearDown(FirestoreService.resetInstance);

  group('Shelves (/shelves)', () {
    for (final dark in [false, true]) {
      testWidgets('the frame: folio, title, standfirst, New shelf, the sheet '
          '(${dark ? 'dark' : 'light'})', (tester) async {
        await _pump(tester, const ShelvesPage(), dark: dark);
        expect(find.text('THE SHELVES · 3 SHELVES · 4 VOLUMES'),
            findsOneWidget);
        expect(find.text('Shelves'), findsOneWidget);
        expect(
            find.text('Group your volumes by subject, project, or year — each '
                'shelf can feed your letter on its own. 4 volumes, shelved.'),
            findsOneWidget);
        expect(KitPageTools.instance.action?.label, 'New shelf');
        expect(KitPageTools.instance.action?.short, 'New shelf');
        expect(KitPageTools.instance.settings, isNull,
            reason: 'Shelves has no settings');
        // The sheet: the top-level shelves, then Unshelved; never a
        // sub-shelf.
        for (final id in ['cook', 'story', '_un']) {
          expect(find.byKey(ValueKey('shelves-sheet-$id')), findsOneWidget);
        }
        expect(find.byKey(const ValueKey('shelves-sheet-bake')), findsNothing);
        expect(find.text('Suggest shelves'), findsOneWidget);
        expect(find.text('The shelf map'), findsOneWidget);
        // The column: On the shelves with its toggle, then §42's catalogue.
        expect(find.text('On the shelves'), findsOneWidget);
        expect(find.byType(KitViewToggle), findsOneWidget);
        expect(find.byType(KitShelfCatalogue), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a phone: the running head names the shelf in view, i of N; '
        'choosing a shelf moves the page and folds it', (tester) async {
      await _pump(tester, const ShelvesPage(), width: 402, height: 874);
      expect(find.byType(KitRunningHead), findsOneWidget);
      expect(_rich('1 of 3'), findsOneWidget);
      // Drop the sheet, choose Stories.
      await tester.tap(_rich('1 of 3'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.byKey(const ValueKey('shelves-sheet-story')));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(_rich('1 of 3'), findsNothing,
          reason: 'the page moved on from Recipes to the shelf chosen (or '
              'past it, at the end of the scroll)');
      expect(tester.takeException(), isNull);
    });

    testWidgets('while a read is out every figure is the dash and nothing is '
        'drawn as empty', (tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      FirestoreService.instance = _Reads();
      // No snapshot yet: the notifiers are never started.
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<DocumentsNotifier>(create: (_) => _Unread()),
          ChangeNotifierProvider<TagsNotifier>(create: (_) => _UnreadTags()),
          ChangeNotifierProvider<SettingsNotifier>(create: (_) => _Settings()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: ShelvesPage()),
        ),
      ));
      await tester.pump();
      expect(find.text('THE SHELVES · — SHELVES · — VOLUMES'),
          findsOneWidget);
      expect(find.text('No shelves yet'), findsNothing);
      expect(find.text('None yet.'), findsNothing);
      expect(find.byType(KitSkeletonLines), findsWidgets);
    });

    testWidgets('a refused read says so in the listing\'s place, never No '
        'shelves yet', (tester) async {
      await _pump(tester, const ShelvesPage(),
          reads: _Reads(tagsError: 'Missing or insufficient permissions.'));
      expect(find.textContaining('Your library could not be read'),
          findsOneWidget);
      expect(find.text('No shelves yet'), findsNothing);
      expect(find.text('THE SHELVES · — SHELVES · — VOLUMES'),
          findsOneWidget);
    });

    testWidgets('No shelves yet: the §37 empty state, its offers, and None yet '
        'in the sheet', (tester) async {
      await _pump(tester, const ShelvesPage(),
          reads: _Reads(shelves: const []));
      expect(find.text('No shelves yet'), findsOneWidget);
      expect(find.text('Make your first shelf'), findsOneWidget);
      expect(find.text('Have NoteLetter suggest shelves from your library'),
          findsOneWidget,
          reason: 'only with complete volumes — there are four');
      expect(find.text('None yet.'), findsOneWidget);
      expect(find.text('The shelf map'), findsNothing,
          reason: 'only with shelves');
    });
  });

  group('A shelf (/shelves/{id})', () {
    for (final dark in [false, true]) {
      testWidgets('the frame: crumb, folio, Ask this shelf, Shelf settings, '
          'the sheet in order (${dark ? 'dark' : 'light'})', (tester) async {
        await _pump(tester, const ShelfPage(shelfId: 'bake'), dark: dark);
        // The crumb: All shelves, then the ancestors, outermost first.
        expect(find.text('ALL SHELVES'), findsOneWidget);
        expect(find.text('RECIPES'), findsOneWidget);
        expect(find.text('SHELF · 1 VOLUME · 3 PASSAGES'),
            findsOneWidget);
        expect(find.text('Baking'), findsWidgets);
        expect(KitPageTools.instance.action?.label, 'Ask this shelf');
        expect(KitPageTools.instance.action?.short, 'Ask shelf');
        expect(KitPageTools.instance.settings?.label, 'Shelf settings');
        // The sheet: the mark, Order, Sub-shelves, The shelf, Also — in
        // that order down the card.
        final order = [
          find.byKey(const ValueKey('shelf-identity')),
          find.text('ORDER'),
          find.text('SUB-SHELVES'),
          find.text('THE SHELF'),
          find.text('ALSO'),
        ];
        for (var i = 1; i < order.length; i++) {
          expect(tester.getTopLeft(order[i]).dy,
              greaterThan(tester.getTopLeft(order[i - 1]).dy));
        }
        expect(find.text('New sub-shelf'), findsOneWidget);
        // Delete shelf is the last Also.
        final also = ['See on map', 'Find sources for this shelf', 'Delete shelf'];
        for (var i = 1; i < also.length; i++) {
          expect(tester.getTopLeft(find.text(also[i])).dy,
              greaterThan(tester.getTopLeft(find.text(also[i - 1])).dy));
        }
        expect(find.text('The volumes'), findsOneWidget);
        expect(find.text('Bread at Home'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('auto-created reads in the folio and the mark', (tester) async {
      await _pump(tester, const ShelfPage(shelfId: 'story'));
      expect(find.text('SHELF · AUTO-CREATED · 1 VOLUME · 3 '
              'PASSAGES'),
          findsOneWidget);
      expect(find.text('SHELF · AUTO-CREATED'), findsOneWidget,
          reason: 'the mark\'s kicker');
    });

    testWidgets('the subtree is the page: Recipes counts Baking\'s volume, '
        'and Order re-sorts it', (tester) async {
      await _pump(tester, const ShelfPage(shelfId: 'cook'));
      expect(find.text('SHELF · 2 VOLUMES · 6 PASSAGES'),
          findsOneWidget);
      double y(String t) => tester.getTopLeft(find.text(t)).dy;
      // Recent first: Pasta (Jul 5) above Bread (Jul 2).
      expect(y('Pasta Fundamentals'), lessThan(y('Bread at Home')));
      await tester.tap(find.text('A–Z'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(y('Bread at Home'), lessThan(y('Pasta Fundamentals')),
          reason: 'A–Z files Bread under B, before Pasta under P');
      // The sub-shelf row carries its rolled-up count and opens nothing here.
      expect(find.byKey(const ValueKey('sub-shelf-bake')), findsOneWidget);
    });

    testWidgets('Shelf settings: In your letter, then This shelf\'s stacked '
        'rows; no Delete in the panel', (tester) async {
      await _pump(tester, const ShelfPage(shelfId: 'bake'));
      expect(KitPageTools.instance.openSettings('letter'), isTrue);
      await tester.pump();
      // The panel's group label, and the sheet's figure of the same name.
      expect(find.text('IN YOUR LETTER'), findsNWidgets(2));
      expect(find.text('Feed today’s letter'), findsOneWidget);
      expect(find.text('HOW PROMINENTLY'), findsOneWidget);
      expect(find.text('THIS SHELF'), findsOneWidget);
      for (final label in ['NAME', 'COLOR', 'INSIDE']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('SPLIT'), findsNothing,
          reason: 'only at five volumes filed directly');
      expect(find.text('Delete shelf'), findsOneWidget,
          reason: 'the sheet\'s Also only — not a Danger row in the panel');
    });

    testWidgets('loading is the skeleton frame, never Shelf Not Found',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<DocumentsNotifier>(create: (_) => _Unread()),
          ChangeNotifierProvider<TagsNotifier>(create: (_) => _UnreadTags()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: ShelfPage(shelfId: 'cook')),
        ),
      ));
      await tester.pump();
      expect(find.text('Shelf Not Found'), findsNothing);
      expect(find.text('ALL SHELVES'), findsOneWidget);
      expect(find.text('SHELF'), findsOneWidget);
      expect(find.byType(KitSkeletonLines), findsWidgets);
    });

    testWidgets('a phone: the running head is the swatch, the name, the order '
        'and the count', (tester) async {
      await _pump(tester, const ShelfPage(shelfId: 'cook'),
          width: 402, height: 874);
      final head = find.byType(KitRunningHead);
      expect(head, findsOneWidget);
      final peek = tester.widget<KitLibPeek>(
          find.descendant(of: head, matching: find.byType(KitLibPeek)));
      expect(peek.title, 'Recipes');
      expect(peek.meta, 'Recent');
      expect(peek.count, '2');
      expect(peek.mark, isA<KitShelfSwatch>());
      expect(find.descendant(of: head, matching: find.text('RECENT')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('The shelf map (/shelves/map)', () {
    testWidgets('the frame, the figures, Go to a shelf in tree order; a pick '
        're-centres the map already drawn', (tester) async {
      await _pump(tester, const ShelfMapPage(), height: 1600);
      expect(find.text('ALL SHELVES'), findsOneWidget);
      expect(find.text('SHELF MAP · 3 SHELVES'), findsOneWidget);
      expect(find.text('The Shelf Map'), findsOneWidget);
      expect(KitPageTools.instance.action, isNull);
      expect(KitPageTools.instance.settings, isNull);
      expect(find.text('ON THE MAP'), findsOneWidget);
      expect(find.text('GO TO A SHELF'), findsOneWidget);
      // Tree order: Recipes, then Baking under it, then Stories.
      double y(String id) =>
          tester.getTopLeft(find.byKey(ValueKey('map-go-$id'))).dy;
      expect(y('cook'), lessThan(y('bake')));
      expect(y('bake'), lessThan(y('story')));
      int n() => tester
          .widget<KitRelationshipMap>(find.byType(KitRelationshipMap))
          .focusN;
      expect(n(), 0);
      await tester.tap(find.byKey(const ValueKey('map-go-story')));
      await tester.pump();
      expect(n(), 1);
      expect(
          tester
              .widget<KitRelationshipMap>(find.byType(KitRelationshipMap))
              .focusKey,
          'shelf:story');
      // The same shelf again centres it again.
      await tester.tap(find.byKey(const ValueKey('map-go-story')));
      await tester.pump();
      expect(n(), 2);
      expect(tester.takeException(), isNull);
    });
  });

  group('kit: the shelf row and the mark', () {
    testWidgets('the current row carries the dot; a facet\'s chosen row is '
        'inert; New sub-shelf has no swatch and no count', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: KitShelfRows(children: [
              KitShelfRow(
                  title: 'Recipes',
                  count: '2',
                  on: true,
                  chosenInert: true,
                  onTap: () => taps++),
              KitShelfRow(title: 'Baking', count: '1', sub: true, onTap: () {}),
              KitShelfRow.create(title: 'New sub-shelf', onTap: () {}),
            ]),
          ),
        ),
      ));
      await tester.tap(find.text('Recipes'));
      expect(taps, 0, reason: 'pressing the chosen facet row does nothing');
      expect(find.byType(KitShelfSwatch), findsNWidgets(2));
      final sub = tester.widget<Text>(find.text('Baking'));
      expect(sub.style?.fontStyle, FontStyle.italic);
    });

    testWidgets('the mark: four spines, 22 tall at most, 5 wide',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Center(child: KitShelfSpines(Colors.red)),
      ));
      final spines = find.descendant(
          of: find.byType(KitShelfSpines), matching: find.byType(Container));
      expect(spines, findsNWidgets(4));
      for (final e in spines.evaluate()) {
        final s = (e.renderObject! as RenderBox).size;
        expect(s.width, 5);
        expect(s.height, lessThanOrEqualTo(22));
      }
    });
  });
}

class _Unread extends DocumentsNotifier {
  @override
  void start() {}
}

class _UnreadTags extends TagsNotifier {
  @override
  void start() {}
}
