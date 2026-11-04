import 'package:flutter/material.dart';

/// Dialog details may grow, but response controls stay inside the viewport.
/// Explicit constraints avoid Dialog's default 280px minimum plus its insets.
class ScrollableActionDialog extends StatelessWidget {
  const ScrollableActionDialog({
    super.key,
    required this.body,
    required this.actions,
    this.shape,
    this.backgroundColor = Colors.white,
  });

  final Widget body;
  final Widget actions;
  final ShapeBorder? shape;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 560),
        shape: shape ??
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: backgroundColor,
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                key: const ValueKey('action-dialog-details'),
                padding: const EdgeInsets.all(16),
                child: body,
              ),
            ),
            const Divider(height: 1),
            Padding(
              key: const ValueKey('action-dialog-footer'),
              padding: const EdgeInsets.all(12),
              child: actions,
            ),
          ],
        ),
      );
}
