import 'dart:async';
import 'package:animated_flip_counter/animated_flip_counter.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../api/habits.dart';
import '../main.dart';
import 'if_phase_badges.dart';
import 'rings_painter.dart';

class HabitCard extends StatelessWidget {
  final Map<String, dynamic> habit;
  final VoidCallback onTap;

  const HabitCard({super.key, required this.habit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final slug = habit['style_slug'] as String? ?? habit['type'] as String? ?? '';
    final variantSlug = habit['variant_slug'] as String? ?? '';
    final isIF    = variantSlug == 'intermittent_fasting';
    final isDaily = slug == 'daily';
    final isTimer = slug == 'timer' && !isIF;
    final isTodo  = slug == 'todo';

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
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
                  // Type badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isIF
                          ? const Color(0xFFE8650A).withOpacity(0.12)
                          : AppTheme.primaryFixed,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      isIF ? 'IF' : slug.toUpperCase(),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        color: isIF ? const Color(0xFFE8650A) : AppTheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, size: 18, color: AppTheme.onSurfaceMuted),
                ],
              ),
              if (isDaily) ...[
                const SizedBox(height: 12),
                _DailyWeekRings(habitId: (habit['id'] as num).toInt()),
              ],
              if (isIF) ...[
                const SizedBox(height: 10),
                _IFCardStatus(habitId: (habit['id'] as num).toInt()),
              ],
              if (isTimer) ...[
                const SizedBox(height: 10),
                _TimerCardStatus(habitId: (habit['id'] as num).toInt()),
              ],
              if (isTodo) ...[
                const SizedBox(height: 10),
                _TodoCardStatus(habitId: (habit['id'] as num).toInt()),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Week rings row ─────────────────────────────────────────────────────────

class _DailyWeekRings extends StatefulWidget {
  final int habitId;
  const _DailyWeekRings({required this.habitId});

  @override
  State<_DailyWeekRings> createState() => _DailyWeekRingsState();
}

class _DailyWeekRingsState extends State<_DailyWeekRings> {
  // logsByDay[dayMs][targetId] = value
  Map<int, Map<int, double>> _logsByDay = {};
  List<Map<String, dynamic>> _targets = [];
  bool _loaded = false;

  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  DateTime get _weekMonday {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: today.weekday - 1));
  }

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
      final targets = await habitsApi.getTargets(widget.habitId);
      final logs = await habitsApi.getLogs(widget.habitId);

      final logsByDay = <int, Map<int, double>>{};
      for (final log in logs) {
        final l = log as Map<String, dynamic>;
        final dayMs = (l['day_ms'] as num).toInt();
        final targetId = (l['target_id'] as num).toInt();
        final value = (l['value'] as num).toDouble();
        logsByDay.putIfAbsent(dayMs, () => <int, double>{})[targetId] = value;
      }

      if (mounted) {
        setState(() {
          _targets = targets.cast<Map<String, dynamic>>();
          _logsByDay = logsByDay;
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  List<double> _progressesFor(int dayMs, bool isFuture) {
    return _targets.map((t) {
      if (isFuture) return 0.0;
      final tid = (t['id'] as num).toInt();
      final tv = (t['target_value'] as num).toDouble();
      final value = _logsByDay[dayMs]?[tid] ?? 0.0;
      return tv > 0 ? (value / tv).clamp(0.0, 1.0) : 0.0;
    }).toList();
  }

  List<bool> get _isLimits =>
      _targets.map((t) => (t['mode'] as String? ?? 'target') == 'limit').toList();

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const SizedBox(height: 44);
    }

    final monday = _weekMonday;
    final todayMs = _todayMs;
    final isLimits = _isLimits;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(7, (i) {
        final day = monday.add(Duration(days: i));
        final dayMs = day.millisecondsSinceEpoch;
        final isFuture = dayMs > todayMs;
        final isToday = dayMs == todayMs;
        final progresses = _progressesFor(dayMs, isFuture);

        return Column(
          children: [
            SizedBox(
              width: 42,
              height: 42,
              child: CustomPaint(
                painter: RingsPainter(
                  progresses: progresses,
                  isLimits: isLimits,
                  isFuture: isFuture,
                  isToday: isToday,
                  ringWidthScale: 0.7,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _dayLabels[i],
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                color: isToday ? AppTheme.primary : AppTheme.onSurfaceMuted,
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        );
      }),
    );
  }
}

// ── Timer card status row ──────────────────────────────────────────────────

class _TimerCardStatus extends StatefulWidget {
  final int habitId;
  const _TimerCardStatus({required this.habitId});

  @override
  State<_TimerCardStatus> createState() => _TimerCardStatusState();
}

class _TimerCardStatusState extends State<_TimerCardStatus> {
  int? _activeStartMs;
  int _weekSessionsMs = 0;
  int? _goalMs;
  bool _loaded = false;
  Timer? _ticker;

  DateTime _weekMonday(DateTime dt) {
    final d = DateTime(dt.year, dt.month, dt.day);
    return d.subtract(Duration(days: d.weekday - 1));
  }

  String _weekKey(DateTime mon) =>
      '${mon.year}-${mon.month.toString().padLeft(2, '0')}-${mon.day.toString().padLeft(2, '0')}';

  int get _elapsedMs => _activeStartMs != null
      ? DateTime.now().millisecondsSinceEpoch - _activeStartMs!
      : 0;

  int get _totalMs => _weekSessionsMs + _elapsedMs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        habitsApi.getActive(widget.habitId),
        habitsApi.getSessions(widget.habitId),
        habitsApi.getGoals(widget.habitId),
      ]);

      final active = results[0] as Map<String, dynamic>?;
      final sessions = results[1] as List<dynamic>;
      final goals = results[2] as List<dynamic>;

      final curKey = _weekKey(_weekMonday(DateTime.now()));
      final weekMs = sessions
          .where((s) =>
              _weekKey(_weekMonday(DateTime.fromMillisecondsSinceEpoch(
                  (s as Map)['start'] as int))) ==
              curKey)
          .fold<int>(0, (sum, s) => sum + ((s as Map)['duration'] as int));

      int? goalMs;
      for (final g in goals) {
        final m = g as Map<String, dynamic>;
        final dt = DateTime.fromMillisecondsSinceEpoch(m['week_start_ms'] as int);
        if (_weekKey(_weekMonday(dt)) == curKey) {
          goalMs = m['value'] as int;
          break;
        }
      }

      if (mounted) {
        setState(() {
          _activeStartMs = active != null ? active['start'] as int : null;
          _weekSessionsMs = weekMs;
          _goalMs = goalMs;
          _loaded = true;
        });
        if (_activeStartMs != null) {
          _ticker?.cancel();
          _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() {});
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  String _fmtCompact(int ms) {
    if (ms < 0) ms = 0;
    final totalMin = ms ~/ 60000;
    final h = totalMin ~/ 60;
    final m = totalMin % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox(height: 20);

    final isActive = _activeStartMs != null;
    final total = _totalMs;
    final goalReached = _goalMs != null && total >= _goalMs!;

    return Row(
      children: [
        // Active indicator dot
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: isActive ? AppTheme.primary : AppTheme.onSurfaceMuted.withAlpha(80),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        // Status: flip clock when active, plain text when not
        if (isActive)
          _FlipClock(elapsedMs: _elapsedMs)
        else
          Text(
            'Inactive',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: AppTheme.onSurfaceMuted,
            ),
          ),
        const Spacer(),
        // Week total
        Text(
          'This week: ${_fmtCompact(total)}',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            color: AppTheme.onSurfaceMuted,
          ),
        ),
        // Goal status
        if (_goalMs != null) ...[
          const SizedBox(width: 6),
          goalReached
              ? Text(
                  '✓',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                )
              : Text(
                  '/ ${_fmtCompact(_goalMs!)}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: AppTheme.onSurfaceMuted,
                  ),
                ),
        ],
      ],
    );
  }
}

