/// The letter chip (Xavier's ruling 2026-10-14; screens/library.md §The
/// letter chip; kit §21's optional part). A shelf whose `letter_mode` CHANGES
/// the letter says so — *Lead* on §6.3's positive tone, *Muted* on idle — in
/// the foot of each Shelves index card and, in direction D, on BOTH of Home's
/// §42 forms (the catalogue's mark line, the covers' head), and nowhere while
/// the daily letter is off or its setting unread.
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
import 'package:flutter_app/pages/tags_page.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/shared/local_flags.dart';
import 'package:flutter_app/state/documents_notifier.dart';
import 'package:flutter_app/state/newsletter_notifier.dart';
import 'package:flutter_app/state/settings_notifier.dart';
import 'package:flutter_app/state/tags_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

const _shelves = [
  Tag(id: 'lead', userId: 'u1', title: 'Leading', letterMode: 'lead'),
  Tag(id: 'muted', userId: 'u1', title: 'Quiet', letterMode: 'muted'),
  Tag(id: 'mixed', userId: 'u1', title: 'Blended', letterMode: 'mixed'),
];

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
        for (final s in _shelves)
          Document(
              id: 'd-${s.id}',
              userId: 'u1',
              title: 'On ${s.title}',
              type: 'pdf',
              status: DocumentStatus.complete,
              createdAt: 1757000000000,
              chunkCount: 3,
              tagIds: [s.id]),
      ]);

  @override
  Stream<List<Tag>> subscribeTags() => Stream.value(_shelves);
}

class _Settings extends SettingsNotifier {
  _Settings(this.value);
  final NewsletterSettings? value;
  @override
  Future<void> loadAll() async {}
  @override
  NewsletterSettings? get newsletter => value;
}

class _Uncounted extends _Reads {
  @override
  Stream<List<Document>> subscribeDocuments({int limit = 200}) =>
      Stream.value([
        Document(
            id: 'd-u',
            userId: 'u1',
            title: 'Never counted',
            type: 'pdf',
            status: DocumentStatus.complete,
            createdAt: 1757000000000,
            tagIds: const ['lead']),
      ]);
}

Future<void> _pumpWith(WidgetTester tester, Widget page, FirestoreService reads,
    NewsletterSettings? settings) async {
  FirestoreService.instance = reads;
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
    child: MaterialApp(theme: AppTheme.light, home: Scaffold(body: page)),
  ));
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
}

Future<void> _pump(WidgetTester tester, Widget page,
    {NewsletterSettings? settings}) async {
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
      ChangeNotifierProvider<SettingsNotifier>(
          create: (_) => _Settings(settings)),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: page),
    ),
  ));
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
}

const _on = NewsletterSettings(enabled: true);
const _off = NewsletterSettings(enabled: false);

Finder _chip(String caps) => find.byWidgetPredicate(
    (w) => w is KitStatusPill && w.label.toUpperCase() == caps);

