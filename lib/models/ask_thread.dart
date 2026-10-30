import 'document.dart' show tsMs;

/// Ask conversation history (contract 4.53.0/4.54.0, ADR-090;
/// `spec/data-model.md` §/ask_threads, `spec/api/ask.md`).
///
/// A thread is an unbounded, queried, time-ordered collection scoped by a
/// `user_id` **field** — not a per-user path — so the rail's list is an ordinary
/// query like `documents` and `chunks`, and the rules allow it only because the
/// equality filter is part of it (INV-02).
///
/// Every write goes through `fn_ask_turn` / `fn_ask_threads` (INV-04). Nothing
/// here constructs a thread locally: a conversation the client invents is a
/// conversation that disappears on reload, which is the whole defect ADR-090
/// closed.

/// Who wrote a message.
///
/// **Open vocabulary for reading** (`spec/data-model.md`): anything that is not
/// `user` renders as the library, so a later `role: "system"` needs no breaking
/// client change. Deliberately not an enum with a `system` case — the point is
/// that an *unknown* value is already handled.
enum AskRole {
  user,
  library;

  static AskRole fromString(String? s) =>
      s == 'user' ? AskRole.user : AskRole.library;
}

class AskThread {
  final String id;

  /// The **first** question, 80 chars on a word boundary. Written once, on
  /// creation, and afterwards only by `fn_ask_threads` PATCH — a title the
  /// reader chose is never overwritten by a later question.
  final String title;

  /// The **latest** question, 200 chars (4.54.0). The rail entry's second line.
  ///
  /// Stored rather than derived: the rail lists threads whose messages it does
  /// not subscribe to, and the only other way to fill this line is to invent
  /// something — which is the one thing a client may never draw.
  final String preview;

  final int messageCount;
  final int? createdAt;
  final int? updatedAt;

  /// The shelf this conversation is scoped to (4.62.0, ADR-098), written on
  /// creation and never afterwards: a scope that could move would make every
  /// answer above it ambiguous about what it searched. `null` is unscoped —
  /// the whole library — and is what every thread created before 4.62.0 says.
  final String? tagId;

  /// The shelf's title **as it was when the conversation was created**. Stored,
  /// not resolved: the rail lists threads without reading shelves, and the
  /// label is what the conversation was asked with. A [tagId] naming a deleted
  /// shelf is inert, never an error.
  final String? tagTitle;

  const AskThread({
    required this.id,
    this.title = '',
    this.preview = '',
    this.messageCount = 0,
    this.createdAt,
    this.updatedAt,
    this.tagId,
    this.tagTitle,
  });

  /// INV-06: every timestamp becomes epoch ms at the read boundary.
  factory AskThread.fromJson(String id, Map<String, dynamic> json) => AskThread(
        id: id,
        title: json['title'] as String? ?? '',
        preview: json['preview'] as String? ?? '',
        messageCount: (json['message_count'] as num?)?.toInt() ?? 0,
        createdAt: tsMs(json['created_at']),
        updatedAt: tsMs(json['updated_at']),
        tagId: json['tag_id'] as String?,
        tagTitle: json['tag_title'] as String?,
      );
}

/// What a library answer SEARCHED (4.62.0, ADR-098) — stored on the message,
/// because a client cannot recompute it from citations it already has.
///
/// [exhaustive] is false when the candidate pool came back full, so the shelf
/// was filtered out of a truncated view of the library. An empty answer then
/// means "none among the closest matches", **not** "none on this shelf", and
/// the screen may not flatten the two: the second is not a fact about the
/// shelf.
class AskScope {
  final String? tagId;
  final String? title;
  final bool exhaustive;

  const AskScope({this.tagId, this.title, this.exhaustive = true});

  static AskScope? fromJson(Object? json) {
    if (json is! Map) return null;
    return AskScope(
      tagId: json['tag_id'] as String?,
      title: json['title'] as String?,
      // Absent means exhaustive: a stored answer from before this field
      // existed searched what it searched, and the cautious sentence is the
      // one that would be claiming something the record does not say.
      exhaustive: json['exhaustive'] as bool? ?? true,
    );
  }
}

/// One citation inside a library answer.
///
/// **Denormalized on purpose** (ADR-090 §Decision 4): a thread renders from its
/// own messages, at full fidelity, without re-running retrieval. The corpus
/// moves, and a conversation whose answers change under the reader is worse
/// than no history, because it is history that lies.
///
/// The cost is that a citation can outlive its document — the stored [title]
/// and [excerpt] render either way, and opening it is what discovers a
/// deletion.
class AskCitation {
  final String? chunkId;
  final String? documentId;
  final String title;

  /// `chunk.text`, 240 chars — so **extraction markers reach it**
  /// (`[Image: …]` lives only in `text`). Rendered as Marker inline
  /// (component-kit §17.2), never stripped.
  final String excerpt;

  final String? sourceType;

  /// The document's own URL (4.63.0, ADR-099), **copied at write time and
  /// never inferred**. `null` for a stored file and an image set, which have
  /// no URL, and for every citation written before 4.63.0 — the same thing to
  /// this screen: no link to offer, and no control rather than one that goes
  /// nowhere (component-kit §6.4.2 rule 3).
  final String? sourceUrl;

