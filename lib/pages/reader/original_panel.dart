import 'dart:convert' show HtmlEscape;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:url_launcher/url_launcher.dart';
import '../../models/chunk.dart';
import '../../models/document.dart';
import '../../services/api.dart';
import '../../services/api_service.dart';
import '../../theme/app_spacing.dart';
import '../../shared/share_original.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/kit/kit.dart';
import 'reader_ui.dart';
import 'update_from_source_bar.dart';
import '../../services/error_text.dart';

/// Reader → Original panel: the document's own source, and the extraction
/// beside it.
///
/// The panel dispatches on the **source shape** (§6.4.2, ADR-075), not on
/// `gcs_path != null` — which is a two-value test over a three-value world and
/// filed every `image_set` as a link, drawing "Open source" over a null:
///
///   `file` → [KitSourceFileView] (§15.1), from `fn_get_raw_document_url`
///   `set`  → [KitSourceSetGallery] (§15.2), from the same call's `members`
///   `link` → no viewer at all; the source_url is the whole source
///
/// Three answers that are NOT the same thing, and this panel drew one sentence
/// for all of them until now: a request that **failed** is §14.1 with the
/// server's own sentence and its request id; a successful call answering
/// `signed_url: null` is a **state** in its own words (§15.1 rule 2); and a
/// `link` never calls at all.
///
/// **Distilled documents (4.6.0, ADR-042)**: `original_content_url` is the full
/// pre-distillation text, and this panel is the only place that guarantee is
/// visible (INV-20b) — so a document whose manuscript is a recipe MUST offer
/// it here, and nothing else in the reader may render it.
///
/// **The extraction beside the source (F-185; kit §15.1 rule 3, web
/// `OriginalPanel`)**: every shape draws what NoteLetter read out of it — *The
/// page as we captured it*, *The document as we read it*, *The article it
/// resolved to*, or for a recipe *The full text, before the recipe* — from
/// the ordered [chunks] the reader already holds (ADR-004), and the raw text,
/// collapsed, where the render above it is not the text (a screenshot, a
/// recipe). A link's live embed is web's iframe; here it is the provider's
/// poster beside *Open on {host}* (CLAUDE.md §Composition deviations).
class OriginalPanel extends StatefulWidget {
  final String docId;
  final Document doc;

  /// The document's passages, in order — what the extraction is drawn from.
  final List<Chunk> chunks;

  const OriginalPanel(
      {super.key, required this.docId, required this.doc, this.chunks = const []});

  /// A recipe's pre-distillation text (`original_content_url`, a durable
  /// download-token URL): an ordinary GET. A seam for the tests.
  static Future<String> Function(String url) fetchOriginal = _get;

  static Future<String> _get(String url) async {
    final res = await Dio().get<String>(url,
        options: Options(responseType: ResponseType.plain));
    return res.data ?? '';
  }

  @override
  State<OriginalPanel> createState() => _OriginalPanelState();
}

class _OriginalPanelState extends State<OriginalPanel> {
  String? _url;
  List<KitSetMember>? _members;
  String? _error;
  String? _errorRequestId;
  bool _loading = false;

  bool get _hasTwoSources => widget.doc.sourceImageUrl?.isNotEmpty ?? false;

  String get _shape => kitSourceShape(
        type: widget.doc.type,
        gcsPath: widget.doc.gcsPath,
        sourceUrl: widget.doc.sourceUrl,
      );

  /// A `link` has no stored object, so it never calls the endpoint — asking
  /// anyway is what put "No original file available." on every article. A
  /// `set` DOES call it: the same response carries its pages in `members`, and
  /// one call answers for every shape that has bytes.
  bool get _fetches => _shape == 'file' || _shape == 'set';

  /// A recipe's original (ADR-042, INV-20b), fetched: '' until it answers.
  /// [_fullLoaded] once it has; [_fullFailed] when it was refused.
  String _fullHtml = '';
  String _fullText = '';
  bool _fullLoaded = false;
  bool _fullFailed = false;

  bool get _isDistilled =>
      widget.doc.contentForm != null &&
      (widget.doc.originalContentUrl?.isNotEmpty ?? false);

  @override
  void initState() {
    super.initState();
    if (_fetches) _load();
    if (_isDistilled) _loadFull();
  }

