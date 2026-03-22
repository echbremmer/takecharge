import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/habits.dart';

final habitsListProvider = FutureProvider<List<dynamic>>((ref) async {
  return habitsApi.list();
});

// Refresh trigger — increment to force re-fetch
final habitsRefreshProvider = StateProvider<int>((ref) => 0);

// Habits list that re-fetches when refresh is incremented
final habitsProvider = FutureProvider<List<dynamic>>((ref) async {
  ref.watch(habitsRefreshProvider); // dependency
  return habitsApi.list();
});

// Active fast (timer habit)
final activeFastProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  ref.watch(habitsRefreshProvider);
  return habitsApi.getActive();
});

// Daily targets per habit
final dailyTargetsProvider =
    FutureProvider.family<List<dynamic>, int>((ref, habitId) async {
  ref.watch(habitsRefreshProvider);
  return habitsApi.getTargets(habitId);
});

// Daily logs per habit (all days)
final dailyLogsProvider =
    FutureProvider.family<List<dynamic>, int>((ref, habitId) async {
  ref.watch(habitsRefreshProvider);
  return habitsApi.getLogs(habitId);
});

// Sessions (timer habit history)
final sessionsProvider = FutureProvider<List<dynamic>>((ref) async {
  ref.watch(habitsRefreshProvider);
  return habitsApi.getSessions();
});
