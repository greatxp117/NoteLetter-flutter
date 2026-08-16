/// Study programs, items and sessions (contract 2.34.0 ADR-033/INV-17;
/// reshaped 3.0.0 ADR-038/INV-19).
///
/// A study program is a scheduled recall loop over chosen sources — NOT a mode
/// of the daily letter, which is why these are three new top-level collections
/// rather than a `kind` on `/newsletters`: the daily filter is a deny-list, so
/// a third kind would leak into every shipped client's letter history.
///
/// All three are **read-only for clients** (INV-04). Every write goes through
/// an `fn_study_*` endpoint.
library;

import 'document.dart' show tsMs;

/// Grades, in SM-2 order. The vocabulary the player submits.
const studyGrades = ['again', 'hard', 'good', 'easy'];

class StudyProgram {
  const StudyProgram({
    required this.id,
    required this.title,
    required this.documentIds,
    required this.enabled,
    required this.status,
    this.deliveryTime = '07:00',
    this.timezone = 'UTC',
    this.frequency = 'daily',
    this.emailEnabled = true,
    this.emailAddress = '',
    this.newPerSession = 5,
    this.maxReviewsPerSession = 10,
    this.unitCount = 0,
    this.introducedCount = 0,
    this.sources = const {},
    this.unitStartedAt,
    this.unitNumber = 1,
    this.dismissedPrompts = const [],
    this.syllabus,
    this.createdAt,
  });

  final String id;
  final String title;

  /// 1–10, **order is the curriculum order**. Immutable after creation in v1.
  final List<String> documentIds;

  /// Scheduled delivery on/off. **Off is a pause** — SRS state and history are
  /// kept, and "Study now" still works.
  final bool enabled;

  /// **Open vocabulary**, backend-written: `active` · `maintenance` ·
  /// `complete`. Render an unknown value neutrally. `complete` is a statement
  /// about today, not a terminal state.
  final String status;

  final String deliveryTime;
  final String timezone;
  final String frequency;
  final bool emailEnabled;
  final String emailAddress;
  final int newPerSession;
  final int maxReviewsPerSession;

  /// Total chunks across [documentIds], recomputed by every build (INV-18 —
  /// chunk edits change the denominator).
  final int unitCount;

  /// Units with a study item. A **display stat, never a cursor**.
  final int introducedCount;

  /// 3.0.0 — per-source kind and reading position, keyed by document id:
  /// `{kind: "notes"|"reading", position: int|null}`.
  ///
  /// An absent entry or an unknown `kind` is treated as **`notes`**, i.e.
  /// available — because the conservative failure is showing material, never
  /// withholding it. `position` applies to `reading` only.
  final Map<String, dynamic> sources;

  /// Where the current unit began. Advanced **only** by
  /// `fn_study_advance_unit`, an explicit reader action — never by a build, an
  /// orchestrator or a date. Null means the first unit, nothing sunk.
  final int? unitStartedAt;

  /// Display counter. Never a cursor: what selection reads is [unitStartedAt].
  final int unitNumber;

  /// Assessment keys (`"<on>|<title>"`) whose unit-boundary suggestion the
  /// reader declined, so the same date cannot ask twice.
  final List<String> dismissedPrompts;

  /// Written **only** by `fn_apply_syllabus_plan`; detach removes the key.
  /// Supplies display topics and prompts only — **it paces nothing** (INV-19).
  final StudySyllabus? syllabus;

  final int? createdAt;

  /// `notes` are never withheld; a `reading` is served only as far as the
  /// reader said they have read.
  String kindFor(String documentId) {
    final k = (sources[documentId] as Map?)?['kind'] as String?;
    return k == 'reading' ? 'reading' : 'notes';
  }

  int? positionFor(String documentId) =>
      (sources[documentId] as Map?)?['position'] as int?;

  factory StudyProgram.fromJson(String id, Map<String, dynamic> json) =>
      StudyProgram(
        id: id,
        title: json['title'] as String? ?? 'Untitled',
        documentIds: (json['document_ids'] as List?)?.cast<String>() ?? const [],
        enabled: json['enabled'] as bool? ?? false,
        status: json['status'] as String? ?? 'active',
        deliveryTime: json['delivery_time'] as String? ?? '07:00',
        timezone: json['timezone'] as String? ?? 'UTC',
        frequency: json['frequency'] as String? ?? 'daily',
        emailEnabled: json['email_enabled'] as bool? ?? true,
        emailAddress: json['email_address'] as String? ?? '',
        newPerSession: json['new_per_session'] as int? ?? 5,
        maxReviewsPerSession: json['max_reviews_per_session'] as int? ?? 10,
        unitCount: json['unit_count'] as int? ?? 0,
        introducedCount: json['introduced_count'] as int? ?? 0,
        sources: (json['sources'] as Map?)?.cast<String, dynamic>() ?? const {},
        unitStartedAt: tsMs(json['unit_started_at']),
        unitNumber: json['unit_number'] as int? ?? 1,
        dismissedPrompts:
            (json['dismissed_prompts'] as List?)?.cast<String>() ?? const [],
        syllabus: json['syllabus'] == null
            ? null
            : StudySyllabus.fromJson(
                (json['syllabus'] as Map).cast<String, dynamic>()),
        createdAt: tsMs(json['created_at']),
      );
}

