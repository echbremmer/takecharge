import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../main.dart';
import '../providers/habits_provider.dart';

/// Placeholder — will be replaced with per-type habit screens
/// (TimerHabitScreen, DailyHabitScreen, TodoHabitScreen)
class HabitScreen extends ConsumerWidget {
  final int habitId;
  const HabitScreen({super.key, required this.habitId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habits = ref.watch(habitsProvider);

    return habits.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Error: $e')),
      ),
      data: (list) {
        final habit = list.firstWhere(
          (h) => h['id'] == habitId,
          orElse: () => null,
        );

        if (habit == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Habit')),
            body: const Center(child: Text('Habit not found')),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(habit['name'] ?? 'Habit'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _confirmDelete(context, ref, habit),
              ),
            ],
          ),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.construction, size: 64, color: AppTheme.sageLight),
                const SizedBox(height: 16),
                Text(
                  'Habit screen coming soon',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppTheme.textMid,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Type: ${habit['type']}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textLight,
                      ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmDelete(
      BuildContext context, WidgetRef ref, Map<String, dynamic> habit) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete habit?'),
        content: Text('Delete "${habit['name']}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              // TODO: call habitsApi.delete(habit['id'])
              ref.invalidate(habitsProvider);
              if (context.mounted) context.go('/');
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
