import 'dart:async';

import 'package:flutter/widgets.dart';

/// Rebuilds **only its own subtree** on a fixed interval and hands the builder
/// the current time.
///
/// The old app drove its clock with a top-level `setState` every second, which
/// rebuilt the camera preview, the map and every chip 60+ times a minute. This
/// isolates the tick so a live clock costs almost nothing.
class TickingBuilder extends StatefulWidget {
  final Duration interval;
  final Widget Function(BuildContext context, DateTime now) builder;

  const TickingBuilder({
    super.key,
    this.interval = const Duration(seconds: 1),
    required this.builder,
  });

  @override
  State<TickingBuilder> createState() => _TickingBuilderState();
}

class _TickingBuilderState extends State<TickingBuilder> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.interval, (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _now);
}
