import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
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
                          const SizedBox(height: 12),
                          _metaRow(ui, doc),
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
            docId: widget.docId, doc: _document!, paras: _paras);
      case 'original':
        return OriginalPanel(docId: widget.docId, doc: _document!);
      case 'history':
        return HistoryPanel(docId: widget.docId, chunks: _chunks);
      case 'summary':
      default:
        return SummaryPanel(doc: _document!);
    }
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
    ]);
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
