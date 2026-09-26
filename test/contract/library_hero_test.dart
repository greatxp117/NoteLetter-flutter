/// F-54, the Library hero's rule (web ef14f8a + 5d6fe8d): Today's letter is
/// the NEWEST daily record — any status, with or without a body — never a
/// readings letter, and its standfirst is the librarian's note by its
/// `data-nl-lede` marker, never a slice of the body. The seed's letter drew
/// no standfirst at all here: the hero sliced `html`, which a letterheaded
/// record does not carry.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/newsletter.dart';
import 'package:flutter_app/models/tag.dart';
import 'package:flutter_app/pages/library_page.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/state/documents_notifier.dart';
import 'package:flutter_app/state/newsletter_notifier.dart';
import 'package:flutter_app/state/tags_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

class _Reads extends FirestoreService {
  _Reads(this.letters, {this.fail = false}) : super.stub();
  final List<Newsletter> letters;
  final bool fail;

  @override
  String? get currentUid => 'u1';

  @override
  Future<List<Newsletter>> listAllNewsletters({int limit = 30}) async {
    if (fail) throw StateError('permission-denied');
    return letters;
  }

  @override
  Stream<List<Document>> subscribeDocuments({int limit = 200}) =>
      Stream.value([
        const Document(
            id: 'd1',
            userId: 'u1',
            title: 'A volume',
            type: 'pdf',
            status: DocumentStatus.complete,
            createdAt: 1757000000000,
            chunkCount: 3),
      ]);

  @override
  Stream<List<Tag>> subscribeTags() => Stream.value(const []);
}

Newsletter _n(String id, Map<String, dynamic> json) =>
    Newsletter.fromJson(id, {'user_id': 'u1', ...json});

final _readings = _n('r1', {
  'kind': 'scripture',
  'status': 'sent',
  'generated_at': 1758800000000,
});
final _generating = _n('g1', {
  'kind': 'daily',
  'status': 'generating',
  'generated_at': 1758700000000,
});
final _legacy = _n('l1', {
  // pre-2.24.0: no `kind` at all; pre-2.0.0: `html`, no `html_body`.
  'status': 'sent',
  'html': '<p>An old card list.</p>',
  'chunk_ids': ['c1', 'c2'],
  'generated_at': 1757500000000,
});
final _letterheaded = _n('h1', {
  'kind': 'daily',
  'status': 'sent',
  'subject': 'Your NoteLetter — on quiet rooms',
  'chunk_ids': ['c1', 'c2', 'c3'],
  'html_body': '<div data-nl-letterhead="1"><h1>NOTELETTER</h1>'
      '<p>Vol. I · No. 3</p><p data-nl-lede="1">Three passages found each '
      'other today.</p></div>',
  'text_body': 'NOTELETTER Vol. I · No. 3 Three passages found each other.',
  'generated_at': 1757540000000,
});

Future<NewsletterNotifier> _load(List<Newsletter> all, {bool fail = false}) async {
  FirestoreService.instance = _Reads(all, fail: fail);
  final n = NewsletterNotifier();
  await n.load();
  return n;
}

Future<void> _pump(WidgetTester tester, List<Newsletter> all,
    {bool fail = false}) async {
  FirestoreService.instance = _Reads(all, fail: fail);
  final letters = NewsletterNotifier();
  await letters.load();
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => DocumentsNotifier()),
      ChangeNotifierProvider(create: (_) => TagsNotifier()),
      ChangeNotifierProvider<NewsletterNotifier>.value(value: letters),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(body: LibraryPage()),
    ),
  ));
  await tester.pump();
  await tester.pump();
}

void main() {
  tearDown(FirestoreService.resetInstance);

  group('todaysLetter', () {
    test('the newest DAILY record, of any status — never a readings letter',
        () async {
      final n = await _load([_readings, _generating, _letterheaded]);
      expect(n.todaysLetter?.id, 'g1',
          reason: 'a generating letter is the newest daily one, as on web');
    });

    test('a kindless pre-2.24.0 record counts (`!= scripture`, never `== daily`)',
        () async {
      final n = await _load([_readings, _legacy]);
      expect(n.todaysLetter?.id, 'l1');
    });

    test('readings letters only: no Today\'s letter', () async {
      final n = await _load([_readings]);
      expect(n.todaysLetter, isNull);
    });
  });

  test('the hero lede is the marked note, cut at 140', () {
    expect(_letterheaded.ledeOf(140), 'Three passages found each other today.');
    final long = _n('x', {'text_body': 'w ' * 100});
    expect(long.ledeOf(140).length, 140);
    expect(long.lede.length, 120, reason: 'the Letters rows keep 120');
  });

  group('the hero', () {
    testWidgets('a letterheaded letter: its note, its subject, its counts',
        (tester) async {
      await _pump(tester, [_readings, _letterheaded]);
      expect(find.byType(KitHeroCard), findsOneWidget);
      expect(find.text('Three passages found each other today.'),
          findsOneWidget);
      expect(find.textContaining('Vol. I'), findsNothing,
          reason: 'never the masthead and folio');
      // The masthead number is the subject, set in caps as `.masthead-no`.
      expect(find.text('YOUR NOTELETTER — ON QUIET ROOMS'), findsOneWidget);
      expect(find.textContaining('3 passages from your library'),
          findsOneWidget);
    });

    testWidgets('a pre-2.0.0 record still draws the hero, with the fallback line',
        (tester) async {
      await _pump(tester, [_legacy]);
      expect(find.byType(KitHeroCard), findsOneWidget);
      expect(find.text('Your daily reading, drawn from what you’ve added to '
          'your library.'), findsOneWidget);
    });

    testWidgets('a failed read says so, never "tomorrow\'s letter"',
        (tester) async {
      await _pump(tester, const [], fail: true);
      expect(find.text("Today's letter could not be read."), findsOneWidget);
      expect(find.byType(KitFailureInline), findsOneWidget);
      expect(find.textContaining("Tomorrow's letter"), findsNothing);
      expect(find.byType(KitHeroCard), findsNothing);
    });
  });
}