void main() {
  setUp(() {
    KitPageTools.instance.reset();
    SharedPreferences.setMockInitialValues({'nl-onboard-dismissed': true});
    LocalFlags.resetForTest();
    LocalFlags.onboardDismissed.value = true;
    LocalFlags.sourceView.value = 'list';
  });
  tearDown(FirestoreService.resetInstance);

  group('the rule', () {
    test('Lead and Muted only — mixed, absent and unknown draw nothing', () {
      expect(KitLetterChip.forShelf('lead', letterOn: true), KitLetterChip.lead);
      expect(
          KitLetterChip.forShelf('muted', letterOn: true), KitLetterChip.muted);
      expect(KitLetterChip.forShelf('mixed', letterOn: true), isNull);
      expect(KitLetterChip.forShelf(null, letterOn: true), isNull);
      expect(KitLetterChip.forShelf('loud', letterOn: true), isNull);
      // An unknown stored value reads `mixed` on the model, too.
      expect(Tag.fromJson('t', {'letter_mode': 'loud'}).letterMode, 'mixed');
      expect(KitLetterChip.lead.label, 'Lead');
      expect(KitLetterChip.lead.positive, isTrue);
      expect(KitLetterChip.muted.label, 'Muted');
      expect(KitLetterChip.muted.positive, isFalse);
    });

    test('nothing at all while the letter is off', () {
      expect(KitLetterChip.forShelf('lead', letterOn: false), isNull);
      expect(KitLetterChip.forShelf('muted', letterOn: false), isNull);
    });

    test('the letter is on only when the stored doc says enabled: true', () {
      // Absent is off, as on Letter settings (web `Boolean(data.enabled)`).
      expect(NewsletterSettings.fromJson(const {}).enabled, isFalse);
      expect(NewsletterSettings.fromJson(const {'enabled': true}).enabled,
          isTrue);
      expect(NewsletterSettings.fromJson(const {'enabled': false}).enabled,
          isFalse);
      // A read that has not answered (or failed) supports no claim.
      expect(_Settings(null).letterOn, isFalse);
      expect(_Settings(_on).letterOn, isTrue);
      expect(_Settings(_off).letterOn, isFalse);
    });
  });

  group('Home (§42, direction D)', () {
    testWidgets('the catalogue carries it on its mark line, at the trailing '
        'edge', (tester) async {
      await _pump(tester, const LibraryPage(), settings: _on);
      expect(find.byType(KitShelfCatalogue), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(KitShelfCatalogue), matching: _chip('LEAD')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(KitShelfCatalogue), matching: _chip('MUTED')),
          findsOneWidget);
      // At the mark line's trailing edge: right of the shelf's numeral.
      final col = find.byKey(const ValueKey('cat-lead'));
      final chip = find.descendant(of: col, matching: _chip('LEAD'));
      final numeral = find.descendant(of: col, matching: find.text('§ I'));
      expect(tester.getTopLeft(chip).dx,
          greaterThan(tester.getTopRight(numeral).dx));
      // `mixed` draws nothing: three shelves, two chips.
      expect(find.byType(KitStatusPill).evaluate().where((e) {
        final w = e.widget as KitStatusPill;
        return w.label == 'Lead' || w.label == 'Muted';
      }).length, 2);
    });

    testWidgets('the covers carry it in the head', (tester) async {
      SharedPreferences.setMockInitialValues(
          {'nl-onboard-dismissed': true, LocalFlags.sourceViewKey: 'grid'});
      await _pump(tester, const LibraryPage(), settings: _on);
      expect(find.byType(KitShelfCovers), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('cvs-lead')),
              matching: _chip('LEAD')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('cvs-muted')),
              matching: _chip('MUTED')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('cvs-mixed')),
              matching: find.byType(KitStatusPill)),
          findsNothing);
    });

    testWidgets('no chip while the letter is off', (tester) async {
      await _pump(tester, const LibraryPage(), settings: _off);
      expect(_chip('LEAD'), findsNothing);
      expect(_chip('MUTED'), findsNothing);
    });

    testWidgets('no chip before the settings read has answered',
        (tester) async {
      await _pump(tester, const LibraryPage());
      expect(_chip('LEAD'), findsNothing);
      expect(_chip('MUTED'), findsNothing);
    });
  });

  group('Home · a passage figure needs a count (ruled 2026-10-14)', () {
    testWidgets('a source never counted keeps its count cell, empty; a '
        'measured count draws', (tester) async {
      await _pump(tester, const LibraryPage(), settings: _on);
      // Recently added's register rows and the catalogue's rows both count.
      expect(
          find.descendant(
              of: find.byType(KitRegisterRow), matching: find.text('3')),
          findsNWidgets(3));
      expect(
          find.descendant(
              of: find.byType(KitShelfCatalogue), matching: find.text('3')),
          findsNWidgets(3));
      FirestoreService.instance = _Uncounted();
      await tester.pumpWidget(const SizedBox());
      await _pumpWith(tester, const LibraryPage(), _Uncounted(), _on);
      expect(find.byType(KitRegisterRow), findsOneWidget);
      for (final where in [
        find.byType(KitRegisterRow),
        find.byType(KitShelfCatalogue),
      ]) {
        expect(find.descendant(of: where, matching: find.text('0')),
            findsNothing,
            reason: 'the cell stays, empty — never "0"');
      }
      // The register row draws no figure nobody measured. (The catalogue's
      // shelf meta is a TOTAL over its sources, which the rule leaves alone.)
      expect(
          find.descendant(
              of: find.byType(KitRegisterRow),
              matching: find.textContaining('passage')),
          findsNothing);
    });
  });

  group('the Shelves index', () {
    testWidgets('each card carries it in its foot, Lead and Muted only',
        (tester) async {
      await _pump(tester, const ShelvesPage(), settings: _on);
      expect(
          find.descendant(
              of: find.byType(KitShelfCard), matching: _chip('LEAD')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(KitShelfCard), matching: _chip('MUTED')),
          findsOneWidget);
      final mixed = find.ancestor(
          of: find.text('Blended'), matching: find.byType(KitShelfCard));
      expect(find.descendant(of: mixed, matching: find.byType(KitStatusPill)),
          findsNothing);
      // In the foot: below the card's last volume line.
      final lead = find.ancestor(
          of: find.text('Leading'), matching: find.byType(KitShelfCard));
      expect(
          tester.getTopLeft(find.descendant(of: lead, matching: _chip('LEAD'))).dy,
          greaterThan(tester
              .getBottomLeft(
                  find.descendant(of: lead, matching: find.text('On Leading')))
              .dy));
    });

    testWidgets('no chip while the letter is off', (tester) async {
      await _pump(tester, const ShelvesPage(), settings: _off);
      expect(_chip('LEAD'), findsNothing);
      expect(_chip('MUTED'), findsNothing);
    });
  });
}
