import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/design/palette.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/pressable.dart';

const cameraYellow = Palette.accentYellow;
const _pixelSize = 1.7;
const _pixelPitch = 2.5;

/// Drives paint only; the camera and control widget trees do not tick with it.
class _PixelMotion extends StatefulWidget {
  final bool animate;
  final Widget Function(ValueNotifier<double> seconds) builder;
  const _PixelMotion({required this.animate, required this.builder});

  @override
  State<_PixelMotion> createState() => _PixelMotionState();
}

class _PixelMotionState extends State<_PixelMotion>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _seconds = ValueNotifier(0.0);
  late final Ticker _ticker;
  int _lastMicros = 0;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _ticker = createTicker((elapsed) {
      if (elapsed.inMicroseconds - _lastMicros < 33333) return;
      _lastMicros = elapsed.inMicroseconds;
      _seconds.value = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    });
  }

  void _sync() {
    final enabled =
        widget.animate &&
        _foreground &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (enabled && !_ticker.isActive) {
      _lastMicros = 0;
      _ticker.start();
    } else if (!enabled && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_PixelMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _seconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_seconds);
}

/// Random targets change once per 1.8 seconds and cross-fade between them.
class _PixelPattern {
  final double chance;
  final int seed;
  final double transitionFraction;
  final _targets = <int, (double, double)>{};
  int? _epoch;
  double _mix = 0;

  _PixelPattern(this.chance, {this.seed = 0, this.transitionFraction = 1});

  void update(double seconds) {
    final cycle = seconds / 1.8;
    final epoch = cycle.floor();
    if (epoch != _epoch) {
      _epoch = epoch;
      _targets.clear();
    }
    final t = ((cycle - epoch) / transitionFraction).clamp(0.0, 1.0);
    _mix = t * t * (3 - 2 * t);
  }

  double value(int index) {
    final (previous, next) = _targets.putIfAbsent(index, () {
      double target(int epoch) {
        final v =
            math.sin(((index + seed) * 17 + epoch * 7919) * 127.1 + 311.7) *
            43758.5453;
        return v - v.floor() < chance ? 1.0 : 0.0;
      }

      return (target(_epoch! - 1), target(_epoch!));
    });
    return previous + (next - previous) * _mix;
  }
}

String formatCameraZoom(double ratio) {
  final tenths = (ratio * 10).round();
  return tenths % 10 == 0
      ? '${tenths ~/ 10}×'
      : '${(tenths / 10).toStringAsFixed(1)}×';
}

/// Camera chrome uses neutral smoke glass and a yellow selection accent.
class CameraGlass extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  const CameraGlass({
    super.key,
    required this.child,
    this.radius = 54,
    this.padding = EdgeInsets.zero,
  });

  /// A solid panel: no blur, gradient or sheen.
  @override
  Widget build(BuildContext context) => Material(
    color: Palette.surfaceSolid,
    clipBehavior: Clip.antiAlias,
    shape: Corners.shape(
      radius,
      side: const BorderSide(color: Palette.strokeSolid),
    ),
    child: Padding(padding: padding, child: child),
  );
}

