import 'package:flutter/material.dart';

class PulseDot extends StatefulWidget {
  final Color color;
  final bool pulse;
  final double size;
  const PulseDot({
    super.key,
    required this.color,
    this.pulse = true,
    this.size = 7,
  });

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: widget.color,
        boxShadow: [
          BoxShadow(color: widget.color.withValues(alpha: 0.9), blurRadius: 8),
        ],
        shape: BoxShape.circle,
      ),
    );
    if (!widget.pulse) return dot;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(_c),
      child: dot,
    );
  }
}
