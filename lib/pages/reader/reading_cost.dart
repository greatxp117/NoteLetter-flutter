/// The reader's reading cost — the byline's "min read" and the stats' Words
/// and Listen (reader.md §Header — byline & reading cost; 4.108.0, ADR-143
/// and ADR-144).
///
/// Extracted as pure rules so they can be asserted directly; the reader page
/// that draws them cannot be mounted by the harness.
library;

import '../../models/document.dart';
import 'dwell.dart' show readingWpm;

/// Does this document have REAL audio, as opposed to a synthesized TTS
/// narration? **Type OR field**, and both halves are load-bearing (ADR-046
/// §Rationale, ADR-049): `source_audio_url` is set for a podcast, while an
/// uploaded recording and an uploaded video carry null by design and mint
/// their URL per request. (This said "and an Instagram/TikTok video" until
/// 4.108.0; no extractor stores one for a short video.)
///
/// **One predicate for the byline, the stats and the Listen section**
/// (ADR-143): Listen is drawn, and "min read" dropped, exactly when this is
/// true. A YouTube document does not have its own audio here — nothing plays
/// its track — so it keeps its reading time, whatever its duration.
bool hasOwnAudio(Document doc) =>
    (doc.sourceAudioUrl?.isNotEmpty ?? false) ||
    doc.type == 'audio' ||
    doc.type == 'video';

/// The byline's reading time, `max(1, ceil(word_count / 220))` minutes from
/// the STORED count — or null: when the document has its own audio (its
/// length is the Listen stat, ADR-143), and when no count is stored (no
/// recount, ADR-144).
String? readingTimeLabel(Document doc) {
  final words = doc.wordCount;
  if (hasOwnAudio(doc) || words == null || words <= 0) return null;
  final mins = (words / readingWpm).ceil().clamp(1, 1 << 30);
  return '$mins min read';
}

/// Whether the stats draw a Listen cell at all. Without its own audio there is
/// nothing to measure, and a dash would say "not measured" (ADR-143).
bool showsListen(Document doc) => hasOwnAudio(doc);

/// The Listen cell's figure: `duration_seconds` as [fmtListen], or null — §8's
/// unmeasured dash — where nothing measured it.
String? listenValue(Document doc) {
  final s = doc.durationSeconds;
  return s != null && s > 0 ? fmtListen(s) : null;
}

/// `m:ss` under an hour, `h:mm:ss` from an hour (web `fmtListen`).
String fmtListen(num seconds) {
  final t = seconds.round().clamp(0, 1 << 30);
  final h = t ~/ 3600;
  final m = (t % 3600) ~/ 60;
  final s = (t % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// The Words cell: the stored `word_count`, or null — the unmeasured dash —
/// where none is stored. Never a recount from the passages (ADR-144).
String? wordsValue(Document doc) =>
    doc.wordCount == null ? null : '${doc.wordCount}';
