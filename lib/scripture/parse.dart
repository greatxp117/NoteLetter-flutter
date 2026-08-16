/// Scripture citation parsing (ADR-027 §2) — a port of the canonical
/// implementation in `NoteLetter-web/src/scripture/parse.js`.
///
/// Runs entirely client-side against `assets/contract/scripture-books.json`, a
/// **byte-identical** copy of the contract artifact
/// `NoteLetter-contracts/spec/scripture-books.json`. That is deliberate: a
/// citation echo updates as the user types, so a round trip is not affordable,
/// and a table duplicated per platform by hand is exactly the drift ADR-027 §2
/// exists to prevent. One artifact, embedded, with a conformance test pinning
/// the copy identical.
///
/// Ambiguities resolve to the web reference, not to this file.
library;

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class ScriptureBook {
  const ScriptureBook({
    required this.id,
    required this.name,
    required this.abbreviations,
    required this.deuterocanonical,
    required this.singleChapter,
  });

  final String id;
  final String name;
  final List<String> abbreviations;
  final bool deuterocanonical;
  final bool singleChapter;
}

/// One contiguous stretch of a chapter.
///
/// `from`/`to` are both null for a whole chapter. `to` null with `from` set
/// means "to the end of the chapter", which only a chapter-crossing range
/// produces — chapter lengths are deliberately NOT in the canon artifact,
/// because nothing needs to know how long a chapter is, only that the range
/// runs to its end.
class VerseSpan {
  const VerseSpan(this.chapter, this.from, this.to);
  final int chapter;
  final int? from;
  final int? to;

  Map<String, dynamic> toJson() =>
      {'chapter': chapter, 'from': from, 'to': to};

  @override
  bool operator ==(Object other) =>
      other is VerseSpan &&
      other.chapter == chapter &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(chapter, from, to);

  @override
  String toString() => 'VerseSpan($chapter, $from, $to)';
}

class Citation {
  const Citation({
    required this.bookId,
    required this.book,
    required this.spans,
    required this.ref,
    required this.whole,
    required this.verseCount,
    required this.deuterocanonical,
  });

  final String bookId;
  final String book;
  final List<VerseSpan> spans;

  /// Human-readable reference, en-dash for ranges.
  final String ref;

  /// Every span is a whole chapter.
  final bool whole;

  /// **Null whenever the extent is not actually known** — a whole chapter, or
  /// a range running to the end of one. A number there would be a guess shown
  /// as a count (ADR-028: only measured figures).
  final int? verseCount;

  final bool deuterocanonical;
}

/// The canon, loaded once. [load] must be awaited before [parseCitation].
class ScriptureCanon {
  ScriptureCanon._(this._lookup, this.canon, this.bookCount, this._maxKeyWords);

  static ScriptureCanon? _instance;
  static ScriptureCanon? get instanceOrNull => _instance;

  final Map<String, ScriptureBook> _lookup;
  final String canon;
  final int bookCount;
  final int _maxKeyWords;

