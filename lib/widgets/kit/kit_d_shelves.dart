import 'dart:math' as math;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../models/document.dart';
import '../../models/tag.dart';
import '../../shared/passage_figure.dart';
import '../../shared/shelf_tree.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_controls.dart' show KitLetterChip;
import 'kit_d_covers.dart' show KitCoverItem, kitCoverCloth;
import 'kit_d_format.dart';
import 'kit_d_home.dart' show KitDNone, KitHxLink;
import 'kit_d_parts.dart';
import 'kit_failure.dart' show KitFailureInline;
import 'kit_frame.dart' show KitScrollView;
import 'kit_source_link.dart';

// Component kit §42 — the shelves as a listing (web `src/kit/d/Shelves.jsx`):
// the catalogue (List) or a row of covers per shelf (Grid), under the app-wide
// List / Grid choice. Home's shelves and the Shelves index both draw it; the
// Library's Shelf facet and every register row's shelf tag read its model.

/// One shelf as the listing draws it: a top-level shelf holding its subtree
/// (5.28.0, ADR-185), or the Unshelved node (`id == '_un'`).
class KitShelfNode {
  final String id;
  final String title;

  /// The shelf's stored colour NAME (`AppColors.shelfColor` resolves it for the
  /// theme), or null — Unshelved, or a shelf with none.
  final String? color;
  final int depth;

  /// Every COMPLETE volume in the subtree.
  final List<Document> vols;

  /// The volumes this shelf holds that no child holds.
  final List<Document> own;
  final List<KitShelfNode> kids;

  /// Σ `chunk_count` over [vols] (a count never taken adds nothing).
  final int passages;

  /// [vols] never opened (`view_count == 0`).
  final int unread;

  /// The letter mode in force (`ShelfTree.letterMode`), or null on Unshelved.
  final String? mode;
  final String description;

  const KitShelfNode({
    required this.id,
    required this.title,
    required this.color,
    required this.depth,
    required this.vols,
    required this.own,
    required this.kids,
    required this.passages,
    required this.unread,
    required this.mode,
    required this.description,
  });

  bool get unshelved => id == kitUnshelvedId;
}

/// The Unshelved node's id (web `'_un'`): it opens the Library, never a shelf.
const String kitUnshelvedId = '_un';

/// The model every D listing reads (web `shelfModel`).
class KitShelfModel {
  /// Top-level shelves, each holding its subtree, in tree order.
  final List<KitShelfNode> roots;

  /// Complete volumes no shelf holds.
  final List<Document> unshelved;

  /// [unshelved] as a node, or null when there are none.
  final KitShelfNode? unshelvedNode;

  /// A document id → the DEEPEST node that holds it as its own — the shelf a
  /// row's tag names. Absent for an unshelved volume.
  final Map<String, KitShelfNode> homeOf;

  /// Every complete volume, in the documents read's order (newest first).
  final List<Document> complete;

  /// Σ `chunk_count` over [complete].
  final int passages;

  const KitShelfModel({
    required this.roots,
    required this.unshelved,
    required this.unshelvedNode,
    required this.homeOf,
    required this.complete,
    required this.passages,
  });

  /// The complete volumes — the library's figure.
  int get total => complete.length;

  /// The listing's nodes: the shelves, then Unshelved when it holds anything.
  List<KitShelfNode> get nodes => [
    ...roots,
    if (unshelvedNode != null) unshelvedNode!,
  ];

  /// Every shelf in tree order, a child under its parent (the Library's Shelf
  /// facet; web `flatShelves`).
  List<KitShelfNode> get flat {
    final out = <KitShelfNode>[];
    void walk(KitShelfNode n) {
      out.add(n);
      n.kids.forEach(walk);
    }

    roots.forEach(walk);
    return out;
  }
}

int _sum(Iterable<Document> vols) =>
    vols.fold<int>(0, (n, v) => n + (v.chunkCount ?? 0));

