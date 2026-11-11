/// F-186 (3) · The manuscript's read-only line in web's words, apostrophe
/// included (ManuscriptPanel.jsx: *how it’s split into passages*). A source
/// read, not a pump: the panel needs a document, its chunks and a reader
/// around it, and the claim here is one character of one sentence.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the manuscript says it’s with web’s curly apostrophe', () {
    final src = File('lib/pages/reader/manuscript_panel.dart').readAsStringSync();
    expect(src, contains('adjust how it’s split into passages'));
    expect(src, isNot(contains("adjust how it's split")),
        reason: 'a straight apostrophe in copy web sets curly');
  });
}
