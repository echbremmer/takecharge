import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:animated_flip_counter/animated_flip_counter.dart';

import '../api/habits.dart';
import '../main.dart';
import '../widgets/if_phase_badges.dart';

class TimerHabitScreen extends ConsumerStatefulWidget {
  final int habitId;
  final String habitName;
  final String variantSlug;

  const TimerHabitScreen(
      {super.key, required this.habitId, required this.habitName, this.variantSlug = ''});

  @override
  ConsumerState<TimerHabitScreen> createState() => _TimerHabitScreenState();
}

class _TimerHabitScreenState extends ConsumerState<TimerHabitScreen> {
  // ── Timer state ────────────────────────────────────────────────────────────
  int? _activeStartMs;
  List<dynamic> _sessions = [];
  final Map<String, Map<String, dynamic>> _goals = {}; // weekKey → goal
  bool _loading = true;
  Timer? _ticker;


  // ── History UI state ───────────────────────────────────────────────────────
  String? _openWeekKey;

  // ── Init ───────────────────────────────────────────────────────────────────
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
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        habitsApi.getActive(widget.habitId),
        habitsApi.getSessions(widget.habitId),
        habitsApi.getGoals(widget.habitId),
      ]);
      final active = results[0] as Map<String, dynamic>?;
      final sessions = results[1] as List<dynamic>;
      final goals = results[2] as List<dynamic>;

      _sessions = sessions;
      _goals.clear();
      for (final g in goals) {
        final dt = DateTime.fromMillisecondsSinceEpoch(g['week_start_ms'] as int);
        _goals[_weekKey(_weekMonday(dt))] = g as Map<String, dynamic>;
      }

      if (active != null) {
        _activeStartMs = active['start'] as int;
        _startTicker();
      }

      _initOpenWeek();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _initOpenWeek() {
    if (_sessions.isEmpty) return;
    final curKey = _weekKey(_weekMonday(DateTime.now()));
    final hasCurrentWeek = _sessions.any((s) =>
        _weekKey(_weekMonday(DateTime.fromMillisecondsSinceEpoch(s['start'] as int))) ==
        curKey);
    _openWeekKey = hasCurrentWeek
        ? curKey
        : _weekKey(_weekMonday(
            DateTime.fromMillisecondsSinceEpoch(_sessions.first['start'] as int)));
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  // ── Timer actions ─────────────────────────────────────────────────────────
  Future<void> _toggle() async {
    if (_activeStartMs != null) {
      // Stop
      await habitsApi.stopActive(widget.habitId);
      _ticker?.cancel();
      setState(() {
        _activeStartMs = null;
      });
    } else {
      // Start
      final now = DateTime.now().millisecondsSinceEpoch;
      await habitsApi.startActive(widget.habitId, now);
      setState(() => _activeStartMs = now);
      _startTicker();
    }
    await _load();
  }

  // ── Time picker ───────────────────────────────────────────────────────────
  Future<void> _pickStartTime() async {
    if (_activeStartMs == null) return;
    final current = DateTime.fromMillisecondsSinceEpoch(_activeStartMs!);

    // First pick date (in case fast started yesterday)
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now().subtract(const Duration(days: 7)),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;

    final newStart = DateTime(
      date.year, date.month, date.day, time.hour, time.minute,
    ).millisecondsSinceEpoch;

    if (newStart >= DateTime.now().millisecondsSinceEpoch) return;
    setState(() => _activeStartMs = newStart);
    habitsApi.adjustActive(widget.habitId, newStart);
  }

  void _adjustStart(int deltaMs) {
    if (_activeStartMs == null) return;
    final newStart = _activeStartMs! + deltaMs;
    if (newStart >= DateTime.now().millisecondsSinceEpoch) return;
    setState(() => _activeStartMs = newStart);
    habitsApi.adjustActive(widget.habitId, newStart);
  }

  // ── Week goal ─────────────────────────────────────────────────────────────
  void _showGoalDialog() {
    final goal = _goals[_weekKey(_weekMonday(DateTime.now()))];
    final parts = goal != null
        ? _msToGoalParts(goal['value'] as int)
        : {'d': 0, 'h': 16, 'm': 0};

    int d = parts['d']!, h = parts['h']!, m = parts['m']!;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AppTheme.surfaceCard,
          title: Text('Set week goal',
              style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w700, color: AppTheme.primary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                _GoalInput(label: 'Days', value: d, min: 0, max: 6,
                    onChanged: (v) => setS(() => d = v)),
                const SizedBox(width: 12),
                _GoalInput(label: 'Hours', value: h, min: 0, max: 23,
                    onChanged: (v) => setS(() => h = v)),
                const SizedBox(width: 12),
                _GoalInput(label: 'Min', value: m, min: 0, max: 55, step: 5,
                    onChanged: (v) => setS(() => m = v)),
              ]),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final ms = (d * 86400 + h * 3600 + m * 60) * 1000;
                if (ms <= 0) return;
                final weekStartMs = _weekMonday(DateTime.now()).millisecondsSinceEpoch;
                final result = await habitsApi.setGoal(
                    widget.habitId, weekStartMs, ms);
                setState(() => _goals[_weekKey(_weekMonday(DateTime.now()))] = result);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _formatDuration(int ms) {
    if (ms < 0) ms = 0;
    final total = ms ~/ 1000;
    final h = (total ~/ 3600).toString().padLeft(2, '0');
    final m = ((total % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatGoalTime(int ms) {
    final p = _msToGoalParts(ms);
    final parts = <String>[];
    if (p['d']! > 0) parts.add('${p['d']}d');
    if (p['h']! > 0) parts.add('${p['h']}h');
    if (p['m']! > 0) parts.add('${p['m']}m');
    return parts.isNotEmpty ? parts.join(' ') : '0m';
  }

  Map<String, int> _msToGoalParts(int ms) {
    final totalMin = (ms / 60000).round();
    final d = totalMin ~/ 1440;
    final h = (totalMin % 1440) ~/ 60;
    var m = ((totalMin % 60) / 5).round() * 5;
    if (m >= 60) m = 55;
    return {'d': d, 'h': h, 'm': m};
  }

  DateTime _weekMonday(DateTime dt) {
    return DateTime(dt.year, dt.month, dt.day - (dt.weekday - 1));
  }

  String _weekKey(DateTime mon) =>
      '${mon.year}-${mon.month.toString().padLeft(2, '0')}-${mon.day.toString().padLeft(2, '0')}';

  String _formatTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatDate(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${days[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}';
  }

  String _weekRangeLabel(DateTime mon) {
    final sun = mon.add(const Duration(days: 6));
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[mon.month - 1]} ${mon.day} – ${months[sun.month - 1]} ${sun.day}';
  }

  double _estimateWaterLoss(int ms) =>
      1200 * (1 - exp(-(ms / 3600000) / 12));

  double _estimateFatLoss(int ms) => (ms / 3600000) * 10.8;

  String _formatWeight(double g) =>
      g >= 1000 ? '${(g / 1000).toStringAsFixed(2)} kg' : '${g.round()} g';

  // ── Current week stats ─────────────────────────────────────────────────────
  int get _curWeekSessionsMs {
    final curKey = _weekKey(_weekMonday(DateTime.now()));
    return _sessions
        .where((s) =>
            _weekKey(_weekMonday(
                DateTime.fromMillisecondsSinceEpoch(s['start'] as int))) ==
            curKey)
        .fold(0, (sum, s) => sum + (s['duration'] as int));
  }

  int get _elapsedMs => _activeStartMs != null
      ? DateTime.now().millisecondsSinceEpoch - _activeStartMs!
      : 0;

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final isActive = _activeStartMs != null;
    final curKey = _weekKey(_weekMonday(DateTime.now()));
    final weekGoal = _goals[curKey];
    final totalMs = _curWeekSessionsMs + _elapsedMs;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 80),
      children: [
        // Habit name
        Text(
          widget.habitName,
          style: GoogleFonts.manrope(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
            color: AppTheme.onSurfaceMuted,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),

        // ── Timer section ────────────────────────────────────────────────────
        Column(
          children: [
            // Status
            Text(
              isActive ? 'Active' : 'Not active',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
                letterSpacing: 0.3,
                color: isActive ? AppTheme.primary : AppTheme.onSurfaceMuted,
              ),
            ),
            const SizedBox(height: 4),

            // Timer display — flip clock style
            _BigFlipClock(elapsedMs: _elapsedMs),

            // Start time + inline edit button
            if (isActive) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _pickStartTime,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Started at ${_formatTime(_activeStartMs!)}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: AppTheme.onSurfaceMuted,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.edit_outlined,
                        size: 14, color: AppTheme.onSurfaceMuted),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 28),

            // Start / Stop button
            _GradientButton(
              label: isActive ? 'Stop' : 'Start',
              isStop: isActive,
              onTap: _toggle,
            ),
          ],
        ),

        const SizedBox(height: 28),

        // ── IF stats panel (only for IF variant) ─────────────────────────────
        if (widget.variantSlug == 'intermittent_fasting') ...[
          _IFStatsPanel(elapsedMs: _elapsedMs, isActive: isActive),
          const SizedBox(height: 16),
        ],

        // ── Week goal card ───────────────────────────────────────────────────
        _WeekGoalCard(
          goal: weekGoal,
          totalMs: totalMs,
          formatGoalTime: _formatGoalTime,
          onEdit: _showGoalDialog,
        ),

        const SizedBox(height: 32),

        // ── History ──────────────────────────────────────────────────────────
        Text(
          'HISTORY',
          style: GoogleFonts.manrope(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
            color: AppTheme.onSurfaceMuted,
          ),
        ),
        const SizedBox(height: 12),

        if (_sessions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No sessions recorded yet.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: AppTheme.onSurfaceMuted,
              ),
            ),
          )
        else
          ..._buildHistory(),
      ],
    );
  }

  // ── History builder ───────────────────────────────────────────────────────
  List<Widget> _buildHistory() {
    final curKey = _weekKey(_weekMonday(DateTime.now()));

    // Group sessions by week
    final weekMap = <String, Map<String, dynamic>>{};
    for (final s in _sessions) {
      final dt = DateTime.fromMillisecondsSinceEpoch(s['start'] as int);
      final key = _weekKey(_weekMonday(dt));
      weekMap.putIfAbsent(key, () => {'mon': _weekMonday(dt), 'sessions': []});
      (weekMap[key]!['sessions'] as List).add(s);
    }

    if (_openWeekKey == null || !weekMap.containsKey(_openWeekKey)) {
      _openWeekKey = weekMap.containsKey(curKey)
          ? curKey
          : weekMap.keys.first;
    }

    return weekMap.entries.map((entry) {
      final key = entry.key;
      final mon = entry.value['mon'] as DateTime;
      final ws = entry.value['sessions'] as List;
      final isCurrent = key == curKey;
      final isOpen = key == _openWeekKey;
      final totalMs = ws.fold<int>(0, (sum, s) => sum + (s['duration'] as int));
      final count = ws.length;
      final label = isCurrent ? 'This week' : _weekRangeLabel(mon);
      final summary =
          '$count session${count != 1 ? 's' : ''} · ${_formatDuration(totalMs)}';
      final weekGoal = _goals[key];

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Week header (collapsible)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _openWeekKey = isOpen ? null : key),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceNest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Text(
                    label,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight:
                          isCurrent ? FontWeight.w600 : FontWeight.w500,
                      color: isCurrent
                          ? AppTheme.primary
                          : AppTheme.onSurfaceMuted,
                    ),
                  ),
                  const Spacer(),
                  Text(summary,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: AppTheme.onSurfaceMuted)),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: isOpen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down,
                        size: 18, color: AppTheme.onSurfaceMuted),
                  ),
                ],
              ),
            ),
          ),

          // Week content
          if (isOpen) ...[
            const SizedBox(height: 8),
            // Past-week goal row
            if (!isCurrent && weekGoal != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceNest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Text('Time goal',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            letterSpacing: 0.8,
                            color: AppTheme.onSurfaceMuted)),
                    const SizedBox(width: 8),
                    Text(_formatGoalTime(weekGoal['value'] as int),
                        style: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.onSurface)),
                    const Spacer(),
                    Text(
                        '${_formatDuration(totalMs)} achieved',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.primary)),
                  ],
                ),
              ),
            // Sessions
            ...ws.map((s) => _SessionCard(
                  session: s,
                  onDelete: () async {
                    await habitsApi.deleteSession(
                        widget.habitId, s['id'] as int);
                    await _load();
                  },
                  formatDuration: _formatDuration,
                  formatDate: _formatDate,
                  formatTime: _formatTime,
                  formatWeight: _formatWeight,
                  estimateWater: _estimateWaterLoss,
                  estimateFat: _estimateFatLoss,
                )),
          ],
          const SizedBox(height: 8),
        ],
      );
    }).toList();
  }
}

