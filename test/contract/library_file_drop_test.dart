// The Library takes a file dropped anywhere on it, on a web build (Xavier
// 2026-11-05: `web` as a direct dependency; web `usePageDrop`,
// pages/sources/intake.jsx; sources.md §Composition, Frame). A drag of files
// draws the veil; a drop files them exactly as the drop zone does. A device
// build has no page-wide drop.
//
// The browser binding (lib/shared/page_drop_web.dart) runs only in a browser;
// `flutter build web` compiles it. What it feeds is tested here.
//
// Mutants run against it (each red): the depth count dropped (a leave over a
// child clears the veil mid-drag); a drag of something that is not files
// drawing the veil; the drop skipping the upload rule; the page never drawing
// the veil; the conditional import pointed at the web binding for every
// build.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/services/resumable_upload.dart' show ChunkSource;
import 'package:flutter_app/shared/page_drop.dart';
import 'package:flutter_app/state/upload_notifier.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

import 'sources_harness.dart';

/// Records what the intake filed, sends nothing.
class _Recording extends UploadNotifier {
  final added = <String>[];

  @override
  Future<String> addFile(
    String name,
    int size,
    Uint8List? bytes,
    String mimeType, {
    ChunkSource? source,
    void Function(String rowId)? onRow,
    String? origin,
  }) async {
    added.add(name);
    return 'row-$name';
  }
}

DroppedFile _file(String name) =>
    DroppedFile(name: name, size: 5, bytes: Uint8List.fromList([1, 2, 3, 4, 5]));

void main() {
  group('the drag', () {
    test('the veil holds while the drag crosses children, and only for files',
        () {
      final c = PageDropController();
      c.enter(files: false);
      expect(c.over, isFalse, reason: 'a selection or a link is not ours');
      c.enter(files: true);
      c.enter(files: true); // into a child
      c.leave(); // out of the parent, still over the child
      expect(c.over, isTrue);
      c.leave();
      expect(c.over, isFalse);
    });

    test('a drop clears the veil and hands the files on; an empty one nothing',
        () {
      final got = <List<DroppedFile>>[];
      final c = PageDropController(onFiles: got.add);
      c.enter(files: true);
      c.drop(const []);
      expect(c.over, isFalse);
      expect(got, isEmpty);
      c.enter(files: true);
      c.drop([_file('Essay.pdf')]);
      expect(got.single.single.name, 'Essay.pdf');
    });
  });

  test('a drop is filed as the drop zone files it: the upload rule first', () {
    final n = _Recording();
    intakeDroppedFiles(n, [_file('Essay.pdf'), _file('main.py')]);
    expect(n.added, ['Essay.pdf']);
    expect(n.refused.single.name, 'main.py');
    expect(n.refused.single.reason, contains('Source code files aren’t supported'));
  });

  // A folder dragged in beside files: the browser hands it as a File whose read
  // rejects. Until 5.68.0 one rejection dropped the whole drop, with no sentence.
  test('a file that could not be read is said; the others are filed', () {
    final n = _Recording();
    intakeDroppedFiles(n, [
      _file('Essay.pdf'),
      const DroppedFile(name: 'Notes.pdf', size: 12),
    ]);
    expect(n.added, ['Essay.pdf']);
    expect(n.refused.single.name, 'Notes.pdf');
    expect(n.refused.single.reason, droppedFileUnreadable);
  });

  test('a folder is refused by the same rule a picked file is', () {
    final n = _Recording();
    intakeDroppedFiles(n, [const DroppedFile(name: 'Photos', size: 0)]);
    expect(n.added, isEmpty);
    expect(n.refused.single.name, 'Photos');
    expect(n.refused.single.reason, isNot(droppedFileUnreadable),
        reason: "the upload rule answers first, in web's words");
  });

  testWidgets('the Library draws the veil over the page and files the drop',
      (tester) async {
    final upload = _Recording();
    final drop = PageDropController();
    await pumpSources(tester, SourcesStubService(), upload: upload, drop: drop);
    expect(find.byType(KitDropVeil), findsNothing);
    drop.enter(files: true);
    await tester.pump();
    expect(find.byType(KitDropVeil), findsOneWidget);
    expect(find.text('Drop to add to your library'), findsOneWidget);
    expect(
        find.text('Each file is read, indexed, and shelved as it arrives.'),
        findsOneWidget);
    drop.drop([_file('Essay.pdf')]);
    await tester.pump();
    expect(find.byType(KitDropVeil), findsNothing);
    expect(upload.added, ['Essay.pdf']);
  });

  test('a device build gets the no-op binding, a web build the browser\'s', () {
    final src = File('lib/shared/page_drop.dart').readAsStringSync();
    expect(src, contains("import 'page_drop_stub.dart'"));
    expect(src, contains("if (dart.library.js_interop) 'page_drop_web.dart'"));
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(RegExp(r'^  web: \^1\.1\.1$', multiLine: true).hasMatch(pubspec),
        isTrue,
        reason: 'the browser binding needs `web` declared, not only resolved');
  });
}
