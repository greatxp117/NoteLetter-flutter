import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/models/chunk.dart';
import 'package:flutter_app/models/document.dart';
import 'fixtures.dart';

/// firestore/doc-shapes (INV-05, INV-06) for the Flutter models.
///
/// Chunk.fromJson must strip the embedding (INV-05 — the model carries no
/// embedding field) and convert created_at to epoch ms (INV-06).
///
/// Document.fromJson reads tags from `tag_ids` (data-model.md — the 1.0.0
/// `tags` naming was extraction drift) and converts all timestamps to epoch ms
/// (INV-06). The pre-1.1 case is the guard against the old drift: it carries
/// both `tag_ids: [seed-tag-recipes]` and a vestigial empty `tags: []`, so a
/// model that read `tags` would silently drop the real tag.
void main() {
  final suite = loadSuite('firestore/doc-shapes');

  test('doc-shapes suite is captured', () => expect(suite, isNotNull));

  for (final c in (suite?['cases'] as List? ?? [])) {
    final req = c['request'] as Map<String, dynamic>;
    final expected = c['response']['body'] as Map<String, dynamic>;

    if (req['collection'] == 'chunks') {
      test('${c['id']} — chunk INV-05/06', () {
        final input = (decode(req['input']) as Map).cast<String, dynamic>();
        final chunk = Chunk.fromJson({...input, 'chunk_id': req['id']});

        // INV-06: created_at is epoch ms (or null), matching the captured expected.
        expect(chunk.createdAt, expected['created_at']);
        // INV-05: the model exposes no embedding.
        expect((chunk as dynamic).toString().contains('embedding'), isFalse);
        // Aligned scalar fields round-trip.
        expect(chunk.chunkId, req['id']);
        expect(chunk.documentId, expected['document_id']);
        expect(chunk.chunkIndex, expected['chunk_index']);
      });
    } else if (req['collection'] == 'documents') {
      test('${c['id']} — document tag_ids + INV-06', () {
        final input = (decode(req['input']) as Map).cast<String, dynamic>();
        final doc = Document.fromJson(req['id'] as String, input);
        final expectedDoc = expected['document'] as Map<String, dynamic>;

        // Tags come from tag_ids, never the vestigial `tags` field.
        expect(doc.tagIds, (expectedDoc['tag_ids'] as List).cast<String>());
        // INV-06: every timestamp is epoch ms (or null).
        expect(doc.createdAt, expectedDoc['created_at']);
        expect(doc.processedAt, expectedDoc['processed_at']);
        expect(doc.lastViewedAt, expectedDoc['last_viewed_at']);
        // Aligned scalar fields round-trip.
        expect(doc.id, expectedDoc['id']);
        expect(doc.userId, expectedDoc['user_id']);
        expect(doc.title, expectedDoc['title']);
        expect(doc.type, expectedDoc['type']);
      });
    }
  }
}
