// F-95 — the cloud-connect claim (5.0.0, ADR-158, INV-32) and the app's own
// return (5.1.0, ADR-159): api/cloud-storage.md §Client behavior on return,
// over the captured answers. The request builders are the request suite's
// (`fn_claim_cloud_connection`, `return` on connect and enable); this is what
// the app does with what comes back.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/cloud_integration.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/shared/cloud_return.dart';
import 'package:flutter_app/state/cloud_notifier.dart';
import 'package:flutter_app/state/org_notifier.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

import 'fixtures.dart';
import 'sources_harness.dart';

Map<String, dynamic> _case(String suite, String id) {
  final s = loadSuite('api/$suite')!;
  return ((s['cases'] as List).firstWhere((c) => (c as Map)['id'] == id)
          as Map)
      .cast<String, dynamic>();
}

Map<String, dynamic> _body(String suite, String id) =>
    ((_case(suite, id)['response'] as Map)['body'] as Map)
        .cast<String, dynamic>();

/// The URL an app-return callback redirects to, as the capture recorded it:
/// `noteletter://cloud-connect` with the redirect's params.
String _appReturn(String suite, String id) {
  final b = _body(suite, id);
  return Uri.parse(b['target'] as String)
      .replace(queryParameters: (b['params'] as Map).cast<String, String>())
      .toString();
}

/// Answers every request with [body] and records what each one sent.
class _Server implements HttpClientAdapter {
  _Server(this.body);
  final Object body;
  final sent = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    sent.add(options);
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

/// A CloudNotifier whose claim is [answer] — the captured response, or a
/// refusal's sentence — gated on [gate], and which records what it was asked.
class _ClaimCloud extends CloudNotifier {
  _ClaimCloud({this.answer, this.refusal, this.gate});
  final Map<String, dynamic>? answer;
  final String? refusal;
  final Future<void>? gate;
  final claimed = <String>[];
  final opened = <String>[];

  /// The providers a claim has connected: the integration exists only once
  /// the claim answered (the read at mount ran before it).
  final live = <String>{};

  @override
  Future<void> loadIntegrations() async {}

  @override
  CloudIntegration? integrationFor(String provider) => live.contains(provider)
      ? CloudIntegration(provider: provider, tokenValid: true)
      : null;

  @override
  Future<({Map<String, dynamic>? answer, String? refusal})> claim(
      String claim) async {
    claimed.add(claim);
    if (gate != null) await gate;
    final a = answer;
    if (a != null && a['cloud_connect'] == 'success' && a['provider'] is String) {
      live.add(a['provider'] as String);
    }
    return (answer: a, refusal: refusal);
  }

