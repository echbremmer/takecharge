import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../providers/habits_provider.dart';
import 'daily_habit_screen.dart';
import 'timer_habit_screen.dart';
import 'todo_habit_screen.dart';

class HabitScreen extends ConsumerWidget {
  final int habitId;
  const HabitScreen({super.key, required this.habitId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habitsAsync = ref.watch(habitsProvider);

    return habitsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Error: $e',
            style: const TextStyle(color: AppTheme.onSurfaceMuted)),
      ),
      data: (list) {
        final habit = list.cast<Map<String, dynamic>?>().firstWhere(
              (h) => h?['id'] == habitId,
              orElse: () => null,
            );

        if (habit == null) {
          return Center(
            child: Text('Habit not found',
                style: GoogleFonts.plusJakartaSans(
                    color: AppTheme.onSurfaceMuted)),
          );
        }

        final type = habit['style_slug'] as String? ?? habit['type'] as String? ?? '';
        final name = habit['name'] as String? ?? '';

        switch (type) {
          case 'timer':
            return TimerHabitScreen(habitId: habitId, habitName: name);
          case 'daily':
            return DailyHabitScreen(habitId: habitId, habitName: name);
          case 'todo':
            return TodoHabitScreen(habitId: habitId, habitName: name);

          default:
            // Daily and Todo screens — coming soon
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.construction_outlined,
                      size: 48, color: AppTheme.onSurfaceMuted),
                  const SizedBox(height: 16),
                  Text(name,
                      style: GoogleFonts.manrope(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.onSurface)),
                  const SizedBox(height: 8),
                  Text(
                    '${type.isEmpty ? 'This' : '${type[0].toUpperCase()}${type.substring(1)}'} habit screen coming soon',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14, color: AppTheme.onSurfaceMuted),
                  ),
                ],
              ),
            );
        }
      },
    );
  }
}
