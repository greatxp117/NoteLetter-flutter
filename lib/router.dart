import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'services/analytics.dart';
import 'state/auth_notifier.dart';
import 'widgets/app_layout.dart';
import 'widgets/support_shell.dart';
import 'pages/landing_page.dart';
import 'pages/library_page.dart';
import 'pages/search_page.dart';
import 'pages/activity_page.dart';
import 'pages/chat_page.dart';
import 'pages/settings_page.dart';
import 'pages/notification_settings_page.dart';
import 'pages/not_found_page.dart';
import 'pages/branding_page.dart';
import 'pages/reader_page.dart';
import 'pages/letter_settings_page.dart';
import 'pages/letters_page.dart';
import 'pages/sources_page.dart';
import 'pages/tags_page.dart';
import 'pages/tags/shelf_page.dart';
import 'pages/study_page.dart';
import 'pages/study/session_player.dart';
import 'pages/study/program_editor.dart';
import 'pages/support_page.dart';
import 'pages/onboarding/wizard.dart';

GoRouter createRouter(AuthNotifier authNotifier) {
  return GoRouter(
    refreshListenable: authNotifier,
    redirect: (context, state) {
      final loggedIn = authNotifier.isLoggedIn;
      final onLanding = state.matchedLocation == '/landing';

      if (!loggedIn && !onLanding) return '/landing';
      if (loggedIn && onLanding) return '/';
      return null;
    },
    errorBuilder: (context, state) => const NotFoundPage(),
    routes: appRoutes(),
  );
}

/// `screen_view` for every navigation, keyed on the route PATTERN.
///
/// Here rather than in `services/analytics.dart` because this is where the
/// route table is — the reference emits it from its route effect for the same
/// reason. Keyed on the pattern (`/reader/:docId`), never on the location, so a
/// route that gains an id later cannot carry one onto the wire: that is the
/// reference's `buildPath`-with-no-ids argument, transposed.
///
/// Deduped on the pattern, because the delegate notifies on rebuilds as well as
/// navigations and a `screen_view` per rebuild measures how often Flutter
/// rebuilt. The post-frame call is for the FIRST screen, which is already
/// configured before anything can listen.
void attachAnalytics(GoRouter router) {
  String? last;
  void report() {
    String? pattern;
    try {
      pattern = router.state.fullPath;
    } catch (_) {
      return; // no configuration yet
    }
    if (pattern == last) return;
    last = pattern;
    final token = Analytics.screenName(pattern);
    if (token != null) Analytics.track('screen_view', {'screen_name': token});
  }

  router.routerDelegate.addListener(report);
  WidgetsBinding.instance.addPostFrameCallback((_) => report());
}

