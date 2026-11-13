import 'package:flutter/material.dart';

import 'design/palette.dart';
import 'design/text_styles.dart';
import 'design/tokens.dart';

/// The single dark theme for the app. The camera surface never inverts with the
/// platform setting, so only a dark theme is provided.
class AppTheme {
  AppTheme._();

  static ThemeData dark() {
    const accent = Palette.accentMuted;
    const panel = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(Corners.lg)),
    );
    const chip = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(Corners.sm)),
    );
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
      surface: Palette.ink,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Palette.ink,
      colorScheme: scheme.copyWith(
        primary: accent,
        secondary: accent,
        surface: Palette.ink,
      ),
      splashFactory: InkRipple.splashFactory,
      textTheme: const TextTheme(
        displaySmall: AppText.display,
        headlineSmall: AppText.h1,
        titleLarge: AppText.h2,
        titleMedium: AppText.title,
        bodyMedium: AppText.body,
        labelLarge: AppText.label,
        labelSmall: AppText.caption,
      ),
      dialogTheme: const DialogThemeData(shape: panel),
      textButtonTheme: const TextButtonThemeData(
        style: ButtonStyle(shape: WidgetStatePropertyAll(chip)),
      ),
      tooltipTheme: const TooltipThemeData(
        decoration: ShapeDecoration(color: Palette.ink2, shape: chip),
        textStyle: TextStyle(color: Palette.textHi),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(),
        elevation: 0,
        backgroundColor: Palette.surfaceSolid,
        contentTextStyle: AppText.bodyHi,
        insetPadding: EdgeInsets.fromLTRB(16, 0, 16, 24),
      ),
    );
  }
}
