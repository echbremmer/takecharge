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
        final Widget content = habits.isEmpty
            ? _EmptyDashboard()
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(habitsProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                  itemCount: habits.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final habit = habits[i] as Map<String, dynamic>;
                    return HabitCard(
                      habit: habit,
                      onTap: () => context.go('/habit/${habit['id']}'),
                    );
                  },
                ),
              );

        return Stack(
          children: [
            content,
            Positioned(
              bottom: 24,
              right: 20,
              child: FloatingActionButton(
                onPressed: () => context.go('/add-habit'),
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                elevation: 4,
                shape: const CircleBorder(),
                child: const Icon(Icons.add),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EmptyDashboard extends StatelessWidget {
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
            'Tap + to add your first habit',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 14, color: AppTheme.onSurfaceMuted),
          ),
        ],
      ),
    );
  }
}
