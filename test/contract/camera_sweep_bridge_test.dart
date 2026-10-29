// F-125 S1: the camera-roll sweep's native bridge, its Dart half
// (lib/services/camera_sweep_bridge.dart). The native half is proven by
// ios/RunnerTests/CameraSweepBridgeTests.swift and, on the simulator, by
// integration_test/sweep_bridge_test.dart.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/services/camera_sweep_bridge.dart';

/// The INV-14 key, as `spec/features/camera-roll-sweep.md` §4 states it:
/// `sha256("v1|<ms>|<w>x<h>|<originalFilename>")`, ms truncated toward zero as
/// Swift's `Int(Double)` does, `Date.distantPast` for a missing date and
/// "unknown" for a missing filename (`AssetIdentity.swift:28-33`). The bridge
/// never computes keys in Dart; this exists to check what it reports.
String specKey(double? seconds, int w, int h, String? name) {
  const distantPastSeconds = -62135769600.0; // Swift Date.distantPast
  final ms = ((seconds ?? distantPastSeconds) * 1000).truncate();
  final material = 'v1|$ms|${w}x$h|${name ?? 'unknown'}';
  return 'v1:${sha256.convert(utf8.encode(material))}';
}

/// Keys the ORIGINAL Swift `AssetIdentity.assetKey(for:)` produced for these
/// inputs (compiled unchanged with swiftc over a fake PHAsset, 2026-10-18,
/// F-125 S1 report). The same table is in RunnerTests against the port. The
/// name column is the resource the Swift preference rule picked.
const _goldens = <(String, double?, int, int, String?, String)>[
  ('screenshot-fractional-ms', 1700000000.123456, 1170, 2532, 'IMG_0001.PNG',
      'v1:cd0fc261514e464d21f034cbb0d9f0a8132936225f3bd42aa8d1a500220b64e1'),
  ('heic-near-next-ms', 1700000000.9999, 4032, 3024, 'IMG_4821.HEIC',
      'v1:377261fc4330b23d0fcecd403f7b290bfffcbdbb8b2bb92444614a1de6f2bb1f'),
  ('no-date-no-resources', null, 100, 100, null,
      'v1:97f733a4c961a07a70f2ccb65ad94b8da243a17bfa9be5fb8a491523bac66014'),
  ('non-ascii-prefers-photo', 1500000000.0, 1920, 1080, 'Café crème — 日本語 ノート.jpeg',
      'v1:90bbae8039da619d6169a78abf61091c09b0cb5024bf00bb23dcaae63d4b395e'),
  ('nfc-e-acute', 1600000000.5, 800, 600, 'Café.jpg',
      'v1:decb8c84656a68890675ad2c5a3b7537fa0d256f8bde8c90517215f05eb3b334'),
  ('nfd-e-acute', 1600000000.5, 800, 600, 'Café.jpg',
      'v1:d33ef2f6f56e1390e786201e46b65ce9d4ecc5b4da3d7ec004ab1bff825a1d44'),
  ('emoji', 1650000000.001, 3024, 4032, '📝 notes 🧾.png',
      'v1:733b856f39a891b3ec984ddbfc3f411165a6ad0c7011403168cef1d1cda31389'),
  ('negative-fraction', -1.5, 1, 1, 'old.jpg',
      'v1:d895041930d6c5431bcc5157ba7d2b399b3b4674d16032fe4bcdb484459ccdae'),
  ('tiny-negative-truncates-to-zero', -0.0005, 2, 2, 'epoch.jpg',
      'v1:6e9da197b14a3f00f1ee7b4c2568cb935ef58d5b71f8b80d005a4487f83b740b'),
  ('fullsize-when-no-photo', 1690000000.25, 640, 480, 'FullSizeRender.jpg',
      'v1:8e05fa3cfaa64d5a0ad19983c9c96147cae2ac490388076f8bac199a5f3be416'),
  ('first-when-neither', 1690000000.25, 640, 480, 'clip.MOV',
      'v1:7fd55a9ca1e08d41ad1f703b6b4eeccc89e6bc36116c2cb714e77283b7ab50a7'),
  ('pipe-in-name', 1700000001.0, 10, 20, 'a|b.jpg',
      'v1:6d5d182fdfcae8ab1fdff64d8c93824482e79e2c6c7aa544f168a65eb5ae7159'),
  ('empty-name-is-not-unknown', 1700000002.0, 10, 20, '',
      'v1:5af3cf2ffede13323fb0d5b0615a1c50c103e382a06377a08147c41fa3790f29'),
];

