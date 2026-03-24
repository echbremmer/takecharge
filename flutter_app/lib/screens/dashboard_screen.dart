import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../api/habits.dart';
import '../main.dart';
import '../providers/habits_provider.dart';
import '../widgets/habit_card.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  List<dynamic> _habits = [];

  Future<void> _persistOrder() async {
    final ids = _habits.map<int>((h) => h['id'] as int).toList();
    try {
      await habitsApi.reorder(ids);
    } finally {
      ref.invalidate(habitsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final habitsAsync = ref.watch(habitsProvider);

    return habitsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Error: $e',
            style: TextStyle(color: AppTheme.onSurfaceMuted)),
      ),
      data: (habits) {
        // Sync local list when the set of habits changes (add/delete/refresh)
        if (_habits.length != habits.length) {
          _habits = List.from(habits);
        }

        final Widget content = _habits.isEmpty
            ? _EmptyDashboard()
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(habitsProvider),
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                  buildDefaultDragHandles: false,
                  itemCount: _habits.length,
                  itemBuilder: (context, i) {
                    final habit = _habits[i] as Map<String, dynamic>;
                    return ReorderableDelayedDragStartListener(
                      key: ValueKey(habit['id']),
                      index: i,
                      child: Padding(
                        padding: EdgeInsets.only(
                          bottom: i < _habits.length - 1 ? 12 : 0,
                        ),
                        child: HabitCard(
                          habit: habit,
                          onTap: () => context.go('/habit/${habit['id']}'),
                        ),
                      ),
                    );
                  },
                  onReorder: (oldIndex, newIndex) {
                    if (newIndex > oldIndex) newIndex--;
                    setState(() {
                      final item = _habits.removeAt(oldIndex);
                      _habits.insert(newIndex, item);
                    });
                    _persistOrder();
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