/// Web `shelfModel(shelves, documents)`.
KitShelfModel kitShelfModel(List<Tag> shelves, List<Document> documents) {
  final complete = documents
      .where((d) => d.status == DocumentStatus.complete)
      .toList();
  final tree = ShelfTree(shelves);
  final homeOf = <String, KitShelfNode>{};

  KitShelfNode node(Tag s, int depth) {
    final ids = tree.subtreeIds(s.id);
    final vols = complete.where((d) => inSubtree(d.tagIds, ids)).toList();
    final kids = [for (final c in tree.childrenOf(s.id)) node(c, depth + 1)];
    final inKids = <String>{
      for (final k in kids)
        for (final v in k.vols) v.id,
    };
    final own = vols.where((v) => !inKids.contains(v.id)).toList();
    final n = KitShelfNode(
      id: s.id,
      title: s.title.isEmpty ? 'Untitled' : s.title,
      color: s.color,
      depth: depth,
      vols: vols,
      own: own,
      kids: kids,
      passages: _sum(vols),
      unread: vols.where((v) => v.viewCount == 0).length,
      mode: tree.letterMode(s.id).mode,
      description: s.description ?? '',
    );
    // Children are built first, so the deepest holder claims a volume.
    for (final v in own) {
      homeOf.putIfAbsent(v.id, () => n);
    }
    return n;
  }

  final roots = [for (final s in tree.roots) node(s, 0)];
  final unshelved = complete.where((d) => !homeOf.containsKey(d.id)).toList();
  final unshelvedNode = unshelved.isEmpty
      ? null
      : KitShelfNode(
          id: kitUnshelvedId,
          title: 'Unshelved',
          color: null,
          depth: 0,
          vols: unshelved,
          own: unshelved,
          kids: const [],
          passages: _sum(unshelved),
          unread: unshelved.where((v) => v.viewCount == 0).length,
          mode: null,
          description: 'Volumes no shelf has claimed yet.',
        );
  return KitShelfModel(
    roots: roots,
    unshelved: unshelved,
    unshelvedNode: unshelvedNode,
    homeOf: homeOf,
    complete: complete,
    passages: _sum(complete),
  );
}

// ── §42 The listing ─────────────────────────────────────────────────────────

/// What a listing does when the reader picks something. [onOpenShelf] gets
/// the node — Unshelved ([KitShelfNode.unshelved]) opens the Library, a shelf
/// its own page; a sub-shelf head hands its own node. [onAsk] null is Ask
/// this shelf ABSENT (generative AI off, 5.29.0, ADR-186).
class KitShelfActions {
  final void Function(KitShelfNode node) onOpenShelf;
  final void Function(KitShelfNode node)? onAsk;
  const KitShelfActions({required this.onOpenShelf, this.onAsk});
}

/// The letter chip on a listed shelf (screens/library.md §The letter chip):
/// only on a NAMED shelf, only where its mode in force changes the letter,
/// only while the letter is measured on.
KitLetterChip? kitShelfChipOf(KitShelfNode n, {required bool letterOn}) =>
    n.unshelved ? null : KitLetterChip.forShelf(n.mode, letterOn: letterOn);

/// `{N volumes} · {N passages}` and ` · {n} unread` when any (web `metaOf` +
/// `unreadOf`). Totals over a subtree: a count never taken adds nothing.
String kitShelfMeta(KitShelfNode n) =>
    '${kitCounted(n.vols.length, 'volume')} · '
    '${kitCounted(n.passages, 'passage')}'
    '${n.unread != 0 ? ' · ${n.unread} unread' : ''}';

/// A shelf's colour for this theme: its stored name or legacy hex, an
/// unrecognised one the muted text colour (web `shelfColorVar`); null for
/// Unshelved, which has none.
Color? kitShelfPaint(BuildContext context, KitShelfNode n) {
  if (n.unshelved) return null;
  final t = Tokens.of(context);
  return AppColors.shelfColor(n.color, dark: t.isDark) ?? t.fgSubtle;
}

