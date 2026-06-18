import 'dart:ui';

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
  });

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    Widget surface = ClipRRect(
      borderRadius: br,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: br,
            // Dark fill for legibility + a soft diagonal sheen for the frost.
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(Palette.sheen, fill),
                fill,
              ],
            ),
            border: borderGradient == null
                ? Border.all(color: stroke, width: 1)
                : null,
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );

    if (borderGradient != null) {
      surface = _GradientBorder(radius: radius, gradient: borderGradient!, child: surface);
    }
    if (shadow != null) {
      surface = DecoratedBox(
        decoration: BoxDecoration(borderRadius: br, boxShadow: shadow),
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
        borderRadius: br,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.alphaBlend(Palette.sheen, fill), fill],
        ),
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
            color: Palette.textHi,
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
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(0.75),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..shader = gradient.createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _BorderPainter old) =>
      old.radius != radius || old.gradient != gradient;
}
