// F-125 S1: the camera-roll sweep's native bridge on a real photo library
// (the simulator's). Run through tool/sweep_bridge_test.sh, which adds the
// photos and sets the permission for each phase; there is no emulator here.
//
// What this proves that the unit tests cannot: the bridge reads REAL assets —
// a real PHAssetResource.originalFilename, non-ASCII included — keys them,
// enumerates them newest first, runs the real Vision check on a real
// thumbnail, and renders a real JPEG; and with access off, refuses.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter_app/services/camera_sweep_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _phase = String.fromEnvironment('SWEEP_BRIDGE_PHASE', defaultValue: 'granted');

/// The spec's formula (§4), recomputed over what the bridge REPORTS. Equal
/// to the native key means the native key is sha256 of exactly these bytes.
String _specKey(SweepAsset a) {
  const distantPastSeconds = -62135769600.0; // Swift Date.distantPast
  final ms = ((a.creationSeconds ?? distantPastSeconds) * 1000).truncate();
  final material = 'v1|$ms|${a.pixelWidth}x${a.pixelHeight}|${a.originalFilename ?? 'unknown'}';
  return 'v1:${sha256.convert(utf8.encode(material))}';
}

// tool/sweep_test_photos.py, newest first.
const _cafe = 'Café crème — 日本語 ノート.jpg';
const _dense = 'sweep-dense.jpg';
const _sparse = 'sweep-sparse.jpg';
const _blank = 'sweep-blank.jpg';
const _ours = [_cafe, _dense, _sparse, _blank];

