/// F-182 · A document status this build does not know reads as in progress,
/// never Failed (data-model.md §documents `status`; web `procPill`,
/// `useReviewInbox`, `isRetryable`).
///
/// Web fails a source only on a literal `error` or `skipped` and draws
/// anything else — a status a later backend writes, or none at all — as
/// *Processing*. This client used to map every unrecognised token to `error`,
/// so such a source read as Failed with Retry, was counted in For your review,
/// and its Retry was refused with a 409 (`fn_retry_document` accepts `error`
/// and a stalled run only).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/pages/sources/browse_section.dart';
import 'package:flutter_app/state/activity_notifier.dart';
import 'package:flutter_app/state/review_inbox.dart';
import 'package:flutter_app/theme/app_theme.dart';

Document _doc(Object? status) => Document.fromJson('d1', {
      'user_id': 'u1',
      'title': 'A later pipeline',
      'type': 'article',
      if (status != null) 'status': status,
      'created_at': DateTime(2026, 11, 11).millisecondsSinceEpoch,
    });

final _now = DateTime(2026, 11, 11, 12);

void main() {
  group('a status this build does not know', () {
    for (final status in ['transcoding', null]) {
      final name = status ?? 'a missing status';
      test('$name is not error, not in For your review, not retryable', () {
        final d = _doc(status);
        expect(d.status, isNot(DocumentStatus.error));
        expect(d.status, DocumentStatus.unknown);
        expect(sourceNeedsReview(d, _now), isFalse);
        expect(d.isStalled(_now), isFalse);
        expect(procSummary([d], _now), '1 indexing');
      });
    }

    test('the known tokens still map to themselves', () {
      expect(_doc('error').status, DocumentStatus.error);
      expect(_doc('skipped').status, DocumentStatus.skipped);
      expect(_doc('complete').status, DocumentStatus.complete);
      expect(_doc('queued').status, DocumentStatus.queued);
      expect(_doc('processing').status, DocumentStatus.processing);
      expect(_doc('pending_upload').status, DocumentStatus.pendingUpload);
      expect(sourceNeedsReview(_doc('error'), _now), isTrue);
    });

    for (final look in ProcessingLook.values) {
      testWidgets('its row reads Processing, never Error or Retry ($look)',
          (tester) async {
        await tester.pumpWidget(ChangeNotifierProvider(
          create: (_) => ActivityNotifier(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: look == ProcessingLook.arrival ? 220 : null,
                  child: ProcessingRow(
                    doc: _doc('transcoding'),
                    look: look,
                    now: _now,
                    editCheck: (_) async => false,
                    studyCheck: (_) async => false,
                  ),
                ),
              ),
            ),
          ),
        ));
        await tester.pump();
        final words = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
            .join(' | ');
        // The stage may be drawn in caps (D's mono stage); the word is
        // web's `procPill` fallback either way.
        expect(words.toLowerCase(), contains('processing'));
        expect(words.toLowerCase(), isNot(contains('error')));
        expect(find.text('Retry'), findsNothing);
        expect(find.textContaining('Retry'), findsNothing);
      });
    }
  });
}
