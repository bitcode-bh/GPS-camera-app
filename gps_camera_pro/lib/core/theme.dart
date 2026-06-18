import 'package:flutter/material.dart';

import 'design/palette.dart';
import 'design/text_styles.dart';

/// The single dark theme for the app. The camera surface never inverts with the
/// platform setting, so only a dark theme is provided.
class AppTheme {
  AppTheme._();

  static ThemeData dark() {
    // Neutral, colourless seed — the UI is fully custom glassmorphism, so the
    // Material accent only ever shows through as ripples, cursors and selection
    // handles; keep those a clean light grey rather than a brand colour.
    const neutralAccent = Color(0xFFE6ECF4);
    final scheme = ColorScheme.fromSeed(
      seedColor: neutralAccent,
      brightness: Brightness.dark,
      surface: Palette.ink,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Palette.ink,
      colorScheme: scheme.copyWith(
        primary: neutralAccent,
        secondary: const Color(0xFFAAB6C8),
        surface: Palette.ink,
      ),
      splashFactory: InkSparkle.splashFactory,
      textTheme: const TextTheme(
        displaySmall: AppText.display,
        headlineSmall: AppText.h1,
        titleLarge: AppText.h2,
        titleMedium: AppText.title,
        bodyMedium: AppText.body,
        labelLarge: AppText.label,
        labelSmall: AppText.caption,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Palette.ink2,
        contentTextStyle: AppText.bodyHi,
        insetPadding: EdgeInsets.fromLTRB(16, 0, 16, 24),
      ),
    );
  }
}
