/// letters.md §Composition *A letter* (direction D, F-144; web
/// `LetterRead.jsx`): the crumb *All letters* over the folio `Letter · No. {n}
/// · {date}`, the title and its lede; the page's one action *Open in email*
/// (short *Email*) — a `mailto:` carrying the subject — and the sheet *This
/// letter*: the letter's passages as Contents, its figures, and *Copy the
/// letter* under Also. Until D this was a bar (`All letters`, a crumb, Copy,
/// Open in email); web `d153111` gave both their handlers.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/newsletter.dart';
import 'package:flutter_app/pages/letters/letter_reader.dart';
import 'package:flutter_app/shared/dates.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

Newsletter _n(Map<String, dynamic> json) =>
    Newsletter.fromJson('l1', {'user_id': 'u1', 'status': 'sent', ...json});

const _body = '<p>A passage about quiet rooms.</p>';
final _at = DateTime(2026, 9, 10, 7).millisecondsSinceEpoch;

const _lettered =
    '<div data-nl-letterhead="1">'
    '<div><h2>The crowded pan</h2><blockquote>Brown the meat.</blockquote></div>'
    '<div><h2>  </h2></div>'
    '<div><h2>Love   the questions</h2><blockquote>Be patient.</blockquote></div>'
    '<p data-nl-lede="1">Three passages found each other today.</p></div>';

Future<void> _pump(
  WidgetTester tester,
  Widget view, {
  double width = 1280,
}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: view),
    ),
  );
  await tester.pump();
}

/// A letterheaded body is a web view no widget test can mount: the host seam
/// draws a stand-in of the letter's own width, and keeps the heading keys.
Widget _host(Newsletter n, Key Function(int) key) => SizedBox(
  key: const ValueKey('stand-in'),
  height: 900,
  child: Column(
    children: [
      SizedBox(key: key(0), height: 300),
      SizedBox(key: key(1), height: 300),
    ],
  ),
);

/// The real faces: the width question is about the real labels, and the test
/// font (Ahem) draws every glyph a full em wide.
Future<void> _loadFonts() async {
  const faces = {
    'Geist': ['Geist-Regular.ttf', 'Geist-Medium.ttf', 'Geist-SemiBold.ttf'],
    'Geist Mono': ['GeistMono-Regular.ttf', 'GeistMono-Medium.ttf'],
    'Source Serif 4': [
      'SourceSerif4-Variable.ttf',
      'SourceSerif4-Italic-Variable.ttf',
    ],
  };
  for (final e in faces.entries) {
    final loader = FontLoader(e.key);
    for (final f in e.value) {
      loader.addFont(rootBundle.load('assets/fonts/$f'));
    }
    await loader.load();
  }
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}

/// A masthead line read back as words (the folio is set in caps, its ` · `
/// on a no-break space).
Finder _caps(String words) => find.byWidgetPredicate(
  (w) =>
      w is Text &&
      (w.data ?? '').replaceAll('\u00a0', ' ') == words.toUpperCase(),
);

