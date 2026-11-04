import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// The app's theme. Colours live in [AppColors]; the names below are kept
/// so existing screens keep working.
class AppTheme {
  static const String fontFamily = 'Roboto';

  // Brand colours (same palette as the care physician screens)
  static const Color primaryTeal = AppColors.primary;
  static const Color accentTeal = AppColors.accent;
  static const Color heartRed = AppColors.dangerBright;
  static const Color darkNavy = AppColors.ink;
  static const Color bgLight = AppColors.page;
  static const Color cardBg = AppColors.card;
  static const Color textDark = AppColors.ink;
  static const Color textMuted = AppColors.muted;

  // Soft pastel backgrounds for the service tiles
  static const Color pastelBlue = AppColors.pastelBlue;
  static const Color pastelGreen = AppColors.pastelGreen;
  static const Color pastelPurple = AppColors.pastelPurple;
  static const Color pastelPink = AppColors.pastelPink;
  static const Color pastelMint = AppColors.pastelMint;
  static const Color pastelYellow = AppColors.pastelYellow;

  static const LinearGradient primaryGradient = AppColors.primaryGradient;
  static const LinearGradient emergencyGradient = AppColors.emergencyGradient;

  /// One type scale for every screen (Roboto, bundled).
  static const TextTheme _textTheme = TextTheme(
    headlineSmall: TextStyle(
        fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.ink),
    titleLarge: TextStyle(
        fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ink),
    titleMedium: TextStyle(
        fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.ink),
    titleSmall: TextStyle(
        fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink),
    bodyLarge: TextStyle(fontSize: 16, color: AppColors.ink),
    bodyMedium: TextStyle(fontSize: 14, color: AppColors.ink),
    bodySmall: TextStyle(fontSize: 12, color: AppColors.muted),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
  );

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.page,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.dangerBright,
        surface: AppColors.page,
      ),
      fontFamily: fontFamily,
      textTheme: _textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.ink),
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: AppColors.ink,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      // Dialog titles were 24 px and ran off the edge on phones
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: const TextStyle(
          fontFamily: fontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: fontFamily,
          fontSize: 14,
          height: 1.4,
          color: AppColors.textBody,
        ),
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      ),
      // Selected chips are filled blue: their tick is white like the label
      chipTheme: const ChipThemeData(checkmarkColor: Colors.white),
      // Every snackbar is dark (blue, navy or red): text, action and close
      // icon are white so they are always readable
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.navy,
        contentTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 14,
          color: Colors.white,
        ),
        actionTextColor: Colors.white,
        closeIconColor: Colors.white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: Colors.white,
          // Material 3 would draw button icons in the primary colour
          // (invisible on blue buttons): icons follow the text colour
          iconColor: Colors.white,
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
          elevation: 0,
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.brand,
          iconColor: AppColors.brand,
          minimumSize: const Size(double.infinity, 50),
          side: const BorderSide(color: AppColors.brand, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.brand,
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(25),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(25),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(25),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        hintStyle: const TextStyle(color: AppColors.lineStrong, fontSize: 14),
        // long validation / help messages wrap instead of being cut off
        errorMaxLines: 3,
        helperMaxLines: 3,
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.line),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.primary : null),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.primary : null),
      ),
    );
  }
}
