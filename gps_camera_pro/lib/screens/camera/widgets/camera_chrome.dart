import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/design/palette.dart';
import '../../../core/design/text_styles.dart';
import '../../../core/design/tokens.dart';
import '../../../core/glass.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/ticking_builder.dart';
import '../../../state/settings_controller.dart';
import '../../../services/camera_capability_service.dart';

/// A soft pulsing dot used on status chips.
class PulseDot extends StatefulWidget {
  final Color color;
  final bool pulse;
  final double size;
  const PulseDot({super.key, required this.color, this.pulse = true, this.size = 7});

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
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
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.9), blurRadius: 8)],
      ),
    );
    if (!widget.pulse) return dot;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(_c),
      child: dot,
    );
  }
}

/// Top-left GPS status chip.
class GpsLockChip extends StatelessWidget {
  final String accuracy;
  final bool live;
  const GpsLockChip({super.key, required this.accuracy, required this.live});

  @override
  Widget build(BuildContext context) {
    return FrostedChip(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PulseDot(color: live ? Palette.success : Palette.warning, pulse: live),
          const SizedBox(width: 7),
          Text(
            live ? 'GPS LOCK · $accuracy' : 'DEMO FIX',
            style: AppText.caption.copyWith(color: Palette.textHi, letterSpacing: 0.4),
          ),
        ],
      ),
    );
  }
}

/// Top-right live clock + date chip (ticks in isolation).
class ClockChip extends StatelessWidget {
  final bool clock24;
  const ClockChip({super.key, required this.clock24});

