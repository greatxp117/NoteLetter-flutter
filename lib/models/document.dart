import 'package:cloud_firestore/cloud_firestore.dart';

enum DocumentStatus {
  pendingUpload,
  queued,
  processing,
  complete,
  error,
  skipped;

  static DocumentStatus fromString(String? s) {
    switch (s) {
      case 'pending_upload':
        return DocumentStatus.pendingUpload;
      case 'queued':
        return DocumentStatus.queued;
      case 'processing':
        return DocumentStatus.processing;
      case 'complete':
        return DocumentStatus.complete;
      case 'skipped':
        return DocumentStatus.skipped;
      default:
        return DocumentStatus.error;
    }
  }
}

/// Epoch-ms conversion at the read boundary (INV-06) — null-safe, never
/// passes a raw Firestore Timestamp into UI/state.
int? tsMs(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.millisecondsSinceEpoch;
  if (value is int) return value;
  return null;
}

/// `/documents/{docId}` — field skeleton per contract data-model.md.
/// `embedding` is not a document field (only chunks carry it); nothing to
/// strip here (INV-05 applies to chunk/tag reads).
///
/// Tags are read from `tag_ids` (data-model.md) — the 1.0.0 spec named this
/// `tags`, which was extraction drift; the backend has always written
/// `tag_ids`. Docs created before 1.1.0 also carry a vestigial empty `tags`
/// field, so reading `tags` would drop their real tags — read `tag_ids` only.
///
/// Deliberately absent: `display_html` (1.1.0, ADR-002 — no longer stored;
/// clients assemble reading content from chunks) and `questions` (1.5.0,
/// ADR-008 — deprecated; summaries are free-structured prose, no client
/// renders "Questions to consider").
class Document {
  final String id;
  final String userId;
  final String title;
  final String type;
  final String? mimeType;
  final DocumentStatus status;
  final String? sourceUrl;
  final String? gcsPath;
  final int? createdAt;
  final int? processedAt;
  final int? chunkCount;
  final int? wordCount;
  final String? summary;
  final List<String> keyPoints;
  final List<String> themes;
  final List<String> tagIds;
  final String? thumbnailUrl;

  /// podcast only (2.7.0, ADR-016): the resolved RSS `<enclosure>` MP3 URL, so
  /// the reader can play the real episode against the transcript's real
  /// timestamps. Null for every other type and every pre-2.7.0 doc.
  final String? sourceAudioUrl;

  /// article-from-screenshot only (2.8.0, ADR-017): a durable, directly
  /// renderable URL to the captured screenshot, carried as the document's
  /// SECOND source alongside [sourceUrl]. Provenance, not content — never in
  /// chunk HTML. Null for every other document and every pre-2.8.0 doc.
  final String? sourceImageUrl;

  /// 2.13.0 (ADR-020) — the source's own byline. Extracted on every URL ingest
  /// since 1.0.0 and persisted by nobody until 2.13.0, so null on every older
  /// document and on every source with no byline (pdf/docx/image/plain).
  final String? author;

  /// 2.13.0 — an ISO `YYYY-MM-DD` **string**, deliberately NOT a Timestamp:
  /// INV-06 does not apply. It is the source's claim about itself, not an
  /// instant we observed, and converting it renders an article published
  /// "January 3" as "January 2" for every reader west of UTC. Format it as a
  /// calendar date with no timezone conversion, and never substitute
  /// [createdAt] — "when you saved it" and "when it was published" differ.
  final String? publishDate;

  /// 2.19.0 (ADR-024) — which half of the pipeline is running. Meaningful ONLY
  /// while [status] is processing, cleared at every terminal write. Open
  /// vocabulary (`extraction` | `embedding` today): render an unknown value
  /// neutrally, never as an error, and never render the raw token to a user.
  final String? processingStage;

  /// 3.1.0 (ADR-039) — the reader finished this document. Written ONLY by
  /// `fn_set_read_state`, never by a client, and reversible. Deliberately not
  /// derivable from chunk coverage: reading every passage and declaring
  /// yourself done are different claims, and only the second is reversible.
  final int? finishedAt;

  /// 2.31.2 (ADR-032, INV-16) — the reader pinned this source for the next
  /// letter. A Timestamp rather than a boolean so overflow beyond the per-letter
  /// cap is carried oldest-first rather than dropped. Cleared only by a letter
  /// that actually carried the document.
  final int? nextLetterRequestedAt;

