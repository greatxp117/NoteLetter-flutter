// Letters in direction D (F-144, screens/letters.md §Composition *Letters*;
// web `pages/LettersView.jsx`, W4). What no frame can show on its own:
//   · the folio's count is a MEASUREMENT — the dash until the archive read
//     answers or while it is refused, a floor (`30+`) once the window is full;
//   · a letter row's number is the letter's own, and only where no letter in
//     the window carries one is it the row's place (W4 FOUND 6);
//   · Contents lists one row per month the archive holds, counted;
//   · what Send now answered stands UNDER THE MASTHEAD (W4 FOUND 1), calm for
//     a cooldown, §14.2 for a refusal;
//   · the panel's delivery switch writes before it moves;
//   · a 402 phone renders the page whole, in both themes.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/newsletter.dart';
import 'package:flutter_app/models/newsletter_settings.dart';
import 'package:flutter_app/models/scripture_newsletter_settings.dart';
import 'package:flutter_app/pages/letters/letter_reader.dart';
import 'package:flutter_app/pages/letters_page.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/shared/cooldown.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

import '../contract/letters_harness.dart';

int _at(int y, int m, int d) => DateTime(y, m, d, 7).millisecondsSinceEpoch;

const _lettered =
    '<div data-nl-letterhead="1"><p>NoteLetter</p>'
    '<div><h2>The crowded pan</h2><blockquote>Brown the meat before adding '
    'liquid, and never crowd the pan.</blockquote>'
    '<a href="https://noteletter.com/reader/d1?p=c1">Read “The Craft of '
    'Braising” in context →</a></div>'
    '<div><h2>Love the questions</h2><blockquote>Be patient toward all that '
    'is unsolved in your heart.</blockquote></div>'
    '<p data-nl-lede="1">Three passages found each other today.</p></div>';

/// The newest letter, numbered by its folio, letterheaded, three passages.
Newsletter _no3() => lettersLetter('n3', {
  'subject': 'Your NoteLetter — On Quiet Rooms',
  'generated_at': _at(2026, 9, 10),
  'html_body': _lettered,
  'text_body': 'NOTELETTER Vol. I · No. 3 · Thursday',
  'chunk_ids': ['a', 'b', 'c'],
  'delivery': {'state': 'delivered'},
});

/// A frame-less letter (no folio, no number), openable.
Newsletter _plain(String id, int at) => lettersLetter(id, {
  'subject': 'Your NoteLetter — On Beginnings',
  'generated_at': at,
  'html_body': '<p>A passage about beginnings.</p>',
  'text_body': 'A passage about beginnings.',
  'chunk_ids': ['x'],
});

Newsletter _empty(String id, int at) => lettersLetter(id, {
  'status': 'empty',
  'generated_at': at,
  'error_message': 'Every passage in the window has been in a recent letter.',
});

Newsletter _readings() => lettersLetter('r1', {
  'kind': 'scripture',
  'generated_at': _at(2026, 9, 10),
  'liturgical_day': {'name': 'Thursday of week 23 in Ordinary Time'},
  'readings': [
    {'label': 'Gospel', 'ref': 'Lk 6:27-38'},
  ],
  'passages_sent': 2,
  'passages_found': 6,
});

const _on = NewsletterSettings(
  enabled: true,
  emailAddress: 'reader@example.com',
  deliveryTime: '08:00',
  timezone: 'America/Chicago',
);

/// The folio as the masthead draws it, read back as words.
Finder _folio(String words) => find.byWidgetPredicate(
  (w) =>
      w is Text && (w.data ?? '').replaceAll(' ', ' ') == words.toUpperCase(),
);

Finder _inContents(String label) =>
    find.descendant(of: find.byType(KitContents), matching: find.text(label));

