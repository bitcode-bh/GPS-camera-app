import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/widgets/pressable.dart';

const cameraYellow = Color(0xFFFFDB55);

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

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0, .3, .72],
            colors: [Color(0x778A8989), Color(0x99373632), Color(0xE8202020)],
          ),
          border: Border.all(color: const Color(0x66FFFFFF)),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0, .012, .05, 1],
              colors: [
                Color(0x55FFFFFF),
                Color(0x10FFFFFF),
                Colors.transparent,
                Colors.transparent,
              ],
            ),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    ),
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
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: plain ? Colors.transparent : const Color(0xFF262626),
              border: ring ? Border.all(color: cameraYellow, width: 2) : null,
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
    return SizedBox(
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
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 12,
                    trackShape: _PixelTrack(
                      _position(
                        (baseline ?? (exposure ? 0.0 : min)).clamp(min, max),
                      ),
                    ),
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
                    color: Color(0xFFF5EBFF),
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
    );
  }
}

class _PixelTrack extends RoundedRectSliderTrackShape {
  static const endInset = 11.0;
  final double baseline;

  const _PixelTrack(this.baseline);

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
  }) {
    final track = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
    );
    final canvas = context.canvas;
    final paint = Paint()..color = const Color(0xFF29272F);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          offset.dx,
          track.top,
          offset.dx + parentBox.size.width,
          track.bottom,
        ),
        const Radius.circular(5),
      ),
      paint,
    );
    paint.color = const Color(0xFFE1D7FA);
    for (var stop = 0; stop <= 5; stop++) {
      canvas.drawCircle(
        Offset(track.left + stop * track.width / 5, track.center.dy),
        1,
        paint,
      );
    }
    final zero = track.left + baseline * track.width;
    final low = math.min(zero, thumbCenter.dx);
    final high = math.max(zero, thumbCenter.dx);
    const dotSize = 1.7;
    const pitch = 2.5;
    for (var x = track.left + 1; x + dotSize <= track.right; x += pitch) {
      if (x + dotSize / 2 < low || x + dotSize / 2 > high) continue;
      for (var column = 0; column < 4; column++) {
        final distance = (thumbCenter.dx - x).abs();
        final shimmer = (math.cos(x * .13 + column * 2.4) + 1) * .13;
        final intensity = (.42 + shimmer + .3 * (1 - distance / track.width))
            .clamp(0.0, 1.0);
        paint.color = Color.lerp(
          const Color(0xFF514169),
          const Color(0xFFDFCBFF),
          intensity,
        )!;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              x,
              track.top + 1.4 + column * pitch,
              dotSize,
              dotSize,
            ),
            const Radius.circular(.35),
          ),
          paint,
        );
      }
    }
    paint.color = const Color(0xFFFBF9F4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: thumbCenter, width: 11, height: 8),
        const Radius.circular(3),
      ),
      paint,
    );
  }
}
