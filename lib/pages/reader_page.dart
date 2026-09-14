import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../models/chunk.dart';
import '../models/document.dart';
import '../services/firestore_service.dart';
import '../shared/extraction_markers.dart';
import '../state/tags_notifier.dart';
import 'reader/history_panel.dart';
import 'reader/listen_panel.dart';
import 'reader/manuscript_panel.dart';
import 'reader/original_panel.dart';
import 'reader/reader_ui.dart';
import 'reader/reorganize_sheet.dart';
import 'reader/source_freshness.dart';
import 'reader/speed_read_panel.dart';
import 'reader/summary_panel.dart';
import '../services/api.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/kit/kit.dart';

/// Reader — one-shot doc + chunks (`chunk_index` asc), fires `logReadEvent`
/// on open (INV-03). Six panels (Summary/Manuscript/SpeedRead/Listen/Original/
/// History) + source-freshness banner + Reorganize action. See reader.md.
///
/// Composition (`screens/reader.md` §Composition): the **Reading** frame (760),
/// a back control naming the library, a §2.1 chapter opening led by the
/// document's file badge, the byline beneath it, then the §8 stat cluster in
/// its **separated row** form. Each panel is a body swap under that one header,
/// never a second header.
///
/// It sits OUTSIDE `AppLayout` and inside `SupportShell` (INV-22) — the reader
/// is the app's one full-bleed reading surface, and the support footer is shell
/// furniture no screen may forget.
class ReaderPage extends StatefulWidget {
  final String docId;

  /// `?p={chunkId}` — the passage the link pointed at (INV-21). It selects the
  /// Manuscript panel rather than the Summary one, because a link to a passage
  /// that opens a summary has not honoured the link; the panel then scrolls to
  /// it.
  final String? passageId;

  const ReaderPage({super.key, required this.docId, this.passageId});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

/// One Listen line: what is spoken, and when it starts (null → the panel falls
/// back to word-count-proportional timing).
class _ListenLine {
  final String text;
  final double? start;
  const _ListenLine(this.text, this.start);
}

class _ReaderPageState extends State<ReaderPage> {
  /// The detailed reading breakdown is **opt-in and off by default** (4.1.0):
  /// the reader is a reading surface, and instrumentation shown to someone who
  /// did not ask for it is noise on the one screen that should be quiet. The
  /// toggle is a client-local display preference and explicitly NOT contract
  /// state — no field, no endpoint, no sync.
  static const _statsPrefKey = 'reader_detailed_stats';

  /// Where a recipe step's time chip asked Listen to start (§Step jump).
  double? _listenSeek;

  bool _finishBusy = false;
  String? _finishError;
  bool _loading = true;
  String? _error;
  String? _errorRequestId;
  bool _notFound = false;
  bool _showStats = false;
  Document? _document;
  List<Chunk> _chunks = const [];
  late String _tab = widget.passageId == null ? 'summary' : 'manuscript';

  @override
  void initState() {
    super.initState();
    _load();
    _loadStatsPref();
  }

