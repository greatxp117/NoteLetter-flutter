/// Moving a passage boundary (`screens/reader.md` §Moving a passage boundary;
/// feature `passage-boundary-drag.md`, F-132).
///
/// The re-cut rules are web's `passageBoundary.js` ported rule for rule, and
/// this file runs web's own cases (`tests/contract/passage-boundary.test.js`,
/// "the re-cut rules") case for case — then the grip: its name, Up/Down, a
/// drag, and the release that changes nothing.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/models/chunk.dart';
import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/pages/reader/manuscript_panel.dart';
import 'package:flutter_app/pages/reader/passage_boundary.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

class _QuietFirestore extends FirestoreService {
  _QuietFirestore() : super.stub();
  @override
  Future<List<String>> logChunksRead(
          String documentId, List<String> chunkIds) async =>
      const [];
}

void main() {
  group('the re-cut rules (web\'s cases)', () {
    const a = '<p>a1</p><p>a2</p>';
    const b = '<p>b1</p><p>b2</p>';

    test('offers every block boundary across both passages, and knows where '
        'it is now', () {
      expect(offeredCuts(a, b), [1, 2, 3]);
      expect(currentCut(a), 2);
    });

    test('never offers a cut that leaves either side with no text and no '
        'image', () {
      // A rule alone is not content: fn_update_content refuses a passage of
      // one.
      expect(offeredCuts('<hr><p>a</p>', '<p>b</p>'), [2]);
      expect(offeredCuts('<p>a</p>', '<p>b</p><hr>'), [1]);
      // An image is.
      expect(
          offeredCuts('<figure><img src="x.png"></figure>', '<p>b</p><p>c</p>'),
          [1, 2]);
    });

    test('re-cuts whole blocks and loses nothing', () {
      final one = recut(a, b, 1)!;
      expect(one.a, '<p>a1</p>');
      expect(one.b, '<p>a2</p><p>b1</p><p>b2</p>');
      final three = recut(a, b, 3)!;
      expect(three.a, '<p>a1</p><p>a2</p><p>b1</p>');
      expect(three.b, '<p>b2</p>');
    });

    test('changes nothing at the current cut or at a cut it does not offer',
        () {
      expect(recut(a, b, 2), isNull);
      expect(recut('<hr><p>a</p>', '<p>b</p>', 1), isNull);
      expect(recut(a, b, 9), isNull);
    });

    test('steps one offered cut at a time, and stays put at either end', () {
      expect(stepCut(a, b, 2, -1), 1);
      expect(stepCut(a, b, 2, 1), 3);
      expect(stepCut(a, b, 1, -1), 1);
      expect(stepCut(a, b, 3, 1), 3);
    });

    test('keeps loose top-level text as a block of its own', () {
      expect(passageBlocks('loose <b>x</b>'), ['loose ', '<b>x</b>']);
      expect(recut('<p>a</p>', 'tail &lt;ok&gt;<p>b</p>', 1), isNull);
      final cut = recut('<p>a</p>', 'tail &lt;ok&gt;<p>b</p>', 2)!;
      expect(cut.a, '<p>a</p>tail &lt;ok&gt;');
      expect(cut.b, '<p>b</p>');
    });

    test('an empty or absent passage has no blocks', () {
      expect(passageBlocks(''), isEmpty);
      expect(passageBlocks(null), isEmpty);
      expect(passageBlocks('  \n '), isEmpty);
    });
  });

  group('the boundary grip', () {
    final chunks = [
      Chunk.fromJson({
        'chunk_id': 'c1',
        'document_id': 'doc-1',
        'chunk_index': 0,
        'html': '<p>Alpha one.</p><p>Alpha two.</p>',
        'text': 'Alpha one. Alpha two.',
      }),
      Chunk.fromJson({
        'chunk_id': 'c2',
        'document_id': 'doc-1',
        'chunk_index': 1,
        'html': '<p>Beta one.</p><p>Beta two.</p>',
        'text': 'Beta one. Beta two.',
      }),
    ];

    Future<void> editPanel(WidgetTester tester) async {
      FirestoreService.instance = _QuietFirestore();
      addTearDown(FirestoreService.resetInstance);
      await tester.binding.setSurfaceSize(const Size(1000, 1600));
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
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('Edit text'));
      await tester.pump();
    }

    // The passages' editing text, block by block: one paragraph a block.
    List<String> bodies(WidgetTester tester) => [
          for (final f in tester.widgetList<TextField>(find.byType(TextField)))
            f.controller!.text,
        ];

    Future<void> dispose(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 30));
    }

    testWidgets('is on every passage after the first, named for the passage '
        'it moves', (tester) async {
      await editPanel(tester);
      expect(find.bySemanticsLabel('Move where passage 2 begins'),
          findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Move where passage 1 begins')),
          findsNothing);
      expect(find.byKey(const ValueKey('ms-grip-2')), findsOneWidget,
          reason: 'keyed by the passage it moves, as its name says');
      await dispose(tester);
    });

    testWidgets('moves the boundary one block per Up or Down, stops at the '
        'end, and keeps focus', (tester) async {
      await editPanel(tester);
      expect(bodies(tester), ['Alpha one.\n\nAlpha two.', 'Beta one.\n\nBeta two.']);
      final grip = find.byKey(const ValueKey('ms-grip-2'));
      expect(grip, findsOneWidget);
      Focus.of(tester.element(find.descendant(
              of: grip, matching: find.byType(Icon))))
          .requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(bodies(tester),
          ['Alpha one.', 'Alpha two.\n\nBeta one.\n\nBeta two.']);
      expect(find.text('unsaved edits'), findsOneWidget,
          reason: 'both passages are edited; nothing is written until Save');
      expect(
          Focus.of(tester.element(
                  find.descendant(of: grip, matching: find.byType(Icon))))
              .hasFocus,
          isTrue,
          reason: 'focus stays on the grip');

      // Alpha one. is all passage 1 has left: no further cut upward.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(bodies(tester),
          ['Alpha one.', 'Alpha two.\n\nBeta one.\n\nBeta two.']);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(bodies(tester),
          ['Alpha one.\n\nAlpha two.\n\nBeta one.', 'Beta two.']);
      await dispose(tester);
    });

    testWidgets('drags: the line follows the pointer, and the release re-cuts '
        'there', (tester) async {
      await editPanel(tester);
      final grip = find.byKey(const ValueKey('ms-grip-2'));
      final start = tester.getCenter(grip);
      // Beta two. — the fourth block — is the target: the drop line follows
      // the pointer to the boundary nearest it.
      final target = tester.getTopLeft(find.byType(TextField).last).dy + 60;
      final gesture = await tester.startGesture(start, kind: PointerDeviceKind.touch);
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      expect(find.text('PASSAGE BEGINS HERE'), findsOneWidget);
      await gesture.moveTo(Offset(start.dx, target));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(find.text('PASSAGE BEGINS HERE'), findsNothing);
      expect(bodies(tester),
          ['Alpha one.\n\nAlpha two.\n\nBeta one.', 'Beta two.']);
      await dispose(tester);
    });

    testWidgets('Escape mid-drag changes nothing, and takes the line away',
        (tester) async {
      await editPanel(tester);
      final grip = find.byKey(const ValueKey('ms-grip-2'));
      final start = tester.getCenter(grip);
      final target = tester.getTopLeft(find.byType(TextField).last).dy + 60;
      final gesture =
          await tester.startGesture(start, kind: PointerDeviceKind.touch);
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesture.moveTo(Offset(start.dx, target));
      await tester.pump();
      expect(find.byKey(const ValueKey('ms-dropline')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byKey(const ValueKey('ms-dropline')), findsNothing);
      await gesture.up();
      await tester.pump();
      expect(bodies(tester),
          ['Alpha one.\n\nAlpha two.', 'Beta one.\n\nBeta two.']);
      expect(find.text('saved'), findsOneWidget);
      await dispose(tester);
    });

    // §Moving a passage boundary: "a cancelled pointer changes nothing". A
    // cancel AFTER the drag was accepted reaches the recognizer as an END
    // (F-142's device batch re-cut on one), so the grip listens for it.
    testWidgets('a cancelled pointer changes nothing', (tester) async {
      await editPanel(tester);
      final grip = find.byKey(const ValueKey('ms-grip-2'));
      final start = tester.getCenter(grip);
      final target = tester.getTopLeft(find.byType(TextField).last).dy + 60;
      final gesture =
          await tester.startGesture(start, kind: PointerDeviceKind.touch);
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesture.moveTo(Offset(start.dx, target));
      await tester.pump();
      expect(find.byKey(const ValueKey('ms-dropline')), findsOneWidget);
      await gesture.cancel();
      await tester.pump();
      expect(find.byKey(const ValueKey('ms-dropline')), findsNothing);
      expect(bodies(tester),
          ['Alpha one.\n\nAlpha two.', 'Beta one.\n\nBeta two.']);
      expect(find.text('saved'), findsOneWidget);
      await dispose(tester);
    });

    testWidgets('on a phone the editing head wraps rather than running past '
        'the sheet', (tester) async {
      FirestoreService.instance = _QuietFirestore();
      addTearDown(FirestoreService.resetInstance);
      await tester.binding.setSurfaceSize(const Size(390, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 1600)),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ManuscriptPanel(
                docId: 'doc-1',
                doc: Document.fromJson('doc-1', {
                  'user_id': 'u1',
                  'title': 'Two passages',
                  'type': 'article',
                  'status': 'complete',
                }),
                chunks: [
                  chunks[0],
                  Chunk.fromJson({
                    'chunk_id': 'c2',
                    'document_id': 'doc-1',
                    'chunk_index': 1,
                    'html': '<p>${List.filled(150, 'word').join(' ')}</p>',
                    'text': List.filled(150, 'word').join(' '),
                    'user_edited': true,
                  }),
                ],
                onSaved: () async {},
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('Edit text'));
      await tester.pump();
      // A RenderFlex overflow is an exception the test framework reports.
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('ms-grip-2')), findsOneWidget);
      expect(find.text('EDITED'), findsOneWidget);
      expect(find.text('MERGE UP'), findsOneWidget);
      expect(
          tester.getTopLeft(find.text('MERGE UP')).dy,
          greaterThan(tester.getTopLeft(find.byKey(const ValueKey('ms-grip-2'))).dy),
          reason: 'what does not fit takes the next line');
      await dispose(tester);
    });

    testWidgets('a release where it started changes nothing', (tester) async {
      await editPanel(tester);
      final grip = find.byKey(const ValueKey('ms-grip-2'));
      final start = tester.getCenter(grip);
      final gesture = await tester.startGesture(start, kind: PointerDeviceKind.touch);
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      await gesture.moveTo(start);
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(bodies(tester),
          ['Alpha one.\n\nAlpha two.', 'Beta one.\n\nBeta two.']);
      expect(find.text('saved'), findsOneWidget);
      await dispose(tester);
    });
  });
}
