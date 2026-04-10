import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../api/habits.dart';
import '../main.dart';

class TodoHabitScreen extends StatefulWidget {
  final int habitId;
  final String habitName;

  const TodoHabitScreen(
      {super.key, required this.habitId, required this.habitName});

  @override
  State<TodoHabitScreen> createState() => _TodoHabitScreenState();
}

class _TodoHabitScreenState extends State<TodoHabitScreen> {
  List<Map<String, dynamic>> _todos = [];
  bool _loading = true;
  String? _error;
  final Set<String> _expandedWeeks = {};
  final _addCtrl = TextEditingController();
  final _focusNode = FocusNode();
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _addCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  DateTime _weekMonday(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return d.subtract(Duration(days: d.weekday - 1));
  }

  String _weekKey(DateTime monday) =>
      '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';

  int get _currentWeekMs =>
      _weekMonday(DateTime.now()).millisecondsSinceEpoch;

  List<Map<String, dynamic>> get _currentTodos {
    final wk = _currentWeekMs;
    return _todos
        .where((t) => (t['week_start_ms'] as num).toInt() == wk)
        .toList();
  }

  Map<String, List<Map<String, dynamic>>> get _historyByWeek {
    final wk = _currentWeekMs;
    final map = <String, List<Map<String, dynamic>>>{};
    for (final t in _todos) {
      final ms = (t['week_start_ms'] as num).toInt();
      if (ms == wk) continue;
      final monday = DateTime.fromMillisecondsSinceEpoch(ms);
      final key = _weekKey(monday);
      map.putIfAbsent(key, () => []).add(t);
    }
    return map;
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final todos = await habitsApi.getTodos(widget.habitId);
      setState(() {
        _todos = todos.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _addTodo() async {
    final text = _addCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _adding = true);
    try {
      final todo = await habitsApi.createTodo(
          widget.habitId, text, _currentWeekMs);
      _addCtrl.clear();
      setState(() {
        _todos.add(todo);
        _adding = false;
      });
    } catch (_) {
      setState(() => _adding = false);
    }
  }

  Future<void> _toggle(Map<String, dynamic> todo) async {
    final id = (todo['id'] as num).toInt();
    final newChecked = !(todo['checked'] as bool? ?? false);
    // Optimistic update
    setState(() => todo['checked'] = newChecked);
    try {
      await habitsApi.toggleTodo(widget.habitId, id, newChecked);
    } catch (_) {
      setState(() => todo['checked'] = !newChecked);
    }
  }

  Future<void> _pickDeadline(Map<String, dynamic> todo) async {
    final id = (todo['id'] as num).toInt();
    final existing = todo['deadline_ms'] != null
        ? DateTime.fromMillisecondsSinceEpoch((todo['deadline_ms'] as num).toInt())
        : null;

    final date = await showDatePicker(
      context: context,
      initialDate: existing ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: existing != null
          ? TimeOfDay.fromDateTime(existing)
          : const TimeOfDay(hour: 23, minute: 59),
    );
    if (time == null || !mounted) return;

    final deadlineMs = DateTime(
            date.year, date.month, date.day, time.hour, time.minute)
        .millisecondsSinceEpoch;
    setState(() => todo['deadline_ms'] = deadlineMs);
    habitsApi.setTodoDeadline(widget.habitId, id, deadlineMs);
  }

  Future<void> _clearDeadline(Map<String, dynamic> todo) async {
    final id = (todo['id'] as num).toInt();
    setState(() => todo['deadline_ms'] = null);
    habitsApi.setTodoDeadline(widget.habitId, id, null);
  }

  Future<void> _delete(Map<String, dynamic> todo) async {
    final id = (todo['id'] as num).toInt();
    setState(() => _todos.removeWhere((t) => (t['id'] as num).toInt() == id));
    try {
      await habitsApi.deleteTodo(widget.habitId, id);
    } catch (_) {
      await _load(); // revert on error
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

    final history = _historyByWeek;
    final sortedWeekKeys = history.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 80),
      children: [
        // ── Add item ───────────────────────────────────────────────────────
        _buildAddRow(),

        const SizedBox(height: 24),

        // ── This week ──────────────────────────────────────────────────────
        _SectionLabel('THIS WEEK'),
        const SizedBox(height: 10),
        _buildCurrentWeek(),

        // ── History ────────────────────────────────────────────────────────
        if (sortedWeekKeys.isNotEmpty) ...[
          const SizedBox(height: 28),
          _SectionLabel('HISTORY'),
          const SizedBox(height: 10),
          ...sortedWeekKeys.map((key) => _buildHistoryWeek(key, history[key]!)),
        ],
      ],
    );
  }

  // ── Add row ───────────────────────────────────────────────────────────────

  Widget _buildAddRow() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _addCtrl,
            focusNode: _focusNode,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 15, color: AppTheme.onSurface),
            decoration: InputDecoration(
              hintText: 'Add a to-do…',
              hintStyle: TextStyle(
                  color: AppTheme.onSurfaceMuted, fontSize: 15),
              filled: true,
              fillColor: AppTheme.surfaceCard,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                      color: AppTheme.primary.withAlpha(80), width: 1.5)),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _addTodo(),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: _adding ? null : _addTodo,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _adding ? AppTheme.primaryFixed : AppTheme.primary,
              shape: BoxShape.circle,
            ),
            child: _adding
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.add, color: Colors.white, size: 22),
          ),
        ),
      ],
    );
  }

  // ── Current week ──────────────────────────────────────────────────────────

  Widget _buildCurrentWeek() {
    final items = _currentTodos;
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'No items yet. Add one above.',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 14, color: AppTheme.onSurfaceMuted),
        ),
      );
    }
    return Column(
      children: items.map((t) => _TodoItem(
            todo: t,
            onToggle: () => _toggle(t),
            onDelete: () => _delete(t),
            onSetDeadline: () => _pickDeadline(t),
            onClearDeadline: () => _clearDeadline(t),
          )).toList(),
    );
  }

  // ── History week ──────────────────────────────────────────────────────────

  Widget _buildHistoryWeek(
      String key, List<Map<String, dynamic>> items) {
    final isExpanded = _expandedWeeks.contains(key);
    final monday =
        DateTime.fromMillisecondsSinceEpoch(_weekMsFromKey(key));
    final sunday = monday.add(const Duration(days: 6));
    final doneCount = items.where((t) => t['checked'] == true).length;

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
                  Expanded(
                    child: Text(
                      '${_fmtDate(monday)} – ${_fmtDate(sunday)}',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.onSurface),
                    ),
                  ),
                  Text(
                    '$doneCount / ${items.length} done',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: doneCount == items.length
                            ? AppTheme.primary
                            : AppTheme.onSurfaceMuted),
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
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                children: items
                    .map((t) => _TodoItem(todo: t, readOnly: true))
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  int _weekMsFromKey(String key) {
    final parts = key.split('-');
    return DateTime(
            int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]))
        .millisecondsSinceEpoch;
  }

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
  Widget build(BuildContext context) => Text(
        text,
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
          color: AppTheme.onSurfaceMuted,
        ),
      );
}

