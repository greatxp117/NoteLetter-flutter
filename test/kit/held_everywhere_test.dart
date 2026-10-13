/// Held is the look of EVERY control that cannot be pressed right now
/// (component-kit §6.1 State — Held; ruled 2026-10-13, Xavier took the
/// recommendation). Until then only sends and confirms were held: a switch
/// with no handler drew exactly as a live one, a disabled segment, stepper or
/// setting link kept its strength or only greyed its text, and the filter
/// chip, shelf select, speed-read controls and the rail's entry actions each
/// dimmed by a number of their own (0.4, 0.55).
///
/// The widget tests prove the kit controls (the setting link's are in
/// `setting_link_held_test.dart`); the sweep reads `lib/` so a new
/// control cannot pick its own number (a hand list cannot assert the list).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/theme/app_spacing.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

Widget _app(Widget child) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: Center(child: child)),
    );

/// The opacity of the outermost [Opacity] under [of] — 1 when there is none.
double _opacity(WidgetTester tester, Finder of) {
  final found = find.descendant(of: of, matching: find.byType(Opacity));
  if (found.evaluate().isEmpty) return 1;
  return tester.widget<Opacity>(found.first).opacity;
}

void main() {
  testWidgets('a switch with no handler is held; a live one is full',
      (tester) async {
    await tester.pumpWidget(_app(KitSwitch(value: true, onChanged: (_) {})));
    expect(_opacity(tester, find.byType(KitSwitch)), 1);
    await tester.pumpWidget(_app(const KitSwitch(value: true)));
    expect(_opacity(tester, find.byType(KitSwitch)), AppSpacing.heldOpacity);
  });

  testWidgets('a segmented track with no handler holds every segment',
      (tester) async {
    const segs = [KitSegment('Low'), KitSegment('Normal'), KitSegment('High')];
    await tester.pumpWidget(_app(
        KitSegmented(segments: segs, selected: 1, onChanged: (_) {})));
    expect(find.descendant(
            of: find.byType(KitSegmented), matching: find.byType(Opacity)),
        findsNothing);
    await tester.pumpWidget(
        _app(const KitSegmented(segments: segs, selected: 1)));
    final held = tester.widgetList<Opacity>(find.descendant(
        of: find.byType(KitSegmented), matching: find.byType(Opacity)));
    expect(held.length, segs.length, reason: 'the selected one included');
    expect(held.every((o) => o.opacity == AppSpacing.heldOpacity), isTrue);
  });

  testWidgets('a filter chip that cannot be pressed is held, not 0.4',
      (tester) async {
    await tester.pumpWidget(_app(const KitFilterChip('Podcasts', count: 0)));
    expect(_opacity(tester, find.byType(KitFilterChip)),
        AppSpacing.heldOpacity);
    await tester.pumpWidget(
        _app(KitFilterChip('Podcasts', count: 3, onPressed: () {})));
    expect(_opacity(tester, find.byType(KitFilterChip)), 1);
  });

  testWidgets('a stepper at its bound holds that button whole',
      (tester) async {
    await tester.pumpWidget(_app(
        KitStepper(value: 0, min: 0, max: 23, onChanged: (_) {})));
    final ops = tester
        .widgetList<Opacity>(find.descendant(
            of: find.byType(KitStepper), matching: find.byType(Opacity)))
        .map((o) => o.opacity)
        .toList();
    expect(ops, [AppSpacing.heldOpacity, 1],
        reason: '− is held at the minimum, + is live');
  });

  testWidgets('a swatch whose write is in flight is held by the token',
      (tester) async {
    await tester.pumpWidget(
        _app(const KitSwatch(color: Color(0xFF888888), label: 'sage-500')));
    expect(_opacity(tester, find.byType(KitSwatch)), AppSpacing.heldOpacity);
  });

  test('no control in lib/ dims a cannot-press state by a number of its own',
      () {
    // `enabled ? 1 : 0.4`, `onTap == null ? 0.4 : 1`, `disabled ? 0.55 : 1` …
    // A MUTED state (a skipped part, an unchecked section, an inactive
    // folder, an inherited chip) is not held and keeps its own figure; its
    // condition is not one of these names.
    final cond = RegExp(
        r'opacity:\s*\(?\s*(?:!?\s*(?:widget\.)?(?:enabled|disabled|busy|_busy|saving|_saving|held|working|waiting)\b|(?:widget\.)?on(?:Tap|Pressed|Changed)\s*[!=]=\s*null)[^,;]{0,40}?\?\s*(?:0?\.\d+|1(?:\.0)?)\s*:\s*(?:0?\.\d+|1(?:\.0)?)');
    // The pattern must catch what it is for — the shapes this sweep removed.
    for (final old in const [
      'opacity: enabled ? 1 : 0.4,',
      'opacity: widget.enabled ? 1 : 0.4,',
      'opacity: onTap == null ? 0.4 : 1,',
      'opacity: disabled ? 0.4 : 1,',
      'opacity: onTap == null && !readOnly ? 0.5 : 1,',
    ]) {
      expect(cond.hasMatch(old), isTrue, reason: old);
    }
    expect(cond.hasMatch('opacity: part.skip ? 0.45 : 1,'), isFalse,
        reason: 'a muted state is not held');
    final offenders = <String>[];
    var seen = 0;
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final src = f.readAsStringSync();
      for (final m in cond.allMatches(src)) {
        final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
        offenders.add('${f.path}:$line ${m.group(0)}');
      }
      seen += RegExp(r'\?\s*AppSpacing\.heldOpacity|AppSpacing\.heldOpacity\s*:')
          .allMatches(src)
          .length;
    }
    expect(seen, greaterThanOrEqualTo(15),
        reason: 'the held sites, each at the token');
    expect(offenders, isEmpty);
  });
}
