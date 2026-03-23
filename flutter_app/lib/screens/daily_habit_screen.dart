import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../api/habits.dart';
import '../main.dart';

class DailyHabitScreen extends StatefulWidget {
  final int habitId;
  final String habitName;

  const DailyHabitScreen(
      {super.key, required this.habitId, required this.habitName});

  @override
  State<DailyHabitScreen> createState() => _DailyHabitScreenState();
}

class _DailyHabitScreenState extends State<DailyHabitScreen> {
  List<Map<String, dynamic>> _targets = [];
  // logsByDay[dayMs][targetId] = value
  Map<int, Map<int, double>> _logsByDay = {};
  bool _loading = true;
  String? _error;
  final Set<String> _expandedWeeks = {};

  // Add-target form
  bool _showAddForm = false;
  final _nameCtrl = TextEditingController();
  final _unitCtrl = TextEditingController();
  final _goalCtrl = TextEditingController();
  final _stepCtrl = TextEditingController(text: '1');
  bool _isLimit = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _unitCtrl.dispose();
    _goalCtrl.dispose();
    _stepCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  int get _todayMs {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
  }

  DateTime _weekMonday(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return d.subtract(Duration(days: d.weekday - 1));
  }

  String _weekKey(DateTime monday) =>
      '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';

  double _getValue(int dayMs, int targetId) =>
      _logsByDay[dayMs]?[targetId] ?? 0.0;

  // Progress 0..1, capped at 1
  double _progress(Map<String, dynamic> t, double value) {
    final tv = (t['target_value'] as num).toDouble();
    if (tv <= 0) return 0;
    return (value / tv).clamp(0.0, 1.0);
  }

  bool _isDone(Map<String, dynamic> t, double value) {
    final mode = t['mode'] as String? ?? 'target';
    final tv = (t['target_value'] as num).toDouble();
    return mode == 'limit' ? value <= tv && value > 0 : value >= tv;
  }

  bool _isOverLimit(Map<String, dynamic> t, double value) {
    final mode = t['mode'] as String? ?? 'target';
    final tv = (t['target_value'] as num).toDouble();
    return mode == 'limit' && value > tv;
  }

  bool _isAllDone(int dayMs) {
    if (_targets.isEmpty) return false;
    return _targets.every((t) {
      final mode = t['mode'] as String? ?? 'target';
      if (mode == 'limit') return true; // limits don't block completion
      return _isDone(t, _getValue(dayMs, (t['id'] as num).toInt()));
    });
  }

  bool _hasAnyData(int dayMs) =>
      _targets.any((t) => _getValue(dayMs, (t['id'] as num).toInt()) > 0);

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
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