// ── Flip clock (HH:MM:SS) ─────────────────────────────────────────────────

class _FlipClock extends StatelessWidget {
  final int elapsedMs;
  const _FlipClock({required this.elapsedMs});

  static const _digitStyle = TextStyle(
    fontFamily: 'monospace',
    fontSize: 26,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    letterSpacing: 1,
  );


  static const _charcoal = Color(0xFF2C2C2C);

  Widget _segment(int value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: _charcoal,
        borderRadius: BorderRadius.circular(5),
      ),
      child: AnimatedFlipCounter(
        value: value,
        wholeDigits: 2,
        textStyle: _digitStyle,
      ),
    );
  }

  Widget _colon() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 6, height: 6, decoration: const BoxDecoration(color: _charcoal, shape: BoxShape.circle)),
            const SizedBox(height: 6),
            Container(width: 6, height: 6, decoration: const BoxDecoration(color: _charcoal, shape: BoxShape.circle)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final totalSec = (elapsedMs / 1000).floor().clamp(0, double.maxFinite.toInt());
    final h = totalSec ~/ 3600;
    final m = (totalSec % 3600) ~/ 60;
    final s = totalSec % 60;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _segment(h),
        _colon(),
        _segment(m),
        _colon(),
        _segment(s),
      ],
    );
  }
}

// ── Todo card status ───────────────────────────────────────────────────────

class _TodoCardStatus extends StatefulWidget {
  final int habitId;
  const _TodoCardStatus({required this.habitId});

