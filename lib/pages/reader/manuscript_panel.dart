import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:html/parser.dart' as html_parser;
import '../../models/chunk.dart';
import '../../models/document.dart';
import '../../services/api.dart';
import '../../services/api_service.dart';
import '../../shared/extraction_markers.dart';
import '../../shared/leave_guard.dart';
import '../../theme/app_radius.dart';
import '../../widgets/kit/kit.dart';
import 'reader_ui.dart';
import 'passage_mark.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'dwell.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';

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

  /// The document itself — read for the **body swap** only: a distilled
  /// document renders the §5.4 Recipe body in place of its passage cards
  /// (4.6.0, ADR-042).
  final Document doc;
  final List<Chunk> chunks;
  final Future<void> Function() onSaved;

  /// The passage a link asked for — `/reader/{docId}?p={chunkId}` (INV-21).
  ///
  /// This is what makes a passage link a passage link: the daily letter, the
  /// cohesive reading and search all hand the reader a chunk id, and until
  /// 4.40.0 this client dropped it and opened the document at the top.
  /// Scrolled to once, after first layout; a chunk id that is not in this
  /// document is simply not found, which leaves the reader at the top — the
  /// same place the link used to land them.
  final String? anchorChunkId;

  /// §Step jump branch 1 — this document has real audio, so a step's time chip
  /// switches to Listen and seeks. Null when it has none, and then the chip is
  /// not a control at all.
  final ValueChanged<double>? onSeekAudio;

  /// §Step jump branch 2 — the source opened at an offset.
  final void Function(String url)? onOpenLink;

  const ManuscriptPanel(
      {super.key,
      required this.docId,
      required this.doc,
      required this.chunks,
      required this.onSaved,
      this.anchorChunkId,
      this.onSeekAudio,
      this.onOpenLink});

  @override
  State<ManuscriptPanel> createState() => _ManuscriptPanelState();
}

class _ManuscriptPanelState extends State<ManuscriptPanel> {
  late List<_EditChunk> _chunks;
  final Map<int, TextEditingController> _controllers = {};
  bool _editing = false;
  bool _saving = false;
  String? _error;

  /// The anchored passage's element, for [Scrollable.ensureVisible]. One key,
  /// not one per chunk: only the anchor is ever scrolled to.
  final GlobalKey _anchorKey = GlobalKey();
  final GlobalKey _sharedKey = GlobalKey();
  bool _anchorScrolled = false;

  @override
  void initState() {
    super.initState();
    _chunks = _initFrom(widget.chunks);
    _scheduleAnchor();
    // Registered ONCE, for the life of the panel, and it answers by reading
    // `_dirty` at the moment it is asked. The alternative — pushing a dirty
    // flag up to the screen on every change — is a second copy of a fact this
    // state already holds, kept in step by a hand-written list of the places
    // that mutate it: there are seven, and the eighth is the one that gets
    // added later (C10).
    _unguard = LeaveGuard.register(_askBeforeLeaving);
  }

  VoidCallback? _unguard;

  /// §18 for leaving with unsaved edits — the same words the reference uses.
  ///
  /// It names what is lost AND what is not, and the safe choice is labelled
  /// with the alternative it takes rather than a bare "Cancel" beside a
  /// destructive verb.
  ///
  /// confirm-ok: this confirmation calls no endpoint. The destructive act IS
  /// the navigation, which nothing can refuse, so there is no rejection for
  /// §18's `error` slot to carry. That slot is required because four confirms
  /// that DID call something could not report a refusal; an empty one here
  /// would be a part of the pattern that can never fill.
  Future<bool> _askBeforeLeaving(BuildContext context) async {
    if (!_dirty) return true;
    final ok = await KitConfirm.show(
      context,
      title: 'Discard your edits?',
      body: 'Your unsaved changes to this manuscript will be lost. Nothing has '
          'been sent yet, so the stored passages are exactly as they were. '
          'Staying takes you back to the manuscript, where Save & re-index '
          'keeps them.',
      confirmLabel: 'Discard and leave',
      cancelLabel: 'Stay and keep editing',
      onConfirm: () async => null,
    );
    return ok == true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleAnchor();
  }