      setState(() {
        _targets = targets.cast<Map<String, dynamic>>();
        _logsByDay = logsByDay;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _setLog(int targetId, int dayMs, double newValue) async {
    final prev = _logsByDay[dayMs]?[targetId] ?? 0.0;
    setState(() {
      _logsByDay.putIfAbsent(dayMs, () => <int, double>{})[targetId] = newValue;
    });
    try {
      await habitsApi.logValue(widget.habitId, targetId, dayMs, newValue);
    } catch (_) {
      setState(() {
        _logsByDay.putIfAbsent(dayMs, () => <int, double>{})[targetId] = prev;
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
          child: Text('Error: $_error',
              style: const TextStyle(color: AppTheme.onSurfaceMuted)));
    }

    final today = DateTime.now();
    final todayMs = _todayMs;
    final weekStart = _weekMonday(today);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 80),
      children: [
        // ── Today ──────────────────────────────────────────────────────────
        _SectionLabel('TODAY'),
        const SizedBox(height: 10),
        if (_targets.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No targets configured yet. Add one below.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14, color: AppTheme.onSurfaceMuted),
            ),
          )
        else
          ..._targets.map((t) {
            final tid = (t['id'] as num).toInt();
            final value = _getValue(todayMs, tid);
            final step = (t['step'] as num).toDouble();
            return _TargetCard(
              target: t,
              value: value,
              progress: _progress(t, value),
              isDone: _isDone(t, value),
              isOverLimit: _isOverLimit(t, value),
              onIncrement: () => _setLog(tid, todayMs, value + step),
              onDecrement: value > 0
                  ? () => _setLog(tid, todayMs, (value - step).clamp(0, double.infinity))
                  : null,
            );
          }),

        const SizedBox(height: 28),

        // ── This week ──────────────────────────────────────────────────────
        _SectionLabel('THIS WEEK'),
        const SizedBox(height: 12),
        _WeekGrid(
          weekStart: weekStart,
          targets: _targets,
          getValue: _getValue,
          progress: _progress,
          isAllDone: _isAllDone,
          hasAnyData: _hasAnyData,
        ),

        const SizedBox(height: 28),

        // ── History ────────────────────────────────────────────────────────
        ..._buildHistory(weekStart),

        const SizedBox(height: 28),

        // ── Manage targets ─────────────────────────────────────────────────
        _buildManageSection(),
      ],
    );
  }

  // ── History ───────────────────────────────────────────────────────────────

  List<Widget> _buildHistory(DateTime currentWeekStart) {
    final weekStarts = <DateTime>{};
    for (final dayMs in _logsByDay.keys) {
      final day = DateTime.fromMillisecondsSinceEpoch(dayMs);
      weekStarts.add(_weekMonday(day));
    }
    weekStarts
        .removeWhere((w) => !w.isBefore(currentWeekStart));

    if (weekStarts.isEmpty) return [];

    final sorted = weekStarts.toList()..sort((a, b) => b.compareTo(a));

    return [
      _SectionLabel('HISTORY'),
      const SizedBox(height: 12),
      ...sorted.map((monday) {
        final key = _weekKey(monday);
        final isExpanded = _expandedWeeks.contains(key);
        final sunday = monday.add(const Duration(days: 6));

        int completeDays = 0;
        bool hasPartial = false;
        for (int i = 0; i < 7; i++) {
          final dayMs =
              monday.add(Duration(days: i)).millisecondsSinceEpoch;
          if (_hasAnyData(dayMs)) {
            if (_isAllDone(dayMs)) {
              completeDays++;
            } else {
              hasPartial = true;
            }
          }
        }

        final dotColor = completeDays == 7
            ? AppTheme.primary
            : (completeDays > 0 || hasPartial)
                ? const Color(0xFFE8982E)
                : Colors.transparent;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: AppTheme.surfaceCard,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x0855624D),
                  blurRadius: 24,
                  offset: Offset(0, 4))
            ],
          ),
          child: Column(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() {
                  if (isExpanded) {
                    _expandedWeeks.remove(key);
                  } else {
                    _expandedWeeks.add(key);
                  }
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: dotColor != Colors.transparent
                              ? dotColor
                              : const Color(0x2055624D),
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${_fmtDate(monday)} – ${_fmtDate(sunday)}',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.onSurface),
                        ),
                      ),
                      if (completeDays > 0)
                        Text(
                          completeDays == 7
                              ? 'Full week'
                              : '$completeDays day${completeDays == 1 ? '' : 's'}',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: AppTheme.onSurfaceMuted),
                        ),
                      const SizedBox(width: 8),
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(Icons.expand_more,
                            size: 18, color: AppTheme.onSurfaceMuted),
                      ),
                    ],
                  ),
                ),
              ),
              if (isExpanded) ...[
                const Divider(height: 1, color: Color(0x1A55624D)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: _WeekGrid(
                    weekStart: monday,
                    targets: _targets,
                    getValue: _getValue,
                    progress: _progress,
                    isAllDone: _isAllDone,
                    hasAnyData: _hasAnyData,
                    compact: true,
                  ),
                ),
              ],
            ],
          ),
        );
      }),
      const SizedBox(height: 0),
    ];
  }

  // ── Manage section ────────────────────────────────────────────────────────

  Widget _buildManageSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceNest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('TARGETS',
              style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                  color: AppTheme.onSurfaceMuted)),
          const SizedBox(height: 12),
          ..._targets.map((t) => _TargetManageRow(
                target: t,
                onDelete: () => _confirmDeleteTarget(t),
              )),
          if (_targets.length < 4) ...[
            if (_targets.isNotEmpty) const SizedBox(height: 4),
            if (!_showAddForm)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _showAddForm = true),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add target'),
                  style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      padding: EdgeInsets.zero),
                ),
              )
            else
              _buildAddForm(),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDeleteTarget(Map<String, dynamic> t) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surfaceCard,
        title: Text('Delete target?',
            style: GoogleFonts.manrope(
                fontWeight: FontWeight.w700, color: AppTheme.onSurface)),
        content: Text(
            'Delete "${t['name']}" and all its logs? This cannot be undone.',
            style:
                GoogleFonts.plusJakartaSans(color: AppTheme.onSurfaceVar)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppTheme.secondary),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await habitsApi.deleteTarget(
          widget.habitId, (t['id'] as num).toInt());
      _load();
    }
  }

  Widget _buildAddForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        _formField(_nameCtrl, 'Name'),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _formField(_unitCtrl, 'Unit (optional)')),
          const SizedBox(width: 8),
          Expanded(
              child:
                  _formField(_goalCtrl, 'Goal value', numeric: true)),
          const SizedBox(width: 8),
          Expanded(
              child: _formField(_stepCtrl, 'Step', numeric: true)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Checkbox(
            value: _isLimit,
            onChanged: (v) => setState(() => _isLimit = v ?? false),
            activeColor: AppTheme.primary,
          ),
          Expanded(
            child: Text('This is a limit (staying under is good)',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: AppTheme.onSurfaceVar)),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => setState(() => _showAddForm = false),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
              ),
              onPressed: _saving ? null : _addTarget,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Add'),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _formField(TextEditingController ctrl, String hint,
      {bool numeric = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      style: GoogleFonts.plusJakartaSans(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            TextStyle(color: AppTheme.onSurfaceMuted, fontSize: 13),
        filled: true,
        fillColor: AppTheme.surfaceCard,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none),
      ),
    );
  }

  Future<void> _addTarget() async {
    final name = _nameCtrl.text.trim();
    final targetValue = double.tryParse(_goalCtrl.text.trim()) ?? 0;
    final step = double.tryParse(_stepCtrl.text.trim()) ?? 1;
    if (name.isEmpty || targetValue <= 0) return;

    setState(() => _saving = true);
    try {
      await habitsApi.createTarget(widget.habitId, {
        'name': name,
        'unit': _unitCtrl.text.trim(),
        'target_value': targetValue,
        'step': step,
        'mode': _isLimit ? 'limit' : 'target',
      });
      _nameCtrl.clear();
      _unitCtrl.clear();
      _goalCtrl.clear();
      _stepCtrl.text = '1';
      setState(() {
        _showAddForm = false;
        _saving = false;
      });
      _load();
    } catch (_) {
      setState(() => _saving = false);
    }
  }

  // ── Formatting ────────────────────────────────────────────────────────────

  String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}';
  }
}

