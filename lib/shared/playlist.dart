// A YouTube playlist link (4.114.0, ADR-151 — api/ingest.md §A playlist link).
// Mirrors web `shared/playlist.js`.
//
// `detectUrlType()` names a `youtube.com/playlist?list=…` link
// `youtube_playlist`, and `fn_ingest_url` answers it with `docIds` — one
// queued document per video — instead of one `docId`. That answer is ONE
// success, stated with the measured count the server returned, and there is no
// single document to open. `warnings` is never rendered: it can carry yt-dlp's
// own text, which is not a sentence we wrote.
import '../widgets/kit/kit.dart' show kitDocKind;

const String playlistType = 'youtube_playlist';
const String playlistLabel = 'YouTube playlist';

/// The badge a pending link draws. A playlist is not a document `type` — the
/// documents it makes are `youtube` — so it draws as YouTube rather than
/// falling through §6.4.1's table to NOTE.
String pendingBadgeKind(String type) =>
    kitDocKind(type == playlistType ? 'youtube' : type);

/// `toLocaleString()` for a count: thousands grouped with commas.
String _grouped(int n) =>
    '$n'.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');

/// The sentence for a `docIds` answer, or null for a single-document one.
/// Counts are the answer's own fields (`enqueued`, `failed`, `notStarted`) —
/// never `docIds.length` re-derived.
String? playlistAdded(Map<String, dynamic>? res) {
  if (res == null || res['docIds'] is! List) return null;
  final enqueued = res['enqueued'];
  if (enqueued is! num || !enqueued.isFinite) return null;
  final n = enqueued.toInt();
  final parts = <String>[
    'Added ${_grouped(n)} ${n == 1 ? 'video' : 'videos'} from this playlist.',
  ];
  final failed = res['failed'];
  if (failed is List && failed.isNotEmpty) {
    parts.add('One could not be started — retry it from your library.');
  }
  final notStarted = res['notStarted'];
  if (notStarted is num && notStarted.isFinite && notStarted > 0) {
    final k = notStarted.toInt();
    parts.add(k == 1
        ? 'The 1 after it was not added.'
        : 'The ${_grouped(k)} after it were not added.');
  }
  return parts.join(' ');
}
