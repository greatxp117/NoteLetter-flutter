import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../shared/reader_origin.dart';
import '../shared/source_host.dart';
import '../models/chunk.dart';
import '../models/document.dart';
import '../models/tag.dart';
import '../services/firestore_service.dart';
import '../shared/extraction_markers.dart';
import '../state/documents_notifier.dart';
import '../state/tags_notifier.dart';
import 'reader/content_form_action.dart';
import 'reader/delete_source.dart';
import 'reader/history_panel.dart';
import 'reader/listen_panel.dart';
import 'reader/manuscript_panel.dart';
import 'reader/original_panel.dart';
import 'reader/reader_prefs.dart';
import 'reader/reader_ui.dart';
import 'reader/reading_cost.dart';
import 'reader/reprocess_action.dart';
import 'reader/source_freshness.dart';
import 'reader/source_priority.dart';
import 'reader/speed_read_panel.dart';
import 'reader/summary_panel.dart';
import 'settings/summaries_section.dart';
import 'tags/shelf_sheet.dart';
import '../services/api.dart';
import '../services/api_service.dart';
import '../widgets/app_layout.dart';
import '../widgets/app_toast.dart';
import '../widgets/kit/kit.dart';
import '../widgets/sidebar.dart' show shellAiOn;
import '../services/analytics.dart';
import '../services/error_text.dart';

/// The source page (the Reader) — one-shot doc + chunks (`chunk_index` asc),
/// fires `logReadEvent` on open (INV-03). See `screens/reader.md`.
///
/// **One document on one scroll** (4.64.0, ADR-100). Summary · Manuscript ·
/// Speed read · Listen · Original · History are all present and reached by
/// scrolling, in that order — which is normative, because the Contents'
/// positions mean nothing across clients otherwise. They were six TABS until
/// 4.64.0, and the manuscript — which `?p=` and `[data-shared]` scroll into —
/// was not mounted on a cold open, so neither jump had ever fired from a link.
///
/// **Direction D** (`screens/reader.md` §Composition; web `ReaderHybrid` +
/// `SecD` in `pages/ReaderView.jsx`): the D frame ([KitDPage]) — the masthead
/// (a crumb whose back control names the screen the Reader was opened FROM,
/// §The way back, then the folio; the title; the byline and the freshness
/// notice in the standfirst's place), the one toolbar (*Add to letter*, short
/// *To letter*; the gear is *Source details*), the sheet *In this volume*
/// (the identity block, Contents, the catalogue card, Finish, Also) — on a
/// phone the running head, with its reading-progress rule — and the six
/// sections in the column, each under its §31 head, mounting on approach.
/// Until D this was a Reading frame under a §2.1 chapter opening with the
/// actions, shelves, priority and stat rows above a sticky §19 rail.
///
/// It is routed OUTSIDE the rail-and-pane shell (its unsaved-edit guard hangs
/// on its own route) and wraps itself in [AppLayout], so it stands inside the
/// shell's chrome at every width, as web's does; INV-22's footer is composed
/// by `SupportShell` above both and ends the primary scroll.
class ReaderPage extends StatefulWidget {
  final String docId;

  /// `?p={chunkId}` — the passage the link pointed at (INV-21). The manuscript
  /// is mounted on open (ADR-100), so this scrolls the one scroll to it.
  final String? passageId;

  /// `?from={path}` — the screen this Reader was opened from (ADR-101). Null
  /// on a cold open: a newsletter link, a notification, a shared URL.
  final String? from;

