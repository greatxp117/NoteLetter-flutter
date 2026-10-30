// F-64 — the web 9a84288 phone tandem, at the two widths gate:phone measures
// (390 and 320, both phones). Nothing a screenshot pair can show: the pair is
// taken on a 402pt simulator, and every defect 9a84288 fixed appeared at 320
// or was hidden under a clipping card. So the widths are asserted here, with
// the BUNDLED faces loaded — the test font draws every glyph a full em wide
// and would wrap tracks the real type fits on one line.
//
// What each group proves, against the reference:
//   · §6.8 — a segmented track wraps ONLY when its labels cannot share a line
//     (`.seg { flex-wrap: wrap }`); a track that fits never wraps.
//   · §6.6 — Sources' Order by stays whole: label, then a full-width track
//     (`.ltabs { width: 100% }` at ≤680), no label cut, nothing past the edge.
//   · Letters — the schedule sentence wraps rather than ellipsising, and the
//     actions wrap with each `flex: 1` (`.nl-actions`).
//   · Library hero — the actions are a wrapping row at their own widths
//     (`.letter-hero .actions`), never a column of full-width bars.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/models/newsletter.dart';
import 'package:flutter_app/pages/settings/summary_prompt.dart';
import 'package:flutter_app/state/settings_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

Future<void> _loadFonts() async {
  const faces = {
    'Geist': [
      'Geist-Light.ttf',
      'Geist-Regular.ttf',
      'Geist-Medium.ttf',
      'Geist-SemiBold.ttf',
      'Geist-Bold.ttf',
    ],
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

const _phones = [390.0, 320.0];

void main() {
  setUpAll(_loadFonts);

  /// Mounts [child] in a real page frame (KitPage: the §1.5 gutter) on a phone
  /// [width] wide. Any RenderFlex overflow fails the test by itself.
  Future<void> pumpPhone(WidgetTester tester, double width, Widget child,
      {SettingsNotifier? settings}) async {
    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    Widget app = MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: KitPage(child: child)),
    );
    if (settings != null) {
      app = ChangeNotifierProvider<SettingsNotifier>.value(
          value: settings, child: app);
    }
    await tester.pumpWidget(app);
    await tester.pump(const Duration(milliseconds: 200));
  }

  bool cut(WidgetTester tester, Finder f) =>
      tester.renderObject<RenderParagraph>(f).didExceedMaxLines;

  double top(WidgetTester tester, String label) =>
      tester.getTopLeft(find.text(label)).dy;

  double right(WidgetTester tester, Finder f) => tester.getTopRight(f).dx;

  // F-144 (direction D, settings.md §Composition): the Summary style's three
  // dimensions are §34 Switches that fill their row and, on a narrow phone,
  // wrap to a second line rather than run past the page (`.set-sw`) — in
  // Settings' ruled register, beside the 38px plate.
  group('§34 a Summary-style Switch wraps only when its labels cannot share a '
      'line', () {
    for (final w in _phones) {
      testWidgets('Summary style at $w — nothing cut, lines only as needed',
          (tester) async {
        await pumpPhone(
          tester,
          w,
          KitDSetScope(
            child: KitRowList(rows: [
              KitSettingRow(
                icon: Icons.edit_outlined,
                title: 'Summary style',
                description: 'How each new source’s summary is written.',
                below: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final d in styleDimensions)
                      KitWrapSwitch<String>(
                        label: d.label,
                        value: d.options.first.id,
                        options: [
                          for (final o in d.options)
                            KitSlideOption(o.id, o.label),
                        ],
                        onChanged: (_) {},
                      ),
                  ],
                ),
              ),
            ]),
          ),
        );
        for (final d in styleDimensions) {
          final tops = <double>{};
          var need = 0.0;
          for (final o in d.options) {
            final f = find.text(o.label);
            expect(cut(tester, f), isFalse, reason: '${o.label} cut at $w');
            expect(right(tester, f), lessThanOrEqualTo(w),
                reason: '${o.label} past a $w phone');
            tops.add(tester.getTopLeft(f).dy);
            need += tester.getSize(f).width + 22 + 2; // `0 11px` + the gap
          }
          // The track's inner width is the widest line any label sits on.
          final track = tester
              .getSize(find
                  .ancestor(
                      of: find.text(d.options.first.label),
                      matching: find.byType(LayoutBuilder))
                  .first)
              .width;
          if (need - 2 <= track) {
            expect(tops.length, 1,
                reason: '${d.label} fits one line at $w and must not wrap');
          } else {
            expect(tops.length, greaterThan(1),
                reason: '${d.label} cannot fit one line at $w');
            // The reference's wrap: the LAST option drops, alone.
            expect(top(tester, d.options.last.label),
                greaterThan(top(tester, d.options.first.label)));
          }
        }
      });
    }
  });

  group('§6.6 Sources — Order by wraps as a whole at phone width', () {
    const sorts = ['Recent', 'Type', 'Title', 'Passages'];
    for (final w in _phones) {
      testWidgets('at $w: label, then the full track on its own line',
          (tester) async {
        await pumpPhone(
          tester,
          w,
          KitControlBar(
            filters: [
              for (final c in ['All', 'Unread', 'PDFs', 'Articles', 'Notes'])
                KitFilterChip(c, count: 1, selected: c == 'All', onPressed: () {}),
            ],
            trailing: [
              const KitControlLabel('Order by'),
              KitSegmented(groupLabel: 'Group', 
                segments: [for (final s in sorts) KitSegment(s)],
                selected: 0,
                onChanged: (_) {},
              ),
            ],
          ),
        );
        for (final s in sorts) {
          expect(cut(tester, find.text(s)), isFalse, reason: '$s cut at $w');
          expect(right(tester, find.text(s)), lessThanOrEqualTo(w - 20));
        }
        // Four sorts share one line under the label.
        expect({for (final s in sorts) top(tester, s)}.length, 1);
        expect(top(tester, 'Recent'),
            greaterThan(top(tester, 'ORDER BY') + 8));
      });
    }
  });

  // Search on a phone (4.108.0, ADR-146; search.md §Phone): the kind chips
  // are ONE row that scrolls sideways under the pinned header, the Segmented
  // controls on their own line beneath — not §6.6's column of wrapping chips.
  group('§6.6 Search — the kind chips are one scrolling row on a phone', () {
    const kinds = ['All sources', 'Books & PDFs', 'My notes', 'Web',
        'YouTube', 'Instagram', 'TikTok', 'Audio', 'Video'];
    for (final w in _phones) {
      testWidgets('at $w: one row, scrolling; the modes beneath it',
          (tester) async {
        await pumpPhone(
          tester,
          w,
          KitControlBar(
            scrollChips: true,
            filters: [
              for (final k in kinds)
                KitFilterChip(k, selected: k == 'All sources', onPressed: () {}),
            ],
            trailing: [
              KitSegmented(groupLabel: 'Group', 
                segments: const [KitSegment('Passages'), KitSegment('Cohesive')],
                selected: 0,
                onChanged: (_) {},
              ),
            ],
          ),
        );
        final rows = {
          for (final k in kinds)
            if (find.text(k).evaluate().isNotEmpty) top(tester, k),
        };
        expect(rows.length, 1, reason: 'one row at $w, never a wrapped column');
        final scroller = find.ancestor(
            of: find.text('All sources'),
            matching: find.byWidgetPredicate((x) =>
                x is SingleChildScrollView &&
                x.scrollDirection == Axis.horizontal));
        expect(scroller, findsOneWidget,
            reason: 'a declared horizontal scroller (§1.4)');
        expect(top(tester, 'Passages'), greaterThan(top(tester, 'All sources')),
            reason: 'the Segmented controls keep a line of their own beneath');
        // A real gesture moves it (only a gesture proves scrollability).
        final before = tester.getTopLeft(find.text('All sources')).dx;
        await tester.drag(scroller, const Offset(-200, 0));
        await tester.pump();
        expect(tester.getTopLeft(find.text('All sources')).dx, lessThan(before));
      });
    }
    testWidgets('every other bar still wraps its chips', (tester) async {
      await pumpPhone(
        tester,
        320,
        KitControlBar(filters: [
          for (final k in kinds)
            KitFilterChip(k, selected: k == 'All sources', onPressed: () {}),
        ]),
      );
      expect({for (final k in kinds) top(tester, k)}.length, greaterThan(1));
    });
  });

  // Direction D (F-144, screens/letters.md §Composition *Letters*): the latest
  // letter is the letter card under its kicker; the schedule and Send now left
  // it for the masthead's folio and the page's action.
  group('Letters — the latest letter at phone width (.ed-letter.dp-latest)', () {
    final latest = Newsletter.fromJson('n1', {
      'subject': 'Your NoteLetter — On Quiet Rooms',
      'status': 'sent',
      'generated_at': '2026-09-10T13:00:00Z',
      'chunk_ids': ['a', 'b', 'c'],
      'text_body': 'NOTELETTER Vol. I · No. 3 · Thursday',
      'html_body': '<div data-nl-letterhead="1">'
          '<div><h2>The crowded pan</h2><blockquote>Brown the meat before '
          'adding liquid, and never crowd the pan.</blockquote></div>'
          '<p data-nl-lede="1">Three passages found each other today, and '
          'each of them is about waiting well.</p></div>',
    });
    for (final w in _phones) {
      testWidgets('at $w: the kicker\'s figures drop, trailing; the actions '
          'stay on the phone', (tester) async {
        await pumpPhone(
          tester,
          w,
          KitLatestLetter(
            state: KitLatestState.built,
            parts: kitLetterParts(latest),
            figures: letterFigures(latest),
            onRead: () {},
            onSettings: () {},
          ),
        );
        expect(tester.takeException(), isNull);
        final lead = find.text('THE LETTER · NO. 3');
        final figs = find.text('3 PASSAGES · ~4 MIN READ');
        expect(cut(tester, figs), isFalse);
        expect(tester.getTopLeft(figs).dy,
            greaterThan(tester.getTopLeft(lead).dy),
            reason: 'margin-left:auto drops the figures to their own line');
        expect(right(tester, figs), lessThanOrEqualTo(w - 20 + 0.5));
        for (final b in [
          find.widgetWithText(KitButton, 'Read the letter'),
          find.widgetWithText(KitButton, 'Letter settings'),
        ]) {
          expect(right(tester, b), lessThanOrEqualTo(w - 20),
              reason: 'an action ran past a $w phone');
        }
      });
    }
  });

  group('Library — the letter hero at phone width (.letter-hero)', () {
    for (final w in _phones) {
      testWidgets('at $w: actions are a wrapping row at their own widths',
          (tester) async {
        await pumpPhone(
          tester,
          w,
          KitHeroCard(
            title: 'A *Letter*',
            marker: 'Thu 10 Sep',
            standfirst: 'Three passages found each other today.',
            stats: const [KitStat('3', 'Passages'), KitStat('12', 'Found')],
            actions: [
              KitButton.primary('Preview & send',
                  icon: Icons.mail_outlined, onPressed: () {}),
              KitButton.ghost('Schedule',
                  icon: Icons.schedule, onPressed: () {}),
            ],
          ),
        );
        final send = find.widgetWithText(KitButton, 'Preview & send');
        final sched = find.widgetWithText(KitButton, 'Schedule');
        for (final b in [send, sched]) {
          expect(right(tester, b), lessThanOrEqualTo(w - 20),
              reason: 'an action ran past a $w phone');
        }
        // Side by side when they fit (390); at 320 the second drops to its
        // own line — at its OWN width, never a full-width bar, and never
        // sheared off the card (what 9a84288 fixed on web).
        if (w >= 390) {
          expect(tester.getTopLeft(sched).dy, tester.getTopLeft(send).dy);
          expect(tester.getTopLeft(sched).dx, greaterThan(right(tester, send)));
        } else {
          expect(tester.getTopLeft(sched).dy,
              greaterThan(tester.getBottomLeft(send).dy - 1));
        }
        final card = tester.getSize(find.byType(KitHeroCard)).width;
        expect(tester.getSize(sched).width, lessThan(card / 2));
        expect(tester.getSize(send).width, lessThan(card * 0.75));
      });
    }
  });
}
