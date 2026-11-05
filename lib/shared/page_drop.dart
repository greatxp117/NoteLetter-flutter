import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';

import '../state/upload_notifier.dart';
import 'upload_types.dart';
import 'page_drop_stub.dart'
    if (dart.library.js_interop) 'page_drop_web.dart' as binding;

/// The Library takes a file dropped anywhere on it (`screens/sources.md`
/// §Composition, Frame; web `usePageDrop`, `pages/sources/intake.jsx`). Only a
/// web build can be handed a file this way: on a device the drop zone and the
/// picker are the way in, so [attachPageDrop] is a no-op there. Xavier
/// 2026-11-05, which took `web` as a direct dependency.

/// One dropped file, read whole: a browser hands a drop no path.
class DroppedFile {
  final String name;
  final int size;
  final Uint8List bytes;

  const DroppedFile(
      {required this.name, required this.size, required this.bytes});
}

/// Whether a drag over the page is a drag of FILES, and where it is (web's
/// enter/leave depth: a drag crossing a child fires leave on the parent
/// before enter on the child, so a plain flag flickers). Pure, so the rule is
/// tested off a browser; the binding feeds it the page's events.
class PageDropController extends ChangeNotifier {
  PageDropController({this.onFiles});

  /// Called with what was dropped, once its bytes are read. The page that
  /// hosts the drop sets it, to its own intake.
  void Function(List<DroppedFile> files)? onFiles;

  int _depth = 0;
  bool _over = false;

  /// The veil is drawn while this is true.
  bool get over => _over;

  void enter({required bool files}) {
    if (!files) return;
    _depth += 1;
    _set(true);
  }

  void leave() {
    _depth = _depth > 0 ? _depth - 1 : 0;
    if (_depth == 0) _set(false);
  }

  void drop(List<DroppedFile> files) {
    _depth = 0;
    _set(false);
    if (files.isNotEmpty) onFiles?.call(files);
  }

  void _set(bool v) {
    if (v == _over) return;
    _over = v;
    notifyListeners();
  }
}

/// Listens for file drags on the whole page (web only) and feeds
/// [controller]; the returned function stops listening.
VoidCallback attachPageDrop(PageDropController controller) =>
    binding.attach(controller);

/// Files a drop exactly as the drop zone's picker does (web `intake.addFiles`):
/// a new intake, each file through the upload rule first — a refusal is said
/// in *what adding answered* in the server's own words — then queued by row.
void intakeDroppedFiles(UploadNotifier notifier, List<DroppedFile> files) {
  notifier.beginIntake();
  for (final f in files) {
    final mimeType = lookupMimeType(f.name) ?? 'application/octet-stream';
    final refused =
        uploadRejection(name: f.name, size: f.size, mimeType: mimeType);
    if (refused != null) {
      notifier.refuse(f.name, refused);
      continue;
    }
    notifier.addFile(f.name, f.size, f.bytes, mimeType);
  }
}
