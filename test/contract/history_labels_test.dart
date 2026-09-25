// The reader's History panel names every contracted read_events event_type in
// words (data-model.md §/read_events) and never draws a raw token: chunk_read
// and doc_finished were missing, so the panel drew `chunk_read (Passage 2)`.
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/pages/reader/history_panel.dart';

void main() {
  const contracted = [
    'doc_opened',
    'chunk_read',
    'chunk_viewed',
    'chunk_newsletter_included',
    'doc_finished',
  ];

  test('every contracted event type has a sentence, never its token', () {
    for (final e in contracted) {
      final label = historyEventLabel(e);
      expect(label, isNot(contains('_')), reason: '$e drew a token');
      expect(historyEventLabels.containsKey(e), isTrue, reason: e);
    }
  });

  test('read and viewed never share wording (ADR-039)', () {
    expect(historyEventLabel('chunk_read'),
        isNot(historyEventLabel('chunk_viewed')));
  });

  test('an unknown type falls back to the neutral label, not the token', () {
    expect(historyEventLabel('something_new'), 'Activity');
    expect(historyEventLabel(null), 'Activity');
  });
}
