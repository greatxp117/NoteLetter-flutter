import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/models/ask_thread.dart';
import 'package:flutter_app/models/tag.dart';
import 'package:flutter_app/pages/chat_page.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/shared/local_flags.dart';
import 'package:flutter_app/state/chat_notifier.dart';
import 'package:flutter_app/state/tags_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/theme/tokens.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

import '../contract/sources_harness.dart' show StubTags;

/// Ask in direction D (F-143; `screens/ask.md` §Composition) with F-134's
/// written answer folded in (5.30.0, kit §25) — the real [ChatPage] over a
/// stubbed Firestore, at the phone's 402 and the desk's 1280, in BOTH themes:
/// the masthead per state, the sheet's groups, the answer (its marker scrolls
/// to and marks its citation, its quote, its note), the citations register,
/// the sent turn and its refusal, the §38 composer (one line, growing toward
/// 172; Enter, Shift+Enter, an IME's Enter), and where the dock rests.

const _phone = Size(402, 874);
const _wide = Size(1280, 900);

final _today = DateTime.now().millisecondsSinceEpoch;
final _lastWeek =
    DateTime.now().subtract(const Duration(days: 9)).millisecondsSinceEpoch;

const _pasta = 'What have I been reading about pasta cooking?';
const _dried =
    'Dried pasta suits sturdy sauces; fresh pasta suits butter and cream in '
    'this recipe.';
const _note = "NoteLetter couldn't write an answer this time. These are the "
    'passages it found.';

AskCitation _cite(int i) => AskCitation(
      chunkId: 'c$i',
      documentId: 'd1',
      title: 'Pasta Fundamentals',
      excerpt: [
        _dried,
        'Finish cooking the pasta in its sauce so the recipe comes together.',
        'Salting the water A pasta recipe begins with heavily salted boiling '
            'water in the kitchen.',
        'A fourth passage that sits low on the page.',
        'A fifth passage, the last one cited.',
      ][i - 1],
      sourceType: 'article',
      sourceUrl: 'https://example.com/pasta-fundamentals',
    );

final _threads = [
  AskThread(
      id: 't1', title: _pasta, preview: 'and about tax invoices?',
      updatedAt: _today, messageCount: 2),
  AskThread(
      id: 't2', title: 'Which recipes use steak?', preview: 'Which recipes?',
      updatedAt: _lastWeek, tagId: 's1', tagTitle: 'Recipes'),
];

final _answered = <AskMessage>[
  const AskMessage(id: 'q1', role: AskRole.user, text: _pasta),
  AskMessage(
    id: 'a1',
    role: AskRole.library,
    citations: [for (var i = 1; i <= 5; i++) _cite(i)],
    answer: const [
      AskAnswerBlock.paragraph('A deterministic answer drawn from your notes [1].'),
      AskAnswerBlock.quote(1, _dried),
    ],
  ),
];

final _noted = <AskMessage>[
  const AskMessage(id: 'q2', role: AskRole.user, text: 'Which recipes use steak?'),
  AskMessage(
    id: 'a2',
    role: AskRole.library,
    citations: [_cite(1)],
    answerNote: _note,
  ),
];

class _Ask extends FirestoreService {
  _Ask({
    this.threads,
    this.messages = const {},
    this.threadsError,
    this.messagesError,
    this.holdMessages = false,
  }) : super.stub();

  /// Null holds the conversations read open (it never answers).
  final List<AskThread>? threads;
  final Map<String, List<AskMessage>> messages;
  final Object? threadsError;
  final Object? messagesError;
  final bool holdMessages;

  @override
  Stream<List<AskThread>> subscribeAskThreads({int limit = 100}) {
    if (threadsError != null) return Stream.error(threadsError!);
    if (threads == null) {
      final c = StreamController<List<AskThread>>();
      return c.stream;
    }
    return Stream.value(threads!);
  }

