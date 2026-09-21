import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/services/api.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/endpoint_budgets.dart';

/// **C5 — the budget has to reach the REQUEST.**
///
/// `client_timeout_check.py` compares the table to the deploy recipes, both
/// ways. It cannot see whether the number is ever applied: a correct table
/// that no call site reads is the shape this workspace calls a gate that
/// proves wiring rather than behaviour. So the adapter records the deadline
/// Dio actually resolved for each verb, which is the only place the answer
/// exists.

class _RecordingAdapter implements HttpClientAdapter {
  final budgets = <String, Duration?>{};

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    budgets[options.path] = options.receiveTimeout;
    return ResponseBody.fromString('{}', 200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _RecordingAdapter adapter;

  setUp(() {
    adapter = _RecordingAdapter();
    ApiService.instance.tokenProvider = () async => 'test-token';
    ApiService.instance.httpClientAdapter = adapter;
  });
  tearDown(ApiService.instance.resetTestSeams);

  test('a 300s endpoint is waited on for 300s + the margin', () async {
    await Api.instance.synthesizeSearch('q');
    expect(adapter.budgets['/fn_synthesize_search'],
        const Duration(seconds: 300) + kTimeoutMargin,
        reason: 'the flat 30s gave up on this one ten times too early');
  });

  test('a 60s endpoint is waited on for 60s + the margin', () async {
    await Api.instance.askTurn('q');
    expect(adapter.budgets['/fn_ask_turn'],
        const Duration(seconds: 60) + kTimeoutMargin,
        reason: 'a 35s Ask rendered "Request timed out" and then the answer '
            'landed underneath it');
  });

  test('every budget outlasts the deadline it waits on', () {
    for (final e in kEndpointDeadlineSeconds.entries) {
      expect(clientTimeoutFor('/${e.key}').inSeconds, greaterThan(e.value),
          reason: '${e.key} would give up before the server is out of time');
    }
  });

  test('an unlisted path falls back to the norm, not to the old 30s', () {
    expect(clientTimeoutFor('/fn_not_in_the_table'), kDefaultTimeout);
    expect(kDefaultTimeout.inSeconds, greaterThan(60),
        reason: 'the fallback has to outlast the fleet norm too');
  });

  test('a query string does not defeat the lookup', () {
    expect(clientTimeoutFor('/fn_synthesize_search?docId=abc'),
        const Duration(seconds: 300) + kTimeoutMargin);
  });
}
