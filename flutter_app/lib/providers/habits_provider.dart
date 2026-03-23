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

// These providers require a habitId — use FutureProvider.family
// or call habitsApi directly in the screen (as TimerHabitScreen does).

final dailyTargetsProvider =
    FutureProvider.family<List<dynamic>, int>((ref, habitId) async {
  ref.watch(habitsRefreshProvider);
  return habitsApi.getTargets(habitId);
});

final dailyLogsProvider =
    FutureProvider.family<List<dynamic>, int>((ref, habitId) async {
  ref.watch(habitsRefreshProvider);
  return habitsApi.getLogs(habitId);
});
