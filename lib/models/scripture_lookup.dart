/// **Verse search** (`fn_scripture_lookup`, contract 2.28.0 + 4.9.0, ADR-027
/// §2 / ADR-045).
///
/// A citation read verse by verse, with the passages from the reader's own
/// library that answer it. The client parses the citation to decide *which
/// question it is asking* (the echo); this endpoint decides the **result**, and
/// parses again — so what a client renders is what was actually searched.
///
/// Two fields carry the whole safety of this screen and neither may be
/// inferred:
///
/// * [parsed] — `false` means the server read the input as an ordinary query.
///   That is a **normal answer**, not a failure: the caller falls through to
///   the vector search rather than showing anything.
/// * [granularity] — `verse` when each verse was its own query, `passage` when
///   the whole citation was one. Rendering per-verse matches for a
///   passage-granularity answer pins a match to a verse it was never measured
///   against — a fabricated attribution, and one nothing about the screen
///   would look wrong for.
library;

/// One matched chunk. Flat, and deliberately not a [SearchResult]: this
/// endpoint returns four fields per row, not the stored chunk plus its
/// document, and reading it through the fuller model would invent defaults for
/// everything it does not send — a score among them.
class ScripturePassage {
  final String chunkId;
  final String documentId;
  final String text;
  final String? title;

  /// **Which citation this row answered** (4.9.0, ADR-045). Mandatory on every
  /// row of [ScriptureLookup.results] and **rendered, never dropped**: the list
  /// is MERGED — the primary citation's matches and the parallels' — so without
  /// it a Luke passage reads as though it answered a Matthew query. The
  /// attribution is data for exactly this reason.
  final String? matchedReference;
  final String? matchedBook;
  final bool isParallel;
  final String? parallelLabel;

  const ScripturePassage({
    required this.chunkId,
    required this.documentId,
    required this.text,
    this.title,
    this.matchedReference,
    this.matchedBook,
    this.isParallel = false,
    this.parallelLabel,
  });

  factory ScripturePassage.fromJson(Map<String, dynamic> json) =>
      ScripturePassage(
        chunkId: json['chunk_id'] as String? ?? '',
        documentId: json['document_id'] as String? ?? '',
        text: json['text'] as String? ?? '',
        title: json['title'] as String?,
        matchedReference: json['matched_reference'] as String?,
        matchedBook: json['matched_book'] as String?,
        isParallel: json['is_parallel'] as bool? ?? false,
        parallelLabel: json['parallel_label'] as String?,
      );

  /// The same row with an attribution attached — used only to rebuild
  /// `results` for a pre-4.9.0 response, which did not carry one.
  ScripturePassage withMatch(String? reference) => ScripturePassage(
    chunkId: chunkId,
    documentId: documentId,
    text: text,
    title: title,
    matchedReference: reference,
    matchedBook: matchedBook,
    isParallel: isParallel,
    parallelLabel: parallelLabel,
  );
}

/// One verse of the citation, in the shipped public-domain edition (ADR-030).
/// [text] is null for a verse that edition does not carry — an absence stated,
/// never an omission.
class ScriptureVerse {
  final int chapter;
  final int verse;
  final String? text;
  final List<ScripturePassage> passages;

  const ScriptureVerse({
    required this.chapter,
    required this.verse,
    required this.text,
    required this.passages,
  });

  factory ScriptureVerse.fromJson(Map<String, dynamic> json) => ScriptureVerse(
    chapter: (json['chapter'] as num?)?.toInt() ?? 0,
    verse: (json['verse'] as num?)?.toInt() ?? 0,
    text: json['text'] as String?,
    passages: ((json['passages'] as List?) ?? const [])
        .map((e) => ScripturePassage.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// Where else scripture tells the same thing (4.9.0, ADR-045). The relation is
/// committed data, never a model call and never a distance — so [label] and
/// [relation] are the server's words and this client invents neither.
class ScriptureParallel {
  final String reference;
  final String? label;
  final String? relation;

  /// Open vocabulary (`synoptic · chronicler · isaiah-kings · maccabees ·
  /// psalm-doublet`); an unknown value renders neutrally, so nothing here
  /// switches on it.
  final String? corpus;
  final int found;
  final List<ScripturePassage> passages;

  const ScriptureParallel({
    required this.reference,
    required this.label,
    required this.relation,
    required this.corpus,
    required this.found,
    required this.passages,
  });

  factory ScriptureParallel.fromJson(Map<String, dynamic> json) =>
      ScriptureParallel(
        reference: json['reference'] as String? ?? '',
        label: json['label'] as String?,
        relation: json['relation'] as String?,
        corpus: json['corpus'] as String?,
        found: (json['found'] as num?)?.toInt() ?? 0,
        passages: ((json['passages'] as List?) ?? const [])
            .map((e) => ScripturePassage.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class ScriptureLookup {
  /// `false` is the server saying this was an ordinary query after all.
  final bool parsed;
  final String reference;
  final String? book;
  final String? edition;

  /// `verse` or `passage` — **reported, never inferred.**
  final String granularity;
  final int found;
  final List<ScriptureVerse> verses;
  final List<ScriptureParallel> parallels;

  /// The **merged ranked list a client renders**: the primary citation's
  /// matches in the order the vector search returned them, then the parallels'.
  ///
  /// **Deliberately not re-sorted here.** The two groups' distances come from
  /// different queries and do not share a scale, so any client-side re-rank
  /// would present two rankings as one.
  final List<ScripturePassage> results;

  const ScriptureLookup({
    required this.parsed,
    required this.reference,
    required this.book,
    required this.edition,
    required this.granularity,
    required this.found,
    required this.verses,
    required this.parallels,
    required this.results,
  });

  bool get perVerse => granularity == 'verse';

  /// Every match across the primary citation and its parallels — the figure
  /// the merged list is labelled with. Measured: the server's own counts.
  int get parallelFound => parallels.fold(0, (n, p) => n + p.found);

  factory ScriptureLookup.fromJson(Map<String, dynamic> json) {
    final verses = ((json['verses'] as List?) ?? const [])
        .map((e) => ScriptureVerse.fromJson(e as Map<String, dynamic>))
        .toList();
    final parallels = ((json['parallels'] as List?) ?? const [])
        .map((e) => ScriptureParallel.fromJson(e as Map<String, dynamic>))
        .toList();
    final granularity = json['granularity'] as String? ?? 'passage';
    final reference = json['reference'] as String? ?? '';

    final raw = json['results'] as List?;
    // `results` is absent before 4.9.0, hence the fallback — and the fallback
    // attaches the attribution the merged list makes mandatory, from the one
    // place it is knowable for each shape.
    final results = raw != null
        ? raw
              .map((e) => ScripturePassage.fromJson(e as Map<String, dynamic>))
              .toList()
        : (granularity == 'verse'
              ? [
                  for (final v in verses)
                    for (final p in v.passages)
                      p.withMatch(
                        '${json['book'] ?? ''} ${v.chapter}:${v.verse}'.trim(),
                      ),
                ]
              : ((json['passages'] as List?) ?? const [])
                    .map(
                      (e) => ScripturePassage.fromJson(
                        e as Map<String, dynamic>,
                      ).withMatch(reference),
                    )
                    .toList());

    return ScriptureLookup(
      parsed: json['parsed'] as bool? ?? false,
      reference: reference,
      book: json['book'] as String?,
      edition: json['edition'] as String?,
      granularity: granularity,
      found: (json['found'] as num?)?.toInt() ?? 0,
      verses: verses,
      parallels: parallels,
      results: results,
    );
  }
}
