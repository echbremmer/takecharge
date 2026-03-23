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
      final auth = ref.read(authProvider);
      final path = state.uri.path;

      if (auth.status == AuthStatus.loading) {
        return path == '/loading' ? null : '/loading';
      }
      if (auth.status == AuthStatus.unauthenticated && path != '/auth') {
        return '/auth';
      }
      if (auth.status == AuthStatus.authenticated &&
          (path == '/auth' || path == '/loading')) {
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

      // Auth (outside shell — no bottom nav)
      GoRoute(
        path: '/auth',
        builder: (_, __) => const AuthScreen(),
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
            path: '/habit/:id',
            builder: (context, state) {
              final id = int.parse(state.pathParameters['id']!);
              return HabitScreen(habitId: id);
            },
          ),
        ],
      ),
    ],
  );
});
