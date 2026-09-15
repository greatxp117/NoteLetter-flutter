import 'package:flutter/material.dart';

import '../../models/search_result.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit/kit.dart';
import 'score_explainer.dart';

/// One ranked passage (`spec/screens/search.md` §Composition §Body).
///
/// A near-relative of the kit's passage card (§5.2) — surface, `--r-md`, a
/// serif quote at reading size, an action bar behind a top rule — but its meta
/// row is not §5.2's mono page-ref: a search result is identified by **which
/// source it came from and how well it matched**, so the head is
/// `[file badge · title · score]`. That is why this is a screen component and
/// not a call to `KitPassageCard` with the wrong parts in it.
///
/// The score is a **measured** figure (the backend's similarity), so it earns
/// its slot; the meter is the bar plus the number, never the bar alone.
class SearchResultCard extends StatefulWidget {
  final SearchResult result;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onOpenSource;

  /// The shelf this result's source sits on, if any — the reference shows one.
  final String? shelfTitle;
  final String? shelfColorToken;

  const SearchResultCard({
    super.key,
    required this.result,
    required this.selected,
    required this.onTap,
    required this.onOpenSource,
    this.shelfTitle,
    this.shelfColorToken,
  });

  @override
  State<SearchResultCard> createState() => _SearchResultCardState();
}

class _SearchResultCardState extends State<SearchResultCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final r = widget.result;
    final text = r.chunk.text;
    final excerpt = text.length > 220 ? '${text.substring(0, 220)}…' : text;

    final borderColor = widget.selected
        ? t.accentChipBorder
        : (_hover ? t.borderStrong : t.border);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          margin: const EdgeInsets.only(bottom: AppSpacing.s3),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: AppRadius.mdR,
            border: Border.all(color: borderColor),
            boxShadow: _hover || widget.selected ? AppShadows.s2 : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  KitFileBadge(kitDocKind(r.document.type),
                      size: KitBadgeSize.inline),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      r.document.title,
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
                  _ScoreMeter(
                    score: r.score,
                    cosine: r.cosine,
                    sourcePriority: r.sourcePriority,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s3),
              // The matched span is marked, not merely quoted: the mark is what
              // says "this is the part that answered you".
              //
              // `chunk.text` is the representation that carries `[Image: …]`
              // (the derivation writes it there and never into `html`), so
              // this row is one of the two surfaces §17.2 exists for. Markers
              // draw as Marker inline — never as the matched quotation, and
              // never stripped: across production they are a median 31.6% of a
              // marker-bearing chunk, and for a Reel whose burned-in text IS
              // the content, deleting them deletes the document.
              KitMarkedText(
                excerpt,
                style: AppTheme.serif(
                  fontSize: 17,
                  height: 28 / 17,
                  color: t.fg,
                ).copyWith(backgroundColor: t.highlight),
              ),
              const SizedBox(height: 14),
              Container(height: 1, color: t.rule),
              const SizedBox(height: AppSpacing.s3),
              Row(
                children: [
                  KitPassageAction(
                    icon: Icons.visibility_outlined,
                    label: 'Open source',
                    onTap: widget.onOpenSource,
                  ),
                  if (widget.shelfTitle != null) ...[
                    const Spacer(),
                    KitTag(
                      widget.shelfTitle!,
                      variant: KitTagVariant.shelf,
                      colorToken: widget.shelfColorToken,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The similarity meter: a 42×4 track filled to the score, and **the number
/// beside it**. A bar alone is a shape; the figure is what makes it a
/// measurement, and this one is measured (the backend's blended rank).
///
/// The meter is also the **anchor** of the §16 score explainer (4.44.0,
/// ADR-082) — the element whose figure the popover breaks down. It carried
/// `cursor: help` on the reference for fifteen months with nothing behind it;
/// [SearchScoreAnchor] is what that cursor was promising, and it draws nothing
/// when the response carried no components to explain.
class _ScoreMeter extends StatelessWidget {
  final double score;
  final double? cosine;
  final double? sourcePriority;

  const _ScoreMeter({
    required this.score,
    required this.cosine,
    required this.sourcePriority,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final clamped = score.clamp(0.0, 1.0);
    return SearchScoreAnchor(
      score: score,
      cosine: cosine,
      sourcePriority: sourcePriority,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: t.surfaceSunken,
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: clamped,
              child: Container(
                decoration: BoxDecoration(
                  color: t.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          const SizedBox(width: 7),
          Text(clamped.toStringAsFixed(2),
              style: AppTheme.mono(fontSize: 10, color: t.fgMuted)),
        ],
      ),
    );
  }
}
