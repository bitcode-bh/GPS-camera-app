import 'package:flutter/material.dart';

import '../design/palette.dart';

/// Stash's plum ground and 14 dp hairline grid.
class StashBackdrop extends StatelessWidget {
  final Widget child;
  final bool transparent;

  const StashBackdrop({
    super.key,
    required this.child,
    this.transparent = false,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _StashGrid(transparent), child: child);
  }
}

class _StashGrid extends CustomPainter {
  final bool transparent;

  const _StashGrid(this.transparent);

  @override
  void paint(Canvas canvas, Size size) {
    if (!transparent) {
      canvas.drawRect(Offset.zero & size, Paint()..color = Palette.ink);
    }
    final line = Paint()
      ..color = const Color(0x0FFFFFFF)
      ..strokeWidth = 0.75;
    for (double x = 0; x < size.width; x += 14) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (double y = 0; y < size.height; y += 14) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(covariant _StashGrid oldDelegate) =>
      oldDelegate.transparent != transparent;
}
