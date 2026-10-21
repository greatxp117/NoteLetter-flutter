// Nested shelves on the screens (contract 5.28.0, ADR-185, INV-33;
// library.md §Nested shelves): the index lists top-level shelves holding
// their subtree; a shelf page carries its breadcrumb, its Sub-shelves row,
// the subtree's volumes and an inherited letter mode said as inherited.
// The rule itself is test/contract/shelf_tree_test.dart's.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/newsletter.dart';
import 'package:flutter_app/models/newsletter_settings.dart';
import 'package:flutter_app/models/tag.dart';
import 'package:flutter_app/pages/tags/shelf_page.dart';
import 'package:flutter_app/pages/tags_page.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/state/documents_notifier.dart';
import 'package:flutter_app/state/newsletter_notifier.dart';
import 'package:flutter_app/state/settings_notifier.dart';
import 'package:flutter_app/state/tags_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';

final _shelves = [
  Tag.fromJson('cat', {'user_id': 'u1', 'title': 'Catholic', 'letter_mode': 'muted'}),
  Tag.fromJson('mary', {'user_id': 'u1', 'title': 'Mary', 'parent_tag_id': 'cat'}),
  Tag.fromJson('app', {'user_id': 'u1', 'title': 'Apparitions', 'parent_tag_id': 'mary'}),
  Tag.fromJson('kit', {'user_id': 'u1', 'title': 'Kitchen'}),
];

Document _doc(String id, List<String> tags) => Document(
    id: id,
    userId: 'u1',
    title: 'On $id',
    type: 'pdf',
    status: DocumentStatus.complete,
    createdAt: 1757000000000,
    chunkCount: 2,
    tagIds: tags);

class _Reads extends FirestoreService {
  _Reads() : super.stub();
  @override
  String? get currentUid => 'u1';
  @override
  Future<List<Newsletter>> listAllNewsletters({int limit = 30}) async =>
      const [];
  @override
  Stream<List<Document>> subscribeDocuments({int limit = 200}) =>
      Stream.value([
        _doc('d-cat', ['cat']),
        _doc('d-mary', ['mary']),
        _doc('d-app', ['app']),
        _doc('d-kit', ['kit']),
      ]);
  @override
  Stream<List<Tag>> subscribeTags() => Stream.value(_shelves);
}

class _Settings extends SettingsNotifier {
  @override
  Future<void> loadAll() async {}
  @override
  NewsletterSettings? get newsletter => const NewsletterSettings(enabled: true);
}

Future<void> _pump(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(1200, 3600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  FirestoreService.instance = _Reads();
  final letters = NewsletterNotifier();
  await letters.load();
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => DocumentsNotifier()),
      ChangeNotifierProvider(create: (_) => TagsNotifier()),
      ChangeNotifierProvider<NewsletterNotifier>.value(value: letters),
      ChangeNotifierProvider<SettingsNotifier>(create: (_) => _Settings()),
    ],
    child: MaterialApp(theme: AppTheme.light, home: Scaffold(body: page)),
  ));
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(FirestoreService.resetInstance);

  testWidgets('the index lists top-level shelves, each holding its subtree',
      (tester) async {
    await _pump(tester, const ShelvesPage());
    expect(find.text('Catholic'), findsOneWidget);
    expect(find.text('Kitchen'), findsOneWidget);
    expect(find.text('Mary'), findsNothing);
    expect(find.text('Apparitions'), findsNothing);
    // Catholic holds its own volume, Mary's and Apparitions': 3, once each.
    expect(find.textContaining('3 volumes · 6 passages · 1 sub-shelf'),
        findsOneWidget);
    expect(find.textContaining('1 volume · 2 passages'), findsOneWidget);
  });

  testWidgets('a sub-shelf page: breadcrumb, Sub-shelves, subtree volumes',
      (tester) async {
    await _pump(tester, const ShelfPage(shelfId: 'mary'));
    expect(find.text('Catholic'), findsOneWidget); // the crumb
    expect(find.text('›'), findsOneWidget);
    expect(find.text('SUB-SHELVES · 1'), findsOneWidget);
    expect(find.text('Apparitions'), findsOneWidget);
    expect(find.text('New sub-shelf'), findsOneWidget);
    expect(find.text('VOLUMES · 2'), findsOneWidget);
    expect(find.text('On d-app'), findsOneWidget);
    expect(find.text('On d-cat'), findsNothing); // the scope runs down
  });

  testWidgets('an inherited letter mode is said as inherited', (tester) async {
    await _pump(tester, const ShelfPage(shelfId: 'app'));
    expect(
        find.text('This shelf is muted — its passages stay out of your letter.'),
        findsOneWidget);
    expect(find.text('Muted by Catholic.'), findsOneWidget);
    // It has no mode of its own, so there is nothing to clear.
    expect(find.text('Use the parent’s setting'), findsNothing);
  });
}
