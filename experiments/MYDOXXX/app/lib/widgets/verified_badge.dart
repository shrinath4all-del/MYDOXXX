import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Green "Verified" mark for providers the admin has approved. [compact]
/// shows only the tick (for tight rows); otherwise tick + label in a pill.
class VerifiedBadge extends StatelessWidget {
  final bool compact;
  final String label;

  const VerifiedBadge({super.key, this.compact = false, this.label = 'Verified'});

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return const Tooltip(
        message: 'Verified by MyDox',
        child: Icon(Icons.verified_rounded, color: AppColors.verified, size: 18),
      );
    }
    return Semantics(
      label: 'Verified by MyDox',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.verifiedSoft,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.verified_rounded,
                color: AppColors.verified, size: 14),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.verifiedDark,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
