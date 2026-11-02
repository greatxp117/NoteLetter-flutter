import 'dart:async';

import 'package:flutter/material.dart';
import '../../models/activity_item.dart';
import '../../models/chunk.dart';
import '../../services/error_text.dart';
import '../../services/firestore_service.dart';
import '../../services/source_history.dart';
import '../../widgets/kit/kit.dart';
import 'reader_ui.dart';

export '../../services/source_history.dart'
    show historyEventLabels, historyEventLabel;

const _filters = [
  KitSlideOption('all', 'All'),
  KitSlideOption('reading', 'Reading'),
  KitSlideOption('activity', 'Activity'),
];

/// The window, labelled as one: a half that returned its whole limit is the
/// most recent N, never a total.
const _readingWindowNote =
    'Only your most recent $sourceHistoryLimit reading events are shown.';
const _activityWindowNote =
    'Only the most recent $sourceHistoryLimit Activity events for this source are shown.';

/// Reader → History (5.44.0, ADR-199; reader.md §History): the source's
/// reading history AND its Activity events, one list, newest first — ported
/// from the web reference `pages/reader/HistoryPanel.jsx`. Until 5.44.0 it was
/// the `read_events` alone.
///
/// Two reads, and each half shows what it has. A half that failed keeps its
/// error and draws a §14.1 block in the list's place, retrying only itself —
/// never an empty list, which would be a source page asserting nothing
/// happened here over a read that did not complete (INV-24).
class HistoryPanel extends StatefulWidget {
  final String docId;
  final List<Chunk> chunks;
  const HistoryPanel({super.key, required this.docId, required this.chunks});

  @override
  State<HistoryPanel> createState() => _HistoryPanelState();
}

class _HistoryPanelState extends State<HistoryPanel> {
  List<Map<String, dynamic>>? _reads;
  Object? _readErr;
  bool _readsDone = false;
  int _readTry = 0;

