import 'package:flutter/foundation.dart';
import '../models/upload_file.dart';
import '../services/api.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/resumable_upload.dart';
import '../services/analytics.dart';
import '../shared/playlist.dart';

class UploadNotifier extends ChangeNotifier {
  final List<UploadFile> _files = [];
  /// What each single-file row still has to send, read a slice at a time
  /// (F-121) — never the whole file held in memory to be sent in one PUT.
  final Map<String, ChunkSource> _pending = {};
  int _seq = 0;

  List<UploadFile> get files => List.unmodifiable(_files);

  /// Row identity. A timestamp alone is not unique: `_pickFiles` starts every
  /// dropped file in one synchronous loop, and two of them can land in the
  /// same microsecond.
  String _newId() => '${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

  /// Returns the **row id**, so the caller can find its own row again. Two
  /// drops of the same filename are two rows, and a name is not an identity:
  /// looking one up by name reported the later row's status for both.
  ///
  /// [bytes] when the bytes are already in hand (a web pick, a test), or
  /// [source] to read them from disk a slice at a time — one is required.
  Future<String> addFile(
    String name,
    int size,
    Uint8List? bytes,
    String mimeType, {
    ChunkSource? source,
  }) async {
    final from = source ?? (bytes == null ? null : ChunkSource.bytes(bytes));
    if (from == null) {
      throw ArgumentError('addFile needs bytes or a source');
    }
    final file = UploadFile(
      id: _newId(),
      name: name,
      size: size,
      mimeType: mimeType,
    );
    _files.add(file);
    _pending[file.id] = from;
    notifyListeners();
    await _uploadFile(file);
    return file.id;
  }

  /// Batch image-set upload (contract 1.1.0): one `image_set` doc over up to 20
  /// images. createMultiImageSession → per-image bare PUT (INV-08) →
  /// signalUploadsComplete. Represented as a single upload row.
  /// Returns the row id (null when there was nothing to send) — same reason
  /// as `addFile`: `image/*` is a shape, not an identity.
  Future<String?> addImageSet(
    List<({String name, int size, Uint8List bytes, String mimeType})> images, {
    String? title,
  }) async {
    if (images.isEmpty) return null;
    final set = images.take(20).toList(); // hard cap ≤20 (uploads.md)
    final setName =
        (title != null && title.trim().isNotEmpty) ? title.trim() : '${set.length} images';
    final file = UploadFile(
      id: _newId(),
      name: setName,
      size: set.fold<int>(0, (a, im) => a + im.size),
      mimeType: 'image/*',
    );
    _files.add(file);
    notifyListeners();

    // An image set is one capture from the upload surface, not twenty.
    Analytics.track('capture_started', {'surface': 'upload'});
    try {
      _patch(file.id, status: UploadStatus.uploading, progress: 0.1);
      final filesMeta = set
          .map((im) =>
              {'filename': im.name, 'mimeType': im.mimeType, 'size': im.size})
          .toList();
      final session =
          await Api.instance.createMultiImageSession(filesMeta, setName);
      final docId = session['docId'] as String;
      final urls = (session['uploadUrls'] as List).cast<String>();
      _patch(file.id, docId: docId, progress: 0.2);

      for (var i = 0; i < set.length; i++) {
        await ApiService.instance.putBytes(urls[i], set[i].bytes, set[i].mimeType);
        _patch(file.id, progress: 0.2 + 0.7 * ((i + 1) / set.length));
      }

      // Signal only after every image PUT succeeded (uploads.md).
      await Api.instance.signalUploadsComplete(docId);
      _patch(file.id, status: UploadStatus.completed, progress: 1.0);
      Analytics.track('capture_completed', {'surface': 'upload'});
    } on UnauthorizedException {
      await AuthService.instance.signOut();
      _patch(file.id,
          status: UploadStatus.error, errorMessage: 'Session expired.');
    } on ApiException catch (e) {
      _patch(file.id, status: UploadStatus.error, errorMessage: e.message);
    } catch (_) {
      _patch(file.id,
          status: UploadStatus.error,
          errorMessage: 'Image upload failed. Please try again.');
    }
    return file.id;
  }

  /// Add a link. Returns a **rejection message**, or null when the request was
  /// made — the same contract as `uploadRejection`, and for the same reason.
  ///
  /// **A link refused at the door creates no document row**, so unlike every
  /// other ingest failure there is no tray entry to carry the reason: the
  /// caller has to render it at the point of paste or it is not rendered at
  /// all. That is the whole of 4.19.3 — the reference caught a clear 400 into
  /// `console.error`, the field cleared, no row appeared, and the paste
  /// vanished. Here the local INV-07 refusal did the same thing one step
  /// earlier, by returning silently.
  Future<String?> addUrl(String rawUrl) async =>
      (await shareUrl(rawUrl)).rejection;

