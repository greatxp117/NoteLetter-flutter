/// "See all" — the live day view behind a readings letter (ADR-029 §5).
///
/// Deliberately **not** a frozen snapshot of what was sent. The answer to
/// "what does my library say about today's readings" changes as the library
/// grows, and freezing it would show a reader fewer passages than they now
/// have — the wrong error. The letter's stored `passages_found` is what makes
/// "5 of 23" honest *as sent*; this page runs the search again and says so
/// when the two differ.
///
/// **A reading that could not be searched answered nothing; it did not answer
/// zero.** The reference shipped this screen with one rejection mapped to
/// `{results: [], error}` and a `failed` flag that was true only when EVERY
/// reading failed — so one failed row drew §7's "Nothing on your shelves
/// answers this reading yet", which is an assertion about the library made
/// from a request that never completed, and its zero went into the live tally,
/// so the banner read the library as having SHRUNK. Both halves are fixed
/// here from the start: the row draws §14.1 where the offer would be, and the
/// tally counts only the readings that answered.
///
/// **§14.1, not §14.2**, and the reference learned this from a screenshot: its
/// first shape put the line inline, and the server's own 500 sentence is
/// "…Contact support with your request ID" — which §14.2 renders no id for.
/// §14 picks the form by WHO ACTS NEXT, and nothing here was refused beside a
/// control: the page searches on open and one reading's RESULTS REGION could
/// not load.
library;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../models/newsletter.dart';
import '../../models/search_result.dart';
import '../../services/api.dart';
import '../../services/api_service.dart';
import '../../shared/dates.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit/kit.dart';

/// One reading's live answer. Injected so a widget test can refuse one reading
/// without a network — the screen's whole subject is the difference between a
/// row that answered zero and a row that did not answer.
typedef ReadingSearch = Future<List<SearchResult>> Function(String ref);

Future<List<SearchResult>> _search(String ref) async {
  final data = await Api.instance.searchNotes(ref, limit: 50);
  return (data['results'] as List? ?? [])
      .whereType<Map<String, dynamic>>()
      .map(SearchResult.fromJson)
      .toList();
}

/// What one reading came back with. `error` and `busy` are the two shapes of
/// "has not answered" — neither is a zero.
class _Row {
  final List<SearchResult> results;
  final ApiException? error;
  final bool busy;
  const _Row({this.results = const [], this.error, this.busy = false});

  bool get answered => error == null && !busy;
}

class ScriptureDayView extends StatefulWidget {
  final Newsletter letter;
  final VoidCallback onBack;
  final VoidCallback onLibrary;

  /// Test seam; the default is the real endpoint.
  final ReadingSearch search;

  const ScriptureDayView({
    super.key,
    required this.letter,
    required this.onBack,
    required this.onLibrary,
    this.search = _search,
  });

  @override
  State<ScriptureDayView> createState() => _ScriptureDayViewState();
}

class _ScriptureDayViewState extends State<ScriptureDayView> {
  /// Null while the first pass is in flight; one entry per reading, keyed by
  /// index so a repeated citation still gets its own row.
  List<_Row>? _live;

  List<LetterReading> get _readings => widget.letter.readings;

  @override
  void initState() {
    super.initState();
    _runAll();
  }

  Future<void> _runAll() async {
    setState(() => _live = null);
    final rows = await Future.wait(_readings.map(_one));
    if (!mounted) return;
    setState(() => _live = rows);
  }

  Future<_Row> _one(LetterReading r) async {
    if (r.ref.isEmpty) return const _Row();
    try {
      return _Row(results: await widget.search(r.ref));
    } on ApiException catch (e) {
      // The exception itself, not a string: §14.1 renders the server's own
      // sentence AND its `request_id`, and a catch that flattens the rejection
      // to 'Search failed' throws both away.
      return _Row(error: e);
    }
  }

