/// The reader names a document by its KIND, never by its raw `type`
/// (web 938a2f4, `tests/contract/reader-kind-label.test.js`; iOS b24d2fd).
///
/// The Original section's rail jump and its eyebrow printed
/// `doc.type.toUpperCase()`: an image set read "IMAGE_SET" — an enum, with its
/// underscore — beside a header plate that says NOTE, and a slide deck read
/// "PPTX" where every other surface calls it a note. §6.4.1 is the one
/// vocabulary for what a document renders as; this holds both reader surfaces
/// to it, the image set first.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/pages/reader/original_panel.dart';
import 'package:flutter_app/pages/reader_page.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// `fn_get_raw_document_url` answering "no object" — a set carries its pages
/// in `members`, a file has none. The panel's eyebrow is drawn either way.
class _NoObject implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return ResponseBody.fromString(
      jsonEncode({'signed_url': null, 'members': []}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Document _doc(String type, {String? gcsPath, String? sourceUrl}) => Document(
      id: 'doc-1',
      userId: 'seed-user-1',
      title: 'Four photographs',
      type: type,
      status: DocumentStatus.complete,
      gcsPath: gcsPath,
      sourceUrl: sourceUrl,
    );

Future<void> _pumpPanel(WidgetTester tester, Document doc) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: SingleChildScrollView(
        child: OriginalPanel(docId: doc.id, doc: doc),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('kitKindLabel is the §6.4.1 plate word', () {
    test('names every writable type by its kind', () {
      // Web's table, verbatim (reader-kind-label.test.js).
      const want = {
        'pdf': 'PDF', 'plain': 'NOTE', 'docx': 'NOTE', 'pptx': 'NOTE',
        'image': 'NOTE', 'image_set': 'NOTE', 'article': 'WEB', 'youtube': 'YT',
        'instagram': 'IG', 'tiktok': 'TT', 'podcast': 'AUDIO', 'audio': 'AUDIO',
        'video': 'VIDEO',
      };
      want.forEach((type, label) => expect(kitKindLabel(type), label, reason: type));
      // Every type the table declares is answered — nothing falls to a raw word.
      for (final type in kKindByType.keys) {
        expect(kitKindLabel(type), matches(RegExp(r'^[A-Z]+$')), reason: type);
      }
    });

    test('never returns the type itself', () {
      for (final type in kKindByType.keys) {
        // These four are their own kind's word.
        if (const {'pdf', 'epub', 'audio', 'video'}.contains(type)) continue;
        expect(kitKindLabel(type), isNot(type.toUpperCase()), reason: type);
      }
    });
  });

  group("the rail's Original jump counts the KIND", () {
    String originalCount(Document d) =>
        readerRailItems(d).firstWhere((i) => i.id == 'original').count!;

    test('an image set is NOTE, not IMAGE_SET', () {
      expect(originalCount(_doc('image_set')), 'NOTE');
    });

    test('a deck is NOTE, not PPTX', () {
      expect(originalCount(_doc('pptx', gcsPath: 'raw/u/d.pptx')), 'NOTE');
    });

    test('a podcast is AUDIO and a YouTube link is YT', () {
      expect(originalCount(_doc('podcast')), 'AUDIO');
      expect(originalCount(_doc('youtube')), 'YT');
    });
  });

  group('the Original section names the kind in its eyebrow', () {
    setUp(() {
      ApiService.instance.tokenProvider = () async => 'test-token';
      ApiService.instance.httpClientAdapter = _NoObject();
    });
    tearDown(ApiService.instance.resetTestSeams);

    testWidgets('an image set reads ORIGINAL · NOTE', (tester) async {
      await _pumpPanel(tester, _doc('image_set'));
      expect(find.text('ORIGINAL · NOTE'), findsOneWidget);
      expect(find.textContaining('IMAGE_SET'), findsNothing);
    });

    testWidgets('a deck is a note too, not PPTX', (tester) async {
      await _pumpPanel(tester, _doc('pptx', gcsPath: 'raw/u/d.pptx'));
      expect(find.text('ORIGINAL · NOTE'), findsOneWidget);
      expect(find.textContaining('PPTX'), findsNothing);
    });

    testWidgets('a link with no host falls back to its kind, not its type',
        (tester) async {
      await _pumpPanel(tester, _doc('youtube', sourceUrl: 'not a url'));
      expect(find.text('ORIGINAL · YT'), findsOneWidget);
      expect(find.textContaining('YOUTUBE'), findsNothing);
    });
  });
}