  /// [addUrl] for the share screen (F-123), which also says what was added:
  /// [note] is the playlist's sentence when the answer was a playlist
  /// (4.114.0, ADR-151), null for a single link.
  Future<({String? rejection, String? note})> shareUrl(String rawUrl) async {
    if (rawUrl.trim().isEmpty) return (rejection: null, note: null);

    // Normalize, then detect (4.86.0, ADR-120): the normalized string is what
    // fn_ingest_url is sent, verbatim.
    final url = normalizeUrl(rawUrl);
    final type = url == null ? null : detectUrlType(url);
    if (url == null || type == null) {
      return (
        rejection: 'That doesn’t look like a link NoteLetter can read. Paste a full '
            'web address, or a YouTube, Instagram, TikTok or podcast link.',
        note: null,
      );
    }

    final displayName =
        type == 'youtube' ? 'YouTube: ${_truncate(url)}' : _truncate(url);

    final file = UploadFile(
      id: _newId(),
      name: displayName,
      size: 0,
      mimeType: 'text/html',
      linkType: type,
    );
    _files.add(file);
    notifyListeners();
    await _ingestUrl(file, url, type);
    // The row carries the reason; hand it back too, so the field the reader is
    // still looking at can say so and keep what they typed.
    final row = _files.firstWhere((f) => f.id == file.id, orElse: () => file);
    return row.status == UploadStatus.error
        ? (rejection: row.errorMessage, note: null)
        : (rejection: null, note: row.note);
  }

  void removeFile(String id) {
    _files.removeWhere((f) => f.id == id);
    _pending.remove(id);
    notifyListeners();
  }

  void updateAuthor(String id, String author) {
    _patch(id, author: author);
  }

  void updateDescription(String id, String description) {
    _patch(id, description: description);
  }

  Future<void> _uploadFile(UploadFile file) async {
    final source = _pending[file.id];
    if (source == null) return;

    // `surface` is WHERE a capture came from, and it is the whole payload: no
    // filename, no mime type, no size. Started and completed are two events on
    // purpose — the gap between them is the abandonment this measures.
    Analytics.track('capture_started', {'surface': 'upload'});
    try {
      _patch(file.id, status: UploadStatus.uploading, progress: 0.1);

      final session = await Api.instance
          .createUploadSession(file.name, file.mimeType, file.size);

      final docId = session['docId'] as String;
      _patch(file.id, docId: docId, progress: 0.25);

      // F-121 (INV-08, ADR-050): through the resumable session, as on web —
      // chunked, resumed from what the session committed, and never the bare
      // PUT of the whole file in memory that a long recording could not
      // survive. The bar moves only with committed bytes.
      await ApiService.instance.putResumable(
        resumableUrl: (session['resumableUrl'] as String?) ?? '',
        docId: docId,
        filename: file.name,
        mimeType: file.mimeType,
        source: source,
        onProgress: (f) => _patch(file.id, progress: 0.25 + 0.75 * f),
      );

      _patch(file.id, status: UploadStatus.completed, progress: 1.0);
      Analytics.track('capture_completed', {'surface': 'upload'});
    } on UnauthorizedException {
      await AuthService.instance.signOut();
      _patch(file.id, status: UploadStatus.error, errorMessage: 'Session expired.');
    } on ApiException catch (e) {
      _patch(file.id, status: UploadStatus.error, errorMessage: e.message);
    } catch (_) {
      _patch(file.id, status: UploadStatus.error,
          errorMessage: 'Upload failed. Please try again.');
    } finally {
      _pending.remove(file.id);
    }
  }

  Future<void> _ingestUrl(UploadFile file, String url, String type) async {
    // The URL itself is never sent. It is somebody's reading, and a URL is
    // legible where a Firestore id is not — the worst of the fields ADR-081
    // found on the wire (INV-25b).
    Analytics.track('capture_started', {'surface': 'url'});
    try {
      _patch(file.id, status: UploadStatus.uploading, progress: 0.5);

      final result = await Api.instance.ingestUrl(url, type);

      // Response has either a single `docId` or a playlist `docIds` (INV-07).
      // A playlist's answer is ONE success, said with the measured count
      // (4.114.0, ADR-151); a single link keeps the row's own line.
      final docIds = (result['docIds'] as List?)?.cast<String>();
      _patch(file.id,
          status: UploadStatus.completed,
          progress: 1.0,
          docId: result['docId'] as String?,
          docIds: docIds,
          note: playlistAdded(result));
      Analytics.track('capture_completed', {'surface': 'url'});
    } on UnauthorizedException {
      await AuthService.instance.signOut();
      _patch(file.id, status: UploadStatus.error, errorMessage: 'Session expired.');
    } on ApiException catch (e) {
      _patch(file.id, status: UploadStatus.error, errorMessage: e.message);
    } catch (_) {
      _patch(file.id, status: UploadStatus.error,
          errorMessage: 'Failed to ingest URL. Please try again.');
    }
  }