/// §42 — the shelves as a listing (web `ShelfListing`): the catalogue in List,
/// covers in Grid, under the app-wide List / Grid choice ([view]). Before the
/// reads have answered it draws the skeleton, and when either read was
/// refused, §14.2 — FIRST, whatever the model holds: a refused documents read
/// would draw every shelf as *0 volumes · Nothing on this shelf yet*, and a
/// refused shelves read every volume as Unshelved — statements a failed read
/// is no evidence for (INV-24). Only an answered, empty library says *No
/// shelves yet*.
class KitShelfListing extends StatelessWidget {
  final KitShelfModel model;
  final String view;
  final bool letterOn;
  final bool loaded;
  final String? libError;
  final KitShelfActions actions;

  /// *No shelves yet — create one from the Shelves page.*'s link.
  final VoidCallback onNewShelf;

  /// Catalogue rows per shelf.
  final int limit;

  const KitShelfListing({
    super.key,
    required this.model,
    required this.view,
    required this.letterOn,
    required this.loaded,
    required this.libError,
    required this.actions,
    required this.onNewShelf,
    this.limit = 8,
  });

  @override
  Widget build(BuildContext context) {
    if (libError != null) {
      return KitFailureInline('Your library could not be read — $libError');
    }
    if (!loaded) return const KitSkeletonLines();
    if (model.roots.isEmpty && model.unshelved.isEmpty) {
      return Text.rich(
        TextSpan(
          children: [
            const TextSpan(text: 'No shelves yet — '),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: KitHxLink(
                'create one from the Shelves page',
                onTap: onNewShelf,
              ),
            ),
            const TextSpan(text: '.'),
          ],
        ),
        style: KitDNone.style(context),
      );
    }
    return view == 'grid'
        ? KitShelfCovers(
            nodes: model.nodes,
            letterOn: letterOn,
            actions: actions,
          )
        : KitShelfCatalogue(
            nodes: model.nodes,
            letterOn: letterOn,
            actions: actions,
            limit: limit,
          );
  }
}

// ── Catalogue (List) ────────────────────────────────────────────────────────

/// §42's List form (web `ShelfCatalogue`): one catalogue column per shelf —
/// `repeat(auto-fit, minmax(min(100%, 320px), 1fr))`, 48 apart.
class KitShelfCatalogue extends StatelessWidget {
  final List<KitShelfNode> nodes;
  final bool letterOn;
  final KitShelfActions actions;
  final int limit;

  const KitShelfCatalogue({
    super.key,
    required this.nodes,
    required this.letterOn,
    required this.actions,
    this.limit = 8,
  });

  static const double _min = 320;
  static const double _gap = 48;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final w = c.maxWidth.isFinite ? c.maxWidth : _min;
      final cols = math.max(1, ((w + _gap) / (_min + _gap)).floor());
      final cw = (w - _gap * (cols - 1)) / cols;
      return Wrap(
        spacing: _gap,
        runSpacing: _gap,
        children: [
          for (var i = 0; i < nodes.length; i++)
            SizedBox(
              width: cw,
              child: _CatColumn(
                node: nodes[i],
                index: i,
                letterOn: letterOn,
                actions: actions,
                limit: limit,
              ),
            ),
        ],
      );
    },
  );
}

/// One catalogue column (web `CatColumn`): a 3px rule in the shelf's colour,
/// `§ {numeral}` and the letter chip, the title, its meta, its description,
/// then up to [limit] rows — its own volumes, then each sub-shelf's under a
/// head — and *{n} more volumes*, *Open shelf →*, *Ask this shelf*.
class _CatColumn extends StatelessWidget {
  final KitShelfNode node;
  final int index;
  final bool letterOn;
  final KitShelfActions actions;
  final int limit;

