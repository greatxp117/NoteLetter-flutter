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

  const AskThread({
    required this.id,
    this.title = '',
    this.preview = '',
    this.messageCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  /// INV-06: every timestamp becomes epoch ms at the read boundary.
  factory AskThread.fromJson(String id, Map<String, dynamic> json) => AskThread(
        id: id,
        title: json['title'] as String? ?? '',
        preview: json['preview'] as String? ?? '',
        messageCount: (json['message_count'] as num?)?.toInt() ?? 0,
        createdAt: tsMs(json['created_at']),
        updatedAt: tsMs(json['updated_at']),
      );
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

  /// The blended `0.8 × cosine + 0.2 × source_priority`. The cosine and the
  /// priority are not stored: no pill displays either.
  final double? score;

  const AskCitation({
    this.chunkId,
    this.documentId,
    this.title = 'Untitled',
    this.excerpt = '',
    this.sourceType,
    this.score,
  });

  factory AskCitation.fromJson(Map<String, dynamic> json) => AskCitation(
        chunkId: json['chunk_id'] as String?,
        documentId: json['document_id'] as String?,
        title: json['title'] as String? ?? 'Untitled',
        excerpt: json['excerpt'] as String? ?? '',
        sourceType: json['source_type'] as String?,
        score: (json['score'] as num?)?.toDouble(),
      );
}

class AskMessage {
  final String id;
  final AskRole role;

  /// The question on a user message; **null** on a library one.
  ///
  /// Explicitly nullable rather than defaulted to `''`: Ask is retrieval-only,
  /// so a library message HAS no prose, and an empty string would render as a
  /// blank sentence the app never wrote. (The previous client composed one out
  /// of the top chunk — the app claiming to have written an answer.)
  final String? text;

  final List<AskCitation> citations;
  final int? createdAt;

  const AskMessage({
    required this.id,
    required this.role,
    this.text,
    this.citations = const [],
    this.createdAt,
  });

  factory AskMessage.fromJson(String id, Map<String, dynamic> json) =>
      AskMessage(
        id: id,
        role: AskRole.fromString(json['role'] as String?),
        text: json['text'] as String?,
        citations: ((json['citations'] as List?) ?? const [])
            .whereType<Map>()
            .map((c) => AskCitation.fromJson(Map<String, dynamic>.from(c)))
            .toList(),
        createdAt: tsMs(json['created_at']),
      );
}
