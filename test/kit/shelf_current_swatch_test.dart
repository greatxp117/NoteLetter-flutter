import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/pages/tags/shelf_parts.dart';
import 'package:flutter_app/theme/app_colors.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/theme/tokens.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

/// The read-only "current" swatch after the twenty (ruled 2026-10-08;
/// `screens/library.md` §Shelf color; web `b70f5ea`, `.ss-swatch-current`).
///
/// A shelf whose stored colour is not one of the twenty — a legacy hex, which is
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

/// The set's size (5.41.0, ADR-196: twenty), so the swatch after it is at [n].
const n = 20;

void main() {
  test('the set is twenty', () => expect(AppColors.shelfColors, hasLength(n)));

  group('the swatch after the twenty', () {
    testWidgets('a legacy-hex shelf: twenty-one, the last one selected in its hex',
        (tester) async {
      await _mount(tester, _legacyHex);
      expect(find.byType(KitSwatch), findsNWidgets(n + 1));
      for (var i = 0; i < n; i++) {
        expect(_swatch(tester, i).selected, isFalse,
            reason: 'none of the twenty is the stored colour');
      }
      final current = _swatch(tester, n);
      expect(current.selected, isTrue);
      expect(current.readOnly, isTrue);
      expect(current.label, 'Current colour, not one of the twenty');
      expect(current.tooltip, 'Current colour');
      final last = find.byType(KitSwatch).at(n);
      expect(_fill(tester, last), AppColors.shelfColor(_legacyHex, dark: false),
          reason: 'exactly what every other surface paints');
      expect(_opacity(tester, last), 1.0, reason: 'read-only is not held');
    });

    testWidgets('it is not a control: a tap sends nothing', (tester) async {
      final picked = await _mount(tester, _legacyHex);
      await tester.tap(find.byType(KitSwatch).at(n));
      await tester.pump();
      expect(picked, isEmpty);
      await tester.tap(find.byType(KitSwatch).at(3));
      expect(picked, ['teal-500'], reason: 'the twenty still write');
    });

    testWidgets('a write in flight holds the twenty, not the current colour',
        (tester) async {
      await _mount(tester, _legacyHex, enabled: false);
      expect(_opacity(tester, find.byType(KitSwatch).at(0)), 0.5);
      expect(_opacity(tester, find.byType(KitSwatch).at(n)), 1.0);
    });

    testWidgets('one of the twenty: twenty, that one selected, no extra one',
        (tester) async {
      await _mount(tester, 'plum-600');
      expect(find.byType(KitSwatch), findsNWidgets(n));
      expect(_swatch(tester, 8).selected, isTrue);
    });

    testWidgets('an unrecognised value draws the muted fallback',
        (tester) async {
      await _mount(tester, 'chartreuse', theme: AppTheme.dark);
      expect(find.byType(KitSwatch), findsNWidgets(n + 1));
      final ctx = tester.element(find.byType(ShelfSwatches));
      expect(_fill(tester, find.byType(KitSwatch).at(n)),
          Tokens.of(ctx).fgSubtle);
    });

    // One test per theme: a second mount in the same test animates between
    // the two themes, and a single pump reads the old one.
    for (final (name, theme, map) in [
      ('light', AppTheme.light, AppColors.shelfColors),
      ('dark', AppTheme.dark, AppColors.shelfColorsDark),
    ]) {
      testWidgets('in $name the twenty paint the $name twenty (ADR-154)',
          (tester) async {
        await _mount(tester, 'plum-600', theme: theme);
        final keys = map.keys.toList();
        for (var i = 0; i < n; i++) {
          expect(_fill(tester, find.byType(KitSwatch).at(i)), map[keys[i]],
              reason: '$name ${keys[i]}');
        }
      });
    }

    testWidgets('the create form has none: a new shelf has no current colour',
        (tester) async {
      await _mount(tester, _legacyHex, showCurrent: false);
      expect(find.byType(KitSwatch), findsNWidgets(n));
    });

    test('the shelf settings ask for it, and only they do', () {
      final page = File('lib/pages/tags/shelf_page.dart').readAsStringSync();
      final sheet = File('lib/pages/tags/shelf_sheet.dart').readAsStringSync();
      expect(page, contains('showCurrent: true'),
          reason: 'the settings row is where the ruling lands');
      expect(sheet, isNot(contains('showCurrent: true')),
          reason: 'the create form has no extra swatch');
    });
  });

  // Direction D (F-141): the browse's "No sources of that type yet." is
  // retired with its chips; the catalogue narrowed to nothing says the
  // reference's line and offers its way back, verbatim.
  test('the Library says what the reference says where a filter matches nothing',
      () {
    final web = File('../NoteLetter-web/src/pages/SourcesBrowse.jsx');
    expect(web.existsSync(), isTrue, reason: 'SourcesBrowse.jsx moved');
    final m = RegExp(r'className="hx-none lx-none">([^<]+?)\s*<button[^>]*>([^<]+)</button>')
        .firstMatch(web.readAsStringSync());
    expect(m, isNotNull, reason: 'the reference line was not found');
    expect(m!.group(1), 'No volumes match.');
    expect(m.group(2), 'Show every volume');
    final mine = File('lib/pages/sources_page.dart').readAsStringSync();
    expect(mine, contains("'${m.group(1)}'"));
    expect(mine, contains("'${m.group(2)}'"));
    expect(mine, isNot(contains('of that type yet')));
  });
}
