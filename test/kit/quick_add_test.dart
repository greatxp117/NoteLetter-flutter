import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/shared/cloud_return.dart';
import 'package:flutter_app/shared/upload_types.dart';
import 'package:flutter_app/state/cloud_notifier.dart';
import 'package:flutter_app/state/documents_notifier.dart';
import 'package:flutter_app/state/tags_notifier.dart';
import 'package:flutter_app/state/upload_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';
import 'package:flutter_app/widgets/quick_add.dart';

import 'shelves_harness.dart';

/// Quick add (F-152; web `overlays/QuickAdd.jsx`, `image-set-choice.test.js`):
/// the sheet's anatomy and words, the phone sheet and the wide dialog, the
/// one-source question (which files it is about, the order a set's pages go
/// in, the count, the cap), the rows a pick and a link make — the server's
/// words reaching a row, a refusal at the door with no request — and Connect
/// through the one entry point: a refusal said under the chips, a cancelled
/// session leaving the chip pressable, a held return moving the sheet.

/// Every request, recorded; answered with [body] at [status].
class _Wire implements HttpClientAdapter {
  _Wire({this.status = 201, this.body = const {'docId': 'n1'}});
  final int status;
  final Map<String, dynamic> body;
  final sent = <({String path, Object? data})>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final d = options.data;
    sent.add((path: options.path, data: d is String ? jsonDecode(d) : d));
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

class _Picker extends FilePicker {
  _Picker(this.files);
  List<PlatformFile> files;
  final types = <FileType>[];

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    types.add(type);
    return FilePickerResult(files);
  }
}

/// Connect answers [answer]; [hold] parks a return first, as a session that
/// came back does.
class _Cloud extends CloudNotifier {
  _Cloud({this.answer, this.hold = false});
  final String? answer;
  final bool hold;
  final asked = <String>[];

  @override
  Future<void> loadIntegrations() async {}

  @override
  Future<String?> connect(String provider, {bool again = false}) async {
    asked.add(provider);
    if (hold) {
      CloudReturn.hold(
          CloudReturn('claim', claim: 'c-1', provider: provider));
    }
    return answer;
  }
}

PlatformFile _png(String name) =>
    PlatformFile(name: name, size: 4, bytes: Uint8List.fromList([1, 2, 3, 4]));

