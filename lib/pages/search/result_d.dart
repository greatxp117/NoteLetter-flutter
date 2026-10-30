import 'package:flutter/material.dart';

import '../../models/search_result.dart';
import '../../shared/extraction_markers.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit/kit.dart';
import 'score_explainer.dart';

/// Where a result's passage is cut while the row is folded
/// (`spec/screens/search.md` §Composition, **Results**): near [near]
/// characters, **at a word**, and **never inside an extraction marker** —
/// a clipped `[Image: …]` no longer matches the marker pattern and would
/// print its brackets (§17.2, ADR-089). Returns the length to keep; the
/// whole text when it is short enough.
///
/// Web `ResultD` cuts at 280 and then runs past any marker the cut lands in;
/// the word comes first here (the spec's *at a word*), so that the marker
/// rule, applied after it, still has the last say.
int searchSnippetCut(String text, {int near = 280}) {
  if (text.length <= near) return text.length;
  var cut = near;
  // The last space at or before the cut, unless the passage runs a long way
  // without one (a URL, a table row), when the cut stays where it was.
  final ws = text.lastIndexOf(RegExp(r'\s'), near);
  if (ws > near * 0.6) cut = ws;
  for (final m in markerRe.allMatches(text)) {
    if (m.start >= cut) break;
    if (m.end > cut) cut = m.end;
  }
  return cut;
}

/// A result's head in a column this narrow or narrower drops the rank column
/// to 28, moves the score under the meta and takes the passage's indent away
/// (web `@container hx (max-width:600px)`).
const double searchNarrowColumn = 600;

/// The register's 1px `--fg` rule over its rows (`.dp-results`).
class SearchRegister extends StatelessWidget {
  final List<Widget> children;
  const SearchRegister({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('search-register'),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Tokens.of(context).fg)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );
}

/// **A result, in D** (`spec/screens/search.md` §Composition; web `ResultD`).
///
/// Its rank (`01`, mono, `--accent-text`), the source's title (serif 600
/// 18/24 — the control that opens the row), under it the source's kind as its
/// cover's label (kit §33 [kitTypeLabel], mono caps) and its first shelf (a
/// swatch and the name), the score meter at the row's end; then the matched
/// passage, marked, cut by [searchSnippetCut]; then *Open source* (the book;
/// the reader by `chunk.document_id`) and *Read it in context*.
///
/// **Opened** — the title, the passage or *Read it in context* — the row
/// shows the passage whole among its neighbours (the chunk-context read; the
/// neighbours in `--fg-muted`) and the link reads *Fold it away*. A failed
/// context read is a §14.2 line under it, never the passage drawn as if it
/// stood alone. The page keeps one row open at a time and fires
/// `result_opened` on opening only.
///
/// Reference metrics (web `app-d-pages.css` `.dp-res*`): `18px 0 16px` over a
/// 1px `--rule`; the head `40px minmax(0,1fr) auto`, gap `4px 16px`; the
/// passage serif 17/28 at most 68ch, 12 under the head and indented 56;
/// actions 12 under, gap `8px 22px`. A column of [searchNarrowColumn] or less:
/// rank 28, the score under the meta (6 above), no indent.
class SearchResultD extends StatelessWidget {
  final SearchResult result;
  final int rank;

  /// The first shelf the source sits on (web `shelfFor`), or null.
  final String? shelfTitle;
  final String? shelfColor;

  final bool open;
  final VoidCallback onToggle;
  final VoidCallback onOpenSource;

  /// The chunk-context window (the match among its ±2 neighbours, in
  /// `chunk_index` order). Empty while the read is out — the passage then
  /// stands alone until the neighbours land, as web's does.
  final List<Chunk> context;

  /// The context read's failure, verbatim (`screens/search.md` §States).
  final String? contextError;

  const SearchResultD({
    super.key,
    required this.result,
    required this.rank,
    required this.open,
    required this.onToggle,
    required this.onOpenSource,
    this.shelfTitle,
    this.shelfColor,
    this.context = const [],
    this.contextError,
  });

