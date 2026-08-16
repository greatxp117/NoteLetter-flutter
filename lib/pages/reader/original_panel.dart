import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/document.dart';
import '../../services/api.dart';
import '../../services/api_service.dart';
import 'reader_ui.dart';
import '../../theme/app_radius.dart';

/// Reader → Original panel: the raw file as it arrived. URL-typed docs open
/// their `source_url` directly (no call, per reader.md); file docs mint a signed
/// GET URL via `fn_get_raw_document_url`. Flutter opens/downloads via the
/// browser rather than embedding a PDF viewer.
class OriginalPanel extends StatefulWidget {
  final String docId;
  final Document doc;
  const OriginalPanel({super.key, required this.docId, required this.doc});

  @override
  State<OriginalPanel> createState() => _OriginalPanelState();
}

class _OriginalPanelState extends State<OriginalPanel> {
  String? _url;
  String? _error;
  bool _isUrlDoc = false;

  bool get _hasTwoSources => widget.doc.sourceImageUrl?.isNotEmpty ?? false;

  @override
  void initState() {
    super.initState();
    // Article-from-screenshot (2.8.0, ADR-017): two sources — the captured
    // screenshot (source_image_url, directly renderable) + the resolved article
    // (source_url). Rendered by the two-source branch below; no raw-file call.
    if (_hasTwoSources) return;
    // URL-typed doc (has source_url, no stored file): open the source directly.
    if ((widget.doc.sourceUrl?.isNotEmpty ?? false) &&
        (widget.doc.gcsPath == null || widget.doc.gcsPath!.isEmpty)) {
      _isUrlDoc = true;
      _url = widget.doc.sourceUrl;
      return;
    }
    Api.instance.getRawDocumentUrl(widget.docId).then((res) {
      if (!mounted) return;
      final url = (res['signed_url'] ?? res['url'] ?? res['rawUrl']) as String?;
      setState(() {
        if (url != null && url.isNotEmpty) {
          _url = url;
        } else {
          _error = 'No original file available.';
        }
      });
    }).catchError((e) {
      if (!mounted) return;
      setState(() => _error =
          e is ApiException ? e.message : 'No original file available.');
    });
  }

  Future<void> _open() async {
    if (_url == null) return;
    await launchUrl(Uri.parse(_url!), mode: LaunchMode.externalApplication);
  }

  Future<void> _launch(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final ui = ReaderUi(context);
    final kind = widget.doc.type.toUpperCase();

    if (_hasTwoSources) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ui.intro('Original · two sources',
            'This article was recognized from a screenshot you captured. Both sources are kept: the image you shared, and the original web article it resolved to.'),
        ClipRRect(
          borderRadius: AppRadius.mdR,
          child: Image.network(
            widget.doc.sourceImageUrl!,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => ui.empty(Icons.image_outlined,
                'Screenshot unavailable', 'The captured screenshot could not be loaded.'),
          ),
        ),
        const SizedBox(height: 6),
        Text('Captured screenshot',
            style: TextStyle(fontFamily: 'Geist', fontSize: 12, color: ui.muted)),
        if (widget.doc.sourceUrl?.isNotEmpty ?? false) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _launch(widget.doc.sourceUrl!),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('View original article'),
          ),
        ],
      ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ui.intro('Original · $kind',
          'The source exactly as it arrived. NoteLetter keeps the original alongside the text it extracted.'),
      if (_error != null)
        ui.empty(
            Icons.insert_drive_file_outlined, 'No original file available.', _error!)
      else if (_url == null)
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()))
      else
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: ui.card,
            borderRadius: AppRadius.mdR,
            border: Border.all(color: ui.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.insert_drive_file_outlined, size: 20, color: ui.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _isUrlDoc
                      ? (widget.doc.sourceUrl ?? 'Original source')
                      : (widget.doc.title.isEmpty
                          ? 'Original file'
                          : widget.doc.title),
                  style: TextStyle(fontFamily: 'Geist', fontSize: 14, color: ui.fg),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Wrap(spacing: 10, children: [
              FilledButton.icon(
                onPressed: _open,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(_isUrlDoc ? 'Open source' : 'Open original'),
              ),
            ]),
          ]),
        ),
    ]);
  }
}
