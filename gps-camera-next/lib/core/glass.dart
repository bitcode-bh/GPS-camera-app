import 'dart:ui';

import 'package:flutter/material.dart';

import 'design/palette.dart';
import 'design/tokens.dart';
import 'widgets/pressable.dart';
import 'widgets/stash_glass.dart';

/// A frosted-glass surface: real backdrop blur + dark translucent fill + a top
/// specular sheen + a hairline stroke. This is the *premium* surface — it costs
/// a [BackdropFilter], so it is reserved for major panels (bottom bar, the
/// geostamp, sheets, settings groups). For the many small chips, prefer
/// [FrostedChip], which skips the blur entirely.
class GlassSurface extends StatelessWidget {
  final Widget child;
  final double radius;
  final double blur;
  final EdgeInsetsGeometry padding;
  final Color fill;
  final Color stroke;
  final Gradient? borderGradient;
  final List<BoxShadow>? shadow;
  final bool refract;
  final bool _menu;

  const GlassSurface({
    super.key,
    required this.child,
    this.radius = Corners.lg,
    this.blur = Blurs.panel,
    this.padding = EdgeInsets.zero,
    this.fill = Palette.glassFill,
    this.stroke = Palette.glassStroke,
    this.borderGradient,
    this.shadow,
    this.refract = true,
  }) : _menu = false;

  const GlassSurface.menu({
    super.key,
    required this.child,
    this.radius = 44,
    this.padding = EdgeInsets.zero,
  }) : _menu = true,
       refract = true,
       blur = Blurs.chip,
       fill = const Color(0xAD2C2C2C),
       stroke = const Color(0x42FFFFFF),
       borderGradient = null,
       shadow = null;

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    final content = Padding(padding: padding, child: child);
    Widget surface = ClipRRect(
      borderRadius: br,
      child: refract && StashGlass.supported
          ? StashGlass(
              radius: radius,
              tint: fill,
              menu: _menu,
              child: content,
            )
          : BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color.alphaBlend(Palette.sheen, fill), fill],
                  ),
                  borderRadius: br,
                  border: borderGradient == null
                      ? Border.all(color: stroke)
                      : null,
                ),
                child: content,
              ),
            ),
    );

    if (borderGradient != null) {
      surface = _GradientBorder(radius: radius, gradient: borderGradient!, child: surface);
    }
    if (shadow != null) {
      surface = DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: shadow,
          borderRadius: br,
        ),
        child: surface,
      );
    }
    return surface;
  }
}

/// A lightweight frosted chip/tile with **no** backdrop blur — just a
/// translucent fill, sheen and hairline. Visually consistent with [GlassSurface]
/// but cheap enough to use dozens of at once over the live camera feed.
class FrostedChip extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color fill;
  final Color stroke;
  final VoidCallback? onTap;

  const FrostedChip({
    super.key,
    required this.child,
    this.radius = Corners.pill,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    this.fill = Palette.glassFillStrong,
    this.stroke = Palette.glassStrokeSoft,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    final box = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.alphaBlend(Palette.sheen, fill), fill],
        ),
        borderRadius: br,
        border: Border.all(color: stroke, width: 1),
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return box;
    return Pressable(onTap: onTap, child: box);
  }
}

/// A circular glass action button (flash, settings, flip…). When [active] it
/// fills with the brand gradient to signal the toggled-on state.
class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final double size;
  final bool active;
  final String? badge;
  final Color badgeColor;
  final bool blur;
  final bool hasBorder;

  const GlassIconButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.size = 44,
    this.active = false,
    this.badge,
    this.badgeColor = Palette.warning,
    this.blur = false,
    this.hasBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(size);
    final inner = SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            icon,
            size: size * 0.44,
            color: active ? Palette.accentMuted : Palette.textHi,
          ),
          if (badge != null)
            Positioned(
              right: size * 0.18,
              bottom: size * 0.14,
              child: Text(
                badge!,
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                  color: active ? Palette.textHi : badgeColor,
                ),
              ),
            ),
        ],
      ),
    );

    Widget body;
    if (StashGlass.supported) {
      body = GlassSurface(
        radius: size / 2,
        fill: active ? Palette.selectionFill : Palette.glassFill,
        child: inner,
      );
    } else if (active) {
      body = DecoratedBox(
        decoration: BoxDecoration(
          gradient: Palette.selectionGradient,
          boxShadow: const [
            BoxShadow(
              color: Palette.selectionGlow,
              blurRadius: 16,
              spreadRadius: -2,
            ),
          ],
          shape: BoxShape.circle,
          border: Border.all(color: Palette.selectionStroke, width: 1),
        ),
        child: inner,
      );
    } else if (blur) {
      body = GlassSurface(
        radius: size,
        blur: Blurs.chip,
        stroke: hasBorder ? Palette.glassStroke : Colors.white.withValues(alpha: 0.15),
        child: inner,
      );
    } else {
      body = DecoratedBox(
        decoration: BoxDecoration(
          color: hasBorder ? null : Colors.white.withValues(alpha: 0.12),
          gradient: hasBorder
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x70121A2C), Palette.glassFillStrong],
                )
              : null,
          shape: BoxShape.circle,
          border: Border.all(
            color: hasBorder ? Palette.glassStroke : Colors.white.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: inner,
      );
    }

    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        label: label,
        button: true,
        enabled: onTap != null,
        child: Pressable(
          onTap: onTap,
          child: ClipRRect(borderRadius: br, child: body),
        ),
      ),
    );
  }
}

/// Paints a 1px gradient border around [child] (used for "selected" panels).
class _GradientBorder extends StatelessWidget {
  final double radius;
  final Gradient gradient;
  final Widget child;
  const _GradientBorder({required this.radius, required this.gradient, required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _BorderPainter(radius: radius, gradient: gradient),
      child: child,
    );
  }
}

class _BorderPainter extends CustomPainter {
  final double radius;
  final Gradient gradient;
  _BorderPainter({required this.radius, required this.gradient});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final contour = RRect.fromRectAndRadius(
      rect.deflate(0.75),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..shader = gradient.createShader(rect);
    canvas.drawRRect(contour, paint);
  }

  @override
  bool shouldRepaint(covariant _BorderPainter old) =>
      old.radius != radius || old.gradient != gradient;
}
