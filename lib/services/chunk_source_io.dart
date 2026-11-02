import 'dart:io';
import 'dart:typed_data';

import 'resumable_upload.dart';

/// A file read one slice at a time, so an upload never holds the whole file.
ChunkSource fileChunkSource(String path, int length) =>
    _FileSource(path, length);

class _FileSource implements ChunkSource {
  _FileSource(this.path, this.length);
  final String path;
  @override
  final int length;

  @override
  Future<Uint8List> read(int start, int end) async {
    final f = await File(path).open();
    try {
      await f.setPosition(start);
      return await f.read(end - start);
    } finally {
      await f.close();
    }
  }
}

/// When the file at [path] was last modified, in milliseconds since the epoch
/// — 0 when it cannot be read. A set's pages go oldest first (F-152, web
/// `orderFrames`'s `lastModified`); a picker hands over no time of its own.
int fileModifiedMs(String path) {
  try {
    return File(path).lastModifiedSync().millisecondsSinceEpoch;
  } catch (_) {
    return 0;
  }
}
