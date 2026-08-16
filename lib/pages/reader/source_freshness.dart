import 'package:flutter/material.dart';
import '../../models/document.dart';
import '../../services/api.dart';
import '../../services/api_service.dart';
import 'reader_ui.dart';
import '../../theme/app_radius.dart';

const _providerName = {
  'google_drive': 'Google Drive',
  'onedrive': 'OneDrive',
  'dropbox': 'Dropbox',
  'notion': 'Notion',
};

/// Reader source-freshness banner (1.4.0, ADR-007). For cloud-imported docs
/// (`source_integration`, `status: complete`), calls `fn_check_source_freshness`
/// AT MOST ONCE per document per app session (module-level cache; never a poll —
/// INV-02). `newer_at_provider` → "Update from source" (`fn_update_from_source`).
/// `missing_at_provider` → muted note. Check failures degrade silently.
class SourceFreshness extends StatefulWidget {
  final String docId;
  final Document doc;
  const SourceFreshness({super.key, required this.docId, required this.doc});

  /// Session cache: docId → freshness result (or null = checked & irrelevant).
  static final Map<String, Map<String, dynamic>?> _cache = {};

  @override
  State<SourceFreshness> createState() => _SourceFreshnessState();
}

class _SourceFreshnessState extends State<SourceFreshness> {
  Map<String, dynamic>? _freshness;
  bool _updating = false;
  bool _queued = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final doc = widget.doc;
    if (doc.sourceIntegration == null || doc.status != DocumentStatus.complete) {
      return;
    }
    if (SourceFreshness._cache.containsKey(widget.docId)) {
      _freshness = SourceFreshness._cache[widget.docId];
      return;
    }
    Api.instance.checkSourceFreshness(widget.docId).then((res) {
      SourceFreshness._cache[widget.docId] = res;
      if (mounted) setState(() => _freshness = res);
    }).catchError((_) {
      // Degrade silently — the reader never blocks on the freshness check.
      SourceFreshness._cache[widget.docId] = null;
    });
  }

  Future<void> _update() async {
    setState(() {
      _updating = true;
      _error = null;
    });
    try {
      await Api.instance.updateFromSource(widget.docId);
      SourceFreshness._cache.remove(widget.docId);
      setState(() => _queued = true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Update failed.');
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _freshness;
    if (widget.doc.sourceIntegration == null || f == null) {
      return const SizedBox.shrink();
    }
    final ui = ReaderUi(context);
    final provider = _providerName[f['provider']] ?? '${f['provider']}';

    if (f['missing_at_provider'] == true) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          'The original file is no longer at $provider — this imported copy is the surviving record.',
          style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: ui.muted),
        ),
      );
    }
    if (f['newer_at_provider'] != true) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ui.surface,
        borderRadius: AppRadius.mdR,
        border: Border.all(color: ui.border),
      ),
      child: Row(children: [
        Icon(Icons.info_outline, size: 15, color: ui.primary),
        const SizedBox(width: 10),
        Expanded(
          child: _queued
              ? Text(
                  'Update queued — this source is being re-imported from $provider. Its content will refresh when processing finishes.',
                  style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: ui.fg))
              : _error != null
                  ? Text(_error!,
                      style:
                          TextStyle(fontFamily: 'Geist', fontSize: 13, color: ui.critical))
                  : Text('A newer version of this file exists in $provider.',
                      style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: ui.fg)),
        ),
        if (!_queued) ...[
          const SizedBox(width: 8),
          TextButton(
            onPressed: _updating ? null : _update,
            child: Text(_updating ? 'Queuing…' : 'Update from source'),
          ),
        ],
      ]),
    );
  }
}
