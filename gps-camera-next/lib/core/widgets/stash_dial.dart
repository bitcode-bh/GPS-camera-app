import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../design/palette.dart';
import '../design/tokens.dart';
import 'stash_glass.dart';

/// Stash's spring-driven selection lens, with a trailing drop that follows
/// the finger. The stops are painted below the lens so they refract with it.
class StashDial extends StatefulWidget {
  final List<String> labels;
  final List<IconData?>? icons;
  final Axis axis;
  final int selected;
  final ValueChanged<int> onChanged;
  final ValueChanged<int>? onActivate;
  final bool Function(int)? isEnabled;
  final Widget? Function(int)? stopContent;

  const StashDial({
    super.key,
    required this.labels,
    this.icons,
    this.axis = Axis.horizontal,
    required this.selected,
    required this.onChanged,
    this.onActivate,
    this.isEnabled,
    this.stopContent,
  }) : assert(
         (icons == null || labels.length == icons.length) && labels.length > 0,
       );

  @override
  State<StashDial> createState() => _StashDialState();
}

class _StashDialState extends State<StashDial>
    with SingleTickerProviderStateMixin {
  static const _edgeTravel = 0.28;
  late final Ticker _ticker = createTicker(_tick);
  late double _head = widget.selected.toDouble();
  late double _tail = _head;
  Duration _previous = Duration.zero;
  SpringSimulation? _spring;
  int? _springTarget;
  double _springTime = 0;
  bool _dragging = false;
  int? _dragStop;

  @override
  void didUpdateWidget(covariant StashDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging &&
        oldWidget.selected != widget.selected &&
        _springTarget != widget.selected) {
      _settle(widget.selected);
    }
  }

  void _settle(int index, {double velocity = 0}) {
    _springTarget = index;
    _spring = SpringSimulation(
      SpringDescription.withDampingRatio(mass: 1, stiffness: 150, ratio: 0.58),
      _head,
      index.toDouble(),
      velocity,
      snapToEnd: true,
    );
    _springTime = 0;
    _start();
  }

  void _start() {
    if (!_ticker.isActive) {
      _previous = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _previous).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _previous = elapsed;
    setState(() {
      final spring = _spring;
      if (spring != null) {
        _springTime += dt;
        _head = spring
            .x(_springTime)
            .clamp(-_edgeTravel, widget.labels.length - 1 + _edgeTravel);
        if (spring.isDone(_springTime)) {
          _spring = null;
          _springTarget = null;
        }
      }
      _tail += (_head - _tail) * (1 - math.exp(-dt * 6));
      if (_spring == null && (_head - _tail).abs() < 0.002) {
        _tail = _head;
        _ticker.stop();
      }
    });
  }

  void _pick(int index, {double velocity = 0}) {
    if (widget.isEnabled?.call(index) == false) {
      _settle(widget.selected);
      return;
    }
    if (index != widget.selected) {
      HapticFeedback.selectionClick();
    }
    _settle(index, velocity: velocity);
    widget.onChanged(index);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vertical = widget.axis == Axis.vertical;
    return SizedBox(
      width: vertical ? 44 : null,
      height: vertical ? null : 48,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final extent = vertical
              ? constraints.maxHeight
              : constraints.maxWidth;
          final slot = extent / widget.labels.length;
          final radius = math.min(slot / 2 - 2, 20.0).clamp(1.0, 20.0);
          final center = (_head + 0.5) * slot;

          int nearestStop(double position) =>
              position.round().clamp(0, widget.labels.length - 1);

          void follow(Offset position) {
            final offset = vertical ? position.dy : position.dx;
            final raw = offset / slot - 0.5;
            final edge = raw.clamp(0.0, widget.labels.length - 1.0);
            final excess = raw - edge;
            setState(() {
              _head = edge + _edgeTravel * excess / (1 + excess.abs());
            });
            final stop = nearestStop(_head);
            if (stop != _dragStop) {
              _dragStop = stop;
              HapticFeedback.selectionClick();
            }
            _start();
          }

          void dragStart(DragStartDetails details) {
            _dragging = true;
            _dragStop = widget.selected;
            _spring = null;
            _springTarget = null;
            follow(details.localPosition);
          }

          void dragUpdate(DragUpdateDetails details) =>
              follow(details.localPosition);

          void dragEnd(DragEndDetails details) {
            _dragging = false;
            final releaseSpeed = (details.primaryVelocity ?? 0) / slot;
            final speed = releaseSpeed.abs() >= 7
                ? releaseSpeed.clamp(-10.0, 10.0)
                : 0.0;
            // A flick can advance one stop beyond the finger's release point.
            final projected = _head + (speed * 0.12).clamp(-1.0, 1.0);
            _pick(nearestStop(projected), velocity: speed);
          }

          void dragCancel() {
            _dragging = false;
            _settle(widget.selected);
          }

          void configure(DragGestureRecognizer recognizer) {
            recognizer
              // The drag has already crossed touch slop before it can fling.
              ..minFlingDistance = 0
              ..onStart = dragStart
              ..onUpdate = dragUpdate
              ..onEnd = dragEnd
              ..onCancel = dragCancel;
          }

          return RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              if (vertical)
                VerticalDragGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      VerticalDragGestureRecognizer
                    >(VerticalDragGestureRecognizer.new, configure)
              else
                HorizontalDragGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      HorizontalDragGestureRecognizer
                    >(HorizontalDragGestureRecognizer.new, configure),
            },
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (!StashGlass.supported)
                    Positioned(
                      left: (vertical ? 22 : center) - radius,
                      top: (vertical ? center : 24) - radius,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Palette.selectionFill,
                          borderRadius: BorderRadius.all(
                            Radius.circular(Corners.pill),
                          ),
                        ),
                        child: SizedBox.square(dimension: radius * 2),
                      ),
                    ),
                  Flex(
                    direction: widget.axis,
                    children: [
                      for (var i = 0; i < widget.labels.length; i++)
                        Expanded(child: _stop(i)),
                    ],
                  ),
                  IgnorePointer(
                    child: StashGlass(
                      radius: 0,
                      tint: Palette.ink2.withValues(alpha: 0.06),
                      head: center,
                      tail: (_tail + 0.5) * slot,
                      dropRadius: radius,
                      vertical: vertical,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _stop(int index) {
    final active = index == widget.selected;
    final enabled = widget.isEnabled?.call(index) ?? true;
    final icon = widget.icons?[index];
    final label = widget.labels[index];
    final under = (1 - (index - _head).abs()).clamp(0.0, 1.0);
    final color = Color.lerp(
      enabled ? Palette.textHi : Palette.textMid,
      Palette.accentMuted,
      under,
    )!;
    final custom = widget.stopContent?.call(index);

    void activate() {
      _pick(index);
      widget.onActivate?.call(index);
    }

    return Semantics(
      label: label,
      button: true,
      enabled: enabled,
      selected: active,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? activate : null,
        child: ExcludeSemantics(
          child: Center(
            child: Transform.scale(
              scale: 1 + 0.18 * under,
              child:
                  custom ??
                  (icon == null
                      ? Text(
                          label,
                          maxLines: 1,
                          style: TextStyle(
                            color: color,
                            fontSize: widget.axis == Axis.horizontal ? 13 : 10,
                            fontWeight: active
                                ? FontWeight.w600
                                : FontWeight.w500,
                            shadows: const [
                              Shadow(color: Palette.ink, blurRadius: 8),
                            ],
                          ),
                        )
                      : Icon(icon, size: 22, color: color)),
            ),
          ),
        ),
      ),
    );
  }
}
