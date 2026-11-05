// Letters reads its archive LIVE (round 3, item 3; web LettersView's
// `subscribeNewsletters` and its optimistic "Sending…" row, 4.76.0 ADR-110).
// Until round 3 the archive was read once, and again once after Send now, so a
// letter still being built kept showing `generating`, and *Letters sent*
// lagged, until the page was opened again.
//
// Mutants run against it (each red): the notifier reading once instead of
// subscribing (each case times out waiting for a snapshot that never comes);
// Send now pushing no pending row; the pending row kept after its
// record lands; the stale send drawn as a row instead of §14.1; the pending
// row counted in the folio.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/newsletter.dart';
import 'package:flutter_app/models/newsletter_settings.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

import 'letters_harness.dart';

const _on = NewsletterSettings(
  enabled: true,
  emailAddress: 'reader@example.com',
  deliveryTime: '08:00',
  timezone: 'America/Chicago',
);

final _at = DateTime.utc(2026, 11, 3, 12).millisecondsSinceEpoch;

Newsletter _sent(String id) => lettersLetter(id, {
      'generated_at': _at,
      'html_body': '<p>A letter</p>',
      'chunk_ids': ['c1'],
    });

Newsletter _building(String id) => lettersLetter(id, {
      'status': 'generating',
      'trigger': 'manual',
      'generated_at': _at + 1000,
    });

Finder _row(String id) => find.byKey(ValueKey('d-lrow-$id'));
Finder _pendingRow() => find.byWidgetPredicate((w) =>
    w is KitLetterArchiveRow &&
    (w.key as ValueKey<String>?)?.value.startsWith('d-lrow-pending-') == true);

// A mutant that reads once leaves a test waiting on a snapshot that never
// comes; the timeout makes that a failure, not a hang.
const _t = Timeout(Duration(seconds: 60));

void main() {
  testWidgets('a record the subscription brings is drawn, with no re-read',
      (tester) async {
    final live = StreamController<List<Newsletter>>();
    addTearDown(live.close);
    await pumpLetters(tester, LettersReads(live: live),
        settings: LettersSettings(_on));
    live.add([_sent('n1')]);
    await lettersFrames(tester);
    expect(_row('n1'), findsOneWidget);
    live.add([_building('n2'), _sent('n1')]);
    await lettersFrames(tester);
    expect(_row('n2'), findsOneWidget,
        reason: 'the build lands on its own, generating');
    expect(find.text('Gathering the best passages from your library…'),
        findsOneWidget);
  }, timeout: _t);

  testWidgets(
      'Send now leads the archive with a Sending row until its record lands',
      (tester) async {
    final live = StreamController<List<Newsletter>>();
    addTearDown(live.close);
    final letters = await pumpLetters(tester, LettersReads(live: live),
        settings: LettersSettings(_on), letters: LettersSender());
    live.add([_sent('n1')]);
    await lettersFrames(tester);
    await tester.tap(find.byType(KitActionButton));
    await lettersFrames(tester);
    expect(_pendingRow(), findsOneWidget);
    expect(letters.pendingSends, hasLength(1));
    // The folio counts the archive, never the row on its way.
    expect(
        tester
            .widget<KitDPage>(find.byKey(const ValueKey('d-letters')))
            .folio,
        startsWith('Letters · 1 letter'));

    // A snapshot carrying only what was known keeps the row.
    live.add([_sent('n1')]);
    await lettersFrames(tester);
    expect(_pendingRow(), findsOneWidget);
    // Its record lands: the row gives way to it.
    live.add([_building('n2'), _sent('n1')]);
    await lettersFrames(tester);
    expect(_pendingRow(), findsNothing);
    expect(_row('n2'), findsOneWidget);
  }, timeout: _t);

  testWidgets(
      'a send that waits five minutes is §14.1, not a row, and tries again',
      (tester) async {
    final live = StreamController<List<Newsletter>>();
    addTearDown(live.close);
    final sender = LettersSender();
    await pumpLetters(tester, LettersReads(live: live),
        settings: LettersSettings(_on), letters: sender);
    live.add([_sent('n1')]);
    await lettersFrames(tester);
    await tester.tap(find.byType(KitActionButton));
    await lettersFrames(tester);
    sender.age(now: DateTime.now().add(const Duration(minutes: 6)));
    await lettersFrames(tester);
    expect(_pendingRow(), findsNothing);
    expect(find.text('The letter did not start.'), findsOneWidget);
    final retry = find.descendant(
        of: find.byType(KitFailureBlock), matching: find.text('Try again'));
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await lettersFrames(tester);
    expect(sender.sends, 2);
    expect(find.text('The letter did not start.'), findsNothing);
    expect(_pendingRow(), findsOneWidget, reason: 'a fresh send is on its way');
  }, timeout: _t);
}
