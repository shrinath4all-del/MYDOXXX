import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../services/chat_access_service.dart';
import '../services/presence_service.dart';

/// A red count of unread chat messages for [uid] on top of [child] (nothing
/// when all are read).
class UnreadBadge extends StatelessWidget {
  final String chatId;
  final String uid;
  final Widget child;

  const UnreadBadge({
    super.key,
    required this.chatId,
    required this.uid,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: ChatAccessService.unreadCount(chatId, uid),
      builder: (context, snap) => unreadBadge(snap.data ?? 0, child),
    );
  }
}

/// [child] with a red [count] in its corner (none when 0).
Widget unreadBadge(int count, Widget child) => Badge(
      isLabelVisible: count > 0,
      backgroundColor: AppColors.unread,
      textColor: Colors.white,
      label: Text(count > 99 ? '99+' : '$count'),
      child: child,
    );

/// A green dot and "Online" while [uid] has the app open; nothing otherwise.
class OnlineDot extends StatelessWidget {
  final String uid;
  final bool showLabel;

  const OnlineDot({super.key, required this.uid, this.showLabel = true});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: PresenceService.user(uid),
      builder: (context, snap) {
        if (!PresenceService.isOnline(snap.data)) {
          return const SizedBox.shrink();
        }
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
                color: AppColors.online, shape: BoxShape.circle),
          ),
          if (showLabel) ...[
            const SizedBox(width: 4),
            const Text('Online',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.online)),
          ],
        ]);
      },
    );
  }
}