void main() {
  setUpAll(_loadFonts);
  final letter = _n({
    'subject': 'On quiet rooms & doors',
    'html_body': _body,
    'generated_at': _at,
  });

  test(
    'Open in email is a mailto carrying the subject, and only the subject',
    () {
      expect(
        letterMailto(letter).toString(),
        'mailto:?subject=On%20quiet%20rooms%20%26%20doors',
      );
      expect(letterMailto(_n({'html_body': _body})).toString(), 'mailto:');
    },
  );

  test('a letter\'s title is the subject after "Your NoteLetter —"', () {
    expect(
      letterTitle(_n({'subject': 'Your NoteLetter — On Quiet Rooms'})),
      'On Quiet Rooms',
    );
    expect(letterTitle(_n({'subject': 'A plain subject'})), 'A plain subject');
    expect(letterTitle(_n({})), 'A Letter');
  });

  testWidgets('the masthead: All letters, the folio, the title, its lede', (
    tester,
  ) async {
    await _pump(
      tester,
      LetterReaderView(
        letter: _n({
          'subject': 'Your NoteLetter — On Quiet Rooms',
          'html_body': _lettered,
          'text_body': 'NOTELETTER Vol. I · No. 3 · Thursday',
          'generated_at': _at,
          'chunk_ids': ['a', 'b', 'c'],
          'delivery': {'state': 'delivered'},
        }),
        onBack: () {},
        host: _host,
      ),
    );
    expect(find.byType(KitDBackControl), findsOneWidget);
    expect(_caps('Letter · No. 3 · ${longDate(_at)}'), findsOneWidget);
    expect(find.text('On Quiet Rooms'), findsOneWidget);
    expect(find.text('Three passages found each other today.'), findsOneWidget);
    final a = KitPageTools.instance.action!;
    expect(a.label, 'Open in email');
    expect(a.short, 'Email');
    // The sheet: the passages read from the drawn letter — a heading with no
    // text is not one — then the figures.
    final contents = find.byType(KitContents);
    expect(
      find.descendant(of: contents, matching: find.text('The crowded pan')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: contents, matching: find.text('Love the questions')),
      findsOneWidget,
    );
    expect(find.text('~4 min'), findsOneWidget);
    expect(find.text('Delivered'), findsOneWidget);
    // Lifted as a sheet on a desk: a border and the --r-xl radius.
    final sheet = tester.widget<Container>(
      find.byKey(const ValueKey('d-letter-sheet')),
    );
    expect((sheet.decoration as BoxDecoration).border, isNotNull);
  });

  testWidgets('a readings letter: its own folio and title, no lede', (
    tester,
  ) async {
    await _pump(
      tester,
      LetterReaderView(
        letter: _n({
          'kind': 'scripture',
          'generated_at': _at,
          'html_body': '<p>x</p>',
          'liturgical_day': {'name': 'Thursday of week 23'},
          'readings': [
            {'label': 'First reading', 'ref': 'Col 3:12-17'},
            {'label': 'Gospel', 'ref': 'Lk 6:27-38'},
          ],
        }),
        onBack: () {},
      ),
    );
    expect(_caps('The readings letter · ${longDate(_at)}'), findsOneWidget);
    expect(find.text('Readings for ${longDate(_at)}'), findsOneWidget);
    final contents = find.byType(KitContents);
    expect(
      find.descendant(of: contents, matching: find.text('First reading')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: contents, matching: find.text('Gospel')),
      findsOneWidget,
    );
  });

  testWidgets('Copy copies the stored letter and says it did', (tester) async {
    Newsletter? copied;
    await _pump(
      tester,
      LetterReaderView(
        letter: letter,
        onBack: () {},
        copy: (n) async => copied = n,
      ),
    );
    await tester.tap(find.text('Copy the letter'));
    await tester.pump();
    expect(copied?.htmlBody, _body);
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('a refused copy is §14.2 above it', (tester) async {
    await _pump(
      tester,
      LetterReaderView(
        letter: letter,
        onBack: () {},
        copy: (_) async => throw Exception('clipboard refused'),
      ),
    );
    await tester.tap(find.text('Copy the letter'));
    await tester.pump();
    final line = find.textContaining('The letter could not be copied — ');
    expect(line, findsOneWidget);
    expect(
      find.ancestor(of: line, matching: find.byType(KitFailureInline)),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(line).dy,
      lessThan(tester.getTopLeft(find.text('Copy the letter')).dy),
    );
  });

  testWidgets('a mail handoff that went nowhere is said under the masthead', (
    tester,
  ) async {
    Uri? asked;
    await _pump(
      tester,
      LetterReaderView(
        letter: letter,
        onBack: () {},
        openMail: (u) async {
          asked = u;
          return false;
        },
      ),
    );
    await tester.tap(find.byType(KitActionButton));
    await tester.pump();
    expect(asked, letterMailto(letter));
    final line = find.textContaining('No mail app could be opened');
    expect(line, findsOneWidget);
    expect(
      find.ancestor(of: line, matching: find.byType(KitSendLine)),
      findsOneWidget,
    );
  });

  testWidgets('a letter with no body has nothing to copy: held', (
    tester,
  ) async {
    var calls = 0;
    await _pump(
      tester,
      LetterReaderView(
        letter: _n({'subject': 'Old', 'html': '<p>x</p>'}),
        onBack: () {},
        copy: (_) async => calls++,
      ),
    );
    final copy = tester.widget<KitAlsoButton>(
      find.byKey(const ValueKey('d-letter-copy')),
    );
    expect(copy.onTap, isNull);
    await tester.tap(find.text('Copy the letter'), warnIfMissed: false);
    await tester.pump();
    expect(calls, 0);
  });

  for (final width in [402.0, 375.0, 320.0]) {
    testWidgets('at $width the page lays out whole, the letter full width', (
      tester,
    ) async {
      await _pump(
        tester,
        LetterReaderView(
          letter: _n({
            'subject': 'Your NoteLetter — On Quiet Rooms',
            'html_body': _lettered,
            'generated_at': _at,
          }),
          onBack: () {},
          host: _host,
        ),
        width: width,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(KitDBackControl), findsOneWidget);
      // On a phone the letter takes the screen's whole width, unframed.
      expect(
        tester.getSize(find.byKey(const ValueKey('stand-in'))).width,
        width,
      );
      expect(tester.getTopLeft(find.byKey(const ValueKey('stand-in'))).dx, 0);
      // The running head: № and the passage the reader is in.
      expect(find.text('№'), findsOneWidget);
    });
  }
}
