import 'package:flutter/material.dart';
import '../../theme/app_radius.dart';
import 'reader_ui.dart';

/// The passage extent mark (spec/screens/reader.md §Manuscript, 4.2.0–4.2.3).
///
/// A quiet full-height tick in the gutter, **outside the text column**, so the
/// prose still reads as one continuous sheet. It shows a passage's EXTENT
/// rather than dividing passages, because "where does it start and stop" is the
/// actual question and a line *between* passages answers only half of it.
///
/// It carries **two facts on two channels**, and the separation is deliberate:
///
///   HEIGHT — how far the reader has got through this passage, measured from
///     scroll position against a reading line at 70% of the viewport. It is a
///     **high-water mark: it only ever rises.** Reading back over a paragraph
///     is still reading it, and a bar that retreated would say the reader had
///     un-read something. Deliberately NOT driven by the dwell clock — a bar
///     driven by a clock advances while the reader stares out of the window.
///
///   WEIGHT — whether the passage has been counted. Deliberately NOT driven by
///     scroll: ADR-039 §Rationale rejected scroll-past as the marking rule
///     (the last passage never scrolls past, and a fast scroll to the bottom
///     would mark everything). **The marking rule is untouched here.**
///
/// A counted passage renders FULL regardless of scroll. Two reasons, and the
/// second is the one that bites: being counted already means the reader got
/// through it, so a partial bar would understate a fact we are certain of; and
/// the high-water mark starts empty on a fresh load, so without this a passage
/// read yesterday would show as an empty track until the reader happened to
/// scroll past it again.
///
/// Counted changes **three properties at once** — width 2→4, full opacity, and
/// the positive token — because `--fg-subtle` against `--positive` measures
/// 1.34:1, a hue-only difference at 2px: missed in passing, and invisible to a
/// reader with reduced colour vision. **A client MUST NOT encode this state in
/// colour alone.** Width is what makes it read instantly, and it doubles as the
/// moment of completion the bar exists to mark.
class PassageMark extends StatefulWidget {
  final bool counted;
  final ReaderUi ui;

  const PassageMark({super.key, required this.counted, required this.ui});

  @override
  State<PassageMark> createState() => _PassageMarkState();
}

class _PassageMarkState extends State<PassageMark> {
  /// The high-water fill, 0..1. A ValueNotifier rather than setState so a
  /// scroll repaints the bar without rebuilding the passage's text.
  final ValueNotifier<double> _fill = ValueNotifier(0);
  ScrollPosition? _position;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Notifications bubble UP from a Scrollable, so a listener inside its
    // subtree would never fire; the position itself is a Listenable and does.
    final pos = Scrollable.maybeOf(context)?.position;
    if (pos != _position) {
      _position?.removeListener(_measure);
      _position = pos;
      _position?.addListener(_measure);
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_measure);
    _fill.dispose();
    super.dispose();
  }

  void _measure() {
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    final scrollBox = _position?.context.storageContext.findRenderObject()
        as RenderBox?;
    if (box == null || scrollBox == null || !box.hasSize || !scrollBox.hasSize) {
      return;
    }
    if (box.size.height <= 0) return;

    // The reading line sits at 70% of the viewport, roughly where the eye is: a
    // passage still below it has not been reached (0), and one whose bottom has
    // crossed it has been read through (1).
    final line = scrollBox.localToGlobal(Offset.zero).dy +
        scrollBox.size.height * 0.7;
    final top = box.localToGlobal(Offset.zero).dy;
    final here = ((line - top) / box.size.height).clamp(0.0, 1.0);

    // Only ever raise.
    if (here > _fill.value) _fill.value = here;
  }

  @override
  Widget build(BuildContext context) {
    final counted = widget.counted;
    const gutter = 4.0; // reserved either way, so widening never reflows text
    final width = counted ? 4.0 : 2.0;
    // A rail, so its cap is a pill of its own width — not a named step.
    final radius = AppRadius.pillR(width);

    return SizedBox(
      width: gutter,
      // The Row stretches this to the passage's own height, so top:0/bottom:0
      // gives a track of exactly the passage's extent — which is the one thing
      // the mark is there to say.
      child: Stack(
        children: [
          Positioned(
            top: 0,
            bottom: 0,
            left: (gutter - width) / 2,
            width: width,
            child: DecoratedBox(
              decoration: BoxDecoration(color: widget.ui.rule, borderRadius: radius),
              child: ValueListenableBuilder<double>(
                valueListenable: _fill,
                builder: (context, fill, _) => FractionallySizedBox(
                  alignment: Alignment.topCenter,
                  heightFactor: counted ? 1.0 : fill.clamp(0.0, 1.0),
                  child: Opacity(
                    // Held back while uncounted so counted is also a jump in
                    // VALUE, not only in hue. Position stays legible here.
                    opacity: counted ? 1.0 : 0.45,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: counted ? widget.ui.positive : widget.ui.subtle,
                        borderRadius: radius,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
