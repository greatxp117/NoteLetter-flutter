import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/document.dart';
import '../../services/api.dart';
import '../../services/api_service.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/kit/kit.dart';
import 'reader_ui.dart';

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
class OriginalPanel extends StatefulWidget {
  final String docId;
  final Document doc;
  const OriginalPanel({super.key, required this.docId, required this.doc});

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

  @override
  void initState() {
    super.initState();
    if (_fetches) _load();
  }

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
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _launch(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final ui = ReaderUi(context);
    final doc = widget.doc;
    final kind = doc.type.toUpperCase();

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
        _fullOriginal(),
      ]);
    }

    if (_shape == 'link') {
      final host = Uri.tryParse(doc.sourceUrl ?? '')?.host ?? '';
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ui.intro(
          'Original · ${host.isEmpty ? kind : host.replaceFirst('www.', '')}',
          doc.contentForm != null
              ? 'This source came from a link and has been reduced to the recipe. The source itself is below, and the full text it was reduced from is kept with it.'
              : 'This source came from a link — there is no uploaded file. The source itself is below.',
        ),
        if (doc.sourceUrl?.isNotEmpty ?? false)
          KitButton.secondary(
            host.isEmpty ? 'Open the source' : 'Open on ${host.replaceFirst('www.', '')}',
            icon: Icons.open_in_new,
            onPressed: () => _launch(doc.sourceUrl!),
          ),
        _fullOriginal(),
      ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ui.intro('Original · $kind',
          'The source exactly as it arrived. NoteLetter keeps the original alongside the text it extracted.'),
      _sourceBody(),
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
      typeLabel: doc.type.toUpperCase(),
      onDownload: _launch,
      onOpen: _launch,
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
