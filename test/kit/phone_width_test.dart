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
import 'package:flutter_app/models/newsletter_settings.dart';
import 'package:flutter_app/pages/letters_page.dart';
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

class _Settings extends SettingsNotifier {
  final NewsletterSettings value;
  _Settings(this.value);
  @override
  NewsletterSettings? get newsletter => value;
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

  group('§6.8 a segmented track wraps only when its labels cannot share a line',
      () {
    for (final w in _phones) {
      testWidgets('Summary style at $w — nothing cut, lines only as needed',
          (tester) async {
        await pumpPhone(
          tester,
          w,
          KitRowList(raised: true, rows: [
            KitSettingRow(
              icon: Icons.edit_outlined,
              title: 'Summary style',
              description: 'How each new source’s summary is written.',
              below: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final d in styleDimensions)
                    KitSegmented(
                      segments: [for (final o in d.options) KitSegment(o.label)],
                      selected: 0,
                      onChanged: (_) {},
                    ),
                ],
              ),
            ),
          ]),
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
            need += tester.getSize(f).width + 20 + 2; // `.seg button` padding + gap
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
              KitSegmented(
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

  group('Letters — the latest-letter card at phone width (.next-letter)', () {
    final settings = _Settings(const NewsletterSettings(
      enabled: true,
      deliveryTime: '08:00',
      timezone: 'America/Chicago',
      frequency: 'daily',
    ));
    final latest = Newsletter.fromJson('n1', {
      'subject': 'Your NoteLetter — On Quiet Rooms',
      'status': 'sent',
      'generated_at': '2026-09-10T13:00:00Z',
      'chunk_ids': ['a', 'b', 'c'],
      'text_body': 'Three passages found each other today.',
    });
    for (final w in _phones) {
      testWidgets('at $w: the schedule wraps, the actions wrap and grow',
          (tester) async {
        await pumpPhone(
          tester,
          w,
          LatestLetterCard(
            latest: latest,
            loaded: true,
            archiveError: null,
            sending: false,
            onSend: () async {},
            onPreview: () {},
            onSettings: () {},
            sendMessage: null,
            sendError: null,
            scheduleOutcome: null,
            scheduleError: null,
            scheduleBusy: false,
            onToggleSchedule: (_) async {},
          ),
          settings: settings,
        );
        final sched = find.textContaining('CHICAGO');
        expect(cut(tester, sched), isFalse,
            reason: 'the schedule sentence was ellipsised at $w');
        expect(right(tester, sched), lessThanOrEqualTo(w - 20));

        final send = find.widgetWithText(KitButton, 'Send now');
        final preview = find.widgetWithText(KitButton, 'Preview');
        final settingsBtn = find.widgetWithText(KitButton, 'Settings');
        for (final b in [send, preview, settingsBtn]) {
          expect(right(tester, b), lessThanOrEqualTo(w - 20),
              reason: 'an action ran past a $w phone');
        }
        // Three do not share a line on a phone; the last drops, alone, and
        // `flex: 1` stretches it to the line.
        expect(tester.getTopLeft(settingsBtn).dy,
            greaterThan(tester.getTopLeft(send).dy));
        expect(tester.getTopLeft(preview).dy, tester.getTopLeft(send).dy);
        final line = right(tester, preview) - tester.getTopLeft(send).dx;
        expect(tester.getSize(settingsBtn).width, closeTo(line, 1));
        // The first line is filled too: equal shares, except that a label
        // wider than its share keeps its width (a flex item's min-content).
        expect(tester.getSize(send).width + 8 + tester.getSize(preview).width,
            closeTo(tester.getSize(settingsBtn).width, 2));
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
