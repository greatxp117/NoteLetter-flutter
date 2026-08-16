/// Which counter a read event moves — INV-03a / INV-03b, contract 4.0.0
/// (ADR-039 §Amendment).
///
/// This is deliberately a PURE function separated from `logReadEvent`'s
/// Firestore transaction, because the transaction is untestable here (the
/// `api/*` harness only sees HTTP requests, and `fake_cloud_firestore` cannot
/// resolve against this SDK's `meta` pin) while the RULE is exactly the part
/// that was wrong and exactly the part a future edit will get wrong again.
///
/// The defect this replaces: `logReadEvent` bumped the document on EVERY event
/// and the chunk whenever a `chunkId` was passed. So expanding a search result
/// cleared the source's unread dot and counted as having read the passage —
/// and this client is configured against real prod, so it re-inflated the very
/// counters the 4.0.0 backfill corrected. A counter fed by more than one event
/// cannot be read as an answer to anything.
library;

/// The counters a single read event moves. At most one is true: an event that
/// moved two counters would be the defect this type exists to prevent.
class ReadCounterTargets {
  const ReadCounterTargets({
    this.document = false,
    this.chunkRead = false,
    this.chunkSearch = false,
  });

  /// `documents.view_count` +1 and `last_viewed_at`. Means OPENED.
  final bool document;

  /// `chunks.view_count` +1 and `last_viewed_at`. Means READ.
  final bool chunkRead;

  /// `chunks.search_view_count` +1, and no stamp — how recently a passage was
  /// glanced at in a result list is not a question any screen asks.
  final bool chunkSearch;

  /// True when this event moves nothing. Not an error: `chunk_newsletter_included`
  /// and `doc_finished` are backend-written and move no counter, and the
  /// vocabulary is OPEN for reading, so an unrecognised event must be inert
  /// rather than throw.
  bool get movesNothing => !document && !chunkRead && !chunkSearch;

  @override
  String toString() =>
      'ReadCounterTargets(document: $document, chunkRead: $chunkRead, '
      'chunkSearch: $chunkSearch)';

  @override
  bool operator ==(Object other) =>
      other is ReadCounterTargets &&
      other.document == document &&
      other.chunkRead == chunkRead &&
      other.chunkSearch == chunkSearch;

  @override
  int get hashCode => Object.hash(document, chunkRead, chunkSearch);
}

/// One event, one counter.
///
///   doc_opened    → documents.view_count + last_viewed_at
///   chunk_read    → chunks.view_count    + last_viewed_at
///   chunk_viewed  → chunks.search_view_count, and nothing else
///
/// Which counter moves is a property of the EVENT, never of whether a
/// `chunkId` happened to be passed — that conflation is how the old code went
/// wrong. A chunk-scoped event with no `chunkId` moves nothing rather than
/// falling back to the document.
ReadCounterTargets readCounterTargets(String eventType, {String? chunkId}) {
  switch (eventType) {
    case 'doc_opened':
      return const ReadCounterTargets(document: true);
    case 'chunk_read':
      return chunkId == null
          ? const ReadCounterTargets()
          : const ReadCounterTargets(chunkRead: true);
    case 'chunk_viewed':
      return chunkId == null
          ? const ReadCounterTargets()
          : const ReadCounterTargets(chunkSearch: true);
    default:
      // chunk_newsletter_included and doc_finished are backend-written; an
      // unknown value is inert by design (the vocabulary is open for reading).
      return const ReadCounterTargets();
  }
}
