import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'page_drop.dart';

/// A web build: the page's own drag events, on the document, feed
/// [controller] (web `usePageDrop`'s handlers). A drag of anything but files
/// (a selection, a link) is not ours and is left to the browser.
VoidCallback attach(PageDropController controller) {
  bool isFiles(web.Event e) {
    final types = (e as web.DragEvent).dataTransfer?.types.toDart ?? const [];
    return types.any((t) => t.toDart == 'Files');
  }

  final enter = ((web.Event e) {
    controller.enter(files: isFiles(e));
  }).toJS;
  final leave = ((web.Event e) {
    controller.leave();
  }).toJS;
  final over = ((web.Event e) {
    // Without this the browser opens the file in the tab instead.
    if (isFiles(e)) e.preventDefault();
  }).toJS;
  final drop = ((web.Event e) {
    final list = (e as web.DragEvent).dataTransfer?.files;
    if (list == null || list.length == 0) {
      controller.drop(const []);
      return;
    }
    e.preventDefault();
    final files = [
      for (var i = 0; i < list.length; i++) ?list.item(i),
    ];
    // The bytes are read before anything is filed: a drop hands a File, and
    // the upload sends bytes, as a web pick does (`withData: kIsWeb`).
    Future.wait(files.map((f) async {
      final buf = await f.arrayBuffer().toDart;
      return DroppedFile(
          name: f.name, size: f.size, bytes: buf.toDart.asUint8List());
    })).then(controller.drop, onError: (_) => controller.drop(const []));
  }).toJS;

  final doc = web.document;
  doc.addEventListener('dragenter', enter);
  doc.addEventListener('dragleave', leave);
  doc.addEventListener('dragover', over);
  doc.addEventListener('drop', drop);
  return () {
    doc.removeEventListener('dragenter', enter);
    doc.removeEventListener('dragleave', leave);
    doc.removeEventListener('dragover', over);
    doc.removeEventListener('drop', drop);
  };
}
