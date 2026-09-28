/// The Library hero's rule. F-54 (web 5d6fe8d): its standfirst is the
/// librarian's note by its `data-nl-lede` marker, never a slice of the body.
/// F-70 (4.99.0, ADR-132; library.md §The letter): the hero's letter is the
/// NEWEST BUILT daily letter (web getLatestLetter) — it was the newest daily
/// RECORD of any status (web ef14f8a), the rule web left at 4.98.0 — and it
/// names its day: "Today's letter" only when built on the device's calendar
/// day, "Latest letter" and "Your latest letter is from {day}" otherwise.
library;

import 'dart:async';

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
import 'package:flutter_app/state/settings_notifier.dart';
import 'package:flutter_app/state/tags_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

class _Reads extends FirestoreService {
  _Reads(this.letters, {this.fail = false, this.hang = false}) : super.stub();
  final List<Newsletter> letters;
  final bool fail;

  /// A read that has not answered yet — the page calls `load()` itself on
  /// mount, so only a service that never answers can hold that state.
  final bool hang;

  @override
  String? get currentUid => 'u1';

  @override
  Future<List<Newsletter>> listAllNewsletters({int limit = 30}) async {
    if (hang) return Completer<List<Newsletter>>().future;
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
// Local noon on a fixed day, so the day the standfirst names does not move
// with the machine's time zone.
final _sep10 = DateTime(2025, 9, 10, 12).millisecondsSinceEpoch;
final _kindless = _n('k1', {
  // No `kind` (pre-2.24.0), a body, no `chunk_ids`, no lede marker.
  'status': 'sent',
  'html_body': '<p>A plain body.</p>',
  'generated_at': _sep10,
});
final _todays = _n('t1', {
  'kind': 'daily',
  'status': 'generating',
  'subject': 'Being sent',
  'chunk_ids': ['c1'],
  'html_body': '<p>Built, and going out now.</p>',
  'generated_at': DateTime.now().millisecondsSinceEpoch,
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
  'generated_at': _sep10,
});

Future<NewsletterNotifier> _load(List<Newsletter> all, {bool fail = false}) async {
  FirestoreService.instance = _Reads(all, fail: fail);
  final n = NewsletterNotifier();
  await n.load();
  return n;
}

Future<void> _pump(WidgetTester tester, List<Newsletter> all,
    {bool fail = false, bool hang = false}) async {
  FirestoreService.instance = _Reads(all, fail: fail, hang: hang);
  final letters = NewsletterNotifier();
  if (!hang) await letters.load();
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => DocumentsNotifier()),
      ChangeNotifierProvider(create: (_) => TagsNotifier()),
      ChangeNotifierProvider<NewsletterNotifier>.value(value: letters),
      ChangeNotifierProvider<SettingsNotifier>(create: (_) => _QuietSettings()),
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

  group('the hero\'s letter is the newest BUILT daily letter', () {
    test('never a record still being built, never a readings letter',
        () async {
      final n = await _load([_readings, _generating, _letterheaded]);
      expect(n.latest?.id, 'h1');
    });

    test('a kindless record counts (`!= scripture`, never `== daily`)',
        () async {
      final n = await _load([_readings, _kindless]);
      expect(n.latest?.id, 'k1');
    });

    test('a pre-2.0.0 record (`html`, no `html_body`) is not a built letter',
        () async {
      final n = await _load([_readings, _legacy]);
      expect(n.latest, isNull);
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

    testWidgets('a built letter with no lede draws the fallback line',
        (tester) async {
      await _pump(tester, [_kindless]);
      expect(find.byType(KitHeroCard), findsOneWidget);
      expect(find.text('Your daily reading, drawn from what you’ve added to '
          'your library.'), findsOneWidget);
    });

    testWidgets('built on an earlier day: Latest letter, and the day named',
        (tester) async {
      await _pump(tester, [_letterheaded]);
      // The section header sets its label in caps (the caller's, as web's
      // `.eyebrow`).
      expect(find.text('LATEST LETTER'), findsOneWidget);
      expect(find.text("TODAY'S LETTER"), findsNothing);
      expect(
          find.text('Your latest letter is from Wednesday, September 10 — '
              '3 passages from your library.'),
          findsOneWidget);
      expect(find.text('SENT'), findsOneWidget,
          reason: 'a sent letter keeps its Sent figure');
    });

    testWidgets('built today: Today\'s letter, and no day named',
        (tester) async {
      await _pump(tester, [_todays]);
      expect(find.text("TODAY'S LETTER"), findsOneWidget);
      expect(find.text("Today's letter is ready — 1 passage from your library."),
          findsOneWidget);
      expect(find.text('SENT'), findsNothing,
          reason: 'Sent only for a letter that was (ADR-132)');
    });

    testWidgets('no chunk_ids: the count clause is dropped, never "0 passages"',
        (tester) async {
      await _pump(tester, [_kindless]);
      expect(find.text('Your latest letter is from Wednesday, September 10.'),
          findsOneWidget);
    });

    testWidgets('before the read answers, the standfirst says nothing',
        (tester) async {
      await _pump(tester, [_letterheaded], hang: true);
      expect(find.textContaining('Your library is being read'), findsNothing);
      expect(find.byType(KitHeroCard), findsNothing);
    });

    testWidgets('a failed read says so, never "tomorrow\'s letter"',
        (tester) async {
      await _pump(tester, const [], fail: true);
      expect(find.text('Your latest letter could not be read.'), findsOneWidget);
      expect(find.byType(KitFailureInline), findsOneWidget);
      expect(find.textContaining("Tomorrow's letter"), findsNothing);
      expect(find.byType(KitHeroCard), findsNothing);
    });
  });
}

/// The Library's checklist reads the letter settings once per visit; the
/// read is not this suite's subject, so it answers nothing.
class _QuietSettings extends SettingsNotifier {
  @override
  Future<void> loadAll() async {}
}