// ── Gradient start/stop button ────────────────────────────────────────────

class _GradientButton extends StatelessWidget {
  final String label;
  final bool isStop;
  final VoidCallback onTap;

  const _GradientButton(
      {required this.label, required this.isStop, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = isStop
        ? const [Color(0xFF8B4A47), Color(0xFFC47F7C)]
        : [AppTheme.primary, AppTheme.primaryCont];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 48),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: (isStop
                  ? const Color(0xFF8B4A47)
                  : AppTheme.primary).withOpacity(0.28),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Week goal card ────────────────────────────────────────────────────────

class _WeekGoalCard extends StatelessWidget {
  final Map<String, dynamic>? goal;
  final int totalMs;
  final String Function(int) formatGoalTime;
  final VoidCallback onEdit;

  const _WeekGoalCard({
    required this.goal,
    required this.totalMs,
    required this.formatGoalTime,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final goalValue = goal?['value'] as int?;
    final leftMs =
        goalValue != null ? max(0, goalValue - totalMs) : null;
    final reached = leftMs == 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceNest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Text('Week goal',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: AppTheme.onSurfaceMuted)),
          const SizedBox(width: 10),
          if (goalValue != null) ...[
            Text(formatGoalTime(goalValue),
                style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.onSurface)),
            const SizedBox(width: 8),
            Text(
              reached ? '✓ Goal reached' : '${formatGoalTime(leftMs!)} left',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: reached ? AppTheme.primary : AppTheme.onSurfaceMuted),
            ),
          ] else
            Text('Set a goal…',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: AppTheme.onSurfaceMuted)),
          const Spacer(),
          GestureDetector(
            onTap: onEdit,
            child: const Icon(Icons.edit_outlined,
                size: 18, color: AppTheme.onSurfaceMuted),
          ),
        ],
      ),
    );
  }
}

