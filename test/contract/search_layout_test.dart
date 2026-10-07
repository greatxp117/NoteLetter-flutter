/// Search's panes stack below 1024px — a viewport width, the same number in
/// every client's breakpoint table (ruled 2026-10-07; screens/search.md
/// §Composition, 4.108.0, ADR-146). Tandem of web ade2891.
///
/// This client stacked on the search body's own width against 768, so a
/// 1000px window split and a 1100px window with a wide rail could stack —
/// neither a number the spec names. The decision is the pure
/// [searchPaneWidth], asserted here at the boundary and across the band where
/// the reference floors (380 + 28 + 420) do not fit beside the rail.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/pages/search_page.dart';
import 'package:flutter_app/theme/app_spacing.dart';

void main() {
  test('the number is 1024, a viewport width', () {
    expect(AppSpacing.searchStackBelow, 1024);
    expect(searchPaneWidth(viewport: 1023, body: 2000), isNull,
        reason: 'stacked below 1024, whatever the body');
    expect(searchPaneWidth(viewport: 1023.9, body: 2000), isNull);
    expect(searchPaneWidth(viewport: 1024, body: 652), isNotNull,
        reason: 'split from 1024, whatever the body');
    expect(searchPaneWidth(viewport: 390, body: 350), isNull);
  });

  test('the split keeps the reference grid where it fits, and yields where '
      'it does not', () {
    double list(double body) =>
        body - 28 - searchPaneWidth(viewport: 1440, body: body)!;
    // 988 of body (1440): the reference's grid, 400 + 560.
    expect(searchPaneWidth(viewport: 1440, body: 988), 560);
    expect(list(988), 400);
    // 900: the list keeps its 380, the pane takes the rest.
    expect(searchPaneWidth(viewport: 1440, body: 900), 492);
    expect(list(900), 380);
    // 652 (a 1024 window beside the rail): the two share the row.
    expect(searchPaneWidth(viewport: 1440, body: 652), 312);
    expect(list(652), 312);
    // Never wider than 560; the list keeps 380 unless the two share evenly.
    for (final b in [600.0, 700.0, 800.0, 1000.0, 1200.0]) {
      final p = searchPaneWidth(viewport: 1440, body: b)!;
      expect(p, lessThanOrEqualTo(560));
      expect(list(b) >= 380 || (list(b) - p).abs() < 0.5, isTrue,
          reason: 'at $b: list ${list(b)}, pane $p');
    }
  });
}
