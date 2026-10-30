import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../shared/relmap_layout.dart' show documentWindow;
import '../state/documents_notifier.dart';
import '../state/settings_notifier.dart';
import '../state/tags_notifier.dart';
import '../widgets/kit/kit.dart';
import '../widgets/sidebar.dart' show shellAiOn;
import 'tags/shelf_sheet.dart';
import 'tags/suggest_shelves.dart';

/// **Shelves — the index** (`/shelves`), in direction D
/// (`screens/library.md` §Composition — Shelves and a shelf; web
/// `pages/ShelvesView.jsx` `ShelvesIndex`).
///
/// A shelf **is** a `/tags` document: its title, description and colour are
/// tag fields, written through `fn_create_tag`/`fn_update_tag` (INV-04), and
/// the volumes on it are a client-side grouping over the documents
/// subscription (INV-02) — there is no shelves collection.
///
/// Composition, every part from the kit:
///
/// * **Frame** the D frame ([KitDPage]): folio `The shelves · {N} shelves ·
///   {N} volumes`, *Shelves*, the standfirst; the action **New shelf** (the
///   rail's `+` form); no settings.
/// * **Sheet** *The shelves*: the top-level shelves (and *Unshelved*) as
///   [KitShelfRow]s, the one in view current; *Also*: *Suggest shelves*, *The
///   shelf map*. On a phone it is the running head (the shelf in view's
///   swatch and title and `{i} of {N}`), and choosing a shelf folds it.
/// * **Column** *On the shelves* with the List / Grid toggle, then kit §42's
///   shelf listing (12 rows a shelf) — or §37's *No shelves yet*.
///
/// Every figure is counted from the shelves and documents reads: while either
/// is out, and when either was refused, a figure draws the dash (ADR-109) and
/// no list is drawn as empty (INV-24).
///
/// The file keeps its name because `harness/failure_pattern_check.py` and
/// `spec/clients/flutter.md` §5 both address this surface as
/// `lib/pages/tags_page.dart`; it is the ROUTE that was renamed.
class ShelvesPage extends StatefulWidget {
  const ShelvesPage({super.key});

  @override
  State<ShelvesPage> createState() => _ShelvesPageState();
}

