/// letters.md §Composition *The letter*: the reader's bar is the back control,
/// the crumb, then Copy and Open in email. This client drew neither (web
/// `d153111` gave both their handlers; `LetterBarActions.jsx`,
/// `letterActions.js`).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/newsletter.dart';
import 'package:flutter_app/pages/letters/letter_reader.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

Newsletter _n(Map<String, dynamic> json) =>
    Newsletter.fromJson('l1', {'user_id': 'u1', 'status': 'sent', ...json});

const _body = '<p>A passage about quiet rooms.</p>';

Future<void> _pump(WidgetTester tester, Widget view, {double width = 900}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: view),
  ));
  await tester.pump();
}

/// The real faces: the width question is about the bar's real labels, and
/// the test font (Ahem) draws every glyph a full em wide.
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

void main() {
  setUpAll(_loadFonts);
  final letter = _n({'subject': 'On quiet rooms & doors', 'html_body': _body});

  test('Open in email is a mailto carrying the subject, and only the subject', () {
    expect(letterMailto(letter).toString(),
        'mailto:?subject=On%20quiet%20rooms%20%26%20doors');
    expect(letterMailto(_n({'html_body': _body})).toString(), 'mailto:');
  });

  testWidgets('Copy copies the stored letter and says it did', (tester) async {
    Newsletter? copied;
    await _pump(
        tester,
        LetterReaderView(
            letter: letter, onBack: () {}, copy: (n) async => copied = n));
    expect(find.text('Open in email'), findsOneWidget);
    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(copied?.htmlBody, _body);
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('a refused copy is §14.2 under the bar', (tester) async {
    await _pump(
        tester,
        LetterReaderView(
            letter: letter,
            onBack: () {},
            copy: (_) async => throw Exception('clipboard refused')));
    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(find.byType(KitFailureInline), findsOneWidget);
    expect(find.textContaining('The letter could not be copied — '),
        findsOneWidget);
  });

  testWidgets('a mail handoff that went nowhere is said, never swallowed',
      (tester) async {
    Uri? asked;
    await _pump(
        tester,
        LetterReaderView(
            letter: letter,
            onBack: () {},
            openMail: (u) async {
              asked = u;
              return false;
            }));
    await tester.tap(find.text('Open in email'));
    await tester.pump();
    expect(asked, letterMailto(letter));
    expect(find.textContaining('No mail app could be opened'), findsOneWidget);
  });

  testWidgets('a letter with no body has nothing to copy', (tester) async {
    var calls = 0;
    await _pump(
        tester,
        LetterReaderView(
            letter: _n({'subject': 'Old', 'html': '<p>x</p>'}),
            onBack: () {},
            copy: (_) async => calls++));
    await tester.tap(find.text('Copy'), warnIfMissed: false);
    await tester.pump();
    expect(calls, 0);
    expect(find.text('Copied'), findsNothing);
  });

  for (final width in [402.0, 375.0, 320.0]) {
    testWidgets('the bar lays out whole at $width', (tester) async {
      await _pump(tester, LetterReaderView(letter: letter, onBack: () {}),
          width: width);
      expect(tester.takeException(), isNull);
      expect(find.text('All letters'), findsOneWidget);
      // Labels while they fit; the glyphs alone below that, never a row
      // running off the screen.
      expect(find.text('Open in email'), width >= 400 ? findsOneWidget : findsNothing);
      expect(find.byIcon(Icons.open_in_new), findsOneWidget);
      expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
    });
  }
}
