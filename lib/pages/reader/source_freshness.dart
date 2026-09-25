
import 'package:flutter/material.dart';
import '../../models/document.dart';
import '../../services/api.dart';
import '../../services/api_service.dart';
import '../../widgets/kit/kit.dart';
import 'reader_ui.dart';
import 'supersession_confirm.dart';
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
  /// **Only a check that ANSWERED is cached** — see the `catchError` below.
  static final Map<String, Map<String, dynamic>?> _cache = {};

  /// The cache is a process-lifetime static, so a suite that fills it leaks
  /// into whatever runs next — the same one-way door `test_isolation_test`
  /// refuses for the service singletons.
  @visibleForTesting
  static void resetCacheForTest() => _cache.clear();

  @visibleForTesting
  static bool debugCacheHas(String docId) => _cache.containsKey(docId);

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
      // Degrade silently — the reader never blocks on the freshness check —
      // but do NOT cache the failure. A cached `null` is indistinguishable
      // from "checked, nothing to say", and it lasted the whole process: one
      // dropped request meant this document could never show its banner again
      // until the app was restarted. Not caching means the next mount asks
      // again, which is still at most once per open (INV-02 forbids a poll,
      // not a retry).
    });
  }

  /// reader.md §Supersession confirm: through the §18 confirm when a passage
  /// was edited or the document is in a study program (or either could not
  /// be checked); a refusal inside it stays in the panel. With no confirm
  /// owed, a refusal is §14.2 in the banner, as before. Write before you
  /// move: the banner flips to queued only once the call has succeeded.
  Future<void> _update() async {
    setState(() {
      _updating = true;
      _error = null;
    });
    final res = await SupersessionConfirm.run(
      context,
      docId: widget.docId,
      title: SupersessionConfirm.updateTitle,
      lead: SupersessionConfirm.updateLead(_freshness?['provider'] as String?),
      confirmLabel: SupersessionConfirm.updateConfirmLabel,
      action: () async {
        try {
          await Api.instance.updateFromSource(widget.docId);
          return null;
        } on ApiException catch (e) {
          return e.message;
        } catch (_) {
          return 'Update failed.';
        }
      },
    );
    if (!mounted) return;
    setState(() {
      _updating = false;
      switch (res.outcome) {
        case SupersessionOutcome.done:
          SourceFreshness._cache.remove(widget.docId);
          _queued = true;
        case SupersessionOutcome.refused:
          _error = res.message;
        case SupersessionOutcome.kept:
          break;
      }
    });
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
      // `.proc-note` from the kit — an italic serif remark at `--fg-subtle`,
      // not UI sans body copy: this is an aside ABOUT the document, in the
      // same editorial voice the rest of the reader's asides use. It was this
      // screen's own `copyWith` until F-09 put the one spelling in the kit.
      return KitProcNote(
        'The original file is no longer at $provider — this imported copy is the surviving record.',
        padding: const EdgeInsets.only(top: 12),
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
                  style: KitText.ui(context, color: ui.fg))
              : _error != null
                  ? KitFailureInline(_error!)
                  : Text('A newer version of this file exists in $provider.',
                      style: KitText.ui(context, color: ui.fg)),
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
