import 'package:flutter/widgets.dart';

import '../../widgets/kit/kit.dart';

/// The **score explainer** (`spec/screens/search.md` §Score explainer, 4.44.0,
/// ADR-082) — kit §16 anchored popover, on both result surfaces.
///
/// The score is a blend, and until 4.44.0 nothing said so to a reader. The
/// meter on a result row (direction D's register) and the mono figure in the
/// cohesive column carry the **same** explainer on their own score element;
/// §16 asks that an anchor be a control, not that every anchor look alike, so
/// neither surface changes appearance.
///
/// **Every figure is measured.** The components come off the response; the
/// contribution is `weight × component` with the weights read from the
/// contract, which is arithmetic over a returned value rather than a
/// reconstruction of one. **Nothing here may be solved for** — a surface that
/// did not receive `source_priority` renders no Source-priority row rather
/// than deriving it from `(score − 0.8 × cosine) / 0.2`.
///
/// **Not a failure surface.** The fields are always present when the request
/// succeeded, so there is no error state of its own: a failed search is
/// already the §14.1 Failure block, and then there is no score to explain.
/// With no component at all the anchor is inert — no popover, no focus stop,
/// and no `cursor: help` promising an explanation that cannot come.

/// The ranking's weights. They live in `spec/api/search.md` and are **not**
/// response fields — constants of the ranking, not properties of a result,
/// which is why sending them per result would make them look like something
/// that varies. `score = 0.8 × cosine + 0.2 × source_priority`.
const double _wCosine = 0.8;
const double _wSourcePriority = 0.2;

const String _hintCosine =
    'How close this passage is to your query, by meaning rather than by words.';
const String _hintSourcePriority =
    'The weight you gave this source. Defaults to 0.50 when you have not set '
    'one.';

/// The Source-priority row's hint once the server says whether the reader
/// weighted the source (4.118.0, ADR-155; web `PRIORITY_HINT`).
const String _hintPrioritySet = 'The weight you gave this source.';
const String _hintPriorityDefault =
    'You have not weighted this source, so it counts at the default.';

class SearchScoreAnchor extends StatelessWidget {
  final double score;

  /// The measured components. A null renders **no row** for that component.
  final double? cosine;
  final double? sourcePriority;

  /// `source_priority_set` (4.118.0, ADR-155): false draws the row as
  /// *default · 0.50* instead of a half-full bar that reads as "you rated
  /// this a half"; null (an older response) draws as before.
  final bool? sourcePrioritySet;

  /// The score element itself — the meter, or the cohesive column's figure.
  final Widget child;

  const SearchScoreAnchor({
    super.key,
    required this.score,
    required this.cosine,
    required this.sourcePriority,
    this.sourcePrioritySet,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // Fixed order: Similarity, then Source priority.
    final rows = <Widget>[
      if (cosine != null)
        KitPopoverMeterRow(
          label: 'Similarity',
          weight: _wCosine,
          value: cosine!,
          contribution: _wCosine * cosine!,
          hint: _hintCosine,
        ),
      if (sourcePriority != null)
        KitPopoverMeterRow(
          label: 'Source priority',
          weight: _wSourcePriority,
          value: sourcePriority!,
          contribution: _wSourcePriority * sourcePriority!,
          hint: switch (sourcePrioritySet) {
            true => _hintPrioritySet,
            false => _hintPriorityDefault,
            null => _hintSourcePriority,
          },
          // `.pop-default` in place of the bar while unweighted.
          defaultValue: sourcePrioritySet == false,
        ),
    ];

    if (rows.isEmpty) return child;

    return KitAnchoredPopover(
      headLabel: 'Relevance',
      headValue: score.toStringAsFixed(4),
      semanticsLabel:
          'Relevance ${score.toStringAsFixed(2)}. How this score was reached.',
      body: rows,
      foot: rows.length == 2
          ? 'Measured by the server, not estimated.'
          : 'This surface received only part of the breakdown.',
      child: child,
    );
  }
}
