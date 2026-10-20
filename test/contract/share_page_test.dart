// F-123: Android's share sheet — lib/shared/share_content.dart (what a share
// is, decided before a byte is read) and lib/pages/share_page.dart (its
// states, composed from the kit). The behaviour ported is iOS's share
// extension (ios/Share/ShareViewController.swift + ShareView.swift, F-122),
// case for case; its copy is asserted verbatim because it exists nowhere else
// (SPEC GAP).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/pages/share_page.dart';
import 'package:flutter_app/services/share_intake.dart';
import 'package:flutter_app/shared/share_content.dart';
import 'package:flutter_app/shared/upload_types.dart' show kScrollHint;
import 'package:flutter_app/state/upload_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

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
    Future<void> pump(
      WidgetTester tester,
      SharedContent content, {
      bool signedIn = true,
      ThemeData? theme,
    }) async {
      ShareIntake.instance.show(content);
      await tester.pumpWidget(
        ChangeNotifierProvider<UploadNotifier>(
          create: (_) => UploadNotifier(),
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
  });
}
