/// **Mark as read** (5.27.0, ADR-184; `screens/reader.md` §Reading state) —
/// web's `ManuscriptPanel` `markRead` and `tests/contract/mark-as-read.test.js`.
///
/// `fake_cloud_firestore` cannot resolve against this SDK, so the write is
/// faked at its seam: [FirestoreService.logChunksRead], the dwell rule's own
/// write (INV-03b), which resolves with the ids it COMMITTED and `[]` on a
/// refusal. What is asserted is the control around it: the states, write
/// before you move, the refusal's §14.2 line, the slot that keeps its height,
/// and that a press never sends a second +1 for a passage whose dwell batch
/// is already in flight.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/models/chunk.dart';
import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/pages/reader/manuscript_panel.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// Each `logChunksRead` call, answered when the test says so.
class _Writes extends FirestoreService {
  _Writes() : super.stub();
  final List<(List<String>, Completer<List<String>>)> calls = [];

  @override
  Future<List<String>> logChunksRead(
      String documentId, List<String> chunkIds) {
    final c = Completer<List<String>>();
    calls.add((List.of(chunkIds), c));
    return c.future;
  }
}

const _refused = "This passage couldn't be marked read. Try again.";

Chunk _chunk(String id, int index, String text, {int viewCount = 0}) =>
    Chunk.fromJson({
      'chunk_id': id,
      'document_id': 'doc-1',
      'chunk_index': index,
      'text': text,
      'html': '<p>$text</p>',
      'view_count': viewCount,
    });

void main() {
  late _Writes writes;
  late List<List<String>> confirmed;

  setUp(() {
    writes = _Writes();
    FirestoreService.instance = writes;
    confirmed = [];
  });
  tearDown(() {
    FirestoreService.resetInstance();
    ManuscriptPanel.debugPauseDwell = false;
  });

  Future<void> pump(WidgetTester tester, List<Chunk> chunks) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ManuscriptPanel(
            docId: 'doc-1',
            doc: Document.fromJson('doc-1', {
              'user_id': 'u1',
              'title': 'Two passages',
              'type': 'article',
              'status': 'complete',
            }),
            chunks: chunks,
            onSaved: () async {},
            onChunksRead: confirmed.add,
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 30));
  }

  final mark1 = find.byKey(const ValueKey('ms-readmark-c1'));
  final mark2 = find.byKey(const ValueKey('ms-readmark-c2'));

  testWidgets('offered at the foot of every unread passage, never on a read '
      'one, never while editing', (tester) async {
    ManuscriptPanel.debugPauseDwell = true;
    await pump(tester, [
      _chunk('c1', 0, 'An unread passage.'),
      _chunk('c2', 1, 'A read passage.', viewCount: 1),
    ]);
    expect(mark1, findsOneWidget);
    expect(find.descendant(of: mark1, matching: find.text('Mark as read')),
        findsOneWidget);
    expect(mark2, findsNothing, reason: 'there is no mark unread');

    await tester.tap(find.text('Edit text'));
    await tester.pump();
    expect(find.text('Mark as read'), findsNothing,
        reason: 'editing is not reading');
    await unmount(tester);
  });

  testWidgets('a press writes that passage at once, says "Marking…", and '
      'turns it read only when the write commits', (tester) async {
    ManuscriptPanel.debugPauseDwell = true;
    await pump(tester, [
      _chunk('c1', 0, 'The first passage.'),
      _chunk('c2', 1, 'The second passage.'),
    ]);
    final below = tester.getTopLeft(mark2).dy;

    await tester.tap(mark1);
    await tester.pump();
    expect(writes.calls.single.$1, ['c1'],
        reason: 'one id, at once, through the dwell rule\'s own write');
    expect(find.descendant(of: mark1, matching: find.text('Marking…')),
        findsOneWidget);
    expect(confirmed, isEmpty, reason: 'write before you move');

    // A second press while it flies sends nothing.
    await tester.tap(mark1, warnIfMissed: false);
    await tester.pump();
    expect(writes.calls, hasLength(1));

    writes.calls.single.$2.complete(['c1']);
    await tester.pump();
    expect(mark1, findsNothing, reason: 'committed: the passage is read');
    expect(confirmed, [
      ['c1']
    ], reason: 'the reader folds the confirmed id in');
    expect(tester.getTopLeft(mark2).dy, below,
        reason: 'the slot keeps its height: nothing under it moved');
    await unmount(tester);
  });

  testWidgets('a refused write leaves the passage unread, with §14.2 beside '
      'the control, and a press tries again', (tester) async {
    ManuscriptPanel.debugPauseDwell = true;
    await pump(tester, [
      _chunk('c1', 0, 'The first passage.'),
      _chunk('c2', 1, 'The second passage.'),
    ]);
    await tester.tap(mark1);
    await tester.pump();
    writes.calls.single.$2.complete(const []);
    await tester.pump();
    expect(find.text(_refused), findsOneWidget);
    expect(find.descendant(of: mark1, matching: find.text('Mark as read')),
        findsOneWidget, reason: 'unread, and offered again');
    expect(confirmed, isEmpty);
    // Beside the control, in the same end-aligned slot: the line comes
    // before it, and wraps above it where the measure is too narrow for
    // both (web's `.ms-readfoot.has-fail`, `flex-wrap`).
    expect(
        tester.getTopLeft(find.text(_refused)).dx,
        lessThan(tester.getTopLeft(mark1).dx +
            tester.getSize(mark1).width));

    await tester.tap(mark1);
    await tester.pump();
    expect(find.text(_refused), findsNothing,
        reason: 'the line goes when the reader tries again');
    writes.calls.last.$2.complete(['c1']);
    await tester.pump();
    expect(mark1, findsNothing);
    expect(confirmed, [
      ['c1']
    ]);
    await unmount(tester);
  });

  testWidgets('a passage whose dwell batch is in flight waits for THAT write '
      'rather than sending a second +1', (tester) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    addTearDown(() => VisibilityDetectorController.instance.updateInterval =
        const Duration(milliseconds: 500));
    // One word: a dwell of 0.07 s, then the 1.5 s settle flushes the batch.
    await pump(tester, [_chunk('c1', 0, 'Hello.')]);
    // The detector reports a frame later; then the dwell, then the settle.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 2));
    expect(writes.calls.single.$1, ['c1'], reason: 'the dwell batch flew');
    expect(mark1, findsOneWidget,
        reason: 'not read until the batch commits — a timer that fired is '
            'not a write that landed');

    await tester.tap(mark1);
    await tester.pump();
    expect(writes.calls, hasLength(1), reason: 'no second +1');
    expect(find.descendant(of: mark1, matching: find.text('Marking…')),
        findsOneWidget);

    writes.calls.single.$2.complete(['c1']);
    await tester.pump();
    await tester.pump();
    expect(mark1, findsNothing);
    expect(confirmed, [
      ['c1']
    ], reason: 'once, from the batch the press rode');
    await unmount(tester);
  });
}
