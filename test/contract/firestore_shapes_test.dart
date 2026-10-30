import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/models/ask_thread.dart';
import 'package:flutter_app/models/chunk.dart';
import 'package:flutter_app/models/cloud_folder.dart';
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

  // firestore/organization-shapes — an organized folder as Sources reads it.
  // `readme` is an OBJECT on the stored document; the model read a flat
  // `readme_status` nothing writes, so every chip said "pending" (F-90's
  // org-scan-wait frame, 2026-10-12).
  final org = loadSuite('firestore/organization-shapes');
  for (final c in (org?['cases'] as List? ?? [])) {
    final req = c['request'] as Map<String, dynamic>;
    if (req['collection'] != 'cloud_folders') continue;
    final expected = c['response']['body'] as Map<String, dynamic>;
    test('${c['id']} — cloud folder: readme status, path, count', () {
      final input = (decode(req['input']) as Map).cast<String, dynamic>();
      final f = CloudFolder.fromJson(req['id'] as String, input);
      expect(f.readmeStatus, (expected['readme'] as Map?)?['status']);
      expect(f.providerPath, expected['provider_path']);
      expect(f.docCount, expected['doc_count']);
    });
  }

  // Ask's written answer reaches the screen as stored (5.30.0, ADR-187,
  // INV-35) — web's `tests/contract/ask-written-answer.test.js`, case for case.
  // The answer is read from the thread's messages subscription, never from
  // the turn's response, so the mapper is the half a response-shaped fixture
  // cannot test: an unmapped field is a sentence under an unread key (the
  // 4.71.0 lesson). The stored message is the CAPTURED `api/ask` suite's, so
  // this reads what the backend really writes.
  group('ask messages: the written answer and its note', () {
    final ask = loadSuite('api/ask');
    final created = (ask?['cases'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .where((c) => c['id'] == 'ask:turn-creates-thread')
        .firstOrNull;
    final stored = (created?['response']['body']['message'] as Map?)
        ?.cast<String, dynamic>();

    AskMessage read(Map<String, dynamic> data) =>
        AskMessage.fromJson('m1', data);

    test('the api/ask suite is captured with a written answer', () {
      expect(stored, isNotNull);
      expect((stored!['answer'] as List).isNotEmpty, isTrue);
    });

    test('the captured answer arrives block for block, with no note', () {
      final m = read({
        'role': 'library',
        'text': null,
        'citations': stored!['citations'],
        'answer': stored['answer'],
        'answer_note': stored['answer_note'],
      });
      final raw = (stored['answer'] as List).cast<Map>();
      expect(m.answer, hasLength(raw.length));
      for (var i = 0; i < raw.length; i++) {
        expect(m.answer![i].text, raw[i]['text']);
        expect(m.answer![i].kind.name, raw[i]['kind']);
        expect(m.answer![i].n, raw[i]['n']);
      }
      expect(m.answerNote, isNull);
      expect(m.answer!.any((b) => b.kind == AskBlockKind.quote), isTrue);
      expect(m.text, isNull, reason: 'a library message has no `text`');
    });

    test('an answer before 5.30.0 has neither field: no answer, no note', () {
      final m = read({
        'role': 'library',
        'text': null,
        'citations': stored!['citations'],
      });
      expect(m.answer, isNull);
      expect(m.answerNote, isNull);
    });

    test('the failure sentence arrives verbatim', () {
      const note = "NoteLetter couldn't write an answer this time. These are "
          'the passages it found.';
      final m = read({
        'role': 'library',
        'text': null,
        'citations': stored!['citations'],
        'answer': null,
        'answer_note': note,
      });
      expect(m.answer, isNull);
      expect(m.answerNote, note);
      expect(read({'role': 'library', 'answer_note': ''}).answerNote, isNull,
          reason: 'an empty sentence is no sentence');
    });

    test('an unknown kind is dropped, and an answer with nothing left is none',
        () {
      expect(
          askAnswer([
            {'kind': 'image', 'text': 'x'},
            {'kind': 'paragraph', 'text': 'Kept [1].'},
          ]),
          [const AskAnswerBlock.paragraph('Kept [1].')]);
      expect(
          askAnswer([
            {'kind': 'image', 'text': 'x'},
            {'kind': 'quote', 'n': 0, 'text': 'no passage'},
          ]),
          isNull);
      expect(askAnswer('not a list'), isNull);
      expect(askAnswer(const []), isNull, reason: 'an empty list is null');
    });

    test('a quote needs a positive integer n — as a number, never a string',
        () {
      expect(askAnswer([
        {'kind': 'quote', 'n': 2, 'text': 'a'},
        {'kind': 'quote', 'n': 1.0, 'text': 'b'},
        {'kind': 'quote', 'n': '1', 'text': 'c'},
        {'kind': 'quote', 'n': 1.5, 'text': 'd'},
        {'kind': 'quote', 'text': 'e'},
        {'kind': 'quote', 'n': -1, 'text': 'f'},
        {'kind': 'paragraph', 'text': ''},
        {'kind': 'paragraph', 'text': 7},
      ]), [
        const AskAnswerBlock.quote(2, 'a'),
        const AskAnswerBlock.quote(1, 'b'),
      ]);
    });

    test('a scoped answer carries its scope', () {
      final m = read({
        'role': 'library',
        'text': null,
        'citations': const [],
        'scope': {'tag_id': 'tag-1', 'title': 'Recipes', 'exhaustive': false},
      });
      expect(m.scope?.tagId, 'tag-1');
      expect(m.scope?.title, 'Recipes');
      expect(m.scope?.exhaustive, isFalse);
    });
  });
}