// ── Session card ──────────────────────────────────────────────────────────

class _SessionCard extends StatelessWidget {
  final dynamic session;
  final VoidCallback onDelete;
  final String Function(int) formatDuration;
  final String Function(int) formatDate;
  final String Function(int) formatTime;
  final String Function(double) formatWeight;
  final double Function(int) estimateWater;
  final double Function(int) estimateFat;

  const _SessionCard({
    required this.session,
    required this.onDelete,
    required this.formatDuration,
    required this.formatDate,
    required this.formatTime,
    required this.formatWeight,
    required this.estimateWater,
    required this.estimateFat,
  });

  @override
  Widget build(BuildContext context) {
    final s = session as Map<String, dynamic>;
    final startMs = s['start'] as int;
    final endMs = s['end'] as int;
    final duration = s['duration'] as int;
    final water = estimateWater(duration);
    final fat = estimateFat(duration);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0855624D), blurRadius: 24, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(formatDate(startMs),
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13, color: AppTheme.onSurfaceMuted)),
                  Text(
                      '${formatTime(startMs)} – ${formatTime(endMs)}',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: AppTheme.onSurfaceMuted)),
                ],
              ),
              const Spacer(),
              Text(formatDuration(duration),
                  style: GoogleFonts.manrope(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.onSurface)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _confirmDelete(context),
                child: const Icon(Icons.close,
                    size: 18, color: AppTheme.onSurfaceMuted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _EstimateChip(
                  label: 'Water weight',
                  value: formatWeight(water),
                  valueColor: const Color(0xFF4A8FA8)),
              const SizedBox(width: 10),
              _EstimateChip(
                  label: 'Fat loss',
                  value: formatWeight(fat),
                  valueColor: AppTheme.secondary),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surfaceCard,
        title: const Text('Delete session?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(
                foregroundColor: AppTheme.secondary),
            onPressed: () {
              Navigator.pop(context);
              onDelete();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _EstimateChip extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _EstimateChip(
      {required this.label, required this.value, required this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceNest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    letterSpacing: 0.5,
                    color: AppTheme.onSurfaceMuted)),
            const SizedBox(height: 2),
            Text(value,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: valueColor)),
          ],
        ),
      ),
    );
  }
}

