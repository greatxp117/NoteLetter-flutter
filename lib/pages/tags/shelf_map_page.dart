import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/document.dart';
import '../../models/tag.dart';
import '../../shared/relmap_layout.dart';
import '../../shared/shelf_tree.dart';
import '../../state/documents_notifier.dart';
import '../../state/tags_notifier.dart';
import '../../widgets/kit/kit.dart';
import 'shelf_parts.dart';

/// **The shelf map** (`screens/library.md` §The shelf map, 5.25.0, ADR-177),
/// in direction D — web `pages/map/MapView.jsx`. Drawn over the two
/// subscriptions the shell already holds (INV-02): it reads nothing of its own
/// and writes nothing.
///
/// Composition, every part from the kit:
///
/// * **Frame** the D frame ([KitDPage]): the crumb *All shelves*, folio
///   `Shelf map · {N} shelves`, *The Shelf Map*, the standfirst. No action,
///   no settings.
/// * **Sheet** *The shelf map*: Figures *On the map* (the graph's own counts),
///   *Go to a shelf* (every shelf in tree order; choosing one selects and
///   centres it on the map already drawn, and never leaves the page), *Also*:
///   *All shelves*. On a phone it is the running head (the map glyph, the
///   chosen shelf's title, `{N} shelves`), and choosing a shelf folds it.
/// * **Column** one §24 [KitRelationshipMap] filling it: at least 560 tall or
///   the window less 120 (a phone: 70% of the window, at least 440).
///
/// [focusShelfId] is the shelf a shelf page's *See on map* hands over. It
/// rides go_router's `extra`, never the address: a shelf id in the URL would
/// reach analytics' page_location (INV-25b, ADR-081).
class ShelfMapPage extends StatefulWidget {
  final String? focusShelfId;

  const ShelfMapPage({super.key, this.focusShelfId});

  @override
  State<ShelfMapPage> createState() => _ShelfMapPageState();
}

