/// Settings › Summaries: "Reset to default" is destructive (ruled
/// 2026-10-07; screens/settings.md §Summaries, 4.108.0). Tandem of web
/// 58c5d03.
///
/// It discards a hand-written summary style that nothing stores anywhere else,
/// so it is a **danger** Button and it confirms first (§18) whenever a custom
/// style is stored — `summary-style-reset` in harness/confirm_required.json,
/// which names `resetSummaryPrompt` on this client. It was a ghost button
/// that sent `{summaryPrompt: null}` on the first tap.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/pages/settings/summaries_section.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

class _Canned implements HttpClientAdapter {
  _Canned(this.reply);
  (int, Object?) Function(RequestOptions o) reply;
  final List<RequestOptions> sent = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    sent.add(options);
    final (status, body) = reply(options);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

/// The stored style, as the settings doc's subscription delivers it.
class _Stored extends FirestoreService {
  _Stored(this.prompt) : super.stub();
  final String? prompt;
  @override
  Stream<String?> subscribeSummarySettings() => Stream.value(prompt);
}

const _custom = 'Summarise like a field naturalist: what was seen, where, and '
    'what it suggests.';

Map<String, Object> _envelope(String error, String code) =>
    {'error': error, 'error_code': code, 'request_id': 'a1b2c3d4'};

Future<void> _pump(WidgetTester tester, String? stored) async {
  FirestoreService.instance = _Stored(stored);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: const Scaffold(
        body: SingleChildScrollView(child: SummariesSection())),
  ));
  await tester.pumpAndSettle();
}

Finder _reset() => find.widgetWithText(KitButton, 'Reset to default');

void main() {
  setUp(() => ApiService.instance.tokenProvider = () async => 'test-token');
  tearDown(() {
    ApiService.instance.resetTestSeams();
    FirestoreService.resetInstance();
  });

  testWidgets('it is the kit\'s danger button, offered over a stored style',
      (tester) async {
    ApiService.instance.httpClientAdapter = _Canned((_) => (200, {}));
    await _pump(tester, _custom);
    expect(_reset(), findsOneWidget);
    expect(tester.widget<KitButton>(_reset()).variant, KitButtonVariant.danger);
  });

  testWidgets('with no custom style stored there is nothing to discard',
      (tester) async {
    ApiService.instance.httpClientAdapter = _Canned((_) => (200, {}));
    await _pump(tester, null);
    expect(_reset(), findsNothing);
  });

  testWidgets('a tap opens §18 and sends nothing; Keep my style sends nothing',
      (tester) async {
    final api = _Canned((_) => (200, {}));
    ApiService.instance.httpClientAdapter = api;
    await _pump(tester, _custom);

    await tester.tap(_reset());
    await tester.pumpAndSettle();
    expect(find.byType(KitConfirm), findsOneWidget);
    expect(find.text('Discard your custom style?'), findsOneWidget);
    expect(find.textContaining('Your summary style, as written'), findsOneWidget,
        reason: 'names what is lost');
    expect(find.text('Summaries already written keep their text.'),
        findsOneWidget,
        reason: 'and what is not');
    expect(api.sent, isEmpty, reason: 'nothing is sent before the answer');

    await tester.tap(find.widgetWithText(KitButton, 'Keep my style'));
    await tester.pumpAndSettle();
    expect(find.byType(KitConfirm), findsNothing);
    expect(api.sent, isEmpty);
  });

  testWidgets('confirming sends exactly {summaryPrompt: null}, then closes',
      (tester) async {
    final api = _Canned((_) => (200, {}));
    ApiService.instance.httpClientAdapter = api;
    await _pump(tester, _custom);

    await tester.tap(_reset());
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(KitConfirm),
        matching: find.widgetWithText(KitButton, 'Reset to default')));
    await tester.pumpAndSettle();

    expect(api.sent, hasLength(1));
    expect(api.sent.single.method, 'PUT');
    expect(api.sent.single.path, endsWith('fn_summary_settings'));
    expect(api.sent.single.data, {'summaryPrompt': null});
    expect(find.byType(KitConfirm), findsNothing);
  });

  testWidgets('a refusal is said inside the panel, which stays open',
      (tester) async {
    const sentence = 'Summary settings could not be saved right now.';
    ApiService.instance.httpClientAdapter =
        _Canned((_) => (500, _envelope(sentence, 'INTERNAL_ERROR')));
    await _pump(tester, _custom);

    await tester.tap(_reset());
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(KitConfirm),
        matching: find.widgetWithText(KitButton, 'Reset to default')));
    await tester.pumpAndSettle();

    expect(find.byType(KitConfirm), findsOneWidget,
        reason: '§18 rule 1: a refusal never closes the panel');
    expect(
        find.descendant(
            of: find.byType(KitConfirm),
            matching: find.byType(KitFailureInline)),
        findsOneWidget);
    expect(find.textContaining(sentence), findsOneWidget);
  });
}
