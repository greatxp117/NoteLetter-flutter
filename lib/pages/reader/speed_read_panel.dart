import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'reader_ui.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../widgets/kit/kit_text.dart';

/// Reader → Speed read panel: RSVP (one word at a time, pinned to a fixed
/// optical-recognition point), with the full text following along beside it.
/// Contract data is just `chunk.text` in order — no endpoints. Mirrors the web
/// SpeedReadPanel's pacing (per-word dwell scaled by length, punctuation and a
/// paragraph's end) minus its keyboard map, which no binding here reaches.
///
/// Composed against `app-speedread.css` (F-43). Until then the word was set in
/// the MONO at 38 where the reference sets the reading serif at 500, the stage
/// had no reticle or stamp, and **the follow-along text did not exist** —
/// which reader.md §Continuous scroll names as part of the section ("Every
/// section renders in full. Speed read's follow-along text…").
class SpeedReadPanel extends StatefulWidget {
  final List<String> paras;
  const SpeedReadPanel({super.key, required this.paras});

  @override
  State<SpeedReadPanel> createState() => _SpeedReadPanelState();
}

class _Word {
  final String w;
  final bool lastInPara;
  const _Word(this.w, this.lastInPara);
}

class _SpeedReadPanelState extends State<SpeedReadPanel> {
  static const _min = 150, _max = 1000, _step = 25;
  static const _presets = [400, 600, 800, 1000];

  /// Every word in reading order, and each paragraph as the global indices of
  /// its words — the reference's `words` and `blocks`.
  late final List<_Word> _words;
  late final List<List<int>> _blocks;

  int _idx = 0;
  int _wpm = 400;
  bool _playing = false;
  bool _held = false;
  Timer? _timer;

  final ScrollController _textScroll = ScrollController();
  final GlobalKey _textBox = GlobalKey();
  late final List<GlobalKey> _paraKeys;

  @override
  void initState() {
    super.initState();
    final words = <_Word>[];
    final blocks = <List<int>>[];
    for (final p in widget.paras) {
      final toks =
          p.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      final ids = <int>[];
      for (var i = 0; i < toks.length; i++) {
        ids.add(words.length);
        words.add(_Word(toks[i], i == toks.length - 1));
      }
      blocks.add(ids);
    }
    _words = words;
    _blocks = blocks;
    _paraKeys = List.generate(blocks.length, (_) => GlobalKey());
  }

  int get _total => _words.length;
  bool get _done => _idx >= _total && _total > 0;
  int get _cur => _idx.clamp(0, _total - 1);

  @override
  void dispose() {
    _timer?.cancel();
    _textScroll.dispose();
    super.dispose();
  }

  double _dwellMs(int i) {
    final base = 60000 / _wpm;
    if (i >= _total) return base;
    final raw = _words[i].w;
    var d = base;
    if (RegExp(r'''[.!?…]["')”\]]?$''').hasMatch(raw)) {
      d *= 2.1;
    } else if (RegExp(r'''[,;:—]["')”\]]?$''').hasMatch(raw)) {
      d *= 1.55;
    }
    if (raw.length > 8) d += (raw.length - 8) * base * 0.06;
    if (_words[i].lastInPara) d *= 1.25;
    return d < 45 ? 45 : d;
  }

  /// One timer at a time, re-armed from the current state — the reference's
  /// effect, which re-runs on every change of index, pace, play or hold.
  void _schedule() {
    _timer?.cancel();
    if (!_playing || _held || _done || _total == 0) return;
    _timer = Timer(Duration(milliseconds: _dwellMs(_cur).round()), () {
      if (!mounted) return;
      _go((_idx + 1).clamp(0, _total));
    });
  }

  void _go(int idx) {
    setState(() {
      _idx = idx;
      if (_idx >= _total) _playing = false;
    });
    _schedule();
    WidgetsBinding.instance.addPostFrameCallback((_) => _follow());
  }

  void _toggle() {
    setState(() {
      if (_done) {
        _idx = 0;
        _playing = true;
      } else {
        _playing = !_playing;
      }
    });
    _schedule();
  }

  void _setWpm(int wpm) {
    setState(() => _wpm = wpm.clamp(_min, _max));
    _schedule();
  }

  // The stage is held to rest and released to read (`holdStart`/`holdEnd`).
  // A tap is a hold that ends at once, so a tap starts reading. A drag that
  // turns into a scroll is a cancel, and starts nothing: the reference stops
  // the page scrolling over the stage (`touch-action: none`), and a reader
  // scrolling past here has not asked for a run.
  void _holdStart() {
    if (_done) return;
    setState(() => _held = true);
    _schedule();
  }

  void _holdEnd({required bool play}) {
    setState(() {
      _held = false;
      if (play && !_done) _playing = true;
    });
    _schedule();
  }

