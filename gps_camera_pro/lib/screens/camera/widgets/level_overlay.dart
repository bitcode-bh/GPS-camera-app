import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/design/palette.dart';

/// A horizon level indicator (Google-Camera style): a fixed reference line and a
/// line that tilts with the device roll. They merge and turn green when level.
/// Purely a viewfinder guide — never part of the captured image.
class LevelOverlay extends StatelessWidget {
  final double roll; // degrees, 0 = level
  const LevelOverlay({super.key, required this.roll});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: CustomPaint(
          size: const Size(220, 120),
          painter: _LevelPainter(roll),
        ),
      ),
    );
  }
}

class _LevelPainter extends CustomPainter {
  final double roll;
  _LevelPainter(this.roll);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final level = roll.abs() < 1.2;
    final color = level ? Palette.success : Colors.white.withValues(alpha: 0.85);

    // Fixed reference ticks (short, centred).
    final ref = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(c.dx - 70, c.dy), Offset(c.dx - 30, c.dy), ref);
    canvas.drawLine(Offset(c.dx + 30, c.dy), Offset(c.dx + 70, c.dy), ref);

    // Tilting line (rotates with roll).
    final rad = -roll * math.pi / 180;
    final dir = Offset(math.cos(rad), math.sin(rad));
    final line = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c - dir * 26, c + dir * 26, line);

    if (level) {
      canvas.drawCircle(c, 4, Paint()..color = Palette.success);
    }
  }

  @override
  bool shouldRepaint(covariant _LevelPainter old) => old.roll != roll;
}
