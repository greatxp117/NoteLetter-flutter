import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/models/newsletter.dart';
import 'package:flutter_app/models/newsletter_settings.dart';
import 'package:flutter_app/models/scripture_newsletter_settings.dart';
import 'package:flutter_app/models/support.dart';
import 'package:flutter_app/models/tag.dart';
import 'package:flutter_app/pages/letter_settings_page.dart';
import 'package:flutter_app/pages/letters/letter_host.dart';
import 'package:flutter_app/pages/support_page.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/shared/cooldown.dart';
import 'package:flutter_app/shared/local_flags.dart';
import 'package:flutter_app/state/newsletter_notifier.dart';
import 'package:flutter_app/state/scripture_letter_notifier.dart';
import 'package:flutter_app/state/settings_notifier.dart';
import 'package:flutter_app/state/support_notifier.dart';
import 'package:flutter_app/state/tags_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

import '../contract/sources_harness.dart' show StubTags;

/// Letter settings and Support in direction D (F-144 sub-lane C;
/// `screens/letters.md` §Composition *Letter settings*, `screens/support.md`
/// §Composition, kit §28 §31 §34 §38): the REAL pages over a stubbed
/// Firestore — the folio's forms, the sheet's Contents and figures, the
/// defaults the build uses, the passages stepper, How often as a draft,
/// Support's dashes, the §38 composer growing and keeping a refused draft, and
/// both screens at a 402 phone in both themes.

const _phone = Size(402, 874);
const _wide = Size(1280, 900);

// ── Stubs ────────────────────────────────────────────────────────────────────

class _Fs extends FirestoreService {
  _Fs({
    this.settings,
    this.settingsError,
    this.holdSettings = false,
    this.letter,
    this.letterError,
    this.readings,
    this.readingsError,
    this.holdReadings = false,
  }) : super.stub();

  /// The stored document; null is no document at all.
  final Map<String, dynamic>? settings;
  final Object? settingsError;
  final bool holdSettings;
  final Newsletter? letter;
  final Object? letterError;
  final ScriptureNewsletterSettings? readings;
  final Object? readingsError;
  final bool holdReadings;

  @override
  String? get currentUid => 'u1';

  @override
  Future<NewsletterSettings> getNewsletterSettings() async {
    if (holdSettings) return Completer<NewsletterSettings>().future;
    if (settingsError != null) throw settingsError!;
    final s = settings;
    return s == null
        ? const NewsletterSettings(enabled: false)
        : NewsletterSettings.fromJson(s);
  }

  @override
  Future<Newsletter?> getLatestLetter() async {
    if (letterError != null) throw letterError!;
    return letter;
  }

  @override
  Future<ScriptureNewsletterSettings?> getScriptureNewsletterSettings() async {
    if (holdReadings) return Completer<ScriptureNewsletterSettings?>().future;
    if (readingsError != null) throw readingsError!;
    return readings;
  }
}

/// Records every request and answers it as the test says.
class _Api implements HttpClientAdapter {
  _Api([this.reply]);
  (int, Object)? Function(RequestOptions o)? reply;
  final List<RequestOptions> sent = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    sent.add(options);
    final (status, body) = reply?.call(options) ?? (200, {'ok': true});
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

class _Support extends SupportNotifier {
  _Support({this.list = const [], this.th, this.isLoading = false, this.sub});
  final List<SupportMessage> list;
  final SupportThread? th;
  final bool isLoading;
  final String? sub;

  @override
  List<SupportMessage> get messages => list;
  @override
  SupportThread? get thread => th;
  @override
  bool get loading => isLoading;
  @override
  String? get subError => sub;
  @override
  bool get awaitingAnswer => th?.awaitingAnswer ?? false;
  @override
  int get unreadForUser => 0;
}

// ── Pumps ────────────────────────────────────────────────────────────────────

const _footer = ValueKey('footer');

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 2));
}