/// **The route table itself**, separated from [createRouter] so INV-22's gate
/// can walk it.
///
/// It is the same list the app runs — not a copy — which is the only form that
/// works: a gate reading a second declaration of the routes would go green on a
/// table the app does not use. Kept a function rather than a `const` because
/// `ShellRoute`/`GoRoute` builders are closures.
List<RouteBase> appRoutes() {
  return [
    GoRoute(path: '/landing', builder: (context, state) => const LandingPage()),
    // INV-22 — the OUTER shell, and the single place the support footer is
    // composed. Every authenticated route is nested inside it, including the
    // reader, which sits outside the rail-and-pane shell below. `/landing` is
    // deliberately outside: sending a support message requires a signed-in
    // caller (INV-01), so there is nothing for the footer to link to.
    ShellRoute(
      navigatorKey: supportShellNavigatorKey,
      // First-run onboarding (`spec/screens/onboarding.md`) wraps the whole
      // authenticated surface, OUTSIDE the support shell and outside
      // `AppLayout`: the wizard has its own frame, and the app's rail is
      // exactly what a reader with nothing in their library has no use for yet.
      // Outside `/landing` too — the gate reads a documents subscription, and
      // there is no reader to have a first run until someone is signed in.
      builder: (context, state, child) => OnboardingGate(
        child: SupportShell(route: state.matchedLocation, child: child),
      ),
      routes: [
        GoRoute(
          path: '/reader/:docId',
          // `?p=` is the passage a link asked for (INV-21) — the id-built
          // target the daily letter, the cohesive reading and search all hand
          // out. It was parsed by nothing on this client until 4.40.0, so
          // every one of those links opened the document at its top.
          builder: (context, state) => ReaderPage(
            docId: state.pathParameters['docId']!,
            passageId: state.uri.queryParameters['p'],
            // `?from=` is the screen the Reader was opened from (4.65.0,
            // ADR-101) — its back control names that screen and returns there.
            from: state.uri.queryParameters['from'],
          ),
        ),
        ShellRoute(
          builder: (context, state, child) => AppLayout(child: child),
          routes: [
            // `/` IS the library (spec/screens/library.md) — the web reference's
            // default view and the rail's Home. `/library` is kept as a redirect
            // because it was this client's route for the volume table, which now
            // lives on Sources.
            GoRoute(
              path: '/',
              builder: (context, state) => const LibraryPage(),
            ),
            GoRoute(path: '/library', redirect: (context, state) => '/'),
            // 4.53.0 — the route is `/ask`, as the reference's has always been.
            // `/chat` stays as a redirect: it is in this app's own history and
            // a renamed route that 404s is a link the reader cannot tell from
            // a deleted screen.
            GoRoute(path: '/chat', redirect: (context, state) => '/ask'),
            GoRoute(
              path: '/search',
              builder: (context, state) => const SearchPage(),
            ),
            GoRoute(
              path: '/activity',
              builder: (context, state) => const ActivityPage(),
            ),
            // Ask's three forms (4.65.0, ADR-101) — a new conversation, one
            // SCOPED to a shelf (4.62.0, ADR-098), and an OPEN one. The thread
            // form takes no shelf segment: a thread carries the scope it was
            // created with, and that scope wins over the route's.
            //
            // The open conversation was screen state until 4.65.0, so a reload
            // — and every return from a Reader a citation opened — drew the
            // new-conversation state over a transcript the reader was reading
            // a second earlier.
            GoRoute(
              path: '/ask',
              builder: (context, state) => const ChatPage(),
            ),
            GoRoute(
              path: '/ask/shelf/:tagId',
              builder: (context, state) =>
                  ChatPage(scopeTagId: state.pathParameters['tagId']),
            ),
            GoRoute(
              path: '/ask/thread/:threadId',
              builder: (context, state) =>
                  ChatPage(threadId: state.pathParameters['threadId']),
            ),
            // Study (2.34.0). `/study/session/:id` is where the session
            // email's CTA lands, so it must be a real route, not a tab.
            GoRoute(
              path: '/study',
              builder: (context, state) => const StudyPage(),
            ),
            GoRoute(
              path: '/study/new',
              builder: (context, state) => const ProgramEditorPage(),
            ),
            GoRoute(
              path: '/study/session/:sessionId',
              builder: (context, state) => SessionPlayerPage(
                sessionId: state.pathParameters['sessionId']!,
              ),
            ),
            GoRoute(
              path: '/study/:programId',
              builder: (context, state) => ProgramEditorPage(
                programId: state.pathParameters['programId'],
              ),
            ),
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsPage(),
            ),
            GoRoute(
              path: '/settings/notifications',
              builder: (context, state) => const NotificationSettingsPage(),
            ),
            GoRoute(
              // 2.3.0 (ADR-012): the OAuth callback lands here with an explicit
              // result in the query string.
              path: '/sources',
              builder: (context, state) => SourcesPage(
                cloudConnectResult: state.uri.queryParameters['cloud_connect'],
                cloudConnectProvider: state.uri.queryParameters['provider'],
                cloudConnectReason: state.uri.queryParameters['reason'],
                cloudConnectOrg: state.uri.queryParameters['org'],
                cloudConnectConnection: state.uri.queryParameters['connection'],
              ),
            ),
            GoRoute(
              path: '/branding',
              builder: (context, state) => const BrandingPage(),
            ),
            GoRoute(
              path: '/letters',
              builder: (context, state) => const LettersPage(),
            ),
            // The letter's form is its own screen, as the reference has it —
            // it was a section inside /settings until F-05.
            GoRoute(
              path: '/letters/settings',
              builder: (context, state) => const LetterSettingsPage(),
            ),
            // Shelves (F-08). `/shelves` and `/shelves/:id` are the
            // reference's own routes; `/tags` stays as a redirect because it
            // was this client's route for the whole life of the screen, and a
            // renamed route that 404s is a link the reader cannot tell from a
            // deleted screen.
            GoRoute(
              path: '/shelves',
              builder: (context, state) => const ShelvesPage(),
            ),
            GoRoute(
              path: '/shelves/:shelfId',
              builder: (context, state) => ShelfPage(
                shelfId: state.pathParameters['shelfId']!,
              ),
            ),
            GoRoute(path: '/tags', redirect: (context, state) => '/shelves'),
            // Support (4.18.0, ADR-054; spec/screens/support.md). `from` is the
            // route the user was on when they clicked the footer — supplied by
            // the shell, which is the only thing that knows it.
            GoRoute(
              path: supportRoute,
              builder: (context, state) =>
                  SupportPage(fromRoute: state.uri.queryParameters['from']),
            ),
          ],
        ),
      ],
    ),
  ];
}
