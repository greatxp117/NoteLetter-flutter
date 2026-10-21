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

/// **The shelf map** (`screens/library.md` §The shelf map, 5.25.0, ADR-177) —
/// web `pages/map/MapView.jsx`. A sub-screen of the Shelves index, drawn over
/// the two subscriptions the shell already holds (INV-02): it reads nothing of
/// its own and writes nothing.
///
/// Composition, every part from the kit:
///
/// * **Frame** Canvas (§1.5) — [KitCanvasPage]: no ceiling, the map taking
///   the rest of the pane with a 420 floor, the footer after it.
/// * **Header** sub-screen (§2.2): *All shelves*, the eyebrow
///   `Shelf map · {n} shelves`, the lede.
/// * **Body** one §24 [KitRelationshipMap].
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
    return Consumer2<TagsNotifier, DocumentsNotifier>(
      builder: (context, tags, docs, _) {
        // INV-24: a map of a library we could not read is a false statement,
        // not an empty one — the failure is drawn where the graph would be.
        final error = tags.error ?? docs.error;
        if (error == null && (tags.loading || docs.loading)) {
          return const KitLoadingPage();
        }
        final shelves = tags.tags;
        final header = SubScreenHeader(
          parentLabel: 'All shelves',
          onBack: () => context.go('/shelves'),
          eyebrow: 'Shelf map · ${plural(shelves.length, 'shelf', 'shelves')}',
          standfirst:
              'Every shelf and the volumes on it. Arrows point from a '
              'volume to its shelf. Select anything to trace its path.',
        );
        if (error != null) {
          return KitCanvasPage(
            fill: false,
            header: header,
            body: KitFailureBlock(
              sentence: 'Your shelves could not be read',
              detail: error,
              // Retry re-subscribes the documents; the tags subscription
              // survives its own error and has nothing to re-issue, so a
              // Retry offered for it would be a control that does nothing.
              onRetry: tags.error == null ? docs.refresh : null,
            ),
          );
        }
        if (shelves.isEmpty) {
          return KitCanvasPage(
            fill: false,
            header: header,
            body: KitEmptyState(
              icon: Icons.shelves,
              title: 'No shelves yet',
              standfirst:
                  'Shelves group your volumes by subject. Make one and '
                  'it appears here.',
              suggestions: [
                KitSuggestion(
                  icon: Icons.shelves,
                  label: 'Go to your shelves',
                  onTap: () => context.go('/shelves'),
                ),
              ],
            ),
          );
        }
        final focus = widget.focusShelfId;
        return KitCanvasPage(
          header: header,
          body: KitRelationshipMap(
            // Parent edges from 5.28.0 (ADR-185): the INV-33 resolution, so a
            // dangling or cyclic stored parent draws no wire.
            graph: () {
              final tree = ShelfTree(shelves);
              return buildShelfGraph(
                [for (final s in shelves) _shelf(s)],
                [for (final d in docs.documents) _doc(d)],
                parentOf: (s) => tree.parent[s.id],
              );
            }(),
            focusKey: focus == null ? null : nodeKey('shelf', focus),
            onOpen: _open,
          ),
        );
      },
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
