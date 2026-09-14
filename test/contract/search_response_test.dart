import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/models/search_result.dart';
import 'fixtures.dart';

/// `api/search` — the **response mapping** (INV-05, INV-06).
///
/// This suite exists because of what its absence cost. Tier-1 asserted how the
/// client *builds* a search request and nothing at all about how it reads the
/// answer, so `SearchResultDocument.fromJson` could cast `created_at` — an ISO
/// 8601 **string** in every response — with `as int?`. Every search this client
/// ever ran threw on the first result and was swallowed by `SearchNotifier`'s
/// blanket `catch (_)` into "Search failed. Please try again.": a healthy
/// backend, a 200 response, and an app that told the user search was down.
///
/// A green request-construction suite says nothing about the read path, and
/// this is the read path.
void main() {
  final suite = loadSuite('api/search');

  test('search suite is captured', () => expect(suite, isNotNull));

  for (final c in (suite?['cases'] as List? ?? [])) {
    final body = c['response']['body'] as Map<String, dynamic>;
    final results = (body['results'] as List?) ?? const [];
    if (results.isEmpty) continue;

    test('${c['id']} — every result parses', () {
      // Hand the model the shape `jsonDecode` really produces — nested objects
      // typed `Map<String, dynamic>`, not the loose maps a fixture walk builds.
      // Otherwise this suite fails on a cast the app never performs.
      Map<String, dynamic> typed(dynamic v) => {
            for (final e in (v as Map).entries)
              e.key as String:
                  e.value is Map ? typed(e.value) : decode(e.value),
          };

      final parsed = [
        for (final r in results) SearchResult.fromJson(typed(r)),
      ];
      expect(parsed.length, results.length);

      for (var i = 0; i < parsed.length; i++) {
        final raw = (results[i] as Map).cast<String, dynamic>();
        final rawChunk = (raw['chunk'] as Map).cast<String, dynamic>();
        final rawDoc = (raw['document'] as Map).cast<String, dynamic>();

        // INV-06: timestamps are epoch ms client-side, whatever the wire says.
        if (rawDoc['created_at'] != null) {
          expect(parsed[i].document.createdAt, isNotNull,
              reason: 'a document timestamp must survive the mapping');
        }
        // The shelf a result came from — unread until 4.5.4.
        expect(parsed[i].document.tagIds,
            (rawDoc['tag_ids'] as List?)?.cast<String>() ?? const []);
        // The document id is NOT in `document` (the endpoint returns
        // `snap.to_dict()`); the chunk is the only place it exists, and it is
        // what "Open source" must navigate by.
        expect(rawDoc.containsKey('id'), isFalse,
            reason: 'if this ever fails, the endpoint changed shape');
        expect(parsed[i].chunk.documentId, rawChunk['document_id']);
        // INV-05: no embedding reaches the model.
        expect(rawChunk.containsKey('embedding'), isFalse);

        // 4.44.0 / ADR-082 — the two MEASURED components of `score`, which the
        // score explainer renders and **may never solve for**. They are always
        // present on a successful response, and the chunk carries a
        // `source_priority` of its own that is NOT this one: reading the
        // chunk's would show the fallback link rather than the value the
        // ranking actually used, and the two agree often enough that the
        // mistake would look right.
        expect(parsed[i].cosine, raw['cosine'],
            reason: 'cosine comes off the response, never off the chunk');
        expect(parsed[i].sourcePriority, raw['source_priority'],
            reason: 'the RESULT-level source_priority is the one that ranked');
      }
    });
  }
}
