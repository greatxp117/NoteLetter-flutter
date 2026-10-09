/// The shelf-colour vocabulary (contract 2.15.0, ADR-022;
/// `screens/library.md` §Shelf color).
///
/// Read **both ways**, because a vocabulary has two halves and nothing ties
/// them together on its own: the token map is what a swatch PAINTS and the
/// label map is what it is ANNOUNCED as. A token with no label is a swatch a
/// reader cannot name; a label with no token is a swatch that paints nothing.
/// That is the `docKind()`/`KIND_ORDER` defect in miniature — a kind the
/// renderer never listed, with no error anywhere.
library;

import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/theme/app_colors.dart';

/// The closed set, in the spec's order, written out here rather than derived
/// from the app's own map — a test that reads the thing it is checking asserts
/// nothing. The ORDER is part of the contract: clients "offer exactly these
/// ten, in this order".
const specOrder = <String, String>{
  'sage-500': 'Moss',
  'sage-700': 'Deep moss',
  'brick-400': 'Vermilion',
  'brick-500': 'Brick',
  'brick-700': 'Oxblood',
  'plum-500': 'Plum',
  'plum-600': 'Deep plum',
  'ink-300': 'Slate',
  'ink-400': 'Deep slate',
  'ink-500': 'Graphite',
};

void main() {
  test('the ten tokens are the spec\'s ten, in the spec\'s order', () {
    expect(AppColors.shelfColors.keys.toList(), specOrder.keys.toList());
  });

  test('every token has its reader-facing name, and no name stands alone', () {
    expect(AppColors.shelfColorLabels.keys.toList(), specOrder.keys.toList());
    expect(AppColors.shelfColorLabels, specOrder);
  });

  test('every offered token resolves to a colour', () {
    for (final name in specOrder.keys) {
      expect(AppColors.shelfColor(name, dark: false), isNotNull, reason: name);
      expect(AppColors.shelfColor(name, dark: true), isNotNull, reason: name);
    }
  });

  // 4.117.0 (ADR-154): a name paints per theme. The dark ten are read from the
  // spec's table (`design-tokens.md`, the `--shelf-{name}` rows), not from a
  // copy here, so a value the spec moves turns this red.
  test('in dark, each name paints the spec\'s dark value', () {
    final md = File('../NoteLetter-contracts/spec/design-tokens.md');
    expect(md.existsSync(), isTrue, reason: 'design-tokens.md moved');
    final rows = <String, Color>{};
    for (final m in RegExp(r'^\| `--shelf-([a-z]+-\d+)` \|[^|]*\|([^|]*)\|',
            multiLine: true)
        .allMatches(md.readAsStringSync())) {
      final hex = RegExp(r'#([0-9A-Fa-f]{6})').allMatches(m.group(2)!).last;
      rows[m.group(1)!] = Color(int.parse('FF${hex.group(1)}', radix: 16));
    }
    expect(rows.keys.toList(), specOrder.keys.toList(),
        reason: 'the table names the ten, in order');
    expect(AppColors.shelfColorsDark.keys.toList(), specOrder.keys.toList());
    for (final name in specOrder.keys) {
      expect(AppColors.shelfColor(name, dark: true), rows[name], reason: name);
      expect(AppColors.shelfColor(name, dark: false), AppColors.shelfColors[name],
          reason: '$name: light is unchanged');
    }
  });

  test('a legacy hex renders as-is — never fail on a stored colour', () {
    // Every auto-created tag holds `#6B7280` and there is no backfill, so this
    // is not a legacy path, it is most of production.
    expect(AppColors.shelfColor('#6B7280', dark: false), isNotNull);
    expect(AppColors.shelfColor('6B7280', dark: false), isNotNull);
    expect(AppColors.shelfColor('#6B7280', dark: true),
        AppColors.shelfColor('#6B7280', dark: false),
        reason: 'a hex paints the same in both themes');
  });

  test('an unrecognised value falls back, rather than throwing', () {
    // Null is the caller's cue to use its own muted colour (§6.2) — what must
    // not happen is an exception on a value the backend is free to store.
    for (final dark in [false, true]) {
      expect(AppColors.shelfColor('var(--sage-500)', dark: dark), isNull);
      expect(AppColors.shelfColor('chartreuse', dark: dark), isNull);
      expect(AppColors.shelfColor(null, dark: dark), isNull);
    }
  });
}