/// Photos hands the filename back DECOMPOSED (NFD: `e` + U+0301) although
/// the file was written composed (NFC) — seen on the first run. The key hashes
/// whatever Photos reports, and the Swift app read the same API, so this is no
/// threat to byte-identity; it only means a test must not look a name up by
/// its composed spelling. Combining marks are dropped and é/è folded to e for
/// the lookup ONLY; every key assertion uses the reported string.
bool _same(String? reported, String written) {
  String fold(String s) => String.fromCharCodes(s.runes.where((r) => r < 0x300 || r > 0x36F))
      .replaceAll('é', 'e')
      .replaceAll('è', 'e');
  return reported != null && fold(reported) == fold(written);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final bridge = CameraSweepBridge();

  // Feature spec §1: partial access is refused, not silently tolerated — the
  // native side answers every library method with the refusal, so a sweep
  // over a few hand-picked photos cannot run through this bridge at all.
  const refusals = {
    'limited': (
      SweepAccess.limited,
      'NoteLetter has access to a few hand-picked photos, not your library. '
          'A sweep needs the whole library to be useful — otherwise it would '
          'quietly find nothing.',
    ),
    'denied': (SweepAccess.denied, 'Photo access is off, so nothing can be swept.'),
  };
  if (refusals.containsKey(_phase)) {
    final (access, sentence) = refusals[_phase]!;
    testWidgets('$_phase access: every library method refuses, in the Swift words',
        (tester) async {
      expect(await bridge.access(), access);
      final refused = throwsA(isA<SweepAccessRefused>()
          .having((e) => e.access, 'access', access)
          .having((e) => e.sentence, 'sentence', sentence));
      await expectLater(bridge.fetchImages(), refused);
      await expectLater(bridge.examine('any'), refused);
      await expectLater(bridge.renderedJpeg('any'), refused);
      debugPrint('SWEEP $_phase: fetchImages, examine and renderedJpeg refused');
    });
    return;
  }

  testWidgets('full access: enumerate newest first, key, check, render', (tester) async {
    expect(_phase, 'granted', reason: 'SWEEP_BRIDGE_PHASE');
    expect(await bridge.access(), SweepAccess.granted);
    // Already decided, so no prompt: this returns the standing answer.
    expect(await bridge.requestAccess(), SweepAccess.granted);

    final c = await bridge.constants();
    expect((c.schemeVersion, c.prefilterVersion, c.minimumCharacters), ('v1', 1, 80));

    // The whole library, a page at a time.
    final all = <SweepAsset>[];
    int? total;
    do {
      final page = await bridge.fetchImages(offset: all.length, limit: 25);
      total = page.total;
      all.addAll(page.assets);
      if (page.assets.isEmpty) break;
    } while (all.length < total);
    expect(all.length, total);
    debugPrint('SWEEP library: $total images');

    // Newest first, as the fetch is sorted.
    final dated = [for (final a in all) if (a.creationSeconds != null) a.creationSeconds!];
    for (var i = 1; i < dated.length; i++) {
      expect(dated[i] <= dated[i - 1], isTrue, reason: 'newest first at $i');
    }

    // Every key is v1: + 64 hex, and is the spec formula over what was reported.
    for (final a in all) {
      expect(a.assetKey, matches(RegExp(r'^v1:[0-9a-f]{64}$')));
      expect(a.assetKey, _specKey(a), reason: '${a.originalFilename}');
    }

    final names = {for (final a in all) a.originalFilename};
    for (final name in _ours) {
      expect(names.any((n) => _same(n, name)), isTrue,
          reason: '"$name" not enumerated under its own name; names seen: $names');
    }

    // A re-import (each run of the script adds the photos again) is a new
    // localIdentifier with the SAME key: INV-14's restore case.
    for (final name in _ours) {
      final copies = all.where((a) => _same(a.originalFilename, name)).toList();
      expect({for (final a in copies) a.assetKey}.length, 1, reason: '$name: one key');
      expect({for (final a in copies) a.localIdentifier}.length, copies.length,
          reason: '$name: one id per copy');
      debugPrint('SWEEP copies of $name: ${copies.length}, one key');
    }

    final first = {
      for (final name in _ours) name: all.firstWhere((a) => _same(a.originalFilename, name))
    };
    // Their EXIF capture times run newest first in the order _ours lists them.
    final positions = [for (final name in _ours) all.indexOf(first[name]!)];
    expect([...positions]..sort(), positions, reason: 'our four, newest first');

    final expected = {
      _cafe: SweepVerdict.candidate,
      _dense: SweepVerdict.candidate,
      _sparse: SweepVerdict.noText,
      _blank: SweepVerdict.noText,
    };
    for (final name in _ours) {
      final a = first[name]!;
      final e = await bridge.examine(a.localIdentifier);
      debugPrint('SWEEP_BRIDGE_RESULT ${jsonEncode({
            'name': a.originalFilename,
            // The exact code points Photos reported: the key hashes THESE.
            'nameCodePoints': [
              for (final r in a.originalFilename!.runes) r.toRadixString(16).padLeft(4, '0')
            ].join(' '),
            'key': a.assetKey,
            'creationSeconds': a.creationSeconds,
            'w': a.pixelWidth,
            'h': a.pixelHeight,
            'screenshot': a.isScreenshot,
            'representative': a.isRepresentative,
            'verdict': e.verdict.name,
            'characters': e.characters,
            'thumbnail': '${e.thumbnailWidth}x${e.thumbnailHeight}',
          })}');
      expect(a.isScreenshot, isFalse, reason: name);
      expect(a.isRepresentative, isTrue, reason: name);
      expect(e.verdict, expected[name], reason: name);
      expect(e.prefilterVersion, 1);
      // Recognition ran on a THUMBNAIL: smaller than the 1600 px original.
      expect(e.thumbnailWidth, isNotNull, reason: name);
      final longEdge = [e.thumbnailWidth!, e.thumbnailHeight!].reduce((x, y) => x > y ? x : y);
      expect(longEdge < 1600, isTrue, reason: '$name thumbnail $longEdge');
      if (expected[name] == SweepVerdict.candidate) {
        expect(e.characters! >= 80, isTrue, reason: '$name: ${e.characters}');
      } else {
        expect(e.characters! < 80, isTrue, reason: '$name: ${e.characters}');
      }
    }

    // The upload bytes: a rendered JPEG on disk.
    final r = await bridge.renderedJpeg(first[_dense]!.localIdentifier);
    expect(r, isNotNull);
    final file = File(r!.path);
    final bytes = await file.readAsBytes();
    expect(bytes.length, r.bytes);
    expect(bytes.sublist(0, 2), [0xFF, 0xD8], reason: 'a JPEG');
    debugPrint('SWEEP rendered ${r.path} (${r.bytes} bytes)');
    await file.delete();

    await expectLater(bridge.examine('no-such-asset/L0/001'),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'notFound')));
  });
}
