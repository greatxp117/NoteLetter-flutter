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
// row counted in the folio; the known records taken after the request (a
// snapshot that beats the reply leaves a row that never leaves, and whose Try
// again mails a second letter); a pending send surviving into another account
// (Try again mails the wrong reader); *Sent* not counting the row.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/newsletter.dart';
import 'package:flutter_app/models/newsletter_settings.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/state/newsletter_notifier.dart';
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

  // `_start_manual_letter` writes the record BEFORE the 202 (4.76.0), so the
  // live archive can bring it before the request answers.
  testWidgets(
      'a record that beats the reply leaves no row, no second letter on Try again',
      (tester) async {
    final live = StreamController<List<Newsletter>>();
    addTearDown(live.close);
    final reply = Completer<String?>();
    final sender = LettersSender(answer: () => reply.future);
    await pumpLetters(tester, LettersReads(live: live),
        settings: LettersSettings(_on), letters: sender);
    live.add([_sent('n1')]);
    await lettersFrames(tester);
    await tester.tap(find.byType(KitActionButton));
    await lettersFrames(tester);
    // The record lands while the request is still out…
    live.add([_building('n2'), _sent('n1')]);
    await lettersFrames(tester);
    // …and only then does the reply arrive.
    reply.complete(null);
    await lettersFrames(tester);
    expect(_pendingRow(), findsNothing);
    expect(sender.pendingSends, isEmpty);
    sender.age(now: DateTime.now().add(const Duration(minutes: 6)));
    await lettersFrames(tester);
    expect(find.text('The letter did not start.'), findsNothing,
        reason: 'a letter that exists never reads as one that did not start');
  }, timeout: _t);

  testWidgets('*Sent* counts the row on its way, as web does; the folio does not',
      (tester) async {
    final live = StreamController<List<Newsletter>>();
    addTearDown(live.close);
    await pumpLetters(tester, LettersReads(live: live),
        settings: LettersSettings(_on), letters: LettersSender());
    live.add([_sent('n1')]);
    await lettersFrames(tester);
    await tester.tap(find.byType(KitActionButton));
    await lettersFrames(tester);
    final sent = find.byWidgetPredicate(
        (w) => w is KitSectionHead && w.title == 'Sent');
    expect(tester.widget<KitSectionHead>(sent).meta, '2 letters');
  }, timeout: _t);

  test('a pending send belongs to its account: another reader starts clean',
      () async {
    final live = StreamController<List<Newsletter>>.broadcast();
    addTearDown(live.close);
    FirestoreService.instance = LettersReads(live: live);
    addTearDown(FirestoreService.resetInstance);
    var uid = 'reader-a';
    final letters = NewsletterNotifier(uid: () => uid);
    addTearDown(letters.dispose);
    unawaited(letters.load());
    live.add([_sent('n1')]);
    await Future<void>.delayed(Duration.zero);
    letters.pushPending(letters.knownLetterIds);
    expect(letters.pendingSends, hasLength(1));

    uid = 'reader-b';
    unawaited(letters.load());
    expect(letters.pendingSends, isEmpty,
        reason: "Try again on A's row would mail B");
    expect(letters.staleSends, isEmpty);
    expect(letters.history, isEmpty, reason: "A's letters are not B's");
    expect(letters.loaded, isFalse, reason: 'B has not been read yet');
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
    // A month under the failure keeps its margin (web's `.hx-sh+.dp-lgroup`
    // zeroes it only straight under the section head).
    final month = tester.widget<KitLetterMonthHead>(
        find.byType(KitLetterMonthHead, skipOffstage: false).first);
    expect(month.first, isFalse);
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
