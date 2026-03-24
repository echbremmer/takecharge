import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../api/summary.dart';
import '../main.dart';

// ── Provider ──────────────────────────────────────────────────────────────

final _summaryProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  return summaryApi.get();
});

// ── Screen ────────────────────────────────────────────────────────────────

class SummaryScreen extends ConsumerWidget {
  const SummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_summaryProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(e.toString(),
            style: const TextStyle(color: AppTheme.secondary)),
      ),
      data: (data) {
        final habits =
            (data['habits'] as List<dynamic>?) ?? [];
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(_summaryProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            children: [
              // Today at a glance
              _SectionLabel('TODAY AT A GLANCE'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: habits
                    .map<Widget>((h) => _TodayChip(habit: h))
                    .toList(),
              ),

              const SizedBox(height: 28),

              // Per-habit charts
              ...habits.map<Widget>((h) => _HabitCard(habit: h)).toList(),
            ],
          ),
        );
      },
    );
  }
}

// ── Today chip ────────────────────────────────────────────────────────────

class _TodayChip extends StatefulWidget {
  final Map<String, dynamic> habit;
  const _TodayChip({required this.habit});

  @override
  State<_TodayChip> createState() => _TodayChipState();
}

class _TodayChipState extends State<_TodayChip> {
  Timer? _timer;
  int _elapsedMs = 0;

  @override
  void initState() {
    super.initState();
    _updateElapsed();
    final today = widget.habit['today'] as Map<String, dynamic>? ?? {};
    if (today['is_active'] == true) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _updateElapsed());
      });
    }
  }

  void _updateElapsed() {
    final today = widget.habit['today'] as Map<String, dynamic>? ?? {};
    _elapsedMs = (today['elapsed_ms'] as int? ?? 0) +
        (today['is_active'] == true ? 1000 : 0);
    // note: elapsed from server ticks from that snapshot; add server lag here if needed
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.habit;
    final slug = h['style_slug'] as String? ?? '';
    final variant = h['variant_slug'] as String? ?? '';
    final today = h['today'] as Map<String, dynamic>? ?? {};
    final name = h['name'] as String? ?? '';

    String value;
    Color accent;
    IconData icon;

    switch (slug) {
      case 'timer':
        final elapsed =
            (today['elapsed_ms'] as int? ?? 0);
        final isActive = today['is_active'] == true;
        final h2 = elapsed ~/ 3600000;
        final m = (elapsed % 3600000) ~/ 60000;
        value = '${h2}h ${m.toString().padLeft(2, '0')}m';
        accent = variant == 'intermittent_fasting'
            ? const Color(0xFFE8650A)
            : AppTheme.primary;
        icon = isActive
            ? Icons.timer
            : Icons.timer_outlined;
        break;
      case 'daily':
        final total = today['targets_total'] as int? ?? 0;
        final hit = today['targets_hit'] as int? ?? 0;
        value = '$hit / $total targets';
        accent = hit == total && total > 0
            ? AppTheme.primary
            : AppTheme.onSurfaceMuted;
        icon = Icons.track_changes_outlined;
        break;
      case 'todo':
        final total = today['week_total'] as int? ?? 0;
        final checked = today['week_checked'] as int? ?? 0;
        value = '$checked / $total this week';
        accent = checked == total && total > 0
            ? AppTheme.primary
            : AppTheme.onSurfaceMuted;
        icon = Icons.checklist_outlined;
        break;
      default:
        value = '—';
        accent = AppTheme.onSurfaceMuted;
        icon = Icons.circle_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0855624D), blurRadius: 12, offset: Offset(0, 2))
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: accent),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.onSurfaceMuted,
                  letterSpacing: 0.3,
                ),
              ),
              Text(
                value,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Per-habit summary card ─────────────────────────────────────────────────

class _HabitCard extends StatelessWidget {
  final Map<String, dynamic> habit;
  const _HabitCard({required this.habit});

  @override
  Widget build(BuildContext context) {
    final slug = habit['style_slug'] as String? ?? '';
    final variant = habit['variant_slug'] as String? ?? '';
    final name = habit['name'] as String? ?? '';
    final weekBars =
        (habit['week_bars'] as List<dynamic>?) ?? [];
    final trendBars =
        (habit['trend_bars'] as List<dynamic>?) ?? [];

    Color accent = slug == 'timer' && variant == 'intermittent_fasting'
        ? const Color(0xFFE8650A)
        : AppTheme.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0855624D), blurRadius: 24, offset: Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),

          if (weekBars.isNotEmpty && slug != 'todo') ...[
            _ChartLabel('THIS WEEK'),
            const SizedBox(height: 8),
            SizedBox(
              height: 80,
              child: _WeekBarChart(
                bars: weekBars,
                accent: accent,
                slug: slug,
              ),
            ),
            const SizedBox(height: 16),
          ],

          _ChartLabel(slug == 'todo' ? '6-WEEK CHECK-OFF RATE' : '6-WEEK TREND'),
          const SizedBox(height: 8),
          SizedBox(
            height: 80,
            child: _TrendBarChart(
              bars: trendBars,
              accent: accent,
              slug: slug,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Week bar chart ─────────────────────────────────────────────────────────

class _WeekBarChart extends StatelessWidget {
  final List<dynamic> bars;
  final Color accent;
  final String slug;

  const _WeekBarChart(
      {required this.bars, required this.accent, required this.slug});

  @override
  Widget build(BuildContext context) {
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final now = DateTime.now();
    final todayIdx = (now.weekday - 1).clamp(0, 6); // Mon=0

    final groups = <BarChartGroupData>[];
    double maxVal = 0;
    for (final b in bars) {
      final v = (b['value'] as num?)?.toDouble() ?? 0;
      if (v > maxVal) maxVal = v;
    }
    if (maxVal == 0) maxVal = slug == 'timer' ? 4.0 : 1.0;

    for (int i = 0; i < bars.length; i++) {
      final v = (bars[i]['value'] as num?)?.toDouble() ?? 0;
      final isFuture = i > todayIdx;
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: isFuture ? 0 : v,
              color: isFuture
                  ? Colors.transparent
                  : accent.withOpacity(v > 0 ? 0.85 : 0.15),
              width: 18,
              borderRadius: BorderRadius.circular(4),
            )
          ],
        ),
      );
    }

    return BarChart(
      BarChartData(
        maxY: maxVal * 1.2,
        gridData: FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(enabled: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (x, meta) {
                final i = x.toInt();
                if (i < 0 || i >= days.length) return const SizedBox.shrink();
                return Text(
                  days[i],
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    color: i == todayIdx
                        ? accent
                        : AppTheme.onSurfaceMuted,
                    fontWeight: i == todayIdx
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                );
              },
              reservedSize: 18,
            ),
          ),
        ),
        barGroups: groups,
      ),
    );
  }
}

