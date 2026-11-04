import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Screen-size rules for the whole app, from [MediaQuery].
///
///   * phone   < 600 px wide
///   * tablet  600–1023 px
///   * desktop ≥ 1024 px (web / laptop)
///
/// Phone-style screens (patient, doctor, nurse, therapist, technician,
/// hospital, ambulance, login, booking, profile) are centred at
/// [phoneMaxWidth] on tablets and desktops instead of stretching edge to
/// edge. Admin and agency screens are built for wide screens and use the
/// full width.
class Responsive {
  Responsive._();

  static const double tabletMin = 600;
  static const double desktopMin = 1024;

  /// Widest a phone-style screen gets on a tablet / desktop.
  static const double phoneMaxWidth = 720;

  /// Text size limits: very large system font settings would push text out
  /// of cards and buttons.
  static const double minTextScale = 0.85;
  static const double maxTextScale = 1.3;

  /// Screen width the layouts are designed for (a typical 6.1" phone).
  static const double designWidth = 390;

  /// How much bigger or smaller than design size this screen is: 1.0 at
  /// 390 px wide, down to 0.88 on small phones, up to 1.12 on tablets and
  /// desktops (where the content column is capped, so it stays modest).
  /// Text and the main picture / avatar sizes are multiplied by it.
  static double widthFactor(BuildContext context) =>
      (width(context) / designWidth).clamp(0.88, 1.12);

  /// A size in design pixels, scaled to this screen (pictures, avatars,
  /// icons). Text does not need this: it is scaled app-wide, see
  /// [appTextScaler].
  static double scale(BuildContext context, double designPx) =>
      designPx * widthFactor(context);

  /// The text scaler for the whole app: the user's system font setting times
  /// the screen's [widthFactor], kept within [minTextScale]..[maxTextScale]
  /// so text never leaves its card.
  static TextScaler appTextScaler(MediaQueryData mq) {
    final system = mq.textScaler.scale(14) / 14;
    final factor = (mq.size.width / designWidth).clamp(0.88, 1.12);
    return TextScaler.linear(
        (system * factor).clamp(minTextScale, maxTextScale).toDouble());
  }

  static Size size(BuildContext context) => MediaQuery.sizeOf(context);
  static double width(BuildContext context) => size(context).width;
  static double height(BuildContext context) => size(context).height;

  static bool isPhone(BuildContext context) => width(context) < tabletMin;
  static bool isTablet(BuildContext context) =>
      width(context) >= tabletMin && width(context) < desktopMin;
  static bool isDesktop(BuildContext context) => width(context) >= desktopMin;

  /// Small phones (≤ 360 px): tighter padding.
  static bool isSmallPhone(BuildContext context) => width(context) <= 360;

  /// Width the content of a phone-style screen actually gets.
  static double contentWidth(BuildContext context) =>
      math.min(width(context), phoneMaxWidth);

  /// Side padding for screen content: 12 on small phones, 16 on phones,
  /// 24 on tablets / desktops.
  static double gutter(BuildContext context) => isSmallPhone(context)
      ? 12
      : isPhone(context)
          ? 16
          : 24;

  /// A dialog's width: [max] on big screens, 90% of the screen on phones.
  static double dialogWidth(BuildContext context, [double max = 420]) =>
      math.min(max, width(context) * 0.9);

  /// The current text scale factor (after the app-wide clamp).
  static double textScale(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(14) / 14;

  /// Grid of tiles: as many columns of at least [minTileWidth] as fit in the
  /// screen's content width (between [minColumns] and [maxColumns]), each
  /// [tileHeight] tall, grown with the user's font size so text never
  /// overflows the tile.
  static SliverGridDelegate grid(
    BuildContext context, {
    required double minTileWidth,
    required double tileHeight,
    double spacing = 14,
    double horizontalPadding = 32,
    int minColumns = 2,
    int maxColumns = 6,
  }) {
    final available = contentWidth(context) - horizontalPadding;
    final columns = ((available + spacing) / (minTileWidth + spacing))
        .floor()
        .clamp(minColumns, maxColumns);
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      crossAxisSpacing: spacing,
      mainAxisSpacing: spacing,
      mainAxisExtent: tileHeight * math.max(1, textScale(context)),
    );
  }
}

/// Centres a phone-style screen at [Responsive.phoneMaxWidth] on tablets and
/// desktops (page background on both sides); on phones it is the screen
/// itself.
class ResponsiveCenter extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  /// false: no page background / shadow (content over a full-width
  /// background, like the splash gradient).
  final bool framed;
  const ResponsiveCenter({
    super.key,
    required this.child,
    this.maxWidth = Responsive.phoneMaxWidth,
    this.framed = true,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (media.size.width <= maxWidth) return child;
    // the screen inside sees the frame's width, so its own MediaQuery sizes
    // (bubbles, grids) fit the frame
    final sized = MediaQuery(
      data: media.copyWith(size: Size(maxWidth, media.size.height)),
      child: child,
    );
    if (!framed) {
      return Center(child: SizedBox(width: maxWidth, child: sized));
    }
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: SizedBox(
          width: maxWidth,
          child: Material(
            elevation: 1,
            color: Theme.of(context).scaffoldBackgroundColor,
            child: sized,
          ),
        ),
      ),
    );
  }
}