class StudySyllabus {
  const StudySyllabus({
    required this.documentId,
    required this.units,
    required this.assessments,
    this.appliedAt,
  });

  final String documentId;

  /// `{topic, starts_on}` — **display texture only**. A unit here is a syllabus
  /// ROW, not a unit of study (which is the content between examinations,
  /// ADR-038 §1), and `starts_on` gates nothing.
  final List<Map<String, dynamic>> units;

  /// `{title, on, assessment_kind, cumulative}`. Open vocabulary defaulting to
  /// `exam` — a parser ignoring the field degrades to proposing a boundary the
  /// reader can decline, never to silence. **Only `exam` ramps reviews and
  /// raises a unit-boundary suggestion**; a `paper` does nothing, because
  /// writing an essay is not being tested.
  final List<Map<String, dynamic>> assessments;

  final int? appliedAt;

  factory StudySyllabus.fromJson(Map<String, dynamic> j) => StudySyllabus(
        documentId: j['document_id'] as String? ?? '',
        units: ((j['units'] as List?) ?? const [])
            .map((u) => (u as Map).cast<String, dynamic>())
            .toList(),
        assessments: ((j['assessments'] as List?) ?? const [])
            .map((a) => (a as Map).cast<String, dynamic>())
            .toList(),
        appliedAt: tsMs(j['applied_at']),
      );
}

class StudySession {
  const StudySession({
    required this.id,
    required this.programId,
    required this.programTitle,
    required this.status,
    required this.items,
    required this.responses,
    this.generatedAt,
    this.trigger = 'manual',
    this.newCount = 0,
    this.reviewCount = 0,
    this.dueRemaining = 0,
    this.rampCount = 0,
    this.errorMessage,
  });

  final String id;
  final String programId;

  /// Denormalized so a session survives its program's deletion as history.
  final String programTitle;

  /// **Open vocabulary**: `generating` → `sent` · `email_failed` · `empty` ·
  /// `error`. Unknown values render as informational.
  final String status;

  final List<StudySessionItem> items;

  /// `{qid: {grade, answer_text?, graded_at}}` — written only by
  /// `fn_submit_study_answer`, and reconciled LIVE by the single-doc
  /// subscription, which is what makes a session resumable.
  final Map<String, dynamic> responses;

  final int? generatedAt;
  final String trigger;
  final int newCount;
  final int reviewCount;
  final int dueRemaining;

  /// Reviews the exam ramp pulled forward (0 without a syllabus or outside an
  /// exam window).
  final int rampCount;

  final String? errorMessage;

  /// Whether the player may take grades.
  ///
  /// Gated on STATUS, never on item count: the build writes the full `items`
  /// array under `generating` **before** the questions are drawn, so a reader
  /// arriving from the email CTA would otherwise see a gradable list whose
  /// every grade came back rejected (2.37.2).
  bool get gradable => status == 'sent' || status == 'email_failed';

  factory StudySession.fromJson(String id, Map<String, dynamic> json) =>
      StudySession(
        id: id,
        programId: json['program_id'] as String? ?? '',
        programTitle: json['program_title'] as String? ?? 'Study',
        status: json['status'] as String? ?? 'generating',
        items: ((json['items'] as List?) ?? const [])
            .map((i) => StudySessionItem.fromJson((i as Map).cast<String, dynamic>()))
            .toList(),
        responses:
            (json['responses'] as Map?)?.cast<String, dynamic>() ?? const {},
        generatedAt: tsMs(json['generated_at']),
        trigger: json['trigger'] as String? ?? 'manual',
        newCount: json['new_count'] as int? ?? 0,
        reviewCount: json['review_count'] as int? ?? 0,
        dueRemaining: json['due_remaining'] as int? ?? 0,
        rampCount: json['ramp_count'] as int? ?? 0,
        errorMessage: json['error_message'] as String?,
      );
}

class StudySessionItem {
  const StudySessionItem({
    required this.itemId,
    required this.chunkId,
    required this.documentId,
    required this.kind,
    required this.title,
    required this.excerptHtml,
    required this.questions,
    this.ramp = false,
  });

  final String itemId;
  final String chunkId;
  final String documentId;

  /// `new` | `review`.
  final String kind;

  final String title;

  /// The chunk's own sanitized html, truncated (INV-10 vocabulary).
  final String excerptHtml;

  /// `{qid, question, answer}` — generated once at introduction and reused
  /// **verbatim** on every review. Stable questions are the point.
  final List<Map<String, dynamic>> questions;

  /// Present only when true: a review the exam ramp pulled forward. Absence
  /// means an ordinary due review.
  final bool ramp;

  factory StudySessionItem.fromJson(Map<String, dynamic> j) => StudySessionItem(
        itemId: j['item_id'] as String? ?? '',
        chunkId: j['chunk_id'] as String? ?? '',
        documentId: j['document_id'] as String? ?? '',
        kind: j['kind'] as String? ?? 'review',
        title: j['title'] as String? ?? '',
        excerptHtml: j['excerpt_html'] as String? ?? '',
        questions: ((j['questions'] as List?) ?? const [])
            .map((q) => (q as Map).cast<String, dynamic>())
            .toList(),
        ramp: j['ramp'] as bool? ?? false,
      );
}
