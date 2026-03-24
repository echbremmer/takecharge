import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../providers/habits_provider.dart';
import '../widgets/habit_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habitsAsync = ref.watch(habitsProvider);

    return habitsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Error: $e',
            style: TextStyle(color: AppTheme.onSurfaceMuted)),
      ),
      data: (habits) {
        if (habits.isEmpty) {
          return _EmptyDashboard(onAdd: () => context.go('/add-habit'));
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(habitsProvider),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            itemCount: habits.length + 1, // +1 for add button at bottom
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              if (i == habits.length) {
                return _AddHabitButton(
                    onTap: () => context.go('/add-habit'));
              }
              final habit = habits[i] as Map<String, dynamic>;
              return HabitCard(
                habit: habit,
                onTap: () => context.go('/habit/${habit['id']}'),
              );
            },
          ),
        );
      },
    );
  }

}

class _EmptyDashboard extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyDashboard({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.track_changes_outlined,
              size: 56, color: AppTheme.onSurfaceMuted),
          const SizedBox(height: 16),
          Text(
            'No habits yet',
            style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.onSurface),
          ),
          const SizedBox(height: 8),
          Text(
            'Add your first habit below',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 14, color: AppTheme.onSurfaceMuted),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add habit'),
          ),
        ],
      ),
    );
  }
}

class _AddHabitButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddHabitButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.add, size: 18, color: AppTheme.primary),
      label: Text('Add habit',
          style: GoogleFonts.plusJakartaSans(
              color: AppTheme.primary, fontWeight: FontWeight.w600)),
    );
  }
}

