import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'reader_ui.dart';
import '../../theme/app_radius.dart';

/// Reader → Speed read panel: RSVP (one word at a time, pinned to a fixed
/// optical-recognition point), with a follow-along transcript. Contract data is
/// just `chunk.text` in order — no endpoints. Mirrors the web SpeedReadPanel's
/// pacing (per-word dwell scaled by length/punctuation) minus its keyboard map.
class SpeedReadPanel extends StatefulWidget {
  final List<String> paras;
  const SpeedReadPanel({super.key, required this.paras});

  @override
  State<SpeedReadPanel> createState() => _SpeedReadPanelState();
}

class _SpeedReadPanelState extends State<SpeedReadPanel> {
  static const _min = 150, _max = 1000, _step = 25;
  static const _presets = [400, 600, 800, 1000];

  late final List<String> _words = widget.paras
      .expand((p) => p.trim().split(RegExp(r'\s+')))
      .where((w) => w.isNotEmpty)
      .toList();

  int _idx = 0;
  int _wpm = 400;
  bool _playing = false;
  Timer? _timer;

  int get _total => _words.length;
  bool get _done => _idx >= _total && _total > 0;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  double _dwellMs(int i) {
    final base = 60000 / _wpm;
    if (i >= _total) return base;
    final raw = _words[i];
    var d = base;
    if (RegExp(r'''[.!?…]["')\]]?$''').hasMatch(raw)) {
      d *= 2.1;
    } else if (RegExp(r'''[,;:—]["')\]]?$''').hasMatch(raw)) {
      d *= 1.55;
    }
    if (raw.length > 8) d += (raw.length - 8) * base * 0.06;
    return d < 45 ? 45 : d;
  }

  void _tick() {
    if (!_playing || _done) return;
    _timer = Timer(Duration(milliseconds: _dwellMs(_idx).round()), () {
      if (!mounted) return;
      setState(() => _idx = (_idx + 1).clamp(0, _total));
      if (_idx >= _total) {
        setState(() => _playing = false);
      } else {
        _tick();
      }
    });
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
    _timer?.cancel();
    if (_playing) _tick();
  }

  void _restart() {
    _timer?.cancel();
    setState(() {
      _idx = 0;
      _playing = false;
    });
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

    final cur = _idx.clamp(0, _total - 1);
    final w = _words[cur];
    final pv = _pivot(w);
    final frac = _total == 0 ? 0.0 : (_idx / _total).clamp(0.0, 1.0);
    final remaining = (_total - _idx).clamp(0, _total);
    final secsLeft = remaining * (60 / _wpm);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ui.intro('Speed read · one word at a time',
          'The source, one word at a time, pinned to a fixed point so your eye holds still. Set a pace that suits you.'),
      // Stage.
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 40),
        decoration: BoxDecoration(
          color: ui.card,
          borderRadius: AppRadius.mdR,
          border: Border.all(color: ui.border),
        ),
        child: Column(children: [
          Container(width: 1, height: 14, color: ui.primary.withValues(alpha: 0.4)),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: GoogleFonts.robotoMono(
                  fontSize: w.length > 9 ? 30 : 38,
                  fontWeight: FontWeight.w500,
                  color: ui.fg),
              children: [
                TextSpan(text: w.substring(0, pv)),
                TextSpan(
                    text: pv < w.length ? w.substring(pv, pv + 1) : ' ',
                    style: TextStyle(color: ui.primary)),
                TextSpan(text: pv + 1 < w.length ? w.substring(pv + 1) : ''),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(width: 1, height: 14, color: ui.primary.withValues(alpha: 0.4)),
          const SizedBox(height: 14),
          Text(
            _done
                ? 'Done'
                : (_playing ? 'Reading' : 'Tap play to read'),
            style: TextStyle(fontFamily: 'Geist', fontSize: 12, color: ui.muted),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      // Progress.
      ClipRRect(
        borderRadius: AppRadius.pillR(6),
        child: LinearProgressIndicator(
          value: frac,
          minHeight: 4,
          backgroundColor: ui.border,
          valueColor: AlwaysStoppedAnimation(ui.primary),
        ),
      ),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(_done ? 'Finished' : '${_fmt(secsLeft)} left',
            style: TextStyle(fontFamily: 'Geist', fontSize: 12, color: ui.muted)),
        Text('${(_idx + (_done ? 0 : 1)).clamp(0, _total)} / $_total words',
            style: TextStyle(fontFamily: 'Geist', fontSize: 12, color: ui.muted)),
      ]),
      const SizedBox(height: 16),
      // Controls.
      Row(children: [
        IconButton(
          onPressed: _idx == 0 ? null : _restart,
          icon: const Icon(Icons.restart_alt),
          color: ui.fg,
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          onPressed: _toggle,
          icon: Icon(_done
              ? Icons.restart_alt
              : (_playing ? Icons.pause : Icons.play_arrow)),
          style: IconButton.styleFrom(
              backgroundColor: ui.primary, foregroundColor: ui.accentFg),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('PACE',
                  style: TextStyle(fontFamily: 'Geist', 
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                      color: ui.muted)),
              const Spacer(),
              Text('$_wpm wpm',
                  style: TextStyle(fontFamily: 'Geist', 
                      fontSize: 13, fontWeight: FontWeight.w600, color: ui.fg)),
            ]),
            Slider(
              value: _wpm.toDouble(),
              min: _min.toDouble(),
              max: _max.toDouble(),
              divisions: (_max - _min) ~/ _step,
              activeColor: ui.primary,
              inactiveColor: ui.border,
              onChanged: (v) => setState(() => _wpm = v.round()),
            ),
            Wrap(
              spacing: 8,
              children: _presets.map((p) {
                final on = _wpm == p;
                return GestureDetector(
                  onTap: () => setState(() => _wpm = p),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: on ? ui.primary : ui.surface,
                      borderRadius: AppRadius.controlR(24),
                      border: Border.all(color: on ? ui.primary : ui.border),
                    ),
                    child: Text('$p',
                        style: TextStyle(fontFamily: 'Geist', 
                            fontSize: 12,
                            color: on ? ui.accentFg : ui.muted)),
                  ),
                );
              }).toList(),
            ),
          ]),
        ),
      ]),
    ]);
  }

  String _fmt(double sec) {
    final s = sec.round().clamp(0, 1 << 30);
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}
