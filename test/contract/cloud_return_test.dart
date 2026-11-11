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

import 'package:flutter_app/models/cloud_file.dart';
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
  Future<({Map<String, dynamic>? answer, String? refusal, String? requestId})>
      claim(String claim) async {
    claimed.add(claim);
    if (gate != null) await gate;
    final a = answer;
    if (a != null && a['cloud_connect'] == 'success' && a['provider'] is String) {
      live.add(a['provider'] as String);
    }
    return (answer: a, refusal: refusal, requestId: null);
  }

  @override
  Future<void> openPicker(String provider) async => opened.add(provider);

  /// The return page's root listing (5.46.0, ADR-201), without a network.
  @override
  Future<({CloudFileListing? listing, String? error})> listOffer(
          String provider,
          {String? pageToken}) async =>
      (
        listing: CloudFileListing(
          items: const [
            CloudFile(id: 'f1', name: 'Reading', type: 'folder'),
          ],
          folderId: 'root',
          provider: provider,
        ),
        error: null,
      );
}

void main() {
  setUp(() => ApiService.instance.tokenProvider = () async => 'test-token');
  tearDown(() {
    ApiService.instance.resetTestSeams();
    CloudReturn.session = null;
    CloudReturn.take();
    CloudReturn.forgetConnecting();
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
      // The one connect entry point remembers where it sent the reader
      // (5.46.0, ADR-201).
      expect(CloudReturn.connectingProvider, 'google_drive');
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

    // F-186 (sources.md §Quick add; web intake.jsx, CloudImportPanel.jsx,
    // OAuthReturn.jsx, QuickAdd.jsx): a 200 with no sign-in link is said in
    // web's words, not a developer's — *Try reconnecting.* where the reader
    // pressed Reconnect, *Try connecting again.* everywhere else.
    test('a connect with no sign-in link says so in web\'s words', () async {
      ApiService.instance.httpClientAdapter = _Server(const {});
      CloudReturn.session = (_) async => fail('no link, no session');
      expect(await CloudNotifier().connect('google_drive'),
          'The sign-in link did not come back. Try connecting again.');
      expect(await CloudNotifier().connect('google_drive', again: true),
          'The sign-in link did not come back. Try reconnecting.');
      expect(await OrgNotifier().enableOrganization('google_drive'),
          'The sign-in link did not come back. Try connecting again.');
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
      // An error redirect names no provider; the session that ran does
      // (5.46.0, ADR-201), so the return page can say *Google Drive*.
      expect(held.provider, 'google_drive');
    });

    test('a provider the return carried is never overwritten', () async {
      ApiService.instance.httpClientAdapter =
          _Server({'authUrl': 'https://accounts.example/auth'});
      CloudReturn.session = (_) async =>
          'noteletter://cloud-connect?cloud_connect=claim&claim=c&provider=notion';
      await CloudNotifier().connect('dropbox');
      expect(CloudReturn.take()!.provider, 'notion');
    });

    test('a 4.x success link is not a return anyone acts on', () {
      final r = CloudReturn.fromParams(
          const {'cloud_connect': 'success', 'provider': 'notion'});
      expect(r!.claim, isNull, reason: 'nothing to spend: Sources ignores it');
      expect(CloudReturn.fromParams(const {'provider': 'notion'}), isNull);
    });
  });

  // 5.52.0 (ADR-203, F-156): the return is the connect page's, its own route
  // pushed over Sources — no longer drawn in place on the Library.
  group('the connect page spends the claim once and answers it', () {
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('a held claim is spent on arrival, then {Provider}, Connected',
        (tester) async {
      final gate = Completer<void>();
      final cloud = _ClaimCloud(
          answer: _body('cloud-storage', 'cloud:claim'), gate: gate.future);
      CloudReturn.hold(CloudReturn.fromParams(
          (_body('cloud-storage', 'cloud:callback-claim-redirect'))
              .cast<String, String>())!);
      final router =
          await pumpConnectApp(tester, SourcesStubService(), cloud: cloud);
      await settle(tester);
      await tester.pump(const Duration(seconds: 1)); // the page transition
      expect(cloud.claimed, ['cap-claim-own']);
      expect(routerPath(router), '/connect/google_drive');
      // The claim in flight is the connect page's, over the Library.
      expect(find.text('Connecting Google Drive'), findsOneWidget);
      expect(find.text('Finishing the Google Drive connection…'), findsOneWidget,
          reason: 'the exchange takes a moment, and the return says so');
      expect(find.text('The Library'), findsNothing);

      gate.complete();
      await settle(tester);
      expect(find.text('Finishing the Google Drive connection…'), findsNothing);
      expect(find.text('Google Drive, Connected'), findsOneWidget);
      expect(find.text('Reading'), findsOneWidget,
          reason: 'what the provider offers, from the root listing');
      // One prompt, not two: the Library nudge and its picker are retired.
      expect(find.textContaining('import your first files'), findsNothing);
      expect(cloud.opened, isEmpty,
          reason: 'the return page IS the picker; none opens behind it');
      await tester.pump();
      expect(cloud.claimed, hasLength(1), reason: 'a claim is spent once');
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('a claim that returns while Sources is open opens the page '
        'over it and is spent there', (tester) async {
      final cloud = _ClaimCloud(answer: {
        ..._body('cloud-storage', 'cloud:claim'),
        'connection': 'reconnected',
      });
      final router =
          await pumpConnectApp(tester, SourcesStubService(), cloud: cloud);
      expect(cloud.claimed, isEmpty);
      CloudReturn.hold(const CloudReturn('claim',
          claim: 'cap-claim-app', provider: 'google_drive'));
      await settle(tester);
      expect(cloud.claimed, ['cap-claim-app']);
      expect(routerPath(router), '/connect/google_drive');
      expect(find.text('Already Connected'), findsOneWidget);
      expect(
          find.text('This Google Drive account was connected already. Your '
              'sign-in was refreshed, and nothing else changed.'),
          findsOneWidget);
      expect(find.text('no sync folders · auto-sync off'), findsOneWidget);
      expect(cloud.opened, isEmpty,
          reason: 'a re-authorisation adds nothing to import');
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('a refused claim is §14\'s block with the server\'s sentence',
        (tester) async {
      final refused = _body('cloud-storage', 'cloud:claim-wrong-account');
      final cloud = _ClaimCloud(refusal: refused['error'] as String);
      CloudReturn.hold(const CloudReturn('claim',
          claim: 'cap-claim-handed', provider: 'google_drive'));
      await pumpConnectApp(tester, SourcesStubService(), cloud: cloud);
      await settle(tester);
      expect(find.text('Not Connected'), findsOneWidget);
      expect(find.byType(KitFailureBlock), findsOneWidget);
      expect(find.text('The connection was not finished.'), findsOneWidget);
      expect(find.text(refused['error'] as String), findsOneWidget);
      expect(find.text('Connect Google Drive again'), findsOneWidget);
      expect(find.text('Google Drive, Connected'), findsNothing);
      expect(cloud.opened, isEmpty);
    });

    testWidgets('an org grant confirms the upgrade on the Library',
        (tester) async {
      final cloud = _ClaimCloud(answer: {
        ..._body('cloud-storage', 'cloud:claim'),
        'org': 'enabled',
      });
      CloudReturn.hold(const CloudReturn('claim',
          claim: 'cap-claim-org-app', provider: 'google_drive'));
      final router =
          await pumpConnectApp(tester, SourcesStubService(), cloud: cloud);
      await settle(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(routerPath(router), '/sources',
          reason: 'about organization, not a connection: handed to the Library');
      expect(find.text('Auto-organization is now enabled for Google Drive.'),
          findsOneWidget);
      expect(find.text('The Library'), findsOneWidget);
      expect(cloud.opened, isEmpty);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('an error return is Nothing Was Shared, and spends nothing',
        (tester) async {
      final cloud = _ClaimCloud();
      final p = _body('cloud-storage', 'cloud:callback-error-return-app')['params']
          as Map;
      CloudReturn.hold(CloudReturn.fromParams(
          {...p.cast<String, String>(), 'provider': 'google_drive'})!);
      await pumpConnectApp(tester, SourcesStubService(), cloud: cloud);
      await settle(tester);
      expect(find.text('Nothing Was Shared'), findsOneWidget);
      expect(
          find.text('You declined access in the Google Drive window, so '
              'nothing came across. Your library is exactly as you left it.'),
          findsOneWidget);
      expect(find.text('error: access_denied'), findsOneWidget);
      expect(find.text('Try Google Drive again'), findsOneWidget);
      expect(find.text('Add files instead'), findsOneWidget);
      expect(cloud.claimed, isEmpty);
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
      final router =
          await pumpConnectApp(tester, SourcesStubService(), cloud: cloud);
      await settle(tester);
      expect(find.text('Not Connected'), findsOneWidget);
      expect(find.text('Couldn’t finish connecting Dropbox. Please try '
          'again.'), findsOneWidget,
          reason: 'open vocabulary: an unknown reason is the generic copy');
      expect(find.text('error: something_new'), findsOneWidget);
      // Back to library leaves the page for Sources, nothing queued.
      await tester.ensureVisible(find.text('Back to library'));
      await tester.tap(find.text('Back to library'));
      await settle(tester);
      expect(routerPath(router), '/sources');
      expect(find.text('The Library'), findsOneWidget);
    });
  });
}
