import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../../models/document.dart';
import '../../services/api.dart';
import '../../services/api_service.dart';
import '../../services/error_text.dart';
import '../../widgets/kit/kit.dart';
import 'reader_ui.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';

/// Reader → Listen panel. A podcast/video carries its real source audio
/// (`source_audio_url`, 2.7.0/ADR-016) + real per-line transcript timestamps
/// (`lineStarts`) — prefer those. Otherwise TTS via `fn_generate_audio` with
/// line starts estimated proportionally to word counts (mirrors the web
/// ListenPanel). Handles 413 (too long) / 422 (no text). Per reader.md.
class ListenPanel extends StatefulWidget {
  final String docId;
  final Document doc;
  final List<String> paras;

  /// Real per-line start times (seconds) for transcript sources; one entry per
  /// para, `null` where a chunk had no `data-start`. Used only when EVERY entry
  /// is present. Empty/absent → always fall back to proportional timing.
  final List<double?> lineStarts;

  /// Where a recipe step's time chip asked playback to start
  /// (`screens/reader.md` §Step jump, branch 1). Applied **once**, when the
  /// player knows its duration — seeking a source that has not loaded clamps
  /// to zero, which lands the reader at the top of the recording and looks
  /// exactly like a chip that did nothing.
  final double? seekTo;

  const ListenPanel(
      {super.key,
      required this.docId,
      required this.doc,
      required this.paras,
      this.lineStarts = const [],
      this.seekTo});

  @override
  State<ListenPanel> createState() => _ListenPanelState();
}

/// One sentence for every way a recording fails to reach the ear — web's own,
/// word for word. Before it, `setSourceUrl` ran unawaited here, so a dead or
/// expired URL drew 0:00 under a Play button that did nothing; and a load that
/// failed after a successful generation was reported as the GENERATION failing
/// (TODO D, 2026-09-22).
const _loadFailed = 'This recording could not be loaded.';

class _ListenPanelState extends State<ListenPanel> {
  final AudioPlayer _player = AudioPlayer();
  String? _audioUrl;
  bool _generating = false;
  String? _error;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  bool _playing = false;

  /// The real episode audio (podcast/video), when present — played directly
  /// instead of TTS narration.
  String? get _sourceAudio =>
      (widget.doc.sourceAudioUrl?.isNotEmpty ?? false) ? widget.doc.sourceAudioUrl : null;

  /// Real transcript timestamps are usable only when every para has one.
  bool get _hasRealStarts =>
      widget.lineStarts.length == widget.paras.length &&
      widget.paras.isNotEmpty &&
      widget.lineStarts.every((s) => s != null && s.isFinite);

  /// The step jump waiting for the player to be ready, if any.
  double? _pendingSeek;

