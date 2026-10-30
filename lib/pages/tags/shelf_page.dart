import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/document.dart';
import '../../models/tag.dart';
import '../../services/api.dart';
import '../../services/api_service.dart';
import '../../state/documents_notifier.dart';
import '../../state/tags_notifier.dart';
import '../../widgets/app_toast.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit/kit.dart';
import '../../widgets/sidebar.dart' show shellAiOn;
import 'shelf_parts.dart';
import 'shelf_sheet.dart';
import 'split_shelf_sheet.dart';
import '../../shared/shelf_tree.dart';

/// **One shelf** (`/shelves/{id}`) — `screens/library.md` §Shelf color, §Shelf
/// granularity and splitting.
///
/// Composition: a §2.2 **back control** naming the parent, then a full §2.1
/// chapter opening — a shelf is its own subject, with a plate for a lead, a
/// folio carrying its counts and provenance, and the shelf's description as the
/// standfirst — then the §8 stat cluster, an optional settings panel, and the
/// §4.1 list of its volumes under a §3 section header with a §6.8 sort control.
///
/// Every figure here is **counted from the documents subscription**, which is
/// why a failed read is stated (INV-24): a shelf that could not be read counts
/// zero of everything and would otherwise read as an empty shelf.
class ShelfPage extends StatefulWidget {
  final String shelfId;

  const ShelfPage({super.key, required this.shelfId});

  @override
  State<ShelfPage> createState() => _ShelfPageState();
}

class _ShelfPageState extends State<ShelfPage> {
  final _name = TextEditingController();

  /// The name as the server last accepted it — what `_saveName` compares
  /// against, so a blur that changed nothing issues no request.
  String _savedName = '';
  bool _nameBound = false;

  bool _savingColor = false;
  String? _colorError;
  bool _savingLetter = false;
  String? _letterError;
  String? _nameError;
  bool _moving = false;
  String? _moveError;

  /// "Find sources for this shelf" and "Split this shelf" start background
  /// tasks (4.102.0, ADR-136); each holds its control while asking and keeps
  /// a refusal beside it (§14.2).
  bool _fillBusy = false;
  String? _fillError;
  bool _splitBusy = false;
  bool _splitRequested = false;
  String? _splitError;

  /// The volumes' order (kit §32 `SORTS`): Recent · A–Z · Most passages.
  String _sort = 'recent';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<TagsNotifier>().start();
      context.read<DocumentsNotifier>().start();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Write before move, for the name as for the colour: `_savedName` moves
  /// only once `fn_update_tag` has answered — so a rejected rename cannot read
  /// as a successful one.
  ///
  /// **And the field goes back** (component-kit §Rules, 4.75.2): on a refusal
  /// the text is reset to the name the server still holds. Leaving the refused
  /// text in the field SHOWED a name the shelf does not have, under a sentence
  /// saying it could not be saved — the sentence and the field disagreeing,
  /// with the field the one a reader believes.
  Future<void> _saveName(Tag shelf) async {
    final next = _name.text.trim();
    if (next.isEmpty || next == _savedName) return;
    final err = await context.read<TagsNotifier>().updateTag(
      shelf.id,
      title: next,
    );
    if (!mounted) return;
    setState(() {
      _nameError = err;
      if (err == null) {
        _savedName = next;
      } else {
        _name.value = TextEditingValue(
          text: _savedName,
          selection: TextSelection.collapsed(offset: _savedName.length),
        );
      }
    });
  }

  /// Deliberately NOT optimistic (`screens/library.md` §Shelf color). The web
  /// swatch moved before the request until 2.15.0, so a rejected write looked
  /// exactly like a successful one until the page was reloaded — which is how a
  /// 400 on every colour change went unnoticed for months.
  Future<void> _pickColour(Tag shelf, String token) async {
    if (_savingColor || token == shelf.color) return;
    setState(() {
      _savingColor = true;
      _colorError = null;
    });
    final err = await context.read<TagsNotifier>().updateTag(
      shelf.id,
      color: token,
    );
    if (!mounted) return;
    setState(() {
      _savingColor = false;
      _colorError = err;
    });
    // No local colour state: the tags subscription (INV-02) carries the
    // accepted value back, so what is drawn is what was stored.
  }

