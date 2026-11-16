import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/palette.dart';
import '../design/text_styles.dart';
import '../design/tokens.dart';
import '../glass.dart';

/// Each settings target owns and clips its ink; neighbouring rows never flash.
class SettingsTap extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  const SettingsTap({super.key, required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    shape: Corners.shape(Corners.sm),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      customBorder: Corners.shape(Corners.sm),
      splashColor: Palette.accentYellow.withValues(alpha: .08),
      highlightColor: Palette.accentYellow.withValues(alpha: .04),
      child: child,
    ),
  );
}

/// One fixed-size squircle glides between equal slots without resizing them.
/// Shared by settings, Video/Photo and Library/Map navigation.
class GlassSegmented<T> extends StatefulWidget {
  final List<({T value, String label})> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final double height;
  final bool enabled;

  const GlassSegmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.height = 48,
    this.enabled = true,
  });

  @override
  State<GlassSegmented<T>> createState() => _GlassSegmentedState<T>();
}

class _GlassSegmentedState<T> extends State<GlassSegmented<T>> {
  double? _drag;

  void _select(int index) {
    setState(() => _drag = null);
    if (!widget.enabled || widget.options[index].value == widget.selected) {
      return;
    }
    HapticFeedback.selectionClick();
    widget.onChanged(widget.options[index].value);
  }

  @override
  void didUpdateWidget(GlassSegmented<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled || oldWidget.options.length != widget.options.length) {
      _drag = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.options.indexWhere(
      (o) => o.value == widget.selected,
    );
    final count = widget.options.length;
    final height = math.max(
      56.0,
      math.max(
        widget.height,
        MediaQuery.textScalerOf(context).scale(12) * 1.2 + 16,
      ),
    );
    return Container(
      height: height,
      padding: const EdgeInsets.all(3),
      decoration: ShapeDecoration(
        color: Palette.glassFillStrong,
        shape: Corners.shape(
          Corners.md,
          side: const BorderSide(color: Palette.glassStrokeSoft),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final slot = constraints.maxWidth / count;
          final rtl = Directionality.of(context) == TextDirection.rtl;
          void follow(double x) {
            final position = rtl ? constraints.maxWidth - x : x;
            setState(
              () => _drag = (position / slot - .5).clamp(0.0, count - 1.0),
            );
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: widget.enabled
                ? (d) => follow(d.localPosition.dx)
                : null,
            onHorizontalDragUpdate: widget.enabled
                ? (d) => follow(d.localPosition.dx)
                : null,
            onHorizontalDragEnd: widget.enabled
                ? (_) => _select((_drag ?? selected.toDouble()).round())
                : null,
            onHorizontalDragCancel: () => setState(() => _drag = null),
            child: Stack(
              children: [
                AnimatedAlign(
                  duration:
                      _drag != null || MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : Motion.normal,
                  curve: Curves.easeOutCubic,
                  alignment: AlignmentDirectional(
                    count == 1
                        ? 0
                        : 2 * (_drag ?? selected.toDouble()) / (count - 1) - 1,
                    0,
                  ),
                  child: IgnorePointer(
                    child: Container(
                      key: const ValueKey('segment-indicator'),
                      width: slot,
                      height: height - 8,
                      decoration: ShapeDecoration(
                        color: const Color(0xFF3A3A3C),
                        shape: Corners.shape(
                          Corners.sm,
                          side: const BorderSide(
                            color: Palette.glassStrokeSoft,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < count; i++)
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: i == selected,
                          enabled: widget.enabled || i == selected,
                          child: SettingsTap(
                            onTap: widget.enabled || i == selected
                                ? () => _select(i)
                                : null,
                            child: Center(
                              child: Text(
                                widget.options[i].label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.label.copyWith(
                                  color: i == selected
                                      ? Palette.accentYellow
                                      : Palette.textMid,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One full-row, accessible on/off setting. Native switches supply drag,
/// keyboard and screen-reader behaviour and animate only when state changes.
class GlassSwitchTile extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;

  const GlassSwitchTile({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.icon,
  });

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    shape: Corners.shape(Corners.sm),
    clipBehavior: Clip.antiAlias,
    child: MergeSemantics(
      child: ListTile(
        onTap: () => onChanged(!value),
        title: Text(label, style: AppText.bodyHi),
        minLeadingWidth: 24,
        horizontalTitleGap: 12,
        leading: SizedBox.square(
          dimension: 24,
          child: icon == null
              ? null
              : Icon(
                  icon,
                  size: 20,
                  color: value ? Palette.accentYellow : Palette.textMid,
                ),
        ),
        trailing: ExcludeFocus(
          child: Transform.scale(
            scale: .6,
            // Shrink the paint while retaining the native switch hit area.
            transformHitTests: false,
            child: Switch(value: value, onChanged: onChanged),
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: Insets.xs),
        minTileHeight: 56,
        visualDensity: VisualDensity.standard,
      ),
    ),
  );
}

/// A compact icon tile that shows a setting's current value and cycles to the
/// next value on tap — the quick-control pattern from the camera menu. It is
/// **flat**: there is no selection container, the active state is conveyed by
/// colour alone (a yellow glyph + label versus muted grey when off).
class CycleTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const CycleTile({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsTap(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: active ? Palette.accentMuted : Palette.textMid,
            ),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppText.label.copyWith(
                color: active ? Palette.accentYellow : Palette.textMid,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A titled panel header shared by the camera and app-settings menus: a leading
/// glyph, the title, and a trailing round close button. Keeps both
/// quick-settings surfaces on one identical visual structure.
class PanelHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onClose;
  const PanelHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Palette.textHi),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: AppText.title)),
        GlassIconButton(
          icon: Icons.close,
          label: 'Close $title',
          size: 48,
          onTap: onClose,
        ),
      ],
    );
  }
}

/// A small uppercase section label with an optional trailing widget.
class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Row(
        children: [
          Text(text, style: AppText.caption.copyWith(color: Palette.textMid)),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}