void main() {
  late UploadNotifier upload;
  late _Wire wire;
  late LiveTags tags;

  setUp(() {
    tags = LiveTags([shelf('a', 'Attention'), shelf('b', 'Birds')]);
    ApiService.instance.tokenProvider = () async => 'test-token';
    wire = _Wire();
    ApiService.instance.httpClientAdapter = wire;
    upload = UploadNotifier();
    // No platform picker exists under test; each case sets what it picks.
    FilePicker.platform = _Picker(const []);
    CloudReturn.take();
  });
  tearDown(() {
    ApiService.instance.resetTestSeams();
    CloudReturn.take();
  });

  Widget providers(Widget child, {CloudNotifier? cloud, bool dark = false}) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UploadNotifier>.value(value: upload),
          ChangeNotifierProvider<CloudNotifier>.value(value: cloud ?? _Cloud()),
          ChangeNotifierProvider<TagsNotifier>.value(value: tags),
          ChangeNotifierProvider<DocumentsNotifier>(create: (_) => QuietDocs()),
        ],
        child: MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: child,
        ),
      );

  /// The body alone, at a phone's width, with its two moves recorded.
  Future<({List<String> moves})> pumpBody(WidgetTester tester,
      {CloudNotifier? cloud, List<PlatformFile> seed = const []}) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final moves = <String>[];
    await tester.pumpWidget(providers(
      Scaffold(
        body: SingleChildScrollView(
          child: QuickAdd(
            seed: seed,
            onMore: () => moves.add('more'),
            onReturn: () => moves.add('return'),
          ),
        ),
      ),
      cloud: cloud,
    ));
    await tester.pump();
    return (moves: moves);
  }

  group('which files the one-source question is about', () {
    test('images the allowlist would send, and nothing else', () {
      bool img(String name, [String mime = '']) =>
          isSetImage(name: name, size: 10, mimeType: mime);
      expect(img('a.png', 'image/png'), isTrue);
      expect(img('b.heic'), isTrue);
      expect(img('c.jpg', 'image/jpeg'), isTrue);
      expect(img('notes.pdf', 'application/pdf'), isFalse);
      expect(img('main.py', 'text/plain'), isFalse);
    });

    test('an untyped .heic declares image/heic', () {
      expect(imageMimeOf('IMG_1.HEIC'), 'image/heic');
      expect(imageMimeOf('x.png', 'image/png'), 'image/png');
      expect(imageMimeOf('x.pdf', 'application/pdf'), isNull);
    });

    test("a set's pages: oldest first, then natural filename order", () {
      final out = orderFrames(
        [('IMG_10.PNG', 3), ('IMG_9.PNG', 3), ('IMG_2.PNG', 1)],
        name: (f) => f.$1,
        lastModified: (f) => f.$2,
      );
      expect(out.map((f) => f.$1), ['IMG_2.PNG', 'IMG_9.PNG', 'IMG_10.PNG']);
      expect(naturalCompare('img_9', 'IMG_10'), lessThan(0));
    });
  });

  group('the question', () {
    Future<void> pumpChoice(WidgetTester tester, int count,
        {VoidCallback? one, VoidCallback? separate}) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: KitImageSetChoice(
            count: count,
            onOne: one ?? () {},
            onSeparate: separate ?? () {},
          ),
        ),
      ));
    }

    testWidgets('names the count, carries the hint verbatim, both answers work',
        (tester) async {
      var one = 0, separate = 0;
      await pumpChoice(tester, 4,
          one: () => one++, separate: () => separate++);
      expect(find.text('Add these 4 images as one source?'), findsOneWidget);
      expect(kScrollHint,
          'Screenshots of one long scroll are joined into one picture.');
      expect(find.text(kScrollHint), findsOneWidget);
      await tester.tap(find.text('One source'));
      await tester.tap(find.text('Separate sources'));
      expect((one, separate), (1, 1));
    });

    testWidgets('over $kImageSetMax images, One source is held and says why',
        (tester) async {
      var one = 0;
      await pumpChoice(tester, kImageSetMax + 1, one: () => one++);
      expect(find.text('One source holds up to $kImageSetMax images.'),
          findsOneWidget);
      await tester.tap(find.text('One source'), warnIfMissed: false);
      expect(one, 0);
    });
  });

  testWidgets('the anatomy, in web order, with touch copy', (tester) async {
    await pumpBody(tester);
    final words = [
      'Drop files, or tap to add one',
      uploadAcceptHelp,
      KitQaLinkRow.placeholder,
      'Add an image set (up to 20)',
      'OR CONNECT A SERVICE',
      'Google Drive',
      'OneDrive',
      'Notion',
      'Dropbox',
    ];
    var lastY = -1.0;
    for (final w in words) {
      final f = w == KitQaLinkRow.placeholder
          ? find.text(w, findRichText: true)
          : find.text(w);
      expect(f, findsWidgets, reason: 'quick add lacks "$w"');
      final y = tester.getTopLeft(f.first).dy;
      expect(y, greaterThanOrEqualTo(lastY), reason: '"$w" is out of order');
      lastY = y;
    }
    // Nothing is going yet, and Add is held on an empty field.
    expect(find.text('GOING TO YOUR LIBRARY'), findsNothing);
    expect(
        tester
            .widget<KitDTap>(find.ancestor(
                of: find.text('Add'), matching: find.byType(KitDTap)))
            .enabled,
        isFalse);
  });

  group('the sheet', () {
    Future<void> openFrom(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(providers(Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: KitButton('Add a source',
                onPressed: () => QuickAdd.show(context)),
          ),
        ),
      )));
      await tester.tap(find.text('Add a source'));
      await tester.pumpAndSettle();
    }

    testWidgets('on a phone it rises from the foot, with its foot',
        (tester) async {
      await openFrom(tester, const Size(390, 844));
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text(QuickAdd.title), findsOneWidget);
      expect(find.text(QuickAdd.subtitle), findsOneWidget);
      expect(find.text('What can I add?'), findsOneWidget);
      expect(find.text('More options →'), findsOneWidget);
      // The foot is outside the scrolling body, at the sheet's foot.
      expect(
          find.ancestor(
              of: find.text('More options →'),
              matching: find.byType(SingleChildScrollView)),
          findsNothing);
      expect(tester.getBottomLeft(find.byType(KitQaFoot)).dy,
          closeTo(tester.getBottomLeft(find.byType(BottomSheet)).dy, 1));
      // ×, and it is gone.
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(QuickAdd), findsNothing);
    });

    testWidgets(
        'on a phone it covers the whole screen: the ROOT navigator, never the '
        "shell's, whose sheet sat between the header and a live tab bar",
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const shell = ValueKey('shell-navigator');
      await tester.pumpWidget(providers(Navigator(
        key: shell,
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (context) => Scaffold(
            body: Center(
              child: KitButton('Add a source',
                  onPressed: () => QuickAdd.show(context)),
            ),
          ),
        ),
      )));
      await tester.tap(find.text('Add a source'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(
          find.ancestor(
              of: find.byType(BottomSheet), matching: find.byKey(shell)),
          findsNothing);
      // The link row is web's 42 (+ its 1px border), not the theme's field.
      expect(tester.getSize(find.byType(KitQaLinkRow)).height, closeTo(44, 0.5));
    });

    testWidgets("wider it is web's dialog, 540 wide", (tester) async {
      await openFrom(tester, const Size(1280, 900));
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.getSize(find.byType(QuickAdd)).width,
          lessThanOrEqualTo(540));
    });

    testWidgets('What can I add? opens the reference sheet over it',
        (tester) async {
      await openFrom(tester, const Size(390, 844));
      await tester.tap(find.text('What can I add?'));
      await tester.pumpAndSettle();
      expect(
          find.text('Every kind of source NoteLetter reads, and the clever bits.'),
          findsOneWidget);
      expect(find.byType(QuickAdd), findsOneWidget,
          reason: 'quick add stays under it');
    });
  });

  testWidgets('More options → is the body’s move to Add a source',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(providers(Scaffold(
      body: Builder(
        builder: (context) => KitButton('Add a source',
            onPressed: () => QuickAdd.show(context)),
      ),
    )));
    await tester.tap(find.text('Add a source'));
    await tester.pumpAndSettle();
    // No router here: the sheet closes and the move goes nowhere.
    await tester.tap(find.text('More options →'));
    await tester.pumpAndSettle();
    expect(find.byType(QuickAdd), findsNothing);
  });

  testWidgets(
      '2+ images in one pick wait for the question; the rest go now — a '
      'refusal at the door is a row with its reason and no request',
      (tester) async {
    FilePicker.platform = _Picker([
      _png('IMG_10.PNG'),
      _png('IMG_9.PNG'),
      _png('IMG_2.PNG'),
      PlatformFile(name: 'main.py', size: 4, bytes: Uint8List(4)),
    ]);
    await pumpBody(tester);
    await tester.tap(find.text('Drop files, or tap to add one'));
    await tester.pump();
    expect(find.text('Add these 3 images as one source?'), findsOneWidget);
    expect(find.text('GOING TO YOUR LIBRARY'), findsOneWidget);
    expect(find.text('main.py'), findsOneWidget);
    expect(find.text('Source code files aren’t supported (.py).'),
        findsOneWidget);
    expect(find.text('ERROR'), findsOneWidget);
    expect(find.text('0 of 1 filed'), findsOneWidget);
    expect(wire.sent, isEmpty, reason: 'nothing is sent before the answer');

    // One source: one set, its pages in a scroll's order, one row.
    await tester.tap(find.text('One source'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Add these 3 images as one source?'), findsNothing);
    expect(find.text('3 images — one source'), findsOneWidget);
    final set = wire.sent.firstWhere(
        (r) => r.path.endsWith('fn_create_multi_image_session'));
    final files = ((set.data as Map)['files'] as List)
        .map((f) => (f as Map)['filename'])
        .toList();
    expect(files, ['IMG_2.PNG', 'IMG_9.PNG', 'IMG_10.PNG']);
    expect(((set.data as Map)['files'] as List).first['mimeType'], 'image/png');
  });

  testWidgets('Separate sources sends each image as its own source',
      (tester) async {
    wire = _Wire(status: 400, body: {'error': 'Not today.'});
    ApiService.instance.httpClientAdapter = wire;
    FilePicker.platform =
        _Picker([_png('a.png'), _png('b.png')]);
    await pumpBody(tester);
    await tester.tap(find.text('Drop files, or tap to add one'));
    await tester.pump();
    await tester.tap(find.text('Separate sources'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final sessions =
        wire.sent.where((r) => r.path.endsWith('fn_create_upload_session'));
    expect(sessions.length, 2);
    // Quick add says where each came from (5.51.0, `upload_origin`): the
    // app's own picker is `phone`.
    expect(sessions.map((r) => (r.data as Map)['origin']), ['phone', 'phone']);
    // The server's words reach each row.
    expect(find.text('Not today.'), findsNWidgets(2));
    expect(find.text('0 of 2 filed'), findsOneWidget);
  });

  testWidgets('seeded files are filed as if picked here', (tester) async {
    await pumpBody(tester, seed: [_png('one.png'), _png('two.png')]);
    await tester.pump();
    expect(find.text('Add these 2 images as one source?'), findsOneWidget);
  });

  testWidgets('a link: a row that files, and the field clears', (tester) async {
    await pumpBody(tester);
    await tester.enterText(find.byType(TextField), 'https://example.com/essay');
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(wire.sent.single.path, endsWith('fn_ingest_url'));
    expect(find.text('example.com/essay'), findsOneWidget);
    expect(find.text('added — indexing will begin shortly'), findsOneWidget);
    expect(find.text('FILED'), findsOneWidget);
    expect(find.text('1 of 1 filed'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
  });

  testWidgets('a link refused at the door says why, and sends nothing',
      (tester) async {
    await pumpBody(tester);
    await tester.enterText(find.byType(TextField), 'not a link');
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pump();
    expect(wire.sent, isEmpty);
    expect(find.textContaining('That doesn’t look like a link NoteLetter can read'),
        findsOneWidget);
    expect(find.text('ERROR'), findsOneWidget);
  });

  group('Connect, through the one entry point', () {
    testWidgets("a refusal is said under the chips, by the service's name",
        (tester) async {
      final cloud = _Cloud(answer: signInLinkMissing());
      final r = await pumpBody(tester, cloud: cloud);
      await tester.tap(find.text('Google Drive'));
      await tester.pump();
      expect(cloud.asked, ['google_drive']);
      expect(
          find.text('Google Drive — The sign-in link did not come back. '
              'Try connecting again.'),
          findsOneWidget);
      expect(find.byType(KitFailureInline), findsOneWidget);
      expect(find.text('Google Drive'), findsOneWidget,
          reason: 'the chip is pressable again');
      expect(r.moves, isEmpty);
    });

    testWidgets('a cancelled session leaves the chip pressable, and moves nothing',
        (tester) async {
      final cloud = _Cloud();
      final r = await pumpBody(tester, cloud: cloud);
      await tester.tap(find.text('Dropbox'));
      await tester.pump();
      expect(cloud.asked, ['dropbox']);
      expect(find.text('Dropbox'), findsOneWidget);
      expect(find.byType(KitFailureInline), findsNothing);
      expect(r.moves, isEmpty);
    });

    testWidgets('a session that came back moves the sheet to the Library',
        (tester) async {
      final r = await pumpBody(tester, cloud: _Cloud(hold: true));
      await tester.tap(find.text('Notion'));
      await tester.pump();
      expect(r.moves, ['return']);
      expect(CloudReturn.pending.value?.provider, 'notion',
          reason: 'the return is held for the Library to spend');
    });
  });

  testWidgets('dark: the sheet builds on the dark tokens', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(providers(
      Scaffold(
        body: SingleChildScrollView(
          child: QuickAdd(onMore: () {}, onReturn: () {}),
        ),
      ),
      dark: true,
    ));
    expect(find.text('Drop files, or tap to add one'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('kit §20.3: shelves at add (5.73.0, ADR-238)', () {
    /// What each request to [path] said about shelves, in order.
    List<Object?> shelvesSent(String path) => [
          for (final r in wire.sent)
            if (r.path.endsWith(path)) (r.data as Map)['tagIds'],
        ];

    Future<void> choose(WidgetTester tester, String title) async {
      await tester.tap(find.bySemanticsLabel('Add a shelf'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text(title));
      await tester.pump();
    }

    Future<void> addLink(WidgetTester tester, String url) async {
      await tester.enterText(find.byType(TextField), url);
      await tester.pump();
      await tester.tap(find.text('Add'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('the row stands after the link row, before what is going',
        (tester) async {
      await pumpBody(tester);
      await addLink(tester, 'https://example.com/a');
      final link = tester.getTopLeft(find.byType(KitQaLinkRow)).dy;
      final row = tester.getTopLeft(find.text('SHELVES')).dy;
      final going = tester.getTopLeft(find.text('GOING TO YOUR LIBRARY')).dy;
      expect(link, lessThan(row));
      expect(row, lessThan(going));
      expect(tags.starts, 1, reason: 'quick add can open over any page');
    });

    testWidgets('none chosen: no key at all, on every kind of add',
        (tester) async {
      FilePicker.platform = _Picker([_png('a.png'), _png('b.png')]);
      await pumpBody(tester);
      await addLink(tester, 'https://example.com/a');
      await tester.tap(find.text('Drop files, or tap to add one'));
      await tester.pump();
      await tester.tap(find.text('Separate sources'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Drop files, or tap to add one'));
      await tester.pump();
      await tester.tap(find.text('One source'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final bodies = [
        for (final r in wire.sent)
          if (r.data is Map &&
              RegExp(r'fn_(ingest_url|create_upload_session|create_multi_image_session)$')
                  .hasMatch(r.path))
            r.data as Map,
      ];
      expect(bodies.length, 4, reason: 'a link, two files, a set');
      for (final b in bodies) {
        expect(b.containsKey('tagIds'), isFalse, reason: '$b');
      }
    });

    testWidgets('each add takes the row as it stood when pressed',
        (tester) async {
      await pumpBody(tester);
      await choose(tester, 'Attention');
      await addLink(tester, 'https://example.com/one');
      await choose(tester, 'Birds');
      await addLink(tester, 'https://example.com/two');
      await tester.tap(find.bySemanticsLabel('Take Attention off'));
      await tester.pump();
      await addLink(tester, 'https://example.com/three');
      expect(shelvesSent('fn_ingest_url'), [
        ['a'],
        ['a', 'b'],
        ['b'],
      ]);
      expect(find.text('Attention'), findsNothing);
      expect(find.text('Birds'), findsOneWidget, reason: 'the row stays live');
    });

    test('the notifier copies at the door: a later change cannot reach an add',
        () async {
      final live = ['a'];
      final going = upload.addUrl('https://example.com/one', tagIds: live);
      live
        ..add('b')
        ..remove('a');
      await going;
      expect(shelvesSent('fn_ingest_url'), [
        ['a'],
      ], reason: 'the request is built after the token is awaited');
    });

    testWidgets('a set takes the row when pressed, not when its frames are read',
        (tester) async {
      final dir = Directory.systemTemp.createTempSync('qa-set');
      addTearDown(() => dir.deleteSync(recursive: true));
      PlatformFile onDisk(String name) {
        final f = File('${dir.path}/$name')..writeAsBytesSync([1, 2, 3, 4]);
        return PlatformFile(name: name, size: 4, path: f.path);
      }

      FilePicker.platform = _Picker([onDisk('a.png'), onDisk('b.png')]);
      await pumpBody(tester);
      await choose(tester, 'Attention');
      await tester.tap(find.text('Drop files, or tap to add one'));
      await tester.pump();
      // In real time: the press starts a real read of a real file, which a test's
      // fake clock would never let finish.
      await tester.runAsync(() async {
        await tester.tap(find.text('One source'));
        await tester.pump();
        // The frames are being read from disk, and the row is live meanwhile.
        expect(wire.sent.where((r) => r.path.endsWith('session')), isEmpty);
        await tester.tap(find.bySemanticsLabel('Take Attention off'));
        await tester.pump();
        expect(find.text('Attention'), findsNothing);
        for (var i = 0;
            i < 200 &&
                !wire.sent.any(
                    (r) => r.path.endsWith('fn_create_multi_image_session'));
            i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
        }
      });
      expect(shelvesSent('fn_create_multi_image_session'), [
        ['a'],
      ]);
    });

    testWidgets('a file and a set carry it too', (tester) async {
      FilePicker.platform = _Picker([
        _png('a.png'),
        _png('b.png'),
      ]);
      await pumpBody(tester);
      await choose(tester, 'Attention');
      await tester.tap(find.text('Drop files, or tap to add one'));
      await tester.pump();
      await tester.tap(find.text('One source'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(shelvesSent('fn_create_multi_image_session'), [
        ['a'],
      ]);
      await tester.tap(find.text('Drop files, or tap to add one'));
      await tester.pump();
      await tester.tap(find.text('Separate sources'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(shelvesSent('fn_create_upload_session'), [
        ['a'],
        ['a'],
      ]);
    });

    testWidgets('a shelf deleted since it was chosen goes, and is not sent',
        (tester) async {
      await pumpBody(tester);
      await choose(tester, 'Attention');
      await choose(tester, 'Birds');
      tags.deliver([shelf('b', 'Birds')]);
      await tester.pump();
      expect(find.text('Attention'), findsNothing);
      await addLink(tester, 'https://example.com/one');
      expect(shelvesSent('fn_ingest_url'), [
        ['b'],
      ]);
    });

    testWidgets(
        'a shelf just made goes on the next add before the read delivers it',
        (tester) async {
      wire = _Wire(body: const {'docId': 'n1', 'tagId': 'made'});
      ApiService.instance.httpClientAdapter = wire;
      await pumpBody(tester);
      await tester.tap(find.bySemanticsLabel('Add a shelf'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(
          find.byKey(const ValueKey('shelf-pick-search')), 'Field notes');
      await tester.pump();
      await tester.tap(find.textContaining('Create', findRichText: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('It goes on what you add next.'), findsOneWidget);
      expect(find.text('Find sources that belong here'), findsNothing,
          reason: 'the library holds no complete source');

      await tester.tap(find.text('Create shelf'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('It goes on what you add next.'), findsNothing,
          reason: 'the sheet closed, and the reader stayed');
      final made = wire.sent.singleWhere((r) => r.path.endsWith('fn_create_tag'));
      expect((made.data as Map)['title'], 'Field notes');

      // tags.shelves never had `made`: never a choice with no chip, and the add
      // carries it.
      expect(find.text('Field notes'), findsOneWidget);
      await addLink(tester, 'https://example.com/one');
      expect(shelvesSent('fn_ingest_url'), [
        ['made'],
      ]);

      tags.deliver([shelf('made', 'Field notes'), ...tags.shelves]);
      await tester.pump();
      expect(find.text('Field notes'), findsOneWidget, reason: 'the same chip');
    });

    testWidgets("a refused shelf is that row's own line, in the server's words",
        (tester) async {
      const sentence = 'One of the shelves you chose no longer exists. '
          'Take it off and try again.';
      wire = _Wire(status: 404, body: const {'error': sentence});
      ApiService.instance.httpClientAdapter = wire;
      await pumpBody(tester);
      await choose(tester, 'Attention');
      await addLink(tester, 'https://example.com/one');
      expect(find.text(sentence), findsOneWidget);
      expect(find.text('Attention'), findsOneWidget,
          reason: 'the chip stays, to be taken off');
    });

    testWidgets('a seeded opening sends what it was handed with none',
        (tester) async {
      await pumpBody(tester,
          seed: [PlatformFile(name: 'one.pdf', size: 4, bytes: Uint8List(4))]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final session =
          wire.sent.singleWhere((r) => r.path.endsWith('fn_create_upload_session'));
      expect((session.data as Map).containsKey('tagIds'), isFalse);
    });

    testWidgets('a second opening starts with nothing chosen', (tester) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(providers(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => QuickAdd.show(context),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await choose(tester, 'Attention');
      expect(find.text('Attention'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('SHELVES'), findsNothing, reason: 'closed');

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('SHELVES'), findsOneWidget);
      expect(find.text('Attention'), findsNothing,
          reason: 'closing the host drops the choice');
      await addLink(tester, 'https://example.com/one');
      expect(shelvesSent('fn_ingest_url'), [null]);
    });
  });
}
