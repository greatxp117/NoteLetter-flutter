/// What heads Home's column and what its tools are (web `LibraryHome.jsx`,
/// `shared/OnboardingChecklist.jsx`; screens/library.md §Composition,
/// direction D): the setup checklist strip, the page's one action and its
/// settings (§27/§28), and the app-wide List / Grid choice (§32) the two
/// listings share.
///
/// Each case is a clause of the reference: the checklist's steps come from
/// live data plus ONE client-local flag, Hide and the disclosure are written
/// per viewer before anything moves, a completed or hidden checklist is gone
/// and takes no room; *Add a source* is the page's action (short *Add*) and
/// *Letter settings* its panel; List / Grid is one choice, written before it
/// moves, offered only once a volume is complete.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/newsletter_settings.dart';
import 'package:flutter_app/models/tag.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/shared/local_flags.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

import 'home_harness.dart';

HomeReads _reads({bool shelved = true}) => HomeReads(
  docs: [
    for (var i = 0; i < 3; i++)
      homeDoc(
        'd$i',
        title: 'Volume $i',
        created: 1757000000000 - i,
        tags: shelved && i == 0 ? const ['t1'] : const [],
      ),
  ],
  tags: const [
    Tag(id: 't1', userId: 'u1', title: 'Finance', color: 'sage-500'),
  ],
);

Future<void> _pump(
  WidgetTester tester, {
  bool shelved = true,
  NewsletterSettings? settings,
  HomeReads? reads,
}) => pumpHome(
  tester,
  reads ?? _reads(shelved: shelved),
  settings: HomeSettings(settings),
  size: const Size(1200, 3000),
);

Finder _named(String label) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == label,
);

void _reset() {
  KitPageTools.instance.reset();
  LocalFlags.resetForTest();
  LocalFlags.sourceView.value = 'list';
  LocalFlags.onboardDismissed.value = false;
  LocalFlags.onboardExpanded.value = null;
  LocalFlags.onboardAsked.value = false;
}

void main() {
  setUp(_reset);
  tearDown(FirestoreService.resetInstance);

  group('the setup checklist', () {
    testWidgets('steps from live data: 4 of 5, the question the one left', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await _pump(tester, settings: const NewsletterSettings());
      expect(find.byType(KitSetupChecklist), findsOneWidget);
      expect(
        tester
            .widget<KitSetupChecklist>(find.byType(KitSetupChecklist))
            .compact,
        isTrue,
        reason: 'Home draws the strip, never the card',
      );
      expect(find.text('4 of 5 set up'), findsOneWidget);
      expect(
        find.text('Ask your library a question'),
        findsOneWidget,
        reason: 'the closed strip lists the remaining step as a pill',
      );
      expect(find.text('Add your first source'), findsNothing);
    });

    testWidgets('no settings doc and no shelved volume are two open steps', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await _pump(tester, shelved: false);
      expect(find.text('2 of 5 set up'), findsOneWidget);
      expect(find.text('File a volume onto a shelf'), findsOneWidget);
      expect(find.text('Set up your daily letter'), findsOneWidget);
    });

    testWidgets('a first question asked completes it, and it is gone', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'nl-onboard-asked': true});
      await _pump(tester, settings: const NewsletterSettings());
      expect(find.byType(KitSetupChecklist), findsNothing);
      expect(
        find.byType(KitHomeCheckSlot),
        findsNothing,
        reason: 'its slot takes no room',
      );
    });

    testWidgets('Hide is written under nl-onboard-dismissed, then it goes', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await _pump(tester, settings: const NewsletterSettings());
      await tester.tap(_named('Hide setup checklist'));
      await pumpFrames(tester, 2);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('nl-onboard-dismissed'), isTrue);
      expect(find.byType(KitSetupChecklist), findsNothing);
    });

    testWidgets('opening it shows every step, the done ones crossed off', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await _pump(tester, settings: const NewsletterSettings());
      await tester.tap(find.text('4 of 5 set up'));
      await pumpFrames(tester, 2);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('nl-onboard-expanded'), isTrue);
      expect(find.text('Create your account'), findsOneWidget);
      expect(find.text('Add your first source'), findsOneWidget);
    });

    testWidgets('it heads the column — above the letter, in an empty library '
        'too, never on the sheet', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pump(tester, reads: HomeReads());
      final strip = tester.getTopLeft(find.byType(KitSetupChecklist));
      expect(
        strip.dy,
        lessThan(tester.getTopLeft(find.byType(KitFirstSources)).dy),
      );
      expect(
        strip.dy,
        lessThan(tester.getTopLeft(find.byType(KitEditionLetter)).dy),
      );
      expect(
        find.descendant(
          of: find.byType(KitSheetCard),
          matching: find.byType(KitSetupChecklist),
        ),
        findsNothing,
      );
    });
  });

  group('the page’s tools', () {
    testWidgets('Add a source is the one action (short Add); Letter settings '
        'is the panel, its body LetterQuick', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pump(
        tester,
        settings: const NewsletterSettings(
          enabled: true,
          deliveryTime: '08:00',
        ),
      );
      final tools = KitPageTools.instance;
      expect(tools.action?.label, 'Add a source');
      expect(tools.action?.short, 'Add');
      expect(tools.settings?.label, 'Letter settings');
      expect(
        find.widgetWithText(KitActionButton, 'Add a source'),
        findsOneWidget,
      );
      expect(tools.openSettings(), isTrue);
      await pumpFrames(tester, 4);
      expect(find.byType(KitLetterQuick), findsOneWidget);
      expect(find.text('Scheduled delivery'), findsOneWidget);
      expect(find.text('Every letter setting →'), findsOneWidget);
    });
  });

  group('List / Grid (§32)', () {
    testWidgets('List by default; Grid is written before it moves, and both '
        'listings follow it', (tester) async {
      SharedPreferences.setMockInitialValues({'nl-onboard-dismissed': true});
      await _pump(tester, settings: const NewsletterSettings());
      // One toggle per listing, one choice.
      expect(find.byType(KitViewToggle), findsNWidgets(2));
      expect(find.byType(KitRegisterRow), findsNWidgets(3));
      expect(find.byType(KitShelfCatalogue), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Grid').first);
      await pumpFrames(tester, 4);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('nl-source-view'), 'grid');
      expect(find.byType(KitCoverStrip), findsOneWidget);
      expect(find.byType(KitShelfCovers), findsOneWidget);
      expect(find.byType(KitRegisterRow), findsNothing);
    });

    testWidgets('no toggle before a volume is complete', (tester) async {
      SharedPreferences.setMockInitialValues({'nl-onboard-dismissed': true});
      await _pump(
        tester,
        reads: HomeReads(
          docs: [homeDoc('p', status: DocumentStatus.queued, chunks: null)],
        ),
      );
      expect(find.byType(KitViewToggle), findsNothing);
    });
  });
}