  void _patch(
    String id, {
    UploadStatus? status,
    double? progress,
    String? author,
    String? description,
    String? docId,
    List<String>? docIds,
    String? errorMessage,
    String? note,
  }) {
    final index = _files.indexWhere((f) => f.id == id);
    if (index == -1) return;
    final f = _files[index];
    if (status != null) f.status = status;
    if (progress != null) f.progress = progress;
    if (author != null) f.author = author;
    if (description != null) f.description = description;
    if (docId != null) f.docId = docId;
    if (docIds != null) f.docIds = docIds;
    if (errorMessage != null) f.errorMessage = errorMessage;
    if (note != null) f.note = note;
    notifyListeners();
  }

  String _truncate(String url) {
    if (url.length <= 60) return url;
    return '${url.substring(0, 57)}...';
  }
}

// Normalize, then detect (INV-07, 4.86.0, ADR-120 — api/ingest.md). Mirrors web
// `normalizeUrl()`: an address bar shows `www.instagram.com/reel/…` with no
// scheme; a leading dotted host gets `https://`. Returns the string
// fn_ingest_url is sent (verbatim, never the parser's re-serialisation), or
// null to reject locally. Only http(s); the host must contain a dot.
final RegExp _bareHost =
    RegExp(r'^[^\s/?#:]+\.[^\s/?#:]+(?::\d+)?(?:[/?#]\S*)?$');
final RegExp _scheme = RegExp(r'^[a-z][a-z0-9+.-]*:', caseSensitive: false);

String? normalizeUrl(String? input) {
  final t = (input ?? '').trim();
  if (t.isEmpty || RegExp(r'\s').hasMatch(t)) return null;
  final hasScheme = _scheme.hasMatch(t) && !_bareHost.hasMatch(t);
  final candidate = hasScheme ? t : (_bareHost.hasMatch(t) ? 'https://$t' : null);
  if (candidate == null) return null;
  final uri = Uri.tryParse(candidate);
  if (uri == null) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  if (!uri.host.contains('.')) return null;
  // Lower-case scheme and host only; path/query/fragment byte for byte.
  return candidate.replaceFirstMapped(
      RegExp(r'^([a-z][a-z0-9+.-]*://)([^/?#]*)', caseSensitive: false),
      (m) => '${m[1]!.toLowerCase()}${m[2]!.toLowerCase()}');
}

/// A post on any other video platform (5.32.0, ADR-189; api/ingest.md) —
/// mirrors web `SOCIAL_VIDEO_HOSTS`. Matched on the hostname's labels, never as
/// a substring (`phoenix.com` holds `x.com`); Threads stays an article.
const List<String> kSocialVideoHosts = <String>[
  'facebook.com', 'fb.watch', 'x.com', 'twitter.com', 'reddit.com', 'redd.it',
  'vimeo.com', 'linkedin.com', 'bsky.app', 'dailymotion.com', 'dai.ly',
  'twitch.tv', 'rumble.com', 'streamable.com', 'loom.com', 'pinterest.com',
  'pin.it', 'snapchat.com',
];

/// Canonical client-side detection table (INV-07) — mirrors web `detectUrlType()`.
String? detectUrlType(String? input) {
  final url = normalizeUrl(input);
  if (url == null) return null;
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return null;
  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  // 4.114.0 (ADR-151): a playlist page is a playlist — checked BEFORE the
  // video row. Only `/playlist` with a non-empty `list`: a `watch?v=…&list=…`
  // link is the one video the reader opened, and stays `youtube`.
  if (host == 'youtube.com' &&
      uri.path == '/playlist' &&
      (uri.queryParameters['list'] ?? '').isNotEmpty) {
    return playlistType;
  }
  if (host == 'youtube.com' || host == 'youtu.be') return 'youtube';
  if (host == 'instagram.com') return 'instagram';
  if (host == 'tiktok.com' || host == 'vm.tiktok.com') return 'tiktok';
  if (host == 'podcasts.apple.com') return 'podcast';
  if (host == 'open.spotify.com' && uri.path.startsWith('/episode/')) return 'podcast';
  if (kSocialVideoHosts.any((d) => host == d || host.endsWith('.$d'))) {
    return 'social_video';
  }
  return 'article';
}