  /// §14.1's one action. The region that could not load is ONE reading's
  /// results, and the only other remedy is leaving the screen and re-running
  /// the searches that worked.
  Future<void> _retry(int i) async {
    setState(() => _live = [
          for (var j = 0; j < _live!.length; j++)
            if (j == i) const _Row(busy: true) else _live![j],
        ]);
    final row = await _one(_readings[i]);
    if (!mounted) return;
    setState(() => _live = [
          for (var j = 0; j < _live!.length; j++)
            if (j == i) row else _live![j],
        ]);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.letter;
    final live = _live;
    final errCount = live?.where((x) => x.error != null).length ?? 0;
    final busyCount = live?.where((x) => x.busy).length ?? 0;
    // A retry in flight is the same absence as a rejection: the row has not
    // answered, so it is not a zero either.
    final unanswered = errCount + busyCount;
    final failed = live != null && live.isNotEmpty && errCount == live.length;
    final partial = live != null && unanswered > 0 && !failed;
    final liveTotal =
        live?.fold<int>(0, (s, x) => s + (x.answered ? x.results.length : 0));
    final sentTotal = n.passagesFound ?? 0;
    // Only a COMPLETE search is comparable to the count the letter stored.
    final drift =
        liveTotal != null && unanswered == 0 && liveTotal != sentTotal;

    final sentIds = <String>{
      for (final r in n.readings)
        for (final p in r.passages) p.chunkId,
    }..remove('');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitUtilityBar(
          leading: KitButton('Back to the letter',
              icon: Icons.chevron_left,
              variant: KitButtonVariant.ghost,
              onPressed: widget.onBack),
          // The reference's crumb is `§ Letters · Readings · <date>`. At phone
          // width the bar carries a back control AND an action, and the kit
          // ellipsises what is left — the first frame read `§ LET…`, which
          // says nothing. Shortened to the SIBLING's spelling
          // (`LetterReaderView`, one screen up the same path): the back
          // control already names where it returns to, and the folio under
          // the bar carries the full line.
          crumb: 'Readings · ${longDate(n.generatedAt)}',
          actions: [
            KitButton('Library',
                icon: Icons.menu_book_outlined,
                variant: KitButtonVariant.ghost,
                onPressed: widget.onLibrary),
          ],
        ),
        Expanded(
          child: KitScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s6, vertical: AppSpacing.s6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ChapterOpening(
                    folio: 'Readings · ${longDate(n.generatedAt)}',
                    title: n.liturgicalDay?.title ?? 'Today',
                    standfirst: 'Everything on your shelves that answers this '
                        'day, searched now.',
                    footnote: (n.liturgicalDay?.cycleLine ?? '').isEmpty
                        ? null
                        : n.liturgicalDay!.cycleLine,
                  ),
                  _LiveBanner(
                    loading: live == null,
                    failed: failed,
                    partial: partial,
                    busy: busyCount > 0,
                    unanswered: unanswered,
                    liveTotal: liveTotal,
                    sentTotal: sentTotal,
                    drift: drift,
                  ),
                  // The letter matched against the verse TEXT and this page
                  // matches on the CITATION, so saying so is what keeps the
                  // count above from reading as a straight before/after. Only
                  // `none` makes the two comparable.
                  if (n.verseSource != null &&
                      n.verseSource != 'none' &&
                      live != null &&
                      !failed)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.s3),
                      child: Text(
                        'Your letter matched against the verse text '
                        '${n.verseSource == 'user' ? 'from the bible on your shelves' : 'of ${n.verseEdition ?? 'a public-domain edition'}'}'
                        '; this page searches by the citation, so the two '
                        'counts are not measured the same way.',
                        style: KitText.meta(context),
                      ),
                    ),
                  for (var i = 0; i < _readings.length; i++)
                    _ReadingSection(
                      reading: _readings[i],
                      row: live == null ? null : live[i],
                      sentIds: sentIds,
                      onRetry: () => _retry(i),
                      onLibrary: widget.onLibrary,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The "Live" statement. Four branches, and the one that did not exist on the
/// reference until B7 is [partial]: a count taken over some of the readings is
/// not comparable to the one the letter stored, so it makes no drift claim.
class _LiveBanner extends StatelessWidget {
  final bool loading;
  final bool failed;
  final bool partial;
  final bool busy;
  final int unanswered;
  final int? liveTotal;
  final int sentTotal;
  final bool drift;

  const _LiveBanner({
    required this.loading,
    required this.failed,
    required this.partial,
    required this.busy,
    required this.unanswered,
    required this.liveTotal,
    required this.sentTotal,
    required this.drift,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final marked = drift || partial;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: AppSpacing.s6, bottom: AppSpacing.s2),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: marked ? t.accentChipBg : t.surfaceSunken,
        borderRadius: AppRadius.mdR,
        border: Border.all(color: marked ? t.accentChipBorder : t.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 1, right: AppSpacing.s3),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: AppRadius.xsR,
              border: Border.all(
                  color: marked ? t.accentChipBorder : t.borderStrong),
            ),
            child: Text('LIVE',
                style: KitText.capsLabel(context,
                    color: marked ? t.accentChipFg : t.fgSubtle)),
          ),
          Expanded(child: Text(_sentence(), style: KitText.body(context))),
        ],
      ),
    );
  }

  String _sentence() {
    if (loading) return 'Searching your library for this day’s readings…';
    if (failed) {
      return 'Your library could not be searched just now. The letter counted '
          '$sentTotal passages for this day when it was sent.';
    }
    if (partial) {
      final subject = unanswered == 1 ? 'One reading' : '$unanswered readings';
      final verb = busy
          ? (unanswered == 1 ? 'has not answered yet' : 'have not answered yet')
          : 'could not be searched just now';
      return '$subject $verb, so this count is incomplete: the readings that '
          'did answer give $liveTotal. Your letter counted $sentTotal for the '
          'whole day when it was sent.';
    }
    if (drift) {
      return 'Your letter counted $sentTotal passages for this day when it was '
          'sent. Your library now answers with $liveTotal.';
    }
    return '$liveTotal passages — the same number your letter counted when it '
        'was sent.';
  }
}

