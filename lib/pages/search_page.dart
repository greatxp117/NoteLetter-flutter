import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/search_result.dart';
import '../models/tag.dart';
import '../services/firestore_service.dart';
import '../state/search_notifier.dart';
import '../state/tags_notifier.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/kit/kit.dart';
import 'search/reading_pane.dart';
import 'search/result_card.dart';
import 'search/search_field.dart';

/// **Search** (`spec/screens/search.md`) — semantic search over the library.
///
/// Recomposed against the kit (ADR-041, screen 5/11). What was here was the
/// search box lifted out of the retired dashboard: a sans page title, a 44px
/// rounded control, and a column of bespoke cards. Three parts of the screen
/// as specified did not exist at all — the **big field** the screen is built
/// around, the **control bar**, and the **reading pane**, which is the reason
/// this is the one screen in the app with a two-pane frame and a 1100px
/// ceiling. A search screen with no second pane is a list of excerpts.
///
/// Composition (§Composition), every part from the kit unless noted:
///
/// * **Frame** Wide (1100) — §1.5. The header block is fixed and the results
///   scroll beneath it (§1.4), as on the reference: the field a reader is
///   typing into does not scroll away from them.
/// * **Header** bespoke ([SearchBigField]) — eyebrow over the big field. Not a
///   chapter opening; §2 names search as one of the three screens that has its
///   own.
/// * **Controls** a control bar (§6.6) of filter chips (§6.7) carrying counts,
///   **disabled at zero rather than hidden**, with the measured result count as
///   the trailing control.
/// * **Body** [SearchResultCard]s in the leading pane and [SearchReadingPane]
///   beside them; a phone stacks the two, it does not drop the pane.
///
/// **Not built here:** the citation path. The parser (`scripture/parse.dart`)
/// and `fn_scripture_lookup` both exist on this client and nothing calls them,
/// so a citation searches as ordinary text. That is a parity gap, not a
/// composition one — recorded in `../TODO.md`.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();

  /// The query whose results are on screen — not what is in the field. Search
  /// runs on submit, so the two differ while the reader is typing, and the
  /// header must not describe results the reader has not asked for yet.
  String _submitted = '';
  String _filter = 'all';

  SearchResult? _selected;
  List<Chunk> _context = const [];
  bool _contextLoading = false;

  @override
  void initState() {
    super.initState();
    // Shelves, for the shelf pill on a result card (INV-02, and the same
    // subscription Library and Sources already hold — not a second read).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<TagsNotifier>().start();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit(String raw) async {
    final query = raw.trim();
    if (query.isEmpty) {
      context.read<SearchNotifier>().clear();
      setState(() {
        _submitted = '';
        _selected = null;
        _context = const [];
      });
      return;
    }

    setState(() {
      _submitted = query;
      _filter = 'all';
      _selected = null;
      _context = const [];
    });

    final search = context.read<SearchNotifier>();
    await search.search(query, limit: 20);
    if (!mounted) return;
    // The reference opens the top result with the results, so the reading pane
    // is answering before the reader has clicked anything.
    final first = search.results.isEmpty ? null : search.results.first;
    if (first != null) _select(first);
  }

  Future<void> _select(SearchResult r) async {
    setState(() {
      _selected = r;
      _context = const [];
      _contextLoading = true;
    });
    // ±2 chunks around the match. This also logs `chunk_viewed`, which as of
    // 4.0.0 bumps `chunks.search_view_count` and **nothing else** (INV-03b):
    // reading a result in this pane is not opening the source and is not
    // reading the passage, so it clears no unread dot and moves no read
    // counter. `getChunkContext` owns that write — never log it from here.
    final chunks =
        await FirestoreService.instance.getChunkContext(r.chunk.chunkId);
    if (!mounted || _selected?.chunk.chunkId != r.chunk.chunkId) return;
    setState(() {
      _context = chunks;
      _contextLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<SearchNotifier, TagsNotifier>(
      builder: (context, search, tags, _) {
        final results = search.results;
        final counts = _countsFor(results);
        final shown = _filter == 'all'
            ? results
            : results.where((r) => _matches(r, _filter)).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KitFrame(
              width: KitFrameWidth.wide,
              top: AppSpacing.s8,
              bottom: 0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SearchBigField(
                    controller: _controller,
                    onSubmitted: _submit,
                  ),
                  if (_submitted.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.s4),
                    KitControlBar(
                      filters: [
                        for (final f in _filters.entries)
                          KitFilterChip(
                            f.value,
                            count: counts[f.key] ?? 0,
                            selected: _filter == f.key,
                            onPressed:
                                f.key == 'all' || (counts[f.key] ?? 0) > 0
                                    ? () => setState(() => _filter = f.key)
                                    : null,
                          ),
                      ],
                      trailing: [
                        _ResultCount(
                          loading: search.isLoading,
                          count: shown.length,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: KitScrollView(
                child: KitFrame(
                  width: KitFrameWidth.wide,
                  top: _submitted.isEmpty ? AppSpacing.s6 : 18,
                  child: _body(context, search, shown, tags.tags),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _body(
    BuildContext context,
    SearchNotifier search,
    List<SearchResult> shown,
    List<Tag> shelves,
  ) {
    if (_submitted.isEmpty) return _Suggestions(onPick: _run);

    if (search.isLoading && search.results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.s12),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (search.error != null) {
      return KitCard(
        child: Row(
          children: [
            Expanded(child: Text(search.error!, style: KitText.meta(context))),
            const SizedBox(width: AppSpacing.s4),
            KitButton.ghost('Try again', onPressed: () => _submit(_submitted)),
          ],
        ),
      );
    }

    if (search.results.isEmpty) {
      return KitEmptyState(
        icon: Icons.search_off_outlined,
        title: 'Nothing matched *that.*',
        standfirst: 'Search reads for meaning, so a longer question usually '
            'works better than a shorter one.',
        suggestions: [
          for (final s in _suggestions.take(2))
            KitSuggestion(
              icon: Icons.search,
              label: '“$s”',
              onTap: () => _run(s),
            ),
        ],
      );
    }

    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (shown.isEmpty)
          KitCard(
            child: Text('No passages of that kind in these results.',
                style: KitText.meta(context)),
          )
        else
          for (final r in shown)
            SearchResultCard(
              result: r,
              selected: _selected?.chunk.chunkId == r.chunk.chunkId,
              onTap: () => _select(r),
              onOpenSource: () => _openSource(r),
              shelfTitle: _shelfFor(r, shelves)?.title,
              shelfColorToken: _shelfFor(r, shelves)?.color,
            ),
      ],
    );

    final pane = SearchReadingPane(
      result: _selected,
      context: _context,
      loading: _contextLoading,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Below the compact width the panes stack — the reading pane goes under
        // the list, it is not dropped. The reference's stylesheet hides it at
        // that width; the screen spec says stack, and a phone reader needs the
        // surrounding context more than a desktop one, not less.
        if (constraints.maxWidth < AppSpacing.compactWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              list,
              const SizedBox(height: AppSpacing.s6),
              pane,
            ],
          );
        }
        // `minmax(380px, 1fr)` list + `minmax(420px, 560px)` pane, 28px gutter.
        final paneWidth = (constraints.maxWidth * 0.42).clamp(420.0, 560.0);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: list),
            const SizedBox(width: 28),
            SizedBox(width: paneWidth, child: pane),
          ],
        );
      },
    );
  }

  void _run(String query) {
    _controller.text = query;
    _submit(query);
  }

  /// The source of a result. Its id comes from the **chunk**: the search
  /// response's `document` is the stored document's fields, and a Firestore
  /// document's id is not among its fields, so `document` carries none.
  void _openSource(SearchResult r) =>
      context.push('/reader/${r.chunk.documentId}');

  Tag? _shelfFor(SearchResult r, List<Tag> shelves) {
    for (final s in shelves) {
      if (r.document.tagIds.contains(s.id)) return s;
    }
    return null;
  }
}

// ── The filter vocabulary ────────────────────────────────────────────────────

/// The reference's four filters, in its order. `all` leads and is never
/// disabled. The labels are the reader's words for the kinds, not the `type`
/// enum's — `Books & PDFs` covers `pdf` and `epub` together.
const _filters = <String, String>{
  'all': 'All sources',
  'pdf': 'Books & PDFs',
  'note': 'My notes',
  'web': 'Web',
};

const _suggestions = <String>[
  'What have I been reading about lately?',
  'Notes on habit formation',
  'Ideas about systems thinking',
  'Quotes about writing well',
];

bool _matches(SearchResult r, String filter) {
  final kind = kitDocKind(r.document.type);
  if (filter == 'pdf') return kind == 'pdf' || kind == 'epub';
  return kind == filter;
}

Map<String, int> _countsFor(List<SearchResult> results) {
  final counts = <String, int>{'all': results.length};
  for (final key in _filters.keys.where((k) => k != 'all')) {
    counts[key] = results.where((r) => _matches(r, key)).length;
  }
  return counts;
}

/// The trailing control of the bar: **how many passages, ranked how**. A
/// measured figure, in the mono face, and it says `Searching…` rather than a
/// stale count while a query is in flight.
class _ResultCount extends StatelessWidget {
  final bool loading;
  final int count;

  const _ResultCount({required this.loading, required this.count});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Text(
      loading
          ? 'Searching…'
          : '$count ${count == 1 ? 'passage' : 'passages'} · ranked by meaning',
      style: AppTheme.mono(
          fontSize: 11, letterSpacing: 0.04 * 11, color: t.fgSubtle),
    );
  }
}

/// The idle screen. **An offer, not an apology** (§7): a reader who has not
/// searched yet is shown what this screen can be asked, in the reader's own
/// voice — the suggestions are questions, not features.
class _Suggestions extends StatelessWidget {
  final ValueChanged<String> onPick;

  const _Suggestions({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return KitEmptyState(
      icon: Icons.search,
      title: 'Ask your library *anything.*',
      standfirst: 'Search reads for meaning rather than keywords, so describe '
          'what you remember and the passages come back ranked.',
      suggestions: [
        for (final s in _suggestions)
          KitSuggestion(
            icon: Icons.search,
            label: '“$s”',
            onTap: () => onPick(s),
          ),
      ],
    );
  }
}