  List<ActivityItem>? _activity;
  Object? _actErr;
  bool _actDone = false;
  StreamSubscription<List<ActivityItem>>? _actSub;

  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _loadReads();
    _subscribeActivity();
  }

  @override
  void didUpdateWidget(HistoryPanel old) {
    super.didUpdateWidget(old);
    if (old.docId != widget.docId) {
      _loadReads();
      _subscribeActivity();
    }
  }

  @override
  void dispose() {
    _actSub?.cancel();
    super.dispose();
  }

  void _loadReads() {
    final attempt = ++_readTry;
    setState(() {
      _readsDone = false;
      _readErr = null;
      _reads = null;
    });
    FirestoreService.instance.getReadHistory(widget.docId).then((list) {
      if (mounted && attempt == _readTry) {
        setState(() {
          _reads = list;
          _readsDone = true;
        });
      }
    }).catchError((Object e) {
      if (mounted && attempt == _readTry) {
        setState(() {
          _readErr = e;
          _readsDone = true;
        });
      }
    });
  }

  /// A listener that errored has ended (Firestore sends nothing after the
  /// error), so the block's retry subscribes again.
  void _subscribeActivity() {
    _actSub?.cancel();
    setState(() {
      _actDone = false;
      _actErr = null;
      _activity = null;
    });
    _actSub = FirestoreService.instance
        .subscribeSourceActivity(widget.docId)
        .listen((items) {
      if (!mounted) return;
      setState(() {
        _activity = items;
        _actErr = null;
        _actDone = true;
      });
    }, onError: (Object e) {
      if (!mounted) return;
      setState(() {
        _actErr = e;
        _activity = null;
        _actDone = true;
      });
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

  Widget _block(String sentence, Object err, VoidCallback onRetry) =>
      KitFailureBlock(
        sentence: sentence,
        detail: describeSdkError(err),
        onRetry: onRetry,
      );

  @override
  Widget build(BuildContext context) {
    final ui = ReaderUi(context);
    // The section's own eyebrow carries no count (two limited reads merged by
    // time are not a total), and inside a D section it is not drawn at all.
    final intro = ui.intro('History');
    Widget panel(List<Widget> children) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [intro, ...children],
        );

    if (!_readsDone || !_actDone) {
      return panel([
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: ui.note('Loading…'),
        ),
      ]);
    }

    final readErr = _readErr;
    final actErr = _actErr;
    if (readErr != null && actErr != null) {
      return panel([
        _block('This source’s history could not be loaded.', readErr, () {
          _loadReads();
          _subscribeActivity();
        }),
      ]);
    }

    final h = sourceHistory(
      docId: widget.docId,
      reads: _reads,
      activity: _activity,
      chunks: widget.chunks,
    );
    final readRows = h.rows.where((r) => !r.isActivity).length;
    final actRows = h.rows.where((r) => r.isActivity).length;

    // One half failed and the other has nothing to show: the block alone.
    if (readErr != null && actRows == 0) {
      return panel([
        _block('Your reading history could not be loaded.', readErr, _loadReads),
      ]);
    }
    if (actErr != null && readRows == 0) {
      return panel([
        _block('Activity for this source could not be loaded.', actErr,
            _subscribeActivity),
      ]);
    }

    // §7 only when BOTH halves answered and both are empty.
    if (h.rows.isEmpty) {
      return panel([
        ui.empty(Icons.history, 'No history yet.',
            'Open this source to start a reading history.'),
      ]);
    }

    final showReading = _filter != 'activity';
    final showActivity = _filter != 'reading';
    final shown = [
      for (final r in h.rows)
        if (r.isActivity ? showActivity : showReading) r,
    ];
    final readBlock = readErr != null && showReading;
    final actBlock = actErr != null && showActivity;
    final nothing = shown.isEmpty && !readBlock && !actBlock;
    final notes = [
      if (showReading && readErr == null && h.readingWindow) _readingWindowNote,
      if (showActivity && actErr == null && h.activityWindow)
        _activityWindowNote,
    ];

    return panel([
      Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: KitSlideSwitch<String>(
          label: 'Show',
          value: _filter,
          options: _filters,
          onChanged: (v) => setState(() => _filter = v),
        ),
      ),
      if (readBlock)
        _block(
          showActivity
              ? 'Your reading history could not be loaded. Activity for this source is below.'
              : 'Your reading history could not be loaded.',
          readErr,
          _loadReads,
        ),
      if (actBlock)
        _block(
          showReading
              ? 'Activity for this source could not be loaded. Your reading history is below.'
              : 'Activity for this source could not be loaded.',
          actErr,
          _subscribeActivity,
        ),
      if ((readBlock || actBlock) && shown.isNotEmpty)
        const SizedBox(height: 18),
      // `.history-list` — a ruled list: a rule above the first row and
      // between rows, none under the last.
      if (shown.isNotEmpty)
        Container(
          decoration:
              BoxDecoration(border: Border(top: BorderSide(color: ui.rule))),
          child: Column(children: [
            for (var i = 0; i < shown.length; i++)
              _row(ui, shown[i], last: i == shown.length - 1),
          ]),
        ),
      if (nothing) _note(ui, 'Nothing of this kind yet.'),
      for (final n in notes) _note(ui, n),
    ]);
  }

  /// The panel's note voice under the list, `18px 2px 0`.
  Widget _note(ReaderUi ui, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 10, 2, 0),
        child: ui.note(text),
      );

  Widget _row(ReaderUi ui, HistoryRow e, {required bool last}) {
    final t = ui.tokens;
    final error = e.isActivity && e.level == 'error';
    final icon = e.isActivity
        ? (error ? Icons.warning_amber_rounded : Icons.timeline_outlined)
        : (e.chunk ? Icons.search : Icons.visibility_outlined);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 2),
      decoration: last
          ? null
          : BoxDecoration(border: Border(bottom: BorderSide(color: ui.rule))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 14, color: error ? t.critical : ui.subtle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.label, style: KitText.label(context)),
                if (e.detail != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      e.detail!,
                      style: KitText.lede(context,
                          fontSize: 13, height: 18.2, color: t.fgMuted),
                    ),
                  ),
              ],
            ),
          ),
          if (e.isActivity) ...[
            const SizedBox(width: 12),
            // The origin tag: mono 10 caps at 0.08em in a hairline pill.
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: t.border),
              ),
              child: Text('ACTIVITY',
                  style: KitText.monoCaps(context, letterSpacing: 0.08)),
            ),
          ],
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(_fmtWhen(e.createdAt),
                style: KitText.monoMeta(context, letterSpacing: 0)),
          ),
        ],
      ),
    );
  }
}
