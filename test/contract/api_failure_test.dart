import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/state/cloud_notifier.dart';

/// **C4g — the HTTP seam, and C4's cloud half gated through it.**
///
/// The seam was already there (`ApiService.httpClientAdapter`, used by the
/// api/* suite to assert request construction). What was missing was the
/// ability to put it BACK: `ApiService.instance` is a static singleton, both
/// seams are set on it, and nothing could undo either — so the suite that
/// installed a canned transport left it installed for everything that ran
/// after it in the same process. `test_isolation_test` now refuses that, and
/// named `api_requests_test` on its first run.
///
/// With a reset in place the adapter can answer with a real status and body,
/// which is what lets `CloudNotifier.loadIntegrations` be driven for real:
/// C4 gated that at the screen only and said so.

class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.status, this.body);

  final int status;
  final Object body;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return ResponseBody.fromString(
      body is String ? body as String : jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(() => ApiService.instance.tokenProvider = () async => 'test-token');
  tearDown(ApiService.instance.resetTestSeams);

  test('a refused integrations read is an ERROR, not an empty account',
      () async {
    ApiService.instance.httpClientAdapter = _CannedAdapter(500, {
      'error': 'Could not reach the integrations service.',
      'error_code': 'INTERNAL',
      'request_id': 'req-123',
    });

    final cloud = CloudNotifier();
    await cloud.loadIntegrations();

    expect(cloud.integrationsError, isNotNull,
        reason: 'it was swallowed as "leave the prior list" — true on a '
            'refresh and false on the only load that matters');
    expect(cloud.integrationsError, contains('integrations service'),
        reason: "§14 PARTS — the server's own sentence, not a constant");
    expect(cloud.integrationsLoaded, isFalse,
        reason: 'an empty list that was never read is not an account with '
            'nothing connected — which is what drew a Connect button beside '
            'a live integration');
    expect(cloud.integrationFor('notion'), isNull);
  });

  test('and a successful read clears it and marks the list read', () async {
    ApiService.instance.httpClientAdapter = _CannedAdapter(200, {
      'integrations': [
        {
          'provider': 'notion',
          'connected': true,
          'tokenValid': true,
        }
      ],
    });

    final cloud = CloudNotifier();
    await cloud.loadIntegrations();

    expect(cloud.integrationsError, isNull);
    expect(cloud.integrationsLoaded, isTrue);
    expect(cloud.integrationFor('notion'), isNotNull);
  });

  test('a later failure KEEPS the list it already read', () async {
    ApiService.instance.httpClientAdapter = _CannedAdapter(200, {
      'integrations': [
        {'provider': 'notion', 'connected': true, 'tokenValid': true}
      ],
    });
    final cloud = CloudNotifier();
    await cloud.loadIntegrations();

    ApiService.instance.httpClientAdapter =
        _CannedAdapter(503, {'error': 'Temporarily unavailable.'});
    await cloud.loadIntegrations();

    expect(cloud.integrationsError, contains('Temporarily unavailable'));
    expect(cloud.integrationsLoaded, isTrue,
        reason: 'the cards were true a moment ago and are kept, with the '
            'notice above them — only a list that was NEVER read is withheld');
    expect(cloud.integrationFor('notion'), isNotNull);
  });
}
