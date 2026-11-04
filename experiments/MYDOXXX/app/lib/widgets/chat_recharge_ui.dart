import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../services/chat_access_service.dart';
import '../services/payment_service.dart';
import '../utils/chat_access.dart';
import '../utils/error_messages.dart';
import 'medcoins_choice.dart';

/// What the patient chose in the chat-closed popup.
enum _ClosedChoice { recharge, single }

/// The popup shown to the patient when the chat time is over or the free
/// messages are used up. "Recharge" opens the paid plans (25 messages);
/// once the chat time is over, "Send one message" is the ₹200 single
/// message.
Future<void> showChatClosedPopup(
  BuildContext context, {
  required String chatId,
  required ChatAccessState reason,
  String peerName = 'your doctor',
}) async {
  final choice = await showDialog<_ClosedChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(children: [
        const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(reason == ChatAccessState.limitReached
              ? 'Messages used up'
              : 'Chat time is over'),
        ),
      ]),
      content: Text(
        reason == ChatAccessState.limitReached
            ? 'You have used all your messages for this chat. Recharge to get ${ChatAccess.paidMessages} more messages.'
            : 'The 24 hours of chat after your consultation are over. Recharge for ${ChatAccess.paidMessages} more messages, or send a single message to $peerName.',
        style: const TextStyle(height: 1.4),
      ),
      actionsOverflowButtonSpacing: 4,
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Not now')),
        if (reason == ChatAccessState.timeOver)
          OutlinedButton(
              onPressed: () => Navigator.pop(ctx, _ClosedChoice.single),
              child: const Text('Send one message')),
        ElevatedButton(
            onPressed: () => Navigator.pop(ctx, _ClosedChoice.recharge),
            child: const Text('Recharge')),
      ],
    ),
  );
  if (!context.mounted) return;
  if (choice == _ClosedChoice.recharge) {
    await showChatRechargeSheet(context, chatId: chatId, reason: reason);
  } else if (choice == _ClosedChoice.single) {
    await showSingleMessageOffer(context, chatId: chatId, peerName: peerName);
  }
}

/// The single message after the consultation: the popup shows the price
/// (₹200, from the `single` plan in Firestore), explains it and takes the
/// payment only after the patient confirms. [followUp]: the doctor has just
/// sent a follow-up message and this is the patient's way to answer it.
Future<void> showSingleMessageOffer(
  BuildContext context, {
  required String chatId,
  required String peerName,
  bool followUp = false,
}) async {
  final plan = await showDialog<RechargePlan>(
    context: context,
    builder: (ctx) => StreamBuilder<RechargePlan?>(
      stream: ChatAccessService.singlePlan(),
      builder: (ctx, snap) {
        final p = snap.data;
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(children: [
            const Icon(Icons.mark_chat_unread_outlined,
                color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
                child: Text(followUp
                    ? '$peerName sent you a message'
                    : 'Send a single message')),
          ]),
          content: !snap.hasData && !snap.hasError
              ? const SizedBox(
                  height: 60,
                  child: Center(child: CircularProgressIndicator()))
              : p == null
                  ? const Text(
                      'Single messages are not available yet. Please recharge the chat instead.')
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${followUp ? 'Your chat time is over. To reply, ' : ''}'
                          'pay ₹${p.price} to send one message to $peerName. '
                          '$peerName then has 24 hours to reply.',
                          style: const TextStyle(height: 1.4),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'You are charged only after you confirm. If there is no reply within 4 hours of your message, the amount goes back to your wallet as MedCoins.',
                          style: TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                              color: AppColors.muted),
                        ),
                      ],
                    ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(followUp ? 'Not now' : 'Cancel')),
            if (p != null)
              ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, p),
                  child: Text('Pay ₹${p.price}')),
          ],
        );
      },
    ),
  );
  if (plan == null || !context.mounted) return;
  final patientUid = chatId.split('_').first;
  final useCoins =
      await askUseMedCoins(context, patientUid: patientUid, price: plan.price);
  if (useCoins == null) return;
  final result = await PaymentService.payForChatRecharge(
      chatId: chatId, planId: plan.id, useCoins: useCoins);
  final messenger = ErrorMessages.messengerKey.currentState;
  if (result.success) {
    messenger?.showSnackBar(SnackBar(
        content: Text('Paid. You can now send one message to $peerName.')));
  } else if (result.message.isNotEmpty) {
    messenger?.showSnackBar(SnackBar(content: Text(result.message)));
  }
}

/// The recharge plans (days, messages and price from Firestore). Paying adds
/// the time and messages to this chat.
Future<void> showChatRechargeSheet(
  BuildContext context, {
  required String chatId,
  required ChatAccessState reason,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _RechargeSheet(chatId: chatId, reason: reason),
  );
}

class _RechargeSheet extends StatefulWidget {
  final String chatId;
  final ChatAccessState reason;
  const _RechargeSheet({required this.chatId, required this.reason});

  @override
  State<_RechargeSheet> createState() => _RechargeSheetState();
}

class _RechargeSheetState extends State<_RechargeSheet> {
  String? _payingPlan;

  Future<void> _pay(RechargePlan plan) async {
    if (_payingPlan != null) return;
    final patientUid = widget.chatId.split('_').first;
    final useCoins =
        await askUseMedCoins(context, patientUid: patientUid, price: plan.price);
    if (useCoins == null || !mounted) return;
    setState(() => _payingPlan = plan.id);
    final result = await PaymentService.payForChatRecharge(
        chatId: widget.chatId, planId: plan.id, useCoins: useCoins);
    if (!mounted) return;
    setState(() => _payingPlan = null);
    final messenger = ErrorMessages.messengerKey.currentState;
    if (result.success) {
      Navigator.pop(context);
      messenger?.showSnackBar(SnackBar(
          content: Text(
              'Chat recharged: ${plan.label} and ${plan.messages} more messages.')));
    } else if (result.message.isNotEmpty) {
      messenger?.showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Expanded(
                child: Text('Recharge your chat',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ]),
            Text(
              widget.reason == ChatAccessState.limitReached
                  ? 'You have used all your messages.'
                  : 'Your chat time is over.',
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 14),
            StreamBuilder<List<RechargePlan>>(
              stream: ChatAccessService.plans(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return const Text(
                      'Plans could not be loaded. Check your internet and try again.',
                      style: TextStyle(color: AppColors.danger));
                }
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final plans = snap.data!;
                if (plans.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                        'Chat recharge is not available yet. Please try again later.',
                        style: TextStyle(color: AppColors.muted)),
                  );
                }
                return Column(
                  children: [for (final p in plans) _planTile(p)],
                );
              },
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primaryTint,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield_outlined,
                      size: 18, color: AppColors.primary),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'If your doctor does not reply within 4 hours of your payment, the amount goes back to your wallet as MedCoins.',
                      style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: AppColors.textBody),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _planTile(RechargePlan p) {
    final busy = _payingPlan == p.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primaryBorder),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.label,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text('+${p.messages} messages',
                  style: const TextStyle(
                      color: AppColors.muted, fontSize: 12.5)),
            ],
          ),
        ),
        ElevatedButton(
          onPressed: _payingPlan == null ? () => _pay(p) : null,
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text('Pay ₹${p.price}'),
        ),
      ]),
    );
  }
}
