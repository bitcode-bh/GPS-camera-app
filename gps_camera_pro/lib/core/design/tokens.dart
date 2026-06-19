import 'package:flutter/animation.dart';

/// Spacing scale (4-pt grid). Use these instead of magic numbers so the layout
/// stays consistent and scalable across screen sizes.
class Insets {
  Insets._();
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 28;
  static const double xxl = 40;
}

/// Corner radii. Larger panels use [lg]/[xl]; chips and pills use [pill].
class Corners {
  Corners._();
  static const double xs = 10;
  static const double sm = 14;
  static const double md = 18;
  static const double lg = 24;
  static const double xl = 32;
  static const double pill = 999;
}

/// Backdrop blur strengths. Sigma drives GPU cost linearly — these are tuned
/// to the minimum that still reads as glass on the live camera preview.
class Blurs {
  Blurs._();
  static const double chip = 6;
  static const double panel = 12;
  static const double sheet = 18;
}

/// Motion language — one emphasised easing curve and a small set of durations so
/// every transition in the app feels like it belongs to the same system.
class Motion {
  Motion._();

  /// Material 3 "emphasised" easing — confident, slightly springy settle.
  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Curve standard = Cubic(0.4, 0.0, 0.2, 1.0);
  static const Curve spring = Cubic(0.34, 1.3, 0.64, 1.0); // gentle overshoot

  static const Duration fast = Duration(milliseconds: 140);
  static const Duration normal = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 350);
  static const Duration page = Duration(milliseconds: 320);
}
