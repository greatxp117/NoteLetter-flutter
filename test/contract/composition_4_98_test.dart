/// The 4.98.0 composition tandem (ADR-131; CHANGELOG 4.98.0 tandem 3c–3g):
/// the §Composition lines rewritten to what web draws, asserted where a frame
/// cannot reach — a processing card per state, the letter row at both widths,
/// the header badge's scale and the sync chips' spelling.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/pages/sources/browse_section.dart';
import 'package:flutter_app/pages/sources/folder_contents.dart';
import 'package:flutter_app/state/activity_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

Document _doc(String status, Map<String, dynamic> extra) =>
    Document.fromJson('doc-1', {
      'user_id': 'u1',
      'title': 'Field notes',
      'type': 'pdf',
      'status': status,
      ...extra,
    });

Future<void> _pumpRow(WidgetTester tester, Document doc) async {
  await tester.pumpWidget(ChangeNotifierProvider(
    create: (_) => ActivityNotifier(),
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
          body: SingleChildScrollView(child: ProcessingRow(doc: doc))),
    ),
  ));
  // Bounded: a working row's spinner and bar never settle.
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _at(WidgetTester tester, double width, Widget child) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light, home: Scaffold(body: Center(child: child))));
}

void main() {
  test('§6.4: the chapter opening lead badge is 34×42, mono 9', () {
    expect(KitBadgeSize.header.width, 34);
    expect(KitBadgeSize.header.height, 42);
    expect(KitBadgeSize.header.fontSize, 9);
  });

  group('sources.md: a processing document is a card, its stage a pill', () {
    testWidgets('queued: the stage is the pill, the subtitle is the type',
        (tester) async {
      await _pumpRow(tester, _doc('queued', {}));
      expect(find.byType(KitProcCard), findsOneWidget);
      final pill = tester.widget<KitProcPill>(find.byType(KitProcPill));
      expect(pill.label, 'Queued');
      expect(pill.tone, KitProcTone.wait);
      expect(find.text('pdf'), findsOneWidget);
      expect(find.text('Queued'), findsNothing,
          reason: 'the stage lives in the pill, never the subtitle');
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('extracting works, with a spinner', (tester) async {
      await _pumpRow(tester,
          _doc('processing', {'processing_stage': 'extraction'}));
      final pill = tester.widget<KitProcPill>(find.byType(KitProcPill));
      expect(pill.label, 'Extracting text');
      expect(pill.tone, KitProcTone.work);
      expect(
          find.descendant(
              of: find.byType(KitProcPill),
              matching: find.byType(CircularProgressIndicator)),
          findsOneWidget);
    });

    testWidgets('error: fail pill, the detail sentence, Retry and Remove',
        (tester) async {
      await _pumpRow(tester, _doc('error', {
        'error_message': 'Extraction failed.',
        'chunk_count': 4,
      }));
      final pill = tester.widget<KitProcPill>(find.byType(KitProcPill));
      expect(pill.tone, KitProcTone.fail);
      expect(find.text('pdf · 4 passages'), findsOneWidget);
      expect(find.text('Extraction failed.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
    });
  });

  group('letters.md: an archive row is a letter row', () {
    Widget row() => const SizedBox(
          width: 900,
          child: KitLetterRow(
            number: 3,
            title: 'On quiet rooms',
            lede: 'Three passages found each other today.',
            figures: '3 passages · ~4 min',
            date: 'Sep 10',
            badge: 'Sent on request',
            settled: true,
          ),
        );

    testWidgets('wide: №, subject over lede, figures, date, badge',
        (tester) async {
      await _at(tester, 1200, row());
      for (final s in [
        '№ 3',
        'On quiet rooms',
        'Three passages found each other today.',
        '3 passages · ~4 min',
        'Sep 10',
        'SENT ON REQUEST',
      ]) {
        expect(find.text(s), findsOneWidget, reason: s);
      }
    });

    testWidgets('phone: figures and date hide; number, text, badge stay',
        (tester) async {
      await _at(tester, 390, row());
      expect(find.text('3 passages · ~4 min'), findsNothing);
      expect(find.text('Sep 10'), findsNothing);
      expect(find.text('№ 3'), findsOneWidget);
      expect(find.text('SENT ON REQUEST'), findsOneWidget);
    });
  });

  test('sync type chips are spelled as web: PDF / Word / PowerPoint', () {
    expect(['pdf', 'docx', 'pptx', 'notion'].map(cloudTypeLabel),
        ['PDF', 'Word', 'PowerPoint', 'Notion page']);
    expect(cloudTypeLabel('odt'), 'ODT');
  });
}
