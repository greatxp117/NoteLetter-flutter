// Component kit §32/§33 — a flat listing of sources in an order: the Library's
// catalogue, and a shelf's own volumes (web `src/kit/d/Catalogue.jsx`: the
// prototype's `NlHome.LibRegister`, `LibWall` and `sortSources`). F-141 builds
// it here, as its first consumer (the Library).

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../models/document.dart';
import '../../shared/passage_figure.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_d_covers.dart' show KitCoverItem;
import 'kit_d_format.dart';
import 'kit_d_library.dart' show KitJumpLetters, KitLibGrid;
import 'kit_d_parts.dart';
import 'kit_d_shelves.dart' show KitShelfNode;

/// The catalogue's orders (web `SORTS`): Recent · A–Z · Most passages.
const List<(String, String)> kSorts = [
  ('recent', 'Recent'),
  ('title', 'A–Z'),
  ('passages', 'Most passages'),
];

final RegExp _article = RegExp(r'^(the|a|an)\s+', caseSensitive: false);

/// Filed the way a library files: *The Library of Babel* under L — the title
/// less a leading *The*, *A* or *An*.
String kitSortKey(String? title) =>
    (title ?? '').replaceFirst(_article, '').trim();

/// The sources in [sort]'s order (web `sortSources`): A–Z by [kitSortKey],
/// Most passages by `chunk_count` (a count never taken sorts as none), Recent
/// by `created_at`, newest first. Stable, as web's `Array.sort` is: equal
/// sources keep the order they came in.
List<Document> kitSortSources(List<Document> list, String sort) {
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  int by((int, Document) x, (int, Document) y) {
    final a = x.$2, b = y.$2;
    final c = switch (sort) {
      'title' => kitSortKey(
          a.title,
        ).toLowerCase().compareTo(kitSortKey(b.title).toLowerCase()),
      'passages' => (b.chunkCount ?? 0).compareTo(a.chunkCount ?? 0),
      _ => (b.createdAt ?? 0).compareTo(a.createdAt ?? 0),
    };
    return c != 0 ? c : x.$1.compareTo(y.$1);
  }

  indexed.sort(by);
  return [for (final e in indexed) e.$2];
}

/// One group of the register: its [key] (the month, the initial or `all`),
/// the head's [label] (none for the one ranked run) and its [items].
class KitSourceGroup {
  final String key;
  final String? label;
  final List<Document> items;
  const KitSourceGroup(this.key, this.label, this.items);
}

/// The listing's groups in its order (web `groupSources`): the month added
/// (*October 2026*, *Undated* without a date), the initial under A–Z (`#`
/// for a title that does not start with a letter), one run for Most passages.
List<KitSourceGroup> kitGroupSources(List<Document> items, String sort) {
  if (sort == 'passages') return [KitSourceGroup('all', null, items)];
  String keyOf(Document v) {
    if (sort == 'title') {
      final k = kitSortKey(v.title);
      final c = k.isEmpty ? '' : k[0].toUpperCase();
      return RegExp(r'^[A-Z]$').hasMatch(c) ? c : '#';
    }
    final at = v.createdAt;
    return at == null ? 'Undated' : kitMonthYear(at);
  }

  final out = <KitSourceGroup>[];
  final at = <String, int>{};
  for (final v in items) {
    final k = keyOf(v);
    final i = at.putIfAbsent(k, () {
      out.add(KitSourceGroup(k, k, []));
      return out.length - 1;
    });
    out[i].items.add(v);
  }
  return out;
}

Color? _shelfColor(BuildContext context, KitShelfNode? home) => home == null
    ? null
    : AppColors.shelfColor(home.color, dark: Tokens.of(context).isDark);

/// §32 — List: §32's register rows under group heads that follow the order —
/// the month added (serif 600 22 over a 1px `--fg` rule, the count in mono),
/// or by initial under A–Z, a large italic accent letter (52; 36 in a column
/// 600 or narrower) held beside its rows as they scroll, with a row of
/// letters above that jumps to one; under Most passages one run, each row's
/// date cell its rank (`01`, `02`, …).
class KitLibRegister extends StatefulWidget {
  final List<Document> items;
  final String sort;

  /// doc id → its home shelf ([kitShelfModel]'s `homeOf`).
  final Map<String, KitShelfNode> homeOf;

  /// The in-app open; null → [KitSourceLink]'s default (push the reader).
  final void Function(Document doc)? onOpen;

  const KitLibRegister({
    super.key,
    required this.items,
    required this.sort,
    this.homeOf = const {},
    this.onOpen,
  });

  @override
  State<KitLibRegister> createState() => _KitLibRegisterState();
}

class _KitLibRegisterState extends State<KitLibRegister> {
  final Map<String, GlobalKey> _groups = {};

  GlobalKey _keyOf(String k) =>
      _groups.putIfAbsent(k, () => GlobalKey(debugLabel: 'lx-reg-$k'));

  void _jump(String letter) {
    final ctx = _groups[letter]?.currentContext;
    final box = ctx?.findRenderObject();
    if (ctx == null || box is! RenderBox) return;
    final position = Scrollable.maybeOf(ctx)?.position;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (position == null || viewport == null) return;
    final target = (viewport.getOffsetToReveal(box, 0).offset - 16).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (KitD.still(context)) {
      position.jumpTo(target);
    } else {
      position.animateTo(
        target,
        duration: AppMotion.durSlow,
        curve: AppMotion.easeQuill,
      );
    }
  }

