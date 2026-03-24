import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../main.dart';

/// Draws concentric progress rings — one ring per target.
/// [progresses] is 0..1 per target (outermost = first).
/// [isLimits]   matches progresses; true = limit mode (green under, red over).
class RingsPainter extends CustomPainter {
  final List<double> progresses;
  final List<bool> isLimits;
  final bool isFuture;
  final bool isToday;

  static const Color _done      = AppTheme.primary;
  static const Color _partial   = Color(0xFFE8982E);
  static const Color _overLimit = Color(0xFFD32F2F);
  static const Color _empty     = Color(0x1A55624D);
  static const Color _future    = Color(0x0A55624D);

  const RingsPainter({
    required this.progresses,
    required this.isLimits,
    required this.isFuture,
    required this.isToday,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final count  = progresses.isEmpty ? 1 : progresses.length;
    final maxR   = size.width / 2;
    final totalGap = count > 1 ? (count - 1) * 2.0 : 0.0;
    final ringWidth = (maxR - totalGap) / count;

    for (int i = 0; i < count; i++) {
      final r = maxR - i * (ringWidth + 2) - ringWidth / 2;
      if (r <= 0) continue;

      final prog  = progresses.isEmpty ? 0.0 : progresses[i];
      final limit = i < isLimits.length && isLimits[i];

      // Background track
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..color = isFuture ? _future : _empty
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringWidth
          ..strokeCap = StrokeCap.round,
      );

      // Progress arc
      if (!isFuture && prog > 0) {
        final arcColor = limit
            ? (prog >= 1.0 ? _overLimit : _done)
            : (prog >= 1.0 ? _done : _partial);

        canvas.drawArc(
          Rect.fromCircle(center: center, radius: r),
          -math.pi / 2,
          2 * math.pi * prog,
          false,
          Paint()
            ..color = arcColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = ringWidth
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // Today indicator dot
    if (isToday) {
      canvas.drawCircle(
        Offset(center.dx, size.height - 1),
        2.5,
        Paint()..color = AppTheme.primary,
      );
    }
  }

  @override
  bool shouldRepaint(RingsPainter old) =>
      old.progresses != progresses ||
      old.isLimits   != isLimits   ||
      old.isFuture   != isFuture   ||
      old.isToday    != isToday;
}