/// A listing as the native side sends it (5.40.0): no key, no filename.
Map<String, Object?> _listing(String id, {double? seconds = 1700000000.5}) => {
      'localIdentifier': id,
      'creationSeconds': seconds,
      'pixelWidth': 1170,
      'pixelHeight': 2532,
      'isScreenshot': false,
      'isRepresentative': true,
    };

/// An identified asset ([CameraSweepBridge.identify]): the listing, the key
/// and the filename.
Map<String, Object?> _asset(String id, {double? seconds = 1700000000.5}) => {
      ..._listing(id, seconds: seconds),
      'assetKey': specKey(seconds, 1170, 2532, 'IMG_$id.PNG'),
      'originalFilename': 'IMG_$id.PNG',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(CameraSweepBridge.channelName);
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final bridge = CameraSweepBridge();
  final calls = <MethodCall>[];

  void answer(Future<Object?> Function(MethodCall) handler) {
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(calls.clear);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('the INV-14 key', () {
    test('the spec formula gives the original Swift keys, all 13 vectors', () {
      for (final (label, seconds, w, h, name, key) in _goldens) {
        expect(specKey(seconds, w, h, name), key, reason: label);
      }
    });

    test('the filename is not normalised: NFC and NFD é are two keys', () {
      final nfc = _goldens.firstWhere((g) => g.$1 == 'nfc-e-acute');
      final nfd = _goldens.firstWhere((g) => g.$1 == 'nfd-e-acute');
      expect(nfc.$5, isNot(nfd.$5)); // the strings differ as code units…
      expect(nfc.$6, isNot(nfd.$6)); // …so the original keyed them apart
    });

    test('a key is v1: and 64 hex digits', () {
      for (final g in _goldens) {
        expect(g.$6, matches(RegExp(r'^v1:[0-9a-f]{64}$')), reason: g.$1);
      }
    });
  });

  group('requests', () {
    test('fetchImages sends the window and the page, 200 by default', () async {
      answer((_) async => {'total': 0, 'assets': <Object?>[]});
      final since = DateTime.utc(2026, 7, 20);
      final until = DateTime.utc(2026, 10, 18, 12);
      await bridge.fetchImages(since: since, until: until, offset: 400);
      await bridge.fetchImages();
      expect(calls[0].method, 'fetchImages');
      expect(calls[0].arguments, {
        'sinceMs': since.millisecondsSinceEpoch,
        'untilMs': until.millisecondsSinceEpoch,
        'offset': 400,
        'limit': 200,
        'localIdentifiers': null,
      });
      expect(calls[1].arguments, {
        'sinceMs': null,
        'untilMs': null,
        'offset': 0,
        'limit': 200,
        'localIdentifiers': null,
      });
    });

    test('fetchImages over named photos sends their ids, in the same window', () async {
      answer((_) async => {'total': 0, 'assets': <Object?>[]});
      final since = DateTime.utc(2026, 7, 20);
      await bridge.fetchImages(since: since, localIdentifiers: ['A/L0/001', 'B/L0/001']);
      expect(calls.single.arguments, {
        'sinceMs': since.millisecondsSinceEpoch,
        'untilMs': null,
        'offset': 0,
        'limit': 200,
        'localIdentifiers': ['A/L0/001', 'B/L0/001'],
      });
    });

    test('identify, changeToken and changesSince', () async {
      answer((call) async => switch (call.method) {
            'identify' => _asset('1'),
            'changeToken' => 'tok-1',
            _ => {'token': 'tok-2', 'localIdentifiers': <Object?>[]},
          });
      await bridge.identify('A/L0/001');
      await bridge.changeToken();
      await bridge.changesSince('tok-1');
      expect(calls.map((c) => c.method), ['identify', 'changeToken', 'changesSince']);
      expect(calls[0].arguments, {'localIdentifier': 'A/L0/001'});
      expect(calls[1].arguments, isNull);
      expect(calls[2].arguments, {'token': 'tok-1'});
    });

    test('a page that cannot exist is refused before the channel', () async {
      answer((_) async => fail('no call expected'));
      expect(() => bridge.fetchImages(offset: -1), throwsArgumentError);
      expect(() => bridge.fetchImages(limit: 0), throwsArgumentError);
      expect(calls, isEmpty);
    });

    test('examine and renderedJpeg name one asset', () async {
      answer((call) async => call.method == 'examine'
          ? {
              'verdict': 'noText',
              'characters': 12,
              'thumbnailWidth': 1024,
              'thumbnailHeight': 768,
              'prefilterVersion': 1,
            }
          : null);
      await bridge.examine('A/L0/001');
      await bridge.renderedJpeg('A/L0/001');
      expect(calls.map((c) => c.method), ['examine', 'renderedJpeg']);
      for (final c in calls) {
        expect(c.arguments, {'localIdentifier': 'A/L0/001'});
      }
    });
  });

  group('partial access is refused, in the Swift app\'s words', () {
    for (final method in [
      'fetchImages',
      'identify',
      'examine',
      'renderedJpeg',
      'changeToken',
      'changesSince',
    ]) {
      test('$method: limited', () async {
        answer((_) async => throw PlatformException(code: 'limited'));
        final Future<Object?> call = switch (method) {
          'fetchImages' => bridge.fetchImages(),
          'identify' => bridge.identify('x'),
          'examine' => bridge.examine('x'),
          'changeToken' => bridge.changeToken(),
          'changesSince' => bridge.changesSince('t'),
          _ => bridge.renderedJpeg('x'),
        };
        await expectLater(
          call,
          throwsA(isA<SweepAccessRefused>()
              .having((e) => e.access, 'access', SweepAccess.limited)
              .having((e) => e.sentence, 'sentence',
                  'NoteLetter has access to a few hand-picked photos, not your '
                  'library. A sweep needs the whole library to be useful — '
                  'otherwise it would quietly find nothing.')),
        );
      });
    }

    test('denied', () async {
      answer((_) async => throw PlatformException(code: 'denied'));
      await expectLater(
        bridge.fetchImages(),
        throwsA(isA<SweepAccessRefused>()
            .having((e) => e.access, 'access', SweepAccess.denied)
            .having((e) => e.sentence, 'sentence',
                'Photo access is off, so nothing can be swept.')),
      );
    });

    test('any other native error stays itself', () async {
      answer((_) async => throw PlatformException(code: 'notFound'));
      await expectLater(bridge.examine('gone'),
          throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'notFound')));
    });
  });

  group('answers', () {
    test('access decodes the three states and nothing else', () async {
      for (final s in ['granted', 'limited', 'denied']) {
        answer((_) async => s);
        expect((await bridge.access()).name, s);
        expect((await bridge.requestAccess()).name, s);
      }
      answer((_) async => 'notDetermined');
      await expectLater(bridge.access(), throwsFormatException);
    });

    test('a page decodes every field of a listing, and carries no key', () async {
      answer((_) async => {
            'total': 2,
            'assets': [
              _listing('1'),
              {..._listing('2', seconds: null), 'isRepresentative': false},
            ],
          });
      final page = await bridge.fetchImages();
      expect(page.total, 2);
      final a = page.assets.first;
      expect(a, isNot(isA<SweepAsset>()));
      expect(a.localIdentifier, '1');
      expect(a.creationDate, DateTime.utc(2023, 11, 14, 22, 13, 20, 500));
      expect(a.isRepresentative, isTrue);
      final b = page.assets.last;
      expect(b.creationSeconds, isNull);
      expect(b.creationDate, isNull);
      expect(b.isRepresentative, isFalse);
    });

    test('identify decodes the key and the filename', () async {
      answer((_) async => {..._asset('2', seconds: null), 'originalFilename': null});
      final a = await bridge.identify('2');
      expect(a.localIdentifier, '2');
      expect(a.assetKey, specKey(null, 1170, 2532, 'IMG_2.PNG'));
      expect(a.originalFilename, isNull);
      answer((_) async => _asset('1'));
      expect((await bridge.identify('1')).assetKey,
          specKey(1700000000.5, 1170, 2532, 'IMG_1.PNG'));
    });

    test('a change token is a string or null, and nothing else', () async {
      answer((_) async => 'tok');
      expect(await bridge.changeToken(), 'tok');
      answer((_) async => null);
      expect(await bridge.changeToken(), isNull, reason: 'no history: every pass walks');
      answer((_) async => 3);
      await expectLater(bridge.changeToken(), throwsFormatException);
    });

    test('changesSince: the changes, null for a token that cannot answer, and closed', () async {
      answer((_) async => {'token': 'tok-2', 'localIdentifiers': ['a', 'b']});
      final c = await bridge.changesSince('tok-1');
      expect(c!.token, 'tok-2');
      expect(c.localIdentifiers, ['a', 'b']);
      answer((_) async => null);
      expect(await bridge.changesSince('old'), isNull, reason: 'only a walk will do');
      for (final bad in [
        {'localIdentifiers': <Object?>[]},
        {'token': 'tok'},
        {'token': 'tok', 'localIdentifiers': 'a'},
        {'token': 'tok', 'localIdentifiers': [1]},
      ]) {
        answer((_) async => bad);
        await expectLater(bridge.changesSince('t'), throwsFormatException, reason: '$bad');
      }
    });

    test('an examination decodes, and an unknown verdict is a failure', () async {
      answer((_) async => {
            'verdict': 'candidate',
            'characters': null,
            'thumbnailWidth': null,
            'thumbnailHeight': null,
            'prefilterVersion': 1,
          });
      final e = await bridge.examine('s');
      expect(e.verdict, SweepVerdict.candidate);
      expect(e.characters, isNull);
      expect(e.prefilterVersion, 1);

      answer((_) async => {
            'verdict': 'maybe',
            'characters': 3,
            'thumbnailWidth': 1,
            'thumbnailHeight': 1,
            'prefilterVersion': 1,
          });
      await expectLater(bridge.examine('s'), throwsFormatException);
    });

    test('a missing field is a failure, never a default', () async {
      final listed = _listing('1');
      for (final key in listed.keys) {
        answer((_) async => {
              'total': 1,
              'assets': [Map.of(listed)..remove(key)],
            });
        await expectLater(bridge.fetchImages(), throwsFormatException, reason: key);
      }
      final identified = _asset('1');
      for (final key in identified.keys) {
        answer((_) async => Map.of(identified)..remove(key));
        await expectLater(bridge.identify('1'), throwsFormatException, reason: key);
      }
    });

    test('renderedJpeg: a file, or null when nothing rendered', () async {
      answer((_) async => {'path': '/tmp/camera-sweep/v1-ab.jpg', 'bytes': 2048});
      final r = await bridge.renderedJpeg('x');
      expect(r!.path, endsWith('.jpg'));
      expect(r.bytes, 2048);
      answer((_) async => null);
      expect(await bridge.renderedJpeg('x'), isNull);
    });

    test('constants', () async {
      answer((_) async =>
          {'schemeVersion': 'v1', 'prefilterVersion': 1, 'minimumCharacters': 80});
      final c = await bridge.constants();
      expect(c.schemeVersion, 'v1');
      expect(c.prefilterVersion, 1);
      expect(c.minimumCharacters, 80);
    });
  });
}
