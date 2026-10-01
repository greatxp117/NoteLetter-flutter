import 'package:flutter/material.dart';
import '../../models/chunk.dart';
import '../../services/firestore_service.dart';
import '../../widgets/kit/kit.dart';
import 'reader_ui.dart';
import '../../services/error_text.dart';

/// One entry per contracted `event_type` (data-model.md §/read_events), and
/// the reference's neutral `Activity` for anything else. `chunk_read` and
/// `doc_finished` (3.1.0) were missing, so this panel drew the raw token
/// `chunk_read (Passage 2)` — the 2.19.0 defect, found by the 2026-09-25
/// frame. Read and viewed never share wording (ADR-039).
const historyEventLabels = {
  'doc_opened': 'Opened the source',
  'chunk_read': 'Read a passage',
  'chunk_viewed': 'Viewed a passage',
  'chunk_newsletter_included': 'Pulled into a letter',
  'doc_finished': 'Marked as finished',
};

String historyEventLabel(Object? eventType) =>
    historyEventLabels[eventType] ?? 'Activity';

/// Reader → History panel: `read_events` for the doc, `created_at desc`,
/// limit 50 (reader.md). Read-only.
class HistoryPanel extends StatefulWidget {
  final String docId;
  final List<Chunk> chunks;
  const HistoryPanel({super.key, required this.docId, required this.chunks});

  @override
  State<HistoryPanel> createState() => _HistoryPanelState();
}

class _HistoryPanelState extends State<HistoryPanel> {


  List<Map<String, dynamic>>? _events;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _error = null;
      _events = null;
    });
    FirestoreService.instance.getReadHistory(widget.docId).then((list) {
      if (mounted) setState(() => _events = list);
    }).catchError((e) {
      if (mounted) setState(() => _error = e);
    });
  }

  String _fmtWhen(int? ts) {
    if (ts == null) return '';
    final diff = DateTime.now().millisecondsSinceEpoch - ts;
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    if (diff < 60 * 1000) return 'Just now';
    if (diff < 24 * 60 * 60 * 1000) {
      final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
      final ap = d.hour < 12 ? 'AM' : 'PM';
      return '$h:${d.minute.toString().padLeft(2, '0')} $ap';
    }
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  String? _chunkLabel(String? chunkId) {
    if (chunkId == null) return null;
    for (final c in widget.chunks) {
      if (c.chunkId == chunkId) return 'Passage ${c.chunkIndex + 1}';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ui = ReaderUi(context);

    if (_error != null) {
      // §14.1 — the region that could not load answers where the content would
      // have been, with the failure NAMED, the underlying sentence verbatim,
      // and one action that re-issues the same request. It read as an italic
      // serif lede here, which is the panel's own explanatory voice: a reader
      // could not tell a failure from a remark.
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ui.intro('Reading history'),
        KitFailureBlock(
          sentence: 'This source’s reading history could not be loaded.',
          detail: describeSdkError(_error!),
          onRetry: _load,
        ),
      ]);
    }
    if (_events == null) {
      // The reference says so in the panel's own voice (`.panel-note`, 24px
      // above and below) rather than drawing a spinner.
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ui.intro('Reading history'),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: ui.note('Loading…'),
        ),
      ]);
    }
    final events = _events!;
    if (events.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ui.intro('Reading history'),
        ui.empty(Icons.history, 'No reads yet.',
            'Open this source to start a reading history.'),
      ]);
    }

    // `.history-list` — a ruled list: a rule above the first row and between
    // rows, none under the last. Each row is the icon at `--fg-subtle`, the
    // label in sans 14 and the time in the mono at 11 (F-43: this drew sans
    // 13 and sans 12 at `--fg-muted`, unruled, as a list of sentences).
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ui.intro(
          'Reading history · ${events.length} event${events.length == 1 ? '' : 's'}'),
      Container(
        decoration:
            BoxDecoration(border: Border(top: BorderSide(color: ui.rule))),
        child: Column(children: [
          for (var i = 0; i < events.length; i++)
            _row(ui, events[i], last: i == events.length - 1),
        ]),
      ),
    ]);
  }

  Widget _row(ReaderUi ui, Map<String, dynamic> e, {required bool last}) {
    final chunkId = e['chunk_id'] as String?;
    final label = _chunkLabel(chunkId);
    final base = historyEventLabel(e['event_type']);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 2),
      decoration: last
          ? null
          : BoxDecoration(border: Border(bottom: BorderSide(color: ui.rule))),
      child: Row(
        children: [
          Icon(chunkId != null ? Icons.search : Icons.visibility_outlined,
              size: 14, color: ui.subtle),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label != null ? '$base ($label)' : base,
                style: KitText.label(context)),
          ),
          const SizedBox(width: 12),
          Text(_fmtWhen(e['created_at'] as int?),
              style: KitText.monoMeta(context, letterSpacing: 0)),
        ],
      ),
    );
  }
}
