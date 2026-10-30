import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/cohesive_reading.dart';
import '../models/search_result.dart';
import '../models/tag.dart';
import '../scripture/parse.dart';
import '../services/analytics.dart';
import '../services/error_text.dart';
import '../services/firestore_service.dart';
import '../shared/local_flags.dart';
import '../state/documents_notifier.dart';
import '../state/search_notifier.dart';
import '../state/tags_notifier.dart';
import '../theme/app_radius.dart';
import '../theme/tokens.dart';
import '../widgets/kit/kit.dart';
import '../widgets/sidebar.dart' show shellAiOn;
import 'search/cohesive_column.dart';
import 'search/result_d.dart';
import 'search/scripture_results.dart';
import 'search/search_field.dart';

/// **Search** (`spec/screens/search.md`) — semantic search over the library,
/// in direction D (§Composition (direction D); web `pages/SearchView.jsx`).
///
/// * **Frame** — the D frame ([KitDPage], kit §26–§29) inside the primary
///   scroll, which ends with the support footer.
/// * **Masthead** — folio `Search · {N} passages · by meaning` (N the library's
///   complete volumes' passages, from the documents subscription; the dash
///   while it is out or refused); title *Search*; the standfirst says what the
///   column holds now ([searchStand]).
/// * **Tools** — the page's own field ([SearchQueryField]), in the rail's place
///   of Search. It stays in the masthead at every width: the toolbar's field
///   wider than a phone, under the standfirst and above the rule on one. No
///   action, no settings.
/// * **Sheet** — *Filters*: Kind (kit §29's facet over the kind chips, the
///   `pdf`/`epub` fold), **Read as** and **Breadth** (both absent while
///   generative AI is off). For a citation the sheet is *Scripture* instead.
///   The running head on a phone says the kind, the mode and the count.
/// * **Column** — no query: *Try searching for* and the suggestions; results:
///   the ruled register of [SearchResultD] rows, each opening in place; no
///   results; the §14.1 Failure block; the cohesive reading
///   ([CohesiveColumn]); or the scripture results.
///
/// * **Citation branch** (2.28.0 + 4.9.0, ADR-027 §2 / ADR-045) — a citation
///   is a **different question**, so it takes a different path and neither the
///   mode nor the breadth control appears on it. The client parse
///   (`scripture/parse.dart`) is the cheap prefilter that decides which
///   question is being asked; `fn_scripture_lookup` decides the **result**,
///   parsing again so one implementation says what was actually searched.
///   Active only where the client-local `nl-scripture` flag is on (ADR-027 §7).
///
/// **Not built here:** the quick-search citation echo. It needs a command
/// palette and this client has none — recorded as an n/a row in
/// `spec/clients/flutter.md` §Out of scope, not carried as a gap.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();

  /// The query whose results are on screen — not what is in the field. Search
  /// runs on submit, so the two differ while the reader is typing, and the
  /// masthead must not describe results the reader has not asked for yet.
  String _submitted = '';
  String _filter = 'all';

  /// Cohesive mode (4.40.0, ADR-078) is a **view mode**, so the control moves
  /// at once — and the body does not. The passages list stays exactly as it
  /// was until the reading lands (write-before-move applied to the frame,
  /// `screens/search.md` §States); the standfirst is what says a request is in
  /// flight, and it says so because a request IS in flight, not on a timer.
  bool _cohesive = false;
  String _breadth = 'normal';

  /// The row open in place (its chunk id) — one at a time.
  String? _openId;

  /// The row whose neighbours were read last, and what came back.
  SearchResult? _selected;
  List<Chunk> _context = const [];

  /// A failed CONTEXT read is its own state (`screens/search.md` §States).
  /// The matched chunk is still true, so it stays on screen; what is missing
  /// is the neighbours, and that is said (§14.2) rather than drawn as a
  /// passage that happens to stand alone.
  String? _contextError;

  /// The citation branch is live for this query. Null on every ordinary query;
  /// the parse is the client's, the result is the server's.
  Citation? _citation;

  @override
  void initState() {
    super.initState();
    // The client-local scripture flag decides whether a citation is a
    // different question at all (ADR-027 §7).
    LocalFlags.ensureLoaded();
    // Shelves, for the shelf on a result row, and the documents the folio
    // counts its passages from (INV-02: the subscriptions Library and the
    // rail already hold — not a second read).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<TagsNotifier>().start();
      context.read<DocumentsNotifier>().start();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _aiOn => shellAiOn(context);

  /// Read as is absent while generative AI is off (5.29.0, ADR-186): the mode
  /// is passages, whatever was last picked.
  bool get _cohesiveOn => _aiOn && _cohesive;

  void _resetRows() {
    _openId = null;
    _selected = null;
    _context = const [];
    _contextError = null;
  }

  Future<void> _submit(String raw) async {
    final query = raw.trim();
    final search = context.read<SearchNotifier>();
    if (query.isEmpty) {
      search.clear();
      setState(() {
        _submitted = '';
        _citation = null;
        _resetRows();
      });
      return;
    }

    // The client parse decides WHICH QUESTION is being asked, cheaply enough
    // to have been the reason ADR-027 §2 keeps parsing client-side at all.
    // `looksLikeCitation` is the free prefilter; a false positive costs
    // nothing because `parseCitation` still rejects it, and being conservative
    // is what keeps an ordinary search from being hijacked (a bare `acts` is a
    // word, not a book).
    final citation =
        LocalFlags.scripture.value && looksLikeCitation(query) &&
                !search.rejectedAsCitation(query)
            ? parseCitation(query)
            : null;

    setState(() {
      _submitted = query;
      _citation = citation;
      _resetRows();
    });
    search.clearScripture();

    if (citation != null) {
      // The server parses again and its reading wins. `parsed: false` is it
      // saying this was an ordinary query after all — a NORMAL answer, so the
      // screen falls through to the vector search rather than showing a
      // failure. Recording which query was rejected is what actually releases
      // the fall-through.
      final stay = await search.lookupScripture(query);
      if (!mounted) return;
      if (stay) return;
      setState(() => _citation = null);
    }

    // Both modes ask the same query. The passages request always runs: it is
    // what the list under a cohesive reading shows while the reading is being
    // built, and what the reader falls back to on the way out of the mode.
    if (_cohesiveOn) unawaited(_runCohesive());
    await _runSearch();
  }

  /// The passages request — the one place it is built, so the kind, the query
  /// and a retry all send the same thing.
  ///
  /// `sourceTypes` goes to the SERVER (4.28.0, ADR-065): it prefilters the
  /// KNN, so each kind returns its own top 20 rather than narrowing the
  /// global top 20 locally.
  Future<void> _runSearch() => context.read<SearchNotifier>().search(
        _submitted,
        sourceTypes: _filter == 'all' ? null : searchSourceTypes(_filter),
        limit: 20,
      );

  /// Ask for the reading of what is currently submitted, over the same kind.
  Future<void> _runCohesive() {
    final search = context.read<SearchNotifier>();
    if (_submitted.isEmpty) {
      search.clearCohesive();
      return Future.value();
    }
    return search.synthesize(
      _submitted,
      sourceTypes: _filter == 'all' ? null : searchSourceTypes(_filter),
      breadth: _breadth,
    );
  }

  void _setMode(String mode) {
    final on = mode == 'cohesive';
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
    setState(() {
      _filter = filter;
      _resetRows();
    });
    if (_submitted.isEmpty) return;
    // **Choosing a kind re-runs the search.** It does not narrow the page
    // already returned — that is a different question, and the wrong one.
    unawaited(_runSearch());
    if (_cohesiveOn) _runCohesive();
  }

  void _clear() {
    _controller.clear();
    _submit('');
  }

  void _run(String query) {
    _controller.text = query;
    _submit(query);
  }

  /// Open or fold a row. One row is open at a time; `result_opened` fires on
  /// OPENING only (4.41.0) — the same control folds it, and counting both
  /// would make one read look like two. The rank is bucketed, never sent raw
  /// (INV-25b).
  void _toggle(SearchResult r, int rank) {
    final id = r.chunk.chunkId;
    if (_openId == id) {
      setState(() => _openId = null);
      return;
    }
    Analytics.track('result_opened', {'rank_bucket': Analytics.bucket(rank)});
    setState(() => _openId = id);
    // The neighbours of a row already read are not read again (web keeps the
    // last context while the same result is selected).
    if (_selected?.chunk.chunkId == id && _contextError == null) return;
    _readContext(r);
  }

  /// The ±2 window around the match. This also logs `chunk_viewed`, which as
  /// of 4.0.0 bumps `chunks.search_view_count` and **nothing else** (INV-03b):
  /// opening a result in place is not opening the source and is not reading
  /// the passage, so it clears no unread dot and moves no read counter.
  /// `getChunkContext` owns that write — never log it from here. Read only
  /// when a row is OPENED, so a passage nobody expanded counts no view.
  Future<void> _readContext(SearchResult r) async {
    setState(() {
      _selected = r;
      _context = const [];
      _contextError = null;
    });
    try {
      final chunks =
          await FirestoreService.instance.getChunkContext(r.chunk.chunkId);
      if (!mounted || _selected?.chunk.chunkId != r.chunk.chunkId) return;
      setState(() => _context = chunks);
    } catch (e) {
      if (!mounted || _selected?.chunk.chunkId != r.chunk.chunkId) return;
      setState(() {
        _context = const [];
        _contextError = describeSdkError(e);
      });
    }
  }

  /// The reading, but only if it answers the query that is on screen. A
  /// response for a previous query is not a stale rendering of this one — it is
  /// an answer to a different question.
  CohesiveReading? _readingFor(SearchNotifier search) {
    final r = search.reading;
    return (r != null && r.query == _submitted) ? r : null;
  }

  /// The source of a result. Its id comes from the **chunk**: the search
  /// response's `document` is the stored document's fields, and a Firestore
  /// document's id is not among its fields, so `document` carries none.
  void _openSource(SearchResult r) =>
      context.push('/reader/${r.chunk.documentId}');

  /// The server's own `link` for a passage, followed inside the app. The route
  /// is built from the ids the response carries — `document_id` and `chunk_id`
  /// (INV-21) — never from anything reconstructed on screen.
  void _openInContext(CohesivePassage p) =>
      context.push('/reader/${p.documentId}?p=${p.chunkId}');

  Tag? _shelfFor(SearchResult r, List<Tag> shelves) {
    for (final s in shelves) {
      if (r.document.tagIds.contains(s.id)) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final search = context.watch<SearchNotifier>();
    final shelves = context.watch<TagsNotifier>().tags;
    final docs = context.watch<DocumentsNotifier>();
    final aiOn = _aiOn;
    final cohesive = aiOn && _cohesive;
    final citation = _citation;
    final asked = _submitted.isNotEmpty;
    final reading = _readingFor(search);
    final n = search.results.length;

    // The folio's figure is the library's passages, counted from the
    // documents read — the dash while it is out or was refused (ADR-109).
    final passages = docs.measured
        ? docs.complete.fold<int>(0, (t, d) => t + (d.chunkCount ?? 0))
        : null;
    final folio = searchFolio(passages);

    final stand = searchStand(
      asked: asked,
      citationRef: citation?.ref,
      scriptureLoading: search.scriptureLoading,
      scriptureFailed: search.scriptureError != null,
      scriptureReference: search.scripture?.reference,
      cohesive: cohesive,
      cohesiveLoading: search.cohesiveLoading,
      cohesiveFailed: search.cohesiveError != null,
      reading: reading,
      breadth: _breadth,
      loading: search.isLoading,
      failed: search.error != null,
      count: n,
    );

    final phone = KitD.phone(context);
    final field = SearchQueryField(
      controller: _controller,
      onSubmitted: _submit,
      onClear: _clear,
    );

    final kindLabel = _filters[_filter] ?? _filters['all']!;
    final breadthLabel = _breadthLabel(_breadth);
    final peek = KitLibPeek(
      icon: Icons.tune,
      title: citation != null ? 'Scripture' : kindLabel,
      meta: cohesive ? 'Cohesive · $breadthLabel' : 'Passages',
      count: asked && citation == null && !search.isLoading &&
              search.error == null
          ? '${cohesive && reading != null ? reading.kept : n}'
          : null,
    );

    return KitDPage(
      folio: folio,
      title: 'Search',
      stand: stand,
      // The page's own field (kit §27): in the toolbar wider than a phone —
      // KitDPage keeps a page's field there from 1024 down, where every other
      // page's tools leave for the chrome — and on a phone under the
      // standfirst, above the rule.
      search: false,
      field: phone ? null : field,
      byline: phone
          ? Padding(padding: const EdgeInsets.only(top: 18), child: field)
          : null,
      sheet: KitDSheet(
        label: 'Filters',
        peek: peek,
        body: citation != null
            ? _ScriptureSheet(onLeave: _clear)
            : _FiltersSheet(
                filter: _filter,
                onFilter: _setFilter,
                aiOn: aiOn,
                cohesive: cohesive,
                onMode: _setMode,
                breadth: _breadth,
                onBreadth: _setBreadth,
              ),
      ),
      child: _body(context, search, shelves, reading),
    );
  }

  Widget _body(
    BuildContext context,
    SearchNotifier search,
    List<Tag> shelves,
    CohesiveReading? reading,
  ) {
    if (_submitted.isEmpty) return _TrySearching(onPick: _run);

    // ── The citation branch ───────────────────────────────────────────────
    final citation = _citation;
    if (citation != null) {
      final lookup = search.scripture;
      if (lookup != null) {
        return ScriptureResults(
          data: lookup,
          onOpenSource: (docId) => context.push('/reader/$docId'),
        );
      }
      if (search.scriptureLoading) {
        return KitDNone('Reading ${citation.ref}…');
      }
      // §14.1, **named for the reference it could not read**. This is not
      // `Not a citation`, which is the server saying the query parsed as
      // ordinary text — that answer falls through to the vector search and
      // never reaches here.
      if (search.scriptureError != null) {
        return KitFailureBlock(
          sentence: '${citation.ref} could not be looked up.',
          detail: search.scriptureError!,
          requestId: search.scriptureRequestId,
          onRetry: () => _submit(_submitted),
        );
      }
    }

    // Write before you move, applied to the frame: the reading REPLACES the
    // register only once it has landed (or failed). Until then the passages
    // are still what is on screen — switching the mode must not blank the
    // body for a request that may yet fail.
    if (_cohesiveOn && (reading != null || search.cohesiveError != null)) {
      return CohesiveColumn(
        reading: reading,
        error: search.cohesiveError,
        requestId: search.cohesiveRequestId,
        onRetry: _runCohesive,
        onOpenInContext: _openInContext,
        onOpenSource: (docId) => context.push('/reader/$docId'),
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

    // **No client-side narrowing** (ADR-065 §2): the server already returned
    // this kind, prefiltered inside the vector search.
    final shown = search.results;
    return SearchRegister(
        children: [
          for (final (i, r) in shown.indexed)
            SearchResultD(
              key: ValueKey('search-result-${r.chunk.chunkId}'),
              result: r,
              rank: i + 1,
              shelfTitle: _shelfFor(r, shelves)?.title,
              shelfColor: _shelfFor(r, shelves)?.color,
              open: _openId == r.chunk.chunkId,
              onToggle: () => _toggle(r, i + 1),
              onOpenSource: () => _openSource(r),
              context: _selected?.chunk.chunkId == r.chunk.chunkId
                  ? _context
                  : const [],
              contextError: _selected?.chunk.chunkId == r.chunk.chunkId
                  ? _contextError
                  : null,
            ),
          if (!search.isLoading && shown.isEmpty)
            const KitDNone(
              'No passages found. Try a broader phrase, or ask your library.',
              top: 18,
            ),
        ],
    );
  }
}

// ── The masthead's sentences ────────────────────────────────────────────────

/// The folio: `Search · {N} passages · by meaning`, N with its thousands
/// separators; the dash while the documents read is out or refused.
String searchFolio(int? passages) =>
    'Search · ${passages == null ? '— passages' : kitCounted(passages, 'passage')}'
    ' · by meaning';

/// The standfirst says what the column holds now (search.md §Composition,
/// **Masthead**). *Seven passages* is a measurement; a failed request
/// measured nothing (§8's rule, applied to it), so it never reads `0`.
String searchStand({
  required bool asked,
  String? citationRef,
  bool scriptureLoading = false,
  bool scriptureFailed = false,
  String? scriptureReference,
  bool cohesive = false,
  bool cohesiveLoading = false,
  bool cohesiveFailed = false,
  CohesiveReading? reading,
  String breadth = 'normal',
  bool loading = false,
  bool failed = false,
  int count = 0,
}) {
  if (!asked) {
    return 'Ask in plain language. Your library is searched by meaning, so '
        'the words do not have to match.';
  }
  if (citationRef != null) {
    if (scriptureLoading) return 'Reading $citationRef…';
    if (scriptureFailed) return '$citationRef could not be looked up.';
    if (scriptureReference != null) {
      return '$scriptureReference, verse by verse.';
    }
    return 'Not a citation.';
  }
  if (cohesive && (cohesiveLoading || cohesiveFailed || reading != null)) {
    if (cohesiveLoading) return 'Arranging the passages into one reading…';
    if (cohesiveFailed) return 'The cohesive reading could not be built.';
    final r = reading!;
    return '${r.kept} of ${kitCounted(r.pool, 'passage')}, arranged as one '
        'reading · ${_breadthLabel(r.breadth)}.';
  }
  if (loading) return 'Searching…';
  if (failed) return 'Search is unavailable right now.';
  return '${kitCap(kitSay(count))} ${count == 1 ? 'passage' : 'passages'}, '
      'ranked by meaning.';
}

// ── The kind vocabulary ─────────────────────────────────────────────────────

/// A FOLD: one chip carrying a second kind's types (ADR-152). "Books & PDFs"
/// is the `pdf` chip and it also sends `epub` — declared here as data, because
/// `doc_kind_check.py` reads this map rather than assuming a fold the request
/// never performed (until 4.115.0 the gate held `{"epub"}` for this surface
/// while the chip sent `kitTypesForKind('pdf')` alone). Web `SEARCH_FOLDS`.
const _searchFolds = <String, List<String>>{
  'pdf': ['epub'],
};

/// The `sourceTypes` a Search kind sends: its own kind's types plus every
/// folded kind's (web `sourceTypesFor`).
List<String> searchSourceTypes(String chip) => [
      ...kitTypesForKind(chip),
      for (final k in _searchFolds[chip] ?? const <String>[])
        ...kitTypesForKind(k),
    ];

/// The Kind facet's choices — the reference's, in its order (web `FILTERS`).
/// `all` leads. The set IS the kind vocabulary (component-kit §6.4.1/§6.7):
/// `podcast` and `video` were once absent, so both buckets were reachable from
/// "All sources" and nowhere else. **No counts** (ADR-065 §4): a count over
/// one page of results is a statement about that page, not the library.
const _filters = <String, String>{
  'all': 'All sources',
  'pdf': 'Books & PDFs',
  'note': 'My notes',
  'web': 'Web',
  'youtube': 'YouTube',
  'instagram': 'Instagram',
  'tiktok': 'TikTok',
  'podcast': 'Audio',
  'video': 'Video',
};

/// The Kind facet's ids and labels, in order — for the tests.
List<(String, String)> get searchKinds =>
    [for (final e in _filters.entries) (e.key, e.value)];

/// The breadth control's positions (`spec/api/search.md` §Selection). The id is
/// the request value; the label is the reader's word for it. **The fractions
/// behind them live on the server** — a client copy of 0.20/0.40/0.65 would be
/// a second threshold to keep in step, and this one is not even displayed.
const _breadths = <(String, String)>[
  ('tight', 'Tighter'),
  ('normal', 'Normal'),
  ('broad', 'Broader'),
];

String _breadthLabel(String id) => _breadths
    .firstWhere((b) => b.$1 == id, orElse: () => (id, id))
    .$2
    .toLowerCase();

const _suggestions = <String>[
  'What have I been reading about lately?',
  'Notes on habit formation',
  'Ideas about systems thinking',
  'Quotes about writing well',
];

// ── The sheet ───────────────────────────────────────────────────────────────

/// *Filters* (kit §29): Kind; then — only while generative AI is on — Read as
/// over its note, and Breadth only while Cohesive.
class _FiltersSheet extends StatelessWidget {
  final String filter;
  final ValueChanged<String> onFilter;
  final bool aiOn;
  final bool cohesive;
  final ValueChanged<String> onMode;
  final String breadth;
  final ValueChanged<String> onBreadth;

  const _FiltersSheet({
    required this.filter,
    required this.onFilter,
    required this.aiOn,
    required this.cohesive,
    required this.onMode,
    required this.breadth,
    required this.onBreadth,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitFacet(
          label: 'Kind',
          value: filter,
          onChanged: onFilter,
          items: [
            for (final e in _filters.entries) KitFacetItem(e.key, e.value),
          ],
        ),
        // Read as and its Breadth are absent while generative AI is off
        // (5.29.0, ADR-186): the mode is passages, whatever was last picked.
        if (aiOn) ...[
          const KitDLabel('Read as'),
          Align(
            alignment: Alignment.centerLeft,
            child: KitSlideSwitch<String>(
              key: const ValueKey('search-mode'),
              label: 'Result mode',
              value: cohesive ? 'cohesive' : 'passages',
              onChanged: onMode,
              options: const [
                KitSlideOption('passages', 'Passages'),
                KitSlideOption('cohesive', 'Cohesive'),
              ],
            ),
          ),
          KitDNote(cohesive
              ? 'The passages arranged into sections, each one verbatim.'
              : 'Each passage on its own, the closest first.'),
          if (cohesive) ...[
            const KitDLabel('Breadth'),
            Align(
              alignment: Alignment.centerLeft,
              child: KitSlideSwitch<String>(
                key: const ValueKey('search-breadth'),
                label: 'Breadth',
                value: breadth,
                onChanged: onBreadth,
                options: [
                  for (final b in _breadths) KitSlideOption(b.$1, b.$2),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}

/// *Scripture* — a citation is a different question, so the sheet shows none
/// of the filters: only what it is, and how to leave it.
class _ScriptureSheet extends StatelessWidget {
  final VoidCallback onLeave;
  const _ScriptureSheet({required this.onLeave});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const KitDLabel('Scripture', first: true),
        const KitDNote(
            'A citation is read verse by verse, beside the passages on your '
            'shelves that answer it.'),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: KitHxLink('Search everything instead', onTap: onLeave),
        ),
      ],
    );
  }
}

// ── No query ────────────────────────────────────────────────────────────────

/// What the column holds before a search: a small SectionHead (§31) *Try
/// searching for*, then the suggestions as italic serif prompts, each led by
/// an accent arrow; one runs that search (web `.dp-try .hx-prompts`).
class _TrySearching extends StatelessWidget {
  final ValueChanged<String> onPick;
  const _TrySearching({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const KitSectionHead('Try searching for', small: true),
        for (final s in _suggestions)
          Align(
            alignment: Alignment.centerLeft,
            child: _Prompt(s, onTap: () => onPick(s)),
          ),
      ],
    );
  }
}

/// `.hx-prompt` — `6px 2px`, the arrow (sans 13 `--accent-text`) 9 before
/// the italic serif 17/24 in `--fg-muted`, `--fg` under a fine pointer; a 2px
/// accent focus ring.
class _Prompt extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _Prompt(this.text, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return KitDTap(
      label: text,
      onTap: onTap,
      builder: (context, hover, focus) => Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        decoration: BoxDecoration(
          borderRadius: AppRadius.smR,
          border: focus ? Border.all(color: t.accent, width: 2) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            ExcludeSemantics(
              child: Text('→', style: KitText.ui(context, color: t.accentText)),
            ),
            const SizedBox(width: 9),
            Flexible(
              child: Text(
                text,
                style: KitText.lede(context,
                    fontSize: 17,
                    height: 24,
                    color: hover ? t.fg : t.fgMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
