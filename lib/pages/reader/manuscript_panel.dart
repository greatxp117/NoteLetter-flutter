import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/chunk.dart';
import '../../services/api.dart';
import '../../services/api_service.dart';
import '../../theme/app_radius.dart';
import 'reader_ui.dart';
import 'passage_mark.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'dwell.dart';
import '../../services/firestore_service.dart';

/// One editable passage. `chunkId == null` marks a passage created by a split
/// (sent to `fn_update_content` with `chunkId: null` so the backend mints one).
class _EditChunk {
  String? chunkId;
  String html;
  String text;
  final bool atomic; // img/table/figure/pre — read-only, deletable only
  bool userEdited;
  bool dirty;
  bool deleted = false;
  bool isNew;
  _EditChunk({
    required this.chunkId,
    required this.html,
    required this.text,
    required this.atomic,
    required this.userEdited,
    this.dirty = false,
    this.isNew = false,
  });
}

/// Reader → Manuscript panel: the extracted text (chunk `html` in order, `text`
/// fallback). Editing writes through `fn_update_content` — text passages are
/// editable/splittable/mergeable/deletable; passages containing atomic blocks
/// (image/table/…) are read-only but removable. Per reader.md / INV-04.
class ManuscriptPanel extends StatefulWidget {
  final String docId;
  final List<Chunk> chunks;
  final Future<void> Function() onSaved;
  const ManuscriptPanel(
      {super.key,
      required this.docId,
      required this.chunks,
      required this.onSaved});

  @override
  State<ManuscriptPanel> createState() => _ManuscriptPanelState();
}

