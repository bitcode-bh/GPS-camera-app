import 'package:flutter/material.dart';

import 'palette.dart';

/// The app type scale. The platform UI font is used (no network font fetch —
/// keeps the app lightweight and offline-safe), but the scale, weights and
/// tracking are tuned for a premium, instrument-like feel.
///
/// Numeric readouts (coordinates, time, metrics) use [mono]/[metric] with
/// tabular figures so digits never jitter as values tick.
class AppText {
  AppText._();

  static const String _family = '.SF Pro Text'; // resolves to system UI font

  static const TextStyle display = TextStyle(
    fontFamily: _family,
    fontSize: 30,
    height: 1.05,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: Palette.textHi,
  );

  static const TextStyle h1 = TextStyle(
    fontSize: 23,
    height: 1.1,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    color: Palette.textHi,
  );

  static const TextStyle h2 = TextStyle(
    fontSize: 18,
    height: 1.15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: Palette.textHi,
  );

  static const TextStyle title = TextStyle(
    fontSize: 15,
    height: 1.2,
    fontWeight: FontWeight.w600,
    color: Palette.textHi,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    height: 1.35,
    fontWeight: FontWeight.w400,
    color: Palette.textMid,
  );

  static const TextStyle bodyHi = TextStyle(
    fontSize: 14,
    height: 1.35,
    fontWeight: FontWeight.w500,
    color: Palette.textHi,
  );

  static const TextStyle label = TextStyle(
    fontSize: 12.5,
    height: 1.2,
    fontWeight: FontWeight.w500,
    color: Palette.textMid,
  );

  /// Uppercase micro caption used on chips and field labels.
  static const TextStyle caption = TextStyle(
    fontSize: 10,
    height: 1.1,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.9,
    color: Palette.textLo,
  );

  /// Numeric readout — tabular figures, medium weight.
  static const TextStyle metric = TextStyle(
    fontSize: 13,
    height: 1.2,
    fontWeight: FontWeight.w600,
    color: Palette.textHi,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Larger numeric headline (clock, hero coordinate).
  static const TextStyle mono = TextStyle(
    fontSize: 16,
    height: 1.1,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
    color: Palette.textHi,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
