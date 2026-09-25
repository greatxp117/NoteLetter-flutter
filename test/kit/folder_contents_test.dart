import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/pages/sources/folder_contents.dart';
import 'package:flutter_app/services/api_service.dart' show ApiException;
import 'package:flutter_app/theme/app_theme.dart';

/// `screens/sources.md` §Folder contents (4.59.0, ADR-096; QUEUE F-23). Each
/// case is one sentence of that section.
void main() {
  var calls = 0;

  Future<void> pump(WidgetTester tester,
      Future<Map<String, dynamic>> Function() scan) async {
    calls = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: FolderContents(
          provider: 'google_drive',
          folderId: 'fld-1',
          onFixTypes: () {},
          scan: () {
            calls++;
            return scan();
          },
        ),
      ),
    ));
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('What’s in here?'));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a disclosure, never automatic', (tester) async {
    await pump(tester, () async => {});
    expect(calls, 0);
    expect(find.text('What’s in here?'), findsOneWidget);
  });

  testWidgets('the two unimported buckets are drawn apart', (tester) async {
    await pump(
        tester,
        () async => {
              'scanned': {'files': 412, 'folders': 9, 'depth': 3},
              'complete': true,
              'importable': {'pdf': 12, 'docx': 4},
              'excluded_by_settings': {'pptx': 2},
              'excluded_by_pattern': 1,
              'unreadable': 381,
              'held_for_review': 3,
            });
    await open(tester);
    expect(calls, 1);
    expect(find.text('scanned 412 files, 4 levels'), findsOneWidget);
    expect(find.text('12 PDF · 4 Word'), findsOneWidget);
    expect(find.text('…3 will wait for your review'), findsOneWidget);
    // The setting carries its control; the fact carries none.
    expect(
        find.text(
            '2 PowerPoint excluded by your settings · 1 excluded by your patterns'),
        findsOneWidget);
    expect(find.text('Change types'), findsOneWidget);
    expect(find.text('381 NoteLetter can’t read'), findsOneWidget);
    expect(find.textContaining('will be imported'), findsNothing);
  });

  testWidgets('a partial scan is a floor, and says so', (tester) async {
    await pump(
        tester,
        () async => {
              'scanned': {'files': 500, 'folders': 3, 'depth': 0},
              'complete': false,
              'stopped_reason': 'file_cap',
              'importable': {'pdf': 88},
              'excluded_by_settings': <String, dynamic>{},
              'excluded_by_pattern': 0,
              'unreadable': 0,
              'held_for_review': 0,
            });
    await open(tester);
    expect(find.text('at least 88 PDF'), findsOneWidget);
    expect(find.text('counted 500 of more — open it to see the rest'),
        findsOneWidget);
  });

  testWidgets('empty is a measurement', (tester) async {
    await pump(
        tester,
        () async => {
              'scanned': {'files': 0, 'folders': 0, 'depth': 0},
              'complete': true,
              'importable': <String, dynamic>{},
              'excluded_by_settings': <String, dynamic>{},
              'excluded_by_pattern': 0,
              'unreadable': 0,
              'held_for_review': 0,
            });
    await open(tester);
    expect(find.text('Nothing in here NoteLetter can read.'), findsOneWidget);
  });

  testWidgets('excluded is not unreadable — no "can read" over a settings gap',
      (tester) async {
    await pump(
        tester,
        () async => {
              'scanned': {'files': 8, 'folders': 2, 'depth': 1},
              'complete': true,
              'importable': <String, dynamic>{},
              'excluded_by_settings': {'pdf': 4, 'pptx': 2, 'docx': 1},
              'excluded_by_pattern': 0,
              'unreadable': 1,
              'held_for_review': 0,
            });
    await open(tester);
    expect(find.textContaining('Nothing in here'), findsNothing);
    expect(find.text('4 PDF · 2 PowerPoint · 1 Word excluded by your settings'),
        findsOneWidget);
    expect(find.text('1 NoteLetter can’t read'), findsOneWidget);
  });

  testWidgets('a failure is a hole with a retry, never a zero',
      (tester) async {
    var fail = true;
    await pump(tester, () async {
      if (fail) {
        throw const ApiException(502, 'The provider did not answer.',
            serverSentence: true);
      }
      return {
        'scanned': {'files': 2, 'folders': 0, 'depth': 0},
        'complete': true,
        'importable': {'pdf': 2},
      };
    });
    await open(tester);
    expect(find.text('The provider did not answer.'), findsOneWidget);
    expect(find.textContaining('Nothing in here'), findsNothing);
    fail = false;
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();
    expect(calls, 2);
    expect(find.text('2 PDF'), findsOneWidget);
  });
}
