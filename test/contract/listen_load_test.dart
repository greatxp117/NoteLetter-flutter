import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/pages/reader/listen_panel.dart';
import 'package:flutter_app/theme/app_theme.dart';

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
  setUp(() {
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
}
