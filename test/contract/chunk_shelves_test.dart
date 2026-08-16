/// Per-chunk shelf overrides (contract 2.35.0, ADR-034).
///
/// The rule worth pinning is that effective shelves are COMPUTED, never
/// stored: a stored list goes stale the moment the document's shelves change,
/// and the staleness would be invisible.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/pages/reader/chunk_shelves.dart';

void main() {
  test('no overrides means pure inheritance', () {
    expect(effectiveChunkShelves(['a', 'b'], null), ['a', 'b']);
    expect(effectiveChunkShelves(['a', 'b'], {}), ['a', 'b']);
  });

  test('removed hides an inherited shelf', () {
    expect(effectiveChunkShelves(['a', 'b'], {'removed': ['a']}), ['b']);
  });

  test('added appends a shelf the document does not carry', () {
    expect(effectiveChunkShelves(['a'], {'added': ['z']}), ['a', 'z']);
  });

  test('a dangling stored id is inert, never an error', () {
    // The tag was deleted, or the document's shelves changed underneath.
    // Strictness is for WRITE time only — otherwise a background shelf change
    // would make a reader's save start failing.
    expect(effectiveChunkShelves(['a'], {'removed': ['gone']}), ['a']);
    expect(effectiveChunkShelves([], {'removed': ['gone']}), []);
  });

  test('an added id already on the document does not duplicate', () {
    expect(effectiveChunkShelves(['a'], {'added': ['a']}), ['a']);
  });

  test('inheritance is distinguishable from user intent', () {
    // They must not render alike: one is an algorithm's guess, the other is
    // something the reader said.
    expect(isInheritedShelf('a', ['a', 'b']), isTrue);
    expect(isInheritedShelf('z', ['a', 'b']), isFalse);
  });

  test('both lists empty is the CLEAR shape', () {
    final e = chunkOverrideEntry(chunkId: 'c1', added: [], removed: []);
    expect(e['addedTagIds'], isEmpty);
    expect(e['removedTagIds'], isEmpty);
    expect(e['chunkId'], 'c1');
  });
}
