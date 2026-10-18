import 'resumable_upload.dart';

/// The web build has no file paths: a pick there carries its bytes.
ChunkSource fileChunkSource(String path, int length) =>
    throw UnsupportedError('A file path cannot be read on the web.');