// ── Trend bar chart (6 weeks) ──────────────────────────────────────────────

class _TrendBarChart extends StatelessWidget {
  final List<dynamic> bars;
  final Color accent;
  final String slug;

  const _TrendBarChart(
      {required this.bars, required this.accent, required this.slug});

  String _weekLabel(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month]} ${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    double maxVal = 0;
    for (final b in bars) {
      final v = (b['value'] as num?)?.toDouble() ?? 0;
      if (v > maxVal) maxVal = v;
    }
    if (maxVal == 0) maxVal = slug == 'timer' ? 4.0 : 1.0;

    final groups = <BarChartGroupData>[];
    for (int i = 0; i < bars.length; i++) {
      final v = (bars[i]['value'] as num?)?.toDouble() ?? 0;
      final isCurrentWeek = i == bars.length - 1;
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: v,
              color: accent.withOpacity(isCurrentWeek ? 0.95 : 0.45),
              width: 20,
              borderRadius: BorderRadius.circular(4),
            )
          ],
        ),
      );
    }

    return BarChart(
      BarChartData(
        maxY: maxVal * 1.2,
        gridData: FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(enabled: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (x, meta) {
                final i = x.toInt();
                if (i < 0 || i >= bars.length) {
                  return const SizedBox.shrink();
                }
                // Show only first and last label
                if (i != 0 && i != bars.length - 1) {
                  return const SizedBox.shrink();
                }
                final ms = (bars[i]['ms'] as int?) ?? 0;
                final label = i == bars.length - 1
                    ? 'Now'
                    : _weekLabel(ms);
                return Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 9,
                    color: i == bars.length - 1
                        ? accent
                        : AppTheme.onSurfaceMuted,
                    fontWeight: i == bars.length - 1
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                );
              },
              reservedSize: 16,
            ),
          ),
        ),
        barGroups: groups,
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

class _ChartLabel extends StatelessWidget {
  final String text;
  const _ChartLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: GoogleFonts.manrope(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: AppTheme.onSurfaceMuted,
        ),
      );
}
