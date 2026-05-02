import 'package:go_router/go_router.dart';
import 'state/auth_notifier.dart';
import 'widgets/app_layout.dart';
import 'pages/landing_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/library_page.dart';
import 'pages/chat_page.dart';
import 'pages/settings_page.dart';
import 'pages/not_found_page.dart';
import 'pages/branding_page.dart';

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
            builder: (context, state) => SettingsPage(
              cloudConnectResult: state.uri.queryParameters['cloud_connect'],
              cloudConnectProvider: state.uri.queryParameters['provider'],
            ),
          ),
          GoRoute(
            path: '/branding',
            builder: (context, state) => const BrandingPage(),
          ),
        ],
      ),
    ],
  );
}
