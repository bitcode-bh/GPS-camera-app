import 'package:flutter/material.dart';

import 'design/palette.dart';
import 'design/tokens.dart';
import 'widgets/pressable.dart';

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
  });

  const GlassSurface.menu({
    super.key,
    required this.child,
    this.radius = 44,
    this.padding = EdgeInsets.zero,
  }) : refract = true,
       blur = Blurs.chip,
       fill = const Color(0xAD2C2C2C),
       stroke = const Color(0x42FFFFFF),
       borderGradient = null,
       shadow = null;

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    final content = Padding(padding: padding, child: child);
    // Solid by design: no backdrop blur, refraction, sheen or tint.
    Widget surface = ClipRSuperellipse(
      borderRadius: br,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: Palette.surfaceSolid,
          shape: Corners.shape(
            radius,
            side: borderGradient == null
                ? const BorderSide(color: Palette.strokeSolid)
                : BorderSide.none,
          ),
        ),
        child: content,
      ),
    );

    if (borderGradient != null) {
      surface = _GradientBorder(
        radius: radius,
        gradient: borderGradient!,
        child: surface,
      );
    }
    if (shadow != null) {
      surface = DecoratedBox(
        decoration: ShapeDecoration(
          shadows: shadow,
          shape: Corners.shape(radius),
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
    final box = DecoratedBox(
      decoration: ShapeDecoration(
        color: Palette.surfaceSolid,
        shape: Corners.shape(
          radius,
          side: const BorderSide(color: Palette.strokeSolid),
        ),
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return box;
    return Pressable(onTap: onTap, child: box);
  }
}

/// A squircle glass action button (flash, settings, flip…). When [active] it
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
    final br = BorderRadius.circular(Corners.md);
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

    // Solid squircle; the active state uses a lighter fill.
    final body = DecoratedBox(
      decoration: ShapeDecoration(
        color: active ? const Color(0xFF3A3A3C) : Palette.surfaceSolid,
        shape: Corners.shape(
          Corners.md,
          side: hasBorder
              ? const BorderSide(color: Palette.strokeSolid)
              : BorderSide.none,
        ),
      ),
      child: inner,
    );

    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        label: label,
        button: true,
        enabled: onTap != null,
        child: Pressable(
          onTap: onTap,
          child: ClipRSuperellipse(borderRadius: br, child: body),
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
  const _GradientBorder({
    required this.radius,
    required this.gradient,
    required this.child,
  });

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
    final contour = Corners.shape(radius).getOuterPath(rect.deflate(0.75));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..shader = gradient.createShader(rect);
    canvas.drawPath(contour, paint);
  }

  @override
  bool shouldRepaint(covariant _BorderPainter old) =>
      old.radius != radius || old.gradient != gradient;
}
