import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/state/ai_settings_notifier.dart';

/// 5.29.0 (ADR-186, INV-34) and 5.33.0 (ADR-190, INV-36): the reading rule and
/// write-before-move of the one AI-settings subscription (F-133, in F-144).
void main() {
  Map<String, dynamic> scenario(String id) {
    final f = File('../NoteLetter-contracts/fixtures/api/ai-settings/cases.json');
    final cases = (jsonDecode(f.readAsStringSync())['cases'] as List)
        .cast<Map<String, dynamic>>();
    return cases.firstWhere((c) => c['id'] == id);
  }

  Map<String, dynamic>? stored(String key, Object? v) =>
      v == 'absent' ? <String, dynamic>{} : {key: v};

  test('ai-settings:reading-check — only a stored literal false is off', () {
    final c = scenario('ai-settings:reading-check');
    final values = (c['request'] as Map)['values'] as List;
    final read = [
      for (final v in values)
        AiSettingsNotifier.generativeAiOf(stored('generativeAI', v)),
    ];
    // absent, false, true, "false", 0
    expect(read, [true, false, true, true, true]);
    expect(AiSettingsNotifier.generativeAiOf(null), isTrue);
  });

  test('ai-settings:video-reading-check — only a stored "claude" is Claude', () {
    final c = scenario('ai-settings:video-reading-check');
    final values = (c['request'] as Map)['values'] as List;
    final read = [
      for (final v in values)
        AiSettingsNotifier.videoAiOf(stored('videoAI', v)),
    ];
    // absent, "claude", "openai", "Claude", ""
    expect(read, [
      VideoAI.openai,
      VideoAI.claude,
      VideoAI.openai,
      VideoAI.openai,
      VideoAI.openai,
    ]);
  });

  test('loading and failed draw no generated surface (INV-34)', () async {
    final ctl = StreamController<Map<String, dynamic>>();
    final ai = AiSettingsNotifier(subscribe: () => ctl.stream)..start();
    expect(ai.genAI, GenAI.loading);
    expect(ai.aiOn, isFalse);
    expect(ai.videoAI, VideoAI.loading);
    ctl.add({});
    await pumpEventQueue();
    expect(ai.genAI, GenAI.on);
    expect(ai.videoAI, VideoAI.openai);
    ctl.addError(Exception('denied'));
    await pumpEventQueue();
    expect(ai.genAI, GenAI.failed);
    expect(ai.aiOn, isFalse);
    expect(ai.videoAI, VideoAI.failed);
    expect(ai.error, isNotNull);
    await ctl.close();
  });

  test('write before you move: a write changes nothing locally; a refusal '
      'keeps the stored value and says the server sentence', () async {
    final ctl = StreamController<Map<String, dynamic>>();
    final sent = <Map<String, Object?>>[];
    var refuse = false;
    final ai = AiSettingsNotifier(
      subscribe: () => ctl.stream,
      write: ({bool? generativeAI, String? videoAI}) async {
        sent.add({'generativeAI': generativeAI, 'videoAI': videoAI});
        if (refuse) throw Exception('Nope.');
        return null;
      },
    )..start();
    ctl.add({});
    await pumpEventQueue();

    final f = ai.setGenerativeAI(false);
    expect(ai.aiBusy, isTrue);
    await f;
    expect(ai.aiBusy, isFalse);
    expect(sent.last, {'generativeAI': false, 'videoAI': null});
    // Still on until the subscription brings the stored value back.
    expect(ai.genAI, GenAI.on);
    ctl.add({'generativeAI': false});
    await pumpEventQueue();
    expect(ai.genAI, GenAI.off);

    // Video reading: a press on the stored choice sends nothing.
    await ai.setVideoAI(VideoAI.openai);
    expect(sent.length, 1);
    await ai.setVideoAI(VideoAI.claude);
    expect(sent.last, {'generativeAI': null, 'videoAI': 'claude'});
    expect(ai.videoAI, VideoAI.openai);

    refuse = true;
    final err = await ai.setGenerativeAI(true);
    expect(err, isNotNull);
    expect(ai.aiError, err);
    expect(ai.genAI, GenAI.off);
    await ctl.close();
  });
}
