import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/models/chunk.dart';
import 'fixtures.dart';

/// firestore/doc-shapes (INV-05, INV-06) for the Flutter models that are
/// contract-aligned today. Chunk.fromJson must strip the embedding (INV-05 —
/// the model carries no embedding field) and convert created_at to epoch ms
/// (INV-06). Document mapping still carries the 1.0.0 `tags` vs `tag_ids`
/// drift; it is left to the Milestone-2 catch-up (the pin check red-stops the
/// whole suite until then, so this file documents what already conforms).
void main() {
  final suite = loadSuite('firestore/doc-shapes');

  test('doc-shapes suite is captured', () => expect(suite, isNotNull));

  for (final c in (suite?['cases'] as List? ?? [])) {
    final req = c['request'] as Map<String, dynamic>;
    if (req['collection'] != 'chunks') continue;
    test('${c['id']} — chunk INV-05/06', () {
      final input = (decode(req['input']) as Map).cast<String, dynamic>();
      final chunk = Chunk.fromJson({...input, 'chunk_id': req['id']});
      final expected = c['response']['body'] as Map<String, dynamic>;

      // INV-06: created_at is epoch ms (or null), matching the captured expected.
      expect(chunk.createdAt, expected['created_at']);
      // INV-05: the model exposes no embedding.
      expect((chunk as dynamic).toString().contains('embedding'), isFalse);
      // Aligned scalar fields round-trip.
      expect(chunk.chunkId, req['id']);
      expect(chunk.documentId, expected['document_id']);
      expect(chunk.chunkIndex, expected['chunk_index']);
    });
  }
}
