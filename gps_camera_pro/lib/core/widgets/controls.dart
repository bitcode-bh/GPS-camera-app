import 'package:flutter/material.dart';

import '../design/palette.dart';
import '../design/text_styles.dart';
import '../design/tokens.dart';
import 'pressable.dart';

/// A glass segmented control. It is **flat** — there is no per-option selection
/// pill; the active option is shown by colour alone (a bright white glyph +
/// label versus muted grey), inside one subtle glass track. Used for map type,
/// units, coordinate format…
class GlassSegmented<T> extends StatelessWidget {
  final List<({T value, String label})> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final double height;

  const GlassSegmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.height = 42,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Palette.glassFillStrong,
        borderRadius: BorderRadius.circular(Corners.md),
        border: Border.all(color: Palette.glassStrokeSoft),
      ),
      child: Row(
        children: [
          for (final o in options)
            Expanded(
              child: Pressable(
                onTap: () => onChanged(o.value),
                child: SizedBox(
                  height: height - 8,
                  child: Center(
                    child: Text(
                      o.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.label.copyWith(
                        color: o.value == selected
                            ? Palette.textHi
                            : Palette.textMid,
                        fontWeight: o.value == selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
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

/// A premium glass toggle switch with a frosted track when on. Pass
/// [compact] for a smaller, subtler switch in dense lists.
class GlassSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool compact;
  const GlassSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final w = compact ? 38.0 : 50.0;
    final h = compact ? 22.0 : 30.0;
    final pad = compact ? 2.5 : 3.0;
    final knob = h - pad * 2;
    return Pressable(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: Motion.normal,
        curve: Motion.emphasized,
        width: w,
        height: h,
        padding: EdgeInsets.all(pad),
        decoration: BoxDecoration(
          gradient: value ? Palette.selectionGradient : null,
          color: value ? null : Palette.glassFillStrong,
          borderRadius: BorderRadius.circular(Corners.pill),
          border: Border.all(
            color: value ? Palette.selectionStroke : Palette.glassStrokeSoft,
          ),
          boxShadow: value
              ? const [
                  BoxShadow(
                    color: Palette.selectionGlow,
                    blurRadius: 12,
                    spreadRadius: -2,
                  ),
                ]
              : null,
        ),
        child: AnimatedAlign(
          duration: Motion.normal,
          curve: Motion.spring,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: knob,
            height: knob,
            decoration: BoxDecoration(
              color: value ? Palette.textHi : Palette.textMid,
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 1)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A compact icon tile that shows a setting's current value and cycles to the
/// next value on tap — the quick-control pattern from the camera menu. It is
/// **flat**: there is no selection container, the active state is conveyed by
/// colour alone (a bright white glyph + label versus muted grey when off).
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
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: active ? Palette.accentMuted : Palette.textMid),
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
        Pressable(
          onTap: onClose,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Palette.glassFillStrong,
              border: Border.all(color: Palette.glassStrokeSoft),
            ),
            child: const Icon(Icons.close, size: 16, color: Palette.textMid),
          ),
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
