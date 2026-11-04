import 'package:flutter/material.dart';

import '../screens/payouts/payout_setup_screen.dart';
import '../services/payment_service.dart';
import '../constants/app_colors.dart';

/// Dashboard banner until the provider's payout bank account is active:
/// patients can't pay online for their bookings before that.
class PayoutSetupBanner extends StatelessWidget {
  final Map<String, dynamic> provider;
  final String email;
  final String phone;
  final String name;

  const PayoutSetupBanner({
    super.key,
    required this.provider,
    this.email = '',
    this.phone = '',
    this.name = '',
  });

  @override
  Widget build(BuildContext context) {
    if (PaymentService.payoutsActive(provider)) return const SizedBox.shrink();
    final status = (provider['payoutStatus'] ?? '').toString();
    final fix = status == 'needs_clarification' || status == 'suspended';
    final waiting = status == 'under_review' || status == 'requested';
    final color = fix ? AppColors.danger : AppColors.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => PayoutSetupScreen(
              provider: provider,
              defaultEmail: email,
              defaultPhone: phone,
              defaultName: name,
            ),
          )),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(
                    waiting
                        ? Icons.hourglass_top_rounded
                        : Icons.account_balance_rounded,
                    color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fix
                            ? 'Update Your Bank Details'
                            : waiting
                                ? 'Bank Details Under Verification'
                                : 'Receive Online Payments',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: color),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        fix
                            ? 'Your bank details need correction to enable online payments from patients.'
                            : waiting
                                ? 'Razorpay is verifying your bank details. Online payments start once it\'s approved.'
                                : 'Link your bank account to enable online payments from patients.',
                        style: TextStyle(fontSize: 12, color: color),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