void main() {
  tearDown(Cooldowns.instance.resetForTest);

  group('the folio and the Delivery figures (pure)', () {
    test('the dash until the archive read answers, or while refused', () {
      expect(
        lettersFolio(measured: false, daily: 0, window: 0),
        'Letters · — letters',
      );
      expect(
        lettersFolio(
          measured: false,
          daily: 4,
          window: 4,
          when: 'Daily at 8:00 AM',
        ),
        'Letters · — letters · Daily at 8:00 AM',
      );
      expect(lettersSentFigure(measured: false, daily: 4, window: 4), '—');
    });

    test('counted once read, agreeing in number', () {
      expect(
        lettersFolio(measured: true, daily: 5, window: 6),
        'Letters · 5 letters',
      );
      expect(
        lettersFolio(measured: true, daily: 1, window: 1),
        'Letters · 1 letter',
      );
      expect(lettersSentFigure(measured: true, daily: 5, window: 6), '5');
    });

    test('a full window is a floor, never a total', () {
      // The window holds BOTH letters; the count is the daily ones in it.
      expect(
        lettersFolio(measured: true, daily: 27, window: 30),
        'Letters · 27+ letters',
      );
      expect(lettersSentFigure(measured: true, daily: 27, window: 30), '27+');
    });

    test('{when} only while delivery is on and read', () {
      expect(lettersWhen(_on), 'Daily at 8:00 AM');
      expect(
        lettersWhen(
          const NewsletterSettings(
            frequency: 'weekdays',
            deliveryTime: '06:30',
          ),
        ),
        'Weekdays at 6:30 AM',
      );
      expect(lettersWhen(const NewsletterSettings(enabled: false)), isNull);
      expect(lettersWhen(null), isNull);
    });
  });

  group('the archive by month, and its numbers (pure)', () {
    test('a letter\'s own number, blank for one without — never a place', () {
      final groups = lettersByMonth([
        _no3(),
        _plain('n2', _at(2026, 9, 9)),
        _plain('n1', _at(2026, 7, 2)),
      ]);
      expect(
        [for (final g in groups) g.label],
        ['September 2026', 'July 2026'],
      );
      expect([for (final g in groups) g.rows.length], [2, 1]);
      expect(
        [
          for (final g in groups)
            for (final r in g.rows) r.$2,
        ],
        ['3', '', ''],
      );
    });

    test('only where NO letter carries a number, each row\'s place', () {
      final groups = lettersByMonth([
        _plain('n3', _at(2026, 9, 10)),
        _plain('n2', _at(2026, 9, 9)),
        _empty('n1', _at(2026, 7, 2)),
      ]);
      expect(
        [
          for (final g in groups)
            for (final r in g.rows) r.$2,
        ],
        ['3', '2', '1'],
      );
    });
  });

  group('the page', () {
    setUpAll(lettersFonts);

    testWidgets('unread: the dash, the kicker over skeletons, no "none yet"', (
      tester,
    ) async {
      await pumpLetters(
        tester,
        LettersReads(hangLetters: true),
        settings: LettersSettings(_on),
      );
      expect(_folio('Letters · — letters · Daily at 8:00 AM'), findsOneWidget);
      expect(find.text('THE LETTER'), findsOneWidget);
      expect(find.byType(KitSkeletonLines), findsNWidgets(2));
      expect(find.text('No letters sent yet.'), findsNothing);
      expect(find.text('No letter yet'), findsNothing);
    });

    testWidgets('refused: the dash, §14.1 under Sent, the kicker says so', (
      tester,
    ) async {
      await pumpLetters(
        tester,
        LettersReads(failLetters: true),
        settings: LettersSettings(_on),
      );
      expect(_folio('Letters · — letters · Daily at 8:00 AM'), findsOneWidget);
      expect(find.byType(KitFailureBlock), findsOneWidget);
      expect(find.text('Your letters could not be read'), findsOneWidget);
      expect(find.text('No letters sent yet.'), findsNothing);
    });

    testWidgets('a full window reads 30+ in the folio and the figures', (
      tester,
    ) async {
      await pumpLetters(
        tester,
        LettersReads(
          letters: [
            for (var i = 0; i < 30; i++)
              _plain('n$i', _at(2026, 9, 28) - i * 86400000),
          ],
        ),
        settings: LettersSettings(_on),
      );
      expect(
        _folio('Letters · 30+ letters · Daily at 8:00 AM'),
        findsOneWidget,
      );
      expect(find.text('30+'), findsOneWidget);
    });

    testWidgets('Contents: the latest letter, the readings letter, each month '
        'counted, readings sent', (tester) async {
      await pumpLetters(
        tester,
        LettersReads(
          letters: [
            _no3(),
            _readings(),
            _plain('n2', _at(2026, 9, 9)),
            _empty('n1', _at(2026, 7, 2)),
          ],
          readings: const ScriptureNewsletterSettings(enabled: true),
        ),
        settings: LettersSettings(_on),
      );
      final order = [
        'The latest letter',
        'The readings letter',
        'September 2026',
        'July 2026',
        'Readings sent',
      ];
      for (final l in order) {
        expect(_inContents(l), findsOneWidget, reason: l);
      }
      final ys = [for (final l in order) tester.getTopLeft(_inContents(l)).dy];
      expect(ys, [...ys]..sort());
      // The folio counts the DAILY records only.
      expect(_folio('Letters · 3 letters · Daily at 8:00 AM'), findsOneWidget);
      // The latest letter under its kicker, with ALL its passages.
      expect(find.text('THE LETTER · NO. 3'), findsOneWidget);
      expect(find.text('3 PASSAGES · ~4 MIN READ'), findsOneWidget);
      expect(find.text('On Quiet Rooms'), findsWidgets);
      expect(find.text('The crowded pan'), findsOneWidget);
      expect(find.text('Love the questions'), findsOneWidget);
      // A row numbered by its folio; the rest blank (never a place).
      final row = find.byKey(const ValueKey('d-lrow-n3'));
      expect(
        find.descendant(of: row, matching: find.text('3')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('d-lmonth-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('d-rlrow-r1')), findsOneWidget);
    });

    testWidgets('a refused send stands under the masthead, as §14.2', (
      tester,
    ) async {
      final sender = LettersSender(
        answer: () async => 'No delivery address is set for this account.',
      );
      await pumpLetters(
        tester,
        LettersReads(letters: [_no3()]),
        settings: LettersSettings(_on),
        letters: sender,
      );
      expect(find.byKey(const ValueKey('d-letters-send-line')), findsNothing);
      await tester.tap(find.byType(KitActionButton));
      await lettersFrames(tester);
      expect(sender.sends, 1);
      final line = find.byKey(const ValueKey('d-letters-send-line'));
      expect(line, findsOneWidget);
      expect(
        find.descendant(of: line, matching: find.byType(KitFailureInline)),
        findsOneWidget,
      );
      expect(find.textContaining('No delivery address is set'), findsOneWidget);
      // Under the masthead's title, above the column — beside the action that
      // was pressed, not at the foot of the letter a screen below it.
      final title = tester.getTopLeft(find.text('Letters').first).dy;
      final top = tester.getTopLeft(line).dy;
      final latest = tester
          .getTopLeft(find.byKey(const ValueKey('d-letters-latest')))
          .dy;
      expect(top, greaterThan(title));
      expect(top, lessThan(latest));
    });

    testWidgets('a queued send says so there, calm', (tester) async {
      await pumpLetters(
        tester,
        LettersReads(letters: [_no3()]),
        settings: LettersSettings(_on),
        letters: LettersSender(),
      );
      await tester.tap(find.byType(KitActionButton));
      await lettersFrames(tester);
      final line = find.byKey(const ValueKey('d-letters-send-line'));
      expect(
        find.descendant(of: line, matching: find.textContaining('On its way')),
        findsOneWidget,
      );
      expect(find.byType(KitFailureInline), findsNothing);
    });

    testWidgets('a cooldown holds the action with its seconds, its sentence '
        'the calm line', (tester) async {
      const sentence =
          'A letter was requested a moment ago — give it a minute.';
      final now = DateTime.utc(2026, 10, 6, 12);
      Cooldowns.instance.clock = () => now;
      Cooldowns.instance.arm(
        WaitKey.letterSend(),
        const ApiException(
          429,
          sentence,
          retryAfterS: 58,
          serverSentence: true,
        ),
      );
      await pumpLetters(
        tester,
        LettersReads(letters: [_no3()]),
        settings: LettersSettings(_on),
      );
      final a = KitPageTools.instance.action!;
      expect(a.label, 'Send now · 0:58');
      expect(a.short, 'Send now');
      expect(a.disabled, isTrue);
      final line = find.byKey(const ValueKey('d-letters-send-line'));
      expect(
        find.descendant(of: line, matching: find.text(sentence)),
        findsOneWidget,
      );
      expect(find.byType(KitFailureInline), findsNothing);
    });

    testWidgets('no recipient: the action is Add a delivery address', (
      tester,
    ) async {
      await pumpLetters(
        tester,
        LettersReads(letters: [_no3()]),
        settings: LettersSettings(const NewsletterSettings(enabled: false)),
        accountEmail: null,
      );
      final a = KitPageTools.instance.action!;
      expect(a.label, 'Add a delivery address');
      expect(a.short, 'Address');
    });

    Future<void> openPanel(WidgetTester tester) async {
      expect(KitPageTools.instance.openSettings('letter'), isTrue);
      await lettersFrames(tester);
    }

    KitSwitch deliverySwitch(WidgetTester tester) => tester.widget<KitSwitch>(
      find.descendant(
        of: find.byKey(const ValueKey('d-letters-delivery')),
        matching: find.byType(KitSwitch),
      ),
    );

    testWidgets('the panel\'s delivery switch writes before it moves', (
      tester,
    ) async {
      final write = Completer<String?>();
      final settings = LettersSettings(
        const NewsletterSettings(enabled: false, emailAddress: 'r@x.test'),
        onDelivery: (_) => write.future,
      );
      await pumpLetters(
        tester,
        LettersReads(letters: [_no3()]),
        settings: settings,
      );
      await openPanel(tester);
      final row = find.byKey(const ValueKey('d-letters-delivery'));
      expect(
        find.descendant(of: row, matching: find.text('Paused')),
        findsOneWidget,
      );
      // Said BEFORE the switch is touched (2.30.0 rule 5).
      expect(
        find.textContaining('Turning this on sends a letter'),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('d-letters-delivery')),
          matching: find.byType(KitSwitch),
        ),
      );
      await lettersFrames(tester, 2);
      expect(settings.deliveryWrites, [true]);
      expect(
        deliverySwitch(tester).value,
        isFalse,
        reason: 'nothing moves while the write is out',
      );
      expect(deliverySwitch(tester).onChanged, isNull, reason: 'held');
      write.complete(null);
      await lettersFrames(tester);
      expect(deliverySwitch(tester).value, isTrue);
      expect(
        find.descendant(of: row, matching: find.text('Every day at 7:00 AM')),
        findsOneWidget,
      );
      expect(find.textContaining('A letter is on its way'), findsOneWidget);
    });

    testWidgets('a refused delivery write leaves the switch where it was', (
      tester,
    ) async {
      final settings = LettersSettings(
        const NewsletterSettings(enabled: false, emailAddress: 'r@x.test'),
        onDelivery: (_) async => 'Scheduled delivery could not be changed.',
      );
      await pumpLetters(
        tester,
        LettersReads(letters: [_no3()]),
        settings: settings,
      );
      await openPanel(tester);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('d-letters-delivery')),
          matching: find.byType(KitSwitch),
        ),
      );
      await lettersFrames(tester);
      expect(deliverySwitch(tester).value, isFalse);
      expect(deliverySwitch(tester).onChanged, isNotNull);
      expect(
        find.ancestor(
          of: find.text('Scheduled delivery could not be changed.'),
          matching: find.byType(KitFailureInline),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a row with a body opens the letter, and comes back', (
      tester,
    ) async {
      await pumpLetters(
        tester,
        LettersReads(letters: [_plain('n2', _at(2026, 9, 9))]),
        settings: LettersSettings(_on),
      );
      await tester.tap(find.byKey(const ValueKey('d-lrow-n2')));
      await lettersFrames(tester);
      expect(find.byType(LetterReaderView), findsOneWidget);
      expect(KitPageTools.instance.action?.label, 'Open in email');
      await tester.tap(find.byType(KitDBackControl));
      await lettersFrames(tester);
      expect(find.byType(LetterReaderView), findsNothing);
      expect(find.byKey(const ValueKey('d-lrow-n2')), findsOneWidget);
    });

    testWidgets('an empty row is informational: it does not open', (
      tester,
    ) async {
      await pumpLetters(
        tester,
        LettersReads(letters: [_empty('n1', _at(2026, 7, 2))]),
        settings: LettersSettings(_on),
      );
      await tester.tap(find.byKey(const ValueKey('d-lrow-n1')));
      await lettersFrames(tester);
      expect(find.byType(LetterReaderView), findsNothing);
      expect(find.text('NOTHING NEW'), findsOneWidget);
    });

    for (final b in Brightness.values) {
      testWidgets('a 402 phone renders the page whole (${b.name})', (
        tester,
      ) async {
        await pumpLetters(
          tester,
          LettersReads(
            letters: [
              _no3(),
              _readings(),
              _plain('n2', _at(2026, 9, 9)),
              _empty('n1', _at(2026, 7, 2)),
            ],
            readings: const ScriptureNewsletterSettings(enabled: true),
          ),
          settings: LettersSettings(_on),
          size: const Size(402, 874),
          brightness: b,
        );
        expect(tester.takeException(), isNull);
        for (final k in ['d-lrow-n3', 'd-lrow-n2', 'd-lrow-n1']) {
          final row = find.byKey(ValueKey(k));
          expect(row, findsOneWidget);
          expect(tester.getTopRight(row).dx, lessThanOrEqualTo(402));
        }
        // ≤700 the row keeps the number, the text, the date and the badge —
        // no figures.
        expect(find.text('3 passages · ~4 min'), findsNothing);
        expect(find.text('DELIVERED'), findsOneWidget);
        // The kicker's figures drop to their own line on a phone, trailing.
        final kick = find.text('THE LETTER · NO. 3');
        final figs = find.text('3 PASSAGES · ~4 MIN READ');
        expect(
          tester.getTopLeft(figs).dy,
          greaterThan(tester.getTopLeft(kick).dy),
        );
        expect(tester.getTopRight(figs).dx, closeTo(402 - 18, 1));
        // The send action is the tab bar's centre on a phone; the page
        // declares it.
        expect(KitPageTools.instance.action?.short, 'Send now');
      });
    }
  });
}
