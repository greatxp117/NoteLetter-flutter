import 'package:flutter/foundation.dart';
import '../models/upload_file.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

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

  Future<void> addUrl(String rawUrl) async {
    final url = rawUrl.trim();
    if (url.isEmpty) return;

    final isYoutube = url.contains('youtube.com') || url.contains('youtu.be');
    final displayName = isYoutube
        ? 'YouTube: ${_truncate(url)}'
        : _truncate(url);

    final file = UploadFile(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: displayName,
      size: 0,
      mimeType: 'text/html',
    );
    _files.add(file);
    notifyListeners();
    await _ingestUrl(file, url, isYoutube);
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

    try {
      _patch(file.id, status: UploadStatus.uploading, progress: 0.1);

      final session = await ApiService.instance.post(
        '/fn_create_upload_session',
        data: {
          'filename': file.name,
          'mimeType': file.mimeType,
          'size': file.size,
        },
      );

      final docId = session['docId'] as String;
      final uploadUrl = session['uploadUrl'] as String;
      _patch(file.id, docId: docId, progress: 0.25);

      await ApiService.instance.putBytes(uploadUrl, bytes, file.mimeType);

      _patch(file.id, status: UploadStatus.completed, progress: 1.0);
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

  Future<void> _ingestUrl(UploadFile file, String url, bool isYoutube) async {
    try {
      _patch(file.id, status: UploadStatus.uploading, progress: 0.5);

      final endpoint = isYoutube ? '/fn_ingest_youtube' : '/fn_ingest_url';
      final result =
          await ApiService.instance.post(endpoint, data: {'url': url});

      _patch(file.id,
          status: UploadStatus.completed,
          progress: 1.0,
          docId: result['docId'] as String?);
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
    if (errorMessage != null) f.errorMessage = errorMessage;
    notifyListeners();
  }

  String _truncate(String url) {
    if (url.length <= 60) return url;
    return '${url.substring(0, 57)}...';
  }
}