  /// Keeps the active word in the middle of the follow-along box, as the
  /// reference's `scrollTo` does — smooth below 550 wpm, a jump above it.
  void _follow() {
    if (!mounted || !_textScroll.hasClients || _total == 0) return;
    final cur = _cur;
    final pi = _blocks.indexWhere((b) => b.isNotEmpty && b.last >= cur);
    if (pi < 0) return;
    final para = _paraKeys[pi].currentContext?.findRenderObject();
    final box = _textBox.currentContext?.findRenderObject();
    if (para is! RenderParagraph || box is! RenderBox) return;
    final range = _ParaText.rangeOf(_words, _blocks[pi], cur);
    final rects = para.getBoxesForSelection(
        TextSelection(baseOffset: range.$1, extentOffset: range.$2));
    if (rects.isEmpty) return;
    final wordTop = para.localToGlobal(Offset(0, rects.first.top),
        ancestor: box);
    final target = (_textScroll.offset +
            wordTop.dy -
            box.size.height / 2 +
            (rects.first.bottom - rects.first.top) / 2)
        .clamp(0.0, _textScroll.position.maxScrollExtent);
    if (_wpm > 550) {
      _textScroll.jumpTo(target);
    } else {
      _textScroll.animateTo(target,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  // Optical-recognition pivot: index of the letter to pin (web srPivot).
  int _pivot(String w) {
    final len = w.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').length;
    if (len <= 1) return 0;
    if (len <= 5) return 1;
    if (len <= 9) return 2;
    if (len <= 13) return 3;
    return 4;
  }

  String _fmt(double sec) {
    final s = sec.round().clamp(0, 1 << 30);
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final ui = ReaderUi(context);
    if (_total == 0) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ui.intro('Speed read · one word at a time'),
        ui.empty(Icons.speed, 'Nothing to read.',
            'This source has no text to speed-read yet.'),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // The reference's note, without its last sentence: that one names the
      // keys, and this client binds none.
      ui.intro('Speed read · one word at a time',
          'The source, served a word at a time and pinned to a fixed point so your eye holds still. Set a pace that suits you, hold to rest, and let the text beside you keep your place.'),
      // `.rsvp-layout` — the text beside the reader above 720, and under it
      // below (`order: 2`), 26 apart.
      LayoutBuilder(builder: (context, box) {
        if (box.maxWidth > 720) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 78, child: _aside(ui, maxHeight: 468)),
            const SizedBox(width: 30),
            Expanded(flex: 122, child: _main(ui, box.maxWidth)),
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _main(ui, box.maxWidth),
          const SizedBox(height: 26),
          _aside(ui, maxHeight: 320),
        ]);
      }),
    ]);
  }

  Widget _main(ReaderUi ui, double width) {
    final t = ui.tokens;
    final cur = _cur;
    final w = _words[cur].w;
    final pv = _pivot(w);
    final frac = (_idx / _total).clamp(0.0, 1.0);
    final remaining = (_total - _idx).clamp(0, _total);
    final secsLeft = remaining * (60 / _wpm);
    final narrow = width <= 560;
    final running = _playing && !_held;
    // `.rsvp-word` — clamp(32px, 4.4vw, 50px), a long word clamp(26px,
    // 3.6vw, 40px), against the viewport the reference measures in.
    final vw = MediaQuery.sizeOf(context).width / 100;
    final size = w.length > 9
        ? (3.6 * vw).clamp(26.0, 40.0)
        : (4.4 * vw).clamp(32.0, 50.0);
    final wordStyle = KitText.title(context,
        fontSize: size, height: 1, weight: FontWeight.w500, tracking: -0.01);
    final tick = Container(
        width: 2, height: 14, color: running ? t.accent : t.borderStrong);
    final stamp = _done
        ? 'Done'
        : (_held
            ? 'Paused — release to resume'
            : (_playing ? 'Reading' : 'Hold or tap to read'));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // `.rsvp-stage`
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _holdStart(),
        onTapUp: (_) => _holdEnd(play: true),
        onTapCancel: () => _holdEnd(play: false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          constraints: BoxConstraints(minHeight: narrow ? 200 : 248),
          decoration: BoxDecoration(
            color: _held ? t.surfaceRaised : t.surface,
            borderRadius: AppRadius.lgR,
            border: Border.all(color: t.border),
            boxShadow: _held ? AppShadows.s2 : AppShadows.s1,
          ),
          child: Stack(alignment: Alignment.center, children: [
            Positioned(top: narrow ? 46 : 56, child: tick),
            Positioned(bottom: 52, child: tick),
            Padding(
              padding: narrow
                  ? const EdgeInsets.fromLTRB(18, 38, 18, 32)
                  : const EdgeInsets.fromLTRB(28, 44, 28, 36),
              // The pivot letter on the centre line: the halves either side
              // take equal room, as the reference's `1fr auto 1fr` grid does.
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(w.substring(0, pv),
                        textAlign: TextAlign.right,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                        style: wordStyle),
                  ),
                  Text(pv < w.length ? w.substring(pv, pv + 1) : ' ',
                      style: wordStyle.copyWith(color: t.accentText)),
                  Expanded(
                    child: Text(pv + 1 < w.length ? w.substring(pv + 1) : '',
                        textAlign: TextAlign.left,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                        style: wordStyle),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 16,
              child: Text(stamp.toUpperCase(),
                  style: KitText.monoCaps(context,
                      letterSpacing: 0.14,
                      color: _held ? t.accentText : null)),
            ),
          ]),
        ),
      ),
      // `.rsvp-progress` — the track, then the readout.
      const SizedBox(height: 22),
      ui.track(frac),
      const SizedBox(height: 9),
      Row(children: [
        Text(_done ? 'Finished' : '${_fmt(secsLeft)} left',
            style: KitText.monoMeta(context, letterSpacing: 0.03)),
        const SizedBox(width: 10),
        _dot(t.borderStrong),
        const SizedBox(width: 10),
        Text('${(_idx + (_done ? 0 : 1)).clamp(0, _total)} / $_total words',
            style: KitText.monoMeta(context, letterSpacing: 0.03)),
      ]),
      const SizedBox(height: 22),
      // `.rsvp-controls` — between two rules; the pace drops to its own line
      // on a phone (`.rsvp-speed { min-width: 100%; order: 3 }`).
      Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          border: Border(
              top: BorderSide(color: t.rule), bottom: BorderSide(color: t.rule)),
        ),
        child: narrow
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  _restart(ui),
                  const SizedBox(width: 14),
                  _play(ui),
                ]),
                const SizedBox(height: 14),
                _speed(ui),
              ])
            : Row(children: [
                _restart(ui),
                const SizedBox(width: 14),
                _play(ui),
                const SizedBox(width: 14),
                Expanded(child: _speed(ui)),
              ]),
      ),
    ]);
  }

  Widget _dot(Color c) => Container(
      width: 3,
      height: 3,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle));

  /// `.rsvp-icon` — a 40px ring on `--surface`, the glyph at `--fg-muted`.
  Widget _restart(ReaderUi ui) {
    final enabled = _idx != 0;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Tooltip(
        message: 'Start over',
        child: Material(
          color: ui.card,
          shape: CircleBorder(side: BorderSide(color: ui.border)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? () => _go(0) : null,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(Icons.restart_alt, size: 19, color: ui.muted),
            ),
          ),
        ),
      ),
    );
  }

  Widget _play(ReaderUi ui) => ui.playButton(
        icon: _done
            ? Icons.restart_alt
            : (_playing ? Icons.pause : Icons.play_arrow),
        iconSize: 24,
        nudge: (_playing && !_done) ? 0 : 2,
        tooltip: _done ? 'Read again' : (_playing ? 'Pause' : 'Play'),
        onTap: _toggle,
      );

  /// `.rsvp-speed` — the Pace label and the figure, the stepper and range,
  /// then the presets.
  Widget _speed(ReaderUi ui) {
    final t = ui.tokens;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text('PACE', style: KitText.monoCaps(context)),
          const Spacer(),
          // `.rsvp-wpm` with its `<b>`: the figure at 14/600 in `--fg`, the
          // unit at 11 in `--fg-muted`.
          Text.rich(TextSpan(children: [
            TextSpan(
                text: '$_wpm',
                style: KitText.monoFigure(context,
                    fontSize: 14, weight: FontWeight.w600)),
            TextSpan(
                text: ' wpm',
                style: KitText.monoMeta(context, color: t.fgMuted)),
          ])),
        ],
      ),
      const SizedBox(height: 8),
      Row(children: [
        _stepper(ui, '−', 'Slower',
            _wpm <= _min ? null : () => _setWpm(_wpm - _step)),
        const SizedBox(width: 12),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              activeTrackColor: t.accent,
              inactiveTrackColor: t.surfaceSunken,
              thumbColor: t.accent,
              overlayShape: SliderComponentShape.noOverlay,
              // A native range draws no step marks; 34 dots across the track
              // were Material's, not the reference's.
              tickMarkShape: SliderTickMarkShape.noTickMark,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              trackShape: const RoundedRectSliderTrackShape(),
            ),
            child: Slider(
              value: _wpm.toDouble(),
              min: _min.toDouble(),
              max: _max.toDouble(),
              divisions: (_max - _min) ~/ _step,
              onChanged: (v) => _setWpm(v.round()),
            ),
          ),
        ),
        const SizedBox(width: 12),
        _stepper(ui, '+', 'Faster',
            _wpm >= _max ? null : () => _setWpm(_wpm + _step)),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final p in _presets) _preset(ui, p),
      ]),
    ]);
  }

  /// `.rsvp-step` — 28 square, `--r-sm`, a ring on `--surface`.
  Widget _stepper(
          ReaderUi ui, String glyph, String label, VoidCallback? onTap) =>
      Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: Semantics(
          button: true,
          label: label,
          child: Material(
            color: ui.card,
            shape: RoundedRectangleBorder(
                borderRadius: AppRadius.smR,
                side: BorderSide(color: ui.border)),
            child: InkWell(
              borderRadius: AppRadius.smR,
              onTap: onTap,
              child: SizedBox(
                width: 28,
                height: 28,
                child: Center(
                    child: Text(glyph,
                        style: KitText.body(context).copyWith(
                            color: ui.muted, height: 1))),
              ),
            ),
          ),
        ),
      );

  /// `.rsvp-presets button` — mono 11 on `--surface-sunken`; chosen, the
  /// accent chip.
  Widget _preset(ReaderUi ui, int p) {
    final t = ui.tokens;
    final on = _wpm == p;
    return Material(
      color: on ? t.accentChipBg : t.surfaceSunken,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.smR,
        side: BorderSide(
            color: on ? t.accentChipBorder : Colors.transparent),
      ),
      child: InkWell(
        borderRadius: AppRadius.smR,
        onTap: () => _setWpm(p),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text('$p',
              style: KitText.monoFigure(context,
                  fontSize: 11, color: on ? t.accentText : t.fgMuted)),
        ),
      ),
    );
  }

  /// `.rsvp-aside` — the eyebrow, then the whole text in a box that scrolls
  /// on its own and keeps the active word in view.
  Widget _aside(ReaderUi ui, {required double maxHeight}) {
    final cur = _cur;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ui.eyebrow('Full text · follows along'),
      const SizedBox(height: 12),
      ConstrainedBox(
        key: _textBox,
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          controller: _textScroll,
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var pi = 0; pi < _blocks.length; pi++)
              if (_blocks[pi].isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(
                      bottom: pi == _blocks.length - 1 ? 0 : 14),
                  child: _ParaText(
                    textKey: _paraKeys[pi],
                    words: _words,
                    ids: _blocks[pi],
                    // A paragraph wholly before or after the cursor draws the
                    // same at every tick; only the one holding it moves.
                    cur: cur.clamp(_blocks[pi].first - 1, _blocks[pi].last + 1),
                    onWord: _go,
                  ),
                ),
          ]),
        ),
      ),
    ]);
  }
}

