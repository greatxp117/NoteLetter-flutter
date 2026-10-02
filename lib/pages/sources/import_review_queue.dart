/// The import review queue (`screens/sources.md` §Import review queue,
/// 4.45.0, ADR-083) — one component for its two hosts, Sources and For your
/// review (4.100.0, `screens/review.md` §Files waiting to import: "verbatim"),
/// so the second place to answer the question is never a second way to answer
/// it.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/cloud_integration.dart';
import '../../models/import_job.dart';
import '../../state/cloud_notifier.dart';
import '../../widgets/kit/kit.dart';
import 'cloud_sync_copy.dart' show reviewSkippedNote;

/// A provider's own name; an unknown one is named as a service, never by its
/// token (CLAUDE.md: never `default: return status`).
String cloudProviderName(String provider) => switch (provider) {
      'google_drive' => 'Google Drive',
      'onedrive' => 'OneDrive',
      'dropbox' => 'Dropbox',
      'notion' => 'Notion',
      _ => 'Connected service',
    };

/// A triage batch's partial outcome (4.69.0, ADR-103 §4 amended). Two lines
/// that must never merge: `skipped` is a measured count and a note — nothing
/// failed — while `failed` is §14.2 inline, naming the FILE, because the
/// retry is per-row and the reader has to find it. It sits beside the note,
/// never in place of the section: what the batch did do is real.
class ReviewOutcomeNotes extends StatelessWidget {
  final ReviewOutcome outcome;
  const ReviewOutcomeNotes({super.key, required this.outcome});

  @override
  Widget build(BuildContext context) {
    final o = outcome;
    final skipped = o.skipped;
    final failed = o.failedNames;
    final rest = o.notAttempted;
    if (skipped == 0 && failed.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 4.90.0 (ADR-124 §7): an approve on a provider that is no longer
          // connected is `skipped` too, and the response does not say which —
          // so the note names both causes and asserts neither.
          if (skipped > 0)
            KitProcNote(reviewSkippedNote(skipped), padding: EdgeInsets.zero),
          if (failed.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: skipped > 0 ? 6 : 0),
              child: KitFailureInline(
                'Could not start ${failed.join(', ')} — the import queue did '
                'not accept ${failed.length == 1 ? 'it' : 'them'}. Retry from '
                'the list below.'
                '${rest > 0 ? ' $rest other ${rest == 1 ? 'file is' : 'files are'} '
                    'still waiting for review — nothing was started for '
                    '${rest == 1 ? 'it' : 'them'}.' : ''}',
              ),
            ),
        ],
      ),
    );
  }
}

/// **The import review queue** (`screens/sources.md` §Import review queue,
/// 4.45.0, ADR-083) — the files a sync held because the reader asked to be
/// asked. Above the progress list, because it is the one thing here that is
/// waiting on them.
///
/// **Empty is not a state worth drawing.** With no rules configured the section
/// never renders; with rules configured and nothing held, it stays absent too.
/// "Nothing waiting" is the normal condition, not an achievement.
///
/// Every action renders **pessimistically** off the subscription — nothing
/// moves here until the write lands. A control that moves first hides the
/// failure completely, and this one acts on files that may be scrolled out of
/// sight.
class ImportReviewQueue extends StatefulWidget {
  final List<ImportJob> held;

  /// The provider's `review_rules`, so a size hold can name its threshold.
  final Map<String, ReviewRule> Function(String provider) rulesFor;
  /// For your review's form (`screens/review.md` §Files waiting to import):
  /// the section eyebrow carries [eyebrow] and the count, and every row names
  /// its provider, because that screen holds every integration's holds at
  /// once. Null: the Sources form, "{n} files waiting for you".
  final String? eyebrow;

  const ImportReviewQueue(
      {super.key, required this.held, required this.rulesFor, this.eyebrow});

  @override
  State<ImportReviewQueue> createState() => _ImportReviewQueueState();
}

class _ImportReviewQueueState extends State<ImportReviewQueue> {
  /// §14.2 — one slot for the section's own rejection. One outstanding batch at
  /// a time, so one slot.
  String? _error;
  bool _busy = false;

