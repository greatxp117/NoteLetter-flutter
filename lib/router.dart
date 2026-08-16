import 'package:go_router/go_router.dart';
import 'state/auth_notifier.dart';
import 'widgets/app_layout.dart';
import 'pages/landing_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/library_page.dart';
import 'pages/chat_page.dart';
import 'pages/settings_page.dart';
import 'pages/notification_settings_page.dart';
import 'pages/not_found_page.dart';
import 'pages/branding_page.dart';
import 'pages/reader_page.dart';
import 'pages/letters_page.dart';
import 'pages/sources_page.dart';
import 'pages/tags_page.dart';

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
    routes: [
      GoRoute(
        path: '/landing',
        builder: (context, state) => const LandingPage(),
      ),
      GoRoute(
        path: '/reader/:docId',
        builder: (context, state) =>
            ReaderPage(docId: state.pathParameters['docId']!),
      ),
      ShellRoute(
        builder: (context, state, child) => AppLayout(child: child),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const DashboardPage(),
          ),
          GoRoute(
            path: '/library',
            builder: (context, state) => const LibraryPage(),
          ),
          GoRoute(
            path: '/chat',
            builder: (context, state) => const ChatPage(),
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
              cloudConnectConnection:
                  state.uri.queryParameters['connection'],
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
          GoRoute(
            path: '/tags',
            builder: (context, state) => const TagsPage(),
          ),
        ],
      ),
    ],
  );
}
