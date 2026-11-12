/// F-205 — whitespace is what JavaScript trims (5.89.0, ADR-270).
///
/// Every text value a client checks before it sends is trimmed and tested with
/// ECMAScript's WhiteSpace + LineTerminator: U+0009–U+000D, U+0020, U+00A0,
/// U+1680, U+2000–U+200A, U+2028, U+2029, U+202F, U+205F, U+3000, U+FEFF. The
/// web reference's `trim()` is the rule and the server now agrees. Dart's
/// `String.trim()` also strips U+0085, so a value web and the server accept
/// was refused or altered here. U+001C–U+001F and U+0085 are TEXT.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/pages/settings/summary_prompt.dart'
    show parsePrompt, sendablePrompt;
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/shared/trim_text.dart';
import 'package:flutter_app/state/support_notifier.dart';

class _Recorder implements HttpClientAdapter {
  final List<RequestOptions> sent = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    sent.add(options);
    return ResponseBody.fromString(jsonEncode({'id': 'm1'}), 201, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// ADR-270 decision 1, written out as the ADR writes it.
const _space = [
  0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, //
  0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008,
  0x2009, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF,
];

/// What JavaScript keeps and Dart's trim() does not, or what neither strips.
const _text = [0x1C, 0x1D, 0x1E, 0x1F, 0x85, 0x200B, 0x180E];

void main() {
  group('trimText is ECMAScript trim()', () {
    for (final c in _space) {
      final s = String.fromCharCode(c);
      test('U+${c.toRadixString(16).toUpperCase().padLeft(4, '0')} is '
          'whitespace', () {
        expect(trimText('${s}x$s'), 'x');
        expect(trimText('$s$s'), '');
        expect(isJsSpace(c), isTrue);
      });
    }
    for (final c in _text) {
      final s = String.fromCharCode(c);
      test('U+${c.toRadixString(16).toUpperCase().padLeft(4, '0')} is text',
          () {
        expect(trimText('${s}x$s'), '${s}x$s');
        expect(trimText(' $s '), s);
        expect(isJsSpace(c), isFalse);
      });
    }
    test('the inside of a value is never touched', () {
      expect(trimText('　a \u0085 b﻿'), 'a \u0085 b');
      expect(trimText(''), '');
    });
  });

  group('the checked fields use it', () {
    test('the summary style: U+0085 alone is a value web sends', () {
      expect(sendablePrompt('\u0085'), '\u0085');
      expect(sendablePrompt(' \u001C\n'), '\u001C');
      expect(sendablePrompt('﻿　'), isNull);
      // A style that is only a separator is hand-written, not the default.
      expect(parsePrompt('\u0085'), isNull);
    });

    test('a support message: U+0085 alone is sent, as web sends it',
        () async {
      final rec = _Recorder();
      ApiService.instance.tokenProvider = () async => 'test-token';
      ApiService.instance.httpClientAdapter = rec;
      addTearDown(ApiService.instance.resetTestSeams);
      final n = SupportNotifier();
      expect(await n.send(' \u0085 '), isTrue);
      expect(rec.sent, hasLength(1));
      expect((rec.sent.single.data as Map)['body'], '\u0085');
      expect(await n.send('　﻿'), isFalse);
      expect(rec.sent, hasLength(1), reason: 'whitespace alone is not sent');
    });

    // Every field ADR-270 names that this client checks. A bare `.trim()` on
    // any of them is Dart's set; each must go through trimText.
    const fields = {
      'lib/pages/settings/summary_prompt.dart': [
        "(draft ?? '').trim()",
        "(text ?? '').trim()",
      ],
      'lib/pages/settings/summaries_section.dart': [
        '_draftText!.trim()',
        'shownText.trim()',
      ],
      'lib/pages/notification_settings_page.dart': [
        '_destCtrl.text.trim()',
        '_labelCtrl.text.trim()',
      ],
      'lib/state/support_notifier.dart': ['body.trim()'],
      'lib/pages/support_page.dart': ['_controller.text.trim()'],
      'lib/pages/letter_settings_page.dart': [
        '_emailCtrl.text.trim()',
        '_purposeCtrl.text.trim()',
        '_rlEmailCtrl.text.trim()',
      ],
      'lib/state/settings_notifier.dart': ['purposeText.trim()'],
      'lib/pages/onboarding/wizard.dart': ['_prompt.text.trim()'],
      'lib/pages/study/program_editor.dart': [
        '_title.text.trim()',
        '_email.text.trim()',
      ],
      'lib/pages/tags/suggest_shelves.dart': [
        'field.text.trim()',
        "(t['title'] as String).trim()",
        "?? '').trim()",
      ],
      'lib/pages/tags/shelf_sheet.dart': [
        '_name.text.trim()',
        '_desc.text.trim()',
        'name.trim()',
      ],
      'lib/pages/tags/split_shelf_sheet.dart': [
        'p.title.text.trim()',
        'p.description.text.trim()',
      ],
      'lib/pages/tags/shelf_page.dart': ['_name.text.trim()'],
      'lib/state/chat_notifier.dart': ['title.trim()', 'text.trim()'],
      'lib/pages/chat_page.dart': ['_controller.text.trim()'],
    };
    for (final MapEntry(key: path, value: gone) in fields.entries) {
      test('$path trims with trimText', () {
        final src = File(path).readAsStringSync();
        for (final g in gone) {
          expect(src.contains(g), isFalse,
              reason: '$path still trims `$g` with Dart\'s set');
        }
        expect(src, contains('trimText('));
      });
    }
  });
}
