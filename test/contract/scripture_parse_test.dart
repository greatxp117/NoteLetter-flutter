/// Scripture citation parsing (contract 2.23.0/2.25.0, ADR-027 §2).
///
/// Mirrors the web reference's `scripture-parse.test.js`. Two of these assert
/// rules that are the whole reason the parser is written down at all rather
/// than reimplemented per client:
///
///   * A Douay-Rheims alias must NOT resolve. DR "1 Kings" is 1 Samuel, so a
///     lookup table that merged the aliases would send those citations to the
///     WRONG BOOK while looking complete.
///   * A bare book name is NOT a citation. "job", "acts" and "wisdom" are
///     ordinary words, and treating them as citations would swallow real
///     searches.
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/scripture/parse.dart';

late ScriptureCanon canon;

Citation? parse(String q) => parseCitation(q, canon: canon);

void main() {
  setUpAll(() {
    canon = ScriptureCanon.fromJson(
        jsonDecode(File('assets/contract/scripture-books.json').readAsStringSync())
            as Map<String, dynamic>);
  });

  test('the embedded artifact is byte-identical to the contract', () {
    // The reason this can be embedded at all (ADR-027 §2): one artifact, and a
    // test pinning the copy. A hand-maintained per-platform table is the drift
    // this exists to prevent.
    final local = File('assets/contract/scripture-books.json').readAsBytesSync();
    final spec =
        File('../NoteLetter-contracts/spec/scripture-books.json').readAsBytesSync();
    expect(local, spec);
  });

  test('the Catholic canon, 73 books', () {
    expect(canon.bookCount, 73);
  });

  group('the ordinary shapes', () {
    test('chapter and verse range', () {
      final c = parse('Mt 16:24-28')!;
      expect(c.bookId, 'matt');
      expect(c.spans, [const VerseSpan(16, 24, 28)]);
      expect(c.verseCount, 5);
      expect(c.whole, isFalse);
    });

    test('a whole chapter has no verse count — that would be a guess', () {
      final c = parse('Romans 8')!;
      expect(c.spans, [const VerseSpan(8, null, null)]);
      expect(c.whole, isTrue);
      expect(c.verseCount, isNull);
    });

    test('an ordinal fused to the name', () {
      expect(parse('1cor 13:4')!.bookId, '1cor');
      expect(parse('2tim 3:16')!.bookId, '2tim');
    });

    test('longest match wins', () {
      expect(parse('Song of Songs 2:1')!.bookId, parse('Sg 2:1')!.bookId);
    });
  });

  group('deuterocanonical books are in the canon', () {
    test('Sirach by its primary name, but NOT by its DR alias', () {
      expect(parse('Sir 3:1')!.bookId, 'sir');
      expect(parse('Sir 3:1')!.deuterocanonical, isTrue);
      // "Ecclesiasticus"/"Ecclus" is Douay-Rheims. Same trap as "3 Kings":
      // merging the alias table would make this parse while looking complete.
      expect(parse('Ecclus 3:1'), isNull);
    });
    test('Wisdom, Maccabees, Tobit, Baruch', () {
      for (final q in ['Wis 7:22', '1 Macc 4:36', 'Tob 12:7', 'Bar 3:9']) {
        expect(parse(q), isNotNull, reason: q);
        expect(parse(q)!.deuterocanonical, isTrue, reason: q);
      }
    });
  });

  group('the Douay-Rheims trap', () {
    test('a modern primary resolves to itself', () {
      expect(parse('1 Kings 2:3')!.bookId, '1kgs');
      expect(parse('1 Sam 2:3')!.bookId, '1sam');
    });

    test('a DR-only alias does NOT resolve', () {
      // "3 Kings" is DR for 1 Kings. Merging the alias table would make this
      // parse — to the wrong book — while looking complete.
      expect(parse('3 Kings 2:3'), isNull);
    });
  });

  group('what published lectionaries actually print', () {
    test('the compound form', () {
      final c = parse('Nahum 2:1, 3; 3:1-3, 6-7')!;
      expect(c.spans, const [
        VerseSpan(2, 1, 1),
        VerseSpan(2, 3, 3),
        VerseSpan(3, 1, 3),
        VerseSpan(3, 6, 7),
      ]);
    });

    test('part-verse letters — the span still covers the whole verse', () {
      // A chunk is never finer than a verse, so the letter narrows the clause
      // and not the span.
      expect(parse('Isaiah 35:1-6a, 10')!.spans,
          const [VerseSpan(35, 1, 6), VerseSpan(35, 10, 10)]);
      expect(parse('1 Corinthians 12:3b-7')!.spans, const [VerseSpan(12, 3, 7)]);
      expect(parse('Psalm 2:7bc-8, 10-12a')!.spans,
          const [VerseSpan(2, 7, 8), VerseSpan(2, 10, 12)]);
    });

    test('a range crossing a chapter (the Passion)', () {
      final c = parse('Matthew 26:14-27:66')!;
      expect(c.spans.first, const VerseSpan(26, 14, null));
      expect(c.spans.last, const VerseSpan(27, 1, 66));
      // Open-ended, so the extent is not knowable.
      expect(c.verseCount, isNull);
    });

    test('a crossing range swallows whole chapters in between', () {
      final c = parse('Genesis 1:1-3:5')!;
      expect(c.spans, const [
        VerseSpan(1, 1, null),
        VerseSpan(2, null, null),
        VerseSpan(3, 1, 5),
      ]);
    });

    test('an inverted range is refused, not repaired', () {
      expect(parse('Matthew 27:1-26:14'), isNull);
    });

    test('RCL optional verses are part of the reading', () {
      expect(parse('Psalm 65:(1-8) 9-13')!.spans,
          const [VerseSpan(65, 1, 8), VerseSpan(65, 9, 13)]);
      expect(parse('1 Samuel 8:4-11 (12-15) 16-20 (11:14-15)'), isNotNull);
    });

    test('psalm groups joined by a word or an ampersand', () {
      expect(parse('Psalm 97:1 and 2b, 6 and 7c, 9')!.spans, const [
        VerseSpan(97, 1, 1),
        VerseSpan(97, 2, 2),
        VerseSpan(97, 6, 6),
        VerseSpan(97, 7, 7),
        VerseSpan(97, 9, 9),
      ]);
      expect(parse('Psalm 78:3 & 4bc, 6c-7, 8'), isNotNull);
    });

    test('a single-chapter book is cited by verse alone', () {
      // Philemon has one chapter, so "9-10" is verses, not a chapter range.
      // The flag comes from the artifact so the parser holds no second opinion.
      final c = parse('Philemon 9-10')!;
      expect(c.spans, const [VerseSpan(1, 9, 10)]);
    });
  });

  group('what must NOT parse', () {
    test('a bare book name is an ordinary search', () {
      for (final q in ['job', 'acts', 'wisdom', 'Song of Songs']) {
        expect(parse(q), isNull, reason: q);
      }
    });

    test('ordinary queries are untouched', () {
      for (final q in ['attention and the moral life', '', 'the 3 body problem']) {
        expect(parse(q), isNull, reason: q);
      }
    });
  });

  test('an en-dash reads the same as a hyphen', () {
    expect(parse('Matthew 16:24–28')!.spans, const [VerseSpan(16, 24, 28)]);
  });

  test('looksLikeCitation is a cheap prefilter, false positives are free', () {
    expect(looksLikeCitation('Mt 16'), isTrue);
    expect(looksLikeCitation('romans 8'), isTrue);
    expect(looksLikeCitation('attention'), isFalse);
  });
}