  final String? errorMessage;

  /// 4.47.0 (ADR-085) — the owner's standing instruction to index this document
  /// even where the image classifier would decline to. Written `true` only by
  /// `fn_retry_document {force: true}` and never cleared, so a `skipped`
  /// document carrying it has already had its appeal heard. Absent (→ false) on
  /// every document nobody has forced.
  final bool forceProcess;

  /// 4.48.0 (ADR-085 §7) — why a `skipped` document was skipped. **Closed**
  /// vocabulary, unlike `image_classification`, so a client may switch on it:
  /// `no_text_content` · `unresolved_article`. `null` on every non-skipped
  /// document. The distinction drives the row: the appeal stays on offer on
  /// `unresolved_article` even after `force_process` is true. Its reason changed
  /// at 4.60.0 (ADR-085 §8) — a forced run no longer runs the lookup at all, so
  /// that pair can no longer be produced, and the clause is now the rescue for
  /// the documents stranded in it by the old rule, which without it would have
  /// no control at all.
  final String? skipReason;

  final double sourcePriority;

  /// INV-03a — OPENED. Bumped by `doc_opened` and, since 4.0.0, by nothing
  /// else: expanding a search hit no longer clears a source's unread dot.
  final int viewCount;
  final int? lastViewedAt;

  /// 4.6.0 (ADR-042) — the shape this document's content was reduced to,
  /// independent of `type`: `recipe` today. **Open vocabulary**, so no client
  /// switches exhaustively on it. Non-null means the stored chunks are a
  /// DISTILLATION, not the source's full text.
  final String? contentForm;

  /// 4.6.0 (ADR-042) — a durable, directly renderable URL holding the full
  /// pre-distillation HTML. Provenance, **not** content: never chunked, never
  /// embedded, never in any chunk HTML. Non-null whenever [contentForm] is
  /// (INV-20b), and it is the honesty guarantee for a reduction — which is why
  /// the Original panel must offer it and nothing else may render it.
  final String? originalContentUrl;

  /// 4.6.0 (ADR-042) — the structured recipe; present iff
  /// `content_form == "recipe"`.
  final Recipe? recipe;

  /// `{ job_id, provider }` when this document was imported from a cloud
  /// provider (data-model.md). Drives the Reader source-freshness check (1.4.0).
  final Map<String, dynamic>? sourceIntegration;

  const Document({
    required this.id,
    required this.userId,
    required this.title,
    required this.type,
    required this.status,
    this.mimeType,
    this.sourceUrl,
    this.gcsPath,
    this.createdAt,
    this.processedAt,
    this.chunkCount,
    this.wordCount,
    this.summary,
    this.keyPoints = const [],
    this.themes = const [],
    this.tagIds = const [],
    this.thumbnailUrl,
    this.sourceAudioUrl,
    this.sourceImageUrl,
    this.author,
    this.publishDate,
    this.processingStage,
    this.finishedAt,
    this.nextLetterRequestedAt,
    this.errorMessage,
    this.forceProcess = false,
    this.skipReason,
    this.sourcePriority = 0.5,
    this.viewCount = 0,
    this.lastViewedAt,
    this.contentForm,
    this.originalContentUrl,
    this.recipe,
    this.sourceIntegration,
  });

  /// Apply an `fn_regenerate_summary` response (4.3.0, ADR-040).
  ///
  /// Deliberately narrow rather than a general `copyWith`: regeneration moves
  /// **exactly** `summary`, `key_points` and `themes`. The title never changes
  /// (it ripples into lists, letters and activity), and neither do passages,
  /// shelves or any counter. A general copyWith here would make it possible to
  /// carry a field the endpoint never returned, and the reader document is a
  /// one-shot fetch with no subscription to correct it.
  Document withRegeneratedSummary(Map<String, dynamic> res) {
    return Document(
      id: id,
      userId: userId,
      title: title,
      type: type,
      status: status,
      mimeType: mimeType,
      sourceUrl: sourceUrl,
      gcsPath: gcsPath,
      createdAt: createdAt,
      processedAt: processedAt,
      chunkCount: chunkCount,
      wordCount: wordCount,
      summary: res['summary'] as String? ?? summary,
      keyPoints: (res['keyPoints'] as List?)?.cast<String>() ?? keyPoints,
      themes: (res['themes'] as List?)?.cast<String>() ?? themes,
      tagIds: tagIds,
      thumbnailUrl: thumbnailUrl,
      sourceAudioUrl: sourceAudioUrl,
      sourceImageUrl: sourceImageUrl,
      author: author,
      publishDate: publishDate,
      processingStage: processingStage,
      finishedAt: finishedAt,
      nextLetterRequestedAt: nextLetterRequestedAt,
      errorMessage: errorMessage,
      forceProcess: forceProcess,
      skipReason: skipReason,
      sourcePriority: sourcePriority,
      viewCount: viewCount,
      lastViewedAt: lastViewedAt,
      contentForm: contentForm,
      originalContentUrl: originalContentUrl,
      recipe: recipe,
      sourceIntegration: sourceIntegration,
    );
  }

