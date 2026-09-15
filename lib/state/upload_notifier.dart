import 'package:flutter/foundation.dart';
import '../models/upload_file.dart';
import '../services/api.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/analytics.dart';

class UploadNotifier extends ChangeNotifier {
  final List<UploadFile> _files = [];
  final Map<String, Uint8List> _pendingBytes = {};

  List<UploadFile> get files => List.unmodifiable(_files);

  Future<void> addFile(
    String name,
    int size,
    Uint8List bytes,
    String mimeType,
  ) async {
    final file = UploadFile(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      size: size,
      mimeType: mimeType,
    );
    _files.add(file);
    _pendingBytes[file.id] = bytes;
    notifyListeners();
    await _uploadFile(file);
  }

  /// Batch image-set upload (contract 1.1.0): one `image_set` doc over up to 20
  /// images. createMultiImageSession → per-image bare PUT (INV-08) →
  /// signalUploadsComplete. Represented as a single upload row.
  Future<void> addImageSet(
    List<({String name, int size, Uint8List bytes, String mimeType})> images, {
    String? title,
  }) async {
    if (images.isEmpty) return;
    final set = images.take(20).toList(); // hard cap ≤20 (uploads.md)
    final setName =
        (title != null && title.trim().isNotEmpty) ? title.trim() : '${set.length} images';
    final file = UploadFile(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
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
  Future<String?> addUrl(String rawUrl) async {
    final url = rawUrl.trim();
    if (url.isEmpty) return null;

    final type = _detectUrlType(url);
    if (type == null) {
      return 'That doesn’t look like a link NoteLetter can read. Paste a full '
          'web address, or a YouTube, Instagram, TikTok or podcast link.';
    }

    final displayName =
        type == 'youtube' ? 'YouTube: ${_truncate(url)}' : _truncate(url);

    final file = UploadFile(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: displayName,
      size: 0,
      mimeType: 'text/html',
    );
    _files.add(file);
    notifyListeners();
    await _ingestUrl(file, url, type);
    // The row carries the reason; hand it back too, so the field the reader is
    // still looking at can say so and keep what they typed.
    final row = _files.firstWhere((f) => f.id == file.id, orElse: () => file);
    return row.status == UploadStatus.error ? row.errorMessage : null;
  }

  /// Canonical client-side detection table (INV-07) — mirrors web `detectUrlType()`.
  String? _detectUrlType(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || uri.host.isEmpty) return null;
    final host = uri.host.replaceFirst(RegExp(r'^www\.'), '');
    if (host == 'youtube.com' || host == 'youtu.be') return 'youtube';
    if (host == 'instagram.com') return 'instagram';
    if (host == 'tiktok.com' || host == 'vm.tiktok.com') return 'tiktok';
    if (host == 'podcasts.apple.com') return 'podcast';
    if (host == 'open.spotify.com' && uri.path.startsWith('/episode/')) return 'podcast';
    return 'article';
  }

  void removeFile(String id) {
    _files.removeWhere((f) => f.id == id);
    _pendingBytes.remove(id);
    notifyListeners();
  }

  void updateAuthor(String id, String author) {
    _patch(id, author: author);
  }

  void updateDescription(String id, String description) {
    _patch(id, description: description);
  }

  Future<void> _uploadFile(UploadFile file) async {
    final bytes = _pendingBytes[file.id];
    if (bytes == null) return;

    // `surface` is WHERE a capture came from, and it is the whole payload: no
    // filename, no mime type, no size. Started and completed are two events on
    // purpose — the gap between them is the abandonment this measures.
    Analytics.track('capture_started', {'surface': 'upload'});
    try {
      _patch(file.id, status: UploadStatus.uploading, progress: 0.1);

      final session = await Api.instance
          .createUploadSession(file.name, file.mimeType, file.size);

      final docId = session['docId'] as String;
      final uploadUrl = session['uploadUrl'] as String;
      _patch(file.id, docId: docId, progress: 0.25);

      await ApiService.instance.putBytes(uploadUrl, bytes, file.mimeType);

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
      _pendingBytes.remove(file.id);
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
      final docIds = (result['docIds'] as List?)?.cast<String>();
      _patch(file.id,
          status: UploadStatus.completed,
          progress: 1.0,
          docId: result['docId'] as String?,
          docIds: docIds);
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
    notifyListeners();
  }

  String _truncate(String url) {
    if (url.length <= 60) return url;
    return '${url.substring(0, 57)}...';
  }
}
