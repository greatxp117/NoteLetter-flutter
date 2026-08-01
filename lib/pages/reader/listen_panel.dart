import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/document.dart';
import '../../services/api.dart';
import '../../services/api_service.dart';
import 'reader_ui.dart';

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

  const ListenPanel(
      {super.key,
      required this.docId,
      required this.doc,
      required this.paras,
      this.lineStarts = const []});

  @override
  State<ListenPanel> createState() => _ListenPanelState();
}

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

  @override
  void initState() {
    super.initState();
    // Podcast/video: the real episode is already available — load it directly,
    // no "Generate audio" step.
    final src = _sourceAudio;
    if (src != null) {
      _audioUrl = src;
      _player.setSourceUrl(src);
    }
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _pos = p);
    });
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _dur = d);
    });
    _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
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
        await _player.setSourceUrl(url);
      } else {
        setState(() =>
            _error = 'Audio is being generated — check back shortly.');
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
    } catch (_) {
      setState(() => _error = 'Failed to generate audio.');
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

  @override
  Widget build(BuildContext context) {
    final ui = ReaderUi(context);

    if (_audioUrl == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ui.intro('Listen',
            'Hear the source read aloud, at your pace. The transcript follows along — tap any line to jump there.'),
        ui.empty(
          Icons.headset_outlined,
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
            child: Center(
              child: Text(_error!,
                  style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: ui.critical)),
            ),
          ),
      ]);
    }

    final total = _dur.inSeconds.toDouble();
    final progress = total == 0 ? 0.0 : _pos.inSeconds / total;
    final active = _activeLine;
    final starts = _starts;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ui.intro(_dur == Duration.zero
          ? 'Listen'
          : 'Listen · ${_fmt(_dur)}${_sourceAudio != null ? '' : ' narration'}'),
      // Player card.
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: ui.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ui.border),
        ),
        child: Column(children: [
          Row(children: [
            Icon(Icons.graphic_eq, size: 24, color: ui.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('NOW READING',
                    style: TextStyle(fontFamily: 'Geist', 
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                        color: ui.muted)),
                Text(widget.doc.title.isEmpty ? 'Untitled' : widget.doc.title,
                    style: GoogleFonts.sourceSerif4(
                        fontSize: 16, fontWeight: FontWeight.w600, color: ui.fg),
                    overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: progress.clamp(0, 1).toDouble(),
              activeColor: ui.primary,
              inactiveColor: ui.border,
              onChanged: total == 0
                  ? null
                  : (v) => _seek(v * total),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_fmt(_pos),
                    style: TextStyle(fontFamily: 'Geist', fontSize: 12, color: ui.muted)),
                Text('-${_fmt(_dur - _pos)}',
                    style: TextStyle(fontFamily: 'Geist', fontSize: 12, color: ui.muted)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
              onPressed: () => _seek(_pos.inSeconds - 15),
              icon: const Icon(Icons.replay_10),
              color: ui.fg,
            ),
            const SizedBox(width: 12),
            IconButton.filled(
              onPressed: () => _playing ? _player.pause() : _player.resume(),
              icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
              style: IconButton.styleFrom(
                backgroundColor: ui.primary,
                foregroundColor: ui.accentFg,
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              onPressed: () => _seek(_pos.inSeconds + 15),
              icon: const Icon(Icons.forward_10),
              color: ui.fg,
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 24),
      ui.eyebrow('Transcript'),
      const SizedBox(height: 10),
      ...List.generate(widget.paras.length, (i) {
        final spoken = i < active;
        return InkWell(
          onTap: total == 0 ? null : () => _seek(starts[i] + 0.1),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              widget.paras[i],
              style: GoogleFonts.sourceSerif4(
                fontSize: 16,
                height: 1.5,
                color: i == active
                    ? ui.fg
                    : (spoken ? ui.muted : ui.muted.withValues(alpha: 0.7)),
                fontWeight: i == active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        );
      }),
    ]);
  }
}
