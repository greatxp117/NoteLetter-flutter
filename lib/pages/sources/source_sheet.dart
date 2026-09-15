import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/document.dart';
import '../../services/api.dart';
import '../../services/api_service.dart';
import '../../widgets/kit/kit.dart';

/// **Seeing the source** (`screens/sources.md` §Document processing, 4.37.0,
/// ADR-075) — the §15 overlay sheet the processing tray opens.
///
/// Every row offers the source itself — failed, queued, uploading or
/// mid-extraction — because `error_message` is a claim *about* a source and
/// nothing else on the screen shows the source. The affordance is the
/// document's **shape** (§6.4.2), which is known from fields written at
/// creation and does **not** depend on `status`:
///
/// | Shape | Affordance | What opens |
/// | --- | --- | --- |
/// | `file` | View file | this sheet, holding §15.1 |
/// | `link` | Open the link | `source_url` externally — **no endpoint call**, the document has no stored object to sign |
/// | `set` | View images | this sheet, holding §15.2 |
///
/// **The reader is not the route.** It is gated on `status == "complete"`
/// everywhere, deliberately, and five of its six tabs are assembled from chunks
/// a failed document does not have. This sheet renders the stored object only.
class SourceSheet {
  SourceSheet._();

  /// The row's label for this document's shape.
  static String labelFor(Document doc) => switch (kitSourceShape(
        type: doc.type,
        gcsPath: doc.gcsPath,
        sourceUrl: doc.sourceUrl,
      )) {
        'link' => 'Open the link',
        'set' => 'View images',
        _ => 'View file',
      };

  /// Open it. A `link` never reaches the sheet — it has no stored object, so
  /// there is nothing to sign and nothing to draw.
  static Future<void> open(BuildContext context, Document doc) async {
    final shape = kitSourceShape(
      type: doc.type,
      gcsPath: doc.gcsPath,
      sourceUrl: doc.sourceUrl,
    );
    if (shape == 'link') {
      final url = doc.sourceUrl;
      if (url == null || url.isEmpty) return;
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }
    if (!context.mounted) return;
    await KitOverlaySheet.show(
      context,
      icon: shape == 'set'
          ? Icons.photo_library_outlined
          : Icons.insert_drive_file_outlined,
      title: doc.title.isEmpty ? 'Original file' : doc.title,
      subtitle: doc.type.toUpperCase(),
      builder: (_) => _SourceBody(doc: doc, shape: shape),
    );
  }
}

/// The three states inside the sheet, and **only one of them is a failure**.
class _SourceBody extends StatefulWidget {
  final Document doc;
  final String shape;

  const _SourceBody({required this.doc, required this.shape});

  @override
  State<_SourceBody> createState() => _SourceBodyState();
}

class _SourceBodyState extends State<_SourceBody> {
  bool _loading = true;
  String? _url;
  List<KitSetMember>? _members;
  String? _error;
  String? _requestId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _requestId = null;
    });
    try {
      final data = await Api.instance.getRawDocumentUrl(widget.doc.id);
      if (!mounted) return;
      setState(() {
        _url = data['signed_url'] as String?;
        _members = ((data['members'] as List?) ?? const [])
            .map((e) => KitSetMember.fromJson(e as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _requestId = e.requestId;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'The original file couldn’t be opened.';
        _loading = false;
      });
    }
  }

  Future<void> _launch(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // The **request** failing is §14.1, in the sheet, with Retry — the one
    // failure of the three.
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: KitFailureBlock(
          sentence: 'The original file couldn’t be opened.',
          detail: _error!,
          requestId: _requestId,
          onRetry: _load,
        ),
      );
    }

    // §15.2 — a set is n objects and its own viewer. BEFORE the null-URL state
    // below, because that state is a statement about `signed_url`, which is
    // null for a set by construction and says nothing about its pages.
    if (widget.shape == 'set') {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: KitSourceSetGallery(
          members: _members ?? const [],
          onOpenPage: (i, m) => KitLightbox.show(context,
              url: m.signedUrl!, caption: 'Page ${i + 1} — ${m.name}'),
        ),
      );
    }

    // A successful request that answered "no object". **Not §14**: the request
    // did not fail, and on a `pending_upload` document the bytes have
    // genuinely not landed yet — dressing a real answer as a failure is
    // ADR-070's own defect in reverse (§15.1 rule 2).
    if (_url == null || _url!.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: KitProcNote(
          widget.doc.status == DocumentStatus.pendingUpload
              ? 'This file hasn’t finished uploading yet — it can be opened as '
                  'soon as the bytes land.'
              : 'No original file is stored for this source.',
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: KitSourceFileView(
        title: widget.doc.title.isEmpty ? 'Original file' : widget.doc.title,
        url: _url!,
        stage: kitStageFor(
            type: widget.doc.type, mimeType: widget.doc.mimeType),
        typeLabel: widget.doc.type.toUpperCase(),
        onDownload: _launch,
        onOpen: _launch,
      ),
    );
  }
}
