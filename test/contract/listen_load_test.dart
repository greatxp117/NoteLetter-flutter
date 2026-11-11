import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/pages/reader/listen_panel.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/theme/app_theme.dart';

/// Answers `fn_get_raw_document_url` as the test says, after [gate].
class _Raw implements HttpClientAdapter {
  _Raw(this.status, this.body, {this.gate});
  final int status;
  final Object body;
  final Future<void>? gate;
  final sent = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    sent.add(options.path);
    if (gate != null) await gate;
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

/// The Listen panel's narration (TODO D, 2026-09-22).
///
/// Two defects, one panel. The model never read `audio_url`, so a narration
/// that already existed was never loaded and the reader was offered "Generate
/// audio" — a paid call — over audio web and iOS play. And `setSourceUrl` ran
/// unawaited, so a URL that could not be loaded drew 0:00 and nothing else.
///
/// The plugin's platform side is faked the way a device answers a URL it
/// cannot load: the player is created, and setting the source is refused. With
/// no platform at all the call does not fail, it WAITS — which is the other
/// half of why an unawaited call looked fine: nothing ever came back to it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final loaded = <String>[];
  tearDown(() => ApiService.instance.resetTestSeams());

  // The plugin initialises its global scope ONCE per isolate and every later
  // player awaits that future: started inside the first widget test's fake
  // clock it is bound to that zone, and a later test's player waits for ever
  // (listen_speed_test records the same). Started here, in the real zone.
  setUpAll(() async {
    messenger.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers.global'), (_) async => null);
    messenger.setMockStreamHandler(
        const EventChannel('xyz.luan/audioplayers.global/events'),
        MockStreamHandler.inline(onListen: (_, _) {}));
    await AudioPlayer.global.ensureInitialized();
  });
  setUp(() {
    loaded.clear();
    ApiService.instance.tokenProvider = () async => 'test-token';
    MockStreamHandlerEventSink? events;
    messenger.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers.global'), (_) async => null);
    messenger.setMockStreamHandler(
        const EventChannel('xyz.luan/audioplayers.global/events'),
        MockStreamHandler.inline(onListen: (_, __) {}));
    messenger.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers'), (call) async {
      final id = (call.arguments as Map)['playerId'] as String;
      if (call.method == 'create') {
        messenger.setMockStreamHandler(
            EventChannel('xyz.luan/audioplayers/events/$id'),
            MockStreamHandler.inline(onListen: (_, sink) {
              events = sink;
            }));
      }
      if (call.method == 'setSourceUrl') {
        loaded.add((call.arguments as Map)['url'] as String);
        // How the native side reports a source it cannot load: an error on the
        // player's event stream, which is what ends the plugin's wait for
        // "prepared". Throwing from the method alone leaves that wait to run
        // out its 30-second timeout.
        events?.error(code: 'DarwinAudioError', message: 'HTTP 404');
      }
      return null;
    });
  });

  Document doc(Map<String, dynamic> extra) => Document.fromJson('d1', {
        'title': 'A narrated source',
        'type': 'pdf',
        'status': 'complete',
        ...extra,
      });

  test('the model reads audio_url', () {
    expect(doc({'audio_url': 'https://x.test/n.mp3'}).audioUrl,
        'https://x.test/n.mp3');
    expect(doc({}).audioUrl, isNull);
  });

  Future<void> pump(WidgetTester tester, Document d) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ListenPanel(docId: 'd1', doc: d, paras: const ['One line.']),
        ),
      ),
    ));
    // The plugin's handshake crosses real platform-message futures, which a
    // fake-async pump does not drain; give it real time, then paint.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
  }

  testWidgets('an existing narration is loaded, not offered for generation',
      (tester) async {
    await pump(tester, doc({'audio_url': 'https://x.test/dead.mp3'}));
    expect(find.text('Generate audio'), findsNothing);
    expect(find.text('No narration yet.'), findsNothing);
    // …and a source that cannot be loaded says so in the player.
    expect(find.text('This recording could not be loaded.'), findsOneWidget);
  });

  testWidgets('with no narration, generation is still offered', (tester) async {
    await pump(tester, doc({}));
    expect(find.text('Generate audio'), findsOneWidget);
    expect(find.text('This recording could not be loaded.'), findsNothing);
  });

  // F-184 (reader.md §Listen: "never offer TTS for a document that has its own
  // audio"; web ListenPanel / docAudio.js). An uploaded recording (`audio`,
  // ADR-046) or video (`video`, ADR-049) has `source_audio_url` null BY
  // DESIGN; its URL is minted per request by fn_get_raw_document_url. Testing
  // the field alone offered a synthesized voice reading the transcript of the
  // user's own recording.
  for (final type in ['audio', 'video']) {
    testWidgets('an uploaded $type plays itself and is never offered narration',
        (tester) async {
      final release = Completer<void>();
      final api = _Raw(200, {'signed_url': 'https://x.test/memo.m4a'},
          gate: release.future);
      ApiService.instance.httpClientAdapter = api;
      await pump(tester, doc({'type': type}));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(api.sent.single, endsWith('/fn_get_raw_document_url'));
      expect(find.text('Loading the recording…'), findsOneWidget);
      expect(find.text('Generate audio'), findsNothing);
      expect(find.text('No narration yet.'), findsNothing);

      release.complete();
      // The answer, then the plugin's handshake (real platform-message
      // futures a fake-async pump does not drain), in turns — until the
      // player is handed a source, or a bounded number of turns.
      for (var i = 0; i < 40 && loaded.isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 10));
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
      }
      await tester.pump();
      expect(loaded, ['https://x.test/memo.m4a'],
          reason: 'the recording itself is what plays');
      expect(find.text('Generate audio'), findsNothing);
    });
  }

  testWidgets('a recording whose URL does not come back says so, and still '
      'offers no narration', (tester) async {
    ApiService.instance.httpClientAdapter = _Raw(200, {'signed_url': null});
    await pump(tester, doc({'type': 'audio'}));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(find.text('This recording could not be loaded.'), findsOneWidget);
    expect(find.text('Generate audio'), findsNothing);
  });
}
