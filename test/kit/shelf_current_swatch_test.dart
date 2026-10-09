import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/pages/tags/shelf_parts.dart';
import 'package:flutter_app/theme/app_colors.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/theme/tokens.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

/// The eleventh, read-only "current" swatch (ruled 2026-10-08;
/// `screens/library.md` §Shelf color; web `b70f5ea`, `.ss-swatch-current`).
///
/// A shelf whose stored colour is not one of the ten — a legacy hex, which is
/// every auto-created shelf — matched no swatch, so the settings row marked
/// nothing: the one state in which the pane said nothing about the colour the
/// shelf is drawn in. Plus the 2026-10-08 wording tandem on Sources' filter
/// note, held to the reference's own line.

const _legacyHex = '#059669';

Future<List<String>> _mount(WidgetTester tester, String? stored,
    {bool showCurrent = true, bool enabled = true, ThemeData? theme}) async {
  final picked = <String>[];
  await tester.pumpWidget(MaterialApp(
    theme: theme ?? AppTheme.light,
    home: Scaffold(
      body: ShelfSwatches(
        selected: stored,
        showCurrent: showCurrent,
        enabled: enabled,
        onPick: picked.add,
      ),
    ),
  ));
  await tester.pump();
  return picked;
}

KitSwatch _swatch(WidgetTester tester, int i) =>
    tester.widgetList<KitSwatch>(find.byType(KitSwatch)).elementAt(i);

/// The fill a swatch paints: its inner circle's colour.
Color? _fill(WidgetTester tester, Finder swatch) {
  final boxes = tester
      .widgetList<Container>(
          find.descendant(of: swatch, matching: find.byType(Container)))
      .map((c) => c.decoration)
      .whereType<BoxDecoration>()
      .where((d) => d.color != null);
  return boxes.isEmpty ? null : boxes.last.color;
}

double _opacity(WidgetTester tester, Finder swatch) => tester
    .widget<Opacity>(
        find.descendant(of: swatch, matching: find.byType(Opacity)).first)
    .opacity;

void main() {
  group('the eleventh swatch', () {
    testWidgets('a legacy-hex shelf: eleven, the last one selected in its hex',
        (tester) async {
      await _mount(tester, _legacyHex);
      expect(find.byType(KitSwatch), findsNWidgets(11));
      for (var i = 0; i < 10; i++) {
        expect(_swatch(tester, i).selected, isFalse,
            reason: 'none of the ten is the stored colour');
      }
      final current = _swatch(tester, 10);
      expect(current.selected, isTrue);
      expect(current.readOnly, isTrue);
      expect(current.label, 'Current colour, not one of the ten');
      expect(current.tooltip, 'Current colour');
      final last = find.byType(KitSwatch).at(10);
      expect(_fill(tester, last), AppColors.shelfColor(_legacyHex),
          reason: 'exactly what every other surface paints');
      expect(_opacity(tester, last), 1.0, reason: 'read-only is not held');
    });

    testWidgets('it is not a control: a tap sends nothing', (tester) async {
      final picked = await _mount(tester, _legacyHex);
      await tester.tap(find.byType(KitSwatch).at(10));
      await tester.pump();
      expect(picked, isEmpty);
      await tester.tap(find.byType(KitSwatch).at(3));
      expect(picked, ['brick-500'], reason: 'the ten still write');
    });

    testWidgets('a write in flight holds the ten, not the current colour',
        (tester) async {
      await _mount(tester, _legacyHex, enabled: false);
      expect(_opacity(tester, find.byType(KitSwatch).at(0)), 0.5);
      expect(_opacity(tester, find.byType(KitSwatch).at(10)), 1.0);
    });

    testWidgets('one of the ten: ten, that one selected, no eleventh',
        (tester) async {
      await _mount(tester, 'plum-600');
      expect(find.byType(KitSwatch), findsNWidgets(10));
      expect(_swatch(tester, 6).selected, isTrue);
    });

    testWidgets('an unrecognised value draws the muted fallback',
        (tester) async {
      await _mount(tester, 'chartreuse', theme: AppTheme.dark);
      expect(find.byType(KitSwatch), findsNWidgets(11));
      final ctx = tester.element(find.byType(ShelfSwatches));
      expect(_fill(tester, find.byType(KitSwatch).at(10)),
          Tokens.of(ctx).fgSubtle);
    });

    testWidgets('the create form has none: a new shelf has no current colour',
        (tester) async {
      await _mount(tester, _legacyHex, showCurrent: false);
      expect(find.byType(KitSwatch), findsNWidgets(10));
    });

    test('the shelf settings ask for it, and only they do', () {
      final page = File('lib/pages/tags/shelf_page.dart').readAsStringSync();
      final sheet = File('lib/pages/tags/shelf_sheet.dart').readAsStringSync();
      expect(page, contains('showCurrent: true'),
          reason: 'the settings row is where the ruling lands');
      expect(sheet, isNot(contains('showCurrent: true')),
          reason: 'the create form has no eleventh');
    });
  });

  test('Sources says "type" where a filter matches nothing, as the reference does',
      () {
    final web = File('../NoteLetter-web/src/pages/SourcesBrowse.jsx');
    expect(web.existsSync(), isTrue, reason: 'SourcesBrowse.jsx moved');
    final line = RegExp(r'className="browse-none">([^<]+)</div>')
        .firstMatch(web.readAsStringSync())
        ?.group(1);
    expect(line, isNotNull, reason: 'the reference line was not found');
    expect(line, 'No sources of that type yet.');
    final mine =
        File('lib/pages/sources/browse_section.dart').readAsStringSync();
    expect(mine, contains("'$line'"));
    expect(mine, isNot(contains('of that kind yet')));
  });
}