  static Future<ScriptureCanon> load() async {
    if (_instance != null) return _instance!;
    final raw = await rootBundle
        .loadString('assets/contract/scripture-books.json');
    return _instance = fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// Exposed so the contract suite can build the canon from the artifact on
  /// disk without a Flutter asset bundle.
  static ScriptureCanon fromJson(Map<String, dynamic> data) {
    final lookup = <String, ScriptureBook>{};
    var maxWords = 1;
    for (final b in (data['books'] as List).cast<Map<String, dynamic>>()) {
      final book = ScriptureBook(
        id: b['id'] as String,
        name: b['name'] as String,
        abbreviations: (b['abbreviations'] as List? ?? const []).cast<String>(),
        deuterocanonical: b['deuterocanonical'] as bool? ?? false,
        singleChapter: b['single_chapter'] as bool? ?? false,
      );
      // Primary keys ONLY. `aliases_douay_rheims` is deliberately not merged:
      // several collide with modern primaries — DR "1 Kings" is 1 Samuel — so
      // a merged table resolves those citations to the WRONG BOOK while
      // looking complete. See the artifact's `disjointness` note.
      for (final key in [book.name.toLowerCase(), ...book.abbreviations]) {
        lookup[key] = book;
        final n = key.split(' ').length;
        if (n > maxWords) maxWords = n;
      }
    }
    return ScriptureCanon._(
      lookup,
      data['canon'] as String? ?? '',
      (data['book_count'] as num?)?.toInt() ?? lookup.length,
      maxWords,
    );
  }

  /// Leading book name, longest match first, so "song of songs" beats "song".
  (ScriptureBook, String)? _matchBook(String text) {
    final words = text.split(' ');
    final upper = _maxKeyWords < words.length ? _maxKeyWords : words.length;
    for (var n = upper; n >= 1; n--) {
      final hit = _lookup[words.take(n).join(' ')];
      if (hit != null) return (hit, words.skip(n).join(' '));
    }
    // "1cor 13" style: a leading ordinal fused to the name.
    final fused = RegExp(r'^([123])([a-z].*)$').firstMatch(words.first);
    if (fused != null) {
      final hit = _lookup['${fused.group(1)} ${fused.group(2)}'];
      if (hit != null) return (hit, words.skip(1).join(' '));
    }
    return null;
  }
}

/// Lowercase, drop periods, collapse whitespace, normalise dashes to "-".
String _normalize(String? s) => (s ?? '')
    .toLowerCase()
    .replaceAll(RegExp(r'[.․]'), '')
    .replaceAll(RegExp('[‐-―−]'), '-')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

const _verse = r'(\d{1,3})\s?[a-z]{0,6}';
final _headRe =
    RegExp('^' r'(\d{1,3})\s*:\s*' '$_verse' r'(?:\s*-\s*(?:(\d{1,3})\s*:\s*)?' '$_verse' r')?$');
final _partRe =
    RegExp('^$_verse' r'(?:\s*-\s*(?:(\d{1,3})\s*:\s*)?' '$_verse' r')?$');
final _wholeChapRe = RegExp(r'^(\d{1,3})$');

/// A range crossing a chapter becomes: the rest of the opening chapter, any
/// chapters wholly inside, then the closing chapter up to its last verse.
List<VerseSpan>? _crossChapter(int c1, int v1, int c2, int v2) {
  if (c2 < c1) return null;
  final spans = <VerseSpan>[VerseSpan(c1, v1, null)];
  for (var c = c1 + 1; c < c2; c++) {
    spans.add(VerseSpan(c, null, null));
  }
  spans.add(VerseSpan(c2, 1, v2));
  return spans;
}

/// The RCL marks OPTIONAL verses with parentheses — `Psalm 65:(1-8) 9-13`.
/// Those verses are part of the reading; whether to read them aloud is the
/// congregation's choice, not a statement that they belong elsewhere. So the
/// brackets and bare spaces between groups become ordinary separators.
String _expandOptional(String tail) {
  var t = tail
      .replaceAll(RegExp(r'[()]'), ' ')
      // Psalms routinely join verse groups with a word or an ampersand rather
      // than a comma — "Psalm 97:1 and 2b, 6 and 7c, 9". Same meaning.
      .replaceAll(RegExp(r'\s*(?:&|\band\b)\s*'), ', ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  t = t.replaceAllMapped(
      RegExp(r'(\d)\s+(\d{1,3}\s*:)'), (m) => '${m[1]}; ${m[2]}');
  t = t.replaceAllMapped(RegExp(r'(\d)\s+(\d)'), (m) => '${m[1]}, ${m[2]}');
  return t;
}

List<VerseSpan>? _parseSpans(String rawTail, bool singleChapter) {
  if (rawTail.isEmpty) return null;
  var tail = _expandOptional(rawTail);
  // Obadiah, Philemon, 2 John, 3 John and Jude have ONE chapter, so the
  // lectionary cites them by verse alone — "Philemon 9-10, 12-17". Without
  // this, "9-10" reads as a chapter range and the citation is refused. The
  // flag comes from the canon artifact, so this parser holds no second,
  // driftable opinion about which books those are.
  if (singleChapter && !RegExp(r'^\d{1,3}\s*:').hasMatch(tail)) {
    tail = '1:$tail';
  }
  final spans = <VerseSpan>[];
  int? chapter;

  for (final group in tail.split(';')) {
    final g = group.trim();
    if (g.isEmpty) continue;
    final parts = g.split(',');
    final h = parts.first.trim();

    final withVerse = _headRe.firstMatch(h);
    final wholeChap = _wholeChapRe.firstMatch(h);

    if (withVerse != null) {
      chapter = int.parse(withVerse.group(1)!);
      final from = int.parse(withVerse.group(2)!);
      final endChapter =
          withVerse.group(3) != null ? int.parse(withVerse.group(3)!) : null;
      final to =
          withVerse.group(4) != null ? int.parse(withVerse.group(4)!) : from;
      if (endChapter != null && endChapter != chapter) {
        final crossed = _crossChapter(chapter, from, endChapter, to);
        if (crossed == null) return null;
        spans.addAll(crossed);
        chapter = endChapter;
      } else {
        if (to < from) return null;
        spans.add(VerseSpan(chapter, from, to));
      }
    } else if (wholeChap != null) {
      chapter = int.parse(wholeChap.group(1)!);
      spans.add(VerseSpan(chapter, null, null));
    } else {
      return null;
    }

    for (final part in parts.skip(1)) {
      final p = part.trim();
      if (p.isEmpty) continue;
      if (chapter == null) return null;
      // A continuation part may itself cross into the next chapter —
      // "Revelation 21:10, 22-22:5" — so it takes the same head grammar.
      final m = _partRe.firstMatch(p);
      if (m == null) return null;
      final from = int.parse(m.group(1)!);
      final endChapter = m.group(2) != null ? int.parse(m.group(2)!) : null;
      final to = m.group(3) != null ? int.parse(m.group(3)!) : from;
      if (endChapter != null && endChapter != chapter) {
        final crossed = _crossChapter(chapter, from, endChapter, to);
        if (crossed == null) return null;
        spans.addAll(crossed);
        chapter = endChapter;
        continue;
      }
      if (to < from) return null;
      spans.add(VerseSpan(chapter, from, to));
    }
  }
  return spans.isEmpty ? null : spans;
}

String _formatRef(ScriptureBook book, List<VerseSpan> spans) {
  final out = <(String, String)>[];
  int? chapter;
  for (var i = 0; i < spans.length; i++) {
    final s = spans[i];
    // An open-ended span followed by the next chapter from verse 1 is how a
    // chapter-crossing range is stored; print it back in the form it was
    // written rather than as two disjoint references.
    final next = i + 1 < spans.length ? spans[i + 1] : null;
    if (s.from != null &&
        s.to == null &&
        next != null &&
        next.from == 1 &&
        next.chapter == s.chapter + 1) {
      chapter = next.chapter;
      out.add((';', '${s.chapter}:${s.from}–${next.chapter}:${next.to}'));
      i++;
      continue;
    }
    // An open-ended span that did NOT pair with a following verse-1 chapter
    // (a range crossing more than one chapter, e.g. Genesis 1:1-3:5, whose
    // middle chapter is whole) prints as its start verse alone. The web
    // reference reaches the same output via a loose `null > n` comparison;
    // spelled out here because Dart will not compare a null.
    final body = (s.to != null && s.to! > s.from!)
        ? '${s.from}–${s.to}'
        : '${s.from}';
    if (s.from == null) {
      out.add((';', '${s.chapter}'));
      chapter = s.chapter;
    } else if (s.chapter == chapter) {
      out.add((',', body));
    } else {
      chapter = s.chapter;
      out.add((';', '${s.chapter}:$body'));
    }
  }
  final buf = StringBuffer(book.name);
  for (var i = 0; i < out.length; i++) {
    buf.write(i == 0 ? ' ' : (out[i].$1 == ',' ? ', ' : '; '));
    buf.write(out[i].$2);
  }
  return buf.toString();
}

/// Parse a citation. Returns **null when the text is not one** — the caller
/// treats null as "this is an ordinary search query", so being conservative
/// here is what keeps normal searches from being hijacked.
Citation? parseCitation(String? query, {ScriptureCanon? canon}) {
  final c = canon ?? ScriptureCanon.instanceOrNull;
  if (c == null) return null;
  final text = _normalize(query);
  if (text.isEmpty) return null;

  final matched = c._matchBook(text);
  if (matched == null) return null;
  final (book, tail) = matched;

  // A bare book name is NOT a citation — "job", "acts" and "wisdom" are
  // ordinary words, and treating them as citations would swallow real
  // searches.
  final spans = _parseSpans(tail.trim(), book.singleChapter);
  if (spans == null) return null;

  final whole = spans.every((s) => s.from == null);
  final openEnded = spans.any((s) => s.from != null && s.to == null);
  final verseCount = (whole || openEnded)
      ? null
      : spans.fold<int>(
          0, (n, s) => n + (s.from == null ? 0 : s.to! - s.from! + 1));

  return Citation(
    bookId: book.id,
    book: book.name,
    deuterocanonical: book.deuterocanonical,
    spans: spans,
    whole: whole,
    verseCount: verseCount,
    ref: _formatRef(book, spans),
  );
}

/// Cheap prefilter for per-keystroke use: could this become a citation? A word
/// followed by a digit. False positives are free — the caller still runs
/// [parseCitation].
bool looksLikeCitation(String? query) =>
    RegExp(r'^\s*[123]?\s*[a-z][a-z\s]*\s+\d', caseSensitive: false)
        .hasMatch(query ?? '');
