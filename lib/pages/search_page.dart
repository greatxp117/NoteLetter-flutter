import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/cohesive_reading.dart';
import '../models/search_result.dart';
import '../models/tag.dart';
import '../services/firestore_service.dart';
import '../state/search_notifier.dart';
import '../state/tags_notifier.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/kit/kit.dart';
import 'search/cohesive_column.dart';
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
/// * **Cohesive** (4.40.0, ADR-078) — the control bar's trailing slot holds a
///   segmented `Passages | Cohesive`, and while Cohesive a second
///   `Tighter | Normal | Broader` beside it; the body becomes
///   [CohesiveColumn], a single reading column in place of the split pane.
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

  /// Cohesive mode (4.40.0, ADR-078) is a **view mode**, so the control moves
  /// at once — and the body does not. The passages list stays exactly as it
  /// was until the reading lands (write-before-move applied to the frame,
  /// `screens/search.md` §States); the count line is what says a request is in
  /// flight, and it says so because a request IS in flight, not on a timer.
  bool _cohesive = false;
  String _breadth = 'normal';

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
    // Both modes ask the same query. The passages request always runs: it is
    // what the list under a cohesive reading shows while the reading is being
    // built, and what the reader falls back to on the way out of the mode.
    if (_cohesive) unawaited(_runCohesive());
    await search.search(query, limit: 20);
    if (!mounted) return;
    // The reference opens the top result with the results, so the reading pane
    // is answering before the reader has clicked anything.
    final first = search.results.isEmpty ? null : search.results.first;
    if (first != null) _select(first);
  }

  /// Ask for the reading of what is currently submitted.
  ///
  /// `sourceTypes` comes off the same chip the list is filtered by, inverted
  /// through the one kind vocabulary ([kitTypesForKind]) — the arrangement is
  /// built server-side, so a chip narrowing only the list we already hold would
  /// narrow the reading not at all.
  Future<void> _runCohesive() {
    final search = context.read<SearchNotifier>();
    if (_submitted.isEmpty) {
      search.clearCohesive();
      return Future.value();
    }
    return search.synthesize(
      _submitted,
      sourceTypes: _filter == 'all' ? null : kitTypesForKind(_filter),
      breadth: _breadth,
    );
  }

  void _setCohesive(bool on) {
    if (_cohesive == on) return;
    setState(() => _cohesive = on);
    if (on) {
      _runCohesive();
    } else {
      context.read<SearchNotifier>().clearCohesive();
    }
  }

  void _setBreadth(String breadth) {
    if (_breadth == breadth) return;
    setState(() => _breadth = breadth);
    _runCohesive();
  }

  void _setFilter(String filter) {
    if (_filter == filter) return;
    setState(() => _filter = filter);
    // The chip narrows the list on the client and the reading on the server;
    // only the second needs a request.
    if (_cohesive) _runCohesive();
  }

  /// The server's own `link` for a passage, followed inside the app. The route
  /// is built from the ids the response carries — `document_id` and `chunk_id`
  /// (INV-21) — never from anything reconstructed on screen.
  void _openInContext(CohesivePassage p) =>
      context.push('/reader/${p.documentId}?p=${p.chunkId}');

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
                                    ? () => _setFilter(f.key)
                                    : null,
                          ),
                      ],
                      trailing: [
                        // §6.8, non-wrapping: the view mode, then — only while
                        // Cohesive — the breadth beside it. The count line
                        // stays trailing.
                        KitSegmented(
                          segments: const [
                            KitSegment('Passages'),
                            KitSegment('Cohesive'),
                          ],
                          selected: _cohesive ? 1 : 0,
                          onChanged: (i) => _setCohesive(i == 1),
                        ),
                        if (_cohesive)
                          KitSegmented(
                            segments: [
                              for (final b in _breadths)
                                KitSegment(b.$2),
                            ],
                            selected: _breadths
                                .indexWhere((b) => b.$1 == _breadth),
                            onChanged: (i) => _setBreadth(_breadths[i].$1),
                          ),
                        _ResultCount(
                          loading: search.isLoading,
                          count: shown.length,
                          cohesive: _cohesive,
                          reading: _readingFor(search),
                          cohesiveLoading: search.cohesiveLoading,
                          cohesiveFailed: search.cohesiveError != null,
                          breadth: _breadth,
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

    // §14.1, ADR-070 — and it goes BEFORE the empty check for a reason: a
    // request that failed is not a library with nothing in it, and rendering
    // the empty state for one is the defect that pattern exists to prevent.
    if (search.error != null) {
      return KitFailureBlock(
        sentence: 'Search is unavailable right now.',
        detail: search.error!,
        requestId: search.requestId,
        onRetry: () => _submit(_submitted),
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

    // Write before you move, applied to the frame: the reading REPLACES the
    // split pane only once it has landed (or failed). Until then the passages
    // list is still what is on screen — switching the mode must not blank the
    // body for a request that may yet fail.
    final reading = _readingFor(search);
    if (_cohesive && (reading != null || search.cohesiveError != null)) {
      return CohesiveColumn(
        reading: reading,
        error: search.cohesiveError,
        requestId: search.cohesiveRequestId,
        onRetry: _runCohesive,
        onOpenInContext: _openInContext,
        onOpenSource: (docId) => context.push('/reader/$docId'),
      );
    }

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

  /// The reading, but only if it answers the query that is on screen. A
  /// response for a previous query is not a stale rendering of this one — it is
  /// an answer to a different question.
  CohesiveReading? _readingFor(SearchNotifier search) {
    final r = search.reading;
    return (r != null && r.query == _submitted) ? r : null;
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
// component-kit §6.4.1/§6.7 — the chip set IS the kind vocabulary. `podcast`
// and `video` were absent, so both buckets were reachable from "All sources"
// and nowhere else. An absent chip is not a DISABLED chip; it is a bucket that
// looks like it does not exist.
const _filters = <String, String>{
  'all': 'All sources',
  'pdf': 'Books & PDFs',
  'note': 'My notes',
  'web': 'Web',
  'podcast': 'Audio',
  'video': 'Video',
};

/// The breadth control's positions (`spec/api/search.md` §Selection). The id is
/// the request value; the label is the reader's word for it. **The fractions
/// behind them live on the server** — a client copy of 0.20/0.40/0.65 would be
/// a second threshold to keep in step, and this one is not even displayed.
const _breadths = <(String, String)>[
  ('tight', 'Tighter'),
  ('normal', 'Normal'),
  ('broad', 'Broader'),
];

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

  /// Cohesive mode reports the READING: `Arranging…` while the request is in
  /// flight, `{kept} of {pool} passages · {breadth}` when it lands, and
  /// `Cohesive reading unavailable` when it does not. Every figure measured —
  /// `kept` and `pool` are the server's own counts, not a length of a list this
  /// widget can see.
  final bool cohesive;
  final CohesiveReading? reading;
  final bool cohesiveLoading;
  final bool cohesiveFailed;
  final String breadth;

  const _ResultCount({
    required this.loading,
    required this.count,
    this.cohesive = false,
    this.reading,
    this.cohesiveLoading = false,
    this.cohesiveFailed = false,
    this.breadth = 'normal',
  });

  String _label() {
    if (!cohesive) {
      return loading
          ? 'Searching…'
          : '$count ${count == 1 ? 'passage' : 'passages'} · ranked by meaning';
    }
    if (cohesiveLoading) return 'Arranging…';
    if (cohesiveFailed) return 'Cohesive reading unavailable';
    final r = reading;
    if (r == null) return 'Arranging…';
    final word = _breadths.firstWhere((b) => b.$1 == r.breadth,
        orElse: () => (r.breadth, r.breadth)).$2.toLowerCase();
    return '${r.kept} of ${r.pool} passages · $word';
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Text(
      _label(),
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
