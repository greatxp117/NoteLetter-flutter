/// Listen is the document's own audio, and the word count is the indexer's
/// (Xavier's rulings of 2026-10-07; draft 4.108.0, ADR-143 option A and
/// ADR-144; reader.md §Header — byline & reading cost). Tandem of web
/// a04612d.
///
/// Until 4.108.0 this client drew Listen as a permanent dash on every document
/// (the reference read `audio_seconds`, which nothing writes), kept "min read"
/// on every transcript, and recounted words from chunk `text` when
/// `word_count` was null. The rules now live in `reader/reading_cost.dart`
/// and are asserted here over the reference's own cases.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/pages/reader/reading_cost.dart';

Document _doc(String type, [Map<String, dynamic> extra = const {}]) =>
    Document.fromJson('doc-1', {
      'user_id': 'u1',
      'title': 'A source',
      'type': type,
      'status': 'complete',
      'word_count': 660,
      ...extra,
    });

void main() {
  group('the predicate', () {
    test(
      'own audio: a stored enclosure, or an uploaded recording or video',
      () {
        expect(
          hasOwnAudio(
            _doc('podcast', {'source_audio_url': 'https://cdn.example/ep.mp3'}),
          ),
          isTrue,
        );
        expect(hasOwnAudio(_doc('audio')), isTrue);
        expect(hasOwnAudio(_doc('video')), isTrue);
      },
    );
    test(
      'YouTube and a short video keep no own audio, whatever their length',
      () {
        expect(
          hasOwnAudio(_doc('youtube', {'duration_seconds': 600})),
          isFalse,
        );
        expect(
          hasOwnAudio(_doc('instagram', {'duration_seconds': 42})),
          isFalse,
        );
        expect(hasOwnAudio(_doc('pdf')), isFalse);
      },
    );
  });

  test('a length is m:ss, h:mm:ss from an hour', () {
    expect(fmtListen(42), '0:42');
    expect(fmtListen(2712), '45:12');
    expect(fmtListen(3599), '59:59');
    expect(fmtListen(3600), '1:00:00');
    expect(fmtListen(3725), '1:02:05');
    expect(fmtListen(2712.4), '45:12');
  });

  group('the stats and the byline', () {
    test('a podcast: Listen is its stored length; no reading time', () {
      final d = _doc('podcast', {
        'source_audio_url': 'https://cdn.example/ep.mp3',
        'duration_seconds': 2712,
      });
      expect(showsListen(d), isTrue);
      expect(listenValue(d), '45:12');
      expect(readingTimeLabel(d), isNull);
    });
    test('an uploaded video an hour long: h:mm:ss', () {
      final d = _doc('video', {'duration_seconds': 3725});
      expect(listenValue(d), '1:02:05');
      expect(readingTimeLabel(d), isNull);
    });
    test(
      'a recording with no stored length: the dash, and still no reading time',
      () {
        final d = _doc('audio', {'duration_seconds': null});
        expect(showsListen(d), isTrue);
        expect(listenValue(d), isNull);
        expect(readingTimeLabel(d), isNull);
      },
    );
    test('YouTube: NO Listen cell at all, and its reading time stays', () {
      final d = _doc('youtube', {'duration_seconds': 600});
      expect(showsListen(d), isFalse);
      expect(readingTimeLabel(d), '3 min read'); // 660 / 220
    });
    test('a PDF: no Listen cell, the reading time from the stored count', () {
      final d = _doc('pdf', {'audio_seconds': 300});
      expect(showsListen(d), isFalse);
      expect(readingTimeLabel(d), '3 min read');
      expect(wordsValue(d), '660');
    });
    test(
      'a null word_count: Words is the dash, and no reading time — never a recount',
      () {
        final d = _doc('pdf', {'word_count': null});
        expect(wordsValue(d), isNull);
        expect(readingTimeLabel(d), isNull);
      },
    );
    test('the reading time rounds up and never reads zero', () {
      expect(readingTimeLabel(_doc('pdf', {'word_count': 1})), '1 min read');
      expect(readingTimeLabel(_doc('pdf', {'word_count': 221})), '2 min read');
      expect(readingTimeLabel(_doc('pdf', {'word_count': 0})), isNull);
    });
  });

  test('duration_seconds is read from the stored document', () {
    expect(_doc('podcast', {'duration_seconds': 2712}).durationSeconds, 2712);
    expect(_doc('pdf').durationSeconds, isNull);
  });
}