  @override
  void initState() {
    super.initState();
    _pendingSeek = widget.seekTo;
    // Podcast/video: the real episode is already available — load it directly,
    // no "Generate audio" step. Otherwise a narration generated before is
    // played, as web does (`sourceAudio || doc.audio_url`); asking to generate
    // one that exists would pay for the same audio twice.
    final src = _sourceAudio ??
        ((widget.doc.audioUrl?.isNotEmpty ?? false) ? widget.doc.audioUrl : null);
    if (src != null) {
      _audioUrl = src;
      _load(src);
    }
    // The player reports a source it cannot play as an ERROR on these
    // streams. With no `onError` that error was uncaught — a zone error on a
    // device, and no word on the screen.
    void failed(Object _) {
      if (mounted) setState(() => _error = _loadFailed);
    }

    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _pos = p);
    }, onError: failed);
    _player.onDurationChanged.listen((d) {
      if (!mounted) return;
      setState(() => _dur = d);
      _applyPendingSeek();
    }, onError: failed);
    _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    }, onError: failed);
  }

  @override
  void didUpdateWidget(ListenPanel old) {
    super.didUpdateWidget(old);
    // A second chip tapped while this panel is already open.
    if (widget.seekTo != null && widget.seekTo != old.seekTo) {
      _pendingSeek = widget.seekTo;
      _applyPendingSeek();
    }
  }

  void _applyPendingSeek() {
    final target = _pendingSeek;
    if (target == null || _dur.inMilliseconds == 0) return;
    _pendingSeek = null;
    _seek(target);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  /// Awaits the player's own answer: `setSourceUrl` completes when the source
  /// is prepared and throws when it cannot be.
  Future<void> _load(String url) async {
    try {
      await _player.setSourceUrl(url);
    } catch (_) {
      if (mounted) setState(() => _error = _loadFailed);
    }
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      return;
    }
    try {
      await _player.resume();
    } catch (_) {
      if (mounted) setState(() => _error = _loadFailed);
    }
  }

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final res = await Api.instance.generateAudio(widget.docId);
      final url = (res['audio_url'] ?? res['audioUrl'] ?? res['url']) as String?;
      if (url != null && url.isNotEmpty) {
        setState(() => _audioUrl = url);
        // Its own failure, not this call's: the narration WAS generated.
        await _load(url);
      } else {
        // `fn_generate_audio` is synchronous: a 200 always carries `audio_url`
        // (api/audio.md). A 200 without one is a failure, not a queue — the
        // "check back shortly" this used to write was a success sentence in
        // the failure slot for a state the backend cannot produce (C9/D6/F2).
        setState(() => _error = 'Narration could not be generated. Please try again.');
      }
    } on ApiException catch (e) {
      setState(() {
        if (e.statusCode == 413) {
          _error = 'This document is too long to narrate.';
        } else if (e.statusCode == 422) {
          _error = 'There is no readable text to narrate.';
        } else {
          _error = e.message;
        }
      });
    } catch (e) {
      // Not an `ApiException`: a request that never reached the endpoint.
      // "Failed to generate audio." named the narration failing when it was
      // never asked for — web and iOS say what the SDK said (D6, §14.3).
      setState(() => _error = describeSdkError(e));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  List<double> get _starts {
    // Real transcript timestamps (podcast/video) when every line has one; else a
    // word-count-proportional approximation over the narration duration (TTS).
    if (_hasRealStarts) {
      return widget.lineStarts.map((s) => s!).toList();
    }
    final w = widget.paras
        .map((p) => p.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).length)
        .toList();
    final sum = w.fold<int>(0, (a, b) => a + b);
    final total = _dur.inMilliseconds / 1000.0;
    var acc = 0;
    return w.map((x) {
      final s = sum == 0 ? 0.0 : (acc / sum) * total;
      acc += x;
      return s;
    }).toList();
  }

  int get _activeLine {
    final starts = _starts;
    final t = _pos.inMilliseconds / 1000.0;
    var idx = 0;
    for (var i = 0; i < starts.length; i++) {
      if (t >= starts[i]) idx = i;
    }
    return idx;
  }

  String _fmt(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _seek(double seconds) async {
    final clamped = seconds.clamp(0, _dur.inSeconds.toDouble());
    await _player.seek(Duration(milliseconds: (clamped * 1000).round()));
  }

  /// The panel note, as the reference words it for each source of sound.
  String get _note => _sourceAudio != null
      ? 'The original episode, at your pace. The transcript follows along — tap any line to jump there.'
      : 'Hear the source read aloud, at your pace. The transcript follows along — tap any line to jump there.';

  @override
  Widget build(BuildContext context) {
    final ui = ReaderUi(context);

    if (_audioUrl == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ui.intro('Listen', _note),
        ui.empty(
          KitQuill.icon,
          'No narration yet.',
          'Generate an audio reading of this source.',
          action: FilledButton.icon(
            onPressed: _generating ? null : _generate,
            icon: _generating
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome, size: 16),
            label: Text(_generating ? 'Generating…' : 'Generate audio'),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            // §14.2 — the inline rejection at the control that asked, in the
            // kit's widget. This composed its own TextStyle until F-36, which
            // is inline composition by definition (ADR-041) and drew the
            // sentence a step off the pattern; the PLAN_LIMIT refusal (4.79.0)
            // is the case that made it visible, since that sentence is the
            // server's and is meant to read exactly as it does everywhere else.
            child: Center(child: KitFailureInline(_error!)),
          ),
      ]);
    }

    final total = _dur.inMilliseconds / 1000.0;
    final progress = total == 0 ? 0.0 : (_pos.inMilliseconds / 1000.0) / total;
    final active = _activeLine;
    final starts = _starts;
    final t = ui.tokens;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // The note stays under the eyebrow once there is something to play —
      // the reference keeps it in both states; this client dropped it here.
      ui.intro(
          _dur == Duration.zero
              ? 'Listen'
              : 'Listen · ${_fmt(_dur)}${_sourceAudio != null ? '' : ' narration'}',
          _note),
      // `.player` — the card the transport sits on (F-43: this was a flat
      // `--r-md` box with a Material slider and a waveform glyph).
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
        decoration: BoxDecoration(
          color: ui.card,
          borderRadius: AppRadius.lgR,
          border: Border.all(color: ui.border),
          boxShadow: AppShadows.s2,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // `.player-top` — the seal, then the eyebrow over the title.
          Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.accentSoft,
                border: Border.all(color: t.accentChipBorder),
              ),
              alignment: Alignment.center,
              child: KitQuill(size: 24, color: t.seal),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('NOW READING',
                    style: KitText.monoCaps(context, letterSpacing: 0.14)),
                const SizedBox(height: 3),
                Text(widget.doc.title.isEmpty ? 'Untitled' : widget.doc.title,
                    // `.player-title`
                    style: KitText.title(context, fontSize: 21, height: 1.15),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
          const SizedBox(height: 22),
          ui.track(progress,
              onSeek: total == 0 ? null : (f) => _seek(f * total)),
          const SizedBox(height: 4),
          // `.player-times` — mono 11 at `--fg-subtle`.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmt(_pos), style: KitText.monoMeta(context, letterSpacing: 0)),
              Text('-${_fmt(_dur - _pos)}',
                  style: KitText.monoMeta(context, letterSpacing: 0)),
            ],
          ),
          // §14.2 under the times, as web and iOS draw it. The player branch
          // had no failure slot at all, so a recording that would not load had
          // nowhere to say so even once something noticed.
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: KitFailureInline(_error!)),
            ),
          const SizedBox(height: 18),
          // `.player-controls` — back 15, play, forward 15, 22 apart. The
          // skips were Material's replay_10/forward_10, a "10" on a control
          // that moves fifteen seconds.
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _skip(ui, back: true),
            const SizedBox(width: 22),
            // `is-play` (web 13c910c): the play triangle's mass sits left of
            // its box, so it is nudged to the optical centre while the Play
            // glyph shows. Material's triangle already sits 1.5px right of
            // centre; 2px more lands it where web's 3px nudge puts IcoPlay.
            ui.playButton(
              icon: _playing ? Icons.pause : Icons.play_arrow,
              nudge: _playing ? 0 : 2,
              tooltip: _playing ? 'Pause' : 'Play',
              onTap: _toggle,
            ),
            const SizedBox(width: 22),
            _skip(ui, back: false),
          ]),
        ]),
      ),
      const SizedBox(height: 30),
      ui.eyebrow('Transcript'),
      const SizedBox(height: 12),
      // `.lt-line` — the reading serif at 18/30 in `--fg-muted`, `--fg-lede`
      // once spoken, and `--fg` on `--accent-chip-bg` with an accent rule at
      // its left edge while it is the line playing. F-43: these were serif 16
      // with the active line BOLDED, a weight the reference never sets.
      ...List.generate(widget.paras.length, (i) {
        final isActive = i == active;
        final spoken = i < active;
        return InkWell(
          onTap: total == 0 ? null : () => _seek(starts[i] + 0.1),
          borderRadius: AppRadius.smR,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: isActive ? t.accentChipBg : null,
              borderRadius: AppRadius.smR,
              border: Border(
                left: BorderSide(
                    width: 2,
                    color: isActive ? t.accent : Colors.transparent),
              ),
            ),
            child: Text(
              widget.paras[i],
              style: KitText.bodyReading(context,
                  color: isActive ? t.fg : (spoken ? t.fgLede : t.fgMuted)),
            ),
          ),
        );
      }),
    ]);
  }

  /// `.pbtn` with its `.skip-n` — the circular arrow at `--fg-muted` and the
  /// mono "15" under it. Material has no fifteen-second glyph, so the arrow is
  /// `replay`, mirrored for forward.
  Widget _skip(ReaderUi ui, {required bool back}) {
    final glyph = Icon(Icons.replay, size: 26, color: ui.muted);
    return IconButton(
      tooltip: back ? 'Back 15s' : 'Forward 15s',
      onPressed: () => _seek(_pos.inSeconds + (back ? -15 : 15).toDouble()),
      icon: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
        back ? glyph : Transform.flip(flipX: true, child: glyph),
        Positioned(
          bottom: -4,
          child: Text('15',
              style: KitText.monoMeta(context,
                  fontSize: 8, letterSpacing: 0, color: ui.muted)),
        ),
      ]),
    );
  }
}
