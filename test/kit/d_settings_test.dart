// F-144 sub-lane B — Settings, Notifications and the wizard's generative-AI
// choice in direction D (settings.md / notifications.md §Composition
// (direction D); F-133: settings.md §Generative AI section §Video reading,
// onboarding.md §Endpoints used §Rules §States; api/ai.md).
//
// What each group proves:
//   · the switch — no switch until the first snapshot; a failed read is ONE
//     §14.1 block; write before you move (held while out, moves only on the
//     subscription, a refusal is §14.2 and the switch stays); the caption
//     only while off; Summaries and Your librarian absent while off, and
//     Contents follows (numbering included).
//   · Video reading — the STORED choice, a press on it sends nothing, held
//     while out, no control (and no failure of its own) while unread/failed.
//   · Notifications — the folio's and the figures' dash while unread or
//     refused, the Type as a draft Switch.
//   · the wizard — the fourth PUT made once per run, its failure line, and a
//     replay that starts from the stored value.
//   · a 402 phone render of Settings and Notifications, both themes, no
//     overflow.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/models/notification_channel.dart';
import 'package:flutter_app/pages/notification_settings_page.dart';
import 'package:flutter_app/pages/onboarding/steps.dart';
import 'package:flutter_app/pages/onboarding/wizard.dart';
import 'package:flutter_app/pages/settings_page.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/shared/local_flags.dart';
import 'package:flutter_app/state/ai_settings_notifier.dart';
import 'package:flutter_app/state/auth_notifier.dart';
import 'package:flutter_app/state/scripture_letter_notifier.dart';
import 'package:flutter_app/state/settings_notifier.dart';
import 'package:flutter_app/state/theme_notifier.dart';
import 'package:flutter_app/state/upload_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

// ── Doubles ─────────────────────────────────────────────────────────────────

/// `AuthNotifier` reaches FirebaseAuth in its constructor, so the page reads
/// this instead: no user, and a sign-out that does nothing.
class _Auth extends ChangeNotifier implements AuthNotifier {
  @override
  User? get user => null;
  @override
  Future<void> signOut() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Store extends FirestoreService {
  _Store({Stream<List<NotificationChannel>>? channels})
    : _channels = channels,
      super.stub();
  final Stream<List<NotificationChannel>>? _channels;

  @override
  Stream<String?> subscribeSummarySettings() => Stream.value(null);

  @override
  Stream<List<NotificationChannel>> subscribeNotificationChannels() =>
      _channels ?? const Stream.empty();
}

class _Canned implements HttpClientAdapter {
  _Canned(this.reply);
  (int, Object?) Function(RequestOptions o) reply;
  final List<RequestOptions> sent = [];