  const ReaderPage({super.key, required this.docId, this.passageId, this.from});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

/// The six sections, in the order `screens/reader.md` §Continuous scroll makes
/// normative, with the label each one's §31 head and Contents row read.
const List<(String, String)> readerSections = [
  ('summary', 'Summary'),
  ('manuscript', 'Manuscript'),
  ('speedread', 'Speed read'),
  ('listen', 'Listen'),
  ('original', 'Original'),
  ('history', 'History'),
];

/// Rendered on open, never deferred: the summary because it is the top of the
/// page, and the manuscript because `?p=` (ADR-051) and `[data-shared]`
/// (ADR-095) scroll to elements inside it. The four below mount on approach.
const List<String> _eager = ['summary', 'manuscript'];

/// The sheet's Contents: one row per section this source HAS (kit §29) — the
/// Summary is absent while generative AI is off (5.29.0, ADR-186, INV-34),
/// and the Manuscript is then § I. *Original* carries the document's kind as
/// its count (`PDF`, `NOTE` — §6.4.1's word, never the raw `type`: an image
/// set's row read "IMAGE_SET" once, web 938a2f4). The section list and this
/// one are the same list, read once: a section Contents never names is a
/// section that disappears with no error (the `KIND_ORDER` shape).
@visibleForTesting
List<KitContentsItem> readerContentsItems(Document doc, {bool aiOn = true}) => [
  for (final (id, label) in readerSections)
    if (aiOn || id != 'summary')
      KitContentsItem(
        id,
        label,
        count: id == 'original' ? kitKindLabel(doc.type) : null,
      ),
];

/// The masthead's folio: `{shelf} · {kind} · Added {Mon D, YYYY}` — the first
/// of the shelves the document is on (*Unshelved* without), the kind as §33's
/// word for its type (*Document*, *Web clip*, *Video*…), the added date.
@visibleForTesting
String readerFolio(Document doc, Tag? shelf) => [
  shelf?.title ?? 'Unshelved',
  kitTypeLabel(doc.type),
  if (doc.createdAt != null) 'Added ${readerDate(doc.createdAt!)}',
].join(' · ');

/// `Jul 1, 2026` (web `toLocaleDateString('en-US', {month: 'short', day:
/// 'numeric', year: 'numeric'})`).
String readerDate(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}

/// The document's first shelf among those the library holds (web `shelfOf`).
Tag? _shelfOf(Document doc, List<Tag> shelves) {
  for (final t in shelves) {
    if (doc.tagIds.contains(t.id)) return t;
  }
  return null;
}

/// One Listen line: what is spoken, and when it starts (null → the panel falls
/// back to word-count-proportional timing).
class _ListenLine {
  final String text;
  final double? start;
  const _ListenLine(this.text, this.start);
}

class _ReaderPageState extends State<ReaderPage> {
  /// Where a recipe step's time chip asked Listen to start (§Step jump).
  double? _listenSeek;

  bool _finishBusy = false;
  String? _finishError;

  /// §Document shelves: one write at a time, and its refusal beside the row.
  bool _shelvesBusy = false;
  String? _shelvesError;
  bool _loading = true;
  String? _error;
  String? _errorRequestId;
  bool _notFound = false;

  /// The detailed reading breakdown is **opt-in and off by default** (4.1.0):
  /// the reader is a reading surface, and instrumentation shown to someone who
  /// did not ask for it is noise on the one screen that should be quiet. The
  /// toggle is the manuscript's Aa → Reading stats (F-74), stored with the
  /// typography — a client-local display preference, never contract state.
  bool get _showStats => ReaderPrefs.current.value.stats;
  Document? _document;
  List<Chunk> _chunks = const [];

  /// The page's primary scroller: the sections follow it, and the running
  /// head's reading-progress rule is its fraction.
  final ScrollController _scroll = ScrollController();

  /// Which section the reader is in (REPORTED from the scroll, never set by a
  /// tap), which have mounted, and the way to one (kit §29, web
  /// `useSectionRail`). Rebuilt when the section list changes (AI on/off).
  KitSections? _sections;
  bool? _sectionsAiOn;

  KitSections _sectionsFor(bool aiOn) {
    final have = _sections;
    if (have != null && _sectionsAiOn == aiOn) return have;
    have?.dispose();
    _sectionsAiOn = aiOn;
    return _sections = KitSections([
      for (final (id, _) in readerSections)
        if (aiOn || id != 'summary') id,
    ], eager: _eager);
  }

  @override
  void initState() {
    super.initState();
    _load();
    ReaderPrefs.current.addListener(_onReaderPrefs);
    ReaderPrefs.ensureLoaded();
  }