  /// The blended `0.8 × cosine + 0.2 × source_priority`. The cosine and the
  /// priority are not stored: no pill displays either.
  final double? score;

  const AskCitation({
    this.chunkId,
    this.documentId,
    this.title = 'Untitled',
    this.excerpt = '',
    this.sourceType,
    this.sourceUrl,
    this.score,
  });

  factory AskCitation.fromJson(Map<String, dynamic> json) => AskCitation(
        chunkId: json['chunk_id'] as String?,
        documentId: json['document_id'] as String?,
        title: json['title'] as String? ?? 'Untitled',
        excerpt: json['excerpt'] as String? ?? '',
        sourceType: json['source_type'] as String?,
        sourceUrl: json['source_url'] as String?,
        score: (json['score'] as num?)?.toDouble(),
      );
}

/// The two kinds of block a written answer is made of (5.30.0, ADR-187;
/// `spec/data-model.md` §/ask_threads/{threadId}/messages). An unknown kind is
/// dropped at the read boundary ([askAnswer]), so nothing downstream draws it.
enum AskBlockKind { paragraph, quote }

/// One block of the library's written answer, in reading order.
///
/// A **paragraph** cites the message's own citations as `[n]` in its [text]. A
/// **quote** is a span of citation [n]'s chunk `text`, in the passage's own
/// characters — the backend proved it before storing it (INV-35), so nothing
/// on this side re-derives, trims or re-quotes it.
class AskAnswerBlock {
  final AskBlockKind kind;
  final String text;

  /// The citation a quote is from (1-based). Null on a paragraph.
  final int? n;

  const AskAnswerBlock.paragraph(this.text)
      : kind = AskBlockKind.paragraph,
        n = null;
  const AskAnswerBlock.quote(this.n, this.text) : kind = AskBlockKind.quote;

  @override
  bool operator ==(Object other) =>
      other is AskAnswerBlock &&
      other.kind == kind &&
      other.text == text &&
      other.n == n;

  @override
  int get hashCode => Object.hash(kind, text, n);

  @override
  String toString() => kind == AskBlockKind.quote
      ? 'quote($n, $text)'
      : 'paragraph($text)';
}

/// The stored `answer` as the screen reads it — web `askAnswer` in `api.js`.
///
/// Not a list → null. A block without a non-empty string `text` is dropped; a
/// `paragraph` keeps its text; a `quote` is kept only with a positive integer
/// `n` (JS `Number.isInteger`, so `1.0` counts and `"1"` does not — Dart will
/// not coerce, so the number is tested as a number). Any other kind is
/// dropped. **An answer with nothing left is no answer** (null), never an
/// empty list: an empty list would draw an answer block with nothing in it.
List<AskAnswerBlock>? askAnswer(Object? raw) {
  if (raw is! List) return null;
  final out = <AskAnswerBlock>[];
  for (final b in raw) {
    if (b is! Map) continue;
    final text = b['text'];
    if (text is! String || text.isEmpty) continue;
    final kind = b['kind'];
    if (kind == 'paragraph') {
      out.add(AskAnswerBlock.paragraph(text));
    } else if (kind == 'quote') {
      final n = b['n'];
      if (n is num && n.isFinite && n == n.truncate() && n > 0) {
        out.add(AskAnswerBlock.quote(n.toInt(), text));
      }
    }
  }
  return out.isEmpty ? null : out;
}

class AskMessage {
  final String id;
  final AskRole role;

  /// The question on a user message; **null** on a library one.
  ///
  /// Explicitly nullable rather than defaulted to `''`: a library message's
  /// prose is [answer], not this field, and an empty string would render as a
  /// blank sentence the app never wrote. (An early client composed one out of
  /// the top chunk — the app claiming to have written an answer.)
  final String? text;

  final List<AskCitation> citations;
  final int? createdAt;

  /// What this answer searched (4.62.0). `null` on a user message, on an
  /// unscoped turn, and on every answer written before 4.62.0.
  final AskScope? scope;

  /// The library's written answer (5.30.0, ADR-187; kit §25) — blocks in
  /// reading order, mapped by [askAnswer]. Null when no answer was asked for
  /// (no citations, or generative AI off), when the model's failed, and on
  /// every answer written before 5.30.0.
  final List<AskAnswerBlock>? answer;

  /// The sentence for an answer that was asked for and not written, verbatim.
  /// Null otherwise — including every answer before 5.30.0. Drawn as §25's
  /// note, never as §14: the turn succeeded and the passages are whole.
  final String? answerNote;

  const AskMessage({
    required this.id,
    required this.role,
    this.text,
    this.citations = const [],
    this.createdAt,
    this.scope,
    this.answer,
    this.answerNote,
  });

  factory AskMessage.fromJson(String id, Map<String, dynamic> json) {
    final note = json['answer_note'];
    return AskMessage(
      id: id,
      role: AskRole.fromString(json['role'] as String?),
      text: json['text'] as String?,
      citations: ((json['citations'] as List?) ?? const [])
          .whereType<Map>()
          .map((c) => AskCitation.fromJson(Map<String, dynamic>.from(c)))
          .toList(),
      createdAt: tsMs(json['created_at']),
      scope: AskScope.fromJson(json['scope']),
      answer: askAnswer(json['answer']),
      answerNote: note is String && note.isNotEmpty ? note : null,
    );
  }
}
