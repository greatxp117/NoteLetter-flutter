import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// A system picker no test can drive, stood in for (F-152): answers every pick
/// with [files] and records what was asked. Install with [FakePicker.install],
/// which hands back the real one to restore.
class FakePicker extends FilePicker {
  FakePicker(this.files);

  List<PlatformFile> files;
  final asked = <FileType>[];

  static FilePicker install(List<PlatformFile> files) {
    final real = FilePicker.platform;
    FilePicker.platform = FakePicker(files);
    return real;
  }

  /// [n] screenshots of one scroll, named as a phone names them — what web's
  /// `quickadd-image-set` frame drops (`IMG_2040.PNG`…). Bytes are a token:
  /// nothing is sent until the one-source question is answered.
  static List<PlatformFile> screenshots(int n) => [
        for (var i = 0; i < n; i++)
          PlatformFile(
              name: 'IMG_${2040 + i}.PNG',
              size: 4,
              bytes: Uint8List.fromList([137, 80, 78, 71])),
      ];

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    asked.add(type);
    return FilePickerResult(files);
  }
}
