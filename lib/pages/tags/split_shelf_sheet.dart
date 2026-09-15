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
///
/// The reference puts this panel inline in the shelf's settings; on a phone it
/// is an overlay sheet over the same screen — the same parts, in the same
/// order, composed from the kit since F-08 (it was Material `TextField`s and a
/// `FilledButton` before).
library;

import 'package:flutter/material.dart';

import '../../services/api.dart';
import '../../services/api_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit/kit.dart';
import '../../services/analytics.dart';

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
        backgroundColor: Tokens.of(context).surface,
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

  @override
  void dispose() {
    for (final p in _parts) {
      p.title.dispose();
      p.description.dispose();
    }
    super.dispose();
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
        _error = _message(e);
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
      // That a shelf was split, and nothing about into what: every part carries
      // a title the reader wrote.
      Analytics.track('shelf_split');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      // Surfaced inline (§14.2), never swallowed — the ADR-022 lesson: a client
      // that does not show its errors makes a validator and a working system
      // indistinguishable. The message is the SERVER's, verbatim.
      setState(() {
        _error = _message(e);
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final kept = _parts.where((p) => !p.skip).length;
    final moving = _parts
        .where((p) => !p.skip)
        .fold<int>(0, (n, p) => n + p.documentIds.length);

    return Padding(
      padding: EdgeInsets.only(
          left: AppSpacing.s5,
          right: AppSpacing.s5,
          top: AppSpacing.s5,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.s5),
      child: KitScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Split “${widget.title}”', style: KitText.h4(context)),
            const SizedBox(height: 6),
            if (_loading)
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator()))
            else if (_error != null && _parts.isEmpty) ...[
              // The proposal itself was refused — a hole, not an empty state.
              KitFailureBlock(
                sentence: 'That shelf could not be analysed.',
                detail: _error!,
              ),
              const SizedBox(height: AppSpacing.s4),
              Align(
                alignment: Alignment.centerRight,
                child: KitButton.ghost('Close',
                    onPressed: () => Navigator.pop(context, false)),
              ),
            ] else if (_parts.isEmpty) ...[
              // A 200 with no parts is "this shelf already looks coherent",
              // not a failure — so there is nothing to confirm.
              KitRowNote(_rationale ??
                  'This shelf already looks coherent — nothing to split.'),
              const SizedBox(height: AppSpacing.s4),
              Align(
                alignment: Alignment.centerRight,
                child: KitButton.ghost('Close',
                    onPressed: () => Navigator.pop(context, false)),
              ),
            ] else ...[
              KitRowNote(
                'Every part is editable, and any part can be skipped — its '
                'volumes stay where they are. The shelf itself is kept either '
                'way.',
              ),
              if (_documentCount > 200) ...[
                const SizedBox(height: 6),
                KitRowNote('This proposal covers the 200 most recent of '
                    '$_documentCount volumes.'),
              ],
              const SizedBox(height: 14),
              for (final part in _parts) _partCard(part),
              if (_unassigned > 0)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.s1),
                  child: KitRowNote(
                      '${_unassigned == 1 ? '1 volume stays' : '$_unassigned volumes stay'} '
                      'on “${widget.title}”.'),
                ),
              const SizedBox(height: 14),
              // States what will happen before it happens, in volumes rather
              // than parts, because that is what the reader is deciding about.
              KitRowNote(
                kept < 2
                    ? 'Keep at least two parts to split.'
                    : '${moving == 1 ? '1 volume moves' : '$moving volumes move'} into '
                        '$kept new shelves. “${widget.title}” is kept.',
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.s2),
                KitFailureInline(_error!),
              ],
              const SizedBox(height: AppSpacing.s3),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  KitButton.ghost('Cancel',
                      onPressed: _saving
                          ? null
                          : () => Navigator.pop(context, false)),
                  const SizedBox(width: AppSpacing.s2),
                  KitButton.primary(
                    _saving ? 'Splitting…' : 'Create $kept shelves',
                    onPressed: (_saving || kept < 2) ? null : _apply,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _partCard(_Part part) {
    final n = part.documentIds.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s3),
      child: Opacity(
        opacity: part.skip ? 0.45 : 1,
        child: KitCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: AppColors.shelfColor(part.color) ??
                          Tokens.of(context).fgSubtle,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Tokens.of(context).border, width: 0.5),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: KitTextField(
                      controller: part.title,
                      placeholder: 'Name for this shelf',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              KitTextField(
                controller: part.description,
                placeholder: 'What belongs on this shelf…',
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  Expanded(
                    child: KitRowNote(
                        n == 1 ? '1 volume' : '$n volumes'),
                  ),
                  KitButton.ghost(
                    part.skip ? 'Include' : 'Skip',
                    onPressed: _saving
                        ? null
                        : () => setState(() => part.skip = !part.skip),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The server's own sentence where there is one (§14.2) — never a generic line
/// substituted for it, and never a Dart `Exception: …` prefix shown to a
/// reader.
String _message(Object e) =>
    e is ApiException ? e.message : 'That request could not be completed.';

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
