import 'package:flutter/material.dart';

import '../../models/search_result.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit/kit.dart';

/// The second pane (`spec/screens/search.md` §Composition §Body): the selected
/// passage **in its surrounding context**, which is the whole reason search has
/// a two-pane frame and its own 1100px ceiling.
///
/// The context is the ±2 chunk window around the match. The match is marked in
/// `--highlight-strong` and set in `--fg`; its neighbours are `--fg-lede`, so
/// the eye lands on the matched span without the neighbours being greyed out of
/// legibility.
///
/// **A phone stacks this pane under the list, it does not drop it** — the
/// screen spec is explicit, and a phone reader has *more* need of the context
/// than a desktop one, not less.
class SearchReadingPane extends StatelessWidget {
  final SearchResult? result;

  /// The ±2 window, in `chunk_index` order, including the match itself.
  final List<Chunk> context;
  final bool loading;

  const SearchReadingPane({
    super.key,
    required this.result,
    required this.context,
    this.loading = false,
  });

  @override
  Widget build(BuildContext buildContext) {
    final t = Tokens.of(buildContext);

    final body = result == null
        ? _empty(buildContext, t)
        : _passage(buildContext, t);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
      decoration: BoxDecoration(
        // `--bg`, not `--surface`: this pane sits beside cards, not on the
        // page, and a surface fill would make it read as one more card.
        color: t.bg,
        borderRadius: AppRadius.mdR,
        border: Border.all(color: t.border),
      ),
      child: body,
    );
  }

  Widget _empty(BuildContext buildContext, Tokens t) => Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s5, vertical: AppSpacing.s16),
        child: Text(
          'Open a result to read the passage in its surrounding context.',
          textAlign: TextAlign.center,
          style: AppTheme.serif(
            fontSize: 16,
            height: 26 / 16,
            fontStyle: FontStyle.italic,
            color: t.fgSubtle,
          ),
        ),
      );

  Widget _passage(BuildContext buildContext, Tokens t) {
    final r = result!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            KitFileBadge(kitDocKind(r.document.type), size: KitBadgeSize.row),
            const SizedBox(width: AppSpacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    r.document.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.serif(
                      fontSize: 19,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: t.fg,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'similarity ${r.score.clamp(0.0, 1.0).toStringAsFixed(2)}',
                    style: TextStyle(
                      fontFamily: AppTheme.fontSans,
                      fontSize: 12,
                      color: t.fgMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(height: 1, color: t.rule),
        const SizedBox(height: AppSpacing.s4),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.s8),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          // The window, or — if the context read returned nothing — the matched
          // chunk on its own. A pane that renders empty because a neighbouring
          // read failed would hide the passage the reader actually asked for.
          for (final c in context.isEmpty ? [r.chunk] : context)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s4),
              child: Text(
                c.text,
                style: c.chunkId == r.chunk.chunkId
                    ? AppTheme.serif(
                        fontSize: 17,
                        height: 30 / 17,
                        color: t.fg,
                      ).copyWith(backgroundColor: t.highlightStrong)
                    : AppTheme.serif(
                        fontSize: 17,
                        height: 30 / 17,
                        color: t.fgLede,
                      ),
              ),
            ),
        Container(height: 1, color: t.rule),
        const SizedBox(height: AppSpacing.s4),
        Text(
          'Showing the passage that matched plus its neighbours. Open the full '
          'source to keep reading.',
          style: AppTheme.serif(
            fontSize: 14,
            height: 22 / 14,
            fontStyle: FontStyle.italic,
            color: t.fgSubtle,
          ),
        ),
      ],
    );
  }
}
