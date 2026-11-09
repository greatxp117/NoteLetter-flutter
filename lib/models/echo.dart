/// A source's **echoes** (`fn_find_echoes`, 5.83.0, ADR-255; api/echoes.md):
/// the passages in the reader's OTHER sources nearest this one's.
///
/// Read as the reference reads it (`EchoesPanel.jsx`): a list that is not a
/// list is no rows, and a figure that is not a whole number is 0. Nothing is
/// re-sorted, filtered or floored here — which neighbours count as echoes is
/// the endpoint's rule, and a second rule here would be a second answer to the
/// same question. `cosine` is not read: no client draws it (kit §43).
library;

/// This source's own passage, or the passage elsewhere that echoes it.
class EchoPassage {
  final String chunkId;
  final int chunkIndex;

  /// The chunk's text, whitespace collapsed and cut at a word at 240
  /// characters. Markers are kept, and a cut may leave one open.
  final String excerpt;

  const EchoPassage({
    required this.chunkId,
    required this.chunkIndex,
    required this.excerpt,
  });

  factory EchoPassage.fromJson(Map<String, dynamic> json) => EchoPassage(
        chunkId: json['chunkId'] as String? ?? '',
        chunkIndex: (json['chunkIndex'] as num?)?.toInt() ?? 0,
        excerpt: json['excerpt'] as String? ?? '',
      );
}

/// The echo: a passage of another of the reader's sources, with that
/// source's id, title (null is drawn *Untitled*) and `type`.
class EchoTarget extends EchoPassage {
  final String docId;
  final String? title;
  final String type;

  const EchoTarget({
    required super.chunkId,
    required super.chunkIndex,
    required super.excerpt,
    required this.docId,
    required this.type,
    this.title,
  });

  factory EchoTarget.fromJson(Map<String, dynamic> json) {
    final p = EchoPassage.fromJson(json);
    return EchoTarget(
      chunkId: p.chunkId,
      chunkIndex: p.chunkIndex,
      excerpt: p.excerpt,
      docId: json['docId'] as String? ?? '',
      title: json['title'] as String?,
      type: json['type'] as String? ?? '',
    );
  }
}

/// One row the server sent: this source's passage and its echo.
class EchoRow {
  final EchoPassage passage;
  final EchoTarget echo;
  const EchoRow(this.passage, this.echo);
}

/// The whole answer.
class EchoesAnswer {
  final List<EchoRow> echoes;

  /// How many of this source's passages were asked (those with a stored
  /// vector, at most 40, evenly spaced). 0 is *nothing to compare yet*.
  final int compared;

  /// How many passages the source has.
  final int passages;

  const EchoesAnswer({
    required this.echoes,
    required this.compared,
    required this.passages,
  });

  /// A long source compared at evenly spaced passages, said under the list.
  bool get partial => compared < passages;

  factory EchoesAnswer.fromJson(Map<String, dynamic> json) {
    final rows = json['echoes'];
    int whole(Object? v) => v is num && v.isFinite ? v.toInt() : 0;
    return EchoesAnswer(
      echoes: [
        if (rows is List)
          for (final r in rows)
            if (r is Map && r['passage'] is Map && r['echo'] is Map)
              EchoRow(
                EchoPassage.fromJson(
                    (r['passage'] as Map).cast<String, dynamic>()),
                EchoTarget.fromJson((r['echo'] as Map).cast<String, dynamic>()),
              ),
      ],
      compared: whole(json['compared']),
      passages: whole(json['passages']),
    );
  }
}

/// One passage of this source and every echo the server sent for it.
class EchoGroup {
  final EchoPassage passage;
  final List<EchoTarget> echoes;
  EchoGroup(this.passage, this.echoes);
}

/// Consecutive rows that answer the same passage share one head (kit §43):
/// the passage is drawn once, its echoes under it. Only CONSECUTIVE rows —
/// the server's order is the source's own, and regrouping across it would be
/// a re-sort (web `echoGroups`).
List<EchoGroup> echoGroups(List<EchoRow> rows) {
  final groups = <EchoGroup>[];
  for (final row in rows) {
    final last = groups.isEmpty ? null : groups.last;
    if (last != null && last.passage.chunkId == row.passage.chunkId) {
      last.echoes.add(row.echo);
    } else {
      groups.add(EchoGroup(row.passage, [row.echo]));
    }
  }
  return groups;
}