// ── Section label ──────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.manrope(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
        color: AppTheme.onSurfaceMuted,
      ),
    );
  }
}

// ── Target card (today) ────────────────────────────────────────────────────

class _TargetCard extends StatelessWidget {
  final Map<String, dynamic> target;
  final double value;
  final double progress;
  final bool isDone;
  final bool isOverLimit;
  final VoidCallback onIncrement;
  final VoidCallback? onDecrement;

  const _TargetCard({
    required this.target,
    required this.value,
    required this.progress,
    required this.isDone,
    required this.isOverLimit,
    required this.onIncrement,
    this.onDecrement,
  });

  @override
  Widget build(BuildContext context) {
    final name = target['name'] as String? ?? '';
    final unit = target['unit'] as String? ?? '';
    final targetValue = (target['target_value'] as num).toDouble();
    final mode = target['mode'] as String? ?? 'target';

    // Colors
    final Color barColor;
    final Color statusColor;
    if (isOverLimit) {
      barColor = const Color(0xFFD32F2F);
      statusColor = const Color(0xFFD32F2F);
    } else if (isDone) {
      barColor = AppTheme.primary;
      statusColor = AppTheme.primary;
    } else {
      barColor = const Color(0xFFE8982E);
      statusColor = const Color(0xFFE8982E);
    }

    final valueStr = value == value.truncateToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(1);
    final goalStr = targetValue == targetValue.truncateToDouble()
        ? targetValue.toInt().toString()
        : targetValue.toStringAsFixed(1);
    final unitStr = unit.isNotEmpty ? ' $unit' : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0855624D),
              blurRadius: 24,
              offset: Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.onSurface)),
              ),
              // Status badge
              if (isDone && !isOverLimit)
                _badge('DONE', AppTheme.primary, AppTheme.primaryFixed)
              else if (isOverLimit)
                _badge('OVER LIMIT', const Color(0xFFD32F2F),
                    const Color(0xFFFFEBEE)),
              if (mode == 'limit' && !isOverLimit && value == 0)
                _badge('LIMIT', AppTheme.onSurfaceMuted,
                    const Color(0x1A55624D)),
            ],
          ),
          const SizedBox(height: 10),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: const Color(0x1A55624D),
              valueColor: AlwaysStoppedAnimation(barColor),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '$valueStr / $goalStr$unitStr',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: statusColor),
              ),
              const Spacer(),
              // − button
              _StepButton(
                icon: Icons.remove,
                onTap: onDecrement,
              ),
              const SizedBox(width: 8),
              // + button
              _StepButton(
                icon: Icons.add,
                onTap: onIncrement,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color fg, Color bg) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: fg)),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _StepButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: onTap != null
              ? AppTheme.primaryFixed
              : const Color(0x0A55624D),
          shape: BoxShape.circle,
        ),
        child: Icon(icon,
            size: 16,
            color: onTap != null
                ? AppTheme.primary
                : AppTheme.onSurfaceMuted),
      ),
    );
  }
}

// ── Manage row ────────────────────────────────────────────────────────────

