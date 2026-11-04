import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../services/chat_access_service.dart';

/// Before a payment: if the patient has MedCoins (1 MedCoin = ₹1), ask
/// whether to use them. Returns true (use MedCoins), false (pay in cash) or
/// null (cancelled). With no MedCoins it returns false at once, with no popup.
Future<bool?> askUseMedCoins(
  BuildContext context, {
  required String patientUid,
  required num price,
}) async {
  int balance = 0;
  try {
    balance = await ChatAccessService.walletBalance(patientUid).first;
  } catch (_) {}
  if (balance <= 0 || !context.mounted) return false;

  final cost = price.round();
  final used = balance < cost ? balance : cost;
  final cash = cost - used;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(children: [
        const Icon(Icons.account_balance_wallet_rounded,
            color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(child: Text('You have $balance MedCoins')),
      ]),
      content: Text(
        cash == 0
            ? 'Pay the whole ₹$cost with $used MedCoins?'
            : 'Use $used MedCoins and pay ₹$cash by card or UPI?',
        style: const TextStyle(height: 1.4),
      ),
      actionsOverflowButtonSpacing: 4,
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('No, pay ₹$cost')),
        ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Use MedCoins')),
      ],
    ),
  );
}
