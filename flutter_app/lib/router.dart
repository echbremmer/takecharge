import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers/auth_provider.dart';
import 'screens/auth_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/habit_screen.dart';
import 'screens/shell_screen.dart';

class _AuthListenable extends ChangeNotifier {
  void notify() => notifyListeners();
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthListenable();
  ref.listen(authProvider, (_, __) => notifier.notify());
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: notifier,
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final isLoading = authState.status == AuthStatus.loading;
      final isAuthed = authState.status == AuthStatus.authenticated;
      final path = state.uri.path;

      // Show loading screen while checking auth
      if (isLoading) return path == '/loading' ? null : '/loading';

      // Send unauthenticated users to login
      if (!isAuthed && path != '/auth') return '/auth';

      // Send authenticated users away from auth/loading screens
      if (isAuthed && (path == '/auth' || path == '/loading')) return '/';

      return null;
    },
    routes: [
      // Loading splash
      GoRoute(
        path: '/loading',
        builder: (_, __) => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      ),

      // Auth (outside shell — no bottom nav)
      GoRoute(
        path: '/auth',
        builder: (_, __) => const AuthScreen(),
      ),

      // Habit detail (outside shell — no bottom nav)
      GoRoute(
        path: '/habit/:id',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);
          return HabitScreen(habitId: id);
        },
      ),

      // Main app shell (with bottom nav)
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
        ],
      ),
    ],
  );
});
