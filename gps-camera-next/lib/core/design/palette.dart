import 'package:flutter/material.dart';

/// The dark color tokens from Stash 0.28.0.
class Palette {
  Palette._();

  // ── Canvas ────────────────────────────────────────────────────────────
  static const Color ink = Color(0xFF19151B); // app background base
  static const Color ink2 = Color(0xFF221D25); // lifted surface

  /// Notices, menus and chips: one neutral, opaque surface. No blur, no tint.
  static const Color surfaceSolid = Color(0xFF1C1C1E);
  static const Color strokeSolid = Color(0x1FFFFFFF);

  // ── Accent ─────────────────────────────
  static const Color teal = Color(0xFFA9B8FF);
  static const Color cyan = Color(0xFFA9B8FF);
  static const Color indigo = Color(0xFFA9B8FF);
  static const Color violet = Color(0xFFA9B8FF);

  static const List<Color> brand = [teal, cyan, indigo];
  static const List<Color> brandSoft = [Color(0xFFA9B8FF), Color(0xFFA9B8FF)];

  static const LinearGradient brandGradient = LinearGradient(
    colors: brand,
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── State accents ─────────────────────────────────────────────────────
  static const Color success = Color(0xFF35C759);
  static const Color warning = Color(0xFFFBBF24);
  static const Color danger = Color(0xFFFF6B6B);

  static const Color accentMuted = Color(0xFFA9B8FF);

  /// Brighter frost used as the fill of a selected pill / segment / toggle.
  static const LinearGradient selectionGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x33FFFFFF), Color(0x14FFFFFF)],
  );

  /// Flat fill variant (segments over an already-dark surface).
  static const Color selectionFill = Color(0x29FFFFFF); // ~16% white
  static const Color selectionStroke = Color(0x73FFFFFF); // ~45% white hairline
  static const Color selectionGlow = Color(0x14FFFFFF); // whisper white glow

  // ── Text ──────────────────────────────────────────────────────────────
  static const Color textHi = Color(0xFFF2F1EC);
  static const Color textMid = Color(0xFFB3ACB8);
  static const Color textLo = Color(0xFF8E8794);
  static const Color onBrand = Color(0xFF14131C);

  // ── Glass surfaces ────────────────────────────────────────────────────
  // A dark translucent fill keeps frosted panels readable over a bright sky or
  // a dark interior alike; the sheen + hairline stroke sell the "glass".
  static const Color glassFill = Color(0x5928222C); // ~35% navy
  static const Color glassFillStrong = Color(0x8C28222C); // ~55% navy
  static const Color glassStroke = Color(0x33FFFFFF); // 20% white hairline
  static const Color glassStrokeSoft = Color(0x1AFFFFFF);
  static const Color sheen = Color(0x26FFFFFF); // top specular highlight

  /// Vertical scrims that anchor controls against the live feed.
  static const Color scrimTop = Color(0xA6000000);
  static const Color scrimBottom = Color(0xCC02040A);
}
