/// F-53, the letter-settings preview (4.98.0, ADR-131; `spec/screens/letters.md`
/// §The letter-settings preview; web 596edef `getLatestLetter`, `LetterHost`,
/// `letterFigures`, `useLetterCopy`).
///
/// The pane is the last letter the backend BUILT, through the Letters reader's
/// own host, with figures from that record only. The page reads the signed-in
/// account and Firestore in `initState`, which no test here can supply, so the
/// predicate, the figures and the pane are driven directly.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/newsletter.dart';
import 'package:flutter_app/pages/letters/letter_host.dart';
import 'package:flutter_app/pages/letters/letter_preview.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

Newsletter _n(String id, Map<String, dynamic> json) =>
    Newsletter.fromJson(id, {'user_id': 'u1', ...json});

const _body = '<p>A passage about quiet rooms.</p>';

Future<void> _pump(WidgetTester tester, Widget pane) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: SingleChildScrollView(child: pane)),
  ));
  await tester.pump();
}

void main() {
  group('the source is one stored record', () {
    test('the newest BUILT daily letter; newer non-letters do not displace it',
        () {
      final page = [
        _n('gen', {'status': 'generating'}),
        _n('empty', {'status': 'empty', 'html_body': _body}),
        _n('err', {'status': 'error', 'html_body': _body}),
        _n('rl', {'status': 'sent', 'kind': 'scripture', 'html_body': _body}),
        _n('built', {'status': 'sent', 'html_body': _body}),
        _n('older', {'status': 'sent', 'html_body': _body}),
      ];
      expect(pickLatestLetter(page)?.id, 'built');
    });

    test('a record with no html_body is not a letter; none → null', () {
      expect(pickLatestLetter([_n('a', {'status': 'sent', 'html': '<p>x</p>'})]),
          isNull);
      expect(pickLatestLetter(const []), isNull);
    });

    test('a pre-2.24.0 record (no kind) is a daily letter', () {
      expect(_n('a', {'status': 'sent', 'html_body': _body}).isBuiltLetter,
          isTrue);
    });
  });

  group('figures come from chunk_ids only (ADR-109)', () {
    test('absent draws no figure, never a 0', () {
      expect(letterFigures(_n('a', {'html_body': _body})), isNull);
    });
    test('present is counted', () {
      expect(letterFigures(_n('a', {'chunk_ids': []})), '0 passages · ~1 min read');
      expect(letterFigures(_n('a', {'chunk_ids': ['c1']})),
          '1 passage · ~2 min read');
      expect(letterFigures(_n('a', {'chunk_ids': ['c1', 'c2', 'c3']})),
          '3 passages · ~4 min read');
    });
  });

  group('the pane', () {
    final letter = _n('built', {
      'status': 'sent',
      'subject': 'On quiet rooms',
      'html_body': _body,
      'text_body': 'A passage about quiet rooms.',
      'chunk_ids': ['c1', 'c2', 'c3'],
    });

    testWidgets('renders the stored letter through the reader\'s host',
        (tester) async {
      await _pump(
          tester,
          LetterPreviewPane(
              letter: letter,
              loaded: true,
              error: null,
              sending: false,
              onSend: () {}));
      expect(find.byType(LetterHost), findsOneWidget);
      expect(find.text('3 PASSAGES · ~4 MIN READ'), findsOneWidget);
      expect(find.text('No letter has been built yet.'), findsNothing);
    });

    testWidgets('none built says so, draws no figure, and Copy is disabled',
        (tester) async {
      await _pump(
          tester,
          const LetterPreviewPane(
              letter: null,
              loaded: true,
              error: null,
              sending: false,
              onSend: null));
      expect(find.text('No letter has been built yet.'), findsOneWidget);
      expect(find.byType(LetterHost), findsNothing);
      expect(find.textContaining('PASSAGES'), findsNothing);
      final copy = tester.widget<KitButton>(
          find.ancestor(of: find.text('Copy'), matching: find.byType(KitButton)));
      expect(copy.onPressed, isNull);
    });

    testWidgets('a failed read is §14.2, never "none built" (INV-24)',
        (tester) async {
      await _pump(
          tester,
          const LetterPreviewPane(
              letter: null,
              loaded: false,
              error: 'You appear to be offline.',
              sending: false,
              onSend: null));
      expect(
          find.text("Today's letter could not be read — You appear to be offline."),
          findsOneWidget);
      expect(find.text('No letter has been built yet.'), findsNothing);
    });

    testWidgets('Copy copies that record and says it did', (tester) async {
      Newsletter? copied;
      await _pump(
          tester,
          LetterPreviewPane(
              letter: letter,
              loaded: true,
              error: null,
              sending: false,
              onSend: () {},
              copy: (n) async => copied = n));
      await tester.tap(find.text('Copy'));
      await tester.pump();
      expect(copied?.htmlBody, _body);
      expect(find.text('Copied'), findsOneWidget);
    });

    testWidgets('a refused copy renders in the §14.2 slot', (tester) async {
      await _pump(
          tester,
          LetterPreviewPane(
              letter: letter,
              loaded: true,
              error: null,
              sending: false,
              onSend: () {},
              copy: (_) async => throw Exception('clipboard refused')));
      await tester.tap(find.text('Copy'));
      await tester.pump();
      expect(find.textContaining('The letter could not be copied — '),
          findsOneWidget);
      expect(find.text('Copied'), findsNothing);
    });
  });
}
