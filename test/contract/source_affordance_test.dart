/// sources.md §Document processing — every processing row offers its source,
/// chosen by the document's SHAPE (§6.4.2), and the control carries the
/// reference's glyph for it (web `SourceAffordance`: IcoExternal / IcoLayers /
/// IcoFile). The label said what opens; until 2026-10-05 nothing said whether
/// it opened outside the app.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/pages/sources/source_sheet.dart';

Document _doc(String type, {String? gcsPath, String? sourceUrl}) => Document(
      id: 'd',
      userId: 'u',
      title: 't',
      type: type,
      status: DocumentStatus.error,
      gcsPath: gcsPath,
      sourceUrl: sourceUrl,
    );

void main() {
  test('each shape has its label and its glyph, together', () {
    final cases = {
      _doc('pdf', gcsPath: 'u/d.pdf'): ('View file', Icons.insert_drive_file_outlined),
      _doc('url', sourceUrl: 'https://example.com/a'): ('Open the link', Icons.open_in_new),
      _doc('image_set'): ('View images', Icons.layers_outlined),
    };
    cases.forEach((doc, want) {
      expect(SourceSheet.labelFor(doc), want.$1, reason: doc.type);
      expect(SourceSheet.iconFor(doc), want.$2, reason: doc.type);
    });
  });
}