  /// The shelf's place in the letter (`screens/library.md`, 4.88.0, ADR-122).
  /// On the reference this stored nothing until 4.88.0 — the switch muted
  /// nothing and was back on after a reload. Same rule as the colour: no local
  /// state, the controls are disabled while the call is out, and the tags
  /// subscription carries the accepted value back.
  ///
  /// 5.28.0 (ADR-185): a choice is the shelf's OWN mode; a null [mode] clears
  /// it (`letter_mode: null`) so the shelf inherits the nearest one above.
  Future<void> _setLetterMode(Tag shelf, String? mode) async {
    if (_savingLetter || mode == shelf.ownLetterMode) return;
    setState(() {
      _savingLetter = true;
      _letterError = null;
    });
    final err = await context.read<TagsNotifier>().updateTag(
      shelf.id,
      letterMode: mode,
      clearLetterMode: mode == null,
    );
    if (!mounted) return;
    setState(() {
      _savingLetter = false;
      _letterError = err;
    });
  }

  /// *Inside* (Move into, 5.28.0, ADR-185). Write before you move: the select
  /// shows the STORED parent, so it moves only when the tags subscription
  /// brings the write back; a refusal is the server's sentence, in place.
  Future<void> _moveTo(Tag shelf, String? currentParent, String next) async {
    final target = next.isEmpty ? null : next;
    if (_moving || target == currentParent) return;
    setState(() {
      _moving = true;
      _moveError = null;
    });
    final err = await context.read<TagsNotifier>().updateTag(
      shelf.id,
      moveTo: target,
      toTopLevel: target == null,
    );
    if (!mounted) return;
    setState(() {
      _moving = false;
      _moveError = err;
    });
  }