class CameraAction extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Widget? child;
  final VoidCallback? onTap;
  final bool ring;
  final bool plain;
  final bool selected;
  final double iconTurns;

  const CameraAction({
    super.key,
    required this.label,
    this.icon,
    this.child,
    this.onTap,
    this.ring = false,
    this.plain = false,
    this.selected = false,
    this.iconTurns = 0,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    excludeFromSemantics: true,
    child: Semantics(
      label: label,
      button: true,
      selected: selected ? true : null,
      enabled: onTap != null,
      child: Pressable(
        onTap: onTap,
        child: ExcludeSemantics(
          child: Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: plain ? Colors.transparent : const Color(0xFF262626),
              shape: Corners.shape(
                Corners.md,
                side: ring
                    ? const BorderSide(color: cameraYellow, width: 2)
                    : BorderSide.none,
              ),
            ),
            child: IconTheme(
              data: IconThemeData(
                color: onTap == null
                    ? Colors.white38
                    : (selected ? cameraYellow : Colors.white),
                size: 23,
              ),
              child: AnimatedRotation(
                turns: iconTurns,
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                child: child ?? Icon(icon),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A four-column, 12dp pixel track with a 54dp touch target.
class CameraAdjustmentRail extends StatelessWidget {
  static const trackHeight = 132.0;
  static const touchWidth = 54.0;

  final String label;
  final double value;
  final double min;
  final double max;
  final bool exposure;
  final bool whiteBalance;
  final bool autoWhiteBalance;
  final double? baseline;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final bool animate;

  const CameraAdjustmentRail({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
    this.exposure = false,
    this.whiteBalance = false,
    this.autoWhiteBalance = false,
    this.baseline,
    this.animate = true,
  });

  // Equal slider travel at low zoom ratios should produce finer adjustments.
  double _position(num value) => exposure || whiteBalance
      ? (value - min) / (max - min)
      : math.log(value / min) / math.log(max / min);

  double _value(double position) => exposure || whiteBalance
      ? min + (max - min) * position
      : min * math.pow(max / min, position);

  String _format(double v) => whiteBalance
      ? '${v.round()} K'
      : exposure
      ? '${v > 0 ? '+' : ''}${v == v.roundToDouble() ? v.toInt() : v.toStringAsFixed(1)} EV'
      : formatCameraZoom(v);

  @override
  Widget build(BuildContext context) {
    final position = _position(value.clamp(min, max));
    final zero = _position(
      (baseline ?? (exposure ? 0.0 : min)).clamp(min, max),
    );
    final intensity = exposure
        ? ((position - zero).abs() / math.max(zero, 1 - zero)).clamp(0.0, 1.0)
        : position;
    return _PixelMotion(
      animate: animate,
      builder: (seconds) => RepaintBoundary(
        child: SizedBox(
          width: touchWidth,
          height: trackHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CustomPaint(
                          painter: _RailPainter(
                            position,
                            zero,
                            intensity,
                            seconds,
                            seed: exposure ? 521 : 0,
                          ),
                        ),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 12,
                            trackShape: const _PixelTrack(),
                            thumbShape: SliderComponentShape.noThumb,
                            overlayShape: SliderComponentShape.noOverlay,
                          ),
                          child: Semantics(
                            label: label,
                            child: Slider(
                              padding: EdgeInsets.zero,
                              value: position,
                              onChanged: onChanged == null
                                  ? null
                                  : (position) => onChanged!(_value(position)),
                              onChangeEnd: onChangeEnd,
                              semanticFormatterCallback: (ratio) =>
                                  autoWhiteBalance && ratio == position
                                  ? 'Auto'
                                  : _format(_value(ratio)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: exposure || whiteBalance ? 46 : null,
                right: exposure || whiteBalance ? null : 46,
                top:
                    _PixelTrack.endInset +
                    (1 - position) * (trackHeight - 2 * _PixelTrack.endInset) -
                    9,
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: Text(
                      autoWhiteBalance ? 'Auto' : _format(value),
                      style: const TextStyle(
                        fontSize: 13,
                        color: cameraYellow,
                        shadows: [
                          Shadow(color: Colors.black, offset: Offset(0, 1)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PixelTrack extends RoundedRectSliderTrackShape {
  static const endInset = 11.0;
  const _PixelTrack();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) => Rect.fromLTWH(
    offset.dx + endInset,
    offset.dy + (parentBox.size.height - 12) / 2,
    math.max(0, parentBox.size.width - 2 * endInset),
    12,
  );

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 0,
  }) {} // The native Slider owns input/semantics; _RailPainter owns its pixels.
}

class _RailPainter extends CustomPainter {
  final double position, baseline, intensity;
  final ValueNotifier<double> seconds;
  final _PixelPattern _pattern;
  _RailPainter(
    this.position,
    this.baseline,
    this.intensity,
    this.seconds, {
    int seed = 0,
  }) : _pattern = _PixelPattern(.18, seed: seed),
       super(repaint: seconds);

  @override
  void paint(Canvas canvas, Size size) {
    final track = Rect.fromLTWH(
      _PixelTrack.endInset,
      (size.height - 12) / 2,
      math.max(0, size.width - 2 * _PixelTrack.endInset),
      12,
    );
    final thumbCenter = Offset(
      track.left + position * track.width,
      track.center.dy,
    );
    _pattern.update(seconds.value);
    final paint = Paint();
    final zero = track.left + baseline * track.width;
    final low = math.min(zero, thumbCenter.dx);
    final high = math.max(zero, thumbCenter.dx);
    for (
      var x = track.left + 1;
      x + _pixelSize <= track.right;
      x += _pixelPitch
    ) {
      final active = x + _pixelSize / 2 >= low && x + _pixelSize / 2 <= high;
      for (var column = 0; column < 4; column++) {
        final index = ((x - track.left - 1) / _pixelPitch).round() * 4 + column;
        paint.color = active
            ? cameraYellow
            : cameraYellow.withValues(
                alpha: .14 + _pattern.value(index) * (.136 + .04 * intensity),
              );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              x,
              track.top + 1.4 + column * _pixelPitch,
              _pixelSize,
              _pixelSize,
            ),
            const Radius.circular(.35),
          ),
          paint,
        );
      }
    }
    paint.color = cameraYellow;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: thumbCenter, width: 2, height: 14),
        const Radius.circular(.5),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_RailPainter oldDelegate) =>
      position != oldDelegate.position ||
      baseline != oldDelegate.baseline ||
      intensity != oldDelegate.intensity ||
      seconds != oldDelegate.seconds;
}

/// The same pixel size and spacing as the adjustment rails, clipped by the disk.
class CameraCaptureGrid extends StatelessWidget {
  final bool recording, animate;
  const CameraCaptureGrid({
    super.key,
    this.recording = false,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) => _PixelMotion(
    animate: recording && animate,
    builder: (seconds) => RepaintBoundary(
      child: ClipOval(
        child: CustomPaint(painter: _CaptureGridPainter(recording, seconds)),
      ),
    ),
  );
}

class _CaptureGridPainter extends CustomPainter {
  final bool recording;
  final ValueNotifier<double> seconds;
  final _pattern = _PixelPattern(.8, transitionFraction: .78);
  _CaptureGridPainter(this.recording, this.seconds) : super(repaint: seconds);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    _pattern.update(seconds.value);
    final paint = Paint();
    final columns = (size.width / _pixelPitch).ceil();
    final rows = (size.height / _pixelPitch).ceil();
    final left = (size.width - ((columns - 1) * _pixelPitch + _pixelSize)) / 2;
    final top = (size.height - ((rows - 1) * _pixelPitch + _pixelSize)) / 2;
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final index = row * columns + column;
        paint.color = recording
            ? Color.lerp(
                cameraYellow,
                const Color(0xFFFF453A),
                _pattern.value(index),
              )!
            : cameraYellow;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              left + column * _pixelPitch,
              top + row * _pixelPitch,
              _pixelSize,
              _pixelSize,
            ),
            const Radius.circular(.35),
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CaptureGridPainter oldDelegate) =>
      recording != oldDelegate.recording || seconds != oldDelegate.seconds;
}
