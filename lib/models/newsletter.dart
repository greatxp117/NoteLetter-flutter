import 'document.dart' show tsMs;

/// `/newsletters/{newsletterId}` — read-only; never construct IDs, query by
/// `generated_at desc` (INV-09).
class Newsletter {
  final String id;
  final String userId;
  final int? generatedAt;
  final String html;
  final String trigger;

  /// `generating | sent | error | empty` (2.2.0, ADR-011) — vocabulary is
  /// OPEN: an unknown status renders as informational, never as a failure.
  final String status;

  /// Client-visible failure/skip reason; set on `error` and `empty`.
  final String? errorMessage;

  /// 2.24.0 (ADR-029) — `daily` | `scripture`. **Absent means `daily`**, so
  /// every pre-2.24.0 record is already correct and there is no backfill.
  ///
  /// Filter with `kind != 'scripture'`, **NEVER** `kind == 'daily'`: equality
  /// would drop a real user's entire pre-2.24.0 history, which is most of it.
  final String? kind;

  bool get isScripture => kind == 'scripture';

  /// 2.26.0 (ADR-030) — the strongest verse source across the day's readings.
  final String? verseSource;
  final String? verseEdition;

  /// 2.24.0 — **the reader owns an edition of their own.** Do NOT read `false`
  /// as "we had no verse text": it was `false` on every record ever written
  /// before 2.26.0, and since then a letter can carry text without the reader
  /// owning a bible (`verseSource == 'system'`).
  final bool bibleOnShelf;

  /// The computed liturgical day, a `YYYY-MM-DD` **date string** (ADR-027 §4).
  final String? liturgicalDay;

  /// Stored AS SENT, so "5 of 23" stays honest even as the library grows.
  final int? passagesSent;
  final int? passagesFound;

  const Newsletter({
    required this.id,
    required this.userId,
    this.generatedAt,
    required this.html,
    required this.trigger,
    required this.status,
    this.errorMessage,
    this.kind,
    this.verseSource,
    this.verseEdition,
    this.bibleOnShelf = false,
    this.liturgicalDay,
    this.passagesSent,
    this.passagesFound,
  });

  factory Newsletter.fromJson(String id, Map<String, dynamic> json) {
    return Newsletter(
      id: id,
      userId: json['user_id'] as String? ?? '',
      generatedAt: tsMs(json['generated_at']),
      html: json['html'] as String? ?? '',
      trigger: json['trigger'] as String? ?? 'scheduled',
      status: json['status'] as String? ?? '',
      errorMessage: json['error_message'] as String?,
      kind: json['kind'] as String?,
      verseSource: json['verse_source'] as String?,
      verseEdition: json['verse_edition'] as String?,
      bibleOnShelf: json['bible_on_shelf'] as bool? ?? false,
      liturgicalDay: json['liturgical_day'] as String?,
      passagesSent: json['passages_sent'] as int?,
      passagesFound: json['passages_found'] as int?,
    );
  }

  /// A row is a readable letter only when it was actually rendered and sent.
  /// `empty`/`error` (and any future non-`sent` status) carry no `html` to
  /// preview — they are informational history rows.
  bool get isReadable => status == 'sent' && html.isNotEmpty;
}