  Future<void> _loadFull() async {
    try {
      final raw = await OriginalPanel.fetchOriginal(widget.doc.originalContentUrl!);
      if (!mounted) return;
      final html = asExtractionHtml(raw);
      setState(() {
        _fullHtml = html;
        _fullText = blockText(html);
        _fullLoaded = true;
      });
    } catch (_) {
      // Degrades to the link below, never to a substitute: the chunks ARE the
      // distillation, and showing them as "the full text" is INV-20b reversed.
      if (mounted) setState(() => _fullFailed = true);
    }
  }

  /// The extraction, assembled from the ordered chunks (web `chunkHtml`): a
  /// chunk's html, or its text as a paragraph.
  String get _chunkHtml => [
        for (final c in widget.chunks)
          (c.html ?? '').trim().isNotEmpty
              ? c.html!.trim()
              : '<p>${const HtmlEscape().convert(c.text)}</p>',
      ].join('\n');

  String get _chunkText => [
        for (final c in widget.chunks)
          c.text.isNotEmpty ? c.text : blockText(c.html ?? ''),
      ].join('\n\n');

  /// A distilled document's original is the pre-distillation HTML OR
  /// NOTHING: while that fetch is out, or after it failed, the only HTML in
  /// hand is the chunks — the recipe itself — and drawn under *The full text,
  /// before the recipe* they said the opposite of INV-20b (F-200, web
  /// eca03fc). The section says where the full text is instead
  /// ([_fullPending]). Everything else shows what was extracted and stored.
  String get _previewHtml => _isDistilled ? _fullHtml : _chunkHtml;

  /// The section's one sentence while a recipe's full text has not loaded
  /// (web `fullPending`, a `.panel-note`), or null.
  String? get _fullPending => !_isDistilled || _fullLoaded
      ? null
      : _fullFailed
          ? 'The full original text couldn’t be loaded here — open it with '
              'the link below.'
          : 'Loading the full original text…';

