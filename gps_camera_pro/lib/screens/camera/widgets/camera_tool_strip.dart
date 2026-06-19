import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../core/design/palette.dart';
import '../../../core/design/text_styles.dart';
import '../../../core/design/tokens.dart';
import '../../../core/glass.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/pressable.dart';
import '../../../models/capture_options.dart';
import '../../../services/camera_capability_service.dart';
import '../../../state/settings_controller.dart';

/// The camera quick-settings control, in three stages:
///
/// 1. **collapsed** — a single round Controls (tune) button.
/// 2. **bar** — the controls slide out to its right as a frosted,
///    horizontally-scrolling strip of flat icons; the button becomes an
///    up-arrow.
/// 3. **panel** — tapping the up-arrow swaps to a two-row panel that drops down
///    and shows every control at once (no scrolling); its header has a close
///    button back to collapsed.
///
/// Active state is shown by **icon colour only** (bright white vs muted grey) —
/// no selection container. Flash / Exposure / Focus / Level are driven by the
/// camera screen via callbacks; the rest are backed by [SettingsController].
class CameraToolStrip extends StatefulWidget {
  final FlashMode flash;
  final VoidCallback onFlash;
  final bool focusLocked;
  final VoidCallback onFocus;
  final bool level;
  final VoidCallback onLevel;
  final double exposure;
  final bool canExpose;
  final VoidCallback onExposure;

  /// Kept for API compatibility with the camera screen layout.
  final bool alignLeft;

  /// Reports open/closed so the parent can hide the opposite-side control.
  final ValueChanged<bool>? onOpenChanged;

  /// Fires `true` when entering panel mode, `false` when leaving it.
  final ValueChanged<bool>? onPanelChanged;

  final bool open;

  const CameraToolStrip({
    super.key,
    required this.open,
    required this.flash,
    required this.onFlash,
    required this.focusLocked,
    required this.onFocus,
    required this.level,
    required this.onLevel,
    required this.exposure,
    required this.canExpose,
    required this.onExposure,
    this.alignLeft = false,
    this.onOpenChanged,
    this.onPanelChanged,
  });

  @override
  State<CameraToolStrip> createState() => _CameraToolStripState();
}

/// The three display stages of the strip.
enum _ToolView { collapsed, bar, panel }

class _CameraToolStripState extends State<CameraToolStrip> {
  final _s = SettingsController.instance;
  late _ToolView _view;

  @override
  void initState() {
    super.initState();
    _view = widget.open ? _ToolView.bar : _ToolView.collapsed;
  }

  @override
  void didUpdateWidget(covariant CameraToolStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The parent can force the strip closed (e.g. a tap-to-focus on the frame).
    if (oldWidget.open != widget.open && !widget.open) {
      _view = _ToolView.collapsed;
    }
  }

  ({IconData icon, String label}) get _flashInfo => switch (widget.flash) {
        FlashMode.auto => (icon: Icons.flash_auto, label: 'Auto'),
        FlashMode.always => (icon: Icons.flash_on, label: 'On'),
        FlashMode.off => (icon: Icons.flash_off, label: 'Off'),
        FlashMode.torch => (icon: Icons.highlight, label: 'Torch'),
      };

  void _setView(_ToolView v) {
    final wasPanel = _view == _ToolView.panel;
    final isPanel = v == _ToolView.panel;
    setState(() => _view = v);
    widget.onOpenChanged?.call(v != _ToolView.collapsed);
    if (wasPanel != isPanel) widget.onPanelChanged?.call(isPanel);
  }

  // A flick past this speed (logical px/s) counts as an intentional swipe.
  static const double _swipeVel = 120;

