import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/palette.dart';

/// A slow, premium "aurora" backdrop used on the non-camera screens (templates,
/// settings, gallery). Deep ink base with a few soft brand-coloured blobs that
/// drift gently. Wrapped in a [RepaintBoundary] so its animation never marks the
/// content above it dirty.
class AuroraBackground extends StatefulWidget {
  final Widget child;
  const AuroraBackground({super.key, required this.child});

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 24))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, _) => CustomPaint(painter: _AuroraPainter(_c.value)),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _AuroraPainter extends CustomPainter {
  final double t;
  _AuroraPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Base wash.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF080C18), Palette.ink],
        ).createShader(rect),
    );

    // Neutral, colourless depth blobs — soft cool-white lifts that read as
    // glass and ambient light rather than a brand-coloured aurora.
    const blobs = [
      (Color(0xFFFFFFFF), 0.0, Offset(0.18, 0.12), 0.85, 0.06),
      (Color(0xFFBFC9D8), 0.33, Offset(0.86, 0.22), 0.95, 0.05),
      (Color(0xFF9AA6BA), 0.66, Offset(0.5, 0.92), 0.8, 0.05),
    ];

    for (final (color, phase, anchor, scale, alpha) in blobs) {
      final a = (t + phase) * 2 * math.pi;
      final dx = anchor.dx + math.cos(a) * 0.06;
      final dy = anchor.dy + math.sin(a * 0.8) * 0.05;
      final center = Offset(dx * size.width, dy * size.height);
      final radius = size.shortestSide * scale;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0.0)],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter old) => old.t != t;
}