  @override
  Widget build(BuildContext context) {
    return FrostedChip(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      child: TickingBuilder(
        builder: (context, now) {
          final t = TimeOfDay.fromDateTime(now);
          final hh = clock24
              ? now.hour.toString().padLeft(2, '0')
              : ((t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod)).toString();
          final mm = now.minute.toString().padLeft(2, '0');
          final ss = now.second.toString().padLeft(2, '0');
          final ap = now.hour < 12 ? 'AM' : 'PM';
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$hh:$mm', style: AppText.mono.copyWith(fontSize: 13)),
              Text(':$ss', style: AppText.mono.copyWith(fontSize: 13, color: Palette.textLo)),
              if (!clock24) ...[
                const SizedBox(width: 4),
                Text(ap, style: AppText.caption.copyWith(color: Palette.textMid)),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Horizontal zoom selector (pill). The active level fills with the brand
/// gradient and the live value is shown there.
class ZoomSelector extends StatelessWidget {
  final double zoom;
  final List<double> levels;
  final ValueChanged<double> onChanged;
  const ZoomSelector({
    super.key,
    required this.zoom,
    required this.onChanged,
    this.levels = const [0.5, 1, 2, 5],
  });

  @override
  Widget build(BuildContext context) {
    final active =
        levels.reduce((a, b) => (a - zoom).abs() < (b - zoom).abs() ? a : b);
    return FrostedChip(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final l in levels)
            Pressable(
              onTap: () => onChanged(l),
              child: AnimatedContainer(
                duration: Motion.fast,
                curve: Motion.emphasized,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: EdgeInsets.symmetric(
                  horizontal: l == active ? 11 : 8,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  gradient: l == active ? Palette.selectionGradient : null,
                  borderRadius: BorderRadius.circular(Corners.pill),
                  border: l == active
                      ? Border.all(color: Palette.selectionStroke, width: 1)
                      : null,
                ),
                child: Text(
                  l == active
                      ? '${zoom.toStringAsFixed(zoom < 1 ? 1 : (zoom % 1 == 0 ? 0 : 1))}×'
                      : (l < 1 ? '.5' : l.toStringAsFixed(0)),
                  style: AppText.label.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: l == active ? Palette.textHi : Palette.textMid,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The capture-mode strip (Photo / Video / …) with a sliding active indicator.
class ModeStrip extends StatelessWidget {
  final List<String> modes;
  final int active;
  final ValueChanged<int> onChanged;
  const ModeStrip({
    super.key,
    required this.modes,
    required this.active,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        shrinkWrap: true,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: modes.length,
        separatorBuilder: (_, _) => const SizedBox(width: 18),
        itemBuilder: (context, i) {
          final on = i == active;
          return Pressable(
            onTap: () => onChanged(i),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  modes[i],
                  style: AppText.caption.copyWith(
                    fontSize: 11,
                    letterSpacing: 1.0,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                    color: on ? Palette.textHi : Palette.textLo,
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedContainer(
                  duration: Motion.normal,
                  curve: Motion.emphasized,
                  height: 3,
                  width: on ? 16 : 0,
                  decoration: BoxDecoration(
                    color: Palette.accentMuted,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The hero shutter button — gradient ring, springy press, busy spinner.
class ShutterButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool busy;
  final bool video;
  const ShutterButton({super.key, required this.onTap, this.busy = false, this.video = false});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      scale: 0.9,
      onTap: busy ? null : onTap,
      child: SizedBox(
        width: 46,
        height: 46,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Core.
            AnimatedContainer(
              duration: Motion.normal,
              curve: Motion.emphasized,
              width: busy ? 24 : (video ? 24 : 46),
              height: busy ? 24 : (video ? 24 : 46),
              decoration: BoxDecoration(
                color: video ? Palette.danger : Colors.white,
                shape: video ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: video ? BorderRadius.circular(busy ? 6 : 8) : null,
              ),
            ),
            if (busy)
              const SizedBox(
                width: 46,
                height: 46,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation(Palette.accentMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Rounded thumbnail of the most recent in-session capture; tapping opens the
/// phone's gallery app.
class GalleryThumb extends StatelessWidget {
  final Uint8List? thumb;
  final VoidCallback onTap;
  final bool hasBorder;
  const GalleryThumb({
    super.key,
    required this.thumb,
    required this.onTap,
    this.hasBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Corners.sm),
          border: Border.all(
            color: hasBorder ? Palette.glassStroke : Colors.white.withValues(alpha: 0.15),
            width: 1.2,
          ),
          color: hasBorder ? Palette.glassFillStrong : Colors.white.withValues(alpha: 0.12),
        ),
        child: thumb != null
            ? Image.memory(thumb!,
                fit: BoxFit.cover, gaplessPlayback: true, cacheWidth: 144)
            : const Icon(Icons.photo_library_outlined,
                size: 20, color: Palette.textMid),
      ),
    );
  }
}

/// A clean vertical zoom selector with no outer container — just the levels
/// in a column, with a vertical track line and an animated indicator next to it.
/// A circular glass button that displays text instead of an icon (used for aspect ratio).
class GlassTextButton extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final double size;
  final bool active;
  final bool hasBorder;

  const GlassTextButton({
    super.key,
    required this.text,
    this.onTap,
    this.size = 46,
    this.active = false,
    this.hasBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(size);
    final inner = SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Text(
          text,
          style: AppText.label.copyWith(
            fontSize: text.length > 3 ? 9.5 : 12,
            fontWeight: FontWeight.w700,
            color: Palette.textHi,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );

    Widget body;
    if (active) {
      body = DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: Palette.selectionGradient,
          border: Border.all(color: Palette.selectionStroke, width: 1),
          boxShadow: const [
            BoxShadow(
              color: Palette.selectionGlow,
              blurRadius: 16,
              spreadRadius: -2,
            ),
          ],
        ),
        child: inner,
      );
    } else {
      body = DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: hasBorder ? null : Colors.white.withValues(alpha: 0.12),
          gradient: hasBorder
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x70121A2C), Palette.glassFillStrong],
                )
              : null,
          border: Border.all(
            color: hasBorder ? Palette.glassStroke : Colors.white.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: inner,
      );
    }

    return Pressable(
      onTap: onTap,
      child: ClipRRect(borderRadius: br, child: body),
    );
  }
}

/// A clean vertical zoom and exposure selector with a vertical track behind the values.
/// Displays zoom values or exposure values depending on the active mode, highlighting the active selection.
enum ProControlMode {
  zoom,
  exposure,
  iso,
  shutter,
  wb,
  focus,
  metering
}

class ProControlSelector extends StatelessWidget {
  final ProControlMode mode;
  final double zoom;
  final double exposure;
  final SettingsController settings;
  final CameraCapabilityService caps;
  final List<double> zoomLevels;
  final List<double> exposureLevels;

  final ValueChanged<double> onZoomChanged;
  final ValueChanged<double> onExposureChanged;
  final ValueChanged<int?> onIsoChanged;
  final ValueChanged<int?> onShutterChanged;
  final ValueChanged<ProWhiteBalance> onWbChanged;
  final ValueChanged<double> onFocusChanged;
  final ValueChanged<MeteringMode> onMeteringChanged;

  const ProControlSelector({
    super.key,
    required this.mode,
    required this.zoom,
    required this.exposure,
    required this.settings,
    required this.caps,
    required this.zoomLevels,
    required this.exposureLevels,
    required this.onZoomChanged,
    required this.onExposureChanged,
    required this.onIsoChanged,
    required this.onShutterChanged,
    required this.onWbChanged,
    required this.onFocusChanged,
    required this.onMeteringChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Build discrete items based on the active mode
    final List<({double value, String label})> items = [];
    double activeValue = 0;

    switch (mode) {
      case ProControlMode.zoom:
        for (final l in zoomLevels) {
          items.add((value: l, label: l < 1 ? '.5x' : '${l.toStringAsFixed(0)}x'));
        }
        activeValue = zoom;
        break;
      case ProControlMode.exposure:
        // Use integer EV stops only to avoid duplicate labels from fine hardware
        // steps (e.g. 1/3-stop increments that all round to the same integer).
        // Cap at ±3 to keep the vertical list compact within the 180px track.
        if (exposureLevels.isNotEmpty) {
          final minStop = exposureLevels.last.ceil().clamp(-3, 0);
          final maxStop = exposureLevels.first.floor().clamp(0, 3);
          for (int stop = maxStop; stop >= minStop; stop--) {
            final target = stop.toDouble();
            final nearest = exposureLevels.reduce(
              (a, b) => (a - target).abs() < (b - target).abs() ? a : b,
            );
            items.add((value: nearest, label: '${stop > 0 ? '+' : ''}$stop'));
          }
        }
        if (items.isEmpty) items.add((value: 0.0, label: '0'));
        activeValue = exposure;
        break;
      case ProControlMode.iso:
        final isoValues = caps.isoValues();
        if (isoValues.isEmpty) {
          items.add((value: 0.0, label: 'Auto'));
        } else {
          items.add((value: 0.0, label: 'Auto'));
          final step = (isoValues.length - 1) / 3;
          final Set<int> sampledIndices = {0, isoValues.length - 1};
          for (int i = 1; i <= 2; i++) {
            sampledIndices.add((i * step).round());
          }
          final sortedIndices = sampledIndices.toList()..sort();
          for (final idx in sortedIndices) {
            final val = isoValues[idx];
            items.add((value: (idx + 1).toDouble(), label: '$val'));
          }
        }
        activeValue = settings.proIso == null
            ? 0.0
            : (isoValues.indexOf(settings.proIso!) + 1).toDouble();
        break;
      case ProControlMode.shutter:
        final shutters = caps.shutterSpeedsNs();
        if (shutters.isEmpty) {
          items.add((value: 0.0, label: 'Auto'));
        } else {
          items.add((value: 0.0, label: 'Auto'));
          final step = (shutters.length - 1) / 3;
          final Set<int> sampledIndices = {0, shutters.length - 1};
          for (int i = 1; i <= 2; i++) {
            sampledIndices.add((i * step).round());
          }
          final sortedIndices = sampledIndices.toList()..sort();
          for (final idx in sortedIndices) {
            final val = shutters[idx];
            items.add((value: (idx + 1).toDouble(), label: _formatShutterShort(val)));
          }
        }
        activeValue = settings.proShutterNs == null
            ? 0.0
            : (shutters.indexOf(settings.proShutterNs!) + 1).toDouble();
        break;
      case ProControlMode.wb:
        if (settings.whiteBalance == ProWhiteBalance.kelvin) {
          // Kelvin temperature scale — 5 sampled stops. No "K" suffix since
          // the chip label already shows the unit.
          const kelvinStops = [2500.0, 3500.0, 5000.0, 6500.0, 8000.0];
          for (final k in kelvinStops) {
            items.add((value: k, label: '${k.toInt()}'));
          }
          activeValue = settings.kelvin.toDouble();
        } else {
          final wbOptions = supportedWhiteBalances(caps);
          final step = (wbOptions.length - 1) / 4;
          final Set<int> sampledIndices = {};
          for (int i = 0; i <= 4; i++) {
            final idx = (i * step).round().clamp(0, wbOptions.length - 1);
            sampledIndices.add(idx);
          }
          final sortedIndices = sampledIndices.toList()..sort();
          for (final idx in sortedIndices) {
            final opt = wbOptions[idx];
            items.add((value: idx.toDouble(), label: opt.shortLabel));
          }
          activeValue = wbOptions.indexOf(settings.whiteBalance).toDouble();
        }
        break;
      case ProControlMode.focus:
        items.addAll([
          (value: 0.0, label: 'Auto'),
          (value: 0.25, label: '0.25'),
          (value: 0.5, label: '0.5'),
          (value: 0.75, label: '0.75'),
          (value: 1.0, label: 'Macro'),
        ]);
        activeValue = settings.manualFocus;
        break;
      case ProControlMode.metering:
        final modes = MeteringMode.values;
        for (int i = 0; i < modes.length; i++) {
          items.add((value: i.toDouble(), label: modes[i].shortLabel));
        }
        activeValue = modes.indexOf(settings.meteringMode).toDouble();
        break;
    }

    final activeItem = items.reduce(
      (a, b) => (a.value - activeValue).abs() < (b.value - activeValue).abs() ? a : b,
    );

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 2,
          height: 180,
          decoration: BoxDecoration(
            color: Colors.white12,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        Positioned(
          height: 180,
          child: AnimatedAlign(
            duration: Motion.fast,
            curve: Motion.emphasized,
            alignment: Alignment(
              0,
              items.length <= 1
                  ? 0
                  : (items.indexOf(activeItem) / (items.length - 1)) * 2 - 1,
            ),
            child: Container(
              width: 2,
              height: 36,
              decoration: BoxDecoration(
                color: Palette.accentMuted,
                borderRadius: BorderRadius.circular(1),
                boxShadow: const [
                  BoxShadow(
                    color: Palette.selectionGlow,
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in items)
              Pressable(
                onTap: () {
                  switch (mode) {
                    case ProControlMode.zoom:
                      onZoomChanged(item.value);
                      break;
                    case ProControlMode.exposure:
                      onExposureChanged(item.value);
                      break;
                    case ProControlMode.iso:
                      final isoValues = caps.isoValues();
                      final idx = item.value.round();
                      onIsoChanged(idx == 0 ? null : isoValues[idx - 1]);
                      break;
                    case ProControlMode.shutter:
                      final shutters = caps.shutterSpeedsNs();
                      final idx = item.value.round();
                      onShutterChanged(idx == 0 ? null : shutters[idx - 1]);
                      break;
                    case ProControlMode.wb:
                      if (settings.whiteBalance == ProWhiteBalance.kelvin) {
                        settings.update(() => settings.kelvin = item.value.round());
                        onWbChanged(ProWhiteBalance.kelvin);
                      } else {
                        final wbOptions = supportedWhiteBalances(caps);
                        onWbChanged(wbOptions[item.value.round()]);
                      }
                      break;
                    case ProControlMode.focus:
                      onFocusChanged(item.value);
                      break;
                    case ProControlMode.metering:
                      onMeteringChanged(MeteringMode.values[item.value.round()]);
                      break;
                  }
                },
                child: AnimatedContainer(
                  duration: Motion.fast,
                  curve: Motion.emphasized,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: item.value == activeItem.value
                        ? Palette.selectionFill
                        : Colors.transparent,
                    border: Border.all(
                      color: item.value == activeItem.value
                          ? Palette.selectionStroke
                          : Colors.transparent,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    item.label,
                    style: AppText.label.copyWith(
                      fontSize: 10,
                      fontWeight: item.value == activeItem.value ? FontWeight.w800 : FontWeight.w600,
                      color: item.value == activeItem.value ? Palette.accentMuted : Palette.textHi,
                      shadows: const [
                        Shadow(color: Colors.black, blurRadius: 4),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  String _formatShutterShort(int ns) {
    if (ns >= 1000000000) {
      return '${(ns / 1000000000).toStringAsFixed(0)}s';
    }
    return '1/${(1000000000 / ns).toStringAsFixed(0)}';
  }
}

/// A full-width horizontal Pro Control bar that displays the current mode and
/// its available values. Supports swipe gestures to cycle through values.
/// Reuses the zoom control interaction pattern for consistency.
class ProControlBar extends StatefulWidget {
  final ProControlMode mode;
  final double zoom;
  final double exposure;
  final SettingsController settings;
  final CameraCapabilityService caps;
  final List<double> zoomLevels;
  final List<double> exposureLevels;
  
  final ValueChanged<double> onZoomChanged;
  final ValueChanged<double> onExposureChanged;
  final ValueChanged<int?> onIsoChanged;
  final ValueChanged<int?> onShutterChanged;
  final ValueChanged<ProWhiteBalance> onWbChanged;
  final ValueChanged<double> onFocusChanged;
  final ValueChanged<MeteringMode> onMeteringChanged;

  const ProControlBar({
    super.key,
    required this.mode,
    required this.zoom,
    required this.exposure,
    required this.settings,
    required this.caps,
    required this.zoomLevels,
    required this.exposureLevels,
    required this.onZoomChanged,
    required this.onExposureChanged,
    required this.onIsoChanged,
    required this.onShutterChanged,
    required this.onWbChanged,
    required this.onFocusChanged,
    required this.onMeteringChanged,
  });

  @override
  State<ProControlBar> createState() => _ProControlBarState();
}

class _ProControlBarState extends State<ProControlBar> {
  final ScrollController _scroll = ScrollController();

  // Fixed width per value tick — lets us centre the active value precisely.
  static const double _itemExtent = 56;
  // Drag distance that moves the selection by one value (continuous feel).
  static const double _dragStepPx = 24;

  // Live drag state: latest item list, selected index, and a fractional cursor
  // that lets the drag glide through values continuously like the zoom control.
  List<({double value, String label})> _items = const [];
  int _activeIndex = 0;
  double _dragIndex = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// The full, un-sampled value list for the active mode plus the index of the
  /// currently-selected value. The scale shows every value (not a sampled few)
  /// so the live selection is always visible and accurate.
  ({List<({double value, String label})> items, int activeIndex}) _buildItems() {
    final items = <({double value, String label})>[];
    int activeIndex = 0;

    switch (widget.mode) {
      case ProControlMode.zoom:
        for (final l in widget.zoomLevels) {
          items.add((value: l, label: l < 1 ? '.5x' : '${l.toStringAsFixed(0)}x'));
        }
        activeIndex = _nearest(items, widget.zoom);
        break;
      case ProControlMode.exposure:
        for (final l in widget.exposureLevels) {
          final txt = (l % 1 == 0) ? l.toStringAsFixed(0) : l.toStringAsFixed(1);
          items.add((value: l, label: '${l > 0 ? '+' : ''}$txt'));
        }
        activeIndex = _nearest(items, widget.exposure);
        break;
      case ProControlMode.iso:
        items.add((value: -1, label: 'Auto'));
        final isoValues = widget.caps.isoValues();
        for (final v in isoValues) {
          items.add((value: v.toDouble(), label: '$v'));
        }
        activeIndex = widget.settings.proIso == null
            ? 0
            : isoValues.indexOf(widget.settings.proIso!) + 1;
        break;
      case ProControlMode.shutter:
        items.add((value: -1, label: 'Auto'));
        final shutters = widget.caps.shutterSpeedsNs();
        for (final v in shutters) {
          items.add((value: v.toDouble(), label: _formatShutterShort(v)));
        }
        activeIndex = widget.settings.proShutterNs == null
            ? 0
            : shutters.indexOf(widget.settings.proShutterNs!) + 1;
        break;
      case ProControlMode.wb:
        if (widget.settings.whiteBalance == ProWhiteBalance.kelvin) {
          // Mode label shows "K"; items show just the number to avoid duplication.
          for (int k = 2500; k <= 8000; k += 500) {
            items.add((value: k.toDouble(), label: '$k'));
          }
          activeIndex = _nearest(items, widget.settings.kelvin.toDouble());
        } else {
          final wbOptions = supportedWhiteBalances(widget.caps);
          for (int i = 0; i < wbOptions.length; i++) {
            items.add((value: i.toDouble(), label: wbOptions[i].shortLabel));
          }
          activeIndex = wbOptions.indexOf(widget.settings.whiteBalance);
        }
        break;
      case ProControlMode.focus:
        // Label steps with real distances derived from the hardware's minimum
        // focus distance (diopters, 1/m). 0 = auto/infinity, 1 = closest.
        final mfd = widget.caps.minFocusDistance;
        const fracs = [0.0, 0.25, 0.5, 0.75, 1.0];
        for (final f in fracs) {
          String label;
          if (f == 0) {
            label = 'Auto';
          } else if (mfd != null && mfd > 0) {
            final m = 1.0 / (f * mfd); // diopters → metres
            label = m >= 1 ? '${m.toStringAsFixed(m >= 10 ? 0 : 1)}m' : '${(m * 100).round()}cm';
          } else {
            label = f == 1.0 ? 'Macro' : f.toStringAsFixed(2);
          }
          items.add((value: f, label: label));
        }
        activeIndex = _nearest(items, widget.settings.manualFocus);
        break;
      case ProControlMode.metering:
        final modes = MeteringMode.values;
        for (int i = 0; i < modes.length; i++) {
          items.add((value: i.toDouble(), label: modes[i].shortLabel));
        }
        activeIndex = modes.indexOf(widget.settings.meteringMode);
        break;
    }
    if (activeIndex < 0) activeIndex = 0;
    return (items: items, activeIndex: activeIndex.clamp(0, items.length - 1));
  }

  int _nearest(List<({double value, String label})> items, double value) {
    var best = 0;
    var bestDist = double.infinity;
    for (int i = 0; i < items.length; i++) {
      final d = (items[i].value - value).abs();
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }

  /// Applies the value at [index] for the active mode. Auto sentinels (value -1
  /// for ISO/shutter) map back to a null setting.
  void _applyIndex(List<({double value, String label})> items, int index) {
    final value = items[index].value;
    switch (widget.mode) {
      case ProControlMode.zoom:
        widget.onZoomChanged(value);
        break;
      case ProControlMode.exposure:
        widget.onExposureChanged(value);
        break;
      case ProControlMode.iso:
        widget.onIsoChanged(value < 0 ? null : value.round());
        break;
      case ProControlMode.shutter:
        widget.onShutterChanged(value < 0 ? null : value.round());
        break;
      case ProControlMode.wb:
        if (widget.settings.whiteBalance == ProWhiteBalance.kelvin) {
          widget.settings.update(() => widget.settings.kelvin = value.round());
          widget.onWbChanged(ProWhiteBalance.kelvin);
        } else {
          final wbOptions = supportedWhiteBalances(widget.caps);
          widget.onWbChanged(wbOptions[value.round()]);
        }
        break;
      case ProControlMode.focus:
        widget.onFocusChanged(value);
        break;
      case ProControlMode.metering:
        widget.onMeteringChanged(MeteringMode.values[value.round()]);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final built = _buildItems();
    final items = built.items;
    final activeIndex = built.activeIndex;
    if (items.isEmpty) return const SizedBox.shrink();
    _items = items;
    _activeIndex = activeIndex;

    return GestureDetector(
      onHorizontalDragStart: (_) => _dragIndex = _activeIndex.toDouble(),
      onHorizontalDragUpdate: (details) {
        if (_items.isEmpty) return;
        // Swipe right → lower index (previous), left → higher (next), continuous.
        _dragIndex = (_dragIndex - details.delta.dx / _dragStepPx)
            .clamp(0, (_items.length - 1).toDouble());
        final ni = _dragIndex.round();
        if (ni != _activeIndex) _applyIndex(_items, ni);
      },
      child: FrostedChip(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mode label
            Text(
              _getModeLabel(widget.mode),
              style: AppText.label.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Palette.textMid,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 12),
            // Value ruler — every value is shown; the active one is centred and
            // highlighted, and re-centres whenever the selection changes.
            Expanded(
              child: SizedBox(
                height: 30,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final vw = constraints.maxWidth;
                    final sidePad = (vw - _itemExtent) / 2;
                    // Re-centre the active value after layout.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!_scroll.hasClients) return;
                      final target = (activeIndex * _itemExtent).clamp(
                        _scroll.position.minScrollExtent,
                        _scroll.position.maxScrollExtent,
                      );
                      if ((_scroll.offset - target).abs() > 0.5) {
                        _scroll.animateTo(
                          target,
                          duration: Motion.fast,
                          curve: Motion.emphasized,
                        );
                      }
                    });
                    return ListView.builder(
                      controller: _scroll,
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.symmetric(
                          horizontal: sidePad.clamp(0, double.infinity)),
                      itemExtent: _itemExtent,
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final active = i == activeIndex;
                        return Center(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _applyIndex(items, i),
                            child: AnimatedContainer(
                              duration: Motion.fast,
                              curve: Motion.emphasized,
                              padding: EdgeInsets.symmetric(
                                horizontal: active ? 11 : 6,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                gradient: active ? Palette.selectionGradient : null,
                                borderRadius: BorderRadius.circular(Corners.pill),
                                border: active
                                    ? Border.all(color: Palette.selectionStroke, width: 1)
                                    : null,
                              ),
                              child: Text(
                                items[i].label,
                                maxLines: 1,
                                overflow: TextOverflow.visible,
                                softWrap: false,
                                style: AppText.label.copyWith(
                                  fontSize: active ? 11 : 9.5,
                                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                                  color: active ? Palette.textHi : Palette.textMid,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getModeLabel(ProControlMode mode) {
    if (mode == ProControlMode.wb &&
        widget.settings.whiteBalance == ProWhiteBalance.kelvin) {
      return 'K';
    }
    return switch (mode) {
      ProControlMode.zoom => 'ZOOM',
      ProControlMode.exposure => 'EXPO',
      ProControlMode.iso => 'ISO',
      ProControlMode.shutter => 'SHUTTER',
      ProControlMode.wb => 'WB',
      ProControlMode.focus => 'FOCUS',
      ProControlMode.metering => 'METERING',
    };
  }

  String _formatShutterShort(int ns) {
    if (ns >= 1000000000) {
      return '${(ns / 1000000000).toStringAsFixed(0)}s';
    }
    return '1/${(1000000000 / ns).toStringAsFixed(0)}';
  }
}

/// A clean horizontal zoom selector with no outer container — just the levels
/// in a row, the active one wrapped in a small brand-gradient pill.
class ZoomBar extends StatelessWidget {
  final double zoom;
  final List<double> levels;
  final ValueChanged<double> onChanged;
  const ZoomBar({
    super.key,
    required this.zoom,
    required this.onChanged,
    this.levels = const [0.5, 1, 2, 5],
  });

  @override
  Widget build(BuildContext context) {
    final active =
        levels.reduce((a, b) => (a - zoom).abs() < (b - zoom).abs() ? a : b);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final l in levels)
          Pressable(
            onTap: () => onChanged(l),
            child: AnimatedContainer(
              duration: Motion.fast,
              curve: Motion.emphasized,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              padding: EdgeInsets.symmetric(
                  horizontal: l == active ? 12 : 4, vertical: 6),
              decoration: BoxDecoration(
                gradient: l == active ? Palette.selectionGradient : null,
                borderRadius: BorderRadius.circular(Corners.pill),
                border: l == active
                    ? Border.all(color: Palette.selectionStroke, width: 1)
                    : null,
              ),
              child: Text(
                l == active
                    ? '${zoom.toStringAsFixed(zoom < 1 ? 1 : (zoom % 1 == 0 ? 0 : 1))}×'
                    : (l < 1 ? '.5' : l.toStringAsFixed(0)),
                style: AppText.label.copyWith(
                  fontSize: l == active ? 12 : 12.5,
                  fontWeight: FontWeight.w700,
                  color: Palette.textHi,
                  shadows: l == active
                      ? null
                      : const [Shadow(color: Colors.black54, blurRadius: 6)],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A compact Photo/Video toggle that sits next to the camera-switch button.
class ModeToggle extends StatelessWidget {
  final List<String> modes;
  final int active;
  final ValueChanged<int> onChanged;
  const ModeToggle({
    super.key,
    required this.modes,
    required this.active,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Palette.glassFillStrong,
        borderRadius: BorderRadius.circular(Corners.pill),
        border: Border.all(color: Palette.glassStrokeSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < modes.length; i++)
            Pressable(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: Motion.fast,
                curve: Motion.emphasized,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  gradient: i == active ? Palette.selectionGradient : null,
                  borderRadius: BorderRadius.circular(Corners.pill),
                  border: i == active
                      ? Border.all(color: Palette.selectionStroke, width: 1)
                      : null,
                ),
                child: Icon(
                  i == 0 ? Icons.photo_camera : Icons.videocam,
                  size: 16,
                  color: i == active ? Palette.textHi : Palette.textMid,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The white-balance presets the *hardware* actually supports, derived from the
/// camera2 AWB mode list. Falls back to Auto (+ Kelvin if the device reports
/// manual/OFF support) when no mode list was detected.
List<ProWhiteBalance> supportedWhiteBalances(CameraCapabilityService caps) {
  // camera2 CONTROL_AWB_MODE constants.
  int? code(ProWhiteBalance w) => switch (w) {
        ProWhiteBalance.auto => 1,
        ProWhiteBalance.incandescent => 2,
        ProWhiteBalance.fluorescent => 3,
        ProWhiteBalance.daylight => 5,
        ProWhiteBalance.cloudy => 6,
        ProWhiteBalance.shade => 8,
        ProWhiteBalance.kelvin => 0, // OFF = manual
      };
  final modes = caps.whiteBalanceModes;
  if (modes.isEmpty) {
    return [
      ProWhiteBalance.auto,
      if (caps.kelvinWhiteBalance) ProWhiteBalance.kelvin,
    ];
  }
  final out = <ProWhiteBalance>[];
  for (final w in ProWhiteBalance.values) {
    if (w == ProWhiteBalance.kelvin) {
      if (caps.kelvinWhiteBalance || modes.contains(0)) out.add(w);
      continue;
    }
    final c = code(w);
    if (c != null && modes.contains(c)) out.add(w);
  }
  if (out.isEmpty) out.add(ProWhiteBalance.auto);
  return out;
}

extension ProWhiteBalanceExt on ProWhiteBalance {
  String get label => switch (this) {
        ProWhiteBalance.auto => 'Auto',
        ProWhiteBalance.daylight => 'Daylight',
        ProWhiteBalance.cloudy => 'Cloudy',
        ProWhiteBalance.shade => 'Shade',
        ProWhiteBalance.fluorescent => 'Fluorescent',
        ProWhiteBalance.incandescent => 'Incandescent',
        ProWhiteBalance.kelvin => 'Kelvin',
      };

  String get shortLabel => switch (this) {
        ProWhiteBalance.auto => 'Auto',
        ProWhiteBalance.daylight => 'Day',
        ProWhiteBalance.cloudy => 'Cloud',
        ProWhiteBalance.shade => 'Shade',
        ProWhiteBalance.fluorescent => 'Fluo',
        ProWhiteBalance.incandescent => 'Tung',
        ProWhiteBalance.kelvin => 'K',
      };
}

extension MeteringModeExt on MeteringMode {
  String get label => switch (this) {
        MeteringMode.matrix => 'Matrix',
        MeteringMode.center => 'Center',
        MeteringMode.spot => 'Spot',
      };

  String get shortLabel => switch (this) {
        MeteringMode.matrix => 'Mat',
        MeteringMode.center => 'Ctr',
        MeteringMode.spot => 'Spot',
      };
}
