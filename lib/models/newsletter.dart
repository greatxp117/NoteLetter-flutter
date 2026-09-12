import 'document.dart' show tsMs;

/// `/newsletters/{newsletterId}` — read-only; never construct IDs, query by
/// `generated_at desc` (INV-09).
class Newsletter {
  final String id;
  final String userId;
  final int? generatedAt;

  /// The email's subject. Present since 2.0.0 on a `daily` record and since
  /// 4.24.0 on a `scripture` one — which a client is free to ignore, because a
  /// readings letter is filed by its DAY and the subject exists for the mailbox.
  final String? subject;

  /// **The letter.** `html_body` is what every build since 2.0.0 has written
  /// and what a client renders (4.50.0, ADR-087).
  final String htmlBody;

  /// The plain-text part. Read for one thing only: the row lede of a letter
  /// written before the letterhead (see [lede]).
  final String textBody;

  /// The pre-2.0.0 rendered email. **Nothing has written it since**, and no
  /// client renders it — it is modelled because the emulator seed and a real
  /// archive both still hold records that carry only this.
  final String html;

  final String trigger;

  /// `generating | sent | error | empty`, plus `email_failed` on a `scripture`
  /// record (4.24.0, ADR-061) — vocabulary is OPEN: an unknown status renders
  /// as informational, never as a failure.
  final String status;

  /// Client-visible failure/skip reason; set on `error`, `empty` and
  /// `email_failed`.
  final String? errorMessage;

  /// Exactly the passages [htmlBody] holds (4.39.0, ADR-077) — so its length
  /// is the letter's passage count, not an estimate.
  final List<String> chunkIds;

  /// 2.24.0 (ADR-029) — `daily` | `scripture`. **Absent means `daily`**, so
  /// every pre-2.24.0 record is already correct and there is no backfill.
  ///
  /// Filter with `kind != 'scripture'`, **NEVER** `kind == 'daily'`: equality
  /// would drop a real user's entire pre-2.24.0 history, which is most of it.
  final String? kind;

  bool get isScripture => kind == 'scripture';

  /// 4.22.0 (ADR-059, INV-23) — what the mail provider's own events say
  /// happened AFTER it accepted the message. **Absent means unknown, never
  /// failed**: no record written before 4.22.0 has one and there is no
  /// backfill.
  final LetterDelivery? delivery;

  /// 2.26.0 (ADR-030) — the strongest verse source across the day's readings.
  final String? verseSource;
  final String? verseEdition;

  /// 2.24.0 — **the reader owns an edition of their own.** Do NOT read `false`
  /// as "we had no verse text": it was `false` on every record ever written
  /// before 2.26.0, and since then a letter can carry text without the reader
  /// owning a bible (`verseSource == 'system'`).
  final bool bibleOnShelf;

  /// The computed liturgical day (`scripture` only) — a **map**, the whole of
  /// `lectionary.identify()`. It carries a `date` inside it, which is the
  /// `YYYY-MM-DD` string ADR-027 §4 is about; the FIELD is not that string.
  /// This was modelled as `String?` here, and `as String?` over a map **throws**
  /// — so `Newsletter.fromJson` could not read any real readings letter at all.
  final LiturgicalDay? liturgicalDay;

  /// Per reading: its label, citation and the passages that answered it.
  final List<LetterReading> readings;

  /// Stored AS SENT, so "5 of 23" stays honest even as the library grows.
  final int? passagesSent;
  final int? passagesFound;

  const Newsletter({
    required this.id,
    required this.userId,
    this.generatedAt,
    this.subject,
    this.htmlBody = '',
    this.textBody = '',
    this.html = '',
    required this.trigger,
    required this.status,
    this.errorMessage,
    this.chunkIds = const [],
    this.kind,
    this.delivery,
    this.verseSource,
    this.verseEdition,
    this.bibleOnShelf = false,
    this.liturgicalDay,
    this.readings = const [],
    this.passagesSent,
    this.passagesFound,
  });

