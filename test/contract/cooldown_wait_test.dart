/// A cooldown's wait is a NUMBER, and the control waits it out (4.107.0,
/// ADR-140; component-kit §6.1 Waiting). The port of the reference's
/// `tests/contract/cooldown-wait.test.js`.
///
/// C11 made a cooldown's sentence the server's. What was still missing was the
/// wait as something a control can act on: every screen said "Please wait 43
/// seconds" and left the button live, so a second tap earned a second refusal.
/// Every cooldown envelope now carries `retry_after_s`; these cases hold this
/// client to it:
///
///   * the number is parsed from OUR envelope and from nothing else — a
///     string, a zero, a body that is not the envelope are all "no number";
///   * each of the nine builders arms the wait the SERVER scopes it to, and
///     no other;
///   * a refusal with a number holds the control for exactly that long, says
///     the remaining time on it, shows the server's sentence while it runs and
///     takes both away at zero;
///   * a refusal WITHOUT a number is drawn exactly as before;
///   * nothing moves before the refusal arrives (write before you move);
///   * the wait belongs to the server's scope, not to a widget: two controls
///     over one scope wait on one clock, and a remount keeps it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/models/cloud_folder.dart';
import 'package:flutter_app/models/cloud_integration.dart';
import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/import_job.dart';
import 'package:flutter_app/models/newsletter_settings.dart';
import 'package:flutter_app/models/study.dart';
import 'package:flutter_app/pages/letters/letter_preview.dart';
import 'package:flutter_app/pages/letters_page.dart';
import 'package:flutter_app/pages/reader/summary_panel.dart';
import 'package:flutter_app/pages/sources/browse_section.dart';
import 'package:flutter_app/pages/sources/organization_settings_panel.dart';
import 'package:flutter_app/pages/study_page.dart';
import 'package:flutter_app/pages/support_page.dart';
import 'package:flutter_app/services/api.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/shared/cooldown.dart';
import 'package:flutter_app/state/activity_notifier.dart';
import 'package:flutter_app/state/org_notifier.dart';
import 'package:flutter_app/state/settings_notifier.dart';
import 'package:flutter_app/state/support_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

import 'sources_harness.dart';

/// Answers every request with [reply]; records what was sent.
class _Canned implements HttpClientAdapter {
  _Canned(this.reply);
  (int, Object?) Function(RequestOptions o) reply;
  final List<RequestOptions> sent = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    sent.add(options);
    final (status, body) = reply(options);
    final isJson = body is Map || body is List;
    return ResponseBody.fromString(
        isJson ? jsonEncode(body) : '$body', status,
        headers: {
          Headers.contentTypeHeader: [
            isJson ? Headers.jsonContentType : Headers.textPlainContentType
          ]
        });
  }

  @override
  void close({bool force = false}) {}
}

/// Holds the first request until [answer], so the in-flight state can be
/// looked at.
class _Held implements HttpClientAdapter {
  final List<RequestOptions> sent = [];
  final _reply = Completer<(int, Object)>();

  void answer(int status, Object body) => _reply.complete((status, body));

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    sent.add(options);
    final (status, body) = await _reply.future;
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object> _envelope(String error, String code, [int? wait]) => {
      'error': error,
      'error_code': code,
      'request_id': 'a1b2c3d4',
      'retry_after_s': ?wait,
    };

class _StudyStub extends FirestoreService {
  _StudyStub(this.programs) : super.stub();
  final List<StudyProgram> programs;

  @override
  String? get currentUid => 'u1';

  @override
  Stream<List<StudyProgram>> subscribeStudyPrograms() => Stream.value(programs);

  @override
  Stream<List<StudySession>> subscribeStudySessions(
          {String? programId, int limit = 30}) =>
      Stream.value(const []);
}

class _FoldersStub extends FirestoreService {
  _FoldersStub(this.folders) : super.stub();
  final List<CloudFolder> folders;

  @override
  String? get currentUid => 'u1';

  @override
  Stream<List<CloudFolder>> subscribeCloudFolders(String provider) =>
      Stream.value(folders.where((f) => f.provider == provider).toList());
}

class _Settings extends SettingsNotifier {
  @override
  NewsletterSettings? get newsletter => const NewsletterSettings(
      enabled: true,
      deliveryTime: '08:00',
      timezone: 'America/Chicago',
      frequency: 'daily');
}

class _ConnectedCloud extends QuietCloud {
  _ConnectedCloud(this.integration);
  final CloudIntegration integration;