  Future<void> _run(List<String> ids, String action) async {
    if (ids.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await context.read<CloudNotifier>().reviewJobs(ids, action,
        names: {for (final j in widget.held) j.id: j.providerFileName});
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final held = widget.held;
    if (held.isEmpty) return const SizedBox.shrink();
    final ids = [for (final j in held) j.id];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          widget.eyebrow != null
              ? '${widget.eyebrow} · ${held.length}'
              : '${held.length} ${held.length == 1 ? 'file' : 'files'} waiting for you',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            KitButton.primary('Import all',
                onPressed: _busy ? null : () => _run(ids, 'approve')),
            // §18 on **"Dismiss all" only**, and the asymmetry is the decision
            // rather than an omission: a reader dismissing one row has just
            // read that row, while this control acts on files that may be
            // scrolled out of sight. Both are undoable from Import history, so
            // a panel on every row would make a triage queue slower without
            // making anything safer.
            KitButton.ghost('Dismiss all', onPressed: _busy
                ? null
                : () async {
                    final done = await KitConfirm.show(
                      context,
                      title: 'Dismiss ${held.length} '
                          '${held.length == 1 ? 'file' : 'files'}?',
                      body: 'They will not be offered again, even if they '
                          'change at the provider. Nothing is deleted where it '
                          'lives. You can undo this with Import again on the '
                          'dismissed row in your import history.',
                      confirmLabel: 'Dismiss them',
                      cancelLabel: 'Keep waiting',
                      onConfirm: () => context
                          .read<CloudNotifier>()
                          .reviewJobs(ids, 'dismiss', names: {
                            for (final j in held) j.id: j.providerFileName
                          }),
                    );
                    if (done == true && mounted) setState(() => _error = null);
                  }),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          KitFailureInline(_error!),
        ],
        const SizedBox(height: 10),
        KitRowList(
          rows: [
            for (final j in held)
              _HeldRow(
                  job: j,
                  rules: widget.rulesFor(j.provider),
                  onRun: _run,
                  nameProvider: widget.eyebrow != null),
          ],
        ),
        // The standing sentence the per-row control keeps above the list, so a
        // single Dismiss is not silent about being permanent.
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Dismissing a file means it will not be offered again, even if it '
            'changes at the provider. Import again on the dismissed row undoes '
            'it.',
            style: KitText.meta(context),
          ),
        ),
      ],
    );
  }
}

/// A held row: the progress-row anatomy, plus the **size** and the **reason**.
class _HeldRow extends StatelessWidget {
  final ImportJob job;
  final Map<String, ReviewRule> rules;
  final Future<void> Function(List<String> ids, String action) onRun;
  final bool nameProvider;

  const _HeldRow(
      {required this.job,
      required this.rules,
      required this.onRun,
      this.nameProvider = false});

  /// "PDF · 42 MB — over your 5 MB review size" / "PPTX — you asked about
  /// every one". **Named by size, never by length**: there is no page count to
  /// promise, because no provider reports one (ADR-083).
  ///
  /// The head is the TYPE KEY of the file's MIME, never `kitDocKind(mime)`:
  /// that table is keyed by document `type`, so a MIME fell through to `note`
  /// and every held row read "NOTE · 42 MB". The threshold is the rule's own
  /// number, read off the provider's `review_rules` — "over your review size"
  /// without it asked the reader to remember what they had set.
  String _reason() {
    final key = job.typeKey;
    final kind = key == null ? 'File' : _typeLabel(key);
    final size = fmtFileSize(job.fileSize);
    final head = size.isEmpty ? kind : '$kind · $size';
    if (job.reviewReason == 'type') return '$head — you asked about every one';
    final rule = key == null ? null : rules[key];
    return rule != null && !rule.isAlways && rule.overMb != null
        ? '$head — over your ${rule.overMb} MB review size'
        : head;
  }

  @override
  Widget build(BuildContext context) {
    return KitSourceRow(
      leading: KitFileBadge(kitDocKind(job.docType)),
      title: job.providerFileName.isEmpty
          ? '(fetching name…)'
          : job.providerFileName,
      subtitle: [
        if (nameProvider) cloudProviderName(job.provider),
        _reason(),
        if (job.providerPath.isNotEmpty) job.providerPath,
      ].join(' · '),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          KitButton.ghost('Import',
              onPressed: () => onRun([job.id], 'approve')),
          const SizedBox(width: 4),
          KitButton.ghost('Dismiss',
              onPressed: () => onRun([job.id], 'dismiss')),
        ],
      ),
    );
  }
}

/// The spelling of a cloud type key on a held row. The spec's own examples
/// ("PDF · 42 MB", "PPTX — …") upper-case the file keys; `notion` is not an
/// acronym, and upper-cased it read "NOTION ·".
String _typeLabel(String key) => switch (key) {
      'notion' => 'Notion page',
      _ => key.toUpperCase(),
    };

/// Bytes as the reference spells them (`fmtSize`): KB under a megabyte —
/// "0.0 MB" is a measured file drawn as nothing.
String fmtFileSize(int bytes) {
  const mb = 1024 * 1024;
  if (bytes <= 0) return '';
  if (bytes >= mb) {
    return '${(bytes / mb).toStringAsFixed(bytes >= 10 * mb ? 0 : 1)} MB';
  }
  final kb = (bytes / 1024).round();
  return '${kb < 1 ? 1 : kb} KB';
}
