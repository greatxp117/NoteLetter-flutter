import 'dart:convert';
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
import 'package:flutter_app/state/upload_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';
import 'package:flutter_app/widgets/quick_add.dart';

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
  Future<String?> connect(String provider) async {
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

  setUp(() {
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
      final cloud = _Cloud(answer: 'No authorization URL returned.');
      final r = await pumpBody(tester, cloud: cloud);
      await tester.tap(find.text('Google Drive'));
      await tester.pump();
      expect(cloud.asked, ['google_drive']);
      expect(find.text('Google Drive — No authorization URL returned.'),
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
}