  @override
  CloudIntegration? integrationFor(String provider) =>
      provider == integration.provider ? integration : null;
}

Widget _app(Widget child) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

/// The KitButton whose whole label (suffix included) is [label].
Finder _button(String label) => find.widgetWithText(KitButton, label);

void main() {
  // The registry's clock, moved by hand: `testWidgets` fakes timers but not
  // `DateTime.now`, so a step through a wait moves both together.
  late DateTime now;
  Future<void> step(WidgetTester tester, Duration d) async {
    now = now.add(d);
    await tester.pump(d);
  }

  setUp(() {
    now = DateTime.utc(2026, 10, 6, 12);
    Cooldowns.instance.clock = () => now;
    ApiService.instance.tokenProvider = () async => 'test-token';
  });
  tearDown(() {
    Cooldowns.instance.resetForTest();
    ApiService.instance.resetTestSeams();
    FirestoreService.resetInstance();
  });

  group('the number is parsed from our envelope and nothing else', () {
    test('a positive whole number is the wait', () {
      expect(retryAfterSeconds({'retry_after_s': 43}), 43);
      expect(retryAfterSeconds({'retry_after_s': 1}), 1);
      expect(retryAfterSeconds({'retry_after_s': 43.0}), 43,
          reason: 'JSON has no int/float: a whole 43.0 is the reference\'s 43');
    });

    test('anything else is no number at all', () {
      for (final body in <Object?>[
        null,
        'HTTP 429',
        <String, Object?>{},
        {'retry_after_s': '43'},
        {'retry_after_s': 0},
        {'retry_after_s': -5},
        {'retry_after_s': 4.5},
        {'retry_after_s': null},
        [43],
      ]) {
        expect(retryAfterSeconds(body), isNull, reason: jsonEncode(body));
      }
    });

    test('it rides ApiException from a real refusal, and arms the document',
        () async {
      ApiService.instance.httpClientAdapter = _Canned((_) => (
            429,
            _envelope('Please wait 43 seconds before retrying.',
                'RATE_LIMITED', 43)
          ));
      final e = await Api.instance
          .retryDocument('d1')
          .then<Object?>((_) => null, onError: (Object x) => x);
      expect(e, isA<ApiException>());
      expect((e as ApiException).retryAfterS, 43);
      expect(Cooldowns.instance.left(WaitKey.documentRetry('d1')), 43);
      expect(Cooldowns.instance.left(WaitKey.documentRetry('d2')), 0);
    });

    test('the cap is a 429 with NO number, and arms nothing', () async {
      ApiService.instance.httpClientAdapter = _Canned((_) => (
            429,
            _envelope('Maximum retry attempts (3) reached for this document.',
                'RATE_LIMITED')
          ));
      final e = await Api.instance
          .retryDocument('d1')
          .then<Object?>((_) => null, onError: (Object x) => x);
      expect((e as ApiException).retryAfterS, isNull);
      expect(Cooldowns.instance.left(WaitKey.documentRetry('d1')), 0);
    });

    test('a body that is not our envelope arms nothing', () async {
      ApiService.instance.httpClientAdapter =
          _Canned((_) => (429, '<html>429 Too Many Requests</html>'));
      final e = await Api.instance
          .requestCloudSync('google_drive')
          .then<Object?>((_) => null, onError: (Object x) => x);
      expect((e as ApiException).retryAfterS, isNull);
      expect(Cooldowns.instance.left(WaitKey.cloudSync('google_drive')), 0);
    });

    test('a 401 is never a wait', () async {
      ApiService.instance.httpClientAdapter = _Canned((_) =>
          (401, _envelope('Session expired.', 'UNAUTHORIZED', 30)));
      final e = await Api.instance
          .requestNewsletter()
          .then<Object?>((_) => null, onError: (Object x) => x);
      expect(e, isA<UnauthorizedException>());
      expect((e as ApiException).retryAfterS, isNull);
      expect(Cooldowns.instance.left(WaitKey.letterSend()), 0);
    });
  });

  group('each of the nine builders arms the wait its server scopes', () {
    // (call, the key it must arm, a sibling key it must NOT arm)
    final cases = <String, (Future<Object?> Function(), String, String?)>{
      'fn_retry_document': (
        () => Api.instance.retryDocument('d1'),
        WaitKey.documentRetry('d1'),
        WaitKey.documentRetry('d2'),
      ),
      'fn_retry_document (force)': (
        () => Api.instance.retryDocument('d1', force: true),
        WaitKey.documentRetry('d1'),
        WaitKey.documentRetry('d2'),
      ),
      'fn_regenerate_summary': (
        () => Api.instance.regenerateSummary('d1'),
        WaitKey.summaryRegen('d1'),
        WaitKey.documentRetry('d1'),
      ),
      'fn_retry_import_job': (
        () => Api.instance.retryImportJob('j1'),
        WaitKey.importJobRetry('j1'),
        WaitKey.importJobRetry('j2'),
      ),
      'fn_update_from_source': (
        () => Api.instance.updateFromSource('d1'),
        WaitKey.sourceRefresh('d1'),
        WaitKey.documentRetry('d1'),
      ),
      'fn_request_cloud_sync': (
        () => Api.instance.requestCloudSync('dropbox'),
        WaitKey.cloudSync('dropbox'),
        WaitKey.cloudSync('google_drive'),
      ),
      'fn_scan_organization (a folder)': (
        () => Api.instance.scanOrganization('dropbox', folderId: 'f9'),
        WaitKey.orgScan('dropbox'),
        WaitKey.orgScan('notion'),
      ),
      'fn_request_newsletter': (
        () => Api.instance.requestNewsletter(),
        WaitKey.letterSend(),
        null,
      ),
      'fn_request_study_session': (
        () => Api.instance.requestStudySession('p1'),
        WaitKey.studySession('p1'),
        WaitKey.studySession('p2'),
      ),
      'fn_send_support_message': (
        () => Api.instance.sendSupportMessage(body: 'hi'),
        WaitKey.supportSend(),
        null,
      ),
    };
    for (final MapEntry(key: name, value: (call, key, sibling))
        in cases.entries) {
      test(name, () async {
        // The scan's cooldown is a 409, every other one a 429.
        final scan = name.startsWith('fn_scan');
        ApiService.instance.httpClientAdapter = _Canned((_) => (
              scan ? 409 : 429,
              _envelope('Please wait 61 seconds.',
                  scan ? 'COOLDOWN' : 'RATE_LIMITED', 61)
            ));
        await call().then<Object?>((_) => null, onError: (Object x) => x);
        expect(Cooldowns.instance.left(key), 61);
        expect(Cooldowns.instance.of(key).sentence, 'Please wait 61 seconds.');
        if (sibling != null) expect(Cooldowns.instance.left(sibling), 0);
      });
    }
  });

  group('the registry and the suffix', () {
    test('the suffix is m:ss, and nothing at zero', () {
      expect(waitSuffix(0), '');
      expect(waitSuffix(9), ' · 0:09');
      expect(waitSuffix(43), ' · 0:43');
      expect(waitSuffix(61), ' · 1:01');
      expect(waitSuffix(298), ' · 4:58');
    });

    test('arms only from a positive number, rounds up, forgets at zero', () {
      final key = WaitKey.letterSend();
      final c = Cooldowns.instance;
      expect(c.arm(key, const ApiException(429, 'x')), isFalse);
      expect(c.arm(key, const ApiException(429, 'x', retryAfterS: 0)), isFalse);
      expect(
          c.arm(key,
              const ApiException(429, 'Wait.', serverSentence: true, retryAfterS: 60)),
          isTrue);
      expect(c.left(key), 60);
      now = now.add(const Duration(milliseconds: 59001));
      expect(c.left(key), 1, reason: 'the last fraction still reads 0:01');
      expect(c.untilNextSecond(key), const Duration(milliseconds: 999));
      now = now.add(const Duration(milliseconds: 999));
      expect(c.left(key), 0);
      now = now.subtract(const Duration(seconds: 30));
      expect(c.left(key), 0, reason: 'forgotten, not resurrected');
    });

    test('a refusal whose words are ours keeps no sentence', () {
      // `_handle`'s constant for a body with no `error` is not the server's
      // sentence, and it must not stand in the slot for the wait (C11).
      final key = WaitKey.supportSend();
      Cooldowns.instance.arm(
          key, const ApiException(429, 'Something went wrong.', retryAfterS: 9));
      expect(Cooldowns.instance.left(key), 9);
      expect(Cooldowns.instance.of(key).sentence, isNull);
    });
  });

  group('the kit controls disable themselves while waiting', () {
    // The page guards (`if (waiting) return`) are a second layer; the control
    // must refuse on its own, or a site that forgets the guard sends anyway.
    testWidgets('KitButton', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_app(Column(children: [
        KitButton('Send now', wait: 5, onPressed: () => taps++),
        KitButton('Idle', onPressed: () => taps += 10),
      ])));
      await tester.tap(_button('Send now · 0:05'));
      await tester.pump();
      expect(taps, 0, reason: 'a waiting button is disabled whatever onPressed says');
      await tester.tap(_button('Idle'));
      expect(taps, 10);
      // At zero there is no suffix span at all — a plain label.
      final idle = tester.widget<Text>(
          find.descendant(of: _button('Idle'), matching: find.byType(Text)));
      expect(idle.data, 'Idle');
      expect(idle.textSpan, isNull);
    });

    testWidgets('KitSettingLink', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_app(KitSettingLink('Update from source',
          icon: null, wait: 61, onTap: () => taps++)));
      await tester.tap(find.text('Update from source · 1:01'));
      await tester.pump();
      expect(taps, 0);
    });

    testWidgets('the composer dock\'s send', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: KitComposerDock(
            controller: TextEditingController(text: 'x'),
            placeholder: 'p',
            waitLeft: 9,
            onSend: () => taps++,
          ),
        ),
      ));
      await tester.tap(find.bySemanticsLabel('Send · 0:09'));
      await tester.pump();
      expect(taps, 0);
    });
  });

  group('reader · regenerate summary waits', () {
    const sentence = 'Please wait 43 seconds before regenerating again.';
    Widget summary() => _app(SummaryPanel(
          doc: Document(
            id: 'd1',
            userId: 'u1',
            title: 'A stored volume',
            type: 'pdf',
            status: DocumentStatus.complete,
            createdAt: 1757000000000,
            summary: 'A stored summary.',
          ),
          onRegenerated: (_) {},
        ));

    testWidgets('nothing moves before the refusal arrives', (tester) async {
      final held = _Held();
      ApiService.instance.httpClientAdapter = held;
      await tester.pumpWidget(summary());
      await tester.tap(_button('Regenerate summary'));
      await tester.pump();
      expect(find.text('Regenerating…'), findsOneWidget);
      expect(find.textContaining('0:4'), findsNothing,
          reason: 'in flight is the busy label, never a countdown');
      expect(Cooldowns.instance.left(WaitKey.summaryRegen('d1')), 0);

      held.answer(429, _envelope(sentence, 'RATE_LIMITED', 43));
      await tester.pumpAndSettle();
      expect(_button('Regenerate summary · 0:43'), findsOneWidget);
    });

    testWidgets(
        'holds the button for the wait, says it, and shows the server\'s '
        'sentence as calm copy', (tester) async {
      final api = _Canned((_) => (429, _envelope(sentence, 'RATE_LIMITED', 43)));
      ApiService.instance.httpClientAdapter = api;
      await tester.pumpWidget(summary());
      await tester.tap(_button('Regenerate summary'));
      await tester.pumpAndSettle();

      final b = _button('Regenerate summary · 0:43');
      expect(b, findsOneWidget);
      expect(tester.widget<KitButton>(b).wait, 43);
      expect(find.text(sentence), findsOneWidget);
      expect(find.byType(KitFailureInline), findsNothing,
          reason: 'a wait is not a failure');
      // The kit's one calm caption, not the description's serif lede (§6.1,
      // 4.108.0).
      expect(
          find.ancestor(
              of: find.text(sentence), matching: find.byType(KitWaitNote)),
          findsOneWidget);

      await tester.tap(b);
      await tester.pump();
      expect(api.sent, hasLength(1), reason: 'a waiting control sends nothing');

      await step(tester, const Duration(seconds: 1));
      expect(_button('Regenerate summary · 0:42'), findsOneWidget,
          reason: 'it counts');
    });

    testWidgets('gives the control back at zero and takes the sentence with it',
        (tester) async {
      ApiService.instance.httpClientAdapter = _Canned((_) => (
            429,
            _envelope('Please wait 2 seconds before regenerating again.',
                'RATE_LIMITED', 2)
          ));
      await tester.pumpWidget(summary());
      await tester.tap(_button('Regenerate summary'));
      await tester.pumpAndSettle();
      expect(_button('Regenerate summary · 0:02'), findsOneWidget);

      await step(tester, const Duration(seconds: 1));
      expect(_button('Regenerate summary · 0:01'), findsOneWidget);
      await step(tester, const Duration(seconds: 1));
      final b = _button('Regenerate summary');
      expect(b, findsOneWidget);
      expect(tester.widget<KitButton>(b).wait, 0);
      expect(find.textContaining('Please wait 2 seconds'), findsNothing);
      expect(find.textContaining('Rewrites the summary'), findsOneWidget,
          reason: 'the caption is its own again');
    });

    testWidgets('a 429 with no number is drawn as before', (tester) async {
      ApiService.instance.httpClientAdapter =
          _Canned((_) => (429, _envelope(sentence, 'RATE_LIMITED')));
      await tester.pumpWidget(summary());
      await tester.tap(_button('Regenerate summary'));
      await tester.pumpAndSettle();
      expect(find.text(sentence), findsOneWidget);
      final b = _button('Regenerate summary');
      expect(b, findsOneWidget, reason: 'no countdown invented from the sentence');
      expect(tester.widget<KitButton>(b).wait, 0);
    });

    testWidgets('a remount keeps the wait', (tester) async {
      ApiService.instance.httpClientAdapter =
          _Canned((_) => (429, _envelope(sentence, 'RATE_LIMITED', 43)));
      await tester.pumpWidget(summary());
      await tester.tap(_button('Regenerate summary'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await step(tester, const Duration(seconds: 3));
      await tester.pumpWidget(summary());
      expect(_button('Regenerate summary · 0:40'), findsOneWidget);
      expect(find.text(sentence), findsOneWidget);
    });
  });

  group('study · Study now waits per program', () {
    testWidgets('holds the refused program\'s control, and only that one',
        (tester) async {
      FirestoreService.instance = _StudyStub([
        for (final id in ['p1', 'p2'])
          StudyProgram.fromJson(id, {
            'title': 'Program $id',
            'document_ids': ['d1'],
            'enabled': true,
            'status': 'active',
          }),
      ]);
      const sentence =
          'You just started a session — give it a minute before requesting '
          'another.';
      ApiService.instance.httpClientAdapter =
          _Canned((_) => (429, _envelope(sentence, 'RATE_LIMITED', 58)));
      await tester.pumpWidget(_app(StudyPage()));
      await tester.pumpAndSettle();
      await tester.tap(_button('Study now').first);
      await tester.pumpAndSettle();

      expect(_button('Study now · 0:58'), findsOneWidget);
      expect(_button('Study now'), findsOneWidget,
          reason: 'the other program is untouched — the cooldown is per program');
      expect(find.text(sentence), findsOneWidget);
      expect(
          find.ancestor(
              of: find.text(sentence), matching: find.byType(KitWaitNote)),
          findsOneWidget);
      expect(Cooldowns.instance.left(WaitKey.studySession('p1')), 58);
      expect(Cooldowns.instance.left(WaitKey.studySession('p2')), 0);
    });
  });

  group('sources · the organization rescan has its countdown (sources.md, '
      'since 1.2.0)', () {
    testWidgets(
        'a 409 COOLDOWN with its number holds every folder of the provider on '
        'one clock, and says the sentence once', (tester) async {
      FirestoreService.instance = _FoldersStub(const [
        CloudFolder(
            id: 'f1',
            provider: 'notion',
            providerPath: '/Papers',
            name: 'Papers',
            organized: true),
        CloudFolder(
            id: 'f2',
            provider: 'notion',
            providerPath: '/Letters',
            name: 'Letters',
            organized: true),
      ]);
      const sentence = 'Scan requested too recently — try again in a few minutes';
      final api =
          _Canned((_) => (409, _envelope(sentence, 'COOLDOWN', 298)));
      ApiService.instance.httpClientAdapter = api;
      await tester.pumpWidget(ChangeNotifierProvider<OrgNotifier>(
        create: (_) => OrgNotifier(),
        child: _app(const OrganizedFoldersPanel(provider: 'notion')),
      ));
      await tester.pumpAndSettle();
      await tester.tap(_button('Rescan').first);
      await tester.pumpAndSettle();

      expect(api.sent.single.data, {'provider': 'notion', 'folder_id': 'f1'});
      expect(_button('Rescan · 4:58'), findsNWidgets(2),
          reason: 'the cooldown is the PROVIDER\'s, whichever folder asked');
      expect(find.text(sentence), findsOneWidget,
          reason: 'said once, over the folders — not per row, not a toast');
      // A wait, said as calm copy (`.proc-note`) — not §14.2, as Summary and
      // Study say theirs (web 23d21a8). 7b0e5fd drew it red.
      expect(
          find.ancestor(
              of: find.text(sentence), matching: find.byType(KitWaitNote)),
          findsOneWidget);
      expect(find.byType(KitFailureInline), findsNothing);
    });

    testWidgets(
        'a 409 COOLDOWN with NO number is still a wait: the same calm slot, '
        'no toast, and it leaves on the next rescan', (tester) async {
      FirestoreService.instance = _FoldersStub(const [
        CloudFolder(
            id: 'f1',
            provider: 'notion',
            providerPath: '/Papers',
            name: 'Papers',
            organized: true),
      ]);
      const sentence = 'Scan requested too recently — try again in a few minutes';
      var cooldown = true;
      ApiService.instance.httpClientAdapter = _Canned((_) => cooldown
          ? (409, _envelope(sentence, 'COOLDOWN'))
          : (200, {'status': 'queued'}));
      await tester.pumpWidget(ChangeNotifierProvider<OrgNotifier>(
        create: (_) => OrgNotifier(),
        child: _app(const OrganizedFoldersPanel(provider: 'notion')),
      ));
      await tester.pumpAndSettle();
      await tester.tap(_button('Rescan'));
      await tester.pumpAndSettle();

      expect(
          find.ancestor(
              of: find.text(sentence), matching: find.byType(KitWaitNote)),
          findsOneWidget,
          reason: 'a wait with no number is said in the same calm slot');
      expect(find.byType(KitFailureInline), findsNothing);
      expect(find.text(sentence), findsOneWidget,
          reason: 'said once — not also a toast');
      expect(find.byType(SnackBar), findsNothing,
          reason: 'not an error toast: nothing broke');
      expect(_button('Rescan'), findsOneWidget,
          reason: 'no number, so no countdown — the control is not held');

      cooldown = false;
      await tester.tap(_button('Rescan'));
      await tester.pump();
      expect(find.text(sentence), findsNothing,
          reason: 'the sentence leaves when the reader asks again');
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('a refusal that is NOT the cooldown is still a failure',
        (tester) async {
      FirestoreService.instance = _FoldersStub(const [
        CloudFolder(
            id: 'f1',
            provider: 'notion',
            providerPath: '/Papers',
            name: 'Papers',
            organized: true),
      ]);
      const sentence = 'Organization is not enabled for this provider.';
      ApiService.instance.httpClientAdapter =
          _Canned((_) => (400, _envelope(sentence, 'VALIDATION_ERROR')));
      await tester.pumpWidget(ChangeNotifierProvider<OrgNotifier>(
        create: (_) => OrgNotifier(),
        child: _app(const OrganizedFoldersPanel(provider: 'notion')),
      ));
      await tester.pumpAndSettle();
      await tester.tap(_button('Rescan'));
      await tester.pumpAndSettle();

      expect(find.text(sentence), findsOneWidget);
      expect(
          find.ancestor(
              of: find.text(sentence), matching: find.byType(KitWaitNote)),
          findsNothing,
          reason: 'only a wait is calm copy');
      // §14.2 in the panel's slot, as Rescan all says its own (item 11,
      // 2026-10-07) — it was an error toast.
      expect(
          find.ancestor(
              of: find.text(sentence), matching: find.byType(KitFailureInline)),
          findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  });

  group('a confirm whose own request was refused by a cooldown', () {
    testWidgets('holds its confirm, says the wait, and keeps the panel open',
        (tester) async {
      final key = WaitKey.documentRetry('doc-1');
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => KitButton('Open', onPressed: () {
              KitConfirm.show(
                context,
                title: 'Retry?',
                confirmLabel: 'Retry and replace',
                cancelLabel: 'Keep it',
                waitKey: key,
                onConfirm: () async {
                  Cooldowns.instance.arm(
                      key,
                      const ApiException(
                          429, 'Please wait 61 seconds before retrying.',
                          serverSentence: true, retryAfterS: 61));
                  return 'Please wait 61 seconds before retrying.';
                },
              );
            }),
          ),
        ),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(_button('Retry and replace'));
      await tester.pumpAndSettle();

      expect(_button('Retry and replace · 1:01'), findsOneWidget);
      expect(find.text('Please wait 61 seconds before retrying.'), findsOneWidget,
          reason: 'one sentence, the wait\'s — not the refusal\'s copy as well');
      // Calm inside the panel too; §18's red slot is for a real refusal.
      expect(
          find.ancestor(
              of: find.text('Please wait 61 seconds before retrying.'),
              matching: find.byType(KitWaitNote)),
          findsOneWidget);
      expect(find.byType(KitFailureInline), findsNothing);
      expect(find.byType(KitConfirm), findsOneWidget,
          reason: '§18: a refusal never closes the panel');
    });

    testWidgets('and is untouched when nothing is waiting', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: KitConfirm(
          title: 'Retry?',
          confirmLabel: 'Retry and replace',
          cancelLabel: 'Keep it',
          waitKey: WaitKey.documentRetry('doc-1'),
          onConfirm: () async => null,
        ),
      ));
      final b = _button('Retry and replace');
      expect(b, findsOneWidget);
      expect(tester.widget<KitButton>(b).wait, 0);
      expect(find.byType(KitFailureInline), findsNothing);
    });
  });

  group('a failed source row waits on its document\'s retry cooldown', () {
    Document doc(String id, String status) => Document.fromJson(id, {
          'user_id': 'u1',
          'title': 'Paper $id',
          'type': status == 'skipped' ? 'image' : 'pdf',
          'status': status,
          if (status == 'error') 'error_message': 'It failed.',
          if (status == 'skipped') 'skip_reason': 'not_text',
        });

    Future<void> pumpRow(WidgetTester tester, Document d,
        {bool? edited = false}) async {
      await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => ActivityNotifier(),
        child: _app(ProcessingRow(
          doc: d,
          editCheck: (_) async => edited,
          studyCheck: (_) async => false,
        )),
      ));
      await tester.pumpAndSettle();
    }

    // Calm everywhere (4.108.0, ADR-145): the row's one sentence slot draws a
    // cooldown as the calm caption; the hard cap stays §14.2 (below).
    testWidgets(
        'a refusal holds Retry and says the server\'s sentence in the row\'s '
        'slot as the calm caption — and the same document on another surface '
        'waits too',
        (tester) async {
      const sentence = 'Please wait 240 seconds before retrying.';
      ApiService.instance.httpClientAdapter =
          _Canned((_) => (429, _envelope(sentence, 'RATE_LIMITED', 240)));
      await pumpRow(tester, doc('doc-9', 'error'));
      await tester.tap(_button('Retry'));
      await tester.pumpAndSettle();

      expect(_button('Retry · 4:00'), findsOneWidget);
      expect(
          find.ancestor(
              of: find.text(sentence), matching: find.byType(KitWaitNote)),
          findsOneWidget);
      expect(find.byType(KitFailureInline), findsNothing,
          reason: 'a wait is not a failure');

      // For your review draws the same ProcessingRow for the same document:
      // a fresh mount reads the same clock.
      await tester.pumpWidget(const SizedBox.shrink());
      await step(tester, const Duration(seconds: 2));
      await pumpRow(tester, doc('doc-9', 'error'));
      expect(_button('Retry · 3:58'), findsOneWidget);
      expect(find.text(sentence), findsOneWidget);
    });

    // One cooldown, one clock — app-wide (4.108.0, ADR-145; review.md,
    // sources.md): the Library tray's row and For your review's row (the
    // dismissible one) for the SAME document, on screen together, hold the
    // same countdown at the same second. Web's pair is one-clock.test.js.
    testWidgets('the tray row and the review row are one clock, at the same '
        'second', (tester) async {
      const sentence = 'Please wait 240 seconds before retrying.';
      ApiService.instance.httpClientAdapter =
          _Canned((_) => (429, _envelope(sentence, 'RATE_LIMITED', 240)));
      final d = doc('doc-9', 'error');
      await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => ActivityNotifier(),
        child: _app(Column(children: [
          ProcessingRow(
              doc: d,
              editCheck: (_) async => false,
              studyCheck: (_) async => false),
          ProcessingRow(
              doc: d,
              dismissible: true,
              editCheck: (_) async => false,
              studyCheck: (_) async => false),
        ])),
      ));
      await tester.pumpAndSettle();
      expect(_button('Retry'), findsNWidgets(2));

      await tester.tap(_button('Retry').last); // pressed on review
      await tester.pumpAndSettle();
      expect(_button('Retry · 4:00'), findsNWidgets(2),
          reason: 'both rows hold, at the same second');
      expect(
          find.ancestor(
              of: find.text(sentence), matching: find.byType(KitWaitNote)),
          findsNWidgets(2));

      await step(tester, const Duration(seconds: 90));
      expect(_button('Retry · 2:30'), findsNWidgets(2));
      await step(tester, const Duration(seconds: 150));
      await tester.pumpAndSettle();
      expect(_button('Retry'), findsNWidgets(2));
      expect(find.text(sentence), findsNothing);
    });

    testWidgets('a forced retry is a retry: Index it anyway waits on it too',
        (tester) async {
      ApiService.instance.httpClientAdapter = _Canned((_) => (
            429,
            _envelope('Please wait 120 seconds before retrying.',
                'RATE_LIMITED', 120)
          ));
      // A request awaited directly runs in the real zone: Dio's own timers
      // never fire under the widget tester's fake clock.
      await tester.runAsync(() => Api.instance
          .retryDocument('doc-3')
          .then<Object?>((_) => null, onError: (Object x) => x));
      await pumpRow(tester, doc('doc-3', 'skipped'));
      expect(_button('Index it anyway · 2:00'), findsOneWidget);
    });

    testWidgets('a row whose document is not waiting is untouched',
        (tester) async {
      Cooldowns.instance.arm(WaitKey.documentRetry('doc-other'),
          const ApiException(429, 'x', retryAfterS: 99));
      await pumpRow(tester, doc('doc-9', 'error'));
      final b = _button('Retry');
      expect(b, findsOneWidget);
      expect(tester.widget<KitButton>(b).wait, 0);
      expect(find.byType(KitFailureInline), findsNothing);
    });

    testWidgets('inside the supersession confirm the confirm itself waits',
        (tester) async {
      const sentence = 'Please wait 299 seconds before retrying.';
      ApiService.instance.httpClientAdapter =
          _Canned((_) => (429, _envelope(sentence, 'RATE_LIMITED', 299)));
      await pumpRow(tester, doc('doc-9', 'error'), edited: true);
      await tester.tap(_button('Retry'));
      await tester.pumpAndSettle();
      await tester.tap(_button('Retry and replace'));
      await tester.pumpAndSettle();

      expect(_button('Retry and replace · 4:59'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(KitConfirm), matching: find.text(sentence)),
          findsOneWidget,
          reason: 'the panel\'s failure slot carries the wait\'s sentence');
      expect(find.byType(KitConfirm), findsOneWidget);

      // Kept: the row behind it is on the same document's clock, so its own
      // slot says the wait for as long as it runs (web ProcRow).
      await tester.tap(find.text('Keep it as it is'));
      await tester.pumpAndSettle();
      expect(_button('Retry · 4:59'), findsOneWidget);
      expect(find.text(sentence), findsOneWidget);
    });
  });

  group('Send now waits on one clock, on Letters and on Letter settings', () {
    testWidgets('one refusal holds both, with the sentence in each send slot',
        (tester) async {
      const sentence =
          'A letter was requested a moment ago — give it a minute.';
      ApiService.instance.httpClientAdapter =
          _Canned((_) => (429, _envelope(sentence, 'RATE_LIMITED', 58)));
      await tester.runAsync(() => Api.instance
          .requestNewsletter()
          .then<Object?>((_) => null, onError: (Object x) => x));

      await tester.pumpWidget(ChangeNotifierProvider<SettingsNotifier>.value(
        value: _Settings(),
        child: _app(Column(children: [
          LatestLetterCard(
            latest: null,
            loaded: true,
            archiveError: null,
            sending: false,
            onSend: () async {},
            onPreview: null,
            onSettings: () {},
            sendMessage: null,
            sendError: null,
            scheduleOutcome: null,
            scheduleError: null,
            scheduleBusy: false,
            onToggleSchedule: (_) async {},
          ),
          LetterPreviewPane(
            letter: null,
            loaded: true,
            error: null,
            sending: false,
            onSend: () {},
          ),
        ])),
      ));
      await tester.pump();

      expect(_button('Send now · 0:58'), findsNWidgets(2));
      expect(find.text(sentence), findsNWidgets(2));
      // Calm on both screens, never §14.2 (letters.md, 4.108.0, ADR-145).
      expect(
          find.ancestor(
              of: find.text(sentence), matching: find.byType(KitWaitNote)),
          findsNWidgets(2));
      expect(find.byType(KitFailureInline), findsNothing);
      await step(tester, const Duration(seconds: 58));
      expect(_button('Send now'), findsNWidgets(2));
      expect(find.text(sentence), findsNothing);
    });
  });

  group('support keeps the draft and holds send for the wait', () {
    testWidgets('send is held, its title says the time, the sentence shows',
        (tester) async {
      const sentence =
          'You just sent that — give it a moment before sending again.';
      final api = _Canned((_) => (429, _envelope(sentence, 'RATE_LIMITED', 9)));
      ApiService.instance.httpClientAdapter = api;
      final support = SupportNotifier();
      await tester.pumpWidget(ChangeNotifierProvider<SupportNotifier>.value(
        value: support,
        child: const MaterialApp(home: Scaffold(body: SupportPage())),
      ));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'The rescan does nothing.');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Send'));
      await tester.pumpAndSettle();

      expect(api.sent, hasLength(1));
      expect(support.error, isNull,
          reason: 'the wait owns the sentence; a copy would outlive it');
      expect(find.text(sentence), findsOneWidget);
      // The dock's calm caption, not its red error line (support.md, 4.108.0).
      expect(
          find.ancestor(
              of: find.text(sentence), matching: find.byType(KitWaitNote)),
          findsOneWidget);
      expect(find.byType(KitFailureInline), findsNothing);
      expect(find.bySemanticsLabel('Send · 0:09'), findsOneWidget);
      expect(tester.widget<KitComposerDock>(find.byType(KitComposerDock)).waitLeft,
          9);
      expect(find.text('The rescan does nothing.'), findsOneWidget,
          reason: 'write before you move: the draft stays');

      await tester.tap(find.bySemanticsLabel('Send · 0:09'));
      await tester.pump();
      expect(api.sent, hasLength(1), reason: 'a waiting send sends nothing');

      await step(tester, const Duration(seconds: 9));
      expect(find.bySemanticsLabel('Send'), findsOneWidget);
      expect(find.text(sentence), findsNothing);
      support.dispose();
    });
  });

  group('sources · Sync now and the import job row', () {
    testWidgets('Sync now waits on the provider\'s clock, as calm copy',
        (tester) async {
      const sentence = 'Sync was requested moments ago — try again shortly.';
      ApiService.instance.httpClientAdapter =
          _Canned((_) => (429, _envelope(sentence, 'RATE_LIMITED', 280)));
      await pumpSources(tester, SourcesStubService(),
          cloud: _ConnectedCloud(const CloudIntegration(
              provider: 'google_drive', tokenValid: true, folderIds: ['f1'])));
      await tester.ensureVisible(_button('Sync now'));
      await tester.tap(_button('Sync now'));
      await tester.pumpAndSettle();

      expect(_button('Sync now · 4:40'), findsOneWidget);
      expect(find.text(sentence), findsOneWidget);
      expect(
          find.ancestor(
              of: find.text(sentence), matching: find.byType(KitFailureInline)),
          findsNothing,
          reason: 'a wait is not a failure');
      expect(
          find.ancestor(
              of: find.text(sentence), matching: find.byType(KitWaitNote)),
          findsOneWidget);
    });

    testWidgets('a job\'s Retry waits on the JOB\'s clock', (tester) async {
      const sentence = 'Please wait 200 seconds before retrying.';
      ApiService.instance.httpClientAdapter =
          _Canned((_) => (429, _envelope(sentence, 'RATE_LIMITED', 200)));
      final jobs = [
        ImportJob(
            id: 'j-1',
            provider: 'google_drive',
            status: 'error',
            errorMessage: 'The download failed.',
            providerFileName: 'Notes.pdf',
            mimeType: 'application/pdf',
            createdAt: DateTime(2026, 9, 20).millisecondsSinceEpoch),
      ];
      await pumpSources(tester, SourcesStubService(jobs: Stream.value(jobs)),
          cloud: _ConnectedCloud(const CloudIntegration(
              provider: 'google_drive', tokenValid: true)));
      await tester.pumpAndSettle();
      final retry = _button('Retry');
      if (retry.evaluate().isEmpty) {
        await tester.ensureVisible(find.text('Show 1'));
        await tester.tap(find.text('Show 1'));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(_button('Retry'));
      await tester.tap(_button('Retry'));
      await tester.pumpAndSettle();

      expect(_button('Retry · 3:20'), findsOneWidget);
      // Calm, where it was §14.2 until 4.108.0 (sources.md §Trust & feedback).
      expect(
          find.ancestor(
              of: find.text(sentence), matching: find.byType(KitWaitNote)),
          findsOneWidget);
      expect(find.byType(KitFailureInline), findsNothing);
      expect(Cooldowns.instance.left(WaitKey.importJobRetry('j-1')), 200);
    });
  });
}