  /// The render, under its own eyebrow (`.orig-section`): 22 above, the
  /// eyebrow 10 over the frame; before anything was extracted, a sentence.
  Widget _section(String label, {String? liveUrl}) {
    final doc = widget.doc;
    final html = _previewHtml;
    final pending = _fullPending;
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Eyebrow(label),
        const SizedBox(height: 10),
        // A recipe's full text not in hand: the section's one sentence.
        if (pending != null)
          Lede(pending, fontSize: 15, height: 23, maxWidth: 480)
        else
          html.trim().isEmpty
              ? const KitProcNote(
                  'Nothing has been extracted from this source yet — the '
                  'preview appears once processing finishes.',
                  padding: EdgeInsets.zero)
              : KitExtractionPreview(
                  title: doc.title.isEmpty ? 'Captured page' : doc.title,
                  html: html,
                  onOpenLive: liveUrl == null ? null : () => _launch(liveUrl),
                ),
      ]),
    );
  }

  /// The raw text, where the render is not the text (web `showRawText`).
  /// A recipe's waits for its full text (F-200, web `showRawText`).
  Widget _raw({required String note}) =>
      ((_isDistilled && _fullLoaded) || (!_isDistilled && _hasTwoSources))
      ? KitRawText(
          text: _isDistilled ? _fullText : _chunkText,
          label: 'Raw extracted text',
          note: note,
        )
      : const SizedBox.shrink();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _errorRequestId = null;
    });
    try {
      final res = await Api.instance.getRawDocumentUrl(widget.docId);
      if (!mounted) return;
      setState(() {
        _url = res['signed_url'] as String?;
        _members = (res['members'] as List?)
            ?.whereType<Map>()
            .map((m) => KitSetMember.fromJson(m.cast<String, dynamic>()))
            .toList();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      // The rejection is KEPT, not flattened to "unavailable": a 500 and a
      // document with no stored object are different answers, and one sentence
      // for both is how this panel read for its whole life.
      setState(() {
        _error = e.message;
        _errorRequestId = e.requestId;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeSdkError(e);
        _loading = false;
      });
    }
  }

  Future<void> _share(BuildContext anchor, String url) async {
    final d = widget.doc;
    final failed = await shareOriginal(
      anchor,
      url: url,
      fileName: shareFileName(title: d.title, type: d.type, gcsPath: d.gcsPath),
      mimeType: d.mimeType,
    );
    if (failed != null && mounted) {
      AppToast.show(context, failed, type: ToastType.error);
    }
  }

  Future<void> _launch(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final ui = ReaderUi(context);
    final doc = widget.doc;
    // The kind's badge word, never the raw `type`: an image set is a NOTE here
    // as it is on the header plate, not "IMAGE_SET" (§6.4.1, web 938a2f4).
    final kind = kitKindLabel(doc.type);

    // Article-from-screenshot (2.8.0, ADR-017): the document has TWO sources —
    // the captured screenshot (a durable URL, no call) and the article it
    // resolved to. This is the only place the screenshot appears.
    if (_hasTwoSources) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ui.intro('Original · two sources',
            'This article was recognized from a screenshot you captured. Both sources are kept: the image you shared, and the original web article it resolved to.'),
        GestureDetector(
          onTap: () => KitLightbox.show(context,
              url: doc.sourceImageUrl!, caption: 'The screenshot you captured'),
          child: KitFigure(
            url: doc.sourceImageUrl!,
            caption: 'Captured screenshot',
          ),
        ),
        if (doc.sourceUrl?.isNotEmpty ?? false) ...[
          const SizedBox(height: AppSpacing.s4),
          KitButton.secondary('View original article',
              icon: Icons.open_in_new,
              onPressed: () => _launch(doc.sourceUrl!)),
        ],
        _section('The article it resolved to',
            liveUrl: (doc.sourceUrl?.isNotEmpty ?? false) ? doc.sourceUrl : null),
        _raw(
            note: _isDistilled
                ? 'The complete text of the source, before it was reduced to the recipe.'
                : 'The text of the resolved article, exactly as it was extracted and stored.'),
        _fullOriginal(),
      ]);
    }

    if (_shape == 'link') {
      final host = Uri.tryParse(doc.sourceUrl ?? '')?.host ?? '';
      final live = (doc.sourceUrl?.isNotEmpty ?? false) ? doc.sourceUrl : null;
      // web `LiveEmbed`: the provider's poster, else the captured page's lead
      // image. The embed itself is a phone deviation (CLAUDE.md).
      final poster = (doc.thumbnailUrl?.isNotEmpty ?? false)
          ? doc.thumbnailUrl
          : firstImage(_previewHtml);
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ui.intro(
          'Original · ${host.isEmpty ? kind : host.replaceFirst('www.', '')}',
          _isDistilled
              ? 'This source came from a link and has been reduced to the recipe. Here is the source itself, and below it the page as NoteLetter captured it, in full.'
              : 'This source came from a link — there is no uploaded file. Here is the source itself, and below it the page as NoteLetter captured it.',
        ),
        if (poster != null) KitPoster(poster, alt: doc.title),
        if (live != null)
          KitButton.secondary(
            host.isEmpty ? 'Open the source' : 'Open on ${host.replaceFirst('www.', '')}',
            icon: Icons.open_in_new,
            onPressed: () => _launch(live),
          ),
        _section(
            _isDistilled
                ? 'The full text, before the recipe'
                : 'The page as we captured it',
            liveUrl: live),
        _raw(
            note:
                'The complete text of the source, before it was reduced to the recipe.'),
        _fullOriginal(),
      ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ui.intro('Original · $kind',
          'The source exactly as it arrived. NoteLetter keeps the original file alongside the text it extracted.'),
      // reader.md §Source freshness, 5.12.0 (ADR-172): beneath the intro,
      // before the file.
      UpdateFromSourceBar(docId: widget.docId, doc: doc),
      _sourceBody(),
      _section(_isDistilled
          ? 'The full text, before the recipe'
          : 'The document as we read it'),
      _raw(
          note:
              'The complete text of the source, before it was reduced to the recipe.'),
      _fullOriginal(),
    ]);
  }

  /// `file` and `set`, and the three answers the one call can give.
  Widget _sourceBody() {
    final doc = widget.doc;

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // §14.1 — the REQUEST failed. Distinct from the two states below, which are
    // successful answers, and it carries the server's sentence and the id.
    if (_error != null) {
      return KitFailureBlock(
        sentence: 'The original file couldn’t be opened.',
        detail: _error!,
        requestId: _errorRequestId,
        onRetry: _load,
      );
    }

    // §15.2 — a set is n objects and its own viewer. This sits BEFORE the
    // null-URL state below, because that state is a statement about
    // `signed_url`, which is null for a set by construction and says nothing
    // about whether its pages are there.
    if (_shape == 'set') {
      return KitSourceSetGallery(
        members: _members ?? const [],
        onOpenPage: (i, m) => KitLightbox.show(context,
            url: m.signedUrl!, caption: 'Page ${i + 1} — ${m.name}'),
      );
    }

    if (_url == null || _url!.isEmpty) {
      // A successful request that answered "no object". NOT §14: the request
      // did not fail, and dressing a real answer as a failure is ADR-070's own
      // defect in reverse (§15.1 rule 2).
      return KitProcNote(
        doc.status == DocumentStatus.pendingUpload
            ? 'This file hasn’t finished uploading yet — it can be opened as soon as the bytes land.'
            : 'No original file is stored for this source.',
      );
    }

    return KitSourceFileView(
      title: doc.title.isEmpty ? 'Original file' : doc.title,
      url: _url!,
      stage: kitStageFor(type: doc.type, mimeType: doc.mimeType),
      // The one place the raw format stays: "A DOCX can't be displayed here"
      // is a statement about the file's BYTES, not a name for the document
      // (web SourceFile.jsx keeps `type.toUpperCase()` for the same reason).
      typeLabel: doc.type.toUpperCase(),
      onDownload: _launch,
      onOpen: _launch,
      // F-124: the file itself, out through the system share sheet — a
      // device capability web lacks (CLAUDE.md's deviations).
      onShare: canShareOriginal ? (anchor, url) => _share(anchor, url) : null,
      // A stitched scroll (5.10.0, ADR-170): drawn tall and captioned (§15.1
      // rule 4) — the only place the picture appears; the Manuscript is text.
      stitchedFrames: doc.stitch?.frameCount,
      knownWidth: doc.stitch?.width,
      knownHeight: doc.stitch?.height,
    );
  }

  /// INV-20b — the honesty guarantee for a reduction. A distillation is
  /// non-destructive only if the text it replaced is reachable, and this is the
  /// one surface that reaches it.
  Widget _fullOriginal() {
    final url = widget.doc.originalContentUrl;
    if (url == null || url.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const KitProcNote(
          'The manuscript for this source has been reduced to the recipe. '
          'Nothing was thrown away — the full original text is kept here.',
          padding: EdgeInsets.zero,
        ),
        const SizedBox(height: AppSpacing.s3),
        KitButton.secondary('Full original text',
            icon: Icons.open_in_new, onPressed: () => _launch(url)),
      ]),
    );
  }
}