  @override
  Stream<List<AskMessage>> subscribeAskMessages(String threadId) {
    if (messagesError != null) return Stream.error(messagesError!);
    if (holdMessages) return StreamController<List<AskMessage>>().stream;
    return Stream.value(messages[threadId] ?? const []);
  }
}

/// `fn_ask_turn`, answered as the test says — or held open until [release].
class _Turn implements HttpClientAdapter {
  _Turn(this.status, this.body);
  final int status;
  final Object body;
  final hold = Completer<void>();
  bool held = false;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls++;
    if (held) await hold.future;
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

const _footer = ValueKey('footer');

Future<void> _pump(
  WidgetTester tester, {
  required String at,
  required _Ask service,
  Size size = _wide,
  Brightness b = Brightness.light,
  List<Tag> shelves = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  FirestoreService.instance = service;
  addTearDown(FirestoreService.resetInstance);
  KitPageTools.instance.reset();
  Widget page(Widget child) => KitShellFooter(
        footer: const SizedBox(key: _footer, height: 160),
        child: Scaffold(body: child),
      );
  final router = GoRouter(initialLocation: at, routes: [
    GoRoute(path: '/ask', builder: (_, _) => page(const ChatPage())),
    GoRoute(
        path: '/ask/shelf/:tagId',
        builder: (_, s) =>
            page(ChatPage(scopeTagId: s.pathParameters['tagId']))),
    GoRoute(
        path: '/ask/thread/:threadId',
        builder: (_, s) =>
            page(ChatPage(threadId: s.pathParameters['threadId']))),
    GoRoute(
        path: '/reader/:id',
        builder: (_, s) => Text('reader ${s.pathParameters['id']}')),
  ]);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ChatNotifier>(create: (_) => ChatNotifier()),
      ChangeNotifierProvider<TagsNotifier>(create: (_) => StubTags(shelves)),
    ],
    child: MaterialApp.router(
      theme: b == Brightness.dark ? AppTheme.dark : AppTheme.light,
      routerConfig: router,
    ),
  ));
  await _settle(tester);
}

/// Bounded pumps — the skeleton lines shimmer forever, so never
/// `pumpAndSettle` here.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 2));
}

Tokens _t(Brightness b) => b == Brightness.dark ? Tokens.dark : Tokens.light;

/// Whether a span, or any span it holds, is set in italic.
bool _italic(InlineSpan span) =>
    span.style?.fontStyle == FontStyle.italic ||
    (span is TextSpan && (span.children ?? const []).any(_italic));

