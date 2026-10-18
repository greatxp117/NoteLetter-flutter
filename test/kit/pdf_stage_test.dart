/// F-124 — §15.1 draws a PDF, and a device shares the original file out.
///
/// The PDF stage's renderer (pdfx) needs a platform, so these tests drive the
/// stage through [KitPdfStage.opener] with a fake document. What a real page
/// looks like is the device run's and the frames' to prove.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/shared/share_original.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

/// A 1x1 PNG, the smallest page image a fake can hand back.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xFF, 0xFF, 0x3F,
  0x00, 0x05, 0xFE, 0x02, 0xFE, 0xA7, 0x35, 0x81, 0x84, 0x00, 0x00, 0x00,
  0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class _FakePdf implements KitPdfSource {
  _FakePdf(this.pageCount);
  @override
  final int pageCount;
  final List<int> rendered = [];
  bool closed = false;

  @override
  Future<Size> pageSize(int page) async => const Size(612, 792);

  @override
  Future<Uint8List> render(int page, double pixelWidth) async {
    rendered.add(page);
    return _png;
  }

  @override
  Future<void> close() async => closed = true;
}

Future<void> _pump(WidgetTester tester, Widget child,
    {Size size = const Size(402, 874)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ));
}

void main() {
  final realOpener = KitPdfStage.opener;
  tearDown(() => KitPdfStage.opener = realOpener);

  test('a PDF is drawn, by its type or its MIME type', () {
    expect(kitStageFor(type: 'pdf'), KitStage.pdf);
    expect(kitStageFor(type: 'document', mimeType: 'application/pdf'),
        KitStage.pdf);
    expect(kitStageFor(type: 'docx'), KitStage.none,
        reason: 'a DOCX keeps rule 1\'s sentence');
  });

  testWidgets('the pages stand one under another, on paper, in a stage capped '
      'at 720 that scrolls', (tester) async {
    final fake = _FakePdf(5);
    KitPdfStage.opener = (_) async => fake;
    await _pump(
      tester,
      const KitSourceFileView(
          title: 'Quarterly Tax Summary',
          url: 'https://storage.test/q.pdf',
          stage: KitStage.pdf),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final page1 = tester.getRect(find.byKey(const ValueKey('kit-pdf-page-1')));
    // 402 wide, the frame's 1px edge, and the stage's 18px phone padding.
    expect(page1.width, closeTo(402 - 2 - 36, 1));
    expect(page1.height, closeTo(page1.width * 792 / 612, 1),
        reason: 'the page keeps its own proportions');
    final stage = tester.getRect(find.byType(KitPdfStage));
    expect(stage.height, KitPdfStage.maxHeight,
        reason: 'five pages are taller than the cap, so the stage scrolls');
    expect(fake.rendered, isNotEmpty);
    expect(fake.rendered.first, 1, reason: 'the first page is drawn first');
    expect(find.byType(Image), findsWidgets);
    expect(find.textContaining('can’t be displayed'), findsNothing);
  });

  testWidgets('a short PDF takes only its own height', (tester) async {
    KitPdfStage.opener = (_) async => _FakePdf(1);
    await _pump(
        tester,
        const KitSourceFileView(
            title: 'One page', url: 'u', stage: KitStage.pdf));
    await tester.pump();
    await tester.pump();
    final stage = tester.getRect(find.byType(KitPdfStage));
    final page = tester.getRect(find.byKey(const ValueKey('kit-pdf-page-1')));
    expect(stage.height, closeTo(page.height + 36, 1));
  });

  testWidgets('a PDF that cannot be opened is rule 1\'s sentence, never a '
      'blank stage', (tester) async {
    KitPdfStage.opener = (_) async => throw StateError('not a PDF');
    await _pump(
        tester,
        const KitSourceFileView(
            title: 'Broken', url: 'u', stage: KitStage.pdf));
    await tester.pump();
    await tester.pump();
    expect(find.text('A PDF can’t be displayed here — open or download it above.'),
        findsOneWidget);
  });

  testWidgets('Share is in the toolbar only when the screen offers it, and '
      'it is handed the URL', (tester) async {
    String? shared;
    await _pump(
      tester,
      KitSourceFileView(
        title: 'deck.pptx',
        url: 'https://storage.test/deck.pptx',
        stage: KitStage.none,
        typeLabel: 'PPTX',
        onDownload: (_) {},
        onOpen: (_) {},
        onShare: (_, url) => shared = url,
      ),
    );
    expect(find.byTooltip('Share original'), findsOneWidget);
    await tester.tap(find.byTooltip('Share original'));
    expect(shared, 'https://storage.test/deck.pptx');

    await _pump(
      tester,
      const KitSourceFileView(
          title: 'deck.pptx', url: 'u', stage: KitStage.none),
    );
    expect(find.byTooltip('Share original'), findsNothing,
        reason: 'the web build and a screen that gives no handler draw none');
  });

  test('the shared copy is named for the file, never the signed URL', () {
    expect(
        shareFileName(
            title: 'Quarterly Tax Summary',
            type: 'pdf',
            gcsPath: 'raw/u1/uploads/AbC123_quarterly-tax.pdf'),
        'quarterly-tax.pdf');
    expect(
        shareFileName(
            title: 'Board deck',
            type: 'pptx',
            gcsPath: 'raw/u1/cloud/google_drive/j1_deck.pptx'),
        'deck.pptx');
    expect(shareFileName(title: 'Notes', type: 'pdf'), 'Notes.pdf');
    expect(shareFileName(title: 'Notes.pdf', type: 'pdf'), 'Notes.pdf');
    expect(shareFileName(title: 'a/b: c', type: 'docx'), 'a b  c.docx');
    expect(shareFileName(title: '', type: 'epub'), 'Original file.epub');
  });
}
