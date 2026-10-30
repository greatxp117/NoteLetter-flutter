// F-74 — the manuscript's reading controls, against the reference
// (ManuscriptPanel.jsx `TypeControls`, `.ms-progress`, `.ms-resume`, the
// first passage's `::first-letter`; readerPrefs.js for every number).
//
// What the frame cannot prove is proved here: the preference table and its
// validation, the resume thresholds, that the stats opt-in now lives in Aa
// (F-77 (2)), and that the drop cap opens only a plain first paragraph.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/models/chunk.dart';
import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/pages/reader/manuscript_panel.dart';
import 'package:flutter_app/pages/reader/reader_prefs.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/theme/tokens.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

class _QuietFirestore extends FirestoreService {
  _QuietFirestore() : super.stub();
  @override
  Future<List<String>> logChunksRead(
          String documentId, List<String> chunkIds) async =>
      const [];
}

Future<void> _pumpPanel(WidgetTester tester, String html,
    {String text = 'Quarterly tax figures and the operating budget.'}) async {
  FirestoreService.instance = _QuietFirestore();
  addTearDown(FirestoreService.resetInstance);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: SingleChildScrollView(
        child: ManuscriptPanel(
          docId: 'doc-1',
          doc: Document.fromJson('doc-1', {
            'user_id': 'u1',
            'title': 'Quarterly Tax Summary',
            'type': 'pdf',
            'status': 'complete',
            'word_count': 7,
          }),
          chunks: [
            Chunk.fromJson({
              'chunk_id': 'c1',
              'document_id': 'doc-1',
              'chunk_index': 0,
              'text': text,
              'html': html,
            }),
          ],
          onSaved: () async {},
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump();
}

/// Unmounts inside the test body: the dwell timers and the position write's
/// debounce are disposed there, before the binding checks for pending timers.
Future<void> _done(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 30));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ReaderPrefs.resetForTest();
  });

  group('the preference table (readerPrefs.js)', () {
    test('sizes, faces and widths are the reference\'s, Medium · Serif · '
        'Normal · stats off by default', () {
      expect([for (final s in ReaderPrefs.sizes) (s.$2, s.$3)], [
        ('Small', 17.0),
        ('Medium', 19.0),
        ('Large', 21.0),
        ('X-large', 24.0),
      ]);
      expect([for (final f in ReaderPrefs.faces) f.$2], ['Serif', 'Sans']);
      expect([for (final m in ReaderPrefs.measures) m.$2],
          ['Narrow', 'Normal', 'Wide']);
      const d = ReaderPrefs();
      expect((d.size, d.face, d.measure, d.stats),
          ('md', 'serif', 'normal', false));
      expect((d.px, d.leading), (19.0, 1.68),
          reason: 'the default IS the sheet\'s pre-2.13.0 type');
    });

    test('leading loosens small and tightens large', () {
      expect(const ReaderPrefs(size: 'sm').leading, 1.75);
      expect(const ReaderPrefs(size: 'lg').leading, 1.68);
      expect(const ReaderPrefs(size: 'xl').leading, 1.55);
    });

    test('an unknown stored value falls back per field, never wholesale', () {
      final p = ReaderPrefs.fromJson(
          {'size': 'huge', 'face': 'sans', 'measure': 7, 'stats': 'yes'});
      expect((p.size, p.face, p.measure, p.stats),
          ('md', 'sans', 'normal', false));
    });

    test('the old stats key is read once as the default', () {
      expect(ReaderPrefs.fromJson({}, legacyStats: true).stats, isTrue);
      expect(ReaderPrefs.fromJson({'stats': false}, legacyStats: true).stats,
          isFalse, reason: 'the store\'s own answer wins');
    });

    test('a choice persists under the one store key', () async {
      await ReaderPrefs.ensureLoaded();
      await ReaderPrefs.set(ReaderPrefs.current.value.copyWith(size: 'lg'));
      final p = await SharedPreferences.getInstance();
      expect(p.getString(ReaderPrefs.storeKey), contains('"size":"lg"'));
    });
  });

  group('where the reader stopped', () {
    test('offered only between 4% and 97%', () {
      ReaderPrefs.savePosition('a', 0.03);
      ReaderPrefs.savePosition('b', 0.5);
      ReaderPrefs.savePosition('c', 0.97);
      expect(ReaderPrefs.positionOf('a'), isNull,
          reason: 'don\'t resume someone to where they already are');
      expect(ReaderPrefs.positionOf('b'), 0.5);
      expect(ReaderPrefs.positionOf('c'), isNull,
          reason: 'finished — start them at the top');
    });

    test('the last 60 documents are kept, not an unbounded map', () {
      final t0 = DateTime(2026, 10, 12);
      for (var i = 0; i < 61; i++) {
        ReaderPrefs.savePosition('d$i', 0.5,
            at: t0.add(Duration(seconds: i)));
      }
      expect(ReaderPrefs.positionOf('d0'), isNull, reason: 'the oldest goes');
      expect(ReaderPrefs.positionOf('d60'), 0.5);
    });
  });

  group('the drop cap', () {
    test('::first-letter takes leading punctuation with the letter', () {
      expect(KitDropCap.split('Quarterly tax'), ('Q', 'uarterly tax'));
      expect(KitDropCap.split('“Quarterly” tax'), ('“Q', 'uarterly” tax'));
    });

    testWidgets('a plain first paragraph opens with the cap in the accent',
        (tester) async {
      await _pumpPanel(tester,
          '<p>Quarterly tax figures and the operating budget.</p>');
      expect(find.byType(KitDropCap), findsOneWidget);
      final cap = tester.widget<Text>(find.text('Q'));
      expect(cap.style?.fontSize, 58);
      expect(cap.style?.color, Tokens.light.accentText);
      await _done(tester);
    });

    testWidgets('a first block that is not a paragraph takes no cap',
        (tester) async {
      await _pumpPanel(tester, '<h2>Budget</h2><p>Quarterly tax.</p>');
      expect(find.byType(KitDropCap), findsNothing);
      await _done(tester);
    });

    testWidgets('a paragraph with inline markup keeps it, and no cap',
        (tester) async {
      await _pumpPanel(tester,
          '<p>Quarterly <a href="https://example.test">tax</a> figures.</p>');
      expect(find.byType(KitDropCap), findsNothing);
      await _done(tester);
    });
  });

  group('Aa, the progress rule and the stats door', () {
    testWidgets('Aa sits beside Edit text and opens the four rows',
        (tester) async {
      await _pumpPanel(tester, '<p>Quarterly tax figures.</p>');
      expect(find.byType(KitTypeControls), findsOneWidget);
      expect(find.byType(KitProgressRule), findsOneWidget);
      await tester.tap(find.text('Aa'));
      await tester.pump();
      for (final l in ['TEXT SIZE', 'TYPEFACE', 'LINE WIDTH', 'READING STATS']) {
        expect(find.text(l), findsOneWidget, reason: l);
      }
      await tester.tap(find.text('Large'));
      await tester.pump();
      expect(ReaderPrefs.current.value.size, 'lg');
      await tester.tap(find.text('Shown'));
      await tester.pump();
      expect(ReaderPrefs.current.value.stats, isTrue,
          reason: 'Reading stats is the breakdown\'s opt-in (F-77 (2))');
      await _done(tester);
    });

    testWidgets('a sheet shorter than the viewport reads as all the way',
        (tester) async {
      await _pumpPanel(tester, '<p>Quarterly tax figures.</p>');
      await tester.pump();
      expect(tester.widget<KitProgressRule>(find.byType(KitProgressRule)).value,
          1.0, reason: '`readable <= 0 ? 1` — nothing to progress through');
      await _done(tester);
    });

    testWidgets('editing hides Aa and the rule', (tester) async {
      await _pumpPanel(tester, '<p>Quarterly tax figures.</p>');
      await tester.tap(find.text('Edit text'));
      await tester.pump();
      expect(find.byType(KitTypeControls), findsNothing);
      expect(find.byType(KitProgressRule), findsNothing);
      await _done(tester);
    });

    testWidgets('a stored position is offered, never performed',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        ReaderPrefs.posKey: '{"doc-1":{"ratio":0.42,"at":1}}',
      });
      await _pumpPanel(tester, '<p>Quarterly tax figures.</p>');
      await tester.pump();
      expect(find.text('You stopped about 42% of the way through.'),
          findsOneWidget);
      await tester.tap(find.text('Start over'));
      await tester.pump();
      expect(find.byType(KitResumeOffer), findsNothing);
      await _done(tester);
    });
  });
}