class _ShelvesPageState extends State<ShelvesPage> {
  /// The shelf in view, and the way to one (web `useSections` over each
  /// shelf's `data-vt-shelf`).
  final KitSections _sec = KitSections(const []);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<TagsNotifier>().start();
      context.read<DocumentsNotifier>().start();
      // The letter chip reads whether the daily letter is on — the same
      // one-shot settings read Home makes; not a subscription.
      context.read<SettingsNotifier>().loadAll();
    });
  }

  @override
  void dispose() {
    _sec.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final docs = context.watch<DocumentsNotifier>();
    final tags = context.watch<TagsNotifier>();
    final letterOn = context.watch<SettingsNotifier>().letterOn;
    final aiOn = shellAiOn(context);
    final router = GoRouter.maybeOf(context);
    void go(String to, {Object? extra}) => router?.go(to, extra: extra);

    final shelves = tags.tags;
    final loaded = !docs.loading && !tags.loading;
    final libError = docs.error ?? tags.error;
    // INV-24 (ADR-071): every figure here is counted from the two
    // subscriptions, so while either is out or was refused each is unread.
    final known = loaded && libError == null;
    final model = kitShelfModel(shelves, docs.documents);
    final totalVols = model.total;
    final windowFull = docs.documents.length >= documentWindow;
    final nodes = model.nodes;
    final ids = [for (final n in nodes) n.id];
    if (!_sameIds(_sec.ids, ids)) _sec.ids = ids;
    // No shelves yet: an answered read with no shelf in it. Volumes no shelf
    // holds do not make it a shelf.
    final bare = known && model.roots.isEmpty;

    void newShelf() => showShelfSheet(
      context,
      canBackfill: totalVols > 0,
      land: (id) => go('/shelves/$id'),
      shelves: shelves,
    );
    void suggest() =>
        showSuggestShelvesSheet(context, canBackfill: totalVols > 0);

    final sheet = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const KitDLabel('The shelves', first: true),
        if (!loaded && libError == null)
          const KitSkeletonLines(
            lines: [KitSkelLine(0.7), KitSkelLine(0.6), KitSkelLine(0.7)],
          ),
        if (bare) const KitDNote('None yet.'),
        if (known && nodes.isNotEmpty)
          ListenableBuilder(
            listenable: _sec,
            builder: (context, _) => KitShelfRows(
              children: [
                for (final n in nodes)
                  KitShelfRow(
                    key: ValueKey('shelves-sheet-${n.id}'),
                    title: n.title,
                    color: kitShelfPaint(context, n),
                    count: kitThousands(n.vols.length),
                    on: _sec.current == n.id,
                    onTap: () => _sec.jump(n.id),
                  ),
              ],
            ),
          ),
        KitSheetAlso(
          children: [
            if (known && totalVols > 0)
              _FoldingAlso(
                'Suggest shelves',
                icon: KitSparkle.icon,
                onTap: suggest,
              ),
            if (known && shelves.isNotEmpty)
              _FoldingAlso(
                'The shelf map',
                icon: KitMapGlyph.icon,
                onTap: () => go('/shelves/map'),
              ),
          ],
        ),
      ],
    );

    final peek = ListenableBuilder(
      listenable: _sec,
      builder: (context, _) {
        final at = math.max(0, nodes.indexWhere((n) => n.id == _sec.current));
        final c = known && nodes.isNotEmpty ? nodes[at] : null;
        if (c != null) {
          return KitLibPeek(
            mark: KitShelfSwatch(kitShelfPaint(context, c)),
            title: c.title,
            count: '${at + 1}',
            tail: ' of ${nodes.length}',
          );
        }
        return KitLibPeek(
          icon: KitStackGlyph.icon,
          title: bare ? 'No shelves yet' : 'The shelves',
          wait: !known,
        );
      },
    );

    final volsShelved = known
        ? ' ${kitCounted(totalVols, 'volume')}, shelved'
              '${windowFull ? ', of your most recent $documentWindow' : ''}.'
        : '';

    return KitDPage(
      folio:
          'The shelves · '
          '${known ? kitCounted(shelves.length, 'shelf', 'shelves') : '— shelves'} · '
          '${known ? kitCounted(totalVols, 'volume') : '— volumes'}',
      title: 'Shelves',
      stand:
          'Group your volumes by subject, project, or year — each shelf can '
          'feed your letter on its own.$volsShelved',
      action: KitPageAction(
        label: 'New shelf',
        short: 'New shelf',
        icon: Icons.add,
        onPressed: newShelf,
      ),
      sections: _sec,
      sheet: KitDSheet(
        label: 'The shelves',
        peek: peek,
        body: sheet,
        foldOnPick: true,
      ),
      // A refused read is said in the listing's place (§14.2, INV-24) —
      // FIRST: "no shelves yet" is a statement about the library, and a failed
      // read is no evidence for it.
      child: libError != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const KitSectionHead('On the shelves', flushTop: true),
                KitFailureInline('Your library could not be read — $libError'),
              ],
            )
          : bare
          ? KitEmptyState(
              icon: KitStackGlyph.icon,
              title: 'No shelves yet',
              standfirst:
                  'A shelf groups volumes by subject, project or year, and '
                  'each one can feed your letter on its own.',
              suggestions: [
                KitSuggestion(
                  icon: Icons.add,
                  label: 'Make your first shelf',
                  onTap: newShelf,
                ),
                if (totalVols > 0)
                  KitSuggestion(
                    icon: KitSparkle.icon,
                    label: 'Have NoteLetter suggest shelves from your library',
                    onTap: suggest,
                  ),
              ],
            )
          : KitSourceView(
              builder: (context, view) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KitSectionHead(
                    'On the shelves',
                    // A ported page's first head in its column has no top
                    // margin (`.dp .d-main>.hx-sh:first-child`).
                    flushTop: true,
                    meta: known ? kitCounted(totalVols, 'volume') : null,
                    actions: [
                      if (known && totalVols > 0) const KitViewToggle(),
                    ],
                  ),
                  KitShelfListing(
                    model: model,
                    view: view,
                    letterOn: letterOn,
                    loaded: loaded,
                    libError: libError,
                    limit: 12,
                    keyOf: _sec.keyOf,
                    onNewShelf: newShelf,
                    actions: KitShelfActions(
                      onOpenShelf: (n) =>
                          go(n.unshelved ? '/sources' : '/shelves/${n.id}'),
                      // Absent while generative AI is off (5.29.0, ADR-186).
                      onAsk: aiOn ? (n) => go('/ask/shelf/${n.id}') : null,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  static bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// An *Also* row that folds the running head first (web `FOLD` names
/// `.rx-more .btn`): an action that opens a sheet must not leave the running
/// head dropped over it.
class _FoldingAlso extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _FoldingAlso(this.label, {required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => KitAlsoButton(
    label,
    icon: icon,
    onTap: () {
      KitSheetScope.pick(context);
      onTap();
    },
  );
}
