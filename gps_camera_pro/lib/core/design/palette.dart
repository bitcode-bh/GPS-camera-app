import 'package:flutter/material.dart';

/// The fixed dark palette for the GPS Camera UI.
///
/// The camera surface is always dark — it must never invert with the platform
/// light/dark setting — so every colour here is hard-coded. The signature look
/// is a cool "aurora" brand gradient (teal → cyan → indigo) over deep navy ink,
/// with frosted-glass surfaces that stay legible over an unpredictable live
/// camera feed.
class Palette {
  Palette._();

  // ── Canvas ────────────────────────────────────────────────────────────
  static const Color ink = Color(0xFF05070D); // app background base
  static const Color ink2 = Color(0xFF0B1122); // lifted surface

  // ── Brand (the signature aurora gradient) ─────────────────────────────
  static const Color teal = Color(0xFF2DE0C8);
  static const Color cyan = Color(0xFF38BDF8);
  static const Color indigo = Color(0xFF818CF8);
  static const Color violet = Color(0xFFA78BFA);

  static const List<Color> brand = [teal, cyan, indigo];
  static const List<Color> brandSoft = [Color(0xFF1FB9A6), Color(0xFF4E7BD6)];

  static const LinearGradient brandGradient = LinearGradient(
    colors: brand,
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── State accents ─────────────────────────────────────────────────────
  static const Color success = Color(0xFF34D399);
  static const Color warning = Color(0xFFFBBF24);
  static const Color danger = Color(0xFFFB7185);

  // ── Selection / active treatment (neutral glass) ──────────────────────
  // One frosted, *colourless* treatment for every active / selected /
  // toggled-on control. There is no brand accent: an "on" control reads as a
  // brighter pane of frosted glass — a lift in translucency, a crisper white
  // hairline and a whisper of glow — rather than a coloured block. Inline
  // glyphs/labels that have no surface of their own use [accentMuted] (a pure
  // bright white) to separate from the muted grey of an "off" control.
  static const Color accentMuted = Color(0xFFFFFFFF); // bright white for active glyphs

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
  static const Color textHi = Color(0xFFF3F7FC);
  static const Color textMid = Color(0xFFAAB6C8);
  static const Color textLo = Color(0xFF6B7689);
  static const Color onBrand = Color(0xFF04211F); // dark ink for text on teal

  // ── Glass surfaces ────────────────────────────────────────────────────
  // A dark translucent fill keeps frosted panels readable over a bright sky or
  // a dark interior alike; the sheen + hairline stroke sell the "glass".
  static const Color glassFill = Color(0x590A1020); // ~35% navy
  static const Color glassFillStrong = Color(0x8C0A1020); // ~55% navy
  static const Color glassStroke = Color(0x33FFFFFF); // 20% white hairline
  static const Color glassStrokeSoft = Color(0x1AFFFFFF);
  static const Color sheen = Color(0x26FFFFFF); // top specular highlight

  /// Vertical scrims that anchor controls against the live feed.
  static const Color scrimTop = Color(0xA6000000);
  static const Color scrimBottom = Color(0xCC02040A);
}
