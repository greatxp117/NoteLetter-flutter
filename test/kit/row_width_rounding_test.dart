/// F-112's class, audited (TODO's "audit Flutter row layouts for width
/// rounding"; lane flutter3, 2026-11-11): a kit row that sizes its children
/// to their content must give every label at least its natural width, or a
/// real font's fractional advance — or a part drawn beside the label that the
/// measurement left out — clips it. F-112 found it on KitActionFlow ("Send now
/// · 0:…"; action_flow_wait_test.dart holds that row). These are the other
/// rows that measure their children and plan lines from the measure:
///
/// * §6.8 KitSegmented, filling (`_segLines`) — sort, frequency, camera roll;
/// * §6.8 KitSegmentedMulti, in D (`_SegMultiD`) and outside it — the
///   notification levels;
/// * §34 KitWrapSwitch — the summary style's dimensions, a channel's type.
///
/// Each is swept from 280 to 380 px in quarter pixels with the app's own
/// faces (the test font's glyphs are whole pixels and can never show it), in
/// every state that adds a part beside a label — §6.1's busy mark on each
/// segment in turn — and asserts no one-line label is cut.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/pages/settings/summary_prompt.dart'
    show styleDimensions;
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

Future<void> _loadRealFonts() async {
  const faces = {
    'Geist': ['Geist-Regular.ttf', 'Geist-Medium.ttf', 'Geist-SemiBold.ttf'],
    'Geist Mono': ['GeistMono-Regular.ttf', 'GeistMono-Medium.ttf'],
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

/// Every one-line label under the row that is drawn narrower than its text.
List<String> _cut(WidgetTester tester) => [
      for (final e in find.byType(RichText).evaluate())
        if (e.renderObject case final RenderParagraph p
            when (p.maxLines == 1 || !p.softWrap) &&
                (p.didExceedMaxLines ||
                    p.getMaxIntrinsicWidth(double.infinity) >
                        p.size.width + 0.001))
          p.text.toPlainText(),
    ];

/// The row at every quarter pixel from 280 to 380: each label it cut, with
/// the widths it was cut at as runs (`Weekdays 280.0–285.75 (24)`).
Future<List<String>> _sweep(
  WidgetTester tester,
  Widget Function() row, {
  bool d = false,
}) async {
  final cut = <String, List<double>>{};
  for (var w = 280.0; w <= 380.0; w += 0.25) {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: w,
            child: d ? KitDScope(child: row()) : row(),
          ),
        ),
      ),
    ));
    await tester.pump();
    for (final c in _cut(tester)) {
      (cut[c] ??= []).add(w);
    }
  }
  return [
    for (final MapEntry(key: label, value: ws) in cut.entries)
      '$label ${_runs(ws).join(', ')} (${ws.length})',
  ];
}

List<String> _runs(List<double> ws) {
  final out = <String>[];
  var start = ws.first, prev = ws.first;
  for (final w in ws.skip(1)) {
    if (w - prev > 0.25 + 1e-9) {
      out.add(start == prev ? '$start' : '$start–$prev');
      start = w;
    }
    prev = w;
  }
  out.add(start == prev ? '$start' : '$start–$prev');
  return out;
}

List<KitSegment> _segments(List<String> labels, int? busy) => [
      for (var i = 0; i < labels.length; i++)
        KitSegment(labels[i], busy: i == busy),
    ];

const _levels = ['Errors', 'Warnings', 'Successes', 'Info'];

void main() {
  setUpAll(_loadRealFonts);

  group('§6.8 KitSegmented, filling', () {
    for (final (name, labels) in [
      ('a folder\'s sync frequency', ['Hourly', 'Daily', 'Weekly']),
      ('the letter\'s frequency', ['Daily', 'Weekdays', 'Weekly']),
      ('the camera roll', ['Automatically', 'Ask me first']),
    ]) {
      for (final busy in [null, for (var i = 0; i < labels.length; i++) i]) {
        testWidgets(
            '$name${busy == null ? '' : ', ${labels[busy]} busy'}: no label '
            'is cut', (tester) async {
          final cut = await _sweep(
            tester,
            () => KitSegmented(
              groupLabel: name,
              expand: true,
              segments: _segments(labels, busy),
              selected: 0,
              onChanged: (_) {},
            ),
          );
          expect(cut, isEmpty);
        });
      }
    }
  });

  group('§6.8 KitSegmentedMulti — the notification levels', () {
    for (final d in [true, false]) {
      for (final busy in [null, for (var i = 0; i < _levels.length; i++) i]) {
        testWidgets(
            '${d ? 'in D' : 'outside D'}'
            '${busy == null ? '' : ', ${_levels[busy]} busy'}: no label is '
            'cut', (tester) async {
          final cut = await _sweep(
            tester,
            () => KitSegmentedMulti(
              groupLabel: 'Levels',
              expand: true,
              segments: _segments(_levels, busy),
              selected: const {0, 1},
              onToggle: (_) {},
            ),
            d: d,
          );
          expect(cut, isEmpty);
        });
      }
    }
  });

  group('§34 KitWrapSwitch', () {
    for (final dim in styleDimensions) {
      testWidgets('the summary style\'s ${dim.label}: no label is cut',
          (tester) async {
        final cut = await _sweep(
          tester,
          () => KitWrapSwitch<String>(
            label: dim.label,
            value: dim.options.first.id,
            options: [
              for (final o in dim.options) KitSlideOption(o.id, o.label),
            ],
            onChanged: (_) {},
          ),
          d: true,
        );
        expect(cut, isEmpty);
      });
    }

    testWidgets('a channel\'s type, with a glyph: no label is cut',
        (tester) async {
      final cut = await _sweep(
        tester,
        () => KitWrapSwitch<String>(
          label: 'Type',
          value: 'onscreen',
          options: const [
            KitSlideOption('onscreen', 'On-screen', icon: Icons.notifications),
            KitSlideOption('email', 'Email', icon: Icons.mail_outline),
            KitSlideOption('push', 'Push', icon: Icons.phone_iphone),
          ],
          onChanged: (_) {},
        ),
        d: true,
      );
      expect(cut, isEmpty);
    });
  });
}
