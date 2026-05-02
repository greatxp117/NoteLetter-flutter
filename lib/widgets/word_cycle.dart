import 'dart:async';
import 'package:flutter/material.dart';

class WordCycle extends StatefulWidget {
  final List<String> words;
  final TextStyle? style;

  const WordCycle({super.key, required this.words, this.style});

  @override
  State<WordCycle> createState() => _WordCycleState();
}

class _WordCycleState extends State<WordCycle> {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      setState(() => _index = (_index + 1) % widget.words.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Measure widest word to prevent layout shifts
    final widest = widget.words.reduce((a, b) => a.length >= b.length ? a : b);
    final style = widget.style ?? DefaultTextStyle.of(context).style;

    return SizedBox(
      width: _measureWidth(widest, style),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        transitionBuilder: (child, animation) {
          final offsetAnimation = Tween<Offset>(
            begin: const Offset(0, 1.0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutExpo));
          final outOffsetAnimation = Tween<Offset>(
            begin: const Offset(0, -1.0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutExpo));

          if (child.key == ValueKey(_index)) {
            return ClipRect(
              child: SlideTransition(position: offsetAnimation, child: child),
            );
          } else {
            return ClipRect(
              child: SlideTransition(position: outOffsetAnimation, child: child),
            );
          }
        },
        child: Text(
          widget.words[_index],
          key: ValueKey(_index),
          style: style,
          textAlign: TextAlign.left,
        ),
      ),
    );
  }

  double _measureWidth(String text, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width + 4;
  }
}