  @override
  Widget build(BuildContext context) {
    final isOpen = _view != _ToolView.collapsed;
    final isPanel = _view == _ToolView.panel;
    // alignLeft: button on left, strip expands right.
    // !alignLeft: button on right, strip expands left.
    final expandRight = widget.alignLeft;
    // Read MediaQuery once here so helper methods don't trigger subtree rebuilds.
    final screenWidth = MediaQuery.sizeOf(context).width;

    final toggleBtn = _circle(
      icon: isOpen ? Icons.close : Icons.photo_camera_outlined,
      active: isOpen,
      onTap: isOpen
          ? () => _setView(_ToolView.collapsed)
          : () => _setView(_ToolView.bar),
    );

    final expandingStrip = ClipRect(
      child: AnimatedAlign(
        alignment: expandRight ? Alignment.centerLeft : Alignment.centerRight,
        duration: Motion.normal,
        curve: Motion.emphasized,
        widthFactor: isOpen ? 1.0 : 0.0,
        child: AnimatedOpacity(
          opacity: isOpen ? 1.0 : 0.0,
          duration: Motion.normal,
          curve: Motion.emphasized,
          child: _revealStrip(expandRight: expandRight, screenWidth: screenWidth),
        ),
      ),
    );

    // Collapsed and bar share a persistent Row so the strip can slide in/out
    // without swapping widget trees (which would kill transitions).
    final row = GestureDetector(
      key: const ValueKey('row'),
      behavior: HitTestBehavior.translucent,
      onVerticalDragEnd: (d) {
        final vel = d.primaryVelocity ?? 0;
        if (isOpen && vel > _swipeVel) {
          _setView(_ToolView.panel);
        } else if (isOpen && vel < -_swipeVel) {
          _setView(_ToolView.collapsed);
        }
      },
      onVerticalDragUpdate: (d) {
        final dy = d.primaryDelta ?? 0;
        if (isOpen && dy > 8) {
          _setView(_ToolView.panel);
        } else if (isOpen && dy < -8) {
          _setView(_ToolView.collapsed);
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: expandRight
            ? [toggleBtn, expandingStrip]
            : [expandingStrip, toggleBtn],
      ),
    );

    // Dynamic grid layout panel. Swipe up to collapse back to collapsed (closed).
    final panel = GestureDetector(
      key: const ValueKey('panel'),
      behavior: HitTestBehavior.translucent,
      onVerticalDragEnd: (d) {
        final vel = d.primaryVelocity ?? 0;
        if (vel < -_swipeVel) {
          _setView(_ToolView.collapsed);
        }
      },
      onVerticalDragUpdate: (d) {
        final dy = d.primaryDelta ?? 0;
        if (dy < -8) {
          _setView(_ToolView.collapsed);
        }
      },
      child: _panel(screenWidth: screenWidth),
    );

    // AnimatedSwitcher cross-fades between the row and panel layouts;
    // AnimatedSize smoothly animates the bounding box as heights differ.
    final stackAlign = expandRight ? Alignment.topLeft : Alignment.topRight;
    return AnimatedSize(
      duration: Motion.normal,
      curve: Motion.emphasized,
      alignment: stackAlign,
      clipBehavior: Clip.antiAlias,
      child: AnimatedSwitcher(
        duration: Motion.normal,
        switchInCurve: Motion.emphasized,
        switchOutCurve: Motion.emphasized,
        transitionBuilder: (child, anim) =>
            FadeTransition(opacity: anim, child: child),
        layoutBuilder: (currentChild, previousChildren) => Stack(
          alignment: stackAlign,
          clipBehavior: Clip.none,
          children: [
            ...previousChildren,
            ?currentChild,
          ],
        ),
        child: isPanel ? panel : row,
      ),
    );
  }

  // ── The round toggle button ───────────────────────────────────────────
  Widget _circle({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.normal,
        curve: Motion.emphasized,
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: active ? Palette.selectionGradient : null,
          color: active ? null : Palette.glassFillStrong,
          border: Border.all(
              color: active ? Palette.selectionStroke : Palette.glassStroke),
          boxShadow: active
              ? const [
                  BoxShadow(
                    color: Palette.selectionGlow,
                    blurRadius: 14,
                    spreadRadius: -3,
                  )
                ]
              : null,
        ),
        child: AnimatedSwitcher(
          duration: Motion.fast,
          transitionBuilder: (c, anim) => ScaleTransition(
            scale: anim,
            child: FadeTransition(opacity: anim, child: c),
          ),
          child: Icon(
            icon,
            key: ValueKey(icon),
            size: active ? 24 : 20,
            color: Palette.textHi,
          ),
        ),
      ),
    );
  }

  // ── Stage 2: the horizontally-scrolling icon strip ────────────────────
  Widget _revealStrip({bool expandRight = true, required double screenWidth}) {
    final maxW = screenWidth - 96;
    return Padding(
      padding: expandRight
          ? const EdgeInsets.only(left: 8)
          : const EdgeInsets.only(right: 8),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: GlassSurface(
          radius: Corners.pill,
          blur: Blurs.chip,
          fill: Palette.glassFillStrong,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: ListenableBuilder(
            listenable: _s,
            builder: (context, _) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final t in _tools()) SizedBox(width: 54, child: t),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Stage 3: the drop-down panel ──────────────────────────────────────
  Widget _panel({required double screenWidth}) {
    final maxW = screenWidth - 40;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW),
      child: GlassSurface(
        radius: Corners.lg,
        blur: Blurs.panel,
        fill: Palette.glassFillStrong,
        padding: const EdgeInsets.fromLTRB(Insets.md, Insets.sm, Insets.md, Insets.md),
        child: ListenableBuilder(
          listenable: _s,
          builder: (context, _) {
            final t = _tools();
            final rowCount = (t.length > 10) ? 3 : 2;
            final perRow = (t.length / rowCount).ceil();

            // Slice into fixed-width rows and pad the final row with empty
            // slots so every column lines up on the same grid — keeping icon
            // spacing, sizing and positioning uniform across the whole menu.
            final rows = <List<Widget>>[];
            for (int i = 0; i < rowCount; i++) {
              final start = i * perRow;
              if (start >= t.length) break;
              final end = (start + perRow).clamp(0, t.length);
              final row = t.sublist(start, end);
              while (row.length < perRow) {
                row.add(const SizedBox.shrink());
              }
              rows.add(row);
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PanelHeader(
                  icon: Icons.tune,
                  title: 'Camera Settings',
                  onClose: () => _setView(_ToolView.collapsed),
                ),
                const SizedBox(height: Insets.sm),
                for (int i = 0; i < rows.length; i++) ...[
                  if (i > 0) const SizedBox(height: Insets.sm),
                  _toolRow(rows[i]),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _toolRow(List<Widget> items) =>
      Row(children: [for (final w in items) Expanded(child: w)]);

  List<Widget> _tools() {
    final f = _flashInfo;
    return <Widget>[
      _ToolTile(
        icon: _s.proMode ? Icons.tune_rounded : Icons.auto_awesome,
        label: _s.proMode ? 'Pro' : 'Auto',
        active: _s.proMode,
        onTap: () => _s.update(() => _s.proMode = !_s.proMode),
      ),
      if (CameraCapabilityService.instance.hasFlash)
        _ToolTile(
          icon: f.icon,
          label: f.label,
          active: widget.flash != FlashMode.off,
          onTap: widget.onFlash,
        ),
      if (CameraCapabilityService.instance.hasHdr)
        _ToolTile(
          icon: _s.hdrMode == HdrMode.off
              ? Icons.hdr_off
              : (_s.hdrMode == HdrMode.auto ? Icons.hdr_auto : Icons.hdr_on),
          label: _s.hdrMode == HdrMode.auto
              ? 'HDR Auto'
              : (_s.hdrMode == HdrMode.on ? 'HDR On' : 'HDR Off'),
          active: _s.hdrMode != HdrMode.off,
          onTap: () => _s.update(() {
            const modes = HdrMode.values;
            _s.hdrMode = modes[(modes.indexOf(_s.hdrMode) + 1) % modes.length];
          }),
        ),
      if (CameraCapabilityService.instance.hasNight)
        _ToolTile(
          icon: _s.nightMode == NightMode.on ? Icons.nightlight_round : Icons.nightlight_outlined,
          label: _s.nightMode == NightMode.on ? 'Night On' : 'Night Off',
          active: _s.nightMode == NightMode.on,
          onTap: () => _s.update(() {
            _s.nightMode = _s.nightMode == NightMode.on ? NightMode.off : NightMode.on;
          }),
        ),
      _ToolTile(
        icon: _s.timerSeconds == 0 ? Icons.timer_off_outlined : Icons.timer_outlined,
        label: _s.timerSeconds == 0 ? 'Off' : '${_s.timerSeconds}s',
        active: _s.timerSeconds != 0,
        onTap: () => _s.update(() {
          const order = [0, 3, 10];
          _s.timerSeconds = order[(order.indexOf(_s.timerSeconds) + 1) % order.length];
        }),
      ),
      _ToolTile(
        icon: Icons.aspect_ratio,
        label: _s.captureRatio.label,
        active: _s.captureRatio != CaptureRatio.full,
        onTap: () => _s.update(() {
          const r = CaptureRatio.values;
          _s.captureRatio = r[(r.indexOf(_s.captureRatio) + 1) % r.length];
        }),
      ),
      _ToolTile(
        icon: Icons.camera_outlined,
        label: CameraCapabilityService.instance
            .resolutionAt(_s.captureResolutionIndex)
            .mpLabel,
        active: _s.captureResolutionIndex <
            CameraCapabilityService.instance.resolutions.length - 1
                ? true
                : _s.captureResolutionIndex == 0,
        onTap: () => _s.update(() {
          final count =
              CameraCapabilityService.instance.resolutions.length;
          _s.captureResolutionIndex =
              (_s.captureResolutionIndex + 1) % count;
        }),
      ),
      _ToolTile(
        icon: Icons.grid_3x3,
        label: !_s.gridLines
            ? 'Off'
            : (_s.gridType == GridType.thirds
                ? '3x3'
                : (_s.gridType == GridType.square ? '4x4' : 'Golden')),
        active: _s.gridLines,
        onTap: () => _s.update(() {
          if (!_s.gridLines) {
            _s.gridLines = true;
            _s.gridType = GridType.thirds;
          } else if (_s.gridType == GridType.thirds) {
            _s.gridType = GridType.square;
          } else if (_s.gridType == GridType.square) {
            _s.gridType = GridType.golden;
          } else {
            _s.gridLines = false;
          }
        }),
      ),
      _ToolTile(
        icon: widget.level ? Icons.straighten : Icons.straighten,
        label: widget.level ? 'On' : 'Off',
        active: widget.level,
        onTap: widget.onLevel,
      ),
      _ToolTile(
        icon: Icons.bar_chart,
        label: _s.histogram ? 'On' : 'Off',
        active: _s.histogram,
        onTap: () => _s.update(() => _s.histogram = !_s.histogram),
      ),
      _ToolTile(
        icon: widget.focusLocked ? Icons.center_focus_strong : Icons.center_focus_weak,
        label: widget.focusLocked ? 'Lock' : 'Auto',
        active: widget.focusLocked,
        onTap: widget.onFocus,
      ),
      _ToolTile(
        icon: Icons.exposure,
        label: widget.canExpose
            ? '${widget.exposure > 0 ? '+' : ''}${widget.exposure.toStringAsFixed(widget.exposure % 1 == 0 ? 0 : 1)}'
            : '—',
        active: widget.exposure != 0,
        onTap: widget.canExpose ? widget.onExposure : () {},
      ),
      if (CameraCapabilityService.instance.manualFocus)
        _ToolTile(
          icon: Icons.center_focus_strong,
          label: _s.focusPeaking ? 'Peak On' : 'Peak Off',
          active: _s.focusPeaking,
          onTap: () => _s.update(() => _s.focusPeaking = !_s.focusPeaking),
        ),
      _ToolTile(
        icon: Icons.warning_amber,
        label: _s.zebraStripes ? 'Zebra On' : 'Zebra Off',
        active: _s.zebraStripes,
        onTap: () => _s.update(() => _s.zebraStripes = !_s.zebraStripes),
      ),
      _ToolTile(
        icon: Icons.save_alt,
        label: _s.saveOriginal ? 'Orig On' : 'Orig Off',
        active: _s.saveOriginal,
        onTap: () => _s.update(() => _s.saveOriginal = !_s.saveOriginal),
      ),
      _ToolTile(
        icon: Icons.flip,
        label: _s.mirror ? 'On' : 'Off',
        active: _s.mirror,
        onTap: () => _s.update(() => _s.mirror = !_s.mirror),
      ),
      _ToolTile(
        icon: _s.shutterSound ? Icons.volume_up_outlined : Icons.volume_off_outlined,
        label: _s.shutterSound ? 'On' : 'Off',
        active: _s.shutterSound,
        onTap: () => _s.update(() => _s.shutterSound = !_s.shutterSound),
      ),
      _ToolTile(
        icon: Icons.location_on_outlined,
        label: _s.saveLocation ? 'GPS On' : 'GPS Off',
        active: _s.saveLocation,
        onTap: () => _s.update(() => _s.saveLocation = !_s.saveLocation),
      ),
    ];
  }
}

/// A flat quick-control tile: an icon over a tiny label, with **no** selection
/// container. The active state is conveyed purely by colour — a bright white
/// glyph and label versus muted grey when off.
class _ToolTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ToolTile({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: SizedBox(
        height: 60,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 21, color: active ? Palette.accentMuted : Palette.textMid),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppText.caption.copyWith(
                fontSize: 9,
                letterSpacing: 0.2,
                color: active ? Palette.textHi : Palette.textMid,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