  Widget _row(Document v, String? lead) => KitRegisterRow(
    key: ValueKey('reg-${v.id}'),
    doc: v,
    shelfTitle: widget.homeOf[v.id]?.title,
    shelfColor: _shelfColor(context, widget.homeOf[v.id]),
    lead: lead,
    onOpen: widget.onOpen == null ? null : () => widget.onOpen!(v),
  );

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final groups = kitGroupSources(widget.items, widget.sort);
    final alpha = widget.sort == 'title';
    final ranked = widget.sort == 'passages';
    final have = {for (final g in groups) g.key};
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth <= 600;
        final children = <Widget>[];
        if (alpha) {
          children.add(KitJumpLetters(have: have, onJump: _jump));
        }
        for (var gi = 0; gi < groups.length; gi++) {
          final g = groups[gi];
          final rows = [
            for (var i = 0; i < g.items.length; i++)
              _row(g.items[i], ranked ? '${i + 1}'.padLeft(2, '0') : null),
          ];
          if (alpha) {
            final letter = Text(
              g.label ?? '',
              style: AppTheme.serif(
                fontSize: narrow ? 36 : 52,
                height: 1,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w500,
                color: t.accentText,
                opsz: 60,
              ),
            );
            final key = _keyOf(g.key);
            children.add(
              Container(
                key: key,
                margin: const EdgeInsets.only(top: 22),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: t.fg)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: narrow ? 44 : 84,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: _StickyLetter(group: key, child: letter),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: rows,
                      ),
                    ),
                  ],
                ),
              ),
            );
          } else {
            children.add(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (g.label != null)
                    Container(
                      margin: EdgeInsets.only(top: gi == 0 ? 8 : 34),
                      padding: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: t.fg)),
                      ),
                      child: Semantics(
                        header: true,
                        child: Wrap(
                          spacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.end,
                          children: [
                            Text(
                              g.label!,
                              style: AppTheme.serif(
                                fontSize: 22,
                                height: 1.2,
                                fontWeight: FontWeight.w600,
                                color: t.fg,
                                opsz: 24,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text(
                                kitCounted(g.items.length, 'volume'),
                                style: AppTheme.mono(
                                  fontSize: 11,
                                  letterSpacing: 0.04 * 11,
                                  color: t.fgSubtle,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ...rows,
                ],
              ),
            );
          }
        }
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        );
      },
    );
  }
}

/// The A–Z letter held 16 from the top of the page's scroller while its group
/// passes (`position: sticky; top: 16px`), never past the end of its group.
/// Read from the scroller's own offset, so it moves on the frame the scroll
/// does.
class _StickyLetter extends StatefulWidget {
  final GlobalKey group;
  final Widget child;
  const _StickyLetter({required this.group, required this.child});

  @override
  State<_StickyLetter> createState() => _StickyLetterState();
}

class _StickyLetterState extends State<_StickyLetter> {
  final GlobalKey _self = GlobalKey();
  ScrollPosition? _position;
  double _shift = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final p = Scrollable.maybeOf(context)?.position;
    if (!identical(p, _position)) {
      _position?.removeListener(_measure);
      _position = p;
      _position?.addListener(_measure);
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_measure);
    super.dispose();
  }

  void _measure() {
    if (!mounted) return;
    final group = widget.group.currentContext?.findRenderObject();
    final self = _self.currentContext?.findRenderObject();
    final vp = _position?.context.storageContext.findRenderObject();
    if (group is! RenderBox || self is! RenderBox || vp is! RenderBox) return;
    if (!group.attached || !vp.attached || !group.hasSize || !self.hasSize) {
      return;
    }
    final top = group.localToGlobal(Offset.zero, ancestor: vp).dy;
    // The letter sits 12 into its group; it sticks once that reaches 16.
    final double next = (16 - (top + 12))
        .clamp(0.0, math.max(0.0, group.size.height - self.size.height - 12))
        .toDouble();
    if ((next - _shift).abs() > .5) setState(() => _shift = next);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return Transform.translate(
      offset: Offset(0, _shift),
      child: KeyedSubtree(key: _self, child: widget.child),
    );
  }
}

/// §33 — Grid: one wall of covers (`repeat(auto-fill, minmax(136px, 1fr))`,
/// `30px 26px`), each in its home shelf's cloth, with the shelf under it (a
/// dot and its name, *Unshelved* without one) and the passage figure — none
/// for a count never taken (ADR-109).
class KitLibWall extends StatelessWidget {
  final List<Document> items;
  final Map<String, KitShelfNode> homeOf;
  final void Function(Document doc)? onOpen;

  const KitLibWall({
    super.key,
    required this.items,
    this.homeOf = const {},
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return KitLibGrid(
        top: 14,
        children: [
          for (final v in items)
            Builder(
              builder: (context) {
                final home = homeOf[v.id];
                final color = _shelfColor(context, home);
                final n = passagesLabel(v.chunkCount);
                return KitCoverItem(
                  key: ValueKey('wall-${v.id}'),
                  doc: v,
                  shelf: color,
                  width: double.infinity,
                  onOpen: onOpen == null ? null : () => onOpen!(v),
                  meta: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 9,
                            decoration: BoxDecoration(
                              color: color ?? t.fgSubtle,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(1),
                                bottomLeft: Radius.circular(1),
                                topRight: Radius.circular(2),
                                bottomRight: Radius.circular(2),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(child: Text(home?.title ?? 'Unshelved')),
                        ],
                      ),
                      if (n != null) ...[
                        const SizedBox(height: 4),
                        Text(n),
                      ],
                    ],
                  ),
                );
              },
            ),
        ],
    );
  }
}
