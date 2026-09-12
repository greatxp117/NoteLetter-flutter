// The Flutter runner for `harness/extraction_marker_check.py` (/conformance 5z).
//
// Executed, never scraped: the gate asks the SHIPPED splitter to report its own
// label list and its splits over the gate's case table, and compares those to
// the spec. A textual reader is what goes quietly to zero when a constant is
// renamed and reports PASS on the silence (4.34.7). Pure Dart on purpose —
// `dart run tool/marker_probe.dart '<cases json>'` from NoteLetter-flutter/.
//
// Output: one JSON line — `[labels, [[piece, …], …]]` where a piece is
// `["t", text]` or `["m", label, body]`, mirroring the web runner.
import 'dart:convert';

import 'package:flutter_app/shared/extraction_markers.dart';

void main(List<String> args) {
  final cases = (jsonDecode(args.first) as List).cast<String>();
  final splits = [
    for (final c in cases)
      [
        for (final p in splitMarkers(c))
          p.isMark ? ['m', p.label, p.body] : ['t', p.text],
      ],
  ];
  // ignore: avoid_print — this script's whole output is the line the gate reads
  print(jsonEncode([markerLabels, splits]));
}