  @override
  Future<void> openPicker(String provider) async => opened.add(provider);
}

void main() {
  setUp(() => ApiService.instance.tokenProvider = () async => 'test-token');
  tearDown(() {
    ApiService.instance.resetTestSeams();
    CloudReturn.session = null;
    CloudReturn.take();
  });

  group('the app asks for its own return, and holds what comes back', () {
    test('connect sends return: "app" and opens the authUrl in the session',
        () async {
      final server = _Server({'authUrl': 'https://accounts.example/auth?x=1'});
      ApiService.instance.httpClientAdapter = server;
      String? opened;
      CloudReturn.session = (url) async {
        opened = url;
        return _appReturn('cloud-storage', 'cloud:callback-return-app');
      };
      expect(await CloudNotifier().connect('google_drive'), isNull);
      expect(server.sent.single.path, endsWith('/fn_connect_cloud_storage'));
      expect(server.sent.single.data, {'provider': 'google_drive', 'return': 'app'});
      expect(opened, 'https://accounts.example/auth?x=1');
      final held = CloudReturn.take()!;
      expect(held.result, 'claim');
      expect(held.claim, 'cap-claim-app');
      expect(held.provider, 'google_drive');
      expect(CloudReturn.take(), isNull, reason: 'taken once, then nothing');
    });

    test('the organization grant asks for the same return', () async {
      final server = _Server({'authUrl': 'https://accounts.example/org'});
      ApiService.instance.httpClientAdapter = server;
      CloudReturn.session =
          (_) async => _appReturn('organization', 'org:callback-return-app');
      expect(await OrgNotifier().enableOrganization('google_drive'), isNull);
      expect(server.sent.single.path, endsWith('/fn_enable_organization'));
      expect(server.sent.single.data, {'provider': 'google_drive', 'return': 'app'});
      expect(CloudReturn.take()!.claim, 'cap-claim-org-app');
    });

    test('a cancelled session parked nothing and says nothing', () async {
      ApiService.instance.httpClientAdapter =
          _Server({'authUrl': 'https://accounts.example/auth'});
      CloudReturn.session = (_) async =>
          throw PlatformException(code: 'CANCELED', message: 'User canceled login');
      expect(await CloudNotifier().connect('dropbox'), isNull,
          reason: 'no sentence: Connect simply stays actionable');
      expect(CloudReturn.pending.value, isNull);
    });

    test('an error return is held as the error it is', () async {
      ApiService.instance.httpClientAdapter =
          _Server({'authUrl': 'https://accounts.example/auth'});
      CloudReturn.session = (_) async =>
          _appReturn('cloud-storage', 'cloud:callback-error-return-app');
      await CloudNotifier().connect('google_drive');
      final held = CloudReturn.take()!;
      expect(held.result, 'error');
      expect(held.reason, 'access_denied');
      expect(held.claim, isNull);
    });

    test('a 4.x success link is not a return anyone acts on', () {
      final r = CloudReturn.fromParams(
          const {'cloud_connect': 'success', 'provider': 'notion'});
      expect(r!.claim, isNull, reason: 'nothing to spend: Sources ignores it');
      expect(CloudReturn.fromParams(const {'provider': 'notion'}), isNull);
    });
  });

  group('Sources spends the claim once and answers it', () {
    testWidgets('a held claim is spent on arrival, then the picker opens',
        (tester) async {
      final gate = Completer<void>();
      final cloud = _ClaimCloud(
          answer: _body('cloud-storage', 'cloud:claim'), gate: gate.future);
      CloudReturn.hold(CloudReturn.fromParams(
          (_body('cloud-storage', 'cloud:callback-claim-redirect'))
              .cast<String, String>())!);
      await pumpSources(tester, SourcesStubService(), cloud: cloud);
      expect(cloud.claimed, ['cap-claim-own']);
      expect(find.text('Finishing the Google Drive connection…'), findsOneWidget,
          reason: 'the exchange takes a moment, and the return says so');

      gate.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('Finishing the Google Drive connection…'), findsNothing);
      // Direction D: the return is said in the Library's notices strip and
      // the first-import nudge over the panels — no toast.
      expect(
          find.text('Connected to Google Drive — import your first files '
              'below.'),
          findsOneWidget);
      expect(find.text('Google Drive connected.'), findsNothing);
      expect(cloud.opened, ['google_drive'],
          reason: 'the first-import prompt fires on return');
      await tester.pump();
      expect(cloud.claimed, hasLength(1), reason: 'a claim is spent once');
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('a claim that returns while Sources is open is spent there',
        (tester) async {
      final cloud = _ClaimCloud(answer: {
        ..._body('cloud-storage', 'cloud:claim'),
        'connection': 'reconnected',
      });
      await pumpSources(tester, SourcesStubService(), cloud: cloud);
      expect(cloud.claimed, isEmpty);
      CloudReturn.hold(const CloudReturn('claim',
          claim: 'cap-claim-app', provider: 'google_drive'));
      await tester.pump();
      await tester.pump();
      expect(cloud.claimed, ['cap-claim-app']);
      expect(
          find.text('Google Drive was already connected — your sign-in was '
              'refreshed and nothing else changed.'),
          findsOneWidget);
      expect(find.textContaining('import your first files'), findsNothing,
          reason: 'no import nudge: nothing was added to import');
      expect(cloud.opened, isEmpty,
          reason: 'a re-authorisation adds nothing to import');
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('a refused claim is §14.2 with the server\'s own sentence',
        (tester) async {
      final refused = _body('cloud-storage', 'cloud:claim-wrong-account');
      final cloud = _ClaimCloud(refusal: refused['error'] as String);
      CloudReturn.hold(const CloudReturn('claim',
          claim: 'cap-claim-handed', provider: 'google_drive'));
      await pumpSources(tester, SourcesStubService(), cloud: cloud);
      await tester.pump();
      expect(find.byType(KitFailureInline), findsOneWidget);
      expect(find.text(refused['error'] as String), findsOneWidget);
      expect(cloud.opened, isEmpty);
    });

    testWidgets('an org grant confirms the upgrade, and opens no picker',
        (tester) async {
      final cloud = _ClaimCloud(answer: {
        ..._body('cloud-storage', 'cloud:claim'),
        'org': 'enabled',
      });
      CloudReturn.hold(const CloudReturn('claim',
          claim: 'cap-claim-org-app', provider: 'google_drive'));
      await pumpSources(tester, SourcesStubService(), cloud: cloud);
      await tester.pump();
      expect(find.text('Auto-organization is now enabled for Google Drive.'),
          findsOneWidget);
      expect(cloud.opened, isEmpty);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('an error return is the reason banner, and spends nothing',
        (tester) async {
      final cloud = _ClaimCloud();
      final p = _body('cloud-storage', 'cloud:callback-error-return-app')['params']
          as Map;
      CloudReturn.hold(CloudReturn.fromParams(
          {...p.cast<String, String>(), 'provider': 'google_drive'})!);
      await pumpSources(tester, SourcesStubService(), cloud: cloud);
      expect(
          find.text('Access to Google Drive was declined. Connect again and '
              'approve to import your files.'),
          findsOneWidget);
      expect(cloud.claimed, isEmpty);
      // Direction D: a reason banner is a notice on the accent rule, and it
      // can be dismissed.
      expect(find.byType(KitLibNotice), findsOneWidget);
      await tester.tap(find.widgetWithText(KitHxLink, 'Dismiss'));
      await tester.pump();
      expect(find.textContaining('Access to Google Drive was declined'),
          findsNothing);
    });

    testWidgets('a claim answered with an error names its reason',
        (tester) async {
      final cloud = _ClaimCloud(answer: const {
        'cloud_connect': 'error',
        'provider': 'dropbox',
        'reason': 'something_new',
      });
      CloudReturn.hold(
          const CloudReturn('claim', claim: 'c', provider: 'dropbox'));
      await pumpSources(tester, SourcesStubService(), cloud: cloud);
      await tester.pump();
      expect(find.text('Couldn’t finish connecting Dropbox. Please try '
          'again.'), findsOneWidget,
          reason: 'open vocabulary: an unknown reason is the generic copy');
    });
  });
}