  const _CatColumn({
    required this.node,
    required this.index,
    required this.letterOn,
    required this.actions,
    required this.limit,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final color = kitShelfPaint(context, node);
    var left = limit;
    final own = node.own.take(left).toList();
    left -= own.length;
    final kids = <(KitShelfNode, List<Document>)>[];
    for (final k in node.kids) {
      final vols = k.vols.take(math.max(0, left)).toList();
      left -= vols.length;
      kids.add((k, vols));
    }
    final shown = own.length + kids.fold<int>(0, (n, x) => n + x.$2.length);
    final more = node.vols.length - shown;
    final chip = kitShelfChipOf(node, letterOn: letterOn);
    return Container(
      key: ValueKey('cat-${node.id}'),
      padding: const EdgeInsets.only(top: 14),
      decoration: color == null
          ? null
          : BoxDecoration(
              border: Border(top: BorderSide(color: color, width: 3)),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 20),
            child: Row(
              children: [
                Text(
                  node.unshelved ? '§ —' : '§ ${KitD.numeral(index)}',
                  style: AppTheme.mono(
                    fontSize: 11,
                    letterSpacing: 0.16 * 11,
                    color: t.fgSubtle,
                  ),
                ),
                const Spacer(),
                if (chip != null) chip.pill(),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: _ShelfTitle(
              node.title,
              size: 32,
              height: 1.06,
              tracking: -0.02,
              opsz: 40,
              underline: color ?? t.fgSubtle,
              onTap: () => actions.onOpenShelf(node),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            kitShelfMeta(node),
            style: AppTheme.mono(
              fontSize: 11,
              letterSpacing: 0.04 * 11,
              color: t.fgSubtle,
            ),
          ),
          if (node.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 48 * 16 * 0.5),
                  child: Text(
                    node.description,
                    style: AppTheme.serif(
                      fontSize: 16,
                      height: 25 / 16,
                      fontStyle: FontStyle.italic,
                      color: t.fgLede,
                      opsz: 18,
                    ),
                  ),
                ),
              ),
            ),
          Container(
            margin: const EdgeInsets.only(top: 20),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: t.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final v in own) _CatRow(v),
                for (final (k, vols) in kids)
                  if (vols.isNotEmpty)
                    _CatSub(
                      kid: k,
                      vols: vols,
                      onOpen: () => actions.onOpenShelf(k),
                    ),
                if (node.vols.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: t.rule)),
                    ),
                    child: Text(
                      'Nothing on this shelf yet.',
                      style: AppTheme.serif(
                        fontSize: 15,
                        fontStyle: FontStyle.italic,
                        color: t.fgSubtle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Wrap(
              spacing: 20,
              runSpacing: 10,
              children: [
                if (more > 0)
                  KitHxLink(
                    kitCounted(more, 'more volume'),
                    onTap: () => actions.onOpenShelf(node),
                  ),
                KitHxLink(
                  'Open shelf →',
                  onTap: () => actions.onOpenShelf(node),
                ),
                if (!node.unshelved && actions.onAsk != null)
                  KitHxLink(
                    'Ask this shelf',
                    icon: Icons.chat_bubble_outline,
                    onTap: () => actions.onAsk!(node),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A shelf's title as a control (`.cat-title`, `.cvs-title`): serif 600,
/// letterpressed; hover underlines it 2px in the shelf's own colour.
class _ShelfTitle extends StatelessWidget {
  final String text;
  final double size;
  final double height;
  final double tracking;
  final double opsz;
  final Color underline;
  final VoidCallback onTap;

  const _ShelfTitle(
    this.text, {
    required this.size,
    required this.height,
    required this.tracking,
    required this.opsz,
    required this.underline,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return KitDTap(
      label: text,
      onTap: onTap,
      builder: (context, hover, focus) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: focus ? Border.all(color: t.accent, width: 2) : null,
        ),
        child: Semantics(
          header: true,
          child: Text(
            text,
            style:
                AppTheme.serif(
                  fontSize: size,
                  height: height,
                  fontWeight: FontWeight.w600,
                  letterSpacing: tracking * size,
                  color: t.fg,
                  opsz: opsz,
                ).copyWith(
                  shadows: AppShadows.letterpress,
                  decoration: hover ? TextDecoration.underline : null,
                  decorationColor: underline,
                  decorationThickness: 2,
                ),
          ),
        ),
      ),
    );
  }
}

/// One catalogue row (web `CatRow`): a link to the source — the unread dot,
/// the title, the author, a dotted leader and the passage count (an EMPTY
/// cell when never taken, ADR-109).
class _CatRow extends StatelessWidget {
  final Document v;
  const _CatRow(this.v);

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final title = v.title.isEmpty ? 'Untitled' : v.title;
    final unread = v.viewCount == 0;
    return KitSourceLink(
      docId: v.id,
      builder: (context, open) => KitRowHover(
        onTap: open,
        label: '$title${unread ? ' (unread)' : ''}',
        child: Container(
          padding: const EdgeInsets.fromLTRB(0, 9, 2, 9),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.rule)),
          ),
          child: _CatRowLine(doc: v, title: title, unread: unread),
        ),
      ),
    );
  }
}

class _CatRowLine extends StatelessWidget {
  final Document doc;
  final String title;
  final bool unread;
  const _CatRowLine({
    required this.doc,
    required this.title,
    required this.unread,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    // Measured as the Text widgets draw: over the ambient default style.
    final base = DefaultTextStyle.of(context).style;
    final titleStyle = base.merge(
      AppTheme.serif(fontSize: 16.5, height: 22 / 16.5, color: t.fg, opsz: 18),
    );
    final authorStyle = base.merge(
      AppTheme.serif(
        fontSize: 14,
        fontStyle: FontStyle.italic,
        color: t.fgSubtle,
      ),
    );
    final countStyle = base.merge(
      AppTheme.mono(
        fontSize: 12,
        color: t.fgMuted,
      ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
    );
    final author = (doc.author ?? '').trim();
    final n = doc.chunkCount;
    final count = n == null ? '' : '$n';
    double widthOf(String s, TextStyle st) {
      if (s.isEmpty) return 0;
      final tp = TextPainter(
        text: TextSpan(text: s, style: st),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final w = tp.width;
      tp.dispose();
      return w;
    }

    final baseTp = TextPainter(
      text: TextSpan(text: ' ', style: titleStyle),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    final baseline = baseTp.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    baseTp.dispose();
    return LayoutBuilder(
      builder: (context, c) {
        // `.cat-row-t {flex: 0 1 auto}`, `.cat-row-a {flex: 0 100 auto}`,
        // `.cat-lead {flex: 1 1 18px; min-width: 18px}`: the author gives way
        // first, then the title; the leader keeps 18.
        const gap = 8.0;
        final gaps = (unread ? 1 : 0) + 1 + (author.isEmpty ? 0 : 1) + 1;
        final avail = math.max(
          0.0,
          c.maxWidth -
              (unread ? 6 : 0) -
              widthOf(count, countStyle) -
              18 -
              gaps * gap,
        );
        final tw = math.min(widthOf(title, titleStyle), avail) + 0.5;
        final aw = author.isEmpty
            ? 0.0
            : math.min(
                widthOf(author, authorStyle) + 0.5,
                math.max(0.0, avail - tw),
              );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            if (unread) ...[
              Baseline(
                baseline: baseline - 4,
                baselineType: TextBaseline.alphabetic,
                child: const KitUnreadDot(),
              ),
              const SizedBox(width: gap),
            ],
            SizedBox(
              width: tw,
              child: Text(
                title,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
            ),
            if (aw > 0) ...[
              const SizedBox(width: gap),
              SizedBox(
                width: aw,
                child: Text(
                  author,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: authorStyle,
                ),
              ),
            ] else if (author.isNotEmpty)
              const SizedBox(width: gap),
            const SizedBox(width: gap),
            Expanded(
              child: CustomPaint(
                painter: _DotLeader(t.borderStrong, baseline - 4),
                child: Text(' ', style: titleStyle),
              ),
            ),
            const SizedBox(width: gap),
            Text(count, style: countStyle),
          ],
        );
      },
    );
  }
}

/// `.cat-lead` — a 1.5px dotted `--border-strong` line, 4 above the baseline.
class _DotLeader extends CustomPainter {
  final Color color;
  final double y;
  const _DotLeader(this.color, this.y);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    for (var x = 0.75; x < size.width; x += 3) {
      canvas.drawCircle(Offset(x, y), 0.75, p);
    }
  }

  @override
  bool shouldRepaint(_DotLeader old) => old.color != color || old.y != y;
}

/// A sub-shelf inside a catalogue column (`.cat-sub`): its head — a cloth
/// swatch, its title in mono caps, its volume count — opening it, then its
/// rows indented 18.
class _CatSub extends StatelessWidget {
  final KitShelfNode kid;
  final List<Document> vols;
  final VoidCallback onOpen;

  const _CatSub({required this.kid, required this.vols, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitDTap(
          label: kid.title,
          onTap: onOpen,
          builder: (context, hover, focus) => Padding(
            padding: const EdgeInsets.only(top: 13, bottom: 5),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 10,
                  decoration: BoxDecoration(
                    color: kitShelfPaint(context, kid) ?? t.fgSubtle,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(1),
                      bottomLeft: Radius.circular(1),
                      topRight: Radius.circular(2),
                      bottomRight: Radius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    kid.title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.mono(
                      fontSize: 10.5,
                      letterSpacing: 0.14 * 10.5,
                      color: hover ? t.fg : t.fgMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  kitCounted(kid.vols.length, 'volume'),
                  style: AppTheme.mono(
                    fontSize: 10.5,
                    letterSpacing: 0.04 * 10.5,
                    color: t.fgSubtle,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final v in vols) _CatRow(v)],
          ),
        ),
      ],
    );
  }
}

// ── Covers (Grid) ───────────────────────────────────────────────────────────

/// §42's Grid form (web `ShelfCovers`): one shelf per row, 46 apart, each a
/// head and a horizontally scrolling row of its covers.
class KitShelfCovers extends StatelessWidget {
  final List<KitShelfNode> nodes;
  final bool letterOn;
  final KitShelfActions actions;

  const KitShelfCovers({
    super.key,
    required this.nodes,
    required this.letterOn,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < nodes.length; i++) ...[
        if (i > 0) const SizedBox(height: 46),
        _CoverShelf(node: nodes[i], letterOn: letterOn, actions: actions),
      ],
    ],
  );
}

/// The cloth swatch of a shelf head (`.cvs-swatch`, 14×20; `.cvs-group-l`'s
/// 8×10): the covers' own cloth at its first depth, a fixed object in both
/// themes. Web mixes the swatch 72% toward ink-700 (46% in dark); this reads
/// the covers' tone 0 (70%; dark keeps the hue, as the covers do) because the
/// kit's OKLab mix is test-only — a recorded deviation.
Color kitShelfCloth(Color shelf, {required bool dark}) =>
    kitCoverCloth(shelf, 0, dark: dark);

class _CoverShelf extends StatelessWidget {
  final KitShelfNode node;
  final bool letterOn;
  final KitShelfActions actions;