class _ManuscriptPanelState extends State<ManuscriptPanel> {
  late List<_EditChunk> _chunks;
  final Map<int, TextEditingController> _controllers = {};
  bool _editing = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _chunks = _initFrom(widget.chunks);
  }

  @override
  void didUpdateWidget(covariant ManuscriptPanel old) {
    super.didUpdateWidget(old);
    if (!_editing && !_dirty) _chunks = _initFrom(widget.chunks);
  }

  @override
  void dispose() {
    for (final t in _dwellTimers.values) {
      t.cancel();
    }
    _flushTimer?.cancel();
    // Flush on the way out — unmount is one of the three flush points.
    _flush();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  static const _atomicRe =
      r'<\s*(img|table|figure|pre)\b';

  List<_EditChunk> _initFrom(List<Chunk> chunks) {
    _controllers.clear();
    return chunks.map((c) {
      final html = (c.html ?? '').trim();
      final atomic = html.isNotEmpty && RegExp(_atomicRe, caseSensitive: false).hasMatch(html);
      return _EditChunk(
        chunkId: c.chunkId,
        html: html.isEmpty ? '<p>${_esc(c.text)}</p>' : html,
        text: html.isEmpty ? c.text : _stripTags(html),
        atomic: atomic,
        userEdited: c.userEdited,
      );
    }).toList();
  }

  bool get _dirty => _chunks.any((c) => c.dirty || c.deleted);
  List<_EditChunk> get _visible => _chunks.where((c) => !c.deleted).toList();

  TextEditingController _controllerFor(int i, _EditChunk c) {
    return _controllers.putIfAbsent(i, () => TextEditingController(text: c.text));
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static String _stripTags(String html) => html
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _textToHtml(String text) {
    final paras = text
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (paras.isEmpty) return '<p></p>';
    return paras.map((p) => '<p>${_esc(p)}</p>').join();
  }

  int _wordCount(String text) =>
      text.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).length;

  // Fold the live controller text back into the model before a structural op.
  void _commit() {
    for (final entry in _controllers.entries) {
      if (entry.key >= _chunks.length) continue;
      final c = _chunks[entry.key];
      if (c.atomic || c.deleted) continue;
      final t = entry.value.text;
      if (t != c.text) {
        c.text = t;
        c.html = _textToHtml(t);
        c.dirty = true;
      }
    }
  }

  void _rebuildControllers() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
  }

  void _splitAt(int visibleIdx) {
    _commit();
    final c = _visible[visibleIdx];
    final realIdx = _chunks.indexOf(c);
    if (c.atomic) return;
    final ctrl = _controllers[realIdx];
    final text = c.text;
    var off = ctrl?.selection.baseOffset ?? -1;
    if (off <= 2 || off >= text.length - 2) {
      final mid = text.length ~/ 2;
      final after = text.indexOf('. ', mid);
      off = after > -1 ? after + 1 : mid;
    }
    final a = text.substring(0, off).trim();
    final b = text.substring(off).trim();
    if (a.isEmpty || b.isEmpty) return;
    c.text = a;
    c.html = _textToHtml(a);
    c.dirty = true;
    final second = _EditChunk(
      chunkId: null,
      html: _textToHtml(b),
      text: b,
      atomic: false,
      userEdited: false,
      dirty: true,
      isNew: true,
    );
    setState(() {
      _chunks.insert(realIdx + 1, second);
      _rebuildControllers();
    });
  }

  void _mergeUp(int visibleIdx) {
    if (visibleIdx <= 0) return;
    _commit();
    final b = _visible[visibleIdx];
    final a = _visible[visibleIdx - 1];
    if (a.atomic || b.atomic) return; // don't merge across atomic blocks
    a.text = '${a.text}\n\n${b.text}';
    a.html = _textToHtml(a.text);
    a.dirty = true;
    setState(() {
      if (b.isNew) {
        _chunks.remove(b);
      } else {
        b.deleted = true;
      }
      _rebuildControllers();
    });
  }

  void _remove(int visibleIdx) {
    _commit();
    final c = _visible[visibleIdx];
    setState(() {
      if (c.isNew) {
        _chunks.remove(c);
      } else {
        c.deleted = true;
      }
      _rebuildControllers();
    });
  }

  Future<void> _save() async {
    _commit();
    setState(() {
      _saving = true;
      _error = null;
    });
    final visibleNow = _chunks.where((c) => !c.deleted).toList();
    final payload = visibleNow
        .map((c) => {'chunkId': c.isNew ? null : c.chunkId, 'html': c.html})
        .toList();
    final deleteIds = _chunks
        .where((c) => c.deleted && c.chunkId != null)
        .map((c) => c.chunkId!)
        .toList();
    try {
      await Api.instance
          .updateContent(widget.docId, chunks: payload, deleteChunkIds: deleteIds);
      await widget.onSaved();
      if (mounted) setState(() => _editing = false);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Failed to save.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _discard() {
    setState(() {
      _chunks = _initFrom(widget.chunks);
      _editing = false;
      _error = null;
    });
  }

  // ── Read tracking (3.1.0, ADR-039) ───────────────────────────────────────
  // A passage is read once continuously visible for
  // `min(0.5 x words / 220 x 60, 20)` seconds. The timer RESETS when it leaves,
  // so a fast scroll to the bottom marks nothing — that is the whole point of
  // the rule, and the reason a fixed short dwell was rejected.
  final Map<String, Timer> _dwellTimers = {};
  final Set<String> _readThisSession = {};
  final Set<String> _pendingFlush = {};
  Timer? _flushTimer;

  void _onVisibility(_EditChunk c, double fraction) {
    if (!mounted || _editing) return;   // editing is not reading
    // A split-created passage has no id yet — nothing to record against.
    final id = c.chunkId;
    if (id == null || id.isEmpty || _readThisSession.contains(id)) return;

    // Not a fixed threshold: a passage taller than the screen can never be
    // 50% visible, so anything at all counts as on-screen and the DWELL is
    // what discriminates.
    if (fraction <= 0) {
      _dwellTimers.remove(id)?.cancel();
      return;
    }
    if (_dwellTimers.containsKey(id)) return;
    _dwellTimers[id] = Timer(dwellFor(wordsIn(c.text)), () {
      _dwellTimers.remove(id);
      if (!mounted) return;
      _readThisSession.add(id);
      _pendingFlush.add(id);
      _scheduleFlush();
    });
  }

  // Batched (ADR-039 §4): accumulate and flush once, never one write per
  // scroll event. Firestore's +1 rule is per document, so many distinct
  // chunks commit together happily.
  void _scheduleFlush() {
    _flushTimer ??= Timer(const Duration(seconds: 15), _flush);
  }

  Future<void> _flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_pendingFlush.isEmpty) return;
    final ids = _pendingFlush.toList();
    _pendingFlush.clear();
    await FirestoreService.instance.logChunksRead(widget.docId, ids);
  }

  /// Which passages are marked read, taken from the `chunks` PROP rather than
  /// the local edit copy (which drops counters). It therefore updates live: a
  /// confirmed `chunk_read` batch folds into the reader's state and arrives
  /// here.
  Set<String> get _countedIds => widget.chunks
      .where((c) => c.viewCount > 0)
      .map((c) => c.chunkId)
      .toSet();

  @override
  Widget build(BuildContext context) {
    final ui = ReaderUi(context);
    final visible = _visible;
    final totalWords =
        visible.fold<int>(0, (n, c) => n + _wordCount(c.text));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ui.intro(
        'Manuscript · the extracted text',
        _editing
            ? 'Edit a passage, split one in two, or merge it with the one above — saving re-embeds the changed passages. Images and tables can be removed but not edited.'
            : "This is the content NoteLetter read out of your source. Switch on editing to correct the text or adjust how it's split into passages.",
      ),
      // Toolbar.
      Row(children: [
        Text('${visible.length} passages · $totalWords words',
            style: TextStyle(fontFamily: 'Geist', 
                fontSize: 11, fontWeight: FontWeight.w600, color: ui.muted)),
        const Spacer(),
        _editing
            ? FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Done & save'),
              )
            : OutlinedButton.icon(
                onPressed: () => setState(() => _editing = true),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit text'),
              ),
      ]),
      const SizedBox(height: 16),
      ...List.generate(visible.length, (i) {
        final c = visible[i];
        final realIdx = _chunks.indexOf(c);
        // Counted state comes from the `chunks` PROP, not the local edit copy
        // (which drops counters), so a confirmed chunk_read batch lights the
        // mark up live.
        final counted = c.chunkId != null &&
            (_countedIds.contains(c.chunkId) ||
                _readThisSession.contains(c.chunkId));

        final body =
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 2.13.0: chunk-boundary SCAFFOLDING — the passage number, the rule,
            // the per-passage word count and the split/merge affordances — is
            // edit-mode only. Those are how the system chunked the text, not a
            // feature of the source. 4.2.0 amended this for the EXTENT alone,
            // which is why the gutter mark below is outside this gate.
            if (_editing)
            Row(children: [
              Text('№ ${(i + 1).toString().padLeft(2, '0')}',
                  style: GoogleFonts.robotoMono(fontSize: 11, color: ui.muted)),
              const SizedBox(width: 10),
              Text('~${_wordCount(c.text)} words',
                  style: TextStyle(fontFamily: 'Geist', fontSize: 11, color: ui.muted)),
              if (c.userEdited) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: ui.surface,
                    borderRadius: BorderRadius.circular(AppRadius.control(20)),
                  ),
                  child: Text('edited',
                      style: TextStyle(fontFamily: 'Geist', fontSize: 10, color: ui.muted)),
                ),
              ],
              const Spacer(),
              ...[
                if (i > 0 && !c.atomic && !visible[i - 1].atomic)
                  IconButton(
                    tooltip: 'Merge up',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _mergeUp(i),
                    icon: const Icon(Icons.vertical_align_top, size: 16),
                  ),
                IconButton(
                  tooltip: 'Remove passage',
                  visualDensity: VisualDensity.compact,
                  onPressed:
                      visible.length <= 1 ? null : () => _remove(i),
                  icon: Icon(Icons.delete_outline, size: 16, color: ui.critical),
                ),
              ],
            ]),
            if (_editing) const SizedBox(height: 8),
            if (_editing && !c.atomic)
              TextField(
                controller: _controllerFor(realIdx, c),
                maxLines: null,
                onChanged: (_) {
                  if (!c.dirty) setState(() => c.dirty = true);
                },
                style: GoogleFonts.sourceSerif4(
                    fontSize: 16, height: 1.5, color: ui.fg),
                decoration: InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(
                      borderSide: BorderSide(color: ui.border)),
                  enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: ui.border)),
                ),
              )
            else
              _rendered(c, ui),
            if (_editing && c.atomic)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Contains an image or table — remove only.',
                    style: TextStyle(fontFamily: 'Geist', fontSize: 11, color: ui.muted)),
              ),
            if (_editing && !c.atomic)
              Align(
                alignment: Alignment.center,
                child: TextButton.icon(
                  onPressed: () => _splitAt(i),
                  icon: const Icon(Icons.content_cut, size: 14),
                  label: const Text('Split here'),
                ),
              ),
          ]);

        return VisibilityDetector(
          key: Key('dwell-${c.chunkId ?? 'new-$i'}'),
          onVisibilityChanged: (info) => _onVisibility(c, info.visibleFraction),
          child: Container(
            margin: const EdgeInsets.only(bottom: 20),
            // At rest the passage carries NO card chrome: the mark shows extent
            // rather than dividing, and the prose stays a clean continuous
            // sheet. Editing keeps the card, because there the passage really
            // is the object being manipulated.
            padding: _editing
                ? const EdgeInsets.all(16)
                : const EdgeInsets.only(right: 16),
            decoration: _editing
                ? BoxDecoration(
                    color: ui.card,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                        color: c.dirty
                            ? ui.primary.withValues(alpha: 0.5)
                            : ui.border),
                  )
                : null,
            // A Stack, not a stretched Row: in a Column the cross axis is
            // unbounded, so `CrossAxisAlignment.stretch` would hand the mark an
            // infinite height and assert. The Stack sizes to the text and the
            // positioned mark fills exactly that — which is the passage's
            // extent, the one measurement the mark exists to report.
            child: _editing
                ? body
                : Stack(
                    children: [
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: 4,
                        child: PassageMark(counted: counted, ui: ui),
                      ),
                      // The gutter — the mark sits OUTSIDE the text column.
                      Padding(
                        padding: const EdgeInsets.only(left: 26),
                        child: body,
                      ),
                    ],
                  ),
          ),
        );
      }),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(_error!,
              style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: ui.critical)),
        ),
      if (_dirty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Text edited',
                  style: TextStyle(fontFamily: 'Geist', 
                      fontSize: 13, fontWeight: FontWeight.w600, color: ui.fg)),
              Text('saving re-embeds changed passages',
                  style: TextStyle(fontFamily: 'Geist', fontSize: 11, color: ui.muted)),
            ]),
            const Spacer(),
            TextButton.icon(
              onPressed: _saving ? null : _discard,
              icon: const Icon(Icons.undo, size: 14),
              label: const Text('Discard'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check, size: 14),
              label: const Text('Save & re-index'),
            ),
          ]),
        ),
    ]);
  }

  Widget _rendered(_EditChunk c, ReaderUi ui) {
    final html = c.html.trim();
    if (html.isEmpty) {
      return Text(c.text,
          style:
              GoogleFonts.sourceSerif4(fontSize: 16, height: 1.6, color: ui.fg));
    }
    return Html(
      data: html,
      style: {
        'body': Style(
          margin: Margins.zero,
          fontSize: FontSize(16),
          lineHeight: LineHeight.number(1.6),
          color: ui.fg,
        ),
      },
    );
  }
}