  /// Fold in the counters a confirmed `doc_opened` write committed
  /// (`screens/reader.md` §Data).
  ///
  /// Narrow for the same reason [withRegeneratedSummary] is: `doc_opened`
  /// moves **exactly** `view_count` and `last_viewed_at`, and it is applied
  /// only once the transaction has confirmed — never a guess made before it
  /// (ADR-022). Rendering the fetched snapshot unmodified is what showed
  /// `Views 0 · Last read Never` for a whole session on a first open.
  Document withReadLogged({required int viewCount, required int lastViewedAt}) {
    return Document(
      id: id,
      userId: userId,
      title: title,
      type: type,
      status: status,
      mimeType: mimeType,
      sourceUrl: sourceUrl,
      gcsPath: gcsPath,
      createdAt: createdAt,
      processedAt: processedAt,
      chunkCount: chunkCount,
      wordCount: wordCount,
      summary: summary,
      keyPoints: keyPoints,
      themes: themes,
      tagIds: tagIds,
      thumbnailUrl: thumbnailUrl,
      sourceAudioUrl: sourceAudioUrl,
      sourceImageUrl: sourceImageUrl,
      author: author,
      publishDate: publishDate,
      processingStage: processingStage,
      finishedAt: finishedAt,
      nextLetterRequestedAt: nextLetterRequestedAt,
      errorMessage: errorMessage,
      forceProcess: forceProcess,
      skipReason: skipReason,
      sourcePriority: sourcePriority,
      viewCount: viewCount,
      lastViewedAt: lastViewedAt,
      contentForm: contentForm,
      originalContentUrl: originalContentUrl,
      recipe: recipe,
      sourceIntegration: sourceIntegration,
    );
  }

  factory Document.fromJson(String id, Map<String, dynamic> json) {
    return Document(
      id: id,
      userId: json['user_id'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled',
      type: json['type'] as String? ?? 'unknown',
      mimeType: json['mime_type'] as String?,
      status: DocumentStatus.fromString(json['status'] as String?),
      sourceUrl: json['source_url'] as String?,
      gcsPath: json['gcs_path'] as String?,
      createdAt: tsMs(json['created_at']),
      processedAt: tsMs(json['processed_at']),
      chunkCount: json['chunk_count'] as int?,
      wordCount: json['word_count'] as int?,
      summary: json['summary'] as String?,
      keyPoints: (json['key_points'] as List?)?.cast<String>() ?? [],
      themes: (json['themes'] as List?)?.cast<String>() ?? [],
      tagIds: (json['tag_ids'] as List?)?.cast<String>() ?? [],
      thumbnailUrl: json['thumbnail_url'] as String?,
      sourceAudioUrl: json['source_audio_url'] as String?,
      sourceImageUrl: json['source_image_url'] as String?,
      author: json['author'] as String?,
      // NOT tsMs(): publish_date is an ISO date STRING, not a Timestamp.
      publishDate: json['publish_date'] as String?,
      processingStage: json['processing_stage'] as String?,
      finishedAt: tsMs(json['finished_at']),
      nextLetterRequestedAt: tsMs(json['next_letter_requested_at']),
      errorMessage: json['error_message'] as String?,
      forceProcess: json['force_process'] as bool? ?? false,
      skipReason: json['skip_reason'] as String?,
      sourcePriority: (json['source_priority'] as num?)?.toDouble() ?? 0.5,
      viewCount: json['view_count'] as int? ?? 0,
      lastViewedAt: tsMs(json['last_viewed_at']),
      contentForm: json['content_form'] as String?,
      originalContentUrl: json['original_content_url'] as String?,
      // Present iff `content_form == "recipe"`, but read off its own field:
      // `content_form` is an OPEN vocabulary and a client that gated the
      // object on a value it recognises would drop the structure the first
      // time the backend names a second form.
      recipe: (json['recipe'] as Map?) == null
          ? null
          : Recipe.fromJson((json['recipe'] as Map).cast<String, dynamic>()),
      sourceIntegration: (json['source_integration'] as Map?)?.cast<String, dynamic>(),
    );
  }
}

/// One ingredient group (`recipe.ingredients[]`, 4.6.0 ADR-042).
///
/// [group] is `null` where the source did not group — and a single-group
/// recipe renders no heading at all (§5.4): a heading invented over an
/// ungrouped list says the source made a distinction it did not make.
class RecipeGroup {
  final String? group;
  final List<String> items;

