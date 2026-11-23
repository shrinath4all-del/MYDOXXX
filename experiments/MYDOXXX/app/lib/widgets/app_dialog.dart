import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_strings.dart';
import 'app_alert_dialog.dart';

/// The app's standard dialog: icon + title that wraps, scrollable content,
/// buttons that wrap on narrow phones, and a width that suits the screen.
/// Use it instead of hand-building an AlertDialog on each screen.
class AppDialog extends StatelessWidget {
  final IconData? icon;
  final Color? iconColor;
  final String title;
  final String? message;
  final Widget? content;
  final List<Widget> actions;

  const AppDialog({
    super.key,
    this.icon,
    this.iconColor,
    required this.title,
    this.message,
    this.content,
    this.actions = const [],
  });

  /// Widest a dialog gets (tablets / web); phones use the full inset width.
  static const double maxWidth = 480;

  /// Ask a yes / no question. Returns true when confirmed.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    String? message,
    Widget? content,
    IconData icon = Icons.help_outline_rounded,
    Color? color,
    String confirmLabel = AppStrings.confirm,
    String cancelLabel = AppStrings.cancel,
    bool barrierDismissible = true,
  }) async {
    final accent = color ?? AppColors.primary;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => AppDialog(
        icon: icon,
        iconColor: accent,
        title: title,
        message: message,
        content: content,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelLabel,
                style: const TextStyle(color: AppColors.muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: AppColors.onColor(accent),

            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// A message with a single button.
  static Future<void> info(
    BuildContext context, {
    required String title,
    String? message,
    Widget? content,
    IconData icon = Icons.info_outline_rounded,
    Color? color,
    String buttonLabel = AppStrings.ok,
  }) {
    final accent = color ?? AppColors.primary;
    return showDialog<void>(
      context: context,
      builder: (ctx) => AppDialog(
        icon: icon,
        iconColor: accent,
        title: title,
        message: message,
        content: content,
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: AppColors.onColor(accent),

            ),
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return AppAlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, color: iconColor ?? AppColors.primary, size: 26),
            const SizedBox(width: 10),
          ],
          Expanded(child: Text(title)),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          // leave room for the title and buttons on short phones
          maxHeight: size.height * 0.6,
        ),
        child: SizedBox(
          width: size.width,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message != null) Text(message!),
                if (message != null && content != null)
                  const SizedBox(height: 12),
                if (content != null) content!,
              ],
            ),
          ),
        ),
      ),
      // buttons go under each other instead of overflowing
      actionsOverflowButtonSpacing: 8,
      actionsOverflowAlignment: OverflowBarAlignment.end,
      actions: actions,
    );
  }
}

/// "Label …… value" line that wraps long values instead of overflowing.
class DialogInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;

  const DialogInfoRow(this.label, this.value,
      {super.key, this.valueColor, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: bold ? AppColors.ink : AppColors.muted,
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: bold ? 16 : 13,
                fontWeight: FontWeight.bold,
                color: valueColor ?? AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fee breakdown box used by every booking confirmation.
class PriceBreakdown extends StatelessWidget {
  /// The base fee, then (label, amount in ₹) extras; zero extras are skipped.
  final num base;
  final List<(String, num)> extras;
  final num total;
  final String baseLabel;

  const PriceBreakdown({
    super.key,
    required this.base,
    this.extras = const [],
    required this.total,
    this.baseLabel = AppStrings.baseFee,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.page,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          DialogInfoRow(baseLabel, '₹$base'),
          for (final (label, amount) in extras)
            if (amount != 0)
              DialogInfoRow(label, '${amount > 0 ? '+' : '−'}₹${amount.abs()}',
                  valueColor: AppColors.accent),
          const Divider(height: 16),
          DialogInfoRow(AppStrings.totalFee, '₹$total',
              valueColor: AppColors.primary, bold: true),
        ],
      ),
    );
  }
}
