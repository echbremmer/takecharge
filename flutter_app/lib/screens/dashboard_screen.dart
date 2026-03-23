import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../api/habits.dart';
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
          return _EmptyDashboard(onAdd: () => _showAddSheet(context, ref));
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
                    onTap: () => _showAddSheet(context, ref));
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

  void _showAddSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddHabitSheet(ref: ref),
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

class _AddHabitSheet extends ConsumerStatefulWidget {
  final WidgetRef ref;
  const _AddHabitSheet({required this.ref});

  @override
  ConsumerState<_AddHabitSheet> createState() => _AddHabitSheetState();
}

class _AddHabitSheetState extends ConsumerState<_AddHabitSheet> {
  final _nameCtrl = TextEditingController();
  String _type = 'timer';
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      await habitsApi.create(name, _type);
      ref.invalidate(habitsProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add Habit',
              style: GoogleFonts.manrope(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary)),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              hintText: 'Habit name',
              hintStyle: TextStyle(color: AppTheme.onSurfaceMuted),
            ),
            autofocus: true,
          ),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'timer', label: Text('Timer')),
              ButtonSegment(value: 'daily', label: Text('Daily')),
              ButtonSegment(value: 'todo', label: Text('Todo')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: const TextStyle(color: AppTheme.secondary, fontSize: 13)),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _loading ? null : _create,
              child: _loading
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Create'),
            ),
          ),
        ],
      ),
    );
  }
}
