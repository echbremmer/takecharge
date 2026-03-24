import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Intermittent fasting phase badges shown based on elapsed fast time.
// Each phase is shown once its threshold is reached (accumulative).
class IFPhaseBadges extends StatelessWidget {
  final int elapsedMs;

  static const _phases = [
    _Phase(ms: 0,                    label: 'Digesting',   color: Color(0xFF60A5FA)),
    _Phase(ms: 12 * 3600 * 1000,    label: 'Fat burning',  color: Color(0xFFE8650A)),
    _Phase(ms: 18 * 3600 * 1000,    label: 'Ketosis',      color: Color(0xFF8B5CF6)),
    _Phase(ms: 24 * 3600 * 1000,    label: 'Autophagy',    color: Color(0xFF0D9488)),
  ];

  const IFPhaseBadges({super.key, required this.elapsedMs});

  @override
  Widget build(BuildContext context) {
    final earned = _phases.where((p) => elapsedMs >= p.ms).toList();
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: earned
          .map((p) => _PhaseBadge(label: p.label, color: p.color))
          .toList(),
    );
  }
}

class _Phase {
  final int ms;
  final String label;
  final Color color;
  const _Phase({required this.ms, required this.label, required this.color});
}

class _PhaseBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _PhaseBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
