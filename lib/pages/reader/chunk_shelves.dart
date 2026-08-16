/// Effective shelves for a chunk (contract 2.35.0, ADR-034).
///
/// A chunk INHERITS its document's shelves. `tag_overrides` records only the
/// reader's explicit deviations, and the effective list is computed AT READ —
/// storing it would go stale the moment the document's shelves change.
///
/// Pure so it can be asserted directly; the chips that render it cannot be.
library;

/// `(documentTagIds - removed) + added`, order-stable on the document's own
/// ordering with additions appended.
///
/// A **stored** id that later dangles — its tag deleted, or the document's
/// shelves changed underneath it — is INERT rather than an error. Strictness
/// is for write time only, which is what stops a background shelf change from
/// making a reader's save start failing.
List<String> effectiveChunkShelves(
  List<String> documentTagIds,
  Map<String, dynamic>? overrides,
) {
  final added = ((overrides?['added'] as List?) ?? const []).cast<String>();
  final removed = ((overrides?['removed'] as List?) ?? const []).cast<String>();
  final out = <String>[];
  for (final id in documentTagIds) {
    if (!removed.contains(id)) out.add(id);
  }
  for (final id in added) {
    if (!out.contains(id)) out.add(id);
  }
  return out;
}

/// Whether a shelf on a chunk came from the document (inherited) or was added
/// by the reader. Drives the quiet/solid chip distinction: user intent and an
/// algorithm's guess must not look the same.
bool isInheritedShelf(String tagId, List<String> documentTagIds) =>
    documentTagIds.contains(tagId);

/// The override entry for one chunk, in the wire shape. Both lists empty means
/// "clear it" — pure inheritance is the ABSENCE of the field, not an empty one.
Map<String, dynamic> chunkOverrideEntry({
  required String chunkId,
  required List<String> added,
  required List<String> removed,
}) =>
    {
      'chunkId': chunkId,
      'addedTagIds': added,
      'removedTagIds': removed,
    };
