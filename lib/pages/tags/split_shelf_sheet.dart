/// Split a shelf (contract 2.20.0, ADR-025).
///
/// Auto-created shelves are BROAD by default; specificity is user-initiated,
/// because the right granularity is not a constant — it depends on how much of
/// a subject the reader has, which is knowable only after the documents exist
/// and only by them. A reader with 400 political essays does not want one shelf
/// called Politics.
///
/// Review-before-write, the `fn_suggest_tags` → `fn_approve_tags` shape: the
/// proposal is editable, any part can be skipped, and nothing is written until
/// the reader confirms. That is what keeps the model out of the write path.
library;

import 'package:flutter/material.dart';
import '../../services/api.dart';
import '../../theme/app_colors.dart';

/// Offered only at >= 5 documents — ABSENT below that, not disabled, because
/// the endpoint 400s there and a control that cannot work is worse than none.
const splitMinDocuments = 5;

class SplitShelfSheet extends StatefulWidget {
  const SplitShelfSheet({super.key, required this.tagId, required this.title});

  final String tagId;
  final String title;

  static Future<bool?> show(BuildContext context, String tagId, String title) =>
      showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (_) => SplitShelfSheet(tagId: tagId, title: title),
      );

  @override
  State<SplitShelfSheet> createState() => _SplitShelfSheetState();
}

class _SplitShelfSheetState extends State<SplitShelfSheet> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _rationale;
  int _documentCount = 0;
  int _unassigned = 0;

  /// The editable proposal. `skip` keeps a part visible but out of the write —
  /// its documents simply stay on the parent.
  final List<_Part> _parts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Api.instance.suggestShelfSplit(widget.tagId);
      if (!mounted) return;
      setState(() {
        _documentCount = (res['documentCount'] as num?)?.toInt() ?? 0;
        _unassigned =
            (res['unassignedDocumentIds'] as List?)?.length ?? 0;
        _rationale = res['rationale'] as String?;
        _parts
          ..clear()
          ..addAll(((res['parts'] as List?) ?? const []).map((p) {
            final m = (p as Map).cast<String, dynamic>();
            return _Part(
              title: TextEditingController(text: m['title'] as String? ?? ''),
              description: TextEditingController(
                  text: m['description'] as String? ?? ''),
              color: m['color'] as String?,
              documentIds:
                  ((m['documentIds'] as List?) ?? const []).cast<String>(),
            );
          }));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _apply() async {
    final kept = _parts.where((p) => !p.skip).toList();
    if (kept.length < 2) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Api.instance.splitShelf(widget.tagId, [
        for (final p in kept)
          {
            'title': p.title.text.trim(),
            if (p.description.text.trim().isNotEmpty)
              'description': p.description.text.trim(),
            if (p.color != null) 'color': p.color,
            'documentIds': p.documentIds,
          }
      ]);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      // Surfaced inline, never swallowed — the ADR-022 lesson: a client that
      // does not show its errors makes a validator and a working system
      // indistinguishable.
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted =
        isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground;
    final kept = _parts.where((p) => !p.skip).length;
    final moving = _parts
        .where((p) => !p.skip)
        .fold<int>(0, (n, p) => n + p.documentIds.length);

    return Padding(
      padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Split “${widget.title}”',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            if (_loading)
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator()))
            else if (_parts.isEmpty) ...[
              // A 200 with no parts is "this shelf already looks coherent",
              // not a failure — so there is nothing to confirm.
              Text(
                  _rationale ??
                      'This shelf already looks coherent — nothing to split.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Close')),
              ),
            ] else ...[
              Text(
                'Every part is editable, and any part can be skipped — its '
                'volumes stay where they are. The shelf itself is kept either '
                'way.',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
              if (_documentCount > 200) ...[
                const SizedBox(height: 6),
                Text(
                    'This proposal covers the 200 most recent of '
                    '$_documentCount volumes.',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted)),
              ],
              const SizedBox(height: 14),
              for (final part in _parts) _partCard(part, theme, muted),
              if (_unassigned > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                      '$_unassigned volume${_unassigned == 1 ? '' : 's'} '
                      'stay on “${widget.title}”.',
                      style:
                          theme.textTheme.bodySmall?.copyWith(color: muted)),
                ),
              const SizedBox(height: 14),
              // States what will happen before it happens, in volumes rather
              // than parts, because that is what the reader is deciding about.
              Text(
                kept < 2
                    ? 'Keep at least two parts to split.'
                    : '$moving volume${moving == 1 ? '' : 's'} move into '
                        '$kept new shelves. “${widget.title}” is kept.',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.critical)),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: (_saving || kept < 2) ? null : _apply,
                    child: Text(_saving ? 'Splitting…' : 'Split shelf'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _partCard(_Part part, ThemeData theme, Color muted) {
    final n = part.documentIds.length;
    return Opacity(
      opacity: part.skip ? 0.5 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: part.title,
                    enabled: !part.skip,
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => part.skip = !part.skip),
                  child: Text(part.skip ? 'Include' : 'Skip'),
                ),
              ],
            ),
            TextField(
              controller: part.description,
              enabled: !part.skip,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 4),
            Text('$n volume${n == 1 ? '' : 's'}',
                style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          ],
        ),
      ),
    );
  }
}

class _Part {
  _Part({
    required this.title,
    required this.description,
    required this.color,
    required this.documentIds,
  });

  final TextEditingController title;
  final TextEditingController description;
  final String? color;
  final List<String> documentIds;
  bool skip = false;
}