  @override
  State<_TodoCardStatus> createState() => _TodoCardStatusState();
}

class _TodoCardStatusState extends State<_TodoCardStatus> {
  List<Map<String, dynamic>> _todos = [];
  int _extraCount = 0;
  final Map<int, Timer> _removalTimers = {};
  final Set<int> _pendingRemoval = {};
  bool _loaded = false;

  int get _currentWeekMs {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: today.weekday - 1)).millisecondsSinceEpoch;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final t in _removalTimers.values) t.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final todos = await habitsApi.getTodos(widget.habitId, weekMs: _currentWeekMs);
      if (mounted) {
        setState(() {
          final unchecked = todos
              .cast<Map<String, dynamic>>()
              .where((t) => !(t['checked'] as bool? ?? false))
              .toList();
          _todos = unchecked.take(4).toList();
          _extraCount = (unchecked.length - 4).clamp(0, 999);
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  void _check(Map<String, dynamic> todo) {
    final id = (todo['id'] as num).toInt();
    setState(() {
      todo['checked'] = true;
      _pendingRemoval.add(id);
    });
    habitsApi.toggleTodo(widget.habitId, id, true);
    _removalTimers[id]?.cancel();
    _removalTimers[id] = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _todos.removeWhere((t) => (t['id'] as num).toInt() == id);
          _pendingRemoval.remove(id);
          _removalTimers.remove(id);
        });
      }
    });
  }

  void _undo(Map<String, dynamic> todo) {
    final id = (todo['id'] as num).toInt();
    _removalTimers[id]?.cancel();
    _removalTimers.remove(id);
    setState(() {
      todo['checked'] = false;
      _pendingRemoval.remove(id);
    });
    habitsApi.toggleTodo(widget.habitId, id, false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox(height: 20);
    if (_todos.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._todos.map((t) {
          final id = (t['id'] as num).toInt();
          final isPending = _pendingRemoval.contains(id);
          return _TodoCardItem(
            todo: t,
            isPending: isPending,
            onTap: isPending ? () => _undo(t) : () => _check(t),
          );
        }),
        if (_extraCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '+ $_extraCount more',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: AppTheme.onSurfaceMuted,
              ),
            ),
          ),
      ],
    );
  }
}

// ── Todo card item ─────────────────────────────────────────────────────────

class _TodoCardItem extends StatelessWidget {
  final Map<String, dynamic> todo;
  final bool isPending;
  final VoidCallback onTap;

  const _TodoCardItem({
    required this.todo,
    required this.isPending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = todo['text'] as String? ?? '';

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(
          children: [
            // Checkbox
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: isPending ? AppTheme.primary : Colors.transparent,
                border: Border.all(
                  color: isPending ? AppTheme.primary : AppTheme.onSurfaceMuted,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(5),
              ),
              child: isPending
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 10),
            // Text
            Expanded(
              child: Text(
                text,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: isPending ? AppTheme.onSurfaceMuted : AppTheme.onSurface,
                  decoration: isPending ? TextDecoration.lineThrough : null,
                  decorationColor: AppTheme.onSurfaceMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── IF card status ─────────────────────────────────────────────────────────

class _IFCardStatus extends StatefulWidget {
  final int habitId;
  const _IFCardStatus({required this.habitId});

  @override
  State<_IFCardStatus> createState() => _IFCardStatusState();
}

class _IFCardStatusState extends State<_IFCardStatus> {
  int? _activeStartMs;
  bool _loaded = false;
  Timer? _ticker;

  int get _elapsedMs => _activeStartMs != null
      ? DateTime.now().millisecondsSinceEpoch - _activeStartMs!
      : 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final active = await habitsApi.getActive(widget.habitId);
      if (mounted) {
        setState(() {
          _activeStartMs = active != null ? active['start'] as int : null;
          _loaded = true;
        });
        if (_activeStartMs != null) {
          _ticker?.cancel();
          _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() {});
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox(height: 20);

    final isActive = _activeStartMs != null;
    final elapsed = _elapsedMs;
    final kcal = (elapsed / 3600000 * 70).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: isActive
                    ? AppTheme.primary
                    : AppTheme.onSurfaceMuted.withAlpha(80),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            if (isActive)
              _FlipClock(elapsedMs: elapsed)
            else
              Text(
                'Ready to fast',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: AppTheme.onSurfaceMuted),
              ),
            const Spacer(),
            if (isActive)
              Text(
                '$kcal kcal',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: AppTheme.onSurfaceMuted),
              ),
          ],
        ),
        if (isActive) ...[
          const SizedBox(height: 6),
          IFPhaseBadges(elapsedMs: elapsed),
        ],
      ],
    );
  }
}

