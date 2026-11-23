import 'package:flutter/material.dart';

/// An [AlertDialog] whose action buttons are all the same size and sit side
/// by side, sharing the dialog's width equally.
///
/// The app theme makes ElevatedButton / OutlinedButton fill the full width
/// (right for forms), which pushed every dialog's buttons onto their own
/// rows; a plain TextButton ("Cancel") was also much smaller than the
/// filled one next to it. Here up to three buttons share one row, each the
/// same height and width; a text button gets an outline so it reads as a
/// button of the same size.
class AppAlertDialog extends AlertDialog {
  AppAlertDialog({
    super.key,
    super.icon,
    super.iconPadding,
    super.iconColor,
    Widget? title,
    super.titlePadding,
    super.titleTextStyle,
    super.content,
    super.contentPadding,
    super.contentTextStyle,
    List<Widget>? actions,
    super.actionsPadding,
    super.actionsAlignment,
    super.actionsOverflowAlignment,
    super.actionsOverflowDirection,
    super.actionsOverflowButtonSpacing = 8,
    super.buttonPadding,
    super.backgroundColor,
    super.elevation,
    super.shadowColor,
    super.surfaceTintColor,
    super.semanticLabel,
    super.insetPadding,
    super.clipBehavior,
    super.shape,
    super.alignment,
    super.scrollable,
  }) : super(
          title: title == null ? null : _TitleWithClose(title),
          actions: actions == null || actions.isEmpty
              ? actions
              : actions.length <= 3
                  ? [DialogActionRow(actions)]
                  : [for (final a in actions) CompactDialogButton(child: a)],
        );
}

/// Dialog buttons in one row, equal width and height.
class DialogActionRow extends StatelessWidget {
  final List<Widget> actions;
  const DialogActionRow(this.actions, {super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: CompactDialogButton(child: actions[i])),
        ],
      ],
    );
  }
}

/// One size for every dialog button: filled, outlined and text buttons are
/// all [height] tall and as wide as their slot; a text button is outlined.
class CompactDialogButton extends StatelessWidget {
  final Widget child;
  const CompactDialogButton({super.key, required this.child});

  static const double height = 46;
  static const _size = WidgetStatePropertyAll(Size(64, height));
  static const _pad =
      WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10));
  static const _shape = WidgetStatePropertyAll(StadiumBorder());

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final line = t.colorScheme.outlineVariant;
    return Theme(
      data: t.copyWith(
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: (t.elevatedButtonTheme.style ?? const ButtonStyle()).copyWith(
              minimumSize: _size, padding: _pad, shape: _shape),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: (t.outlinedButtonTheme.style ?? const ButtonStyle()).copyWith(
              minimumSize: _size, padding: _pad, shape: _shape),
        ),
        textButtonTheme: TextButtonThemeData(
          style: (t.textButtonTheme.style ?? const ButtonStyle()).copyWith(
            minimumSize: _size,
            padding: _pad,
            shape: _shape,
            side: WidgetStatePropertyAll(BorderSide(color: line, width: 1.2)),
          ),
        ),
      ),
      child: DefaultTextStyle.merge(
        textAlign: TextAlign.center,
        child: child,
      ),
    );
  }
}

/// The ✕ in a popup's top corner. It only shows on popups that may be
/// closed anyway (tapping outside closes them); a popup that has to be
/// answered or is busy (payment, emergency alert) keeps no ✕.
class DialogCloseButton extends StatelessWidget {
  const DialogCloseButton({super.key});

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route is! PopupRoute || !route.barrierDismissible) {
      return const SizedBox.shrink();
    }
    return IconButton(
      tooltip: 'Close',
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.close_rounded, size: 22),
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      onPressed: () => Navigator.of(context).maybePop(),
    );
  }
}

/// The popup title with the ✕ on its right.
class _TitleWithClose extends StatelessWidget {
  final Widget title;
  const _TitleWithClose(this.title);

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: title),
          const SizedBox(width: 4),
          Transform.translate(
            offset: const Offset(8, -6),
            child: const DialogCloseButton(),
          ),
        ],
      );
}

/// A custom popup ([Dialog]) with the same ✕ in its top-right corner.
class AppDialogShell extends Dialog {
  AppDialogShell({
    super.key,
    super.backgroundColor,
    super.elevation,
    super.shadowColor,
    super.surfaceTintColor,
    super.insetAnimationDuration,
    super.insetAnimationCurve,
    super.insetPadding,
    super.clipBehavior,
    super.shape,
    super.alignment,
    Widget? child,
  }) : super(
          child: child == null
              ? null
              : Stack(children: [
                  child,
                  const Positioned(top: 4, right: 4, child: DialogCloseButton()),
                ]),
        );
}