/// Every place [text] is drawn, rich text included.
Finder _txt(String text) => find.text(text, findRichText: true);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalFlags.resetForTest();
    ApiService.instance.tokenProvider = () async => 'test-token';
  });
  tearDown(ApiService.instance.resetTestSeams);

  group('the masthead, per state', () {
    for (final size in [_phone, _wide]) {
      for (final b in Brightness.values) {
        testWidgets('a new conversation — ${size.width} $b', (tester) async {
          await _pump(tester,
              at: '/ask', service: _Ask(threads: _threads), size: size, b: b);
          expect(_txt('ASK · GROUNDED IN YOUR LIBRARY'), findsOneWidget);
          expect(find.text('Ask Your Library'), findsOneWidget);
          expect(
              find.text('Ask about what you’ve read — answers quote the '
                  'passages they draw on.'),
              findsOneWidget);
          expect(KitPageTools.instance.action, isNull,
              reason: 'New conversation only while one is open');
          // §37: the feather, its title and standfirst, the four offers.
          expect(find.text('Ask your library a question'), findsOneWidget);
          expect(
              find.text('Ask a question and NoteLetter will answer from your '
                  'notes, quoting the passages it draws on.'),
              findsOneWidget);
          expect(find.byType(KitSuggestion), findsNWidgets(4));
          // The title is set smaller than §26's: 32 on a phone, else
          // clamp(38, 4cqi, 64).
          final style =
              tester.widget<Text>(find.text('Ask Your Library')).style!;
          if (size == _phone) {
            expect(style.fontSize, 32);
          } else {
            expect(style.fontSize, inInclusiveRange(38, 64));
          }
          expect(tester.takeException(), isNull);
          await _unmount(tester);
        });
      }
    }

    testWidgets('scoped: every line names the shelf, and no prompts',
        (tester) async {
      await _pump(tester,
          at: '/ask/shelf/s1',
          service: _Ask(threads: _threads),
          shelves: const [
            Tag(id: 's1', userId: 'u1', title: 'Recipes', color: 'teal'),
          ]);
      expect(_txt('ASK · GROUNDED IN ONE SHELF · RECIPES'),
          findsOneWidget);
      expect(find.text('Ask Recipes'), findsOneWidget);
      expect(
          find.text('Only passages on this shelf are read — every answer '
              'quotes the passages it draws on.'),
          findsOneWidget);
      expect(find.text('Ask Recipes a question'), findsOneWidget);
      expect(find.byType(KitSuggestion), findsNothing);
      expect(find.text('Ask Recipes anything…'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(KitAskComposer),
              matching: find.bySemanticsLabel('Ask Recipes')),
          findsOneWidget,
          reason: 'the composer\'s accessible name names the shelf');
      await _unmount(tester);
    });

    for (final size in [_phone, _wide]) {
      testWidgets('a conversation open — ${size.width}', (tester) async {
        await _pump(tester,
            at: '/ask/thread/t1',
            service: _Ask(threads: _threads, messages: {'t1': _answered}),
            size: size);
        final folio = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .firstWhere((s) => s.startsWith('ASK · GROUNDED'));
        expect(folio, matches(RegExp(r'· \d{1,2}:\d\d [AP]M$')),
            reason: 'the clock today, after a no-break space');
        expect(find.descendant(of: find.byType(KitAskTitle), matching: find.text(_pasta)),
            findsOneWidget);
        final action = KitPageTools.instance.action;
        expect(action?.label, 'New conversation');
        expect(action?.short, 'New', reason: 'the tab bar centre on a phone');
        await _unmount(tester);
      });
    }
  });

  group('the sheet: Conversations', () {
    for (final b in Brightness.values) {
      testWidgets('Today and Earlier, the open one marked, scope and §9.1 '
          '— $b', (tester) async {
        await _pump(tester,
            at: '/ask/thread/t1',
            service: _Ask(threads: _threads, messages: {'t1': _answered}),
            b: b);
        expect(find.text('CONVERSATIONS'), findsOneWidget);
        expect(find.text('TODAY'), findsOneWidget);
        expect(find.text('EARLIER'), findsOneWidget);
        expect(
            tester.getTopLeft(find.text('TODAY')).dy,
            lessThan(tester.getTopLeft(find.text('EARLIER')).dy));
        expect(find.byType(KitAskConvo), findsNWidgets(2));
        expect(find.text('RECIPES'), findsOneWidget, reason: '§9.2 scope');
        // The open entry: the accent dot and weight 600.
        final dot = find.byKey(const ValueKey('ask-convo-dot'));
        expect(dot, findsOneWidget);
        expect(
            (tester.widget<Container>(dot).decoration as BoxDecoration).color,
            _t(b).accent);
        final open = tester.widget<Text>(find.descendant(
            of: find.byKey(const ValueKey('ask-convo-t1')),
            matching: find.text(_pasta)));
        expect(open.style!.fontWeight, FontWeight.w600);
        expect(find.bySemanticsLabel('Rename “$_pasta”'), findsOneWidget);
        expect(find.bySemanticsLabel('Delete “$_pasta”'), findsOneWidget);
        await _unmount(tester);
      });
    }

    testWidgets('while it is read: skeleton lines, not the no-threads state',
        (tester) async {
      await _pump(tester, at: '/ask', service: _Ask());
      expect(
          find.descendant(
              of: find.byType(KitSheetCard),
              matching: find.byType(KitSkeletonLines)),
          findsOneWidget);
      expect(find.byType(KitAskConvo), findsNothing);
      await _unmount(tester);
    });

    testWidgets('a refused read: §14.1 in the list\'s place', (tester) async {
      await _pump(tester,
          at: '/ask',
          service: _Ask(
              threadsError: FirebaseException(
                  plugin: 'cloud_firestore', code: 'permission-denied')));
      expect(find.text('Your conversations could not be loaded.'),
          findsOneWidget);
      expect(find.byType(KitAskConvo), findsNothing);
      expect(find.text('New conversation'), findsOneWidget,
          reason: 'the way out stays');
      await _unmount(tester);
    });

    testWidgets('rename in place: the field carries the title, Escape '
        'abandons', (tester) async {
      await _pump(tester,
          at: '/ask/thread/t1',
          service: _Ask(threads: _threads, messages: {'t1': _answered}));
      await tester.tap(find.bySemanticsLabel('Rename “$_pasta”'));
      await _settle(tester);
      final field = find.descendant(
          of: find.byKey(const ValueKey('ask-convo-t1')),
          matching: find.byType(TextField));
      expect(field, findsOneWidget);
      expect(tester.widget<TextField>(field).controller!.text, _pasta);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
      expect(field, findsNothing);
      await _unmount(tester);
    });
  });

  group('the transcript', () {
    for (final size in [_phone, _wide]) {
      for (final b in Brightness.values) {
        testWidgets('§25 answer, quote and the citations register — '
            '${size.width} $b', (tester) async {
          await _pump(tester,
              at: '/ask/thread/t1',
              service: _Ask(threads: _threads, messages: {'t1': _answered}),
              size: size,
              b: b);
          final t = _t(b);
          // The question: mono caps You over the serif 600 head.
          expect(find.text('YOU'), findsOneWidget);
          expect(find.text('YOUR LIBRARY'), findsOneWidget);
          final q = tester
              .widgetList<Text>(find.text(_pasta))
              .where((w) => w.style?.fontWeight == FontWeight.w600)
              .toList();
          expect(q, isNotEmpty);
          // The paragraph's [n] is a chip, never the bracketed text.
          expect(_txt('A deterministic answer drawn from your notes .'),
              findsNothing);
          expect(find.textContaining('[1]', findRichText: true), findsNothing);
          expect(find.byType(KitAskRef), findsNWidgets(2),
              reason: 'the paragraph\'s marker and the quote\'s meta');
          // The quote: italic, set in from a 2px accent rule, no added marks.
          final quote = find.byKey(const ValueKey('ask-quote-1'));
          expect(quote, findsOneWidget);
          final rule = (tester.widget<Container>(quote).decoration
                  as BoxDecoration)
              .border as Border;
          expect(rule.left.width, 2);
          expect(rule.left.color, t.accent);
          final qt = tester.widget<RichText>(find
              .descendant(of: quote, matching: find.byType(RichText))
              .first);
          expect(qt.text.toPlainText(), _dried,
              reason: 'the passage\'s own characters, no quotation marks');
          expect(_italic(qt.text), isTrue, reason: 'serif italic');
          // The register: index, badge, title, the whole excerpt, actions.
          expect(find.byType(KitAskCitation), findsNWidgets(5));
          expect(find.byType(KitFileBadge), findsNWidgets(5));
          expect(find.text('Open'), findsNWidgets(5));
          expect(find.text('example.com'), findsNWidgets(5));
          final idx = tester.widget<Text>(find.descendant(
              of: find.byType(KitAskCitation).first,
              matching: find.text('1')));
          expect(idx.style?.fontStyle, FontStyle.italic);
          expect(idx.style?.color, t.accentText);
          expect(idx.textAlign, TextAlign.right);
          expect(tester.takeException(), isNull);
          await _unmount(tester);
        });
      }
    }

    testWidgets('a marker scrolls to its citation and marks it for 1.6s',
        (tester) async {
      await _pump(tester,
          at: '/ask/thread/t1',
          service: _Ask(threads: _threads, messages: {'t1': _answered}),
          size: _phone);
      final scroll = find
          .ancestor(of: find.byType(KitAskQuestion), matching: find.byType(Scrollable))
          .first;
      final before = tester.state<ScrollableState>(scroll).position.pixels;
      KitAskCitation cite() =>
          tester.widget<KitAskCitation>(find.byType(KitAskCitation).first);
      expect(cite().marked, isFalse);
      await tester.tap(find.byType(KitAskRef).first);
      await tester.pump();
      expect(cite().marked, isTrue);
      await tester.pump(const Duration(milliseconds: 600));
      final after = tester.state<ScrollableState>(scroll).position.pixels;
      expect(after, greaterThan(before),
          reason: 'citation 1 sat below the fold on a phone');
      final box = tester.getRect(find.byType(KitAskCitation).first);
      expect(box.top, greaterThanOrEqualTo(0));
      expect(box.bottom, lessThan(_phone.height - 100),
          reason: 'it lands above the docked composer');
      // `--accent-soft` while marked.
      await tester.pump(const Duration(milliseconds: 200));
      final fill = tester
          .widget<AnimatedContainer>(find.descendant(
              of: find.byType(KitAskCitation).first,
              matching: find.byType(AnimatedContainer)))
          .decoration as BoxDecoration;
      expect(fill.color, Tokens.light.accentSoft);
      await tester.pump(const Duration(milliseconds: 1000));
      expect(cite().marked, isFalse, reason: 'for a moment, not for good');
      await _unmount(tester);
    });

    for (final b in Brightness.values) {
      testWidgets('the note: one italic muted line, never §14 — $b',
          (tester) async {
        await _pump(tester,
            at: '/ask/thread/t2',
            service: _Ask(threads: _threads, messages: {'t2': _noted}),
            size: _phone,
            b: b);
        final note = tester.widget<Text>(find.text(_note));
        expect(note.style?.fontStyle, FontStyle.italic);
        expect(note.style?.color, _t(b).fgMuted);
        expect(find.byType(KitFailureBlock), findsNothing);
        expect(find.byType(KitFailureInline), findsNothing);
        expect(find.byType(KitAskCitation), findsOneWidget);
        await _unmount(tester);
      });
    }

    testWidgets('a thread being restored draws skeleton lines, never the '
        'thinking line', (tester) async {
      await _pump(tester,
          at: '/ask/thread/t1',
          service: _Ask(threads: _threads, holdMessages: true));
      expect(find.text('Reading your notes…'), findsNothing);
      expect(find.byType(KitEmptyState), findsNothing);
      expect(find.byType(KitSkeletonLines), findsWidgets);
      await _unmount(tester);
    });

    testWidgets('a refused transcript read: §14.1 with its retry',
        (tester) async {
      await _pump(tester,
          at: '/ask/thread/t1',
          service: _Ask(
              threads: _threads,
              messagesError: FirebaseException(
                  plugin: 'cloud_firestore', code: 'permission-denied')));
      expect(find.text('This conversation could not be loaded.'),
          findsOneWidget);
      expect(find.byType(KitEmptyState), findsNothing);
      expect(find.text('Try again'), findsOneWidget,
          reason: 'the read\'s retry: it re-subscribes');
      await _unmount(tester);
    });

    testWidgets('the three empties stay three', (tester) async {
      await _pump(tester,
          at: '/ask/thread/t1',
          service: _Ask(threads: _threads, messages: {
            't1': const [
              AskMessage(id: 'q', role: AskRole.user, text: 'one'),
              AskMessage(id: 'a', role: AskRole.library),
              AskMessage(id: 'q2', role: AskRole.user, text: 'two'),
              AskMessage(
                  id: 'b',
                  role: AskRole.library,
                  scope: AskScope(tagId: 's1', title: 'Recipes')),
              AskMessage(id: 'q3', role: AskRole.user, text: 'three'),
              AskMessage(
                  id: 'c',
                  role: AskRole.library,
                  scope: AskScope(
                      tagId: 's1', title: 'Recipes', exhaustive: false)),
            ],
          }));
      expect(find.text('No related passages found.'), findsOneWidget);
      expect(find.text('No passages on Recipes relate to that.'),
          findsOneWidget);
      expect(
          find.text('No passages on Recipes came up among the closest '
              'matches in your library. A narrower question may reach them.'),
          findsOneWidget);
      await _unmount(tester);
    });
  });

  group('the sent turn (ADR-097) and the composer (§38)', () {
    testWidgets('Enter asks: the question stays with Reading your notes…',
        (tester) async {
      final turn = _Turn(201, {'threadId': 't1', 'message': {}})..held = true;
      ApiService.instance.httpClientAdapter = turn;
      await _pump(tester, at: '/ask', service: _Ask(threads: const []));
      await tester.tap(find.byKey(const ValueKey('ask-field')));
      await tester.enterText(
          find.byKey(const ValueKey('ask-field')), 'What about bread?');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _settle(tester);
      expect(turn.calls, 1);
      expect(find.text('What about bread?'), findsOneWidget,
          reason: 'the question is in the transcript, not the composer');
      expect(find.text('Reading your notes…'), findsOneWidget);
      expect(find.byType(KitEmptyState), findsNothing);
      // Send is held while the turn is in flight.
      await tester.enterText(find.byKey(const ValueKey('ask-field')), 'more');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(turn.calls, 1);
      turn.hold.complete();
      await _settle(tester);
      await _unmount(tester);
    });

    for (final b in Brightness.values) {
      testWidgets('a refusal: the server\'s sentence and Try again — $b',
          (tester) async {
        ApiService.instance.httpClientAdapter = _Turn(500, {
          'error': 'Ask failed. Contact support with your request ID.',
          'error_code': 'INTERNAL',
          'request_id': 'req-1',
        });
        await _pump(tester,
            at: '/ask', service: _Ask(threads: const []), size: _phone, b: b);
        await tester.enterText(
            find.byKey(const ValueKey('ask-field')), 'What about bread?');
        await _settle(tester);
        await tester.tap(find.byKey(const ValueKey('ask-send')));
        await _settle(tester);
        expect(find.text('What about bread?'), findsOneWidget);
        expect(find.byType(KitFailureInline), findsOneWidget);
        expect(
            find.textContaining('Ask failed. Contact support',
                findRichText: true),
            findsOneWidget);
        expect(find.text('Try again'), findsOneWidget);
        expect(find.text('Reading your notes…'), findsNothing);
        await _unmount(tester);
      });
    }

    testWidgets('Shift+Enter and an IME\'s Enter are not a send',
        (tester) async {
      final turn = _Turn(500, {'error': 'x'});
      ApiService.instance.httpClientAdapter = turn;
      await _pump(tester, at: '/ask', service: _Ask(threads: const []));
      final field = find.byKey(const ValueKey('ask-field'));
      await tester.tap(field);
      await tester.enterText(field, 'line one');
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(turn.calls, 0, reason: 'Shift+Enter starts a new line');
      // An open composition: the Enter that ends it is the composition's.
      final controller = tester.widget<TextField>(find.descendant(
              of: field, matching: find.byType(TextField)))
          .controller!;
      controller.value = const TextEditingValue(
        text: 'かな',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(turn.calls, 0, reason: 'the IME owns that Enter');
      await _unmount(tester);
    });

    testWidgets('the field starts one line tall and grows to 172, then '
        'scrolls', (tester) async {
      await _pump(tester, at: '/ask', service: _Ask(threads: const []));
      final field = find.byKey(const ValueKey('ask-field'));
      final one = tester.getSize(field).height;
      expect(one, closeTo(24 + 14, 1), reason: 'one line: 24 + `7px 0`');
      await tester.enterText(field, 'one\ntwo\nthree');
      await tester.pump();
      expect(tester.getSize(field).height, closeTo(3 * 24 + 14, 1));
      await tester.enterText(field, List.filled(20, 'line').join('\n'));
      await tester.pump();
      expect(tester.getSize(field).height, 172, reason: 'then it scrolls');
      await _unmount(tester);
    });
  });

  group('the dock rests at the column\'s foot', () {
    for (final size in [_phone, _wide]) {
      testWidgets('pinned to the viewport\'s foot, then above the footer — '
          '${size.width}', (tester) async {
        await _pump(tester,
            at: '/ask/thread/t1',
            service: _Ask(threads: _threads, messages: {'t1': _answered}),
            size: size);
        final composer = find.byType(KitAskComposer);
        final scroll = find
            .ancestor(of: composer, matching: find.byType(Scrollable))
            .first;
        final view = tester.getRect(scroll);
        final pad = size == _phone ? 12.0 : 24.0;
        expect(tester.getRect(composer).bottom, closeTo(view.bottom - pad, 1),
            reason: 'while the column runs past the viewport');
        // To the end: the dock rests at the column's end, above the footer.
        final pos = tester.state<ScrollableState>(scroll).position;
        pos.jumpTo(pos.maxScrollExtent);
        await _settle(tester);
        final footer = tester.getRect(find.byKey(_footer));
        expect(tester.getRect(composer).bottom + pad,
            lessThanOrEqualTo(footer.top),
            reason: 'never over the support footer');
        expect(footer.bottom, closeTo(view.bottom, 1));
        // The dock answers where it is drawn: its send takes the tap.
        pos.jumpTo(0);
        await _settle(tester);
        // Pinned, a field that grows grows UP: the card's foot stays put.
        await tester.enterText(find.byKey(const ValueKey('ask-field')),
            'one\ntwo\nthree\nfour');
        await _settle(tester);
        expect(tester.getRect(composer).bottom, closeTo(view.bottom - pad, 1),
            reason: 'a growing composer stays docked');
        expect(tester.getSize(composer).height, greaterThan(100));
        await tester.enterText(
            find.byKey(const ValueKey('ask-field')), 'pinned');
        await tester.pump();
        expect(find.byKey(const ValueKey('ask-send')).hitTestable(),
            findsOneWidget);
        await _unmount(tester);
      });
    }
  });

  group('phone: the running head', () {
    testWidgets('the history glyph, the open title and the count; an entry '
        'folds it', (tester) async {
      await _pump(tester,
          at: '/ask/thread/t1',
          service: _Ask(threads: _threads, messages: {
            't1': _answered,
            't2': _noted,
          }),
          size: _phone);
      final peek = find.byKey(const ValueKey('d-peek'));
      expect(find.descendant(of: peek, matching: find.byIcon(Icons.history)),
          findsOneWidget);
      expect(find.descendant(of: peek, matching: find.text(_pasta)),
          findsOneWidget);
      expect(find.descendant(of: peek, matching: find.text('2')),
          findsOneWidget);
      await tester.tap(peek);
      await _settle(tester);
      await tester.tap(find.text('Which recipes use steak?').hitTestable());
      await _settle(tester);
      expect(find.descendant(of: peek, matching: find.text('Which recipes use steak?')),
          findsOneWidget,
          reason: 'it navigated to the entry');
      expect(find.text('TODAY').hitTestable(), findsNothing,
          reason: 'choosing an entry folds the running head');
      await _unmount(tester);
    });
  });
}
