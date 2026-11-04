import 'package:flutter/material.dart';

/// Every colour the app uses. Screens use these names, never a raw
/// `Color(0x…)`.
///
/// The app is blue and white: the care physician navy / deep blue, light
/// blue tints, white cards and slate text. The only other colour is red,
/// kept for emergencies, errors and cancel actions so they never look like
/// a normal button. The older names (success, warning, purple, …) stay so
/// screens keep compiling, but they are all shades of the same blue now.
class AppColors {
  AppColors._();

  // Care physician blue (buttons, links, headers, selected states)
  static const Color navy = Color(0xFF075985);
  static const Color primary = Color(0xFF0369A1);
  static const Color primaryDark = Color(0xFF0C4A6E);
  static const Color primaryLight = Color(0xFF0284C7);
  static const Color primaryBorder = Color(0xFFBAE6FD);
  static const Color primarySoft = Color(0xFFE0F2FE);
  static const Color primaryTint = Color(0xFFF0F9FF);
  static const Color accent = primary;

  // Text and lines (slate greys)
  static const Color ink = Color(0xFF0F172A);
  static const Color inkSoft = Color(0xFF1E293B);
  static const Color textBody = Color(0xFF334155);
  static const Color slate = Color(0xFF475569);
  static const Color muted = Color(0xFF556376); // 5:1 on white and on the light blue tints
  static const Color lineStrong = Color(0xFFCBD5E1);
  static const Color lineSoft = Color(0xFFDDE3E8);
  static const Color line = Color(0xFFE2E8F0);
  static const Color divider = Color(0xFFE4E9ED);
  static const Color chip = Color(0xFFF1F5F9);
  static const Color page = Color(0xFFF8FAFC);
  static const Color card = Colors.white;
  static const Color white = Colors.white;

  // Success / online: blue
  static const Color success = primary;
  static const Color successDark = navy;
  static const Color successDeep = primaryDark;
  static const Color successBright = primaryLight;
  static const Color successLight = Color(0xFF7DD3FC);
  static const Color successSoft = primarySoft;
  static const Color successTint = primaryTint;
  static const Color mintTint = primaryTint;

  // Danger / emergency / errors: the one non-blue colour
  static const Color danger = Color(0xFFDC2626);
  static const Color dangerBright = Color(0xFFEF4444);
  static const Color dangerLight = Color(0xFFF87171);
  static const Color dangerSoft = Color(0xFFFEE2E2);
  static const Color dangerDeep = Color(0xFFB91C1C);

  // Verified providers: the one green, so "verified" is understood at a glance
  static const Color verified = Color(0xFF16A34A);
  static const Color verifiedDark = Color(0xFF15803D);
  static const Color verifiedSoft = Color(0xFFDCFCE7);
  static const Color verifiedLight = Color(0xFF4ADE80); // on dark headers

  // Chats: "Online" in green, unread message counts in red
  static const Color online = verified;
  static const Color unread = danger;

  // Pending / notices: blue
  static const Color warning = primary;
  static const Color warningBright = primaryLight;
  static const Color warningDeep = primaryDark;
  static const Color warningBorder = primaryBorder;
  static const Color warningSoft = primarySoft;
  static const Color warningTint = primaryTint;
  static const Color orange = primary;
  static const Color orangeTint = primaryTint;

  // Former accent colours: blue
  static const Color blue = primaryLight;
  static const Color indigo = navy;
  static const Color violet = primaryDark;
  static const Color purple = primary;
  static const Color purpleDeep = primaryDark;
  static const Color purpleSoft = primarySoft;
  static const Color pink = primaryLight;

  // Patient home service tiles: a different soft colour for each service
  static const Color pastelBlue = Color(0xFFE0F2FE);
  static const Color pastelGreen = Color(0xFFE6F4EA);
  static const Color pastelPurple = Color(0xFFF3E8FF);
  static const Color pastelPink = Color(0xFFFEE2E2);
  static const Color pastelMint = Color(0xFFECFDF5);
  static const Color pastelYellow = Color(0xFFFEF3C7);
  static const Color serviceNurse = primary;
  static const Color serviceTechnician = primary;
  static const Color serviceTherapist = primary;
  static const Color serviceCarePhysician = primary;

  /// Buttons and selected states: the care physician navy.
  static const Color brand = navy;

  /// Headers: the care physician header's navy -> deep blue.
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [navy, primary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient emergencyGradient = LinearGradient(
    colors: [danger, dangerBright],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  /// Text / icon colour that stays readable on [background]: white on dark
  /// or saturated colours, ink on light ones.
  static Color onColor(Color background) =>
      ThemeData.estimateBrightnessForColor(background) == Brightness.dark
          ? Colors.white
          : ink;
}