  @override
  Widget build(BuildContext buildContext) {
    final t = Tokens.of(buildContext);
    return LayoutBuilder(
      builder: (ctx, c) {
        final narrow = c.maxWidth <= searchNarrowColumn;
        final indent = narrow ? 0.0 : 56.0;
        final r = result;
        final type = r.document.type.isEmpty || r.document.type == 'unknown'
            ? r.chunk.sourceType
            : r.document.type;
        final title = r.document.title.isEmpty ? 'Untitled' : r.document.title;

        final rankText = Text(
          rank.toString().padLeft(2, '0'),
          style: KitText.monoMeta(ctx,
              fontSize: 11, letterSpacing: 0.06, color: t.accentText),
        );
        final titleControl = KitDTap(
          key: ValueKey('search-title-$rank'),
          label: title,
          expanded: open,
          onTap: onToggle,
          builder: (context, hover, focus) => DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              border: focus ? Border.all(color: t.accent, width: 2) : null,
            ),
            child: Text(
              title,
              style: KitText.title(context,
                      fontSize: 18, height: 24 / 18, weight: FontWeight.w600)
                  .copyWith(
                decoration: hover ? TextDecoration.underline : null,
                decorationColor: t.linkDecor,
              ),
            ),
          ),
        );
        final meta = Wrap(
          spacing: 14,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              kitTypeLabel(type).toUpperCase(),
              style: KitText.monoMeta(ctx, fontSize: 10.5, letterSpacing: 0.1),
            ),
            if (shelfTitle != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  KitShelfSwatch(
                    kitShelfColorOf(ctx, shelfColor),
                    height: 10,
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(shelfTitle!, style: KitText.note(ctx)),
                  ),
                ],
              ),
          ],
        );
        final score = _ScoreMeter(
          score: r.score,
          cosine: r.cosine,
          sourcePriority: r.sourcePriority,
          sourcePrioritySet: r.sourcePrioritySet,
          leading: narrow,
        );

        final head = narrow
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  SizedBox(width: 28, child: rankText),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        titleControl,
                        const SizedBox(height: 4),
                        meta,
                        const SizedBox(height: 4 + 6),
                        score,
                      ],
                    ),
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        SizedBox(width: 40, child: rankText),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              titleControl,
                              const SizedBox(height: 4),
                              meta,
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  score,
                ],
              );

        final reading = KitText.bodyReading(ctx, fontSize: 17, height: 28);
        final quiet = KitText.bodyReading(ctx,
            fontSize: 17, height: 28, color: t.fgMuted);
        final text = r.chunk.text;
        final cut = open ? text.length : searchSnippetCut(text);
        final idx = r.chunk.chunkIndex;
        final before = open
            ? [for (final n in context) if (n.chunkIndex < idx) n]
            : const <Chunk>[];
        final after = open
            ? [for (final n in context) if (n.chunkIndex > idx) n]
            : const <Chunk>[];

        Widget neighbour(Chunk n) => Padding(
              key: ValueKey('search-neighbour-${n.chunkId}'),
              padding: const EdgeInsets.only(top: 12),
              // `text`, not `html` — the one representation `[Image: …]`
              // reaches, so the markers draw inline here too (§17.2).
              child: KitMarkedText(n.text, style: quiet),
            );

        final passage = Text.rich(
          key: ValueKey('search-passage-$rank'),
          TextSpan(
            style: reading,
            children: [
              TextSpan(
                style: reading.copyWith(backgroundColor: t.highlight),
                children: [
                  for (final p in splitMarkers(
                      KitMarkedText.collapse(text.substring(0, cut)).trim()))
                    p.isMark
                        ? KitMarkerInline.span(ctx, p, hostFontSize: 17)
                        : TextSpan(text: p.text),
                ],
              ),
              if (cut < text.length) const TextSpan(text: '…'),
            ],
          ),
        );

        // `.dp-res-q{max-width:68ch}` — the `ch` of the box's own face, which
        // is the body's (sans 16, inherited), not the passage's serif.
        final quote = ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: 68 * KitText.ch(ctx, KitText.body(ctx))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, n) in before.indexed)
                i == 0
                    ? KitMarkedText(n.text,
                        key: ValueKey('search-neighbour-${n.chunkId}'),
                        style: quiet)
                    : neighbour(n),
              if (before.isNotEmpty) const SizedBox(height: 12),
              passage,
              for (final n in after) neighbour(n),
            ],
          ),
        );

        return Container(
          key: ValueKey('search-row-$rank'),
          padding: const EdgeInsets.only(top: 18, bottom: 16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.rule)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              head,
              Padding(
                padding: EdgeInsets.only(top: 12, left: indent),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: open
                      ? quote
                      : MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onToggle,
                            child: quote,
                          ),
                        ),
                ),
              ),
              if (open && contextError != null)
                Padding(
                  padding: EdgeInsets.only(top: 10, left: indent),
                  child: KitFailureInline(
                      'The surrounding passages could not be loaded — '
                      '$contextError'),
                ),
              Padding(
                padding: EdgeInsets.only(top: 12, left: indent),
                child: Wrap(
                  spacing: 22,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // The document id lives on the CHUNK: `fn_search_notes`
                    // returns the document as `snap.to_dict()`, which has no
                    // id. The action's label and glyph are the kit's
                    // (search.md §Action glyphs: the book), drawn as D's
                    // quiet link.
                    KitSourceLink(
                      docId: r.chunk.documentId,
                      onOpen: onOpenSource,
                      builder: (context, go) {
                        final a = KitPassageAction.openSource(onTap: go);
                        return KitHxLink(a.label, icon: a.icon, onTap: go);
                      },
                    ),
                    KitHxLink(
                      open ? 'Fold it away' : 'Read it in context',
                      key: ValueKey('search-toggle-$rank'),
                      onTap: onToggle,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The score meter (§Score explainer): a 42×4 measured bar (`--accent` on
/// `--surface-sunken`) and **the figure beside it** (mono 10 `--fg-muted`),
/// the anchor of the §16 explainer. A bar alone is a shape; the figure is
/// what makes it a measurement.
///
/// [leading]: under the meta at the column's start (a narrow column), where
/// web opens the explainer rightward (`.pop{right:auto;left:0}`). The kit's
/// popover opens flush to its anchor's trailing edge, so here the anchor is
/// the popover's own width with the meter at its start — the panel then lines
/// up with the meter instead of running off the page to the left.
class _ScoreMeter extends StatelessWidget {
  final double score;
  final double? cosine;
  final double? sourcePriority;
  final bool? sourcePrioritySet;
  final bool leading;

  const _ScoreMeter({
    required this.score,
    required this.cosine,
    required this.sourcePriority,
    this.sourcePrioritySet,
    this.leading = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final fill = score.clamp(0.0, 1.0);
    final meter = Row(
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
            widthFactor: fill,
            child: Container(
              decoration: BoxDecoration(
                color: t.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          score.toStringAsFixed(2),
          style: KitText.monoFigure(context, fontSize: 10, color: t.fgMuted),
        ),
      ],
    );
    final anchor = SearchScoreAnchor(
      score: score,
      cosine: cosine,
      sourcePriority: sourcePriority,
      sourcePrioritySet: sourcePrioritySet,
      child: leading
          ? SizedBox(
              width: KitAnchoredPopover.panelWidth,
              child: Align(alignment: Alignment.centerLeft, child: meter),
            )
          : meter,
    );
    // The kit's anchor keeps 4px and its 1px focus ring around the meter;
    // under the meta the bar starts on the title's edge, as web's does.
    return leading
        ? Transform.translate(offset: const Offset(-5, 0), child: anchor)
        : anchor;
  }
}