/// One `.rsvp-para`: serif 15/26 at `--fg-muted`, words already read at
/// `--fg-subtle`, the active word on `--highlight` in `--fg`. A tap on a word
/// moves the reader there (`.rsvp-w` onClick). One paragraph, one hit test —
/// not a recognizer per word.
class _ParaText extends StatelessWidget {
  /// On the paragraph's [RichText], so the panel can find its layout to keep
  /// the active word in view and a tap can be hit-tested against it.
  final GlobalKey textKey;
  final List<_Word> words;
  final List<int> ids;
  final int cur;
  final ValueChanged<int> onWord;

  const _ParaText(
      {required this.textKey,
      required this.words,
      required this.ids,
      required this.cur,
      required this.onWord});

  /// The character range of global word [g] inside the paragraph [ids],
  /// joined by single spaces as [build] lays it out.
  static (int, int) rangeOf(List<_Word> words, List<int> ids, int g) {
    var at = 0;
    for (final id in ids) {
      final len = words[id].w.length;
      if (id == g) return (at, at + len);
      at += len + 1;
    }
    return (0, 0);
  }

  @override
  Widget build(BuildContext context) {
    final ui = ReaderUi(context);
    final t = ui.tokens;
    final base = KitText.bodyReading(context,
        fontSize: 15, height: 26, color: t.fgMuted);
    final spans = <InlineSpan>[];
    for (var i = 0; i < ids.length; i++) {
      final g = ids[i];
      final style = g == cur
          ? base.copyWith(color: t.fg, backgroundColor: t.highlight)
          : (g < cur ? base.copyWith(color: t.fgSubtle) : null);
      spans.add(TextSpan(text: words[g].w, style: style));
      if (i < ids.length - 1) spans.add(const TextSpan(text: ' '));
    }
    return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final para = textKey.currentContext?.findRenderObject();
          if (para is! RenderParagraph) return;
          final pos = para.getPositionForOffset(d.localPosition).offset;
          var at = 0;
          for (final id in ids) {
            final end = at + words[id].w.length;
            if (pos <= end) {
              onWord(id);
              return;
            }
            at = end + 1;
          }
        },
        child: RichText(
          key: textKey,
          text: TextSpan(style: base, children: spans),
        ),
      );
  }
}
