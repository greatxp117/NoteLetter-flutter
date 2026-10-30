// F-146: the camera roll's D parts (lib/widgets/kit/kit_d_camera.dart) render
// in both themes, on a phone and wider, with no overflow; the flow's frame
// is the whole screen on a phone and a sheet at most 560 wide beyond it; the
// dates read as the spec writes them.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

void main() {
  Widget page() => KitFlowFrame(
        onEscape: () {},
        top: KitFlowTop(label: 'Camera roll · 2 of 4', progress: 0.5, onClose: () {}),
        body: KitFlowBody(children: [
          const KitFlowMast(
            folio: 'Correspondence · Camera roll',
            title: 'The Pages in Your Camera Roll',
            stand: 'Most of us photograph what we mean to read later.',
          ),
          const KitFlowLabel('How it reads your photos'),
          const KitFlowRows(rows: [
            KitFlowRow(number: 1, title: 'On your phone first', sub: 'Each photo is read here.', strong: true, top: true),
          ]),
          KitFlowRadio(label: 'The last year', count: '1,284 photos', selected: true, onTap: () {}),
          const KitFlowRadio(label: 'Everything', selected: false),
          const KitFlowBig(figure: '312', label: 'of 1,284 photos'),
          const KitFlowBar(value: 0.25),
          const KitFlowFigures(figures: [('9', 'for your review'), ('1,229', 'passed over'), ('0', 'waiting for iCloud')]),
          KitFlowRow(
            lead: KitPhotoTile(photoId: 'p', load: () async => null),
            title: 'Screenshot',
            sub: 'Taken 14 March',
            trail: 'For your review',
            accent: true,
          ),
          const KitFlowSummary('Filed 46 · Waiting 9 · Passed over 1,229'),
          KitPhotoTile(photoId: 'q', load: () async => null, large: true, label: 'Taken on 14 March'),
          const KitFlowKicker(kicker: 'Photo with text', heading: 'Taken on 14 March'),
          const KitFlowText.note('The look back keeps everything it finds for you to see first.'),
          const KitFlowSlot('Once it is filed, NoteLetter reads it and shelves it as it does anything you add.'),
          const KitFlowDots(count: 9, current: 2),
          const KitFlowStatus('On · looked 10m ago'),
          KitFlowReach(text: 'The last year · done', links: [KitHxLink('Look further back', onTap: () {})]),
          KitFlowPanelFoot(children: [
            KitFlowPanelButton('Look now', icon: Icons.refresh, onTap: () {}),
            KitFlowPanelButton('Turn off the camera roll', danger: true, onTap: () {}),
          ]),
        ]),
        foot: [
          KitFlowButton.primary('Allow access', icon: Icons.photo_camera_outlined, onTap: () {}),
          KitFlowGhosts(children: [
            KitFlowButton.ghost('File all 9', onTap: () {}),
            const KitFlowButton.ghost('Pass over'),
          ]),
          KitFlowButton.link('Back', onTap: () {}),
        ],
      );

  for (final (name, theme) in [('light', AppTheme.light), ('dark', AppTheme.dark)]) {
    for (final size in const [Size(402, 874), Size(1280, 900)]) {
      testWidgets('the flow\'s parts, $name, ${size.width.toInt()} wide', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(theme: theme, home: Scaffold(body: page())));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.takeException(), isNull);
        expect(find.text('CAMERA ROLL · 2 OF 4'), findsOneWidget);
        expect(find.text('CORRESPONDENCE · CAMERA ROLL'), findsOneWidget);
        final frame = tester.getSize(find.byType(KitGround).first);
        if (size.width <= 680) {
          expect(frame.width, size.width, reason: 'the whole screen on a phone');
        } else {
          expect(frame.width, 560, reason: 'a sheet at most 560 wide');
        }
      });
    }
  }

  test('the camera roll\'s dates', () {
    final now = DateTime(2026, 10, 30);
    expect(kitDayMonth(DateTime(2026, 3, 14), now: now), '14 March');
    expect(kitDayMonth(DateTime(2025, 3, 14), now: now), '14 March 2025');
    expect(kitDayMonth(DateTime(2026, 3, 14), year: true, now: now), '14 March 2026');
    final at = DateTime(2026, 10, 30, 12);
    expect(kitAgo(at, at.add(const Duration(seconds: 20))), 'just now');
    expect(kitAgo(at, at.add(const Duration(minutes: 10))), '10m ago');
    expect(kitAgo(at, at.add(const Duration(hours: 3))), '3h ago');
    expect(kitAgo(at, at.add(const Duration(days: 2))), '2d ago');
    expect(kitAgo(DateTime(2026, 3, 14), DateTime(2026, 10, 30)), 'Mar 14');
  });
}
