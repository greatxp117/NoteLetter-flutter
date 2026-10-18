import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart' as pdfx;

import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/tokens.dart';
import 'kit_text.dart';

/// An open PDF, as the stage needs it: how many pages, how big each is, and
/// each page drawn at a given pixel width. An interface so the stage can be
/// driven in a widget test, where no platform renderer exists.
abstract class KitPdfSource {
  int get pageCount;

  /// The page's size in PDF points, 1-based like the renderer's.
  Future<Size> pageSize(int page);

  /// The page as an encoded image, [pixelWidth] wide, on white.
  Future<Uint8List> render(int page, double pixelWidth);

  Future<void> close();
}

/// Opens [url]'s bytes as a [KitPdfSource]. Replaced in tests.
typedef KitPdfOpener = Future<KitPdfSource> Function(String url);

/// §15.1's PDF stage (component-kit §15.1; F-124) — the reference's
/// `.pdf-stage`: the pages on white sheets, one under another, in a stage that
/// scrolls, capped at 720 and padded 18 on a phone. Web frames the browser's
/// own viewer in an iframe; this client renders the pages itself (pdfx: PDFKit
/// on iOS, PdfRenderer on Android), each as it scrolls into view, never the
/// whole document at once.
///
/// A PDF that cannot be opened is §15.1 rule 1's sentence, as before F-124 — a
/// stage that renders nothing reads as a broken viewer.
class KitPdfStage extends StatefulWidget {
  final String url;

  const KitPdfStage({super.key, required this.url});

  /// The opener every stage uses. Tests swap it for a fake.
  static KitPdfOpener opener = _openWithPdfx;

  static const double maxHeight = 720;

  @override
  State<KitPdfStage> createState() => _KitPdfStageState();
}

class _KitPdfStageState extends State<KitPdfStage> {
  KitPdfSource? _source;
  List<Size>? _sizes;
  bool _failed = false;
  final Map<int, Uint8List> _pages = {};
  final Set<int> _asked = {};
  double? _renderedAt;

  /// One page at a time: a renderer asked for ten pages at once holds ten
  /// full-size bitmaps, and pdfx's iOS side serialises them anyway.
  Future<void> _queue = Future.value();

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final source = await KitPdfStage.opener(widget.url);
      final sizes = <Size>[];
      for (var i = 1; i <= source.pageCount; i++) {
        sizes.add(await source.pageSize(i));
      }
      if (!mounted) {
        await source.close();
        return;
      }
      setState(() {
        _source = source;
        _sizes = sizes;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _ask(int page, double pixelWidth) {
    final source = _source;
    if (source == null || _asked.contains(page)) return;
    _asked.add(page);
    _queue = _queue.then((_) async {
      if (!mounted) return;
      try {
        final bytes = await source.render(page, pixelWidth);
        if (mounted) setState(() => _pages[page] = bytes);
      } catch (_) {
        // A page that will not draw stays a blank sheet of its own size; the
        // rest of the document still reads.
      }
    });
  }

  @override
  void dispose() {
    final source = _source;
    _queue.whenComplete(() => source?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    if (_failed) {
      return Container(
        width: double.infinity,
        color: t.surfaceSunken,
        padding: const EdgeInsets.all(AppSpacing.s4),
        child: const KitProcNote(
            'A PDF can’t be displayed here — open or download it above.',
            padding: EdgeInsets.zero),
      );
    }
    final sizes = _sizes;
    final compact =
        MediaQuery.sizeOf(context).width < AppSpacing.compactWidth;
    final pad = compact ? 18.0 : 32.0;
    return LayoutBuilder(builder: (context, c) {
      final inner = c.maxWidth - 2 * pad;
      if (sizes == null) {
        return Container(
          height: 160,
          color: t.surfaceSunken,
          alignment: Alignment.center,
          child: const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2)),
        );
      }
      // Web's page is 520 wide on a desk and the full stage on a phone.
      final pageWidth = inner < 520 ? inner : 520.0;
      final heights = [
        for (final s in sizes) s.width <= 0 ? pageWidth : pageWidth * s.height / s.width
      ];
      final content = heights.fold<double>(0, (a, h) => a + h) +
          AppSpacing.s4 * (heights.length - 1) +
          2 * pad;
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final pixelWidth = (pageWidth * dpr).roundToDouble();
      if (_renderedAt != pixelWidth) {
        // A new width draws every page again, at the new width.
        _renderedAt = pixelWidth;
        _pages.clear();
        _asked.clear();
      }
      return Container(
        height: content < KitPdfStage.maxHeight ? content : KitPdfStage.maxHeight,
        color: t.surfaceSunken,
        child: ListView.builder(
          padding: EdgeInsets.all(pad),
          itemCount: sizes.length,
          itemBuilder: (context, i) {
            final page = i + 1;
            _ask(page, pixelWidth);
            final bytes = _pages[page];
            return Padding(
              padding: EdgeInsets.only(
                  bottom: i == sizes.length - 1 ? 0 : AppSpacing.s4),
              child: Center(
                child: Container(
                  key: ValueKey('kit-pdf-page-$page'),
                  width: pageWidth,
                  height: heights[i],
                  decoration: const BoxDecoration(
                    // literal-ok: --paper-50, the page itself. A sheet of paper
                    // is pale in both themes, as web's `.pdf-page` is.
                    color: Color(0xFFFAFAF7),
                    boxShadow: AppShadows.s3,
                  ),
                  child: bytes == null
                      ? null
                      : Image.memory(bytes,
                          fit: BoxFit.fill, gaplessPlayback: true),
                ),
              ),
            );
          },
        ),
      );
    });
  }
}

Future<KitPdfSource> _openWithPdfx(String url) async {
  final res = await Dio().get<List<int>>(url,
      options: Options(responseType: ResponseType.bytes));
  final data = Uint8List.fromList(res.data ?? const []);
  final doc = await pdfx.PdfDocument.openData(data);
  return _PdfxSource(doc);
}

class _PdfxSource implements KitPdfSource {
  _PdfxSource(this._doc);
  final pdfx.PdfDocument _doc;

  @override
  int get pageCount => _doc.pagesCount;

  @override
  Future<Size> pageSize(int page) async {
    final p = await _doc.getPage(page);
    try {
      return Size(p.width, p.height);
    } finally {
      await p.close();
    }
  }

  @override
  Future<Uint8List> render(int page, double pixelWidth) async {
    final p = await _doc.getPage(page);
    try {
      final h = pixelWidth * p.height / p.width;
      final img = await p.render(
        width: pixelWidth,
        height: h,
        format: pdfx.PdfPageImageFormat.png,
        backgroundColor: '#FAFAF7',
      );
      if (img == null) throw StateError('page $page did not render');
      return img.bytes;
    } finally {
      await p.close();
    }
  }

  @override
  Future<void> close() => _doc.close();
}