class _ShelfMapPageState extends State<ShelfMapPage> {
  /// The shelf chosen (arrival's focus, then *Go to a shelf*), and a count
  /// bumped by every pick so the same shelf picked twice centres twice (web
  /// `pick: {id, n}`).
  late String? _pick = widget.focusShelfId;
  int _n = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<TagsNotifier>().start();
      context.read<DocumentsNotifier>().start();
    });
  }

  void _open(MapNode node) {
    if (node.isShelf) {
      context.go('/shelves/${node.id}');
    } else {
      // The map is the Reader's origin: its back control reads *Shelf map*
      // (`screens/reader.md` §The way back).
      context.push(
        '/reader/${node.id}?from=${Uri.encodeComponent('/shelves/map')}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final docs = context.watch<DocumentsNotifier>();
    final tags = context.watch<TagsNotifier>();
    final shelves = tags.tags;
    final loaded = !docs.loading && !tags.loading;
    // INV-24: a map, its figures and its shelf list are statements about the
    // library — none is drawn from a read that is out or was refused.
    final error = tags.error ?? docs.error;
    final known = loaded && error == null;
    final tree = ShelfTree(shelves);
    // Parent edges from 5.28.0 (ADR-185): the INV-33 resolution, so a
    // dangling or cyclic stored parent draws no wire.
    final graph = buildShelfGraph(
      [for (final s in shelves) _shelf(s)],
      [for (final d in docs.documents) _doc(d)],
      parentOf: (s) => tree.parent[s.id],
    );
    final size = MediaQuery.sizeOf(context);
    final mapHeight = KitD.phone(context)
        ? math.max(440.0, size.height * 0.7)
        : math.max(560.0, size.height - 120);

    final Widget body;
    if (error != null) {
      // A map of a library we could not read is a false statement, not an
      // empty one — the failure is drawn where the graph would be.
      body = KitFailureBlock(
        sentence: 'Your shelves could not be read.',
        detail: error,
        // Retry re-subscribes the documents; the tags subscription has
        // nothing to re-issue, so a Retry offered for it would do nothing.
        onRetry: tags.error == null ? docs.refresh : null,
      );
    } else if (!loaded) {
      body = const KitSkeletonLines(
        lines: [
          KitSkelLine(0.6), KitSkelLine(), KitSkelLine(), //
          KitSkelLine(0.7), KitSkelLine(),
        ],
        top: 0,
      );
    } else if (shelves.isEmpty) {
      body = KitEmptyState(
        icon: KitStackGlyph.icon,
        title: 'No shelves yet',
        standfirst:
            'Shelves group your volumes by subject. Make one and it '
            'appears here.',
        suggestions: [
          KitSuggestion(
            icon: KitStackGlyph.icon,
            label: 'Go to your shelves',
            onTap: () => context.go('/shelves'),
          ),
        ],
      );
    } else {
      body = SizedBox(
        height: mapHeight,
        child: KitRelationshipMap(
          graph: graph,
          focusKey: _pick == null ? null : nodeKey('shelf', _pick!),
          focusN: _n,
          onOpen: _open,
        ),
      );
    }

    // Every shelf in tree order, a sub-shelf under its parent.
    final flat = <(Tag, int)>[];
    void walk(Tag s, int depth) {
      flat.add((s, depth));
      for (final k in tree.childrenOf(s.id)) {
        walk(k, depth + 1);
      }
    }

    for (final r in tree.roots) {
      walk(r, 0);
    }
    final c = graph.counts;
    final sheet = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitFigures(
          label: 'On the map',
          rows: known
              ? [
                  ('Shelves', kitThousands(c.shelves)),
                  ('Volumes', kitThousands(c.volumes)),
                  ('Links', kitThousands(c.links)),
                  if (c.unshelved > 0) ('Unshelved', kitThousands(c.unshelved)),
                ]
              : const [('Shelves', '—'), ('Volumes', '—'), ('Links', '—')],
        ),
        if (known && flat.isNotEmpty) ...[
          const KitDLabel('Go to a shelf'),
          KitShelfRows(
            children: [
              for (final (s, depth) in flat)
                KitShelfRow(
                  key: ValueKey('map-go-${s.id}'),
                  title: s.title.isEmpty ? 'Untitled' : s.title,
                  color: kitShelfColorOf(context, s.color),
                  count: kitThousands(
                    shelfVolumes(s, docs.complete, tree).length,
                  ),
                  sub: depth > 0,
                  on: _pick == s.id,
                  onTap: () => setState(() {
                    _pick = s.id;
                    _n++;
                  }),
                ),
            ],
          ),
        ],
        KitSheetAlso(
          children: [
            Builder(
              builder: (context) => KitAlsoButton(
                'All shelves',
                icon: KitStackGlyph.icon,
                onTap: () {
                  KitSheetScope.pick(context);
                  context.go('/shelves');
                },
              ),
            ),
          ],
        ),
      ],
    );
    final picked = _pick == null
        ? null
        : shelves.where((s) => s.id == _pick).firstOrNull;

    return KitDPage(
      back: KitDBackControl('All shelves', onTap: () => context.go('/shelves')),
      folio:
          'Shelf map · '
          '${known ? kitCounted(shelves.length, 'shelf', 'shelves') : '— shelves'}',
      title: 'The Shelf Map',
      stand:
          'Every shelf and the volumes on it. Arrows point from a volume to '
          'its shelf. Select anything to trace its path.',
      search: true,
      sheet: KitDSheet(
        label: 'The shelf map',
        foldOnPick: true,
        peek: KitLibPeek(
          icon: KitMapGlyph.icon,
          title: picked == null
              ? 'The shelf map'
              : (picked.title.isEmpty ? 'Untitled' : picked.title),
          count: known ? kitThousands(shelves.length) : null,
          tail: known ? (shelves.length == 1 ? ' shelf' : ' shelves') : null,
        ),
        body: sheet,
      ),
      child: body,
    );
  }

  static MapShelf _shelf(Tag t) => MapShelf(
    t.id,
    title: t.title,
    color: t.color,
    parentTagId: t.parentTagId,
  );

  static MapDoc _doc(Document d) => MapDoc(
    d.id,
    title: d.title,
    type: d.type,
    complete: d.status == DocumentStatus.complete,
    tagIds: d.tagIds,
  );
}
