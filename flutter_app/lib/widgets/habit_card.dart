import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../api/habits.dart';
import '../main.dart';
import 'rings_painter.dart';

class HabitCard extends StatelessWidget {
  final Map<String, dynamic> habit;
  final VoidCallback onTap;

  const HabitCard({super.key, required this.habit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final slug = habit['style_slug'] as String? ?? habit['type'] as String? ?? '';
    final type = slug.toUpperCase();
    final isDaily = slug == 'daily';

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // Habit name
              Expanded(
                child: Text(
                  habit['name'] ?? '',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.onSurfaceVar,
                  ),
                ),
              ),
              // Today rings for daily habits
              if (isDaily) ...[
                _DailyTodayRings(habitId: (habit['id'] as num).toInt()),
                const SizedBox(width: 10),
              ],
              // Type badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryFixed,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  type,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: AppTheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, size: 18, color: AppTheme.onSurfaceMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _DailyTodayRings extends StatefulWidget {
  final int habitId;
  const _DailyTodayRings({required this.habitId});

  @override
  State<_DailyTodayRings> createState() => _DailyTodayRingsState();
}

class _DailyTodayRingsState extends State<_DailyTodayRings> {
  List<double> _progresses = [];
  List<bool> _isLimits = [];
  bool _loaded = false;

  int get _todayMs {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final todayMs = _todayMs;
      final targets = await habitsApi.getTargets(widget.habitId);
      final logs = await habitsApi.getLogs(widget.habitId, dayMs: todayMs);

      // Build targetId → value map from today's logs
      final logMap = <int, double>{};
      for (final log in logs) {
        final l = log as Map<String, dynamic>;
        logMap[(l['target_id'] as num).toInt()] =
            (l['value'] as num).toDouble();
      }

      final progresses = <double>[];
      final isLimits = <bool>[];

      for (final t in targets) {
        final m = t as Map<String, dynamic>;
        final tid = (m['id'] as num).toInt();
        final tv = (m['target_value'] as num).toDouble();
        final mode = m['mode'] as String? ?? 'target';
        final value = logMap[tid] ?? 0.0;

        final prog = tv > 0 ? (value / tv).clamp(0.0, 1.0) : 0.0;
        progresses.add(prog);
        isLimits.add(mode == 'limit');
      }

      if (mounted) {
        setState(() {
          _progresses = progresses;
          _isLimits = isLimits;
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const SizedBox(width: 36, height: 36);
    }
    return SizedBox(
      width: 36,
      height: 36,
      child: CustomPaint(
        painter: RingsPainter(
          progresses: _progresses,
          isLimits: _isLimits,
          isFuture: false,
          isToday: true,
        ),
      ),
    );
  }
}