  factory Newsletter.fromJson(String id, Map<String, dynamic> json) {
    return Newsletter(
      id: id,
      userId: json['user_id'] as String? ?? '',
      generatedAt: tsMs(json['generated_at']),
      subject: json['subject'] as String?,
      htmlBody: json['html_body'] as String? ?? '',
      textBody: json['text_body'] as String? ?? '',
      html: json['html'] as String? ?? '',
      trigger: json['trigger'] as String? ?? 'scheduled',
      status: json['status'] as String? ?? '',
      errorMessage: json['error_message'] as String?,
      chunkIds:
          (json['chunk_ids'] as List?)?.whereType<String>().toList() ?? const [],
      kind: json['kind'] as String?,
      delivery: LetterDelivery.fromJson(
          (json['delivery'] as Map?)?.cast<String, dynamic>()),
      verseSource: json['verse_source'] as String?,
      verseEdition: json['verse_edition'] as String?,
      bibleOnShelf: json['bible_on_shelf'] as bool? ?? false,
      liturgicalDay: LiturgicalDay.fromJson(
          (json['liturgical_day'] as Map?)?.cast<String, dynamic>()),
      readings: (json['readings'] as List?)
              ?.whereType<Map>()
              .map((r) => LetterReading.fromJson(r.cast<String, dynamic>()))
              .toList() ??
          const [],
      passagesSent: json['passages_sent'] as int?,
      passagesFound: json['passages_found'] as int?,
    );
  }

  /// A letter that **brings its own letterhead** (4.50.0, ADR-087): seal,
  /// masthead, folio, theme, note, contents, cards and foot. A client hosts
  /// such a body BARE and adds no frame of its own.
  ///
  /// The test is the ATTRIBUTE, never a version or a date — the archive holds
  /// both shapes forever, and deciding by the body itself is what lets an old
  /// letter and a new one both render correctly, in either deploy order.
  bool get hasLetterhead => htmlBody.contains('data-nl-letterhead');

  /// The one line a row quotes when it shows a letter **without opening it**.
  ///
  /// A letter with a letterhead names its own: the librarian's note carries
  /// `data-nl-lede="1"`. Without the marker the lede is the head of
  /// `text_body`, as it always was — the head of a letterheaded body is the
  /// masthead and the folio, which reads the same in every letter, so a list
  /// built from it would say nothing about any row.
  String get lede {
    if (hasLetterhead) {
      final m = _ledeRe.firstMatch(htmlBody);
      if (m != null) {
        final text = _stripTags(m.group(2) ?? '');
        if (text.isNotEmpty) return _clip(text);
      }
    }
    return _clip(_collapse(textBody));
  }

  /// Only a letter that was actually BUILT has a body to open into a reader.
  /// `empty`/`error`/`generating` rows are informational history rows — and a
  /// **bounced** letter is still openable: it exists, it just never reached the
  /// mailbox, which INV-23 keeps as a separate question from whether it built.
  bool get isReadable => htmlBody.isNotEmpty;
}

/// The `delivery` map (4.22.0, ADR-059, INV-23).
class LetterDelivery {
  /// `accepted` → `deferred` → `delivered` → `bounced` | `dropped` → `spam`.
  /// **Open for reading** — an unrecognised state says nothing rather than
  /// asserting a problem.
  final String state;

  /// The provider's own sentence: the SMTP refusal, or the suppression cause.
  /// This is the *why*, and the only reason the record is worth keeping.
  final String? detail;
  final String? mxServer;
  final int attempts;

  const LetterDelivery({
    required this.state,
    this.detail,
    this.mxServer,
    this.attempts = 0,
  });

  static LetterDelivery? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final state = json['state'] as String?;
    if (state == null || state.isEmpty) return null;
    return LetterDelivery(
      state: state,
      detail: json['detail'] as String?,
      mxServer: json['mx_server'] as String?,
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
    );
  }
}

/// One reading of the day, and what the library answered it with.
class LetterReading {
  final String label;
  final String ref;
  final bool lead;

  /// `false` when the citation itself could not be read — which says something
  /// different from "nothing matched", and must not be shown as an empty
  /// library.
  final bool parsed;
  final List<LetterPassage> passages;
  final int matchTotal;

  const LetterReading({
    required this.label,
    required this.ref,
    this.lead = false,
    this.parsed = true,
    this.passages = const [],
    this.matchTotal = 0,
  });