class _TargetManageRow extends StatelessWidget {
  final Map<String, dynamic> target;
  final VoidCallback onDelete;

  const _TargetManageRow(
      {required this.target, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final name = target['name'] as String? ?? '';
    final unit = target['unit'] as String? ?? '';
    final mode = target['mode'] as String? ?? 'target';
    final tv = (target['target_value'] as num).toDouble();
    final tvStr = tv == tv.truncateToDouble()
        ? tv.toInt().toString()
        : tv.toStringAsFixed(1);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(name,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 14, color: AppTheme.onSurfaceVar)),
          ),
          Text(
            '${mode == 'limit' ? '≤' : ''} $tvStr${unit.isNotEmpty ? ' $unit' : ''}',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13, color: AppTheme.onSurfaceMuted),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onDelete,
            child: const Icon(Icons.close,
                size: 18, color: AppTheme.onSurfaceMuted),
          ),
        ],
      ),
    );
  }
}

// ── Week grid ─────────────────────────────────────────────────────────────

class _WeekGrid extends StatelessWidget {
  final DateTime weekStart;
  final List<Map<String, dynamic>> targets;
  final double Function(int dayMs, int targetId) getValue;
  final double Function(Map<String, dynamic> t, double value) progress;
  final bool Function(int dayMs) isAllDone;
  final bool Function(int dayMs) hasAnyData;
  final bool compact;

  const _WeekGrid({
    required this.weekStart,
    required this.targets,
    required this.getValue,
    required this.progress,
    required this.isAllDone,
    required this.hasAnyData,
    this.compact = false,
  });

  static const _days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _daysFull = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayStart =
        DateTime(today.year, today.month, today.day);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(7, (i) {
        final day = weekStart.add(Duration(days: i));
        final dayMs = day.millisecondsSinceEpoch;
        final isFuture = day.isAfter(todayStart);
        final isToday = day.isAtSameMomentAs(todayStart);

        // Build progress list per target
        final progresses = targets.map((t) {
          final tid = (t['id'] as num).toInt();
          final v = getValue(dayMs, tid);
          return isFuture ? 0.0 : progress(t, v);
        }).toList();

        final size = compact ? 28.0 : 36.0;

        return Column(
          children: [
            SizedBox(
              width: size,
              height: size,
              child: CustomPaint(
                painter: _RingsPainter(
                  progresses: progresses,
                  isFuture: isFuture,
                  isToday: isToday,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              compact ? _days[i] : _daysFull[i],
              style: GoogleFonts.plusJakartaSans(
                fontSize: compact ? 10 : 11,
                color: isToday
                    ? AppTheme.primary
                    : AppTheme.onSurfaceMuted,
                fontWeight: isToday
                    ? FontWeight.w700
                    : FontWeight.w400,
              ),
            ),
          ],
        );
      }),
    );
  }
}

// ── Concentric rings painter ──────────────────────────────────────────────

class _RingsPainter extends CustomPainter {
  final List<double> progresses; // 0..1 per target
  final bool isFuture;
  final bool isToday;

  static const Color _done = AppTheme.primary;
  static const Color _partial = Color(0xFFE8982E);
  static const Color _empty = Color(0x1A55624D);
  static const Color _future = Color(0x0A55624D);

  const _RingsPainter({
    required this.progresses,
    required this.isFuture,
    required this.isToday,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final count = progresses.isEmpty ? 1 : progresses.length;
    final maxR = size.width / 2;
    // Rings: outermost = first target, innermost = last
    // ringWidth grows based on count
    final totalGap = count > 1 ? (count - 1) * 2.0 : 0.0;
    final ringWidth = (maxR - totalGap) / count;

    for (int i = 0; i < count; i++) {
      final r = maxR - i * (ringWidth + 2) - ringWidth / 2;
      if (r <= 0) continue;

      final prog = progresses.isEmpty ? 0.0 : progresses[i];

      // Background track
      final trackPaint = Paint()
        ..color = isFuture ? _future : _empty
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawCircle(center, r, trackPaint);

      // Progress arc
      if (!isFuture && prog > 0) {
        final arcColor =
            prog >= 1.0 ? _done : _partial;
        final arcPaint = Paint()
          ..color = arcColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringWidth
          ..strokeCap = StrokeCap.round;

        canvas.drawArc(
          Rect.fromCircle(center: center, radius: r),
          -math.pi / 2,
          2 * math.pi * prog,
          false,
          arcPaint,
        );
      }
    }

    // Today indicator dot
    if (isToday) {
      final dotPaint = Paint()..color = AppTheme.primary;
      canvas.drawCircle(
          Offset(center.dx, size.height - 1), 2.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) =>
      old.progresses != progresses ||
      old.isFuture != isFuture ||
      old.isToday != isToday;
}
