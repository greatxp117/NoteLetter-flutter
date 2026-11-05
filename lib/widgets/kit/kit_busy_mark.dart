import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// §6.1 State — Busy (ADR-237): the one drawing of "this control's own request
/// is on its way". To change what busy looks like, change this file: no screen
/// and no control draws its own.
///
/// A ring in the control's own label [color], with a quarter of it open, one
/// turn in 0.8s, sized to the control's icon slot. Under reduced motion it stops
/// turning and stays drawn. Decorative to a screen reader: the busy label or the
/// control's name says it in words.
class KitBusyMark extends StatefulWidget {
  final double size;
  final Color color;

  const KitBusyMark({super.key, this.size = 14, required this.color});

  @override
  State<KitBusyMark> createState() => _KitBusyMarkState();
}

class _KitBusyMarkState extends State<KitBusyMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _turn.stop();
    } else if (!_turn.isAnimating) {
      _turn.repeat();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: RotationTransition(
          turns: _turn,
          child: CustomPaint(
            size: Size.square(widget.size),
            painter: _BusyRing(widget.color),
          ),
        ),
      );
}

class _BusyRing extends CustomPainter {
  final Color color;

  const _BusyRing(this.color);

  static const double _stroke = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = _stroke / 2;
    final ring = Rect.fromLTWH(
        inset, inset, size.width - _stroke, size.height - _stroke);
    canvas.drawArc(
      ring,
      // Open at the top, as web's `border-top-color: transparent` is.
      -math.pi / 4,
      1.5 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_BusyRing old) => old.color != color;
}
