/// A picture already in the library (5.50.0–5.51.0, ADR-202) — the words a
/// copy's row and its Compare sheet use for WHEN and HOW a document came in,
/// and the one read of the original both of them draw from. Web
/// `src/shared/pictureCopy.js`.
///
/// How is said from what the document itself records, most specific first:
/// the camera roll (`source_capture`), a cloud service (`cloud_placement`),
/// the upload's own origin (`upload_origin`, 5.51.0 — the client's word), and
/// plain *Uploaded* for an upload stored before any client said where it came
/// from (`features/picture-dedupe.md` §Compare).
library;

import 'package:flutter/foundation.dart';

import '../models/document.dart';
import '../services/firestore_service.dart';
import 'cloud_providers.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const _originPhrase = {
  'computer': 'Uploaded from your computer',
  'phone': 'Uploaded from your phone',
  'share_sheet': 'Shared from your phone',
};

/// *From your camera roll* · *From Google Drive* · *Uploaded from your
/// computer* · … · *Uploaded*.
String howPhrase(Document doc) {
  if (doc.fromCameraRoll) return 'From your camera roll';
  final provider = doc.cloudProvider;
  if (provider != null && provider.isNotEmpty) {
    return 'From ${cloudProviders[provider]?.name ?? provider}';
  }
  return _originPhrase[doc.uploadOrigin] ?? 'Uploaded';
}

String _lower(String s) => s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

/// `today` · `Oct 12` · `Oct 12, 2025` — on the reader's clock.
String _dayWords(int ms, DateTime now) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final n = now.toLocal();
  if (d.year == n.year && d.month == n.month && d.day == n.day) return 'today';
  final day = '${_months[d.month - 1]} ${d.day}';
  return d.year == n.year ? day : '$day, ${d.year}';
}

/// `9:03 AM` (web `toLocaleTimeString('en-US', {hour: 'numeric', minute:
/// '2-digit'})`).
String _clock(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
}

/// *Added today, 2:14 PM* · *Added Oct 12, 9:03 AM* · *Added Oct 12, 2025,
/// 9:03 AM* — null with no `created_at`.
String? addedLine(int? ms, {DateTime? now}) =>
    ms == null ? null : 'Added ${_dayWords(ms, now ?? DateTime.now())}, ${_clock(ms)}';

/// The row's line: *In your library since Oct 12 · from your camera roll*
/// (`screens/sources.md`: §Compare's words, lower-cased after the dot).
String? sinceLine(Document original, {DateTime? now}) {
  final ms = original.createdAt;
  if (ms == null) return null;
  return 'In your library since ${_dayWords(ms, now ?? DateTime.now())} · '
      '${_lower(howPhrase(original))}';
}

/// *3024 × 4032* — null without a stored picture size.
String? sizeLine(Document doc) {
  final w = doc.pictureWidth, h = doc.pictureHeight;
  return w != null && h != null && w > 0 && h > 0 ? '$w × $h' : null;
}

/// The row's line when the original could not be drawn from.
const originalGone = 'The original is no longer in your library.';
const originalUnread = 'The original couldn’t be read.';

/// One read per original, shared by every row and sheet that names it
/// (ADR-202 addendum 1). null: the reader's library holds no document by that
/// id — it was removed. A read that FAILS throws, and is never turned into
/// "no original"; it is not kept, so the next ask reads again (web
/// `readOriginal`). A removal is not kept either: the next ask says it again.
class OriginalRecords {
  OriginalRecords._();

  /// The read itself; a test sets it.
  @visibleForTesting
  static Future<Document?> Function(String docId) read =
      (id) => FirestoreService.instance.findOwnDocument(id);

  static final Map<String, Future<Document?>> _cache = {};

  static Future<Document?> of(String docId) => _cache.putIfAbsent(docId, () {
        // A read that throws before it starts (no Firestore here) is a read
        // that failed — said in the row's line, never thrown into a build.
        Future<Document?> f;
        try {
          f = read(docId);
        } catch (e, st) {
          f = Future<Document?>.error(e, st);
        }
        f.then<void>((d) {
          if (d == null) _cache.remove(docId);
        }, onError: (Object _) {
          _cache.remove(docId);
        });
        return f;
      });

  @visibleForTesting
  static void reset() => _cache.clear();
}
