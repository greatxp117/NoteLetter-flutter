/// INV-03a / INV-03b — one event, one counter (contract 4.0.0, ADR-039 §Amendment).
///
/// `logReadEvent` is a Firestore transaction, so the `api/*` request-construction
/// harness is structurally blind to it — the same gap that let the web reference
/// rewrite which counters move with all 295 Tier-1 tests green. The rule is
/// therefore extracted as a pure function and pinned here.
///
/// It is the rule most easily broken in silence: a counter moved by the wrong
/// event throws nothing, fails nothing, and looks exactly like data. This client
/// shipped that defect against real prod.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/services/read_counters.dart';

void main() {
  group('one event, one counter', () {
    test('doc_opened moves the document only', () {
      final t = readCounterTargets('doc_opened');
      expect(t.document, isTrue);
      expect(t.chunkRead, isFalse);
      expect(t.chunkSearch, isFalse);
    });

    test('chunk_read moves the chunk read counter only', () {
      final t = readCounterTargets('chunk_read', chunkId: 'c1');
      expect(t.chunkRead, isTrue);
      // Reading a passage is not another visit to the document, or every
      // scroll would read as a re-open.
      expect(t.document, isFalse);
      expect(t.chunkSearch, isFalse);
    });

    test('chunk_viewed moves the SEARCH counter only', () {
      final t = readCounterTargets('chunk_viewed', chunkId: 'c1');
      expect(t.chunkSearch, isTrue);
      // The 4.0.0 headline: expanding a search hit must not mark the source
      // opened, or it silently clears the unread dot.
      expect(t.document, isFalse);
      // And a glance in a result list is not reading, so coverage must not move.
      expect(t.chunkRead, isFalse);
    });

    test('no event ever moves two counters', () {
      for (final e in ['doc_opened', 'chunk_read', 'chunk_viewed',
                       'chunk_newsletter_included', 'doc_finished', 'nonsense']) {
        final t = readCounterTargets(e, chunkId: 'c1');
        final moved = [t.document, t.chunkRead, t.chunkSearch].where((b) => b).length;
        expect(moved, lessThanOrEqualTo(1), reason: '$e moved $moved counters');
      }
    });
  });

  group('events that move nothing', () {
    test('the two backend-written events are inert on the client', () {
      // chunk_newsletter_included stamps last_included_in_newsletter and
      // doc_finished sets finished_at — neither is a counter, and neither is
      // client-written at all.
      expect(readCounterTargets('chunk_newsletter_included', chunkId: 'c1').movesNothing, isTrue);
      expect(readCounterTargets('doc_finished').movesNothing, isTrue);
    });

    test('an unrecognised event is inert, never an error', () {
      // The vocabulary is OPEN for reading.
      expect(readCounterTargets('some_future_event', chunkId: 'c1').movesNothing, isTrue);
    });

    test('a chunk event with no chunkId moves nothing — it does NOT fall back to the document', () {
      // This is precisely the old bug's shape: deciding from the presence of a
      // chunkId rather than from the event.
      expect(readCounterTargets('chunk_read').movesNothing, isTrue);
      expect(readCounterTargets('chunk_viewed').movesNothing, isTrue);
    });
  });
}
