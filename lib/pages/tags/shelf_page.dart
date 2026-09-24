import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/document.dart';
import '../../models/tag.dart';
import '../../state/documents_notifier.dart';
import '../../state/tags_notifier.dart';
import '../../widgets/kit/kit.dart';
import 'reshelve_sheet.dart';
import 'shelf_parts.dart';
import 'split_shelf_sheet.dart';

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

  bool _settings = false;
  bool _savingColor = false;
  String? _colorError;
  String? _nameError;
  int _sort = 0;

  static const _sorts = [
    KitSegment('Recent'),
    KitSegment('Title'),
    KitSegment('Passages'),
  ];

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

  /// Write before move, for the name as for the colour: the field keeps what
  /// the reader typed, and `_savedName` moves only once `fn_update_tag` has
  /// answered — so a rejected rename cannot read as a successful one.
  Future<void> _saveName(Tag shelf) async {
    final next = _name.text.trim();
    if (next.isEmpty || next == _savedName) return;
    final err =
        await context.read<TagsNotifier>().updateTag(shelf.id, title: next);
    if (!mounted) return;
    setState(() {
      _nameError = err;
      if (err == null) _savedName = next;
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
    final err =
        await context.read<TagsNotifier>().updateTag(shelf.id, color: token);
    if (!mounted) return;
    setState(() {
      _savingColor = false;
      _colorError = err;
    });
    // No local colour state: the tags subscription (INV-02) carries the
    // accepted value back, so what is drawn is what was stored.
  }

  // §18 (4.56.0, ADR-092): the delete runs INSIDE the confirmation, so a refusal
  // answers in the panel and the panel stays open. It used to close first and
  // put the sentence in the colour picker's error slot, three controls away
  // from the button that was pressed.
  //
  // 4.85.0 (ADR-119): the confirmation names the sources left on no shelf and
  // offers to re-shelve them. The ids are captured BEFORE the delete — after
  // it no query can find what the shelf held — and the review sheet opens on
  // the root navigator, because this page has nothing to render once its
  // shelf is gone.
  Future<void> _delete(Tag shelf, List<Document> vols, List<Tag> all) async {
    final tags = context.read<TagsNotifier>();
    final nav = Navigator.of(context, rootNavigator: true);
    final others = [
      for (final s in all)
        if (s.id != shelf.id) ReshelveItem(s.id, s.title),
    ];
    final canReshelve = vols.isNotEmpty && others.isNotEmpty;
    final orphans =
        vols.where((d) => d.tagIds.every((t) => t == shelf.id)).length;
    final sources = [for (final d in vols) ReshelveItem(d.id, d.title)];
    final title = shelf.title;
    var reshelveOn = true;
    final body = 'The shelf and its settings are removed. Its '
        '${plural(vols.length, 'volume stays', 'volumes stay')} in your '
        'library — they just come off this shelf.'
        '${orphans > 0 ? ' $orphans of them ${orphans == 1 ? 'is' : 'are'} on no other shelf.' : ''}';
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
                subtitle: 'After the delete, NoteLetter suggests one of your '
                    'other shelves for each. Nothing is filed until you '
                    'choose.',
                onChanged: (v) => setLocal(() => reshelveOn = v),
              ),
            ],
          ],
        ),
      ),
      confirmLabel: 'Delete shelf',
      cancelLabel: 'Keep it',
      onConfirm: () => tags.deleteTag(shelf.id),
    );
    if (done != true || !mounted) return;
    context.go('/shelves');
    if (canReshelve && reshelveOn && nav.mounted) {
      showReshelveSheet(nav.context,
          title: title, sources: sources, shelves: others);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<TagsNotifier, DocumentsNotifier>(
      builder: (context, tags, docs, _) {
        if (tags.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        final shelf = tags.tags.where((t) => t.id == widget.shelfId).firstOrNull;
        if (shelf == null) return _notFound(context);

        if (!_nameBound) {
          _nameBound = true;
          _name.text = shelf.title;
          _savedName = shelf.title;
        }

        final vols = shelfVolumes(shelf, docs.complete);
        final passages = shelfPassages(vols);
        final error = tags.error ?? docs.error;

        return KitPage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KitBackControl('All shelves',
                  onTap: () => context.go('/shelves')),
              const SizedBox(height: 18),
              ChapterOpening(
                mark: KitShelfPlate(shelf.color),
                folio: 'Shelf${_provenance(shelf, tags.tags)} · '
                    '${plural(vols.length, 'volume', 'volumes')} · '
                    '${plural(passages, 'passage', 'passages')}',
                title: shelf.title,
                standfirst: (shelf.description ?? '').isEmpty
                    ? null
                    : shelf.description,
                rule: false,
                actions: [
                  // A control that says "this shelf" and asks the whole
                  // library is the control lying (4.62.0, ADR-098). The scope
                  // rides the URL, so a reload keeps it and the screen never
                  // claims a scope it is not sending.
                  KitButton.ghost('Ask this shelf',
                      icon: Icons.forum_outlined,
                      onPressed: () => context.go('/ask/shelf/${shelf.id}')),
                  _settings
                      ? KitButton.secondary('Settings',
                          icon: Icons.tune,
                          onPressed: () => setState(() => _settings = false))
                      : KitButton.ghost('Settings',
                          icon: Icons.tune,
                          onPressed: () => setState(() => _settings = true)),
                ],
              ),
              if (error != null) ...[
                KitFailureInline('This shelf could not be read — $error'),
                const SizedBox(height: 14),
              ],
              // §8 — measured, every one: counted from the documents this
              // subscription actually carries.
              KitStatCluster(stats: [
                KitStat('${vols.length}', 'Volumes'),
                KitStat('$passages', 'Passages'),
                KitStat(_span(vols), 'Span'),
              ]),
              if (_settings) ...[
                const SizedBox(height: 22),
                _settingsPanel(shelf, vols, tags.tags),
              ],
              const SizedBox(height: 12),
              SectionHeader('Volumes · ${vols.length}'),
              KitControlBar(
                trailing: [
                  const KitControlLabel('Order by'),
                  KitSegmented(
                    segments: _sorts,
                    selected: _sort,
                    onChanged: (i) => setState(() => _sort = i),
                  ),
                ],
              ),
              if (vols.isEmpty)
                KitEmptyState(
                  icon: Icons.auto_stories_outlined,
                  title: 'This shelf is empty.',
                  standfirst:
                      'Add a volume from your library to file it here.',
                  suggestions: [
                    KitSuggestion(
                      icon: Icons.library_books_outlined,
                      label: 'Open your library',
                      onTap: () => context.go('/sources'),
                    ),
                  ],
                )
              else
                KitRowList(
                  rows: [
                    for (final d in _ordered(vols))
                      KitSourceLink(
                        docId: d.id,
                        builder: (context, open) => KitSourceRow(
                          leading: KitFileBadge(kitDocKind(d.type)),
                          title: d.title.isEmpty ? 'Untitled' : d.title,
                          subtitle: plural(d.chunkCount ?? 0, 'passage', 'passages'),
                          count: '${d.chunkCount ?? 0}',
                          date: shortDate(d.createdAt),
                          onTap: open,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _notFound(BuildContext context) => KitPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            KitBackControl('All shelves', onTap: () => context.go('/shelves')),
            const SizedBox(height: 18),
            const ChapterOpening(
              title: 'Shelf not found',
              standfirst: 'This shelf may have been deleted.',
            ),
          ],
        ),
      );

  Widget _settingsPanel(Tag shelf, List<Document> vols, List<Tag> all) {
    final volumes = vols.length;
    return KitPanel(
      children: [
        KitPanelRow(
          label: 'Name',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                // The reference saves on blur; so does this. A trailing Save
                // button would be a control the reader has to find, and a
                // keystroke-by-keystroke write would re-embed the tag on every
                // letter typed (`fn_update_tag` re-embeds when the title
                // changes).
                child: Focus(
                  onFocusChange: (has) {
                    if (!has) _saveName(shelf);
                  },
                  child: KitTextField(controller: _name),
                ),
              ),
              if (_nameError != null) ...[
                const SizedBox(height: 8),
                KitFailureInline(_nameError!),
              ],
            ],
          ),
        ),
        KitPanelRow(
          label: 'Color',
          alignTop: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShelfSwatches(
                selected: shelf.color,
                enabled: !_savingColor,
                onPick: (token) => _pickColour(shelf, token),
              ),
              if (_colorError != null) ...[
                const SizedBox(height: 8),
                KitFailureInline(_colorError!),
              ],
            ],
          ),
        ),
        // 2.20.0 (ADR-025) — offered only at >= 5 volumes, and ABSENT below
        // that rather than disabled: the endpoint 400s there, and there is
        // nothing to divide.
        if (volumes >= splitMinDocuments)
          KitPanelRow(
            label: 'Split',
            alignTop: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KitButton.secondary(
                  'Split this shelf',
                  icon: Icons.call_split,
                  onPressed: () => SplitShelfSheet.show(
                      context, shelf.id, shelf.title),
                  // Nothing to reload after: tags are a live subscription
                  // (INV-02), so the new shelves and the parent's recomputed
                  // count arrive on their own.
                ),
                const SizedBox(height: 8),
                KitRowNote(
                  'Divide $volumes volumes into narrower shelves. '
                  'Nothing changes until you confirm.',
                ),
              ],
            ),
          ),
        KitPanelRow(
          label: 'Danger',
          child: Align(
            alignment: Alignment.centerLeft,
            child: KitButton.danger(
              'Delete shelf',
              icon: Icons.delete_outline,
              onPressed: () => _delete(shelf, vols, all),
            ),
          ),
        ),
      ],
    );
  }

  List<Document> _ordered(List<Document> vols) {
    final arr = [...vols];
    switch (_sort) {
      case 1:
        arr.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case 2:
        arr.sort((a, b) => (b.chunkCount ?? 0).compareTo(a.chunkCount ?? 0));
      default:
        arr.sort((a, b) => (b.createdAt ?? 0).compareTo(a.createdAt ?? 0));
    }
    return arr;
  }
}

/// Provenance is **purely a label** (ADR-025): counts and filters never roll up
/// to the parent, child shelves are not nested under it in the index, and a
/// `parent_tag_id` whose shelf has since been deleted reads as nothing rather
/// than as an error.
String _provenance(Tag shelf, List<Tag> shelves) {
  if (shelf.source == 'auto_created') return ' · auto-created';
  if (shelf.source != 'split_from') return '';
  final parent =
      shelves.where((s) => s.id == shelf.parentTagId).firstOrNull;
  return parent == null ? '' : ' · split from ${parent.title}';
}

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