  @override
  void dispose() {
    ReaderPrefs.current.removeListener(_onReaderPrefs);
    _sections?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onReaderPrefs() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _errorRequestId = null;
      _notFound = false;
    });
    try {
      final result = await FirestoreService.instance.getReaderDocument(
        widget.docId,
      );
      if (!mounted) return;
      if (result == null) {
        // 404 / foreign document — never leak existence (reader.md §States).
        setState(() {
          _notFound = true;
          _loading = false;
        });
        return;
      }
      setState(() {
        _document = result.$1;
        _chunks = result.$2;
        _loading = false;
      });
      // WHAT was opened, in the §6.4.1 kind vocabulary — never which document.
      // Here rather than in `_reload`, for the same reason `_load` is the only
      // path that logs `doc_opened`: a content edit rewriting the chunks under
      // the reader is not a second opening.
      final kind = kitDocKind(result.$1.type);
      Analytics.track('reader_opened', {'kind': kind});
      // The document above is the PRE-INCREMENT snapshot: `doc_opened` is
      // logged after it is read. Fold in what the write actually committed,
      // once it confirms — never optimistically before (ADR-022). A null
      // resolution means the log failed and the stored values stand.
      final logged = await result.$3;
      if (!mounted || logged == null || _document == null) return;
      setState(
        () => _document = _document!.withReadLogged(
          viewCount: logged.viewCount,
          lastViewedAt: logged.lastViewedAt,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _errorRequestId = e.requestId;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeSdkError(e);
        _loading = false;
      });
    }
  }

  // Reload without re-firing the doc_opened read event (used after content
  // edits / reorganization rewrites chunks under the reader).
  Future<void> _reload() async {
    final result = await FirestoreService.instance.getReaderDocumentQuietly(
      widget.docId,
    );
    if (!mounted || result == null) return;
    setState(() {
      _document = result.$1;
      _chunks = result.$2;
    });
  }

  /// Fold a CONFIRMED batch of `chunk_read` writes into the chunks already in
  /// memory, so *Passages read* and the 4.1.0 breakdown move as you read. The
  /// reader holds chunks as a one-shot read (INV-02), so nothing else would
  /// notice — and a figure that only changes on reload reads as broken. Only
  /// ids the write confirmed arrive here, and each moves a chunk 0 → 1 once.
  void _foldInChunksRead(List<String> ids) {
    if (!mounted || ids.isEmpty) return;
    final set = ids.toSet();
    setState(() {
      _chunks = [
        for (final c in _chunks)
          set.contains(c.chunkId) ? c.withChunkRead() : c,
      ];
    });
  }

  /// What a reader that SPEAKS says. A marker's channel name and body, never
  /// its brackets — `"On screen: you."`, not `"bracket on screen colon you
  /// bracket"` (4.52.0, ADR-089 §17).
  List<String> get _paras =>
      _chunks.map((c) => markersForSpeech(c.text)).toList();

  /// Listen lines (4.11.0, ADR-047; reader.md §Listen follow-along).
  ///
  /// A transcript chunk keeps ONE `<p data-start>` per sentence, so it
  /// contributes one line per timed paragraph. A chunk with ≤1 of them — every
  /// transcript indexed before 4.11.0, which is never backfilled, and every
  /// non-transcript document — contributes a single line for the whole chunk.
  /// Decided PER CHUNK on what the html actually holds, never per document and
  /// never on the contract version: one library holds both shapes permanently.
  ///
  /// A chunk carrying OTHER blocks (a mixed carousel's photo figures between
  /// `<hr>`-joined slides, ADR-019 §Amendment) stays whole — splitting it to
  /// its timed paragraphs would drop the photo slides out of the transcript
  /// list entirely. A keyframe `<figure>` (4.82.0, ADR-116) is the exception:
  /// it follows its sentence and has no words of its own, so a reel with one
  /// keeps its per-sentence lines. Mirrors the web ReaderView's `listenLines`.
  List<_ListenLine> get _listenLines {
    final out = <_ListenLine>[];
    for (final c in _chunks) {
      final body = html_parser.parseFragment(c.html ?? '');
      final blocks = body.children;
      final timed = blocks
          .where(
            (el) => el.localName == 'p' && el.attributes['data-start'] != null,
          )
          .toList();
      final allParagraphs =
          blocks.isNotEmpty &&
          blocks.every((el) => el.localName == 'p' || el.localName == 'figure');
      if (timed.length > 1 && allParagraphs) {
        for (final p in timed) {
          out.add(
            _ListenLine(
              markersForSpeech(p.text),
              double.tryParse(p.attributes['data-start'] ?? ''),
            ),
          );
        }
      } else {
        out.add(
          _ListenLine(
            markersForSpeech(c.text),
            timed.isNotEmpty
                ? double.tryParse(timed.first.attributes['data-start'] ?? '')
                : null,
          ),
        );
      }
    }
    return out;
  }

  List<String> get _listenParas => _listenLines.map((l) => l.text).toList();
  List<double?> get _lineStarts => _listenLines.map((l) => l.start).toList();

  /// The page's ONE action (kit §27): *Add to letter*, the tab bar's *To
  /// letter* — it goes to Letter settings. Held while the source is read.
  KitPageAction _toLetter({bool disabled = false}) => KitPageAction(
    label: 'Add to letter',
    short: 'To letter',
    icon: Icons.mail_outlined,
    disabled: disabled,
    onPressed: disabled ? () {} : () => context.go('/letters/settings'),
  );

  @override
  Widget build(BuildContext context) => AppLayout(child: _page(context));

  Widget _page(BuildContext context) {
    final doc = _document;
    if (_notFound || (_error != null && doc == null)) return _notReadable();
    if (_loading || doc == null) return _readerLoading();
    return _readerPage(doc);
  }

  /// §The way back's control, as the crumb's §39 back control: it NAMES the
  /// screen the Reader was opened from and returns there (ADR-101); a cold
  /// open, and any `?from=` this app does not recognise, say `Library` and go
  /// to Sources. Every state draws it — loaded, loading and NOT FOUND —
  /// because the failure state is the one a reader most needs a way out of.
  KitDBackControl _backControl() {
    final origin = readerOrigin(
      widget.from,
      tags: context.watch<TagsNotifier>().tags,
    );
    return KitDBackControl(origin.label, onTap: _goBack);
  }

  /// While the source is read, D already stands (reader.md §Composition,
  /// Loading): the masthead's crumb, folio and title, the sheet's identity
  /// block and its cover are drawn from the row the documents listing already
  /// holds — so a tapped cover has somewhere to land — and everything that
  /// waits on the document's own read is skeleton lines. With no row (a cold
  /// open from a letter link before the listing answers) the title and the
  /// identity block are skeleton lines too: nothing unread is drawn.
  Widget _readerLoading() {
    final shelves = context.watch<TagsNotifier>().tags;
    Document? row;
    for (final d in context.watch<DocumentsNotifier>().documents) {
      if (d.id == widget.docId) {
        row = d;
        break;
      }
    }
    final shelf = row == null ? null : _shelfOf(row, shelves);
    final author = row?.author?.trim();
    return KitDPage(
      key: const ValueKey('rx-loading'),
      back: _backControl(),
      crumbStacks: true,
      gridTop: 40,
      folio: row == null
          ? ''
          : [shelf?.title ?? 'Unshelved', kitTypeLabel(row.type)].join(' · '),
      title: row == null ? '' : (row.title.isEmpty ? 'Untitled' : row.title),
      titleWidget: row == null
          ? const KitSkeletonLines(lines: [KitSkelLine(0.6, true)], top: 0)
          : null,
      byline: author != null && author.isNotEmpty
          ? KitReaderByline(author: author)
          : const KitSkeletonLines(lines: [KitSkelLine(0.3)], top: 14),
      action: _toLetter(disabled: true),
      // Held, not absent: the gear is where Source details will be. It opens
      // nothing until the source is read.
      settings: KitPageSettings(
        label: 'Source details',
        held: true,
        body: (context, close) => const SizedBox.shrink(),
      ),
      controller: _scroll,
      sheet: KitDSheet(
        label: 'In this volume',
        peek: const KitPeekWait('In this volume'),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (row != null) KitReaderIdentity(doc: row, shelf: shelf),
            const KitSkeletonLines(
              lines: [
                KitSkelLine(0.4), KitSkelLine(), KitSkelLine(), //
                KitSkelLine(0.6), KitSkelLine(), KitSkelLine(),
                KitSkelLine(0.5),
              ],
              top: 20,
            ),
          ],
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
  }

  /// A 404 is the only one of these the heading was ever telling the truth
  /// about: it is the D page titled *Source not found* with the read's own
  /// sentence as its standfirst. Every other refusal is the D page titled
  /// *Source* with §14.1 in the column (component-kit §14, ADR-070). Both keep
  /// the crumb, and neither leaks a foreign document's existence.
  Widget _notReadable() {
    final missing = _notFound;
    return KitDPage(
      key: const ValueKey('rx-failed'),
      back: _backControl(),
      crumbStacks: true,
      gridTop: 40,
      folio: '',
      title: missing ? 'Source not found' : 'Source',
      // web api.js `getDocument`'s 404 sentence.
      stand: missing ? 'Document not found' : null,
      controller: _scroll,
      child: missing
          ? const SizedBox.shrink()
          : KitFailureBlock(
              sentence: 'This source could not be loaded.',
              detail: _error!,
              requestId: _errorRequestId,
              onRetry: _load,
            ),
    );
  }

  Widget _readerPage(Document doc) {
    final shelves = context.watch<TagsNotifier>().tags;
    final shelf = _shelfOf(doc, shelves);
    final aiOn = shellAiOn(context);
    final sections = _sectionsFor(aiOn);
    final items = readerContentsItems(doc, aiOn: aiOn);
    final complete = doc.status == DocumentStatus.complete;
    final total = _chunks.length;
    final readCount = _chunks.where((c) => c.viewCount > 0).length;

    // Byline & reading cost (2.13.0, ADR-020 — §Header): what the document IS
    // before what the system did to it. Every part optional.
    final author = doc.author?.trim();
    final host = sourceHost(doc.sourceUrl);
    final byline = KitReaderByline(
      // Rendered AS STORED — never reformatted, re-cased or split.
      author: author == null || author.isEmpty ? null : doc.author,
      // publish_date is an ISO `YYYY-MM-DD` STRING: a calendar date with NO
      // timezone conversion, and never `created_at` in its place.
      published: _fmtPublishDate(doc.publishDate),
      host: host,
      onSource: doc.sourceUrl == null
          ? null
          : () => launchUrlString(
              doc.sourceUrl!,
              mode: LaunchMode.externalApplication,
            ),
      // max(1, ceil(word_count / 220)) from the STORED count; omitted for a
      // document with its own audio (ADR-143) and where none is stored.
      readingTime: readingTimeLabel(doc),
    );

    // Filing (§Document shelves, §Source priority) and the summary style live
    // in Source details, the page's settings panel (kit §28).
    final filing = complete;
    final details = (filing || aiOn)
        ? KitPageSettings(
            label: 'Source details',
            has: aiOn ? const ['summaries'] : const [],
            body: (context, close) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The panel's first label stands 18 under its head's rule
                // (web `.d-pnl-h + .d-l`); a group after a reused Settings
                // section, 28 (`.d-pnl .set-section + .d-l`).
                if (filing) ...[
                  const KitDLabel('Filing', top: 18),
                  _documentShelves(shelves),
                  const SizedBox(height: 14),
                  SourcePriorityRow(
                    docId: widget.docId,
                    doc: _document ?? doc,
                    onSaved: (v) => setState(
                      () => _document = _document?.withSourcePriority(v),
                    ),
                  ),
                ],
                // Settings' own section, not a copy: one writer of the style.
                // Absent while generative AI is off (5.29).
                if (aiOn) ...[
                  KitDLabel('Summary style', top: filing ? 28 : 18),
                  const SummariesSection(),
                ],
              ],
            ),
          )
        : null;

    // Also: the quieter actions, destructive last (kit §29). Each carries its
    // own §18 confirm where it re-derives or deletes. Only what this source
    // can do is listed, so the label never stands over nothing.
    final canReorganize = complete && total >= 2;
    final also = <Widget>[
      if (aiOn)
        // web `IcoChat` — the speech bubble Support draws.
        KitAlsoButton(
          'Ask about this',
          icon: Icons.chat_bubble_outline,
          onTap: () => context.go('/ask'),
        ),
      // 4.103.0 (ADR-136): the analysis runs in the background and its plan
      // waits in For your review, where the sheet opens over it.
      if (canReorganize)
        KitAlsoButton(
          _reorganizing ? 'Asking…' : 'Reorganize',
          icon: Icons.title,
          onTap: _reorganizing ? null : () => _requestReorganize(doc),
        ),
      // reader.md §Supersession confirm (4.6.0, ADR-042).
      if (ContentFormAction.offeredFor(doc))
        ContentFormAction(
          docId: widget.docId,
          doc: doc,
          chunks: _chunks,
          onQueued: () => _reload(),
        ),
      // reader.md §Re-process (5.27.0, ADR-183): after the content-form
      // action, before Delete.
      if (ReprocessAction.offeredFor(doc))
        ReprocessAction(
          docId: widget.docId,
          doc: doc,
          chunks: _chunks,
          onQueued: () => _reload(),
        ),
      // reader.md §Deleting a source (4.105.0, ADR-138).
      if (DeleteSourceAction.offeredFor(doc))
        DeleteSourceAction(
          docId: widget.docId,
          doc: doc,
          passages: total,
          shelves: shelves,
          onDeleted: _goBack,
        ),
    ];

    final finished = doc.finishedAt != null;
    void jump(String id) {
      // Which section the reader actually reads in: a jump is a use of a
      // mode; the scroll that reaches the same section is not, and neither is
      // a tap on the section already current.
      if (id != sections.current) {
        Analytics.track('reader_mode_used', {'mode': id});
      }
      sections.jump(id);
    }

    final sheetBody = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitReaderIdentity(doc: doc, shelf: shelf),
        const KitReaderSheetLabel('In this volume'),
        KitContents(
          items: items,
          sections: sections,
          label: 'Sections of this source',
          onJump: jump,
        ),
        // The catalogue card: every figure comes from the document this
        // screen already loaded. Two may be the dash: Words where the indexer
        // stored no count, Listen where a document with its own audio has no
        // stored length; a document WITHOUT its own audio draws no Listen row
        // (ADR-143). Coverage is rendered here and only here: every chunk is
        // in memory, so it costs no extra read, and its meter is that one
        // count over the total — never a share of the overlapping ways.
        KitFigures.ledger(
          label: 'The catalogue card',
          ledger: [
            KitFigureRow('Passages', '$total'),
            KitFigureRow(
              'Words',
              doc.wordCount == null ? '—' : _grouped(doc.wordCount!),
            ),
            if (showsListen(doc))
              KitFigureRow('Listen', listenValue(doc) ?? '—'),
            KitFigureRow(
              'Added',
              doc.createdAt == null ? '—' : readerDate(doc.createdAt!),
            ),
            KitFigureRow('Views', '${doc.viewCount}'),
            KitFigureRow(
              'Last read',
              doc.lastViewedAt == null
                  ? 'Never'
                  : readerDate(doc.lastViewedAt!),
            ),
            KitFigureRow(
              'Passages read',
              '$readCount',
              of: ' of $total',
              meter: total == 0 ? 0 : readCount / total,
            ),
          ],
        ),
        if (_showStats) _breakdown(),
        // Finish / un-finish (3.1.0, ADR-039): the control says which it will
        // do, and says what "finished" is worth. Quiet on the sheet: the
        // page's one brick button is its action.
        KitReaderFinish(
          label: _finishBusy
              ? (finished ? 'Un-finishing…' : 'Marking…')
              : (finished ? 'Mark unfinished' : 'Mark finished'),
          note: finished
              ? 'You finished this on ${readerDate(doc.finishedAt!)}.'
              : 'Reaching the end marks this for you — this is for when you '
                    'got there another way.',
          onPressed: _finishBusy ? null : () => _setFinished(!finished),
          error: _finishError,
        ),
        KitSheetAlso(children: also),
      ],
    );

    return NotificationListener<ScrollStartNotification>(
      // The reader's own hand ends a held jump.
      onNotification: (n) {
        if (n.dragDetails != null) sections.release();
        return false;
      },
      child: KitDPage(
        key: const ValueKey('rx-page'),
        back: _backControl(),
        crumbStacks: true,
        gridTop: 40,
        folio: readerFolio(doc, shelf),
        title: doc.title.isEmpty ? 'Untitled' : doc.title,
        byline: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            byline,
            KitReaderMastNote(
              child: SourceFreshness(docId: widget.docId, doc: doc),
            ),
          ],
        ),
        action: _toLetter(),
        settings: details,
        controller: _scroll,
        sections: sections,
        sheet: KitDSheet(
          label: 'In this volume',
          foldOnPick: true,
          peek: KitSecPeek(items: items, sections: sections),
          foot: KitReadProgress(controller: _scroll),
          body: sheetBody,
        ),
        // A section that answers late (Original's signed URL, Listen) grows
        // the page above a held jump: put the jump back.
        child: NotificationListener<SizeChangedLayoutNotification>(
          onNotification: (_) {
            sections.reanchor();
            return false;
          },
          child: ListenableBuilder(
            listenable: sections,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < items.length; i++)
                  KitReaderSection(
                    sectionKey: sections.keyOf(items[i].id),
                    n: i,
                    title: items[i].label,
                    mounted: sections.isMounted(items[i].id),
                    builder: (context) => SizeChangedLayoutNotifier(
                      child: ReaderSectionScope(
                        child: !complete && items[i].id != 'summary'
                            ? ReaderUi(context).empty(
                                Icons.hourglass_empty,
                                'Still processing',
                                'This section needs the finished passages. '
                                    'Check back once processing completes.',
                              )
                            : _section(items[i].id),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _reorganizing = false;

  /// A refusal is said as a toast — the action has no panel to hold it.
  Future<void> _requestReorganize(Document doc) async {
    setState(() => _reorganizing = true);
    final title = doc.title.isEmpty ? 'this document' : doc.title;
    try {
      await Api.instance.requestReorgPlan(widget.docId);
      if (mounted) {
        AppToast.show(
          context,
          'Drafting a reorganization of “$title” in the background. '
          "You'll find it in For your review.",
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          'This document could not be reorganized. ${e.message}',
          type: ToastType.error,
        );
      }
    } catch (_) {
      // Not swallowed: said as the error toast, with no envelope to quote.
      if (mounted) {
        AppToast.show(
          context,
          'This document could not be reorganized.',
          type: ToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _reorganizing = false);
    }
  }

  /// §The way back. A PUSHED reader (a citation's Open, ADR-101) pops back to
  /// the screen that pushed it, which is the same place `origin.path` names and
  /// keeps that screen's own state. Only a reader with no stack behind it — a
  /// cold open — navigates. A deleted source leaves the same way.
  void _goBack() {
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(
      readerOrigin(widget.from, tags: context.read<TagsNotifier>().tags).path,
    );
  }

  /// §Document shelves (4.83.0, ADR-117; 4.104.0, ADR-137): a §20 editor over
  /// the whole document's `tag_ids` — each drawn as a §35 shelf tag in D —
  /// shown for every complete document; with no shelves at all it is the add
  /// control alone, and its picker is where a first shelf is made from here.
  /// It sits in Source details, read from the document as it is NOW (the
  /// panel outlives the build that opened it).
  /// [tags] are the ones [build] watched: this runs inside the panel's own
  /// build, where watching from the page's context is not allowed.
  Widget _documentShelves(List<Tag> tags) {
    final byId = {for (final t in tags) t.id: t};
    final current = _document?.tagIds ?? const <String>[];
    return KitShelfChipEditor(
      label: 'Shelves',
      chips: [
        for (final id in current)
          if (byId[id] != null) KitShelfChip(byId[id]!),
      ],
      addable: [
        for (final t in tags)
          if (!current.contains(t.id)) t,
      ],
      busy: _shelvesBusy,
      error: _shelvesError,
      removeLabel: (s) => 'Take this source off ${s.title}',
      onAdd: (id) => _writeShelves([...current, id]),
      onRemove: (id) => _writeShelves([
        for (final x in current)
          if (x != id) x,
      ]),
      // The sheet hands the new id back once `fn_create_tag` resolved, and
      // the add runs then — built from the list last READ at that moment,
      // not the one this row was drawn from.
      onCreate: (name) => showShelfSheet(
        context,
        // The document is complete, so the library holds a source to scan.
        canBackfill: true,
        land: null,
        initialName: name,
        createSubtitle: 'This source goes on it as soon as it is created.',
        onCreated: (id) {
          final read = _document?.tagIds ?? current;
          if (!read.contains(id)) _writeShelves([...read, id]);
        },
      ),
    );
  }

  /// One `fn_update_document {tagIds}`. The list sent is the one this screen
  /// last READ plus or minus one id, and the chips move only once the server
  /// accepted it — on success the document commits exactly the list it sent.
  /// A refusal stays beside the row (§14.2) and the chips stay as they were.
  Future<void> _writeShelves(List<String> next) async {
    setState(() {
      _shelvesBusy = true;
      _shelvesError = null;
    });
    try {
      await Api.instance.updateDocument(widget.docId, {'tagIds': next});
      if (!mounted) return;
      setState(() => _document = _document?.withTagIds(next));
    } on ApiException catch (e) {
      if (mounted) setState(() => _shelvesError = e.message);
    } catch (e) {
      if (mounted) setState(() => _shelvesError = describeSdkError(e));
    } finally {
      if (mounted) setState(() => _shelvesBusy = false);
    }
  }

  Widget _section(String id) {
    switch (id) {
      case 'manuscript':
        return ManuscriptPanel(
          docId: widget.docId,
          doc: _document!,
          chunks: _chunks,
          onSaved: _reload,
          onChunksRead: _foldInChunksRead,
          anchorChunkId: widget.passageId,
          // §Step jump branch 1, keyed on **type OR field**: an uploaded
          // recording and an uploaded video both carry `source_audio_url:
          // null` by design, so a client that tests only the field draws a
          // dead chip on every voice memo and every video.
          onSeekAudio: hasOwnAudio(_document!)
              ? (start) {
                  // §Step jump: the chip asks Listen to start at a time — a
                  // JUMP, which mounts Listen if the reader has not reached
                  // it. The seek is set first, so a mounted section does not
                  // play from the top while the scroll runs.
                  setState(() => _listenSeek = start);
                  _sections?.jump('listen');
                }
              : null,
          onOpenLink: (url) =>
              launchUrlString(url, mode: LaunchMode.externalApplication),
        );
      case 'speedread':
        return SpeedReadPanel(paras: _paras);
      case 'listen':
        return ListenPanel(
          docId: widget.docId,
          doc: _document!,
          paras: _listenParas,
          lineStarts: _lineStarts,
          seekTo: _listenSeek,
        );
      case 'original':
        return OriginalPanel(docId: widget.docId, doc: _document!);
      case 'history':
        return HistoryPanel(docId: widget.docId, chunks: _chunks);
      case 'summary':
      default:
        return SummaryPanel(
          doc: _document!,
          // The response body is the update path — the document was loaded
          // with a one-shot get, so nothing else will deliver the new fields
          // and re-fetching would only ask for what we were just told.
          onRegenerated: (res) => setState(
            () => _document = _document!.withRegeneratedSummary(res),
          ),
        );
    }
  }

  /// `YYYY-MM-DD` → "3 January 2026". Returns null rather than guessing when
  /// the string is not the shape the contract promises.
  static String? _fmtPublishDate(String? iso) {
    if (iso == null) return null;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso.trim());
    if (m == null) return null;
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final mo = int.parse(m.group(2)!);
    if (mo < 1 || mo > 12) return null;
    return '${int.parse(m.group(3)!)} ${months[mo - 1]} ${m.group(1)}';
  }

  /// `toLocaleString()` — 1,234.
  static String _grouped(int n) =>
      '$n'.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');

  /// Detailed reading stats (4.1.0) — every figure a filter over chunks
  /// already in memory, so the whole breakdown costs **zero extra reads**.
  /// The categories overlap and are never presented as a partition; absent
  /// means zero, never unknown.
  Widget _breakdown() => KitReadingBreakdown(
    read: _chunks.where((c) => c.viewCount > 0).length,
    searched: _chunks.where((c) => c.searchViewCount > 0).length,
    lettered: _chunks.where((c) => c.lastIncludedInNewsletter != null).length,
    untouched: _chunks
        .where(
          (c) =>
              c.viewCount == 0 &&
              c.searchViewCount == 0 &&
              c.lastIncludedInNewsletter == null,
        )
        .length,
  );

  /// Finish / un-finish (3.1.0, ADR-039). NOT optimistic: `finished_at` comes
  /// back from a re-read rather than being minted locally.
  Future<void> _setFinished(bool finished) async {
    setState(() {
      _finishBusy = true;
      _finishError = null;
    });
    try {
      await Api.instance.setReadState(widget.docId, finished);
      // Only the finishing direction, as the reference has it: un-finishing is
      // a correction, and counting it as a completion would make the number
      // read the wrong way.
      if (finished && _document != null) {
        Analytics.track('doc_finished', {'kind': kitDocKind(_document!.type)});
      }
      // Re-read rather than mint a timestamp locally: the endpoint is the sole
      // writer of finished_at and the server clock is the one that counts.
      await _reload();
    } on ApiException catch (e) {
      if (mounted) setState(() => _finishError = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _finishError = 'That did not save. Try again.');
      }
    } finally {
      if (mounted) setState(() => _finishBusy = false);
    }
  }
}
