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
