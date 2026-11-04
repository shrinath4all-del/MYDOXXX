import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_strings.dart';
import '../utils/appointment_rules.dart';
import 'unread_badge.dart';

/// "Chat" button for a booking: greyed out until the consultation ends
/// (tapping says why), then enabled. The 24 free hours, the 10 free messages and
/// the paid recharge are handled inside the chat itself, so it stays
/// enabled after the 24 hours (the patient can recharge there).
class ChatButton extends StatelessWidget {
  final Map<String, dynamic> booking;
  final VoidCallback onChat;
  final bool compact;

  /// Whose unread messages to count on the button (the signed-in account).
  final String? viewerUid;

  const ChatButton({
    super.key,
    required this.booking,
    required this.onChat,
    this.compact = false,
    this.viewerUid,
  });

  @override
  Widget build(BuildContext context) {
    final state = AppointmentRules.chatState(booking);
    final open = state != ChatState.notStarted;
    final button = OutlinedButton.icon(
      // a disabled button can't be tapped, so the "why" comes from here
      onPressed: open
          ? onChat
          : () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text(AppStrings.chatLocked)),
              ),
      style: OutlinedButton.styleFrom(
        minimumSize: Size(compact ? 0 : double.infinity, 44),
        foregroundColor: open ? AppColors.primary : AppColors.lineStrong,
        iconColor: open ? AppColors.primary : AppColors.lineStrong,
        side: BorderSide(
            color: open ? AppColors.primary : AppColors.line, width: 1.5),
      ),
      icon: Icon(
          open ? Icons.chat_bubble_outline_rounded : Icons.lock_outline_rounded,
          size: 18),
      label: const Text(AppStrings.chat),
    );
    final patient = (booking['patientUid'] ?? '').toString();
    final provider = (booking['doctorUid'] ?? '').toString();
    final viewer = viewerUid;
    return Tooltip(
      message: open ? AppStrings.chat : AppStrings.chatLocked,
      child: viewer == null || patient.isEmpty || provider.isEmpty
          ? button
          : UnreadBadge(
              chatId: '${patient}_$provider', uid: viewer, child: button),
    );
  }
}
