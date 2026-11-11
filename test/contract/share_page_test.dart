// F-123: Android's share sheet — lib/shared/share_content.dart (what a share
// is, decided before a byte is read) and lib/pages/share_page.dart (its
// states, composed from the kit). The behaviour ported is iOS's share
// extension (ios/Share/ShareViewController.swift + ShareView.swift, F-122),
// case for case; its copy is asserted verbatim because it exists nowhere else
// (SPEC GAP).
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/pages/share_page.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/share_intake.dart';
import 'package:flutter_app/shared/share_content.dart';
import 'package:flutter_app/shared/upload_types.dart' show kScrollHint;
import 'package:flutter_app/state/documents_notifier.dart';
import 'package:flutter_app/state/tags_notifier.dart';
import 'package:flutter_app/state/upload_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

import '../kit/shelves_harness.dart';

/// The add's request, recorded when it is sent; [hold] keeps the answer back.
class _ShareWire implements HttpClientAdapter {
  final bodies = <Map>[];
  int status = 201;
  Map<String, dynamic> answer = const {'docId': 'n1'};
  Completer<void>? hold;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final d = options.data;
    bodies.add((d is String ? jsonDecode(d) : d) as Map);
    await hold?.future;
    return ResponseBody.fromString(jsonEncode(answer), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

SharedStream _s(String name, String mime, {int size = 1000, String? error}) =>
    SharedStream(
      uri: 'content://x/$name',
      name: name,
      size: size,
      mimeType: mime,
      error: error,
    );

void main() {
  group('classifyShare — iOS extractContent, transposed', () {
    test('a browser shares the address as text, often after a title', () {
      final c = classifyShare(
        const SharePayload(
          text: 'An essay worth reading https://example.com/essay?id=4.',
        ),
      );
      expect(c, isA<SharedLink>());
      expect((c as SharedLink).url, 'https://example.com/essay?id=4');
      expect(c.type, 'article');
    });

    test(
      'a bare address is a link (ADR-120); the type is detected (INV-07)',
      () {
        final c =
            classifyShare(
                  const SharePayload(text: 'www.youtube.com/watch?v=abc'),
                )
                as SharedLink;
        expect(c.url, 'https://www.youtube.com/watch?v=abc');
        expect(c.type, 'youtube');
        expect(
          (classifyShare(
                    const SharePayload(
                      text: 'https://www.youtube.com/playlist?list=PL1',
                    ),
                  )
                  as SharedLink)
              .type,
          'youtube_playlist',
        );
      },
    );

    test('selected text with no link, and a file:// address, are nothing', () {
      expect(
        classifyShare(const SharePayload(text: 'a sentence I selected')),
        isA<SharedNothing>(),
      );
      expect(
        classifyShare(const SharePayload(text: 'file:///sdcard/a.pdf')),
        isA<SharedNothing>(),
      );
      expect(classifyShare(const SharePayload()), isA<SharedNothing>());
    });

    test('a file with a caption is a FILE, never a link', () {
      final c = classifyShare(
        SharePayload(
          text: 'see https://example.com',
          items: [_s('notes.pdf', 'application/pdf')],
        ),
      );
      expect(c, isA<SharedFile>());
      expect((c as SharedFile).item.name, 'notes.pdf');
    });

    test('one or many photos are one image set', () {
      final c = classifyShare(
        SharePayload(
          items: [
            _s('a.jpg', 'image/jpeg'),
            _s('b.png', 'image/png'),
            _s('c.heic', ''),
          ],
        ),
      );
      expect(c, isA<SharedImages>());
      expect((c as SharedImages).items, hasLength(3));
      expect(c.countRefusal, isNull);
      expect(c.unreadable, isNull);
    });

    test('more than 20 photos are refused on the card, in iOS words', () {
      final c =
          classifyShare(
                SharePayload(
                  items: [
                    for (var i = 0; i < 21; i++) _s('p$i.jpg', 'image/jpeg'),
                  ],
                ),
              )
              as SharedImages;
      expect(c.countRefusal, 'Select between 1 and 20 images.');
    });

    test('a photo that could not be read is said, not dropped', () {
      final c =
          classifyShare(
                SharePayload(
                  items: [
                    _s('a.jpg', 'image/jpeg'),
                    _s('b.jpg', 'image/jpeg', error: 'Permission denied'),
                  ],
                ),
              )
              as SharedImages;
      expect(c.items, hasLength(1));
      expect(c.unreadable, 'It couldn’t be read — Permission denied');
    });

    test('a file outside the closed set is refused in the server words', () {
      final c = classifyShare(
        SharePayload(items: [_s('main.py', 'text/x-python')]),
      );
      expect(c, isA<SharedRefused>());
      expect((c as SharedRefused).filename, 'main.py');
      expect(c.reason, 'Source code files aren’t supported (.py).');
    });

    test('a file over its type cap is refused before it is copied', () {
      final c = classifyShare(
        SharePayload(
          items: [_s('book.pdf', 'application/pdf', size: 101 * 1024 * 1024)],
        ),
      );
      expect(
        (c as SharedRefused).reason,
        'That file is over the 100 MB limit.',
      );
      // Video's cap is its own (ADR-049).
      expect(
        classifyShare(
          SharePayload(
            items: [_s('talk.mp4', 'video/mp4', size: 500 * 1024 * 1024)],
          ),
        ),
        isA<SharedFile>(),
      );
    });

    test('every class of the closed set is accepted as one file', () {
      for (final (name, mime) in [
        ('a.pdf', 'application/pdf'),
        (
          'a.docx',
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        ),
        (
          'a.pptx',
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        ),
        ('a.epub', 'application/epub+zip'),
        ('a.md', 'text/markdown'),
        ('a.txt', 'text/plain'),
        ('a.m4a', 'audio/mp4'),
        ('a.mov', 'video/quicktime'),
      ]) {
        expect(
          classifyShare(SharePayload(items: [_s(name, mime)])),
          isA<SharedFile>(),
          reason: name,
        );
      }
    });

    test(
      'a share nothing could be read from is unreadable, not unsupported',
      () {
        final c = classifyShare(
          SharePayload(
            items: [_s('', '', error: 'No content provider: content://gone')],
          ),
        );
        expect(c, isA<SharedUnreadable>());
        expect(
          (c as SharedUnreadable).reason,
          'It couldn’t be read — No content provider: content://gone',
        );
      },
    );

    test('the payload MainActivity sends decodes', () {
      final p = SharePayload.fromMap({
        'text': null,
        'items': [
          {
            'uri': 'content://m/1',
            'name': 'a.pdf',
            'size': 12,
            'mime': 'application/pdf',
          },
          {'uri': 'content://m/2', 'error': 'boom'},
        ],
      });
      expect(p.items.first.size, 12);
      expect(p.items.last.error, 'boom');
      expect(p.items.last.name, '');
    });

    test('the address is truncated in the middle', () {
      expect(middleEllipsis('https://example.com/a'), 'https://example.com/a');
      final long = 'https://example.com/${'x' * 200}/the-end';
      final shown = middleEllipsis(long);
      expect(shown.length, 90);
      expect(shown, startsWith('https://example.com/'));
      expect(shown, endsWith('/the-end'));
      expect(shown, contains('…'));
    });

    test('the kind a link files as — iOS URLContentType.label', () {
      expect(linkKindLabel('article'), 'Article');
      expect(linkKindLabel('youtube'), 'YouTube video');
      expect(linkKindLabel('youtube_playlist'), 'YouTube playlist');
      expect(linkKindLabel('instagram'), 'Instagram post');
      expect(linkKindLabel('tiktok'), 'TikTok video');
      expect(linkKindLabel('podcast'), 'Podcast episode');
      expect(linkKindLabel('something_new'), 'Article');
    });
  });

  group('SharePage — the states, from the kit', () {
    late LiveTags tags;
    setUp(() => tags = LiveTags([shelf('a', 'Attention'), shelf('b', 'Birds')]));

    Future<void> pump(
      WidgetTester tester,
      SharedContent content, {
      bool signedIn = true,
      ThemeData? theme,
    }) async {
      ShareIntake.instance.show(content);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<UploadNotifier>(
              create: (_) => UploadNotifier(),
            ),
            ChangeNotifierProvider<TagsNotifier>.value(value: tags),
            ChangeNotifierProvider<DocumentsNotifier>(
              create: (_) => QuietDocs(),
            ),
          ],
          child: MaterialApp(
            theme: theme ?? AppTheme.light,
            home: SharePage(signedIn: signedIn),
          ),
        ),
      );
      await tester.pump();
    }

    KitButton button(WidgetTester tester, String label) =>
        tester.widget<KitButton>(
          find.byWidgetPredicate((w) => w is KitButton && w.label == label),
        );

    testWidgets('every state: a sub-screen header, then one surface card', (
      tester,
    ) async {
      for (final c in <SharedContent>[
        const SharedLink('https://example.com', 'article'),
        SharedImages([_s('a.jpg', 'image/jpeg')]),
        SharedFile(_s('a.pdf', 'application/pdf')),
        const SharedUnreadable('It couldn’t be read — x'),
        const SharedRefused(
          'a.py',
          'Source code files aren’t supported (.py).',
        ),
        const SharedNothing(),
      ]) {
        await pump(tester, c);
        expect(find.byType(SubScreenHeader), findsOneWidget, reason: '$c');
        expect(find.text('ADD TO NOTELETTER'), findsOneWidget, reason: '$c');
        expect(find.text('Cancel'), findsOneWidget, reason: '$c');
        expect(find.byType(KitCard), findsOneWidget, reason: '$c');
      }
    });

    testWidgets('signed out: Sign in required, whatever was shared', (
      tester,
    ) async {
      await pump(
        tester,
        const SharedLink('https://example.com', 'article'),
        signedIn: false,
      );
      expect(find.text('Sign in required'), findsOneWidget);
      expect(
        find.text('Sign in to NoteLetter to share content to your library.'),
        findsOneWidget,
      );
      expect(find.byType(KitButton), findsNothing);
    });

    testWidgets('a link: its address, what it files as, Add to NoteLetter', (
      tester,
    ) async {
      await pump(
        tester,
        const SharedLink('https://www.youtube.com/watch?v=abc', 'youtube'),
      );
      expect(find.text('LINK'), findsOneWidget);
      expect(find.text('https://www.youtube.com/watch?v=abc'), findsOneWidget);
      expect(find.text('Files as: YouTube video'), findsOneWidget);
      expect(button(tester, 'Add to NoteLetter').onPressed, isNotNull);
    });

    testWidgets(
      'photos: the count, the scroll sentence, a title, Upload Photos',
      (tester) async {
        await pump(
          tester,
          SharedImages([_s('a.jpg', 'image/jpeg'), _s('b.jpg', 'image/jpeg')]),
        );
        expect(find.text('PHOTOS'), findsOneWidget);
        expect(find.text('2 photos selected'), findsOneWidget);
        expect(find.text(kScrollHint), findsOneWidget);
        expect(find.byType(KitTextField), findsOneWidget);
        expect(find.text('Title (optional)'), findsOneWidget);
        expect(button(tester, 'Upload Photos').onPressed, isNotNull);

        await pump(tester, SharedImages([_s('a.jpg', 'image/jpeg')]));
        expect(find.text('1 photo selected'), findsOneWidget);
      },
    );

    testWidgets('21 photos: the refusal on the card and no upload', (
      tester,
    ) async {
      await pump(
        tester,
        SharedImages([
          for (var i = 0; i < 21; i++) _s('p$i.jpg', 'image/jpeg'),
        ]),
      );
      expect(
        find.widgetWithText(
          KitFailureInline,
          'Select between 1 and 20 images.',
        ),
        findsOneWidget,
      );
      expect(button(tester, 'Upload Photos').onPressed, isNull);
    });

    testWidgets('an unreadable photo beside readable ones is said', (
      tester,
    ) async {
      await pump(
        tester,
        SharedImages([
          _s('a.jpg', 'image/jpeg'),
        ], unreadable: 'It couldn’t be read — Permission denied'),
      );
      expect(
        find.widgetWithText(
          KitFailureInline,
          'It couldn’t be read — Permission denied',
        ),
        findsOneWidget,
      );
      expect(button(tester, 'Upload Photos').onPressed, isNotNull);
    });

    testWidgets('a file: its name and Upload File', (tester) async {
      await pump(tester, SharedFile(_s('Lecture 4.m4a', 'audio/mp4')));
      expect(find.text('FILE'), findsOneWidget);
      expect(find.text('Lecture 4.m4a'), findsOneWidget);
      expect(button(tester, 'Upload File').onPressed, isNotNull);
    });

    testWidgets('refused: the name and the server sentence, no button', (
      tester,
    ) async {
      await pump(
        tester,
        const SharedRefused(
          'a.ppt',
          'Legacy .ppt files aren’t supported — re-save as .pptx and upload again.',
        ),
      );
      expect(find.text('Can’t add this file'), findsOneWidget);
      expect(find.text('a.ppt'), findsOneWidget);
      expect(
        find.widgetWithText(
          KitFailureInline,
          'Legacy .ppt files aren’t supported — re-save as .pptx and upload again.',
        ),
        findsOneWidget,
      );
      expect(find.byType(KitButton), findsNothing);
    });

    testWidgets('unreadable is not unsupported', (tester) async {
      await pump(tester, const SharedUnreadable('It couldn’t be read — gone'));
      expect(find.text('Couldn’t read what you shared'), findsOneWidget);
      expect(
        find.widgetWithText(KitFailureInline, 'It couldn’t be read — gone'),
        findsOneWidget,
      );
      expect(find.text('Nothing to share'), findsNothing);
    });

    testWidgets('nothing: Nothing to share, and why', (tester) async {
      await pump(tester, const SharedNothing());
      expect(find.text('Nothing to share'), findsOneWidget);
      expect(
        find.text("This kind of content isn't supported yet."),
        findsOneWidget,
      );
      expect(find.byType(KitButton), findsNothing);
    });

    testWidgets('dark: the same card, no exceptions', (tester) async {
      await pump(
        tester,
        const SharedLink('https://example.com', 'article'),
        theme: AppTheme.dark,
      );
      expect(find.byType(KitCard), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    group('kit §20.3: Shelves (5.73.0, ADR-238)', () {
      late _ShareWire wire;
      setUp(() {
        ApiService.instance.tokenProvider = () async => 'test-token';
        wire = _ShareWire();
        ApiService.instance.httpClientAdapter = wire;
      });
      tearDown(ApiService.instance.resetTestSeams);

      Future<void> choose(WidgetTester tester, String title) async {
        await tester.tap(find.bySemanticsLabel('Add a shelf'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(find.text(title));
        await tester.pump();
      }

      const sentence = 'Optional. NoteLetter still adds its own as it reads.';

      testWidgets('every accepted card, between its lines and its button', (
        tester,
      ) async {
        for (final (content, line, label) in <(SharedContent, String, String)>[
          (
            const SharedLink('https://example.com', 'article'),
            'Files as: Article',
            'Add to NoteLetter',
          ),
          (
            SharedImages([_s('a.jpg', 'image/jpeg')]),
            '1 photo selected',
            'Upload Photos',
          ),
          (SharedFile(_s('a.pdf', 'application/pdf')), 'a.pdf', 'Upload File'),
        ]) {
          await pump(tester, content);
          final y = tester.getTopLeft(find.text('SHELVES')).dy;
          expect(tester.getTopLeft(find.text(line)).dy, lessThan(y));
          expect(
            y,
            lessThan(tester.getTopLeft(find.byType(KitButton)).dy),
            reason: label,
          );
          expect(find.text(sentence), findsOneWidget);
        }
      });

      testWidgets('the states with nothing to add draw no row', (tester) async {
        for (final c in <SharedContent>[
          const SharedUnreadable('It couldn’t be read — gone'),
          const SharedRefused('a.ppt', 'No.'),
          const SharedNothing(),
        ]) {
          await pump(tester, c);
          expect(find.text('SHELVES'), findsNothing, reason: '$c');
        }
      });

      testWidgets('signed out: no row, and no read of anyone\'s shelves', (
        tester,
      ) async {
        await pump(
          tester,
          const SharedLink('https://example.com', 'article'),
          signedIn: false,
        );
        await tester.pump();
        expect(find.text('SHELVES'), findsNothing);
        expect(tags.starts, 0);
      });

      testWidgets('signed in: the row starts the tags read', (tester) async {
        await pump(tester, const SharedLink('https://example.com', 'article'));
        await tester.pump();
        expect(tags.starts, 1);
      });

      testWidgets('a share starts with none, and sends no key', (tester) async {
        await pump(tester, const SharedLink('https://example.com', 'article'));
        await tester.tap(find.text('Add to NoteLetter'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(wire.bodies.single.containsKey('tagIds'), isFalse);
        await tester.pump(const Duration(seconds: 1));
      });

      testWidgets('the add carries what is chosen; the row holds in flight', (
        tester,
      ) async {
        wire.hold = Completer<void>();
        await pump(tester, const SharedLink('https://example.com', 'article'));
        await choose(tester, 'Attention');
        await tester.tap(find.text('Add to NoteLetter'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        expect(wire.bodies.single['tagIds'], ['a']);

        // In flight: held, and the one ring is the pressed Add's (F-198) —
        // never the + Shelf that was last pressed.
        expect(find.byType(KitBusyMark), findsOneWidget);
        expect(
          find.descendant(
            of: find.byWidgetPredicate(
              (w) => w is KitButton && w.label == 'Add to NoteLetter',
            ),
            matching: find.byType(KitBusyMark),
          ),
          findsOneWidget,
        );
        await tester.tap(
          find.bySemanticsLabel('Take Attention off'),
          warnIfMissed: false,
        );
        await tester.pump();
        expect(find.text('Attention'), findsOneWidget, reason: 'it is held');

        wire.hold!.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('Added link for processing.'), findsOneWidget);
        await tester.pump(const Duration(seconds: 1));
      });

      // F-198 · §6.1 State — Busy (5.72.0, ADR-237): the pressed control
      // draws the ring while its own request is in flight, and only it.
      testWidgets('the pressed button carries the ring while its add runs; '
          'the card is held, and the ring goes when it answers', (tester) async {
        const channel = MethodChannel('xp.noteletter/share');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        for (final (content, label) in <(SharedContent, String)>[
          (const SharedLink('https://example.com', 'article'),
              'Add to NoteLetter'),
          (SharedImages([_s('a.jpg', 'image/jpeg')]), 'Upload Photos'),
          (SharedFile(_s('a.pdf', 'application/pdf')), 'Upload File'),
        ]) {
          // The link's request, and the photos' and the file's copy out of
          // the sharing app, each held open by the test.
          wire.hold = Completer<void>();
          final copying = Completer<Object?>();
          messenger.setMockMethodCallHandler(channel, (_) => copying.future);
          await pump(tester, content);
          expect(find.byType(KitBusyMark), findsNothing, reason: '$label idle');

          await tester.tap(find.text(label));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 20));
          final pressed = button(tester, label);
          expect(pressed.busy, isTrue, reason: label);
          expect(pressed.onPressed, isNull, reason: '$label is held');
          expect(find.byType(KitBusyMark), findsOneWidget, reason: label);
          expect(
            find.descendant(
              of: find.byWidgetPredicate(
                (w) => w is KitButton && w.label == label,
              ),
              matching: find.byType(KitBusyMark),
            ),
            findsOneWidget,
            reason: 'the ring is $label\'s own',
          );

          copying.complete(null); // nothing came back: a refusal
          wire.hold!.complete();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          expect(find.byType(KitBusyMark), findsNothing,
              reason: '$label answered');
          await tester.pump(const Duration(seconds: 1));
        }
      });

      testWidgets(
        'a refused shelf is the card\'s line, and the card stays, chip and all',
        (tester) async {
          const said =
              'One of the shelves you chose no longer exists. Take it off and '
              'try again.';
          wire.status = 404;
          wire.answer = const {'error': said};
          await pump(tester, const SharedLink('https://example.com', 'article'));
          await choose(tester, 'Attention');
          await tester.tap(find.text('Add to NoteLetter'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          expect(find.widgetWithText(KitFailureInline, said), findsOneWidget);
          expect(find.text('Files as: Article'), findsOneWidget);
          await tester.tap(find.bySemanticsLabel('Take Attention off'));
          await tester.pump();
          expect(find.text('Attention'), findsNothing, reason: 'live again');
        },
      );

      testWidgets('a share arriving while an add is in flight starts with none', (
        tester,
      ) async {
        wire.hold = Completer<void>();
        await pump(tester, const SharedLink('https://example.com', 'article'));
        await choose(tester, 'Attention');
        await tester.tap(find.text('Add to NoteLetter'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        ShareIntake.instance.show(
          const SharedLink('https://example.org', 'article'),
        );
        await tester.pump();
        expect(find.text('Attention'), findsNothing);
        expect(wire.bodies.single['tagIds'], ['a'], reason: 'its own copy');
        wire.hold!.complete();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      });

      testWidgets('a new share starts over with none chosen', (tester) async {
        await pump(tester, const SharedLink('https://example.com', 'article'));
        await choose(tester, 'Attention');
        ShareIntake.instance.show(
          const SharedLink('https://example.org', 'article'),
        );
        await tester.pump();
        await tester.pump();
        expect(find.text('Attention'), findsNothing);
      });
    });
  });
}