Future<void> _pumpAt(
  WidgetTester tester,
  String at,
  Widget page, {
  required List<SingleChildWidget> providers,
  Size size = _wide,
  Brightness b = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  KitPageTools.instance.reset();
  final router = GoRouter(
    initialLocation: at,
    routes: [
      GoRoute(
        path: at,
        builder: (_, _) => KitShellFooter(
          footer: const SizedBox(key: _footer, height: 160),
          child: Scaffold(body: page),
        ),
      ),
    ],
  );
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    MultiProvider(
      providers: providers,
      child: MaterialApp.router(
        theme: b == Brightness.dark ? AppTheme.dark : AppTheme.light,
        routerConfig: router,
      ),
    ),
  );
  await _settle(tester);
}

Future<SettingsNotifier> _letterSettings(
  WidgetTester tester,
  _Fs fs, {
  Size size = _wide,
  Brightness b = Brightness.light,
  List<Tag> shelves = const [],
  String account = 'reader@example.com',
}) async {
  FirestoreService.instance = fs;
  addTearDown(FirestoreService.resetInstance);
  final settings = SettingsNotifier();
  await _pumpAt(
    tester,
    '/letters/settings',
    LetterSettingsPage(accountEmail: () => account),
    size: size,
    b: b,
    providers: [
      ChangeNotifierProvider<SettingsNotifier>.value(value: settings),
      ChangeNotifierProvider<ScriptureLetterNotifier>(
        create: (_) => ScriptureLetterNotifier(),
      ),
      ChangeNotifierProvider<TagsNotifier>(create: (_) => StubTags(shelves)),
      ChangeNotifierProvider<NewsletterNotifier>(
        create: (_) => NewsletterNotifier(),
      ),
    ],
  );
  return settings;
}

Future<void> _support(
  WidgetTester tester,
  SupportNotifier support, {
  Size size = _wide,
  Brightness b = Brightness.light,
}) => _pumpAt(
  tester,
  '/support',
  const SupportPage(),
  size: size,
  b: b,
  providers: [ChangeNotifierProvider<SupportNotifier>.value(value: support)],
);

// ── Readers ──────────────────────────────────────────────────────────────────

/// Every string drawn, rich text included, no-break spaces read as spaces.
List<String> _drawn(WidgetTester tester) => [
  // Every Text draws through a RichText, so the RichTexts are each string
  // once.
  for (final w in tester.widgetList<RichText>(find.byType(RichText)))
    w.text.toPlainText().replaceAll('\u00a0', ' '),
];

/// The folio: the one drawn string that starts with [lead].
String _folio(WidgetTester tester, String lead) =>
    _drawn(tester).firstWhere((s) => s.startsWith(lead), orElse: () => '');

List<String> _contents(WidgetTester tester) => [
  for (final t in tester.widgetList<Text>(
    find.descendant(
      of: find.byKey(const ValueKey('lset-contents')),
      matching: find.byType(Text),
    ),
  ))
    t.data ?? '',
].where((s) => !RegExp(r'^[IVX]+$').hasMatch(s)).toList();

/// A figure's value: the drawn string right after its (caps) term.
String _figure(WidgetTester tester, String term) {
  final all = _drawn(tester);
  final i = all.indexOf(term.toUpperCase());
  return i < 0 || i + 1 >= all.length ? '' : all[i + 1];
}

Newsletter _built() => Newsletter.fromJson('n1', {
  'user_id': 'u1',
  'status': 'sent',
  'subject': 'On quiet rooms',
  'html_body': '<p>A passage about quiet rooms.</p>',
  'chunk_ids': ['c1', 'c2', 'c3'],
  'generated_at': DateTime(2026, 9, 10, 7).millisecondsSinceEpoch,
});

Finder _stepperGlyph(String key, String glyph) =>
    find.descendant(of: find.byKey(ValueKey(key)), matching: find.text(glyph));

