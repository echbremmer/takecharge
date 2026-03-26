import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Intermittent fasting phase badges in Agnoster/powerline style.
// All 4 phases are always shown; unearned phases are greyed out.
// Earned phases flow left-to-right with a filled arrow connector between them.
class IFPhaseBadges extends StatelessWidget {
  final int elapsedMs;

  static const _phases = [
    _Phase(ms: 0,                 label: 'Digesting',   color: Color(0xFF60A5FA)),
    _Phase(ms: 12 * 3600 * 1000, label: 'Fat burning',  color: Color(0xFFE8650A)),
    _Phase(ms: 18 * 3600 * 1000, label: 'Ketosis',      color: Color(0xFF8B5CF6)),
    _Phase(ms: 24 * 3600 * 1000, label: 'Autophagy',    color: Color(0xFF0D9488)),
  ];

  static const _dimColor = Color(0xFFD1D5DB);
  static const _segmentHeight = 26.0;

  const IFPhaseBadges({super.key, required this.elapsedMs});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(_phases.length, (i) {
        final phase = _phases[i];
        final earned = elapsedMs >= phase.ms;
        final nextEarned = i + 1 < _phases.length && elapsedMs >= _phases[i + 1].ms;
        final isLast = i == _phases.length - 1;

        final segColor = earned ? phase.color : _dimColor;
        final nextSegColor = isLast
            ? Colors.transparent
            : (nextEarned ? _phases[i + 1].color : _dimColor);

        final isFirst = i == 0;
        final radius = const Radius.circular(6);
        final borderRadius = isFirst && isLast
            ? BorderRadius.all(radius)
            : isFirst
                ? BorderRadius.only(topLeft: radius, bottomLeft: radius)
                : isLast
                    ? BorderRadius.only(topRight: radius, bottomRight: radius)
                    : BorderRadius.zero;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Segment body
            Container(
              height: _segmentHeight,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: segColor,
                borderRadius: borderRadius,
              ),
              alignment: Alignment.center,
              child: Text(
                phase.label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            // Arrow connector (skip after last segment)
            if (!isLast)
              CustomPaint(
                size: const Size(10, _segmentHeight),
                painter: _ArrowPainter(
                  leftColor: segColor,
                  rightColor: nextSegColor,
                ),
              ),
          ],
        );
      }),
    );
  }
}

// Paints the powerline arrow: left half filled with leftColor,
// right half filled with rightColor, divided by a right-pointing chevron.
class _ArrowPainter extends CustomPainter {
  final Color leftColor;
  final Color rightColor;

  const _ArrowPainter({required this.leftColor, required this.rightColor});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final mid = h / 2;

    // Background = right segment's color so the corners blend in seamlessly.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = rightColor,
    );

    // Arrow = left segment's color, pointing right into the next segment.
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(w, mid)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(path, Paint()..color = leftColor);
  }

  @override
  bool shouldRepaint(_ArrowPainter old) =>
      old.leftColor != leftColor || old.rightColor != rightColor;
}

class _Phase {
  final int ms;
  final String label;
  final Color color;
  const _Phase({required this.ms, required this.label, required this.color});
}