  // §18 (4.56.0, ADR-092): the delete runs INSIDE the confirmation, so a refusal
  // answers in the panel and the panel stays open. It used to close first and
  // put the sentence in the colour picker's error slot, three controls away
  // from the button that was pressed.
  //
  // 4.85.0 (ADR-119): the confirmation names the sources left on no shelf and
  // offers to re-shelve them.
  //
  // 4.101.0 (ADR-136 — library.md §Deleting a shelf): the delete runs in the
  // BACKGROUND. This call only records the task and marks the shelf
  // `deleting`, so it is fast, and the confirmation still holds until it
  // answers (§18 rule 1). The capture, the strip and the proposal are the
  // worker's; whatever it proposes waits in For your review, not in a sheet
  // that closing loses.
  Future<void> _delete(
    Tag shelf,
    List<Document> vols,
    List<Tag> all,
    ShelfTree tree,
  ) async {
    final others = [
      for (final s in all)
        if (s.id != shelf.id) s,
    ];
    final kids = tree.childrenOf(shelf.id).length;
    final up = tree.parent[shelf.id];
    final upTitle = up == null ? null : tree.byId[up]?.title;
    final canReshelve = vols.isNotEmpty && others.isNotEmpty;
    final orphans = vols
        .where((d) => d.tagIds.every((t) => t == shelf.id))
        .length;
    final title = shelf.title;
    var reshelveOn = true;
    final body =
        'The shelf and its settings are removed. Its '
        '${plural(vols.length, 'volume stays', 'volumes stay')} in your '
        'library — they just come off this shelf.'
        '${orphans > 0 ? ' $orphans of them ${orphans == 1 ? 'is' : 'are'} on no other shelf.' : ''}'
        // 5.28.0 (ADR-185 §7): the confirm says where the children go.
        '${kids > 0 ? ' Its ${plural(kids, 'sub-shelf moves', 'sub-shelves move')} up ${upTitle != null ? 'into $upTitle' : 'to the top level'}.' : ''}';
    final done = await KitConfirm.show(
      context,
      title: 'Delete the “$title” shelf?',
      bodyWidget: StatefulBuilder(
        builder: (ctx, setLocal) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(body, style: KitText.meta(ctx)),
            if (canReshelve) ...[
              const SizedBox(height: 12),
              KitCheckRow(
                value: reshelveOn,
                title: 'Suggest new shelves for its sources',
                subtitle:
                    'After the delete, NoteLetter suggests one of your '
                    'other shelves for each. They wait in For your review, '
                    'and nothing is filed until you choose.',
                onChanged: (v) => setLocal(() => reshelveOn = v),
              ),
            ],
          ],
        ),
      ),
      confirmLabel: 'Delete shelf',
      cancelLabel: 'Keep it',
      onConfirm: () async {
        try {
          await Api.instance.requestShelfDelete(
            shelf.id,
            reshelve: canReshelve && reshelveOn,
          );
          return null;
        } on ApiException catch (e) {
          return e.message;
        } catch (_) {
          // Not swallowed: no envelope came back, so this is the §18 slot's
          // sentence, rendered in the panel.
          return 'The shelf could not be deleted right now.';
        }
      },
    );
    if (done != true || !mounted) return;
    context.go('/shelves');
    AppToast.show(
      context,
      'Deleting “$title” in the background. '
      "You'll find it in For your review.",
    );
  }

  /// The proposal is a worker's and waits in For your review, where closing a
  /// sheet cannot lose it (4.102.0).
  Future<void> _findSources(Tag shelf) async {
    setState(() {
      _fillBusy = true;
      _fillError = null;
    });
    final refused = await requestShelfBackfill(shelf.id);
    if (!mounted) return;
    setState(() {
      _fillBusy = false;
      _fillError = refused;
    });
    if (refused == null) {
      AppToast.show(context, backfillStartedToast(shelf.title));
    }
  }

  Future<void> _requestSplit(Tag shelf) async {
    setState(() {
      _splitBusy = true;
      _splitError = null;
    });
    String? refused;
    try {
      await Api.instance.requestShelfSplit(shelf.id);
    } on ApiException catch (e) {
      refused = e.message;
    } catch (_) {
      // Not swallowed: no envelope came back; rendered beside the control.
      refused = 'That request could not be completed.';
    }
    if (!mounted) return;
    setState(() {
      _splitBusy = false;
      _splitError = refused;
      _splitRequested = refused == null;
    });
    if (refused == null) {
      AppToast.show(
        context,
        'Suggesting a split of “${shelf.title}” in the background. '
        "You'll find it in For your review.",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final docs = context.watch<DocumentsNotifier>();
    final tags = context.watch<TagsNotifier>();
    final aiOn = shellAiOn(context);
    final loaded = !docs.loading && !tags.loading;
    final libError = tags.error ?? docs.error;
    // A cold-loaded /shelves/{id} renders before the first snapshot: nothing
    // but the skeleton draws until the snapshot, or its failure, is in —
    // never "Shelf Not Found", a claim about a list not yet received.
    if (!loaded && libError == null) return _loading(context);
    final shelf = tags.tags.where((t) => t.id == widget.shelfId).firstOrNull;
    if (shelf == null) return _notFound(context, libError);

    if (!_nameBound) {
      _nameBound = true;
      _name.text = shelf.title;
      _savedName = shelf.title;
    }

    // The page counts the SUBTREE (5.28.0, ADR-185, INV-33); a split, a
    // delete and their copy act on what is filed DIRECTLY here.
    final all = tags.tags;
    final tree = ShelfTree(all);
    final model = kitShelfModel(all, docs.documents);
    final vols = shelfVolumes(shelf, docs.complete, tree);
    final direct = shelfVolumes(shelf, docs.complete);
    final passages = shelfPassages(vols);
    final crumbs = tree.ancestors(shelf.id).reversed.toList();
    final kids = tree.childrenOf(shelf.id);
    final parentId = tree.parent[shelf.id];
    final eff = tree.letterMode(shelf.id);
    final modeLabel = KitShelfLetter.labelOf(eff.mode);
    // INV-24 (ADR-071): every figure here is counted from the documents read,
    // and a failed read counts zero of everything.
    final unread = libError != null;
    final name = shelf.title.isEmpty ? 'Untitled' : shelf.title;
    final color = kitShelfColorOf(context, shelf.color);
    final provenance = _provenance(shelf);
    final canBackfill = docs.complete.isNotEmpty;
    final sortLabel = (kSorts.firstWhere(
      (o) => o.$1 == _sort,
      orElse: () => kSorts.first,
    )).$2;
    final items = kitSortSources(vols, _sort);

    final sheet = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitShelfIdentity(color: color, kicker: 'Shelf$provenance', name: name),
        KitLibOrder(
          options: kSorts,
          value: _sort,
          onChanged: (v) => setState(() => _sort = v),
        ),
        const KitDLabel('Sub-shelves'),
        KitShelfRows(
          children: [
            for (final k in kids)
              KitShelfRow(
                key: ValueKey('sub-shelf-${k.id}'),
                title: k.title.isEmpty ? 'Untitled' : k.title,
                color: kitShelfColorOf(context, k.color),
                count: unread
                    ? '—'
                    : kitThousands(shelfVolumes(k, docs.complete, tree).length),
                onTap: () => context.go('/shelves/${k.id}'),
              ),
            KitShelfRow.create(
              title: 'New sub-shelf',
              onTap: () => showShelfSheet(
                context,
                canBackfill: canBackfill,
                land: (id) => context.go('/shelves/$id'),
                shelves: all,
                parent: shelf,
              ),
            ),
          ],
        ),
        KitFigures(
          label: 'The shelf',
          rows: [
            ('Volumes', unread ? '—' : kitThousands(vols.length)),
            ('Passages', unread ? '—' : kitThousands(passages)),
            ('Span', unread ? '—' : _span(vols)),
            // The shelf's own (or inherited) mode, read with the shelf: it
            // stands when the documents read did not.
            ('In your letter', modeLabel),
          ],
        ),
        KitSheetAlso(
          children: [
            _FoldingAlso(
              'See on map',
              icon: KitMapGlyph.icon,
              // The focus rides `extra`, never the URL (INV-25b, ADR-177).
              onTap: () => context.go('/shelves/map', extra: shelf.id),
            ),
            // §Backfill review from the shelf's own page (4.83.0, ADR-117):
            // absent with no complete source — there is nothing to read.
            if (canBackfill)
              _FoldingAlso(
                _fillBusy ? 'Asking…' : 'Find sources for this shelf',
                icon: Icons.search,
                onTap: _fillBusy ? null : () => _findSources(shelf),
              ),
            // Last, in `--critical-text`: it opens §Deleting a shelf's §18
            // confirmation; nothing is deleted from the sheet itself.
            _FoldingAlso(
              'Delete shelf',
              icon: Icons.delete_outline,
              danger: true,
              onTap: () => _delete(shelf, direct, all, tree),
            ),
          ],
        ),
      ],
    );

    final notices = <Widget>[
      if (_fillError != null) KitFailureInline(_fillError!),
      if (libError != null)
        KitFailureInline('This shelf could not be read — $libError'),
    ];

    return KitDPage(
      back: KitDBackControl(
        'All shelves',
        onTap: () => context.go('/shelves'),
        trail: [
          for (final c in crumbs)
            (
              c.title.isEmpty ? 'Untitled' : c.title,
              () => context.go('/shelves/${c.id}'),
            ),
        ],
      ),
      crumbStacks: true,
      folio:
          'Shelf$provenance · '
          '${unread ? '— volumes' : kitCounted(vols.length, 'volume')} · '
          '${unread ? '— passages' : kitCounted(passages, 'passage')}',
      title: name,
      stand: (shelf.description ?? '').isEmpty ? null : shelf.description,
      // A control that says "this shelf" and asks the whole library is the
      // control lying (4.62.0, ADR-098): the scope rides the URL. Absent while
      // generative AI is off (5.29.0, ADR-186).
      action: aiOn
          ? KitPageAction(
              label: 'Ask this shelf',
              short: 'Ask shelf',
              icon: Icons.chat_bubble_outline,
              onPressed: () => context.go('/ask/shelf/${shelf.id}'),
            )
          : null,
      settings: KitPageSettings(
        label: 'Shelf settings',
        has: const ['letter'],
        body: (context, close) =>
            _settingsBody(shelf, direct, all, tree, parentId, eff),
      ),
      under: notices.isEmpty ? null : KitLibNotices(children: notices),
      sheet: KitDSheet(
        label: 'This shelf',
        foldOnPick: true,
        peek: KitLibPeek(
          mark: KitShelfSwatch(color),
          title: name,
          meta: sortLabel,
          count: unread ? '—' : kitThousands(vols.length),
        ),
        body: sheet,
      ),
      child: KitSourceView(
        builder: (context, view) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KitSectionHead(
              'The volumes',
              flushTop: true,
              meta: unread ? null : kitCounted(vols.length, 'volume'),
              actions: [if (!unread && vols.isNotEmpty) const KitViewToggle()],
            ),
            // A refused read draws nothing here: the line under the
            // masthead says why.
            if (unread)
              const SizedBox.shrink()
            else if (vols.isEmpty)
              const KitDNone(
                'This shelf is empty. Add a volume from your library to '
                'file it here.',
              )
            else if (view == 'grid')
              KitLibWall(items: items, homeOf: model.homeOf)
            else
              KitLibRegister(items: items, sort: _sort, homeOf: model.homeOf),
          ],
        ),
      ),
    );
  }

  /// Shelf settings (kit §28): *In your letter*, then *This shelf* — Name
  /// (saved on blur), Color (the twenty and the read-only current swatch),
  /// Inside (§20.2), Split (only at ≥ 5 volumes filed directly).
  Widget _settingsBody(
    Tag shelf,
    List<Document> direct,
    List<Tag> all,
    ShelfTree tree,
    String? parentId,
    ShelfLetterMode eff,
  ) {
    final valid = [
      for (final s in all)
        if (s.id != shelf.id && tree.canHold(shelf.id, s.id)) s,
    ];
    final inheritedFrom =
        shelf.ownLetterMode == null &&
            eff.from != null &&
            eff.from!.id != shelf.id
        ? eff.from!.title
        : null;
    // Built with the page: its controls redraw with the page's own state and
    // the tags read (write before you move).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const KitDLabel('In your letter', top: 18),
        KitShelfLetter(
          mode: eff.mode,
          inheritedFrom: inheritedFrom,
          canInherit: shelf.ownLetterMode != null && parentId != null,
          held: _savingLetter,
          error: _letterError,
          onMode: (m) => _setLetterMode(shelf, m),
        ),
        const KitDLabel('This shelf'),
        KitDFieldRow(
          label: 'Name',
          top: 4,
          error: _nameError,
          // The reference saves on blur. A keystroke-by-keystroke write
          // would re-embed the tag on every letter typed (`fn_update_tag`
          // re-embeds when the title changes).
          child: Focus(
            onFocusChange: (has) {
              if (!has) _saveName(shelf);
            },
            // A shelf's NAME, set in `.ss-input`'s serif — not the data mono.
            child: KitTextField(controller: _name, face: KitFieldFace.serif),
          ),
        ),
        KitDFieldRow(
          label: 'Color',
          error: _colorError,
          child: ShelfSwatches(
            selected: shelf.color,
            enabled: !_savingColor,
            showCurrent: true,
            onPick: (token) => _pickColour(shelf, token),
          ),
        ),
        // Move into (5.28.0, ADR-185): every valid parent, plus the top
        // level.
        KitDFieldRow(
          label: 'Inside',
          error: _moveError,
          child: Align(
            alignment: Alignment.centerLeft,
            child: KitShelfSelect(
              value: parentId ?? '',
              shelves: valid,
              allShelves: all,
              none: 'Top level',
              label: 'Move ${shelf.title} into',
              disabled: _moving,
              onChanged: (id) => _moveTo(shelf, parentId, id),
              onCreate: (name) => showShelfSheet(
                context,
                canBackfill: false,
                land: null,
                initialName: name,
                createSubtitle:
                    '${shelf.title} moves into it as soon as it is created.',
                onCreated: (id) => _moveTo(shelf, parentId, id),
              ),
            ),
          ),
        ),
        // 2.20.0 (ADR-025) — offered only at >= 5 volumes filed directly,
        // and ABSENT below that rather than disabled: the endpoint 400s
        // there, and there is nothing to divide. The suggestion runs in the
        // background and waits in For your review (4.102.0).
        if (direct.length >= splitMinDocuments)
          KitDFieldRow(
            label: 'Split',
            error: _splitError,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_splitRequested)
                  const KitRowNote(
                    'A split is being suggested — it will wait for you in '
                    'For your review. Nothing changes until you confirm '
                    'there.',
                  )
                else ...[
                  KitButton.secondary(
                    _splitBusy ? 'Asking…' : 'Split this shelf',
                    icon: Icons.call_split,
                    onPressed: _splitBusy ? null : () => _requestSplit(shelf),
                  ),
                  const SizedBox(height: 8),
                  KitRowNote(
                    'Divide ${kitCounted(direct.length, 'volume')} into '
                    'narrower shelves. The suggestion waits in For your '
                    'review; nothing changes until you confirm.',
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  /// While the shelves read is out: the D frame stands, its title, sheet and
  /// column as skeleton lines (web `ShelfLoading`).
  Widget _loading(BuildContext context) => KitDPage(
    back: KitDBackControl('All shelves', onTap: () => context.go('/shelves')),
    crumbStacks: true,
    folio: 'Shelf',
    title: '',
    titleWidget: const KitSkeletonLines(
      lines: [KitSkelLine(0.4, true)],
      top: 0,
    ),
    sheet: KitDSheet(
      label: 'This shelf',
      peek: Row(
        children: [
          KitGlyph(
            KitStackGlyph.icon,
            size: 16,
            color: Tokens.of(context).fgMuted,
          ),
          const SizedBox(width: 10),
          const Expanded(child: KitPeekWait('This shelf')),
        ],
      ),
      body: const KitSkeletonLines(
        lines: [
          KitSkelLine(0.6), KitSkelLine(), KitSkelLine(), //
          KitSkelLine(0.4), KitSkelLine(), KitSkelLine(),
        ],
        top: 0,
      ),
    ),
    child: const KitSkeletonLines(
      lines: [
        KitSkelLine(0.4, true), KitSkelLine(), KitSkelLine(), //
        KitSkelLine(0.7), KitSkelLine(), KitSkelLine(), KitSkelLine(0.6),
      ],
      top: 0,
    ),
  );

  /// INV-24: shelves we could not read say so — "may have been deleted" is a
  /// claim about a list this page never received (web `ShelfDetail`).
  Widget _notFound(BuildContext context, String? error) => KitDPage(
    back: KitDBackControl('All shelves', onTap: () => context.go('/shelves')),
    folio: 'Shelf',
    title: error != null ? 'Shelf' : 'Shelf Not Found',
    stand: error != null ? null : 'This shelf may have been deleted.',
    child: error != null
        ? KitFailureBlock(
            sentence: 'This shelf could not be read.',
            detail: error,
          )
        : const SizedBox.shrink(),
  );
}

/// An *Also* row that folds the running head first (web `FOLD` names
/// `.rx-more .btn`): an action that opens a sheet or a confirm must not leave
/// the running head dropped over it.
class _FoldingAlso extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool danger;

  const _FoldingAlso(
    this.label, {
    required this.icon,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) => KitAlsoButton(
    label,
    icon: icon,
    danger: danger,
    onTap: onTap == null
        ? null
        : () {
            KitSheetScope.pick(context);
            onTap!();
          },
  );
}

/// Where the shelf sits is its crumb (5.28.0, ADR-185); "split from" was the
/// label for a relation that now nests.
String _provenance(Tag shelf) =>
    shelf.source == 'auto_created' ? ' · auto-created' : '';

/// The span of a shelf: the first volume's date, and the last's when there is
/// more than one. `—` when there is nothing to measure — a measured absence,
/// never a zero.
String _span(List<Document> vols) {
  if (vols.isEmpty) return '—';
  final ranked = [...vols]
    ..sort((a, b) => (a.createdAt ?? 0).compareTo(b.createdAt ?? 0));
  final first = shortDate(ranked.first.createdAt);
  if (ranked.length == 1) return first;
  return '$first – ${shortDate(ranked.last.createdAt)}';
}
