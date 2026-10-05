// letters.md §Composition *Archive*: one bordered surface of LETTER rows, and
// the readings letter's archive is the same row (`.letter-row.rl-row`, web
// `ReadingsArchiveRow`) with its `.lr-kind` tag and its `.lr-refs` line.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/theme/tokens.dart';
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

const _refs = 'Col 3:12-17  ·  Ps 150:1-6  ·  Lk 6:27-38';

Widget _row({bool readings = true}) => KitLetterRowList(rows: [
      KitLetterRow(
        number: 3,
        title: 'Thursday of week 23 in Ordinary Time',
        kind: readings ? 'Readings' : null,
        refs: readings,
        lede: readings ? _refs : 'On quiet rooms',
        figures: '5 of 23 passages',
        date: 'Sep 11',
        badge: 'Delivered',
        settled: true,
        onTap: () {},
      ),
    ]);

Future<void> _pump(WidgetTester tester, double width, Widget child,
    {ThemeData? theme}) async {
  tester.view.physicalSize = Size(width, 900);
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

  testWidgets('a readings row carries the kind tag and sets refs in mono', (tester) async {
    await _pump(tester, 1200, _row());
    expect(find.text('READINGS'), findsOneWidget);
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
    final refs = tester.widget<Text>(find.text(_refs));
    expect(refs.style!.fontFamily, AppTheme.fontMono);
    expect(refs.style!.fontStyle, isNot(FontStyle.italic));
    final ctx = tester.element(find.text(_refs));
    expect(refs.style!.color, Tokens.of(ctx).fgSubtle);
    expect(find.text('5 of 23 passages'), findsOneWidget);
  });

  testWidgets('a daily row is unchanged: no tag, an italic lede', (tester) async {
    await _pump(tester, 1200, _row(readings: false));
    expect(find.text('READINGS'), findsNothing);
    final lede = tester.widget<Text>(find.text('On quiet rooms'));
    expect(lede.style!.fontStyle, FontStyle.italic);
  });

  for (final width in [402.0, 320.0]) {
    for (final dark in [false, true]) {
      testWidgets('a readings row lays out whole at $width (${dark ? 'dark' : 'light'})',
          (tester) async {
        await _pump(tester, width, _row(),
            theme: dark ? AppTheme.dark : AppTheme.light);
        expect(tester.takeException(), isNull);
        // The phone wraps the citations rather than cutting the last one.
        expect(tester.widget<Text>(find.text(_refs)).maxLines, isNull);
      });
    }
  }
}
