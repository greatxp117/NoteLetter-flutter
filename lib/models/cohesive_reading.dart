/// The **cohesive reading** (`fn_synthesize_search`, contract 4.40.0, ADR-078).
///
/// What the library says about a query, arranged into named sections with a
/// bridging sentence each. Every passage is the STORED chunk, verbatim, placed
/// by code, carrying an id-built reader link (INV-21). The model only named
/// the sections and wrote the bridges — so nothing in this file rewrites,
/// trims, re-orders or re-links what came back, and nothing derives a link.
///
/// Ephemeral: the response is the whole state. Nothing here is persisted, and
/// there is no Firestore shape to mirror.
library;

/// The measured floor the server actually applied — `null` when the pool was
/// empty. Every value is a measurement, so a client may display it; none of it
/// is recomputed here (the fractions are the server's, and a second copy of a
/// threshold is a threshold that drifts).
class CohesiveFloor {
  final double top;
  final double anchor;
  final double low;
  final double cut;

  const CohesiveFloor({
    required this.top,
    required this.anchor,
    required this.low,
    required this.cut,
  });

  static CohesiveFloor? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    double d(String k) => (json[k] as num?)?.toDouble() ?? 0;
    return CohesiveFloor(
        top: d('top'), anchor: d('anchor'), low: d('low'), cut: d('cut'));
  }
}

/// The source of a passage. Deliberately NOT [SearchResultDocument]: the
/// cohesive response carries four fields of the document (`title`, `type`,
/// `source_url`, `thumbnail_url`), not the stored record minus its summary,
/// and reading it through the fuller model would invent defaults for fields
/// the endpoint never sends.
///
/// As in the passages mode, there is no `id` here — a Firestore document's id
/// is not among its fields. The document id of a passage is `document_id`, on
/// the passage itself, which is also what the link is built from.
class CohesivePassageDocument {
  final String title;
  final String type;
  final String? sourceUrl;
  final String? thumbnailUrl;

  const CohesivePassageDocument({
    required this.title,
    required this.type,
    this.sourceUrl,
    this.thumbnailUrl,
  });

  factory CohesivePassageDocument.fromJson(Map<String, dynamic>? json) =>
      CohesivePassageDocument(
        title: (json?['title'] as String?) ?? 'Untitled',
        type: (json?['type'] as String?) ?? 'unknown',
        sourceUrl: json?['source_url'] as String?,
        thumbnailUrl: json?['thumbnail_url'] as String?,
      );
}

/// One placed passage. Flat — the chunk's own fields sit at the top level of
/// the response object, unlike `fn_search_notes`' `{chunk, document}` pair.
class CohesivePassage {
  final String chunkId;
  final String documentId;
  final int chunkIndex;
  final String sourceType;
  final String text;

  /// The stored chunk html, sanitized at ingest (INV-11) — the same trust
  /// basis the reader and the letter render on. **Null on a chunk written
  /// before html existed**, and then [text] is the whole passage.
  final String? html;

  final double score;
  final double cosine;

  /// `/reader/{document_id}?p={chunk_id}`, built in code from ids by the
  /// server (INV-21). Never re-derived here: a link a client assembles is a
  /// link that can disagree with the one the letter sent.
  final String link;

  final int? pageNumber;
  final double? timestampStart;
  final CohesivePassageDocument document;

  const CohesivePassage({
    required this.chunkId,
    required this.documentId,
    required this.chunkIndex,
    required this.sourceType,
    required this.text,
    required this.html,
    required this.score,
    required this.cosine,
    required this.link,
    required this.pageNumber,
    required this.timestampStart,
    required this.document,
  });

  factory CohesivePassage.fromJson(Map<String, dynamic> json) =>
      CohesivePassage(
        chunkId: json['chunk_id'] as String? ?? '',
        documentId: json['document_id'] as String? ?? '',
        chunkIndex: (json['chunk_index'] as num?)?.toInt() ?? 0,
        sourceType: json['source_type'] as String? ?? '',
        text: json['text'] as String? ?? '',
        html: json['html'] as String?,
        score: (json['score'] as num?)?.toDouble() ?? 0,
        cosine: (json['cosine'] as num?)?.toDouble() ?? 0,
        link: json['link'] as String? ?? '',
        pageNumber: (json['page_number'] as num?)?.toInt(),
        timestampStart: (json['timestamp_start'] as num?)?.toDouble(),
        document: CohesivePassageDocument.fromJson(
            json['document'] as Map<String, dynamic>?),
      );
}

/// One named section. `bridge` may be empty (a `kept == 1` reading and the
/// total fallback both produce a section with no bridge); the title is never
/// empty — the server substitutes `Section k`.
class CohesiveSection {
  final String title;
  final String bridge;
  final List<CohesivePassage> passages;

  const CohesiveSection({
    required this.title,
    required this.bridge,
    required this.passages,
  });

  factory CohesiveSection.fromJson(Map<String, dynamic> json) =>
      CohesiveSection(
        title: json['title'] as String? ?? '',
        bridge: json['bridge'] as String? ?? '',
        passages: ((json['passages'] as List?) ?? const [])
            .map((e) => CohesivePassage.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class CohesiveReading {
  final String query;
  final String breadth;
  final int pool;
  final int kept;
  final CohesiveFloor? floor;
  final List<CohesiveSection> sections;

  /// Set exactly when the arrangement degraded — a number re-placed, or the
  /// whole arrangement fallen back to one section. **A reading with a note is
  /// COMPLETE**: every kept passage is in it either way. It is a notice, not a
  /// failure, and `kept == 0` is a no-results answer rather than either.
  final String? note;

  const CohesiveReading({
    required this.query,
    required this.breadth,
    required this.pool,
    required this.kept,
    required this.floor,
    required this.sections,
    required this.note,
  });

  factory CohesiveReading.fromJson(Map<String, dynamic> json) =>
      CohesiveReading(
        query: json['query'] as String? ?? '',
        breadth: json['breadth'] as String? ?? 'normal',
        pool: (json['pool'] as num?)?.toInt() ?? 0,
        kept: (json['kept'] as num?)?.toInt() ?? 0,
        floor: CohesiveFloor.fromJson(json['floor'] as Map<String, dynamic>?),
        sections: ((json['sections'] as List?) ?? const [])
            .map((e) => CohesiveSection.fromJson(e as Map<String, dynamic>))
            .toList(),
        note: json['note'] as String?,
      );
}
