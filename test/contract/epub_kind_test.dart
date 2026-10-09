import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/pages/search_page.dart' show searchSourceTypes;
import 'package:flutter_app/shared/upload_types.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

/// EPUB is a live kind (ADR-152): the picker offers it, the upload rule reads
/// it as its own class, it is a stored `file`, and Search's "Books & PDFs"
/// chip SENDS it — a fold the gate used to assume while the request carried
/// `pdf` alone.
void main() {
  test('the picker offers .epub, and the drop zone names it', () {
    expect(uploadAllowedExtensions, contains('epub'));
    expect(uploadAcceptHelp, contains('EPUB'));
  });

  test('an EPUB is accepted by its type or, untyped, by its extension', () {
    expect(uploadRejection(name: 'book.epub', size: 1024,
        mimeType: 'application/epub+zip'), isNull);
    expect(uploadRejection(name: 'book.epub', size: 1024), isNull);
    expect(uploadRejection(name: 'book.epub', size: 1024,
        mimeType: 'application/octet-stream'), isNull);
    expect(uploadRejection(name: 'book.pdf', size: 1024,
        mimeType: 'application/epub+zip'),
        '“book.pdf” is declared as application/epub+zip but has a .pdf extension.');
    expect(uploadRejection(name: 'book.epub', size: 101 * 1024 * 1024),
        'That file is over the 100 MB limit.');
  });

  test('an EPUB plates as EPUB and its source is a stored file', () {
    expect(kitDocKind('epub'), 'epub');
    expect(kitKindLabel('epub'), 'EPUB');
    expect(kitSourceShape(type: 'epub'), 'file');
  });

  test('"Books & PDFs" sends the folded kind; every other chip sends its own',
      () {
    expect(searchSourceTypes('pdf'), unorderedEquals(['pdf', 'epub']));
    expect(searchSourceTypes('web'), unorderedEquals(['article', 'url']));
    expect(searchSourceTypes('video'), ['video']);
  });
}