  Future<void> _loadStatsPref() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _showStats = prefs.getBool(_statsPrefKey) ?? false);
  }

  Future<void> _setStatsPref(bool on) async {
    setState(() => _showStats = on);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_statsPrefKey, on);
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
        _error = '$e';
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
  /// A chunk carrying non-`<p>` blocks (a mixed carousel's figures, ADR-019
  /// §Amendment) also stays whole — splitting it to its timed paragraphs would
  /// drop the photo slides out of the transcript list entirely.
  ///
  /// Until this existed the client took `firstMatch` per chunk, which is the
  /// chunk's own start under both shapes and therefore never wrong — it simply
  /// gave up sentence-level seek, one line where the reference offers twenty.
  /// Mirrors the web ReaderView's `listenLines`.
  List<_ListenLine> get _listenLines {
    final out = <_ListenLine>[];
    for (final c in _chunks) {
      final body = html_parser.parseFragment(c.html ?? '');
      final blocks = body.children;
      final timed = blocks
          .where((el) =>
              el.localName == 'p' && el.attributes['data-start'] != null)
          .toList();
      final allParagraphs =
          blocks.isNotEmpty && blocks.every((el) => el.localName == 'p');
      if (timed.length > 1 && allParagraphs) {
        for (final p in timed) {
          out.add(_ListenLine(markersForSpeech(p.text),
              double.tryParse(p.attributes['data-start'] ?? '')));
        }
      } else {
        out.add(_ListenLine(
            markersForSpeech(c.text),
            timed.isNotEmpty
                ? double.tryParse(timed.first.attributes['data-start'] ?? '')
                : null));
      }
    }
    return out;
  }

  List<String> get _listenParas =>
      _listenLines.map((l) => l.text).toList();
  List<double?> get _lineStarts =>
      _listenLines.map((l) => l.start).toList();

  /// Does this document have REAL audio behind its timestamps, as opposed to a
  /// synthesized narration? **Type OR field**, and both halves are
  /// load-bearing (ADR-046 §Rationale, ADR-049): `source_audio_url` is set for
  /// a podcast and an Instagram/TikTok video, while an uploaded recording and
  /// an uploaded video carry null by design and mint their URL per request.
  static bool _hasOwnAudio(Document doc) =>
      (doc.sourceAudioUrl?.isNotEmpty ?? false) ||
      doc.type == 'audio' ||
      doc.type == 'video';

  /// `word_count`, falling back to counting chunk `text` when it is null —
  /// the reference's rule, and the one the byline's reading time reads.
  int get _words =>
      _document?.wordCount ??
      _chunks.fold<int>(
        0,
        (n, c) =>
            n +
            c.text
                .trim()
                .split(RegExp(r'\s+'))
                .where((w) => w.isNotEmpty)
                .length,
      );

  @override
  Widget build(BuildContext context) {
    final doc = _document;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_notFound || (_error != null && doc == null)) {
      return _notReadable();
    }

    final complete = doc!.status == DocumentStatus.complete;
    final canReorg = complete && _chunks.length >= 2;
    final readCount = _chunks.where((c) => c.viewCount > 0).length;

    // The reader is the one authenticated screen OUTSIDE `AppLayout`, so
    // nothing above it pays for the status bar — the AppBar this screen used
    // to carry did, and dropping it put the back control under the notch.
    return SafeArea(
      bottom: false,
      child: KitPage(
        width: KitFrameWidth.reading,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            KitBackControl(
              'Library',
              onTap: () =>
                  context.canPop() ? context.pop() : context.go('/sources'),
            ),
            const SizedBox(height: 18),
            ChapterOpening(
              mark: KitFileBadge(
                kitDocKind(doc.type),
                size: KitBadgeSize.header,
              ),
              folio: _shelfLabel(doc),
              title: doc.title.isEmpty ? 'Untitled' : doc.title,
              // The header runs straight into the byline and the stat row; the
              // chapter rule would read as a divider between a title and its own
              // subtitle.
              rule: false,
              actions: [
                KitButton.ghost(
                  'Ask about this',
                  icon: Icons.forum_outlined,
                  onPressed: () => context.go('/ask'),
                ),
                if (canReorg)
                  KitButton.ghost(
                    'Reorganize',
                    icon: Icons.account_tree_outlined,
                    onPressed: () => ReorganizeSheet.show(
                      context,
                      widget.docId,
                      () => _reload(),
                    ),
                  ),
                KitButton.secondary(
                  'Add to letter',
                  icon: Icons.mail_outlined,
                  onPressed: () => context.go('/settings'),
                ),
              ],
            ),
            _bylineRow(doc),
            SourceFreshness(docId: widget.docId, doc: doc),
            const SizedBox(height: 14),
            _statRow(doc, readCount),
            if (_showStats) ...[const SizedBox(height: 16), _breakdown()],
            const SizedBox(height: 14),
            _finishControl(doc),
            const SizedBox(height: 24),
            ReaderPanelTabs(
              panels: _panels(doc),
              selected: _tab,
              onSelect: (id) => setState(() => _tab = id),
            ),
            const SizedBox(height: 22),
            if (!complete && _tab != 'summary')
              ReaderUi(context).empty(
                Icons.hourglass_empty,
                'Still processing',
                'This panel needs the finished passages. Check back once '
                    'processing completes.',
              )
            else
              _panel(),
          ],
        ),
      ),
    );
  }

  /// 404 / foreign document, and a document that could not be read at all.
  /// Never leaks existence: both say the same thing.
  Widget _notReadable() {
    // The reader is the one authenticated screen OUTSIDE `AppLayout`, so
    // nothing above it pays for the status bar — the AppBar this screen used
    // to carry did, and dropping it put the back control under the notch.
    return SafeArea(
      bottom: false,
      child: KitPage(
        width: KitFrameWidth.reading,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            KitBackControl('Library', onTap: () => context.go('/sources')),
            const SizedBox(height: 18),
            const ChapterOpening(title: 'Source not found', rule: false),
            if (_error != null)
              KitFailureBlock(
                sentence: 'This source could not be loaded.',
                detail: _error!,
                requestId: _errorRequestId,
                onRetry: _load,
              ),
          ],
        ),
      ),
    );
  }

  /// The document's shelf, as the folio line — the reference's `shelfLabel`.
  /// `Unshelved` rather than an empty folio: the row is the screen's place in
  /// the library, and an absent one reads as a missing part.
  String _shelfLabel(Document doc) {
    final tags = context.watch<TagsNotifier>().tags;
    for (final t in tags) {
      if (doc.tagIds.contains(t.id)) return t.title;
    }
    return 'Unshelved';
  }

  List<ReaderPanel> _panels(Document doc) => [
    const ReaderPanel('summary', 'Summary', Icons.auto_awesome_outlined),
    const ReaderPanel('manuscript', 'Manuscript', Icons.notes_outlined),
    const ReaderPanel('speedread', 'Speed read', Icons.speed_outlined),
    const ReaderPanel('listen', 'Listen', Icons.headset_outlined),
    ReaderPanel(
      'original',
      'Original',
      Icons.insert_drive_file_outlined,
      count: doc.type.toUpperCase(),
    ),
    const ReaderPanel('history', 'History', Icons.history),
  ];

  Widget _panel() {
    switch (_tab) {
      case 'manuscript':
        return ManuscriptPanel(
          docId: widget.docId,
          doc: _document!,
          chunks: _chunks,
          onSaved: _reload,
          anchorChunkId: widget.passageId,
          // §Step jump branch 1, keyed on **type OR field**: an uploaded
          // recording and an uploaded video both carry `source_audio_url:
          // null` by design, so a client that tests only the field draws a
          // dead chip on every voice memo and every video.
          onSeekAudio: _hasOwnAudio(_document!)
              ? (start) => setState(() {
                    _tab = 'listen';
                    _listenSeek = start;
                  })
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

  /// Byline & reading cost (2.13.0, ADR-020 — screens/reader.md §Header).
  /// What the document IS, before what the system did to it. Every part is
  /// optional; the row disappears entirely when none apply.
  Widget _bylineRow(Document doc) {
    final t = Tokens.of(context);
    final parts = <String>[];

    // Rendered AS STORED — never reformatted, re-cased or split.
    if (doc.author != null && doc.author!.trim().isNotEmpty) {
      parts.add(doc.author!);
    }

    // publish_date is an ISO `YYYY-MM-DD` STRING, not a Timestamp: INV-06 does
    // not apply, so it is formatted as a calendar date with NO timezone
    // conversion. Converting it would render an article published "January 3"
    // as "January 2" for every reader west of UTC. And createdAt is never
    // substituted — "when you saved it" and "when it was published" differ.
    final published = _fmtPublishDate(doc.publishDate);
    if (published != null) parts.add(published);

    final host = _sourceHost(doc.sourceUrl);
    if (host != null) parts.add(host);

    // max(1, ceil(word_count / 220)) — normative, so every client says the
    // same number. 220 wpm is the same constant the read-tracking dwell rule
    // uses; a client must not hold two opinions about reading speed.
    //
    // The spec omits it "for transcript sources that show a real duration
    // instead", and this client shows no duration for any source: nothing in
    // the workspace writes `audio_seconds`, so the reference's Listen cell is
    // a permanent em-dash. Suppressing the reading time on an audio source
    // would leave the row saying NEITHER, which is the half of the rule that
    // was never the point.
    if (_words > 0) {
      final mins = (_words / 220).ceil().clamp(1, 1 << 30);
      parts.add('$mins min read');
    }

    if (parts.isEmpty) return const SizedBox.shrink();

    final row = Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        parts.join('  ·  '),
        style: TextStyle(
          fontFamily: AppTheme.fontSans,
          fontSize: 13,
          color: t.fgMuted,
        ),
      ),
    );

    // The whole byline links to the source when there is one.
    if (doc.sourceUrl == null) return row;
    return InkWell(
      onTap: () =>
          launchUrlString(doc.sourceUrl!, mode: LaunchMode.externalApplication),
      child: row,
    );
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

  /// The hostname, `www.` stripped. Null when there is no parseable host.
  static String? _sourceHost(String? url) {
    if (url == null) return null;
    final h = Uri.tryParse(url)?.host;
    if (h == null || h.isEmpty) return null;
    return h.startsWith('www.') ? h.substring(4) : h;
  }

  /// §8, **separated row** — serif numerals over mono caps labels, each closed
  /// by a 1px rule, the last unseparated. NOT wrapped top and bottom: the
  /// `--ruled` modifier is a report treatment, and the kit said otherwise until
  /// 4.46.0 because it was transcribed from a dead web class (ADR-084).
  ///
  /// There is no LISTEN cell. The reference has one and it renders an em-dash
  /// on every document in the library, because `audio_seconds` is read by
  /// `ReaderView.jsx` and written by nothing in the workspace — no backend
  /// field, no fixture, no data-model row. §8 is explicit that a stat needs a
  /// real backing signal before it gets a slot.
  Widget _statRow(Document doc, int readCount) {
    return KitStatCluster(
      stats: [
        KitStat('${_chunks.length}', 'Passages'),
        KitStat('$_words', 'Words'),
        KitStat(
          doc.createdAt != null ? _fmtDate(doc.createdAt!) : '—',
          'Added',
        ),
        KitStat('${doc.viewCount}', 'Views'),
        KitStat(
          doc.lastViewedAt != null ? _fmtDate(doc.lastViewedAt!) : 'Never',
          'Last read',
        ),
        // Coverage, rendered HERE and only here (screens/reader.md): every chunk
        // is already in memory, so it costs no extra read — the same number on a
        // list screen would be one query per row. Since 4.0.0 view_count counts
        // only chunk_read, so this means passages READ and can no longer be moved
        // by a newsletter delivery or a search glance. The denominator is context
        // beside the numeral, not a second figure.
        KitStat(
          '$readCount',
          'Passages read',
          denominator: '${_chunks.length}',
        ),
      ],
    );
  }

  /// Detailed reading stats (4.1.0) — every figure a filter over chunks
  /// already in memory, so the whole breakdown costs **zero extra reads**, and
  /// that is the entire reason it is affordable here and nowhere else.
  ///
  /// **These categories overlap and are never presented as a partition.** A
  /// passage can be read here AND have arrived in a letter AND have been
  /// opened from a search; only "never reached you" is exclusive. A bar, a
  /// percentage or a set of parts summing to `chunk_count` would reintroduce
  /// in the presentation layer exactly the conflation 4.0.0 removed from the
  /// counters.
  ///
  /// **Absent means zero, never unknown**: `search_view_count` is absent on
  /// every pre-4.0.0 chunk and `chunk_read` did not exist before 3.1.0, so on
  /// older documents these read low. That is accurate — those events were
  /// never recorded — and rendering it as "no data" would imply the number is
  /// unavailable rather than known to be zero.
  Widget _breakdown() {
    final read = _chunks.where((c) => c.viewCount > 0).length;
    final searched = _chunks.where((c) => c.searchViewCount > 0).length;
    final lettered = _chunks
        .where((c) => c.lastIncludedInNewsletter != null)
        .length;
    final untouched = _chunks
        .where(
          (c) =>
              c.viewCount == 0 &&
              c.searchViewCount == 0 &&
              c.lastIncludedInNewsletter == null,
        )
        .length;

    Widget line(int n, String what) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$n ',
              style: AppTheme.serif(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Tokens.of(context).fg,
              ),
            ),
            TextSpan(text: what),
          ],
        ),
        style: KitText.meta(context),
      ),
    );

    return KitPanel(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Eyebrow('How these passages reached you'),
            SizedBox(height: 4),
            Lede(
              'Ways overlap — a passage can arrive more than one way.',
              fontSize: 14,
              height: 21,
              maxWidth: 440,
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            line(read, 'read in the reader'),
            line(searched, 'opened from a search'),
            line(lettered, 'arrived in a letter'),
            line(untouched, 'not yet reached you'),
          ],
        ),
      ],
    );
  }

  /// Finish / un-finish (3.1.0, ADR-039). The label says which it will do —
  /// never a checkbox whose meaning the reader has to infer — and the write is
  /// NOT optimistic: `finished_at` comes back from the response rather than
  /// being minted locally.
  ///
  /// The detailed-stats toggle rides alongside it: a display preference, on the
  /// row where the reader is already deciding what this screen says about a
  /// document rather than what the document says.
  Widget _finishControl(Document doc) {
    final finished = doc.finishedAt != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            finished
                ? KitButton.secondary(
                    _finishBusy ? 'Un-finishing…' : 'Mark unfinished',
                    onPressed: _finishBusy ? null : () => _setFinished(false),
                  )
                : KitButton.primary(
                    _finishBusy ? 'Marking…' : 'Mark finished',
                    onPressed: _finishBusy ? null : () => _setFinished(true),
                  ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Text(
                finished
                    ? 'You finished this on ${_fmtDate(doc.finishedAt!)}.'
                    : 'Reaching the end marks this for you — this is for when '
                          'you got there another way.',
                style: TextStyle(
                  fontFamily: AppTheme.fontSans,
                  fontSize: 12,
                  height: 1.5,
                  color: Tokens.of(context).fgSubtle,
                ),
              ),
            ),
            KitSettingLink(
              _showStats
                  ? 'Hide reading detail'
                  : 'How these passages reached you',
              icon: _showStats ? Icons.expand_less : Icons.expand_more,
              onTap: () => _setStatsPref(!_showStats),
            ),
          ],
        ),
        // §14.2 — the rejection answers beside the control that refused it,
        // in the control's own flow. Nothing else moved: the label is still
        // what it was before the tap.
        if (_finishError != null) ...[
          const SizedBox(height: 8),
          KitFailureInline(_finishError!),
        ],
      ],
    );
  }

  Future<void> _setFinished(bool finished) async {
    setState(() {
      _finishBusy = true;
      _finishError = null;
    });
    try {
      await Api.instance.setReadState(widget.docId, finished);
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

  String _fmtDate(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}