  const _CoverShelf({
    required this.node,
    required this.letterOn,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final color = kitShelfPaint(context, node);
    final chip = kitShelfChipOf(node, letterOn: letterOn);
    final groups = <({KitShelfNode? kid, List<Document> vols})>[
      if (node.own.isNotEmpty || node.vols.isEmpty) (kid: null, vols: node.own),
      for (final k in node.kids)
        if (k.vols.isNotEmpty) (kid: k, vols: k.vols),
    ];
    final anySub = groups.any((g) => g.kid != null);
    final head = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 14,
      runSpacing: 8,
      children: [
        Container(
          width: 14,
          height: 20,
          decoration: color == null
              ? null
              : BoxDecoration(
                  color: kitShelfCloth(color, dark: t.isDark),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(2),
                    bottomLeft: Radius.circular(2),
                    topRight: Radius.circular(3),
                    bottomRight: Radius.circular(3),
                  ),
                  boxShadow: AppShadows.s1,
                ),
        ),
        _ShelfTitle(
          node.title,
          size: 26,
          height: 1.1,
          tracking: -0.016,
          opsz: 32,
          underline: color ?? t.fgSubtle,
          onTap: () => actions.onOpenShelf(node),
        ),
        Text(
          kitShelfMeta(node),
          style: AppTheme.mono(
            fontSize: 11,
            letterSpacing: 0.04 * 11,
            color: t.fgSubtle,
          ),
        ),
        if (chip != null) chip.pill(),
      ],
    );
    final acts = Wrap(
      spacing: 20,
      runSpacing: 8,
      children: [
        if (!node.unshelved && actions.onAsk != null)
          KitHxLink(
            'Ask this shelf',
            icon: Icons.chat_bubble_outline,
            onTap: () => actions.onAsk!(node),
          ),
        KitHxLink('Open shelf →', onTap: () => actions.onOpenShelf(node)),
      ],
    );
    return Column(
      key: ValueKey('cvs-${node.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // `.cvs-acts{margin-left:auto}`: the actions at the head's trailing
        // edge, on their own line when the head does not leave room.
        LayoutBuilder(
          builder: (context, c) => c.maxWidth < 560
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    head,
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerRight, child: acts),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: head),
                    const SizedBox(width: 14),
                    acts,
                  ],
                ),
        ),
        if (node.description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 28),
            child: Text(
              node.description,
              style: AppTheme.serif(
                fontSize: 15,
                height: 23 / 15,
                fontStyle: FontStyle.italic,
                color: t.fgLede,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: KitScrollView.secondary(
            reason:
                "a shelf's covers: one row per shelf, as many as it holds "
                '(kit §42, §1.4)',
            axis: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < groups.length; i++) ...[
                    if (i > 0) const SizedBox(width: 28),
                    _CoverGroup(
                      kid: groups[i].kid,
                      vols: groups[i].vols,
                      cloth: groups[i].kid == null
                          ? color
                          : kitShelfPaint(context, groups[i].kid!),
                      padTop: anySub,
                      onOpenKid: groups[i].kid == null
                          ? null
                          : () => actions.onOpenShelf(groups[i].kid!),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One group of a shelf's covers (`.cvs-group`): the shelf's own, or a
/// sub-shelf's — 28 in, a 1px `--border` before it, its label above.
class _CoverGroup extends StatelessWidget {
  final KitShelfNode? kid;
  final List<Document> vols;
  final Color? cloth;
  final bool padTop;
  final VoidCallback? onOpenKid;

  const _CoverGroup({
    required this.kid,
    required this.vols,
    required this.cloth,
    required this.padTop,
    this.onOpenKid,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < vols.length; i++) ...[
          if (i > 0) const SizedBox(width: 20),
          KitCoverItem(
            doc: vols[i],
            shelf: cloth,
            meta: Text(passagesLabel(vols[i].chunkCount) ?? ''),
          ),
        ],
        if (vols.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'Nothing on this shelf yet.',
              style: AppTheme.serif(
                fontSize: 15,
                fontStyle: FontStyle.italic,
                color: t.fgSubtle,
              ),
            ),
          ),
      ],
    );
    final k = kid;
    if (k == null) {
      return Padding(
        padding: EdgeInsets.only(top: padTop ? 26 : 0),
        child: row,
      );
    }
    return Container(
      padding: const EdgeInsets.only(left: 28, top: 26),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: t.border)),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          row,
          Positioned(
            top: -26,
            left: 0,
            child: KitDTap(
              label: k.title,
              onTap: onOpenKid,
              builder: (context, hover, focus) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 10,
                    decoration: BoxDecoration(
                      color: cloth == null
                          ? null
                          : kitShelfCloth(cloth!, dark: t.isDark),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(1),
                        bottomLeft: Radius.circular(1),
                        topRight: Radius.circular(2),
                        bottomRight: Radius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    '${k.title.toUpperCase()} ›',
                    style: AppTheme.mono(
                      fontSize: 10.5,
                      letterSpacing: 0.14 * 10.5,
                      color: hover ? t.fg : t.fgMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
