import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../api/habits.dart';
import '../main.dart';
import '../providers/habits_provider.dart';

class AddHabitScreen extends ConsumerStatefulWidget {
  const AddHabitScreen({super.key});

  @override
  ConsumerState<AddHabitScreen> createState() => _AddHabitScreenState();
}

class _AddHabitScreenState extends ConsumerState<AddHabitScreen> {
  final _nameCtrl = TextEditingController();
  String _type = 'timer';
  String? _variantSlug; // null = generic type selected
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
      await habitsApi.create(name, _type, variantSlug: _variantSlug);
      ref.invalidate(habitsProvider);
      if (mounted) context.go('/');
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('VANDAG'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0x26C5C8BE)),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 80),
        children: [
          // ── Name ──────────────────────────────────────────────────────────
          _SectionLabel('NAME'),
          const SizedBox(height: 10),
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 15, color: AppTheme.onSurface),
            decoration: InputDecoration(
              hintText: 'e.g. Morning run, Reading…',
              hintStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 15, color: AppTheme.onSurfaceMuted),
              filled: true,
              fillColor: AppTheme.surfaceCard,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _create(),
          ),

          const SizedBox(height: 28),

          // ── Built-in types ────────────────────────────────────────────────
          _SectionLabel('BUILT-IN'),
          const SizedBox(height: 10),
          _BuiltInOption(
            variantSlug: 'intermittent_fasting',
            selected: _variantSlug == 'intermittent_fasting',
            icon: Icons.local_fire_department_outlined,
            label: 'Intermittent Fasting',
            description:
                'Timer-based fasting tracker with fat burning zone indicator, calorie estimates, and water weight loss.',
            onTap: () => setState(() {
              _variantSlug = 'intermittent_fasting';
              _type = 'timer';
              if (_nameCtrl.text.trim().isEmpty) {
                _nameCtrl.text = 'Fasting';
              }
            }),
          ),

          const SizedBox(height: 28),

          // ── Generic type ──────────────────────────────────────────────────
          _SectionLabel('TYPE'),
          const SizedBox(height: 10),
          _TypeOption(
            value: 'timer',
            selected: _variantSlug == null && _type == 'timer',
            icon: Icons.timer_outlined,
            label: 'Timer',
            description:
                'Track time spent on an activity. Start and stop a timer, set a weekly time goal.',
            onTap: () => setState(() { _type = 'timer'; _variantSlug = null; }),
          ),
          const SizedBox(height: 10),
          _TypeOption(
            value: 'daily',
            selected: _variantSlug == null && _type == 'daily',
            icon: Icons.track_changes_outlined,
            label: 'Daily',
            description:
                'Log measurable targets each day — steps, glasses of water, calories, etc.',
            onTap: () => setState(() { _type = 'daily'; _variantSlug = null; }),
          ),
          const SizedBox(height: 10),
          _TypeOption(
            value: 'todo',
            selected: _variantSlug == null && _type == 'todo',
            icon: Icons.checklist_outlined,
            label: 'To-do',
            description:
                'A weekly checklist of tasks. Add items, check them off, and review past weeks.',
            onTap: () => setState(() { _type = 'todo'; _variantSlug = null; }),
          ),

          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!,
                style: const TextStyle(color: AppTheme.secondary, fontSize: 13)),
          ],

          const SizedBox(height: 32),

          // ── Create button ─────────────────────────────────────────────────
          SizedBox(
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
                textStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 16, fontWeight: FontWeight.w700),
              ),
              onPressed: _loading ? null : _create,
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Create habit'),
            ),
          ),
        ],
      ),
    );
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

// ── Built-in option card ───────────────────────────────────────────────────

class _BuiltInOption extends StatelessWidget {
  final String variantSlug;
  final bool selected;
  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;

  static const _ifOrange = Color(0xFFE8650A);

  const _BuiltInOption({
    required this.variantSlug,
    required this.selected,
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? _ifOrange : Colors.transparent,
            width: 2,
          ),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0855624D),
                blurRadius: 24,
                offset: Offset(0, 4)),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: selected
                    ? _ifOrange.withOpacity(0.15)
                    : AppTheme.surfaceNest,
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  size: 20,
                  color: selected ? _ifOrange : AppTheme.onSurfaceMuted),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        label,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: selected ? _ifOrange : AppTheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _ifOrange.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'BUILT-IN',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: _ifOrange,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: AppTheme.onSurfaceMuted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? _ifOrange : Colors.transparent,
                border: Border.all(
                  color: selected ? _ifOrange : AppTheme.onSurfaceMuted,
                  width: 2,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Generic type option card ────────────────────────────────────────────────

class _TypeOption extends StatelessWidget {
  final String value;
  final bool selected;
  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;

  const _TypeOption({
    required this.value,
    required this.selected,
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppTheme.primary : Colors.transparent,
            width: 2,
          ),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0855624D),
                blurRadius: 24,
                offset: Offset(0, 4)),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: selected ? AppTheme.primaryFixed : AppTheme.surfaceNest,
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  size: 20,
                  color: selected ? AppTheme.primary : AppTheme.onSurfaceMuted),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: selected ? AppTheme.primary : AppTheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: AppTheme.onSurfaceMuted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppTheme.primary : Colors.transparent,
                border: Border.all(
                  color: selected ? AppTheme.primary : AppTheme.onSurfaceMuted,
                  width: 2,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
