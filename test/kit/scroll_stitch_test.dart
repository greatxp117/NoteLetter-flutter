// 5.10.0 (ADR-170) — a stitched scroll, as this client draws it (F-117).
//
// An image set whose pages were one continuous scroll is re-typed `image` with
// a `stitch` record by the run that joined them. What the contract suite cannot
// see is the drawing: §15.1 rule 4 (a tall picture is READ at the stage's
// width in a stage that scrolls, decoded at the width it is drawn — never
// fitted into a sliver, never decoded at 200 MB), the caption that is the one
// place the picture is explained, and the hint sentence on the set entry.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/shared/upload_types.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

// `NetworkImage` reaches for the network in a widget test; every image here is
// a 1x1 PNG (kit_smoke_test.dart's reason).
final Uint8List _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
    'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

class _Overrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? _) => _Client();
}

class _Client implements HttpClient {
  @override
  bool autoUncompress = true;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _Request();
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Request implements HttpClientRequest {
  @override
  final HttpHeaders headers = _Headers();
  @override
  Future<HttpClientResponse> close() async => _Response();
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Response implements HttpClientResponse {
  @override
  int get statusCode => HttpStatus.ok;
  @override
  int get contentLength => _png.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream<List<int>>.value(_png).listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Headers implements HttpHeaders {
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  setUpAll(() => HttpOverrides.global = _Overrides());
  tearDownAll(() => HttpOverrides.global = null);

  Future<void> pump(WidgetTester tester, Widget child,
      {Brightness brightness = Brightness.light}) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(MaterialApp(
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
  }

  group('documents.stitch', () {
    test('read when it is a real record, dropped when it is not', () {
      final s = DocumentStitch.fromJson(
          {'frame_count': 6, 'order': 'given', 'width': 1170, 'height': 11646, 'joins': []});
      expect(s!.frameCount, 6);
      expect(s.tall, isTrue);
      expect(DocumentStitch.fromJson(null), isNull);
      expect(DocumentStitch.fromJson({'frame_count': 0}), isNull,
          reason: '"Joined from 0 screenshots" is worse than no caption');
      final doc = Document.fromJson('d1', {
        'type': 'image', 'mime_type': 'image_set', 'status': 'complete',
        'stitch': {'frame_count': 3, 'width': 390, 'height': 3120},
      });
      expect(doc.stitch!.frameCount, 3);
      expect(Document.fromJson('d2', {'type': 'image'}).stitch, isNull);
    });
  });

  group('§15.1 rule 4 — a tall image is read, not fitted', () {
    testWidgets('a stitched scroll: captioned, in a scrolling stage, decoded downsampled',
        (tester) async {
      for (final b in Brightness.values) {
        await pump(
          tester,
          const KitSourceFileView(
            title: 'A long thread',
            url: 'https://x.test/stitched.png',
            stage: KitStage.image,
            stitchedFrames: 6,
            knownWidth: 1170,
            knownHeight: 11646,
          ),
          brightness: b,
        );
        expect(find.text('Joined from 6 screenshots of one scroll.'), findsOneWidget);
        expect(
            find.descendant(
                of: find.byType(KitSourceFileView),
                matching: find.byType(SingleChildScrollView)),
            findsOneWidget,
            reason: 'the tall stage must scroll');
        final img = tester.widget<Image>(find.descendant(
            of: find.byType(KitSourceFileView), matching: find.byType(Image)));
        // Drawn at the stage's width (never past its own 1170 px), decoded
        // at that width x at most 2 — not at the picture's full size.
        expect(img.fit, BoxFit.fitWidth);
        final provider = img.image;
        expect(provider, isA<ResizeImage>(),
            reason: 'Image.network with cacheWidth wraps it in a ResizeImage');
        final w = (provider as ResizeImage).width!;
        expect(w, lessThanOrEqualTo(1170 * 2));
        expect(w, greaterThan(0));
      }
    });

    testWidgets('an ordinary photo keeps the fit-inside rule and no caption',
        (tester) async {
      await pump(
        tester,
        const KitSourceFileView(
          title: 'photo.jpg',
          url: 'https://x.test/photo.jpg',
          stage: KitStage.image,
        ),
      );
      expect(find.textContaining('Joined from'), findsNothing);
      final img = tester.widget<Image>(find.descendant(
          of: find.byType(KitSourceFileView), matching: find.byType(Image)));
      expect(img.fit, BoxFit.contain);
    });
  });

  test('the hint sentence is the spec\'s, verbatim', () {
    expect(kScrollHint, 'Screenshots of one long scroll are joined into one picture.');
  });
}