  List<RequestOptions> to(String path) => [
    for (final o in sent)
      if (o.path.endsWith(path)) o,
  ];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    sent.add(options);
    final (status, body) = reply(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const _plan = {
  'plan': 'free',
  'documents': 7,
  'max_documents': 100,
  'ingests_this_month': 3,
  'max_ingests_per_month': 60,
  'period_end': '2026-11-01T00:00:00Z',
};

(int, Object?) _ok(RequestOptions o) => o.path.endsWith('/fn_plan_status')
    ? (200, _plan)
    : (200, <String, dynamic>{});

/// The one AI-settings subscription, driven by hand, and every write it
/// asked for. [gate] holds a write open until the test completes it; [refuse]
/// answers the next write with the server's sentence.
class _Ai {
  final StreamController<Map<String, dynamic>> ctrl = StreamController();
  final List<Map<String, Object?>> writes = [];
  Completer<Object?>? gate;
  bool holdWrites = false;
  String? refuse;

  late final AiSettingsNotifier notifier = AiSettingsNotifier(
    subscribe: () => ctrl.stream,
    write: ({bool? generativeAI, String? videoAI}) async {
      writes.add({'generativeAI': ?generativeAI, 'videoAI': ?videoAI});
      if (holdWrites) {
        gate = Completer<Object?>();
        await gate!.future;
      }
      final r = refuse;
      if (r != null) {
        refuse = null;
        throw ApiException(400, r, serverSentence: true);
      }
      return null;
    },
  );

  void emit(Map<String, dynamic> d) => ctrl.add(d);
  void fail() => ctrl.addError(Exception('permission-denied'));
}

// ── Harness ─────────────────────────────────────────────────────────────────

Future<void> _pump(
  WidgetTester tester,
  Widget page, {
  required _Ai ai,
  Size size = const Size(1280, 5200),
  Brightness b = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(create: (_) => ThemeNotifier()),
        ChangeNotifierProvider<AuthNotifier>.value(value: _Auth()),
        ChangeNotifierProvider<AiSettingsNotifier>.value(value: ai.notifier),
      ],
      child: MaterialApp(
        theme: b == Brightness.dark ? AppTheme.dark : AppTheme.light,
        home: Scaffold(body: page),
      ),
    ),
  );
  await _settle(tester);
}

/// Bounded: the skeleton lines and the switches animate.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _inContents(Key key, String label) =>
    find.descendant(of: find.byKey(key), matching: find.text(label));

KitSwitch _aiSwitch(WidgetTester tester) =>
    tester.widget<KitSwitch>(find.byKey(SettingsPage.aiSwitchKey));

KitSlideSwitch<VideoAI> _video(WidgetTester tester) =>
    tester.widget<KitSlideSwitch<VideoAI>>(find.byKey(SettingsPage.videoKey));

void main() {
  late _Canned http;

  setUp(() {
    KitPageTools.instance.reset();
    SharedPreferences.setMockInitialValues({});
    LocalFlags.resetForTest();
    FirestoreService.instance = _Store();
    ApiService.instance.tokenProvider = () async => 'test-token';
    http = _Canned(_ok);
    ApiService.instance.httpClientAdapter = http;
  });
  tearDown(() {
    ApiService.instance.resetTestSeams();
    FirestoreService.resetInstance();
  });

  // ── Settings: the generative-AI switch (F-133) ─────────────────────────────
  group('Settings — Generative AI (settings.md §Generative AI section)', () {
    testWidgets('unread: the row, no switch, no Video reading control, and '
        'nothing the switch hides', (tester) async {
      final ai = _Ai();
      await _pump(tester, const SettingsPage(), ai: ai);
      expect(find.text(SettingsPage.aiDescription), findsOneWidget);
      expect(
        find.byKey(SettingsPage.aiSwitchKey),
        findsNothing,
        reason: 'INV-24: no switch at a guessed position',
      );
      expect(find.byKey(SettingsPage.videoKey), findsNothing);
      expect(
        find.text('Video reading'),
        findsOneWidget,
        reason: 'the row is drawn; only its control waits',
      );
      // Loading draws no generated surface (INV-34).
      expect(find.text('Summary style'), findsNothing);
      expect(find.text('Your librarian'), findsNothing);
      expect(_inContents(SettingsPage.contentsKey, 'Summaries'), findsNothing);
      expect(
        _inContents(SettingsPage.contentsKey, 'Generative AI'),
        findsOneWidget,
      );
    });

    testWidgets('failed: ONE §14.1 block in the switch row, no switch, and '
        'Video reading adds no failure of its own', (tester) async {
      final ai = _Ai();
      await _pump(tester, const SettingsPage(), ai: ai);
      ai.fail();
      await _settle(tester);
      expect(
        find.text('Your generative-AI setting could not be read.'),
        findsOneWidget,
      );
      expect(
        find.byType(KitFailureBlock),
        findsOneWidget,
        reason: 'one subscription, one failure, said once',
      );
      expect(find.byKey(SettingsPage.aiSwitchKey), findsNothing);
      expect(find.byKey(SettingsPage.videoKey), findsNothing);
      expect(find.text('Summary style'), findsNothing);
    });

    testWidgets('on: the switch on, no caption; Summaries and Your librarian '
        'drawn, and listed', (tester) async {
      final ai = _Ai();
      await _pump(tester, const SettingsPage(), ai: ai);
      ai.emit({});
      await _settle(tester);
      expect(_aiSwitch(tester).value, isTrue, reason: 'absent is on');
      expect(find.text(SettingsPage.aiOffCaption), findsNothing);
      expect(find.text('Summary style'), findsOneWidget);
      expect(find.text('Your librarian'), findsOneWidget);
      expect(
        _inContents(SettingsPage.contentsKey, 'Summaries'),
        findsOneWidget,
      );
      // The order drawn: Generative AI is IV, Summaries V, Scripture VI.
      expect(find.bySemanticsLabel('IV Generative AI'), findsOneWidget);
      expect(find.bySemanticsLabel('V Summaries'), findsOneWidget);
      expect(find.bySemanticsLabel('VI Scripture'), findsOneWidget);
    });

    testWidgets('off: the caption, verbatim; Summaries and Your librarian '
        'absent, and Contents renumbers', (tester) async {
      final ai = _Ai();
      await _pump(tester, const SettingsPage(), ai: ai);
      ai.emit({'generativeAI': false});
      await _settle(tester);
      expect(_aiSwitch(tester).value, isFalse);
      expect(find.text(SettingsPage.aiOffCaption), findsOneWidget);
      expect(find.text('Summary style'), findsNothing);
      expect(find.text('Your librarian'), findsNothing);
      expect(_inContents(SettingsPage.contentsKey, 'Summaries'), findsNothing);
      expect(find.bySemanticsLabel('V Scripture'), findsOneWidget);
      // Video reading is present whether AI is on or off.
      expect(find.byKey(SettingsPage.videoKey), findsOneWidget);
    });

    testWidgets('write before you move: held while out, moved only by the '
        'subscription', (tester) async {
      final ai = _Ai()..holdWrites = true;
      await _pump(tester, const SettingsPage(), ai: ai);
      ai.emit({});
      await _settle(tester);

      await tester.tap(find.byKey(SettingsPage.aiSwitchKey));
      await tester.pump();
      expect(ai.writes, [
        {'generativeAI': false},
      ]);
      expect(_aiSwitch(tester).value, isTrue, reason: 'nothing moved locally');
      expect(_aiSwitch(tester).onChanged, isNull, reason: 'held while out');

      ai.gate!.complete(null);
      await _settle(tester);
      expect(
        _aiSwitch(tester).value,
        isTrue,
        reason: 'the write landed; the STORED value has not come back',
      );
      expect(_aiSwitch(tester).onChanged, isNotNull);

      ai.emit({'generativeAI': false});
      await _settle(tester);
      expect(_aiSwitch(tester).value, isFalse);
      expect(find.text(SettingsPage.aiOffCaption), findsOneWidget);
      expect(find.text('Summary style'), findsNothing);
    });

    testWidgets('a refusal is §14.2 under the row, and the switch stays', (
      tester,
    ) async {
      final ai = _Ai()..refuse = 'Generative AI could not be changed now.';
      await _pump(tester, const SettingsPage(), ai: ai);
      ai.emit({});
      await _settle(tester);
      await tester.tap(find.byKey(SettingsPage.aiSwitchKey));
      await _settle(tester);
      expect(
        find.widgetWithText(
          KitFailureInline,
          'Generative AI could not be changed now.',
        ),
        findsOneWidget,
      );
      expect(_aiSwitch(tester).value, isTrue);
      expect(find.text('Summary style'), findsOneWidget);
    });
  });

  // ── Settings: Video reading (5.33.0) ──────────────────────────────────────
  group('Settings — Video reading (settings.md §Video reading)', () {
    testWidgets('the STORED choice; a press on it sends nothing; the other is '
        'asked for, held while out, and moves on the subscription', (
      tester,
    ) async {
      final ai = _Ai()..holdWrites = true;
      await _pump(tester, const SettingsPage(), ai: ai);
      ai.emit({'videoAI': 'claude'});
      await _settle(tester);
      expect(_video(tester).value, VideoAI.claude);

      Finder opt(String l) => find.descendant(
        of: find.byKey(SettingsPage.videoKey),
        matching: find.text(l),
      );
      await tester.tap(opt('Claude'));
      await tester.pump();
      expect(
        ai.writes,
        isEmpty,
        reason: 'a press on the selected sends nothing',
      );

      await tester.tap(opt('OpenAI'));
      await tester.pump();
      expect(ai.writes, [
        {'videoAI': 'openai'},
      ]);
      expect(_video(tester).held, isTrue);
      expect(_video(tester).value, VideoAI.claude);

      ai.gate!.complete(null);
      await _settle(tester);
      expect(_video(tester).held, isFalse);
      expect(_video(tester).value, VideoAI.claude);
      ai.emit({'videoAI': 'openai'});
      await _settle(tester);
      expect(_video(tester).value, VideoAI.openai);
    });

    testWidgets('anything but a literal "claude" reads OpenAI', (tester) async {
      final ai = _Ai();
      await _pump(tester, const SettingsPage(), ai: ai);
      ai.emit({'videoAI': 'Claude'});
      await _settle(tester);
      expect(_video(tester).value, VideoAI.openai);
    });

    testWidgets('a refusal is §14.2 under the row', (tester) async {
      final ai = _Ai()..refuse = 'Video reading could not be changed.';
      await _pump(tester, const SettingsPage(), ai: ai);
      ai.emit({});
      await _settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byKey(SettingsPage.videoKey),
          matching: find.text('Claude'),
        ),
      );
      await _settle(tester);
      expect(
        find.widgetWithText(
          KitFailureInline,
          'Video reading could not be changed.',
        ),
        findsOneWidget,
      );
      expect(_video(tester).value, VideoAI.openai);
    });
  });

  // ── Settings: the D composition ───────────────────────────────────────────
  group('Settings — composition (direction D)', () {
    testWidgets('folio, Contents in order, Also; no camera roll', (
      tester,
    ) async {
      final ai = _Ai();
      await _pump(tester, const SettingsPage(), ai: ai);
      ai.emit({});
      await _settle(tester);
      final page = tester.widget<KitDPage>(find.byType(KitDPage));
      expect(page.folio, startsWith('Settings · Account · '));
      expect(page.title, 'Settings');
      expect(page.action, isNull);
      expect(page.settings, isNull);
      const order = [
        'I Setup',
        'II Appearance',
        'III The daily letter',
        'IV Generative AI',
        'V Summaries',
        'VI Scripture',
        'VII Notifications',
        'VIII Account',
      ];
      for (final l in order) {
        expect(find.bySemanticsLabel(l), findsOneWidget, reason: l);
      }
      expect(find.text('Camera roll'), findsNothing);
      expect(find.text('Write to support'), findsOneWidget);
      expect(find.text('Sign out'), findsWidgets);
      expect(find.widgetWithText(KitButton, 'Run setup'), findsOneWidget);
    });
  });

  // ── Notifications ─────────────────────────────────────────────────────────
  group('Notifications (notifications.md §Composition (direction D))', () {
    NotificationChannel ch(String id, String type, bool on) =>
        NotificationChannel.fromJson(id, {
          'user_id': 'u1',
          'type': type,
          'levels': ['error'],
          'enabled': on,
          if (type == 'email') 'destination': 'seed@noteletter.test',
        });

    testWidgets(
      'the dash until read; then the count, the figures and the rows',
      (tester) async {
        final channels = StreamController<List<NotificationChannel>>();
        FirestoreService.instance = _Store(channels: channels.stream);
        await _pump(tester, const NotificationSettingsPage(), ai: _Ai());
        KitDPage page() => tester.widget<KitDPage>(find.byType(KitDPage));
        expect(page().folio, 'Settings · Notifications · — channels');
        expect(
          find.byType(KitFigures),
          findsNothing,
          reason: 'figures only once read (INV-24)',
        );
        expect(find.byType(KitSkeletonLines), findsOneWidget);
        expect(find.text('No channels yet'), findsNothing);

        channels.add([
          ch('a', 'push', false),
          ch('b', 'email', true),
          ch('c', 'onscreen', true),
        ]);
        await _settle(tester);
        expect(page().folio, 'Settings · Notifications · 3 channels');
        final figs = tester.widget<KitFigures>(find.byType(KitFigures));
        expect(figs.rows, [('Channels', '3'), ('On', '2'), ('Paused', '1')]);
        expect(find.textContaining('(paused)'), findsOneWidget);
        expect(find.text('seed@noteletter.test'), findsOneWidget);
        expect(find.text('What has been sent to you'), findsOneWidget);
        await channels.close();
      },
    );

    testWidgets('a refused read: the dash, no figures, §14.2 — never "no '
        'channels"', (tester) async {
      final channels = StreamController<List<NotificationChannel>>();
      FirestoreService.instance = _Store(channels: channels.stream);
      await _pump(tester, const NotificationSettingsPage(), ai: _Ai());
      channels.addError(Exception('permission-denied'));
      await _settle(tester);
      expect(
        tester.widget<KitDPage>(find.byType(KitDPage)).folio,
        'Settings · Notifications · — channels',
      );
      expect(find.byType(KitFigures), findsNothing);
      expect(
        find.textContaining('Your channels could not be read'),
        findsOneWidget,
      );
      expect(find.text('No channels yet'), findsNothing);
      await channels.close();
    });

    testWidgets('Type is a §34 Switch and a draft: Email asks for the address '
        'and sends nothing', (tester) async {
      FirestoreService.instance = _Store(channels: Stream.value(const []));
      await _pump(tester, const NotificationSettingsPage(), ai: _Ai());
      expect(find.text('No channels yet'), findsOneWidget);
      final type = find.byKey(NotificationSettingsPage.typeKey);
      expect(tester.widget<KitWrapSwitch<String>>(type).value, 'onscreen');
      expect(find.text('SEND TO'), findsNothing);
      await tester.tap(find.descendant(of: type, matching: find.text('Email')));
      await tester.pump();
      expect(tester.widget<KitWrapSwitch<String>>(type).value, 'email');
      expect(find.text('SEND TO'), findsOneWidget);
      expect(http.sent, isEmpty, reason: 'a draft until Add channel');
      expect(find.byKey(NotificationSettingsPage.addKey), findsOneWidget);
    });
  });

  // ── The wizard's generative-AI choice ────────────────────────────────────
  group('the wizard (onboarding.md §Rules §States)', () {
    Future<void> pumpWizard(
      WidgetTester tester, {
      required _Ai ai,
      required _Letters letters,
      void Function()? onDone,
    }) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AiSettingsNotifier>.value(
              value: ai.notifier,
            ),
            ChangeNotifierProvider<SettingsNotifier>.value(value: letters),
            ChangeNotifierProvider<ScriptureLetterNotifier>(
              create: (_) => ScriptureLetterNotifier(),
            ),
            ChangeNotifierProvider<UploadNotifier>(
              create: (_) => UploadNotifier(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: OnboardingWizard(
              documents: const [],
              onDone: () async => onDone?.call(),
              onSkip: () async {},
            ),
          ),
        ),
      );
      await _settle(tester);
    }

    Future<void> next(WidgetTester tester, String label) async {
      await tester.tap(find.widgetWithText(KitButton, label));
      await _settle(tester);
    }

    KitObCheck box(WidgetTester tester) =>
        tester.widget<KitObCheck>(find.byKey(LibrarianStep.useAIKey));

    testWidgets('ticked by default; unticked, Finish sends {generativeAI: '
        'false} once — not again on a retry after the letter failed', (
      tester,
    ) async {
      final ai = _Ai();
      final letters = _Letters(['The letter could not be saved.', null]);
      var done = 0;
      await pumpWizard(tester, ai: ai, letters: letters, onDone: () => done++);
      // A fresh account: the stored value is absent, which is on.
      ai.emit({});
      await next(tester, 'Begin');
      await next(tester, 'Continue');
      expect(box(tester).value, isTrue);
      await tester.tap(find.byKey(LibrarianStep.useAIKey));
      await tester.pump();
      expect(box(tester).value, isFalse);
      expect(http.sent, isEmpty, reason: 'nothing is written until Finish');
      await next(tester, 'Continue');
      await next(tester, 'Continue');
      await next(tester, 'Continue');
      // The summary's row, and the way back to the Librarian step.
      expect(find.text('Generative AI'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);

      await next(tester, 'Open your library');
      final puts = http.to('/fn_ai_settings');
      expect(puts, hasLength(1));
      expect(puts.single.method, 'PUT');
      expect(puts.single.data, {'generativeAI': false});
      expect(find.text('The letter could not be saved.'), findsOneWidget);
      expect(done, 0, reason: 'a save failure must not claim success');

      await next(tester, 'Try again');
      expect(
        http.to('/fn_ai_settings'),
        hasLength(1),
        reason: 'made at most once per run',
      );
      expect(letters.calls, 2);
      expect(done, 1, reason: 'the run finished on the retry');
    });

    testWidgets('a refused AI write: its own line and standfirst, the run '
        'kept; a retry sends it again', (tester) async {
      final ai = _Ai();
      http.reply = (o) => o.path.endsWith('/fn_ai_settings')
          ? (
              400,
              {
                'error': 'generativeAI must be a boolean.',
                'error_code': 'BAD_REQUEST',
                'request_id': 'a1b2c3d4',
              },
            )
          : _ok(o);
      await pumpWizard(tester, ai: ai, letters: _Letters([null, null]));
      ai.emit({});
      for (final l in [
        'Begin',
        'Continue',
        'Continue',
        'Continue',
        'Continue',
      ]) {
        await next(tester, l);
      }
      await next(tester, 'Open your library');
      expect(
        find.text(
          'Your AI choice could not be saved: generativeAI must be a boolean.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'your AI choice could not be saved. Try '
          'again, or change it later in Settings.',
        ),
        findsOneWidget,
      );
      http.reply = _ok;
      await next(tester, 'Try again');
      expect(http.to('/fn_ai_settings'), hasLength(2));
      expect(
        find.textContaining('Your AI choice could not be saved'),
        findsNothing,
      );
    });

    testWidgets('a replay starts from the stored value', (tester) async {
      final ai = _Ai();
      await pumpWizard(tester, ai: ai, letters: _Letters([null]));
      ai.emit({'generativeAI': false});
      await next(tester, 'Begin');
      await next(tester, 'Continue');
      expect(box(tester).value, isFalse);
    });
  });

  // ── Phone ─────────────────────────────────────────────────────────────────
  group('a 402 phone, both themes, no overflow', () {
    for (final b in Brightness.values) {
      testWidgets('Settings ($b), AI off: the running head, the stacked '
          'Video reading Switch', (tester) async {
        final ai = _Ai();
        await _pump(
          tester,
          const SettingsPage(),
          ai: ai,
          size: const Size(402, 874),
          b: b,
        );
        ai.emit({'generativeAI': false});
        await _settle(tester);
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('d-peek')),
          findsOneWidget,
          reason: 'the sheet runs as the running head',
        );
        // The whole column, laid out, at the phone's width.
        await tester.scrollUntilVisible(
          find.byKey(SettingsPage.videoKey),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await _settle(tester);
        expect(tester.takeException(), isNull);
        expect(
          tester.getTopRight(find.byKey(SettingsPage.videoKey)).dx,
          lessThanOrEqualTo(402),
        );
      });

      testWidgets('Notifications ($b): rows, levels, the Type Switch', (
        tester,
      ) async {
        FirestoreService.instance = _Store(
          channels: Stream.value([
            NotificationChannel.fromJson('a', {
              'user_id': 'u1',
              'type': 'email',
              'label': 'Work inbox',
              'levels': ['error', 'warning'],
              'enabled': true,
              'destination': 'seed@noteletter.test',
            }),
          ]),
        );
        await _pump(
          tester,
          const NotificationSettingsPage(),
          ai: _Ai(),
          size: const Size(402, 874),
          b: b,
        );
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.byKey(NotificationSettingsPage.addKey),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await _settle(tester);
        expect(tester.takeException(), isNull);
        for (final l in ['Errors', 'Warnings', 'Successes', 'Info']) {
          for (final e in find.text(l).evaluate()) {
            expect(
              tester.getTopRight(find.byWidget(e.widget)).dx,
              lessThanOrEqualTo(402),
              reason: l,
            );
          }
        }
      });
    }
  });
}

/// The letter's save, answered from a script: each entry is one Finish's
/// answer (null is saved).
class _Letters extends SettingsNotifier {
  _Letters(this.answers);
  final List<String?> answers;
  int calls = 0;

  @override
  Future<String?> saveOnboardingLetter({
    required String frequency,
    required String deliveryTime,
    required int itemsPerNewsletter,
    required String timezone,
    String purposeText = '',
  }) async {
    final a = calls < answers.length ? answers[calls] : null;
    calls++;
    return a;
  }
}
