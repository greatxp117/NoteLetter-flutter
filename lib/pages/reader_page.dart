import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../models/chunk.dart';
import '../models/document.dart';
import '../services/firestore_service.dart';
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
import '../widgets/app_toast.dart';

/// Reader — one-shot doc + chunks (`chunk_index` asc), fires `logReadEvent`
/// on open (INV-03). Six panels (Summary/Manuscript/SpeedRead/Listen/Original/
/// History) + source-freshness banner + Reorganize action. See reader.md.
class ReaderPage extends StatefulWidget {
  final String docId;
  const ReaderPage({super.key, required this.docId});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  bool _finishBusy = false;
  bool _loading = true;
  String? _error;
  Document? _document;
  List<Chunk> _chunks = const [];
  String _tab = 'summary';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result =
          await FirestoreService.instance.getReaderDocument(widget.docId);
      if (!mounted) return;
      if (result == null) {
        setState(() {
          _error = 'Document not found.';
          _loading = false;
        });
        return;
      }
      setState(() {
        _document = result.$1;
        _chunks = result.$2;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load this document.';
        _loading = false;
      });
    }
  }

  // Reload without re-firing the doc_opened read event (used after content
  // edits / reorganization rewrites chunks under the reader).
  Future<void> _reload() async {
    final result =
        await FirestoreService.instance.getReaderDocumentQuietly(widget.docId);
    if (!mounted || result == null) return;
    setState(() {
      _document = result.$1;
      _chunks = result.$2;
    });
  }

  List<String> get _paras => _chunks.map((c) => c.text).toList();

  /// Real per-line start times for audio/video transcripts (youtube/tiktok/
  /// instagram/podcast): each transcript chunk's HTML is a single `<p data-start="…">`.
  /// `null` per chunk when absent (non-transcript sources) → ListenPanel falls back
  /// to word-count-proportional timing. Mirrors the web ReaderView.
  List<double?> get _lineStarts => _chunks.map((c) {
        final m = RegExp(r'data-start="([\d.]+)"').firstMatch(c.html ?? '');
        return m != null ? double.tryParse(m.group(1)!) : null;
      }).toList();

  static const _tabs = [
    ('summary', 'Summary', Icons.auto_awesome_outlined),
    ('manuscript', 'Manuscript', Icons.notes_outlined),
    ('speedread', 'Speed read', Icons.speed_outlined),
    ('listen', 'Listen', Icons.headset_outlined),
    ('original', 'Original', Icons.insert_drive_file_outlined),
    ('history', 'History', Icons.history),
  ];

  @override
  Widget build(BuildContext context) {
    final ui = ReaderUi(context);
    final doc = _document;
    final complete = doc?.status == DocumentStatus.complete;
    final canReorg = complete && _chunks.length >= 2;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/library'),
        ),
        title: Text(
          doc?.title ?? 'Reader',
          style: GoogleFonts.sourceSerif4(
              fontSize: 18, fontWeight: FontWeight.w700),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (canReorg)
            TextButton.icon(
              onPressed: () => ReorganizeSheet.show(
                  context, widget.docId, () => _reload()),
              icon: const Icon(Icons.account_tree_outlined, size: 16),
              label: const Text('Reorganize'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text(_error!,
                      style: TextStyle(fontFamily: 'Geist', color: ui.critical)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 64),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SourceFreshness(docId: widget.docId, doc: doc!),
                          _bylineRow(ui, doc),
                          const SizedBox(height: 12),
                          _metaRow(ui, doc),
                          _finishControl(ui, doc),
                          const SizedBox(height: 16),
                          _tabBar(ui),
                          const SizedBox(height: 24),
                          if (!complete && _tab != 'summary')
                            ui.empty(Icons.hourglass_empty, 'Still processing',
                                'This panel needs the finished passages. Check back once processing completes.')
                          else
                            _panel(),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _panel() {
    switch (_tab) {
      case 'manuscript':
        return ManuscriptPanel(
            docId: widget.docId, chunks: _chunks, onSaved: _reload);
      case 'speedread':
        return SpeedReadPanel(paras: _paras);
      case 'listen':
        return ListenPanel(
            docId: widget.docId, doc: _document!, paras: _paras, lineStarts: _lineStarts);
      case 'original':
        return OriginalPanel(docId: widget.docId, doc: _document!);
      case 'history':
        return HistoryPanel(docId: widget.docId, chunks: _chunks);
      case 'summary':
      default:
        return SummaryPanel(doc: _document!);
    }
  }

  /// Byline & reading cost (2.13.0, ADR-020 — screens/reader.md §Header).
  /// What the document IS, before what the system did to it. Every part is
  /// optional; the row disappears entirely when none apply.
  Widget _bylineRow(ReaderUi ui, Document doc) {
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
    final words = doc.wordCount ?? 0;
    if (words > 0 && doc.sourceAudioUrl == null) {
      final mins = (words / 220).ceil().clamp(1, 1 << 30);
      parts.add('$mins min read');
    }

    if (parts.isEmpty) return const SizedBox.shrink();

    final row = Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        parts.join('  ·  '),
        style: TextStyle(
            fontFamily: 'Geist', fontSize: 13, color: ui.muted),
      ),
    );

    // The whole byline links to the source when there is one.
    if (doc.sourceUrl == null) return row;
    return InkWell(
      onTap: () => launchUrlString(doc.sourceUrl!,
          mode: LaunchMode.externalApplication),
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
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
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

  Widget _metaRow(ReaderUi ui, Document doc) {
    Widget stat(String num, String label) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(num,
                style: GoogleFonts.sourceSerif4(
                    fontSize: 18, fontWeight: FontWeight.w700, color: ui.fg)),
            Text(label.toUpperCase(),
                style: TextStyle(fontFamily: 'Geist', 
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                    color: ui.muted)),
          ],
        );
    return Wrap(spacing: 28, runSpacing: 12, children: [
      stat('${_chunks.length}', 'Passages'),
      stat('${doc.wordCount ?? 0}', 'Words'),
      stat('${doc.viewCount}', 'Views'),
      stat(doc.lastViewedAt != null ? _fmtDate(doc.lastViewedAt!) : 'Never',
          'Last read'),
      // Coverage, rendered HERE and only here (screens/reader.md): every chunk
      // is already in memory, so it costs no extra read — the same number on a
      // list screen would be one query per row. Since 4.0.0 view_count counts
      // only chunk_read, so this means passages READ and can no longer be moved
      // by a newsletter delivery or a search glance.
      stat('${_chunks.where((c) => c.viewCount > 0).length} / ${_chunks.length}',
          'Passages read'),
    ]);
  }

  /// Finish / un-finish (3.1.0, ADR-039). The label says which it will do —
  /// never a checkbox whose meaning the reader has to infer — and the write is
  /// NOT optimistic: `finished_at` comes back from the response rather than
  /// being minted locally.
  Widget _finishControl(ReaderUi ui, Document doc) {
    final finished = doc.finishedAt != null;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(children: [
        OutlinedButton(
          onPressed: _finishBusy ? null : () => _setFinished(!finished),
          child: Text(_finishBusy
              ? 'Saving…'
              : finished
                  ? 'Mark as unfinished'
                  : 'Mark as finished'),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            finished
                ? 'You marked this finished${doc.finishedAt != null ? ' on ${_fmtDate(doc.finishedAt!)}' : ''}.'
                : 'Reaching the end does this for you — this is for the times '
                    'you got there another way.',
            style: TextStyle(
                fontFamily: 'Geist', fontSize: 12, color: ui.muted),
          ),
        ),
      ]),
    );
  }

  Future<void> _setFinished(bool finished) async {
    setState(() => _finishBusy = true);
    try {
      await Api.instance.setReadState(widget.docId, finished);
      // Re-read rather than mint a timestamp locally: the endpoint is the sole
      // writer of finished_at and the server clock is the one that counts.
      await _reload();
    } catch (_) {
      if (mounted) {
        AppToast.show(context, 'Could not save that.', type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _finishBusy = false);
    }
  }

  Widget _tabBar(ReaderUi ui) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _tabs.map((t) {
          final on = _tab == t.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _tab = t.$1),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: on ? ui.primary : ui.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: on ? ui.primary : ui.border),
                ),
                child: Row(children: [
                  Icon(t.$3, size: 15, color: on ? ui.accentFg : ui.muted),
                  const SizedBox(width: 6),
                  Text(t.$2,
                      style: TextStyle(fontFamily: 'Geist', 
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: on ? ui.accentFg : ui.fg)),
                ]),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _fmtDate(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}';
  }
}