// ── Todo item ─────────────────────────────────────────────────────────────

class _TodoItem extends StatelessWidget {
  final Map<String, dynamic> todo;
  final VoidCallback? onToggle;
  final VoidCallback? onDelete;
  final VoidCallback? onSetDeadline;
  final VoidCallback? onClearDeadline;
  final bool readOnly;

  const _TodoItem({
    required this.todo,
    this.onToggle,
    this.onDelete,
    this.onSetDeadline,
    this.onClearDeadline,
    this.readOnly = false,
  });

  String _fmtDeadline(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day}  $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final checked = todo['checked'] as bool? ?? false;
    final text = todo['text'] as String? ?? '';
    final deadlineMs = todo['deadline_ms'] != null
        ? (todo['deadline_ms'] as num).toInt()
        : null;
    final isOverdue = deadlineMs != null &&
        DateTime.now().millisecondsSinceEpoch > deadlineMs &&
        !checked;

    return GestureDetector(
      onTap: readOnly ? null : onToggle,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: checked
              ? AppTheme.primaryFixed.withAlpha(120)
              : (readOnly ? Colors.transparent : AppTheme.surfaceNest),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            // Checkbox
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: checked ? AppTheme.primary : Colors.transparent,
                border: Border.all(
                  color: checked
                      ? AppTheme.primary
                      : AppTheme.onSurfaceMuted,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(5),
              ),
              child: checked
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            // Text
            Expanded(
              child: Text(
                text,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  color: checked
                      ? AppTheme.onSurfaceMuted
                      : AppTheme.onSurface,
                  decoration: checked ? TextDecoration.lineThrough : null,
                  decorationColor: AppTheme.onSurfaceMuted,
                ),
              ),
            ),
            // Deadline
            if (!readOnly) ...[
              const SizedBox(width: 8),
              if (deadlineMs != null)
                GestureDetector(
                  onTap: onClearDeadline,
                  child: Text(
                    _fmtDeadline(deadlineMs),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isOverdue
                          ? const Color(0xFFD32F2F)
                          : AppTheme.onSurfaceMuted,
                    ),
                  ),
                )
              else
                GestureDetector(
                  onTap: onSetDeadline,
                  child: const Icon(Icons.schedule_outlined,
                      size: 16, color: AppTheme.onSurfaceMuted),
                ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: onDelete,
                child: const Icon(Icons.close,
                    size: 16, color: AppTheme.onSurfaceMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