  factory LetterReading.fromJson(Map<String, dynamic> json) => LetterReading(
        label: json['label'] as String? ?? '',
        ref: json['ref'] as String? ?? '',
        lead: json['lead'] as bool? ?? false,
        // Absent means the citation parsed — `parsed: false` is written only
        // when it did not. An `?? false` here would report every reading in
        // every letter written before the field as unreadable.
        parsed: json['parsed'] as bool? ?? true,
        passages: (json['passages'] as List?)
                ?.whereType<Map>()
                .map((p) => LetterPassage.fromJson(p.cast<String, dynamic>()))
                .toList() ??
            const [],
        matchTotal: (json['match_total'] as num?)?.toInt() ?? 0,
      );
}

class LetterPassage {
  final String chunkId;
  final String documentId;
  final String text;

  const LetterPassage({
    this.chunkId = '',
    this.documentId = '',
    this.text = '',
  });

  factory LetterPassage.fromJson(Map<String, dynamic> json) => LetterPassage(
        chunkId: json['chunk_id'] as String? ?? '',
        documentId: json['document_id'] as String? ?? '',
        text: json['text'] as String? ?? '',
      );
}

/// `liturgical_day` — the computed day, as `lectionary.identify()` returns it.
class LiturgicalDay {
  final String? name;
  final String? season;
  final int? week;
  final String? weekday;
  final String? cycle;
  final String? liturgicalYear;

  /// The calendar date, `YYYY-MM-DD` (ADR-027 §4 — a date, not an instant).
  final String? date;

  /// The temporal key. Safe to show a reader in a "no readings yet" message.
  final String? dayId;

  const LiturgicalDay({
    this.name,
    this.season,
    this.week,
    this.weekday,
    this.cycle,
    this.liturgicalYear,
    this.date,
    this.dayId,
  });

  static LiturgicalDay? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return LiturgicalDay(
      name: json['name'] as String?,
      season: json['season'] as String?,
      week: (json['week'] as num?)?.toInt(),
      weekday: json['weekday'] as String?,
      cycle: json['cycle'] as String?,
      liturgicalYear: json['liturgical_year']?.toString(),
      date: json['date'] as String?,
      dayId: json['id'] as String?,
    );
  }

  /// The day's name as the lectionary gives it, with a readable fallback
  /// composed from the parts `identify()` always returns.
  String get title {
    if (name != null && name!.isNotEmpty) return name!;
    final w = week != null ? ' of week $week' : '';
    final s = season != null ? ' in ${season!.replaceAll('_', ' ')}' : '';
    final d = (weekday == null || weekday!.isEmpty)
        ? 'Today'
        : weekday![0].toUpperCase() + weekday!.substring(1);
    return '$d$w$s'.trim();
  }

  /// `Cycle B · 2026`, or as much of it as the record carries.
  String get cycleLine => [
        if (cycle != null && cycle!.isNotEmpty) 'Cycle $cycle',
        if (liturgicalYear != null && liturgicalYear!.isNotEmpty) liturgicalYear,
      ].join(' · ');
}

/// The librarian's note, by its marker. Read the MARKER, never a position or an
/// English phrase.
final _ledeRe = RegExp(
    r'<([a-z][a-z0-9]*)\b[^>]*\bdata-nl-lede\b[^>]*>([\s\S]*?)</\1>',
    caseSensitive: false);

String _collapse(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// The lede is our own server-side render, so the only entities in it are the
/// ones `html.escape()` writes. The web reference gets this free from
/// `DOMParser`; a raw tag strip here would put `&#x27;` in the middle of every
/// row whose note has an apostrophe — which is most of them.
String _stripTags(String s) {
  var out = s.replaceAll(RegExp(r'<[^>]+>'), '');
  const entities = {
    '&#x27;': "'",
    '&#39;': "'",
    '&quot;': '"',
    '&nbsp;': ' ',
    '&lt;': '<',
    '&gt;': '>',
    // Last, so a `&amp;lt;` in the source does not become `<`.
    '&amp;': '&',
  };
  entities.forEach((k, v) => out = out.replaceAll(k, v));
  return _collapse(out);
}

String _clip(String s) => s.length <= 120 ? s : s.substring(0, 120);