class _ReadingSection extends StatelessWidget {
  final LetterReading reading;

  /// Null while the first pass is in flight.
  final _Row? row;
  final Set<String> sentIds;
  final VoidCallback onRetry;
  final VoidCallback onLibrary;

  const _ReadingSection({
    required this.reading,
    required this.row,
    required this.sentIds,
    required this.onRetry,
    required this.onLibrary,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final r = reading;
    final err = row?.error;
    final results = row?.answered == true ? row!.results : const <SearchResult>[];

    return Container(
      padding: const EdgeInsets.only(top: 26, bottom: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.rule)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(r.label.toUpperCase(), style: KitText.capsLabel(context)),
              const SizedBox(width: AppSpacing.s3),
              Expanded(child: Text(r.ref, style: KitText.h3(context))),
              const SizedBox(width: AppSpacing.s3),
              // A row that has not answered has no count. `0 passages` would
              // be a measurement of a request that never completed.
              Text(_count().toUpperCase(), style: KitText.capsLabel(context)),
            ],
          ),
          if (!r.parsed)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                  'This citation could not be read, so nothing was matched '
                  'against it.',
                  style: KitText.meta(context)),
            ),
          if (err != null)
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: AppSpacing.s2),
              child: KitFailureBlock(
                sentence: 'This reading could not be searched.',
                detail: err.message,
                requestId: err.requestId,
                onRetry: onRetry,
              ),
            )
          else if (row?.busy == true)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text('Searching again…', style: KitText.meta(context)),
            )
          else if (results.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final p in results)
                    _DayPassage(result: p, inLetter: sentIds.contains(p.chunk.chunkId)),
                ],
              ),
            )
          else if (row != null && r.parsed)
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: AppSpacing.s1),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                        'Nothing on your shelves answers this reading yet.',
                        style: KitText.meta(context)),
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  KitButton('Add a source',
                      variant: KitButtonVariant.ghost, onPressed: onLibrary),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _count() {
    if (row == null || row!.busy) return '…';
    if (row!.error != null) return '—';
    final n = row!.results.length;
    return '$n ${n == 1 ? 'passage' : 'passages'}';
  }
}

/// A near-relative of the kit's passage card (§5.2), for the same reason
/// `SearchResultCard` is one: §5.2's meta row is a mono page-ref, and a live
/// search answer is identified by **which source it came from and how well it
/// matched**. It is not that card either — this screen shows the passage
/// WHOLE (the letter's own "see all" promise) and carries the one thing no
/// other surface does: whether this passage is the one the letter sent.
/// `.sc-p` (app-scripture.css) — a QUOTED passage, not a source row: a
/// --surface card on --shadow-1 with no border, 14/16 padding; its head a
/// content-sized plate, the title in SANS 13/600 and the measured score in
/// mono 10.5 at --fg-subtle pushed right; the text serif 15/25 at --fg-lede.
class _DayPassage extends StatelessWidget {
  final SearchResult result;
  final bool inLetter;

  const _DayPassage({required this.result, required this.inLetter});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final r = result;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.mdR,
        boxShadow: AppShadows.s1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              KitFileBadge(kitDocKind(r.document.type),
                  size: KitBadgeSize.chip),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  r.document.title.isEmpty ? 'Untitled' : r.document.title,
                  style: KitText.ui(context, weight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              // Measured: the backend's own blended rank.
              Text(r.score.toStringAsFixed(2),
                  style: KitText.capsLabel(context,
                      fontSize: 10.5, letterSpacing: 0.04, color: t.fgSubtle)),
              if (inLetter) ...[
                const SizedBox(width: 10),
                const KitTag('In the letter', variant: KitTagVariant.accent),
              ],
            ],
          ),
          const SizedBox(height: 8),
          KitMarkedText(r.chunk.text,
              style: KitText.lede(context, fontSize: 15, height: 25)
                  .copyWith(fontStyle: FontStyle.normal)),
        ],
      ),
    );
  }
}
