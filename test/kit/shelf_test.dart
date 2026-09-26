// F-65 — the kit shelf (web `ShelfView.jsx`, `app-sources-shelf.css`) at the
// widths a phone lays it out in, with the BUNDLED faces: the test font draws
// every glyph a full em wide and would overflow what the real type fits.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

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

const _books = [
  KitBook(
      id: 'a',
      title: 'Quarterly Tax Summary With A Title Long Enough To Ellipsise',
      kind: 'pdf',
      passages: 2,
      createdAt: 1750000000000,
      shelf: 'Finance'),
  KitBook(
      id: 'b',
      title: 'Espresso Article',
      kind: 'web',
      passages: 40,
      words: 250000,
      viewCount: 3,
      sourceUrl: 'https://www.example.com/espresso'),
  KitBook(id: 'c', title: '', kind: 'podcast', passages: 0),
];

Future<void> _pumpAt(WidgetTester tester, double width, Widget child,
    {ThemeData? theme}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: theme ?? AppTheme.light,
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: child,
      ),
    ),
  ));
}

void main() {
  setUpAll(_loadFonts);

  for (final width in [390.0, 320.0]) {
    for (final dark in [false, true]) {
      testWidgets('a pulled book lays out whole at $width (${dark ? 'dark' : 'light'})',
          (tester) async {
        await _pumpAt(tester, width, const KitShelfView(items: _books),
            theme: dark ? AppTheme.dark : AppTheme.light);
        await tester.tap(find.byType(KitBookSpine).first);
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
        expect(find.byType(KitBookDetail), findsOneWidget);
        expect(find.byType(KitBookCover), findsOneWidget);
        // Stacked on a phone: the cover sits OVER the text, not beside it.
        final cover = tester.getRect(find.byType(KitBookCover));
        final title = tester.getRect(find.text('Open in reader'));
        expect(cover.bottom, lessThan(title.top));
      });
    }
  }

  testWidgets('a spine is as wide as its words, and keeps its height',
      (tester) async {
    await _pumpAt(tester, 390, const KitShelfView(items: _books));
    final w = [
      for (final e in find.byType(KitBookSpine).evaluate())
        tester.getSize(find.byWidget(e.widget)).width
    ];
    // 2 passages ≈ 1,700 words → near the 16px floor; 250k words → near 64.
    expect(w[0], lessThan(20));
    expect(w[1], greaterThan(55));
    // An unread book carries the dot; a read one does not.
    final dots = find.descendant(
        of: find.byType(KitBookSpine).at(1),
        matching: find.byWidgetPredicate((x) =>
            x is Container &&
            (x.decoration as BoxDecoration?)?.shape == BoxShape.circle));
    expect(dots, findsNothing);
    final first = tester.getSize(find.byType(KitBookSpine).first).height;
    await tester.pumpWidget(const SizedBox());
    await _pumpAt(tester, 390, const KitShelfView(items: _books));
    expect(tester.getSize(find.byType(KitBookSpine).first).height, first);
  });

  testWidgets('an empty filter says so, never an empty ledge', (tester) async {
    await _pumpAt(tester, 390, const KitShelfView(items: []));
    expect(find.text('Nothing on this shelf yet.'), findsOneWidget);
    expect(find.byType(KitShelfUnit), findsNothing);
  });

  testWidgets('a named shelf heads its ledge with plate, name and count',
      (tester) async {
    await _pumpAt(
        tester,
        390,
        KitShelfUnit(
          label: 'Finance',
          books: _books,
          openId: null,
          onOpen: (_) {},
          dot: const Color(0xFF6F8159), // literal-ok: a test shelf colour
        ));
    expect(tester.takeException(), isNull);
    expect(find.text('Finance'), findsOneWidget);
    expect(find.text('3 volumes · 42 passages'), findsOneWidget);
  });

  for (final width in [600.0, 390.0]) {
    testWidgets('source cards: two columns at 720, one at 460 ($width)',
        (tester) async {
      await _pumpAt(
          tester,
          width,
          KitSourceCardGrid(cards: [
            for (final b in _books)
              KitSourceCard(book: b, kindLabel: 'PDFs', date: 'Jun 15'),
          ]));
      expect(tester.takeException(), isNull);
      final a = tester.getRect(find.byType(KitSourceCard).at(0));
      final b = tester.getRect(find.byType(KitSourceCard).at(1));
      expect(a.top == b.top, width > 460,
          reason: '.src-cards: 1fr 1fr at ≤720, 1fr at ≤460');
    });
  }
}
