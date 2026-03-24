import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers/auth_provider.dart';
import 'providers/server_url_provider.dart';
import 'screens/auth_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/habit_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/add_habit_screen.dart';
import 'screens/server_url_screen.dart';
import 'screens/summary_screen.dart';
import 'screens/shell_screen.dart';

class _RouterListenable extends ChangeNotifier {
  void notify() => notifyListeners();
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterListenable();
  ref.listen(authProvider, (_, __) => notifier.notify());
  ref.listen(serverUrlProvider, (_, __) => notifier.notify());
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: notifier,
    redirect: (context, state) {
      final serverUrl = ref.read(serverUrlProvider);
      final auth = ref.read(authProvider);
      final path = state.uri.path;

      // 1. Still loading storage — show spinner
      if (serverUrl.status == ServerUrlStatus.loading ||
          auth.status == AuthStatus.loading) {
        return path == '/loading' ? null : '/loading';
      }

      // 2. No server URL saved yet — must configure first
      if (serverUrl.status == ServerUrlStatus.unset) {
        return path == '/server-url' ? null : '/server-url';
      }

      // 3. Server URL set but not authenticated
      if (auth.status == AuthStatus.unauthenticated) {
        return path == '/auth' ? null : '/auth';
      }

      // 4. Authenticated — bounce away from setup/auth screens
      if (auth.status == AuthStatus.authenticated &&
          (path == '/auth' || path == '/server-url' || path == '/loading')) {
        return '/';
      }

      return null;
    },
    routes: [
      // Loading splash (outside shell)
      GoRoute(
        path: '/loading',
        builder: (_, __) => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      ),

      // Server URL setup (outside shell — first-launch only)
      GoRoute(
        path: '/server-url',
        builder: (_, __) => const ServerUrlScreen(),
      ),

      // Auth (outside shell — no bottom nav)
      GoRoute(
        path: '/auth',
        builder: (_, __) => const AuthScreen(),
      ),

      // Add habit (outside shell — focused task with own AppBar)
      GoRoute(
        path: '/add-habit',
        builder: (_, __) => const AddHabitScreen(),
      ),

      // Main app shell — AppBar + bottom nav wraps all authenticated screens
      ShellRoute(
        builder: (context, state, child) => ShellScreen(
          location: state.uri.path,
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (_, __) => const ProfileScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, __) => const SettingsScreen(),
          ),
          GoRoute(
            path: '/habit/:id',
            builder: (context, state) {
              final id = int.parse(state.pathParameters['id']!);
              return HabitScreen(habitId: id);
            },
          ),
          GoRoute(
            path: '/summary',
            builder: (_, __) => const SummaryScreen(),
          ),
        ],
      ),
    ],
  );
});