  /// Scroll to the anchor once, after the frame that first laid it out.
  ///
  /// Scheduled from two places because the panel is built before its chunks
  /// arrive as often as after: whichever frame first has both the id and the
  /// element wins, and `_anchorScrolled` makes the other a no-op. Never
  /// repeated — re-anchoring on a rebuild would yank a reader who has scrolled
  /// away back to the passage they arrived at.
  void _scheduleAnchor() {
    if (_anchorScrolled) return;
    // `?p=` WINS. It is the more specific statement of where to land — a letter
    // quoting one passage — and two schedulers racing to scroll one viewport
    // land on whichever frame finishes last (ADR-095, mirroring the reference).
    final toPassage = widget.anchorChunkId != null;
    if (!toPassage && _sharedChunkId == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _anchorScrolled) return;
      final ctx = (toPassage ? _anchorKey : _sharedKey).currentContext;
      if (ctx == null) return;
      _anchorScrolled = true;
      Scrollable.ensureVisible(ctx,
          // A shared slide is where the document OPENS, not a movement to
          // watch; a letter's passage is a jump the reader should see happen.
          duration: toPassage ? const Duration(milliseconds: 320) : Duration.zero,
          curve: Curves.easeOut,
          alignment: 0.08);
      if (toPassage) _flashAnchor();
    });
  }

  /// §Deep link's mark: a FLASH, not a state (4.15.0, ADR-051).
  ///
  /// It answers "which passage did the letter mean" and then gets out of the
  /// way; a persistent highlight would compete with the passage-extent mark.
  /// This client scrolled to the passage from 4.40.0 and never marked it, so
  /// a reader arriving from a letter landed in the right place with nothing
  /// saying which passage had been quoted.
  void _flashAnchor() {
    if (!mounted) return;
    setState(() => _flashing = true);
    Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _flashing = false);
    });
  }

  bool _flashing = false;

  /// The chunk carrying the shared-slide mark, or null (4.58.0, ADR-095).
  String? get _sharedChunkId {
    for (final c in widget.chunks) {
      if ((c.html ?? '').contains('data-shared')) return c.chunkId;
    }
    return null;
  }

  /// Set the moment a save succeeds, and honoured by the reload that follows.
  ///
  /// ADR-056: after a save the in-memory list is **spent**. Its entries marked
  /// deleted name chunks that no longer exist, so a second save resends them
  /// and is refused with a 404. Re-seed from the reload rather than editing on
  /// top of it. The ordinary guard below cannot do this on its own: `onSaved()`
  /// triggers the reload while `_editing` is still true, so `!_editing` blocks
  /// exactly the re-seed that matters.
  bool _pendingResync = false;

  @override
  void didUpdateWidget(covariant ManuscriptPanel old) {
    super.didUpdateWidget(old);
    if (_pendingResync) {
      _pendingResync = false;
      _rebuildControllers();
      _chunks = _initFrom(widget.chunks);
      return;
    }
    if (!_editing && !_dirty) _chunks = _initFrom(widget.chunks);
  }

  @override
  void dispose() {
    _unguard?.call();
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

  /// ADR-056 obligation 2 — never serialize an empty block.
  ///
  /// `<p></p>` used to be the answer for text the reader had cleared. It is a
  /// top-level block with neither text nor an atomic element, which is exactly
  /// what `fn_update_content` refuses — and it refuses the WHOLE list, so one
  /// emptied passage silently discards every other edit in the save. Emitting
  /// nothing lets the preflight below name the passage instead.
  static String _textToHtml(String text) {
    final paras = text
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (paras.isEmpty) return '';
    return paras.map((p) => '<p>${_esc(p)}</p>').join();
  }

  /// Does this fragment carry anything `fn_update_content` will accept?
  ///
  /// Mirrors the endpoint's own test — derived text, or an `<img>` — so the
  /// editor refuses a passage for the same reason the server would, before a
  /// request is built. `img`, `table` and `hr` are content with no text of
  /// their own; `hr` is here because it is the slide/page-break unit (ADR-063),
  /// not decoration.
  static bool _htmlHasContent(String html) {
    if (_stripTags(html).isNotEmpty) return true;
    return RegExp(r'<(img|table|hr)\b', caseSensitive: false).hasMatch(html);
  }

  /// `fn_update_content`'s passage ceiling (ADR-056).
  static const int _maxPassages = 200;

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
    final visibleNow = _chunks.where((c) => !c.deleted).toList();

    // ADR-056 obligation 1 — preflight the closed conditions, because this
    // endpoint refuses the WHOLE list for one bad passage: a save of 200
    // passages fails on account of passage 137 and nothing else is written.
    // Checking here names the passage by its 1-BASED POSITION ON SCREEN, which
    // is the number the endpoint uses and the only one the reader can see.
    final emptyAt = visibleNow.indexWhere((c) => !_htmlHasContent(c.html));
    if (emptyAt > -1) {
      setState(() => _error =
          'Passage ${emptyAt + 1} is empty. Delete it with its 🗑 button, '
          'or put some text back.');
      return;
    }
    if (visibleNow.length > _maxPassages) {
      setState(() => _error =
          'This edit has ${visibleNow.length} passages and $_maxPassages is '
          'the limit. Merge some before saving.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
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
      // Before the reload, not after: `onSaved()` is what delivers the new
      // chunks, and the flag has to be set when didUpdateWidget reads it.
      _pendingResync = true;
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
            style: KitText.fine(context, color: ui.muted, weight: FontWeight.w600)),
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
      // ADR-056 obligation 3 — the rejection renders AT THE CONTROL THAT
      // FAILED, as component-kit §14.2's Inline form (ADR-070): the server's
      // message verbatim, no reference id, because this is a value the reader
      // can fix. It used to be a bare Text at the FOOT of the panel, below
      // every passage — and the save affordance is reachable from anywhere in
      // the document, so a reader part way through the text never scrolled to
      // the end to find out why Save had done nothing.
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: KitFailureInline(_error!),
        ),
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
                  style: AppTheme.mono(fontSize: 11, color: ui.muted)),
              const SizedBox(width: 10),
              Text('~${_wordCount(c.text)} words',
                  style: KitText.fine(context, color: ui.muted)),
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
                      // kit-ok: F-43 — web draws this as `.ms-editbadge`; recompose, not respell
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
                  icon: Icon(Icons.delete_outline, size: 16, color: ui.criticalText),
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
                style: AppTheme.serif(
                    fontSize: 16, height: 1.5, color: ui.fg),
                decoration: InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(
                      borderSide: BorderSide(color: ui.border)),
                  enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: ui.border)),
                ),
              )
            // The Recipe body swap (4.6.0, ADR-042). It renders INSIDE the
            // passage container rather than instead of it, so the gutter mark,
            // the dwell rule and INV-03b read tracking behave exactly as on any
            // other document — the passages ARE the rendered recipe's chunks.
            //
            // Only at rest and only for a single-chunk document: editing edits
            // the manuscript, which is what `fn_update_content` writes, never
            // the structured field. A multi-chunk recipe falls back to plain
            // HTML, which is still a complete recipe — the chunk html IS the
            // recipe (ADR-042 §3).
            else if (_recipeBody && i == 0)
              KitRecipeBody(
                recipe: widget.doc.recipe!,
                images: _imagesFrom(c.html),
                onSeek: widget.onSeekAudio,
                deepLink: _youtubeAt,
                onOpenLink: widget.onOpenLink,
                onOpenImage: (im) => KitLightbox.show(context,
                    url: im.url, caption: im.caption),
              )
            else
              _rendered(c, ui),
            if (_editing && c.atomic)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Contains an image or table — remove only.',
                    style: KitText.fine(context, color: ui.muted)),
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

        // The anchor key rides the OUTERMOST element of the passage, so
        // `ensureVisible` scrolls to the passage and not to a span inside it.
        final isAnchor =
            c.chunkId != null && c.chunkId == widget.anchorChunkId;
        // The shared-slide anchor is the FIRST passage carrying the mark. One
        // document has at most one, but a chunk that has been split by an edit
        // could carry it twice, and scrolling to a second one is scrolling
        // somewhere the reader did not ask to be.
        final isShared = !isAnchor &&
            widget.anchorChunkId == null &&
            _sharedChunkId != null &&
            c.chunkId == _sharedChunkId;
        return KeyedSubtree(
          key: isAnchor
              ? _anchorKey
              : isShared
                  ? _sharedKey
                  : null,
          child: VisibilityDetector(
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
                // The letter's passage, for 2.6 seconds (4.15.0, ADR-051).
                // `--accent-soft` because it flips with the theme; a raw step
                // would stay put and read as a light wash on the dark page.
                : (isAnchor && _flashing
                    ? BoxDecoration(
                        color: ui.tokens.accentSoft,
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      )
                    : null),
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
          ),
        );
      }),
      if (_dirty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Text edited',
                  style: KitText.ui(context, color: ui.fg, weight: FontWeight.w600)),
              Text('saving re-embeds changed passages',
                  style: KitText.fine(context, color: ui.muted)),
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

  /// The RESTING (non-editing) render.
  ///
  /// It annotates extraction markers (§17, ADR-089); edit mode deliberately
  /// does not — an annotation in front of the cursor is one `fn_update_content`
  /// away from being stored, which is the one way a display rule becomes a data
  /// change. Sanitize first, annotate second: the spans this adds carry a
  /// `class`, which the chunk vocabulary lists under *Never*.
  ///
  /// Without this, a marker reached the reader as body copy in the reading
  /// serif — the author's voice saying what the extractor found.
  /// Turn the backend's `data-shared` into a class flutter_html can select
  /// (4.58.0, ADR-095).
  ///
  /// The attribute is the contract; the class is this client's rendering of
  /// it, added at DISPLAY time exactly as `markSanitizedHtml` adds its marker
  /// spans — nothing here changes anything stored, and `class` stays on the
  /// chunk vocabulary's *Never* list for anything written back. Edit mode does
  /// not annotate at all, for the same reason markers do not: an annotation in
  /// front of the cursor is one `fn_update_content` away from being stored.
  ///
  /// Parsed rather than regexed: the attribute appears as `data-shared=""`
  /// after the server's sanitizer and as a bare `data-shared` from the
  /// extractor, and a pattern that has to know which is a pattern that will
  /// eventually meet the other one.
  static String _markShared(String html) {
    if (!html.contains('data-shared')) return html;
    final frag = html_parser.parseFragment(html);
    for (final el in frag.querySelectorAll('[data-shared]')) {
      final existing = el.attributes['class'];
      el.attributes['class'] =
          existing == null || existing.isEmpty ? 'x-shared' : '$existing x-shared';
    }
    return frag.outerHtml;
  }

  /// A distilled document renders the §5.4 body rather than passage cards.
  bool get _recipeBody =>
      widget.doc.recipe != null &&
      !_editing &&
      _chunks.where((c) => !c.deleted).length == 1;

  /// The manuscript's own images, by `data-nl-image-id` — read out of the chunk
  /// HTML exactly as the reference does, because `images[]` stores Storage
  /// object PATHS, which do not render, while the `<img>` here carries a URL
  /// that does.
  List<RecipeImage> _imagesFrom(String html) {
    final frag = html_parser.parseFragment(html);
    return [
      for (final el in frag.querySelectorAll('img[data-nl-image-id]'))
        if ((el.attributes['src'] ?? '').isNotEmpty)
          RecipeImage(
            id: el.attributes['data-nl-image-id']!,
            url: el.attributes['src']!,
            caption: el.attributes['alt'] ?? '',
          ),
    ];
  }

  /// §Step jump branch 2 — a `source_url` on a platform that takes a time
  /// parameter. YouTube is the only one, and it is checked by HOST rather than
  /// by substring: a URL that merely mentions youtube.com is not one.
  String? _youtubeAt(double start) {
    final raw = widget.doc.sourceUrl;
    if (raw == null || raw.isEmpty) return null;
    final u = Uri.tryParse(raw);
    final host = u?.host.toLowerCase() ?? '';
    final youtube = host == 'youtu.be' ||
        host == 'youtube.com' ||
        host.endsWith('.youtube.com');
    if (u == null || !youtube) return null;
    return u.replace(queryParameters: {
      ...u.queryParameters,
      't': '${start.round()}s',
    }).toString();
  }

  Widget _rendered(_EditChunk c, ReaderUi ui) {
    final html = _markShared(markSanitizedHtml(c.html.trim()));
    if (html.isEmpty) {
      return KitMarkedText(c.text,
          style:
              AppTheme.serif(fontSize: 16, height: 1.6, color: ui.fg));
    }
    return Html(
      data: html,
      extensions: AppTheme.htmlExtensions,
      style: AppTheme.htmlStyles(
        ui.tokens,
        body: Style(
          margin: Margins.zero,
          fontSize: FontSize(16),
          lineHeight: LineHeight.number(1.6),
          color: ui.fg,
        ),
      ),
    );
  }
}
