import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

import '../../models/cohesive_reading.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit/kit.dart';
import 'result_card.dart' show SearchPassageAction;
import 'score_explainer.dart';

/// **Cohesive body** (`spec/screens/search.md` §Composition, 4.40.0, ADR-078).
///
/// A single reading column replacing the split pane: per section a serif
/// heading, the bridge as an italic standfirst, then one passage card per
/// passage. Sections are separated by a rule — 36 above, 28 below.
///
/// **Nothing here rewrites what came back.** The passages are the reader's own
/// words, placed by the server; the arrangement is the whole feature. So this
/// widget renders `html` verbatim, prints the server's `link` rather than
/// building one, and does not re-sort, cap or deduplicate anything.
///
/// Three states, each its own (§States):
///
/// * **failure** — the §14.1 Failure block, in the column. A cohesive failure
///   is not an empty library, and `kept: 0` is not a failure.
/// * **no results** — `kept: 0`, the empty rendering.
/// * **reading** — the sections, under a quiet line when `note` is set.
class CohesiveColumn extends StatelessWidget {
  final CohesiveReading? reading;
  final String? error;
  final String? requestId;
  final VoidCallback onRetry;

  /// Opens the passage in the reader, scrolled to it — the server's own
  /// `link`, taken apart into the route this app already has. INV-21: the ids
  /// are the server's, never re-derived from anything else on screen.
  final void Function(CohesivePassage passage) onOpenInContext;
  final void Function(String documentId) onOpenSource;

  const CohesiveColumn({
    super.key,
    required this.reading,
    required this.error,
    required this.requestId,
    required this.onRetry,
    required this.onOpenInContext,
    required this.onOpenSource,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);

    Widget column(Widget child) => Center(
          // The wide frame's inner gutter — a reading column, not a page.
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: child,
          ),
        );

    if (error != null) {
      return column(KitFailureBlock(
        sentence: 'The cohesive reading could not be built.',
        detail: error!,
        requestId: requestId,
        onRetry: onRetry,
      ));
    }

    final r = reading;
    if (r == null || r.kept == 0) {
      return column(KitEmptyState(
        icon: Icons.auto_awesome_outlined,
        title: 'Nothing to arrange *yet.*',
        standfirst: 'No passage in the library cleared this breadth. Widening '
            'it asks the same question of more of your notes.',
      ));
    }

    return column(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A reading with `note` is COMPLETE — every kept passage is in it. One
        // line whether a single number was re-placed or the whole arrangement
        // fell back to one section: both are true of both, and the reader
        // cannot act on the difference. A notice, never the failure block.
        if (r.note != null) ...[
          Text(
            'The arrangement needed adjusting; every passage is here.',
            style: AppTheme.serif(
              fontSize: 14,
              height: 20 / 14,
              color: t.fgMuted,
            ).copyWith(fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: AppSpacing.s5),
        ],
        for (var i = 0; i < r.sections.length; i++) ...[
          if (i > 0) ...[
            const SizedBox(height: 36),
            Container(height: 1, color: t.rule),
            const SizedBox(height: 28),
          ],
          _Section(
            section: r.sections[i],
            onOpenInContext: onOpenInContext,
            onOpenSource: onOpenSource,
          ),
        ],
      ],
    ));
  }
}

class _Section extends StatelessWidget {
  final CohesiveSection section;
  final void Function(CohesivePassage passage) onOpenInContext;
  final void Function(String documentId) onOpenSource;

  const _Section({
    required this.section,
    required this.onOpenInContext,
    required this.onOpenSource,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          section.title,
          style: AppTheme.serif(
            fontSize: 22,
            height: 1.15,
            fontWeight: FontWeight.w500,
            color: t.fg,
          ).copyWith(letterSpacing: -0.015 * 22),
        ),
        if (section.bridge.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            section.bridge,
            style: AppTheme.serif(
              fontSize: 16,
              height: 24 / 16,
              color: t.fgLede,
            ).copyWith(fontStyle: FontStyle.italic),
          ),
        ],
        const SizedBox(height: 18),
        for (final p in section.passages)
          _CohesivePassageCard(
            passage: p,
            onOpenInContext: () => onOpenInContext(p),
            onOpenSource: () => onOpenSource(p.documentId),
          ),
      ],
    );
  }
}

/// A placed passage. The kit's §5.2 anatomy — meta row, serif quote, action bar
/// behind a rule — with the search screen's meta row rather than §5.2's mono
/// page-ref, exactly as [SearchResultCard] has it: a passage here is identified
/// by which source it came from and how well it matched.
///
/// The quote is the stored `html`, rendered as-is. It was sanitized at ingest
/// (INV-11) — the same trust basis the reader and the daily letter render on —
/// and `html` is null only on a chunk written before html existed, where `text`
/// is the whole passage.
class _CohesivePassageCard extends StatefulWidget {
  final CohesivePassage passage;
  final VoidCallback onOpenInContext;
  final VoidCallback onOpenSource;

  const _CohesivePassageCard({
    required this.passage,
    required this.onOpenInContext,
    required this.onOpenSource,
  });

  @override
  State<_CohesivePassageCard> createState() => _CohesivePassageCardState();
}

class _CohesivePassageCardState extends State<_CohesivePassageCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final p = widget.passage;
    final html = (p.html ?? '').trim();

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: AppRadius.mdR,
          border: Border.all(color: _hover ? t.borderStrong : t.border),
          boxShadow: _hover ? AppShadows.s1 : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // The plate reads the DOCUMENT's type, falling back to the
                // passage's `source_type` — the same pair the reference passes,
                // and both are in the one kind vocabulary (§6.4.1).
                KitFileBadge(
                  kitDocKind(p.document.type == 'unknown'
                      ? p.sourceType
                      : p.document.type),
                  size: KitBadgeSize.inline,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    p.document.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.serif(
                      fontSize: 15,
                      height: 1.2,
                      fontWeight: FontWeight.w500,
                      color: t.fg,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // A measured figure (the blended score the server ranked on),
                // in the mono face — the same slot the passages mode gives it,
                // and the same §16 explainer behind it (4.44.0, ADR-082). Both
                // surfaces carry ONE explainer; what differs is only the
                // element it hangs on.
                SearchScoreAnchor(
                  score: p.score,
                  cosine: p.cosine,
                  sourcePriority: p.sourcePriority,
                  child: Text(p.score.toStringAsFixed(2),
                      style: AppTheme.mono(fontSize: 10, color: t.fgMuted)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (html.isEmpty)
              // `text` is the representation `[Image: …]` lives in, so the
              // no-html branch draws its markers as §17.2 rather than as the
              // reader's own sentence.
              KitMarkedText(p.text,
                  style: AppTheme.serif(
                      fontSize: 17, height: 28 / 17, color: t.fg))
            else
              Html(
                data: html,
                extensions: AppTheme.htmlExtensions,
                style: AppTheme.htmlStyles(
                  t,
                  body: Style(
                    margin: Margins.zero,
                    fontSize: FontSize(17),
                    lineHeight: LineHeight.number(28 / 17),
                    color: t.fg,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Container(height: 1, color: t.rule),
            const SizedBox(height: 10),
            Row(
              children: [
                SearchPassageAction(
                  icon: Icons.visibility_outlined,
                  label: 'Open in context',
                  onTap: widget.onOpenInContext,
                ),
                const SizedBox(width: AppSpacing.s4),
                SearchPassageAction(
                  icon: Icons.bookmark_border,
                  label: 'Open source',
                  onTap: widget.onOpenSource,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