  const RecipeGroup({this.group, this.items = const []});

  factory RecipeGroup.fromJson(Map<String, dynamic> j) => RecipeGroup(
        group: j['group'] as String?,
        items: (j['items'] as List?)?.map((e) => '$e').toList() ?? const [],
      );
}

/// One method step (`recipe.steps[]`).
///
/// [start] is a float seconds offset **or null**, and null far more often than
/// not: INV-20(c) makes the backend refuse to estimate rather than guess. A
/// client MUST NOT fill the gap — no interpolation, no proportional guess, no
/// falling back to the manuscript's own `data-start` (a distilled document has
/// none). Showing the time without making it seek conforms; seeking to the
/// wrong place does not.
class RecipeStep {
  final String text;
  final String? imageId;
  final double? start;

  const RecipeStep({required this.text, this.imageId, this.start});

  factory RecipeStep.fromJson(Map<String, dynamic> j) => RecipeStep(
        text: j['text'] as String? ?? '',
        imageId: j['image_id'] as String?,
        start: (j['start'] as num?)?.toDouble(),
      );
}

/// The structured recipe (`document.recipe`, 4.6.0 ADR-042) — present iff
/// `content_form == "recipe"`.
///
/// It is **not** what makes the document readable: the chunk HTML already IS
/// the recipe (ADR-042 §3), so a client that reads none of these fields still
/// renders a complete one. What the structure buys is the checkable list, the
/// step-bound pictures and the step times.
///
/// [yield_] and the three times are **strings as the source stated them**, and
/// `null` where it did not state them — never inferred, the same posture as
/// `author`/`publish_date`. An omitted stat is ABSENT from the row, never a
/// zero and never an em-dash: a placeholder reads as a measured value.
class Recipe {
  final String title;
  final String? yield_;
  final String? prepTime;
  final String? cookTime;
  final String? totalTime;
  final List<RecipeGroup> ingredients;
  final List<RecipeStep> steps;
  final List<String> notes;

  /// `data-nl-image-id` content hashes matching `images[]` — the pictures no
  /// step claimed, rendered as the trailing gallery (the first is the lead).
  final List<String> gallery;

  const Recipe({
    required this.title,
    this.yield_,
    this.prepTime,
    this.cookTime,
    this.totalTime,
    this.ingredients = const [],
    this.steps = const [],
    this.notes = const [],
    this.gallery = const [],
  });

  factory Recipe.fromJson(Map<String, dynamic> j) => Recipe(
        title: j['title'] as String? ?? '',
        yield_: j['yield'] as String?,
        prepTime: j['prep_time'] as String?,
        cookTime: j['cook_time'] as String?,
        totalTime: j['total_time'] as String?,
        ingredients: (j['ingredients'] as List?)
                ?.whereType<Map>()
                .map((e) => RecipeGroup.fromJson(e.cast<String, dynamic>()))
                .toList() ??
            const [],
        steps: (j['steps'] as List?)
                ?.whereType<Map>()
                .map((e) => RecipeStep.fromJson(e.cast<String, dynamic>()))
                .toList() ??
            const [],
        notes: (j['notes'] as List?)?.map((e) => '$e').toList() ?? const [],
        gallery: (j['gallery'] as List?)?.map((e) => '$e').toList() ?? const [],
      );
}
