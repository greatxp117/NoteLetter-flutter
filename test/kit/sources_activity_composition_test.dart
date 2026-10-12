// F-79 — what the 2026-10-05 Sources, folder-picker and Activity pairs found,
// against the reference (SourcesBrowse.jsx `.empty-dropzone`, CloudFilePicker
// `.proc-error-actions` and its native checkbox, ActivityView's timeline,
// app-kit.css `.filebadge`).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/pages/sources/cloud_picker.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/theme/tokens.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

Future<void> _pump(WidgetTester tester, Widget w, {double width = 402}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: SingleChildScrollView(child: w)),
  ));
}

void main() {
  testWidgets('the drop zone draws the upload tray at its leading edge',
      (tester) async {
    await _pump(
        tester,
        const KitDropZone(
            icon: KitUploadGlyph.icon,
            title: 'Drop files, or tap to add a few',
            help: 'PDF'));
    final glyph = tester.getRect(find.byType(KitUploadGlyph));
    final zone = tester.getRect(find.byType(KitDropZone));
    expect(glyph.left - zone.left, lessThan(40),
        reason: '`.dz-feather` is a block `text-align` does not centre');
    expect(find.byType(Icon), findsNothing,
        reason: 'the stroked tray, not Material\'s filled arrow');
  });

  testWidgets('a picker checkbox is the reference\'s 13px box', (tester) async {
    var on = false;
    await _pump(
        tester,
        StatefulBuilder(
          builder: (context, set) => CloudPickerCheck(
              value: on, label: 'Import Docs', onToggle: () => set(() => on = !on)),
        ));
    expect(find.byType(Checkbox), findsNothing);
    final box = find.descendant(
        of: find.byType(KitCheckbox), matching: find.byType(Container));
    expect(tester.getSize(box.first), const Size(13, 13));
    await tester.tap(find.byType(KitCheckbox));
    await tester.pump();
    expect(on, isTrue);
    final deco = tester.widget<Container>(box.first).decoration as BoxDecoration;
    expect(deco.color, Tokens.light.accent);
  });

  testWidgets('on a phone the picker\'s confirm and Cancel sit at the trailing '
      'edge', (tester) async {
    await _pump(
        tester,
        CloudPickerFoot(
            confirmLabel: 'Import 0 items',
            onConfirm: null,
            onCancel: () {},
            busy: false));
    final cancel = tester.getRect(find.text('Cancel'));
    expect(cancel.right, greaterThan(402 - 40),
        reason: '`.proc-error-actions { justify-content: flex-end }` ≤720');
  });

  testWidgets('platform badges take no tint; pdf and web keep theirs',
      (tester) async {
    BoxDecoration decoOf(String kind) => tester
        .widget<Container>(find
            .descendant(
                of: find.byWidgetPredicate(
                    (w) => w is KitFileBadge && w.kind == kind),
                matching: find.byType(Container))
            .first)
        .decoration as BoxDecoration;
    await _pump(
        tester,
        const Wrap(children: [
          KitFileBadge('youtube'),
          KitFileBadge('podcast'),
          KitFileBadge('pdf'),
          KitFileBadge('web'),
        ]));
    expect(decoOf('youtube').color, const Color(0x00000000));
    expect(decoOf('podcast').color, const Color(0x00000000));
    expect(decoOf('pdf').color, Tokens.light.accentChipBg);
    expect(decoOf('web').color, Tokens.light.surfaceSunken);
  });

  testWidgets('the timeline spine runs through the nodes\' centres',
      (tester) async {
    await _pump(
        tester,
        KitTimeline(rows: [
          KitTimelineRow(
            icon: Icons.check,
            tone: KitNodeTone.sage,
            chip: 'INDEXED',
            subject: 'Quarterly Tax Summary',
            time: 'Just now',
          ),
        ]));
    final list = tester.getRect(find.byType(KitTimeline));
    final node = tester.getRect(find.byIcon(Icons.check));
    expect(node.center.dx - list.left, closeTo(16, 1.5),
        reason: 'the row\'s -12 inset puts the 32 node flush, centred on 16');
  });

  // F-90 (6): a folder's README status is web's ReadmeChip — its own words,
  // and an unknown status drawn as pending, never as its raw token.
  testWidgets('the README chip says each status in the reference\'s words',
      (tester) async {
    await _pump(
        tester,
        const Wrap(children: [
          KitReadmeChip('written'),
          KitReadmeChip('user_modified'),
          KitReadmeChip('error'),
          KitReadmeChip('pending'),
          KitReadmeChip('something_new'),
        ]));
    expect(find.text('README written'), findsOneWidget);
    expect(find.text('README edited by you'), findsOneWidget);
    expect(find.text('README error'), findsOneWidget);
    expect(find.text('README pending'), findsNWidgets(2));
    expect(find.textContaining('something_new'), findsNothing);
  });
}