// ── Goal input spinner ────────────────────────────────────────────────────

class _GoalInput extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  const _GoalInput({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.step = 1,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11, color: AppTheme.onSurfaceMuted)),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: value - step >= min
                    ? () => onChanged(value - step)
                    : null,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.remove,
                      size: 16,
                      color: value - step >= min
                          ? AppTheme.primary
                          : AppTheme.onSurfaceMuted),
                ),
              ),
              Text('$value',
                  style: GoogleFonts.manrope(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.onSurface)),
              GestureDetector(
                onTap: value + step <= max
                    ? () => onChanged(value + step)
                    : null,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.add,
                      size: 16,
                      color: value + step <= max
                          ? AppTheme.primary
                          : AppTheme.onSurfaceMuted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── IF stats panel ─────────────────────────────────────────────────────────

class _IFStatsPanel extends StatelessWidget {
  final int elapsedMs;
  final bool isActive;

  static const _targetMs = 16 * 3600 * 1000;

  const _IFStatsPanel({required this.elapsedMs, required this.isActive});

  double _estimateWater(int ms) =>
      1200 * (1 - exp(-(ms / 3600000) / 12));

  String _formatWeight(double g) =>
      g >= 1000 ? '${(g / 1000).toStringAsFixed(2)} kg' : '${g.round()} g';

  @override
  Widget build(BuildContext context) {
    if (!isActive) return const SizedBox.shrink();

    final progress = (elapsedMs / _targetMs).clamp(0.0, 1.0);
    final kcal = (elapsedMs / 3600000 * 70).round();
    final water = _estimateWater(elapsedMs);
    final h = elapsedMs ~/ 3600000;
    final m = (elapsedMs % 3600000) ~/ 60000;
    final targetH = _targetMs ~/ 3600000;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceNest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'THIS FAST',
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                  color: AppTheme.onSurfaceMuted,
                ),
              ),
              const Spacer(),
              Text(
                '${h}h ${m.toString().padLeft(2, '0')}m / ${targetH}h',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: AppTheme.onSurfaceMuted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppTheme.surfaceCard,
              valueColor: AlwaysStoppedAnimation<Color>(
                  progress >= 1.0 ? AppTheme.primary : const Color(0xFFE8650A)),
            ),
          ),
          const SizedBox(height: 12),
          IFPhaseBadges(elapsedMs: elapsedMs),
          const SizedBox(height: 12),
          Row(
            children: [
              _EstimateChip(
                label: 'Kcal burned',
                value: '$kcal kcal',
                valueColor: AppTheme.secondary,
              ),
              const SizedBox(width: 10),
              _EstimateChip(
                label: 'Water weight',
                value: _formatWeight(water),
                valueColor: const Color(0xFF4A8FA8),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


// ── Big flip clock (timer screen) ────────────────────────────────────────────

class _BigFlipClock extends StatelessWidget {
  final int elapsedMs;
  const _BigFlipClock({required this.elapsedMs});

  static const _charcoal = Color(0xFF2C2C2C);
  static const _digitStyle = TextStyle(
    fontFamily: 'monospace',
    fontSize: 46,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    letterSpacing: 1,
  );

  Widget _segment(int value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _charcoal,
          borderRadius: BorderRadius.circular(8),
        ),
        child: AnimatedFlipCounter(
          value: value,
          wholeDigits: 2,
          textStyle: _digitStyle,
        ),
      );

  Widget _colon() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: _charcoal, shape: BoxShape.circle)),
            const SizedBox(height: 8),
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: _charcoal, shape: BoxShape.circle)),
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
