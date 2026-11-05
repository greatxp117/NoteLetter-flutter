// `kitLetterSections` against a letter the REAL renderer built (5.63.0, TODO
// L194(b); web `tests/contract/letter-sections-built.test.js`, case for case).
//
// Home's letter card and the Letters page's latest letter read their passages
// out of the letterhead's HTML — each passage an `h2`, its body the element
// after it, its source the card's "Read “…” in context" link to `/reader/{id}`.
// The backend's `_render_newsletter_html` writes that HTML, so a change there
// emptied the card with nothing failing: `d_home_kit_test` fed it hand-written
// strings, which say only that it reads the shape their author imagined.
//
// The fixture is `firestore/built-letter`: two sources, Send now, the queue
// drained through the real `fn_build_newsletter`, the stored record's
// `html_body` whole. A renderer change re-captures it, and this file says
// whether this client can still read what the backend now writes.
//
// Mutants run against it (each turns it red): the source pattern with
// straight quotes (`Read "(.+)" in context`); passages read from `h3` for
// `h2`; the reader-link test pointed at `/letters/`.
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/newsletter.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

import 'fixtures.dart';

void main() {
  final suite = loadSuite('firestore/built-letter');
  final built = (suite!['cases'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((c) => c['id'] == 'built-letter:html-body');
  final body =
      Map<String, dynamic>.from(built['response']['body'] as Map);
  final letter = Newsletter.fromJson('built-letter', body);
  final sources = (built['request']['sources'] as List)
      .cast<Map<String, dynamic>>();
  final chunkIds = (body['chunk_ids'] as List).cast<String>();

  test('the fixture is a built, sent daily letter with a letterhead', () {
    expect(letter.status, 'sent');
    expect(letter.htmlBody, contains('data-nl-letterhead'));
    expect(chunkIds.length, sources.length);
  });

  test('one section per passage the letter carries, numbered in order', () {
    expect([for (final s in kitLetterSections(letter)) s.n],
        [for (var i = 0; i < chunkIds.length; i++) i + 1]);
  });

  test("each section has its heading and its passage's words", () {
    for (final s in kitLetterSections(letter)) {
      expect(s.title, isNotEmpty, reason: 'section ${s.n} has a heading');
      expect(s.text, isNotEmpty, reason: 'section ${s.n} has its passage');
    }
  });

  test('each section names its source and the document it opens', () {
    final s = kitLetterSections(letter);
    expect([for (final x in s) x.docId]..sort(),
        [for (final x in sources) x['id'] as String]..sort());
    for (final x in s) {
      expect(x.source,
          sources.firstWhere((src) => src['id'] == x.docId)['title']);
    }
  });

  test("the card's parts carry the same sections, and a count from chunk_ids",
      () {
    final p = kitLetterParts(letter)!;
    final s = kitLetterSections(letter);
    expect([for (final x in p.sections) (x.n, x.title, x.text, x.source, x.docId)],
        [for (final x in s) (x.n, x.title, x.text, x.source, x.docId)]);
    expect(p.count, chunkIds.length);
  });
}