int _stepper(WidgetTester tester, String key) =>
    tester.widget<KitStepper>(find.byKey(ValueKey(key))).value;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalFlags.resetForTest();
    ApiService.instance.tokenProvider = () async => 'test-token';
  });
  tearDown(() {
    ApiService.instance.resetTestSeams();
    Cooldowns.instance.resetForTest();
  });

  group('the build\'s defaults', () {
    test('a key the stored document does not carry reads as the build uses '
        'it', () {
      final s = NewsletterSettings.fromJson(const {});
      expect(s.frequency, 'daily');
      expect(s.deliveryTime, '07:00');
      expect(s.itemsPerNewsletter, 5);
      expect(s.excludeRecentDays, 7);
      expect(
        s.timezone,
        isEmpty,
        reason: 'no zone stored is no zone — the page offers the device\'s',
      );
      expect(s.enabled, isFalse);
      const blank = NewsletterSettings();
      expect(blank.timezone, isEmpty);
      expect(
        blank.toJson().containsKey('timezone'),
        isFalse,
        reason: 'an empty zone is never sent',
      );
    });

    test('empty reads as absent, as web\'s `||`; a rest of 0 is a value', () {
      final s = NewsletterSettings.fromJson(const {
        'frequency': '',
        'deliveryTime': '',
        'itemsPerNewsletter': 0,
        'excludeRecentDays': 0,
      });
      expect(s.frequency, 'daily');
      expect(s.deliveryTime, '07:00');
      expect(s.itemsPerNewsletter, 5);
      expect(s.excludeRecentDays, 0);
      expect(
        NewsletterSettings.fromJson(const {
          'itemsPerNewsletter': 12.0,
        }).itemsPerNewsletter,
        12,
      );
    });

    for (final doc in [null, <String, dynamic>{}]) {
      testWidgets('${doc == null ? 'no document' : 'an empty document'} '
          'draws Daily · 7:00 AM · 5 · 7', (tester) async {
        await _letterSettings(tester, _Fs(settings: doc));
        expect(
          tester
              .widget<KitSlideSwitch<String>>(
                find.byKey(const ValueKey('lset-frequency')),
              )
              .value,
          'daily',
        );
        expect(
          tester
              .widget<TextField>(
                find.descendant(
                  of: find.byKey(const ValueKey('lset-time')),
                  matching: find.byType(TextField),
                ),
              )
              .controller
              ?.text,
          '07:00',
        );
        expect(_stepper(tester, 'lset-passages'), 5);
        expect(_stepper(tester, 'lset-rest'), 7);
        await _unmount(tester);
      });
    }

    testWidgets('Save sends what the fields show — the build\'s values for '
        'what was never stored', (tester) async {
      final api = _Api();
      ApiService.instance.httpClientAdapter = api;
      await _letterSettings(tester, _Fs(settings: const {}));
      await tester.ensureVisible(find.byKey(const ValueKey('lset-save')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('lset-save')));
      await _settle(tester);
      final put = api.sent.single;
      expect(put.path, endsWith('/fn_newsletter_settings'));
      final body = put.data as Map;
      expect(body['frequency'], 'daily');
      expect(body['deliveryTime'], '07:00');
      expect(body['itemsPerNewsletter'], 5);
      expect(body['excludeRecentDays'], 7);
      expect((body['timezone'] as String), isNotEmpty);
      expect(
        body.containsKey('enabled'),
        isFalse,
        reason: 'the switch owns `enabled`',
      );
      expect(find.text('Saved'), findsOneWidget);
      await _unmount(tester);
    });
  });

  group('Letter settings: the folio', () {
    testWidgets('before the read answers: no schedule part', (tester) async {
      await _letterSettings(tester, _Fs(holdSettings: true));
      expect(_folio(tester, 'LETTERS · SETTINGS'), 'LETTERS · SETTINGS');
      expect(
        tester
            .widget<KitButton>(find.byKey(const ValueKey('lset-save')))
            .onPressed,
        isNull,
        reason: 'nothing read, nothing to save',
      );
      await _unmount(tester);
    });

    // Web 22f9461 (QA FOUND 2): before the read answers the page drew the
    // BUILD's defaults — Daily, 7:00 AM, 5 passages, the switch off — as if
    // they were this reader's letter. Delivery and Composition stand over the
    // kit skeleton instead, and Save is held, until the read answers.
    testWidgets('before the read answers: the skeleton, never the build\'s '
        'defaults', (tester) async {
      await _letterSettings(tester, _Fs(holdSettings: true));
      expect(
        find.byKey(const ValueKey('lset-loading')),
        findsOneWidget,
        reason: 'Delivery does not stand over the skeleton while unread',
      );
      expect(
        find.byType(KitSkeletonLines),
        findsNWidgets(2),
        reason: 'Delivery and Composition each stand over the skeleton',
      );
      for (final unmeasured in ['Daily', 'Weekdays', '7:00 AM', '07:00', '5']) {
        expect(
          find.text(unmeasured),
          findsNothing,
          reason: '"$unmeasured" is a default nobody read',
        );
      }
      expect(
        find.byType(KitSwitch),
        findsNothing,
        reason: 'no delivery switch at a guessed position',
      );
      expect(find.byType(KitStepper), findsNothing);
      expect(find.byKey(const ValueKey('lset-frequency')), findsNothing);
      expect(
        tester
            .widget<KitButton>(find.byKey(const ValueKey('lset-save')))
            .onPressed,
        isNull,
        reason: 'Save is held until the read answers',
      );
      await _unmount(tester);
    });

    testWidgets('on: {How often} at {h:mm AM}', (tester) async {
      await _letterSettings(
        tester,
        _Fs(
          settings: const {
            'enabled': true,
            'frequency': 'weekdays',
            'deliveryTime': '08:00',
            'timezone': 'America/Chicago',
          },
        ),
      );
      expect(
        _folio(tester, 'LETTERS · SETTINGS'),
        'LETTERS · SETTINGS · WEEKDAYS AT 8:00 AM',
      );
      expect(find.text('Letter Settings'), findsOneWidget);
      expect(
        find.text(
          'A letter is from someone, to someone. Tune how yours '
          'arrives.',
        ),
        findsOneWidget,
      );
      await _unmount(tester);
    });

    testWidgets('off: Delivery off', (tester) async {
      await _letterSettings(tester, _Fs(settings: const {'enabled': false}));
      expect(
        _folio(tester, 'LETTERS · SETTINGS'),
        'LETTERS · SETTINGS · DELIVERY OFF',
      );
      await _unmount(tester);
    });

    testWidgets('a refused read: no schedule part, §14.1 alone, no '
        'Composition', (tester) async {
      await _letterSettings(tester, _Fs(settingsError: Exception('offline')));
      expect(_folio(tester, 'LETTERS · SETTINGS'), 'LETTERS · SETTINGS');
      expect(
        find.text(
          'Your letter settings could not be read, so there is '
          'nothing here to change yet.',
        ),
        findsOneWidget,
      );
      expect(find.byType(KitFailureBlock), findsOneWidget);
      expect(find.byKey(const ValueKey('lset-schedule')), findsNothing);
      expect(find.byKey(const ValueKey('lset-passages')), findsNothing);
      expect(find.byKey(const ValueKey('lset-save')), findsNothing);
      expect(_contents(tester), isNot(contains('Composition')));
      await _unmount(tester);
    });
  });

  group('Letter settings: the sheet', () {
    testWidgets('Contents names the sections the page draws, in order; the '
        'latest letter\'s figures', (tester) async {
      await _letterSettings(
        tester,
        _Fs(
          settings: const {'enabled': true},
          letter: _built(),
          readings: const ScriptureNewsletterSettings(),
        ),
      );
      expect(_contents(tester), [
        'Delivery',
        'Composition',
        'The readings letter',
        'The latest letter',
      ]);
      expect(
        tester.widget<KitDPage>(find.byType(KitDPage)).sheet?.label,
        'Letter settings',
      );
      expect(_figure(tester, 'Built'), 'Thursday, September 10');
      expect(_figure(tester, 'Passages'), '3');
      // A frame-less letter through the reader's own host, at the column's
      // width (web `.dp-lset .letter-preview-pane>.letter-page{padding:0}`).
      expect(tester.widget<LetterHost>(find.byType(LetterHost)).inset, isFalse);
      expect(
        find.byType(KitLiftedLetter),
        findsNothing,
        reason: 'only a letter with its letterhead is lifted',
      );
      expect(find.text('§ IV'), findsWidgets);
      await _unmount(tester);
    });

    testWidgets('no readings letter until its document answers; None yet '
        'when no letter was built', (tester) async {
      await _letterSettings(
        tester,
        _Fs(settings: const {}, holdReadings: true),
      );
      expect(_contents(tester), [
        'Delivery',
        'Composition',
        'The latest letter',
      ]);
      expect(_figure(tester, 'Built'), 'None yet');
      expect(_figure(tester, 'Passages'), '—');
      expect(find.text('No letter has been built yet.'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('a refused letter read is the dash and §14.2, never None yet', (
      tester,
    ) async {
      await _letterSettings(
        tester,
        _Fs(settings: const {}, letterError: Exception('offline')),
      );
      expect(_figure(tester, 'Built'), '—');
      expect(
        find.textContaining('Your latest letter could not be read — '),
        findsOneWidget,
      );
      expect(find.text('No letter has been built yet.'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('a refused readings read before its first answer is §14.2 in '
        'its section, never an off switch', (tester) async {
      await _letterSettings(
        tester,
        _Fs(settings: const {}, readingsError: Exception('denied')),
      );
      expect(_contents(tester), contains('The readings letter'));
      expect(
        find.textContaining(
          'Your readings-letter settings could not be '
          'read — ',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('lset-readings')), findsNothing);
      await _unmount(tester);
    });

    testWidgets('a refused readings-letter field says so beside that field', (
      tester,
    ) async {
      ApiService.instance.httpClientAdapter = _Api(
        (o) => o.path.endsWith('/fn_scripture_newsletter_settings')
            ? (
                400,
                {
                  'error': 'Unknown settings key(s): tempo',
                  'error_code': 'UNKNOWN_KEYS',
                  'request_id': 'r1',
                },
              )
            : null,
      );
      await _letterSettings(
        tester,
        _Fs(
          settings: const {},
          readings: const ScriptureNewsletterSettings(enabled: true),
        ),
      );
      final arrives = find.ancestor(
        of: find.text('Arrives at').last,
        matching: find.byType(KitConfigField),
      );
      final save = find.descendant(
        of: arrives,
        matching: find.widgetWithText(KitButton, 'Save'),
      );
      await tester.ensureVisible(save);
      await tester.pump();
      await tester.tap(save);
      await _settle(tester);
      expect(
        find.descendant(
          of: arrives,
          matching: find.text('Unknown settings key(s): tempo'),
        ),
        findsOneWidget,
      );
      expect(
        find.text('Unknown settings key(s): tempo'),
        findsOneWidget,
        reason: 'once, beside the field — not again at the switch',
      );
      await _unmount(tester);
    });

    testWidgets('a Contents row jumps to its section', (tester) async {
      await _letterSettings(tester, _Fs(settings: const {}, letter: _built()));
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('lset-contents')),
          matching: find.text('The latest letter'),
        ),
      );
      await _settle(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.byKey(const ValueKey('lset-send-now')).hitTestable(),
        findsOneWidget,
      );
      await _unmount(tester);
    });
  });

  group('Letter settings: Composition', () {
    testWidgets('the passages stepper reaches 7 and holds its +', (
      tester,
    ) async {
      await _letterSettings(
        tester,
        _Fs(settings: const {'itemsPerNewsletter': 6}),
      );
      await tester.ensureVisible(find.byKey(const ValueKey('lset-passages')));
      await tester.tap(_stepperGlyph('lset-passages', '+'));
      await tester.pump();
      expect(_stepper(tester, 'lset-passages'), 7);
      await tester.tap(_stepperGlyph('lset-passages', '+'));
      await tester.pump();
      expect(_stepper(tester, 'lset-passages'), 7);
      await _unmount(tester);
    });

    testWidgets('a stored 12 shows 12, and + never lowers it', (tester) async {
      await _letterSettings(
        tester,
        _Fs(settings: const {'itemsPerNewsletter': 12}),
      );
      await tester.ensureVisible(find.byKey(const ValueKey('lset-passages')));
      expect(_stepper(tester, 'lset-passages'), 12);
      expect(_stepperGlyph('lset-passages', '12'), findsOneWidget);
      await tester.tap(_stepperGlyph('lset-passages', '+'));
      await tester.pump();
      expect(_stepper(tester, 'lset-passages'), 12);
      await tester.tap(_stepperGlyph('lset-passages', '−'));
      await tester.pump();
      expect(_stepper(tester, 'lset-passages'), 11);
      await _unmount(tester);
    });

    testWidgets('How often is a draft: it moves on the press, writes nothing, '
        'and Save carries it', (tester) async {
      final api = _Api();
      ApiService.instance.httpClientAdapter = api;
      await _letterSettings(
        tester,
        _Fs(
          settings: const {
            'enabled': true,
            'frequency': 'daily',
            'deliveryTime': '07:00',
          },
        ),
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('lset-frequency')),
          matching: find.text('Weekly'),
        ),
      );
      await _settle(tester);
      expect(
        tester
            .widget<KitSlideSwitch<String>>(
              find.byKey(const ValueKey('lset-frequency')),
            )
            .value,
        'weekly',
      );
      expect(api.sent, isEmpty, reason: 'a draft has no write of its own');
      expect(
        _folio(tester, 'LETTERS · SETTINGS'),
        'LETTERS · SETTINGS · WEEKLY AT 7:00 AM',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('lset-save')));
      await tester.tap(find.byKey(const ValueKey('lset-save')));
      await _settle(tester);
      expect((api.sent.single.data as Map)['frequency'], 'weekly');
      await _unmount(tester);
    });

    testWidgets('Draw from counts in words: 1 shelf, all shelves', (
      tester,
    ) async {
      await _letterSettings(
        tester,
        _Fs(
          settings: const {
            'topicFilters': ['Pasta'],
          },
        ),
        shelves: [
          Tag.fromJson('s1', {
            'user_id': 'u1',
            'title': 'Pasta',
            'color': 'sage-500',
          }),
          Tag.fromJson('s2', {
            'user_id': 'u1',
            'title': 'Stories',
            'color': 'plum-600',
          }),
        ],
      );
      expect(find.text('1 shelf'), findsOneWidget);
      await _unmount(tester);
    });
  });

  group('Support: the folio, the figures and the column', () {
    testWidgets('before the thread is read: the dash everywhere, skeleton '
        'lines', (tester) async {
      await _support(tester, _Support(isLoading: true));
      expect(_folio(tester, 'SUPPORT'), 'SUPPORT · — MESSAGES');
      expect(_figure(tester, 'Messages'), '—');
      expect(_figure(tester, 'Last'), '—');
      expect(_figure(tester, 'Status'), '—');
      expect(find.byType(KitSkeletonLines), findsOneWidget);
      expect(find.text('Nothing sent yet'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('a refused read: the dash, §14.1, never Nothing sent yet', (
      tester,
    ) async {
      await _support(
        tester,
        _Support(sub: 'Missing or insufficient permissions.'),
      );
      expect(_folio(tester, 'SUPPORT'), 'SUPPORT · — MESSAGES');
      expect(_figure(tester, 'Status'), '—');
      expect(
        find.text('Your support thread could not be read.'),
        findsOneWidget,
      );
      expect(find.text('Nothing sent yet'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('no thread: 0 messages, Nothing sent yet, the quiet offer', (
      tester,
    ) async {
      await _support(tester, _Support());
      expect(_folio(tester, 'SUPPORT'), 'SUPPORT · 0 MESSAGES');
      expect(_figure(tester, 'Messages'), '0');
      expect(_figure(tester, 'Last'), '—');
      expect(_figure(tester, 'Status'), 'Nothing sent yet');
      expect(find.byType(KitEmptyState), findsOneWidget);
      expect(
        find.text('Replies reach you through your notification channels.'),
        findsOneWidget,
      );
      expect(find.text('Notification channels'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('a thread awaiting a reply: the register, the awaiting line', (
      tester,
    ) async {
      final now = DateTime.now();
      final at = DateTime(
        now.year,
        now.month,
        now.day,
        9,
        41,
      ).millisecondsSinceEpoch;
      await _support(
        tester,
        _Support(
          th: const SupportThread(
            id: 'u1',
            lastSender: SupportSender.user,
            messageCount: 2,
          ),
          list: [
            SupportMessage(
              id: 'm1',
              sender: SupportSender.support,
              body: 'Thanks — looking now.',
              createdAt: at,
            ),
            SupportMessage(
              id: 'm2',
              sender: SupportSender.user,
              body: 'The reader lost my place.',
              route: '/activity',
              createdAt: at,
            ),
          ],
        ),
      );
      expect(_folio(tester, 'SUPPORT'), 'SUPPORT · 2 MESSAGES');
      expect(_figure(tester, 'Last'), 'You · 9:41 AM');
      expect(_figure(tester, 'Status'), 'Awaiting a reply');
      expect(find.byType(KitDThread), findsOneWidget);
      expect(find.byType(KitMessageCard), findsNWidgets(2));
      expect(find.text('YOU · 9:41 AM · /ACTIVITY'), findsOneWidget);
      expect(find.byType(KitThreadNote), findsOneWidget);
      await _unmount(tester);
    });
  });

  group('Support: the §38 composer', () {
    testWidgets('one line tall at rest, growing to 172, then scrolling', (
      tester,
    ) async {
      await _support(tester, _Support());
      final field = find.byKey(const ValueKey('support-field'));
      expect(
        tester.getSize(field).height,
        closeTo(24 + 14, 1),
        reason: 'one line: 24 + `7px 0`',
      );
      await tester.enterText(field, 'one\ntwo\nthree');
      await tester.pump();
      expect(tester.getSize(field).height, closeTo(3 * 24 + 14, 1));
      await tester.enterText(field, List.filled(20, 'line').join('\n'));
      await tester.pump();
      expect(tester.getSize(field).height, 172, reason: 'then it scrolls');
      await _unmount(tester);
    });

    testWidgets('a refused send keeps the text, with the server\'s sentence; '
        'an accepted one clears it', (tester) async {
      var refuse = true;
      final api = _Api(
        (_) => refuse
            ? (
                400,
                {
                  'error': 'That message is too long.',
                  'error_code': 'INVALID_BODY',
                  'request_id': 'r1',
                },
              )
            : (201, {'ok': true}),
      );
      ApiService.instance.httpClientAdapter = api;
      final support = _Support();
      await _support(tester, support);
      final field = find.byKey(const ValueKey('support-field'));
      await tester.enterText(field, 'The rescan does nothing.');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('support-send')));
      await _settle(tester);
      expect(api.sent, hasLength(1));
      expect(
        find.text('The rescan does nothing.'),
        findsOneWidget,
        reason: 'write before you move: the draft stays',
      );
      expect(
        find.descendant(
          of: find.byType(KitDComposer),
          matching: find.text('That message is too long.'),
        ),
        findsOneWidget,
      );
      refuse = false;
      await tester.tap(find.byKey(const ValueKey('support-send')));
      await _settle(tester);
      expect(api.sent, hasLength(2));
      expect(
        tester
            .widget<TextField>(
              find.descendant(of: field, matching: find.byType(TextField)),
            )
            .controller
            ?.text,
        '',
      );
      await _unmount(tester);
    });

    testWidgets('⌘/Ctrl+Enter sends; Enter is a newline', (tester) async {
      final api = _Api((_) => (201, {'ok': true}));
      ApiService.instance.httpClientAdapter = api;
      await _support(tester, _Support());
      final field = find.byKey(const ValueKey('support-field'));
      await tester.enterText(field, 'The rescan does nothing.');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _settle(tester);
      expect(api.sent, isEmpty, reason: 'a bare Enter is the field\'s');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await _settle(tester);
      expect(api.sent, hasLength(1));
      await _unmount(tester);
    });

    testWidgets('an empty field holds the send', (tester) async {
      final api = _Api();
      ApiService.instance.httpClientAdapter = api;
      await _support(tester, _Support());
      await tester.tap(find.byKey(const ValueKey('support-send')));
      await tester.pump();
      expect(api.sent, isEmpty);
      expect(find.bySemanticsLabel('Send to support'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('docked at the column\'s foot, above the support footer', (
      tester,
    ) async {
      await _support(tester, _Support());
      final composer = find.byType(KitDComposer);
      final footer = tester.getRect(find.byKey(_footer));
      expect(tester.getRect(composer).bottom, lessThanOrEqualTo(footer.top));
      await _unmount(tester);
    });
  });

  group('a 402 phone, both themes: no overflow', () {
    for (final b in Brightness.values) {
      testWidgets('Letter settings — $b', (tester) async {
        await _letterSettings(
          tester,
          _Fs(
            settings: const {
              'enabled': true,
              'frequency': 'weekdays',
              'deliveryTime': '08:00',
              'timezone': 'America/Los_Angeles',
              'topicFilters': ['Pasta'],
            },
            letter: _built(),
            readings: const ScriptureNewsletterSettings(enabled: true),
          ),
          size: _phone,
          b: b,
          shelves: [
            Tag.fromJson('s1', {
              'user_id': 'u1',
              'title': 'A shelf whose name runs long enough to wrap',
              'color': 'sage-500',
            }),
          ],
        );
        expect(tester.takeException(), isNull);
        // The running head is the sheet's Contents line.
        final peek = find.byKey(const ValueKey('d-peek'));
        expect(peek, findsOneWidget);
        expect(
          find.descendant(of: peek, matching: find.text('Delivery')),
          findsOneWidget,
        );
        final scroll = find
            .ancestor(
              of: find.byKey(const ValueKey('lset-schedule')),
              matching: find.byType(Scrollable),
            )
            .first;
        final pos = tester.state<ScrollableState>(scroll).position;
        for (var y = 0.0; y < pos.maxScrollExtent; y += 600) {
          pos.jumpTo(y);
          await tester.pump();
          expect(tester.takeException(), isNull, reason: 'at $y');
        }
        pos.jumpTo(pos.maxScrollExtent);
        await _settle(tester);
        expect(tester.takeException(), isNull);
        await _unmount(tester);
      });

      testWidgets('Support — $b', (tester) async {
        await _support(
          tester,
          _Support(
            th: const SupportThread(id: 'u1', lastSender: SupportSender.user),
            list: [
              SupportMessage(
                id: 'm1',
                sender: SupportSender.user,
                body: 'A long report: ${List.filled(40, 'word').join(' ')}',
                route: '/sources',
                createdAt: DateTime(2026, 9, 12, 10, 2).millisecondsSinceEpoch,
              ),
            ],
          ),
          size: _phone,
          b: b,
        );
        expect(tester.takeException(), isNull);
        final peek = find.byKey(const ValueKey('d-peek'));
        expect(
          find.descendant(of: peek, matching: find.text('Awaiting a reply')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: peek, matching: find.text('1')),
          findsOneWidget,
        );
        await tester.enterText(
          find.byKey(const ValueKey('support-field')),
          List.filled(12, 'a line of the report').join('\n'),
        );
        await _settle(tester);
        expect(tester.takeException(), isNull);
        await _unmount(tester);
      });
    }
  });
}
