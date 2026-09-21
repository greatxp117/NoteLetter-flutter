import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/services/api_service.dart';

/// **C8 / ADR-112 — a body that is not our envelope.**
///
/// A Cloud Run or load-balancer 504 is an HTML page; a container that dies
/// mid-response sends nothing. `_handle` answered all of it with "Something
/// went wrong. Please try again." — no status, no words, a 504 and a malformed
/// body indistinguishable in a support thread — and a 2xx whose body was not a
/// Map threw a `TypeError` out of `data as Map<String, dynamic>`: not an
/// `ApiException`, so no screen could draw it as §14 and the one place that
/// counts `request_failed` never saw it.
///
/// The `else if` chain had a second edge. Its first arm was `data is Map`, so a
/// timeout whose response carried a Map with no `error` in it fell into that
/// arm, found nothing, and kept the generic constant — losing the timeout's own
/// sentence to a branch that had no answer either.
///
/// Driven through C4g's transport seam, so the real `_handle` runs against a
/// real status and body.

class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.status, this.body, {this.contentType = Headers.jsonContentType});

  final int status;
  final Object? body;
  final String contentType;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return ResponseBody.fromString(
      body is String ? body! as String : jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [contentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A transport that fails the way a receive timeout does, WITH a response body
/// attached — the shape the old first arm swallowed.
class _TimeoutAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.receiveTimeout,
      response: Response(
        requestOptions: options,
        statusCode: 504,
        data: const {'nothing': 'we can use'},
      ),
    );
  }

  @override
  void close({bool force = false}) {}
}

String sentence(int status) =>
    'The server did not answer as expected (HTTP $status).';

void main() {
  setUp(() => ApiService.instance.tokenProvider = () async => 'test-token');
  tearDown(ApiService.instance.resetTestSeams);

  test('an HTML 504 gets a sentence with its status, not a constant', () async {
    ApiService.instance.httpClientAdapter = _CannedAdapter(
        504, '<html><title>504 Gateway Timeout</title></html>',
        contentType: Headers.textPlainContentType);

    final e = await ApiService.instance
        .get('/fn_list_tags')
        .then<Object?>((_) => null)
        .catchError((Object e) => e);

    expect(e, isA<ApiException>());
    expect((e as ApiException).message, sentence(504));
    expect(e.statusCode, 504);
    expect(e.errorCode, isNull, reason: 'there was no envelope to carry one');
    expect(e.requestId, isNull);
  });

  test('a 2xx that is not JSON is a rejection, not a TypeError', () async {
    ApiService.instance.httpClientAdapter = _CannedAdapter(200, '<html>nope</html>',
        contentType: Headers.textPlainContentType);

    final e = await ApiService.instance
        .get('/fn_list_tags')
        .then<Object?>((_) => null)
        .catchError((Object e) => e);

    expect(e, isA<ApiException>(),
        reason: 'a TypeError is not a rejection any screen can render');
    expect((e as ApiException).message, sentence(200),
        reason: '(HTTP 200) is the honest thing to say about a 200 that could '
            'not be read');
  });

  test('a timeout that carried a body keeps the TIMEOUT sentence', () async {
    ApiService.instance.httpClientAdapter = _TimeoutAdapter();

    final e = await ApiService.instance
        .get('/fn_list_tags')
        .then<Object?>((_) => null)
        .catchError((Object e) => e);

    expect((e as ApiException).message,
        'Request timed out. Check your connection and try again.',
        reason: 'the old first arm was `data is Map`, which this satisfies '
            'while carrying no sentence at all');
  });

  test('the envelope still wins where there is one', () async {
    ApiService.instance.httpClientAdapter = _CannedAdapter(409, {
      'error': 'That shelf name is already taken.',
      'error_code': 'CONFLICT',
      'request_id': 'req-9',
    });

    final e = await ApiService.instance
        .post('/fn_create_tag')
        .then<Object?>((_) => null)
        .catchError((Object e) => e);

    expect((e as ApiException).message, 'That shelf name is already taken.');
    expect(e.errorCode, 'CONFLICT');
    expect(e.requestId, 'req-9');
  });

  test('a 401 quotes the server, and is still an UnauthorizedException',
      () async {
    ApiService.instance.httpClientAdapter = _CannedAdapter(401, {
      'error': 'Your session expired. Sign in again.',
    });

    final e = await ApiService.instance
        .get('/fn_list_tags')
        .then<Object?>((_) => null)
        .catchError((Object e) => e);

    expect(e, isA<UnauthorizedException>(),
        reason: 'notifiers route to sign-in by TYPE — the type must survive');
    expect((e as ApiException).message, 'Your session expired. Sign in again.',
        reason: 'an expired session, a revoked token and a drifted clock are '
            'three different next moves, and the constant said one thing');
  });

  test('a 401 with no sentence keeps the constant', () async {
    ApiService.instance.httpClientAdapter =
        _CannedAdapter(401, '', contentType: Headers.textPlainContentType);

    final e = await ApiService.instance
        .get('/fn_list_tags')
        .then<Object?>((_) => null)
        .catchError((Object e) => e);

    expect(e, isA<UnauthorizedException>());
    expect((e as ApiException).message, 'Session expired. Please log in again.');
  });

  test('an ordinary JSON 2xx still decodes', () async {
    ApiService.instance.httpClientAdapter =
        _CannedAdapter(200, {'tags': <dynamic>[]});
    expect(await ApiService.instance.get('/fn_list_tags'), {'tags': <dynamic>[]});
  });
}
