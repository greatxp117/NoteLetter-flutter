import 'package:flutter/material.dart';
import '../../models/chunk.dart';
import '../../services/firestore_service.dart';
import 'reader_ui.dart';

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
  static const _labels = {
    'doc_opened': 'Opened the source',
    'chunk_viewed': 'Viewed a passage',
    'chunk_newsletter_included': 'Pulled into a letter',
  };

  List<Map<String, dynamic>>? _events;
  Object? _error;

  @override
  void initState() {
    super.initState();
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
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ui.intro('Reading history'),
        ui.note('Could not load reading history.'),
      ]);
    }
    if (_events == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ui.intro('Reading history'),
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator())),
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

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ui.intro(
          'Reading history · ${events.length} event${events.length == 1 ? '' : 's'}'),
      ...events.map((e) {
        final chunkId = e['chunk_id'] as String?;
        final label = _chunkLabel(chunkId);
        final base = _labels[e['event_type']] ?? '${e['event_type']}';
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Icon(chunkId != null ? Icons.search : Icons.visibility_outlined,
                  size: 14, color: ui.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label != null ? '$base ($label)' : base,
                    style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: ui.fg)),
              ),
              Text(_fmtWhen(e['created_at'] as int?),
                  style: TextStyle(fontFamily: 'Geist', fontSize: 12, color: ui.muted)),
            ],
          ),
        );
      }),
    ]);
  }
}