/// A stored original with no markup of its own (an Instagram reel's caption
/// and transcript) as paragraphs, so a renderer does not run it into one
/// blob; anything with a tag in it is left exactly as stored (web `asHtml`).
String asExtractionHtml(String raw) {
  final s = raw.trim();
  if (s.isEmpty || RegExp(r'<[a-z][a-z0-9]*[\s/>]', caseSensitive: false).hasMatch(s)) {
    return s;
  }
  return s
      .split(RegExp(r'\n\s*\n'))
      .map((b) => b.trim())
      .where((b) => b.isNotEmpty)
      .map((b) => '<p>${const HtmlEscape().convert(b).replaceAll('\n', '<br>')}</p>')
      .join();
}

/// The first image in a captured fragment — a lead image for a source that
/// publishes no poster (web `firstImage`).
String? firstImage(String html) {
  if (html.isEmpty) return null;
  final d = html_parser.parseFragment(html);
  final img = d.querySelector('img[data-nl-image-id]') ?? d.querySelector('img');
  final src = img?.attributes['src'];
  return (src == null || src.isEmpty) ? null : src;
}

/// A fragment's text with its block boundaries kept (web `blockText`):
/// paragraphs are not run into one word.
String blockText(String html) {
  if (html.isEmpty) return '';
  final d = html_parser.parseFragment(html);
  for (final el in d.querySelectorAll(
      'p, div, li, h1, h2, h3, h4, blockquote, tr, figcaption, pre, br')) {
    el.append(dom.Text('\n'));
  }
  return (d.text ?? '')
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}
