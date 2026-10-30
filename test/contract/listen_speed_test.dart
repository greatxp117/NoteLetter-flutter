/// Listen's playback speed (`screens/reader.md` §Playback speed; feature
/// `listen-playback-speed.md`, F-132) — web's `tests/contract/
/// listen-speed.test.js`: a kit §34 switch named "Speed", six rates, one
/// chosen, 1× by default; it sets the player's rate on a change AND on every
/// load; the choice is a reader preference stored on the device, and an
/// unknown stored value reads as 1×.
library;

import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/pages/reader/listen_panel.dart';
import 'package:flutter_app/pages/reader/reader_prefs.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(ReaderPrefs.resetForTest);
  tearDown(ReaderPrefs.resetForTest);

  group('the stored rate', () {
    test('is one of the six, labelled as web labels it', () {
      expect(ReaderPrefs.rates, [0.75, 1, 1.25, 1.5, 1.75, 2]);
      expect([for (final r in ReaderPrefs.rates) ReaderPrefs.rateLabel(r)],
          ['0.75×', '1×', '1.25×', '1.5×', '1.75×', '2×']);
      expect(const ReaderPrefs().rate, 1);
    });

    test('round-trips beside the typography, and is stored as web stores it',
        () {
      final p = const ReaderPrefs().copyWith(size: 'lg', rate: 1.75);
      final back = ReaderPrefs.fromJson(jsonDecode(jsonEncode(p.toJson())));
      expect(back, p);
      expect(back.rate, 1.75);
      expect(back.size, 'lg', reason: 'one store, one writer: nothing lost');
      expect(const ReaderPrefs().toJson()['rate'], 1,
          reason: 'web reads `1`; `1.0` would be the same number, but a '
              'store two clients share is spelled one way');
      // Web's own spelling reads back here.
      expect(ReaderPrefs.fromJson({'rate': 2}).rate, 2);
    });

    test('reads an unknown value as 1×', () {
      for (final raw in <Object?>[3, 0.5, '1.5', null, true]) {
        expect(ReaderPrefs.fromJson({'rate': raw}).rate, 1, reason: '$raw');
      }
      expect(ReaderPrefs.fromJson(null).rate, 1);
    });

    test('a stored rate survives a cold start', () async {
      SharedPreferences.setMockInitialValues({
        ReaderPrefs.storeKey: jsonEncode({'size': 'sm', 'rate': 1.25}),
      });
      await ReaderPrefs.ensureLoaded();
      expect(ReaderPrefs.current.value.rate, 1.25);
      expect(ReaderPrefs.current.value.size, 'sm');
    });
  });

  group('the Speed row', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<String> calls;
    late List<double> rates;

    // The plugin initialises its global scope ONCE per isolate and awaits
    // that future for every player after. Started inside one test's fake
    // clock, it is bound to that test's zone, and every later test's player
    // waits on it for ever; started here, in the real zone, it serves all.
    setUpAll(() async {
      messenger.setMockMethodCallHandler(
          const MethodChannel('xyz.luan/audioplayers.global'),
          (_) async => null);
      messenger.setMockStreamHandler(
          const EventChannel('xyz.luan/audioplayers.global/events'),
          MockStreamHandler.inline(onListen: (_, _) {}));
      await AudioPlayer.global.ensureInitialized();
    });

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      calls = [];
      rates = [];
      MockStreamHandlerEventSink? events;
      messenger.setMockMethodCallHandler(
          const MethodChannel('xyz.luan/audioplayers'), (call) async {
        final args = call.arguments as Map;
        final id = args['playerId'] as String;
        calls.add(call.method);
        if (call.method == 'create') {
          messenger.setMockStreamHandler(
              EventChannel('xyz.luan/audioplayers/events/$id'),
              MockStreamHandler.inline(onListen: (_, sink) {
                events = sink;
              }));
        }
        if (call.method == 'setPlaybackRate') {
          rates.add((args['playbackRate'] as num).toDouble());
        }
        if (call.method == 'setSourceUrl') {
          // A source the device prepared: what ends the plugin's wait.
          events?.success({'event': 'audio.onPrepared', 'value': true});
        }
        return null;
      });
    });

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ListenPanel(
              docId: 'd1',
              doc: Document.fromJson('d1', {
                'title': 'A narrated source',
                'type': 'pdf',
                'status': 'complete',
                'audio_url': 'https://example.test/a.mp3',
              }),
              paras: const ['One line.'],
            ),
          ),
        ),
      ));
      // The plugin's handshake crosses real platform-message futures.
      for (var i = 0; i < 10 && !calls.contains('setSourceUrl'); i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
    }

    testWidgets('is a §34 switch of six rates, 1× chosen by default, under the '
        'player controls', (tester) async {
      await pump(tester);
      final sw = tester.widget<KitSlideSwitch<double>>(
          find.byType(KitSlideSwitch<double>));
      expect(sw.label, 'Speed');
      expect([for (final o in sw.options) o.label],
          ['0.75×', '1×', '1.25×', '1.5×', '1.75×', '2×']);
      expect(sw.value, 1);
      expect(find.text('SPEED'), findsOneWidget);
      expect(
          tester.getTopLeft(find.byType(KitSlideSwitch<double>)).dy,
          greaterThan(tester.getTopLeft(find.byTooltip('Play')).dy),
          reason: 'below the controls');
    });

    testWidgets('sets the rate on load, and again on a change, which is stored',
        (tester) async {
      await pump(tester);
      final loaded = calls.indexOf('setSourceUrl');
      expect(loaded, greaterThan(-1));
      expect(calls.lastIndexOf('setPlaybackRate'), greaterThan(loaded),
          reason: 'applied again once the source loads');
      expect(rates.last, 1);

      await tester.tap(find.text('1.5×'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      expect(rates.last, 1.5);
      expect(ReaderPrefs.current.value.rate, 1.5);
      expect(
          tester
              .widget<KitSlideSwitch<double>>(
                  find.byType(KitSlideSwitch<double>))
              .value,
          1.5);
      final raw = await tester.runAsync<String?>(() async =>
          (await SharedPreferences.getInstance())
              .getString(ReaderPrefs.storeKey));
      final stored = jsonDecode(raw!);
      expect(stored['rate'], 1.5);
    });

    testWidgets('a rate chosen before the audio loads applies when it does',
        (tester) async {
      await ReaderPrefs.set(const ReaderPrefs(rate: 1.75));
      await pump(tester);
      final loaded = calls.indexOf('setSourceUrl');
      expect(calls.lastIndexOf('setPlaybackRate'), greaterThan(loaded));
      expect(rates.last, 1.75);
    });
  });
}
