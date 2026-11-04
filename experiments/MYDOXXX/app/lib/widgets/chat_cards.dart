import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../utils/appointment_rules.dart';

/// "28 Oct, 4:05 PM" for a message's createdAt (empty if unknown).
String chatSentAt(Map<String, dynamic> msg) {
  final t = DateTime.tryParse((msg['createdAt'] ?? '').toString());
  if (t == null) return '';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${t.day} ${months[t.month - 1]}, ${AppointmentRules.hm(t)}';
}

/// The patient's audio or video call request, shown in the chat for both.
///
///   requested  doctor: Accept (rings the patient) / Decline
///              patient: Cancel request
///   accepted, missed
///              both: Start call (the patient can call the doctor too)
///   started    both: End call
///   completed, declined, cancelled: nothing more to do
///
/// Calls last up to 15 minutes.
class CallRequestCard extends StatelessWidget {
  final Map<String, dynamic> message;

  /// The provider's view (the request came from the patient).
  final bool providerView;

  /// The chat time is on, so the call can be started now.
  final bool canStart;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onCancel;
  final VoidCallback? onStart;
  final VoidCallback? onEnd;

  const CallRequestCard({
    super.key,
    required this.message,
    required this.providerView,
    this.canStart = false,
    this.onAccept,
    this.onDecline,
    this.onCancel,
    this.onStart,
    this.onEnd,
  });

  bool get video => message['callType'] == 'video';

  static String statusOf(Map<String, dynamic> m) =>
      (m['callStatus'] ?? 'requested').toString();

  static String statusLabel(Map<String, dynamic> m) {
    final secs = m['callSeconds'];
    switch (statusOf(m)) {
      case 'accepted':
        return 'Accepted';
      case 'started':
        return 'On call';
      case 'completed':
        if (secs is num) {
          final mm = (secs ~/ 60).toString().padLeft(2, '0');
          final ss = (secs.toInt() % 60).toString().padLeft(2, '0');
          return 'Call completed · $mm:$ss';
        }
        return 'Call completed';
      case 'missed':
        return 'Missed call';
      case 'declined':
        return 'Call declined';
      case 'cancelled':
        return 'Request cancelled';
      default:
        return 'Waiting for the doctor';
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = statusOf(message);
    final bad = status == 'missed' ||
        status == 'declined' ||
        status == 'cancelled';
    final done = status == 'completed';
    final kind = video ? 'Video' : 'Audio';
    final callIcon = video ? Icons.videocam_rounded : Icons.call_rounded;

    final buttons = <Widget>[];
    if (status == 'requested') {
      if (providerView) {
        buttons.addAll([
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.danger)),
              onPressed: onDecline,
              child: const Text('Decline'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: canStart ? onAccept : null,
              icon: Icon(callIcon, size: 18),
              label: const Text('Accept'),
            ),
          ),
        ]);
      } else {
        buttons.add(Expanded(
          child: OutlinedButton(
            onPressed: onCancel,
            child: const Text('Cancel request'),
          ),
        ));
      }
    } else if (status == 'accepted' || status == 'missed') {
      buttons.add(Expanded(
        child: ElevatedButton.icon(
          onPressed: canStart ? onStart : null,
          icon: Icon(callIcon, size: 18),
          label: Text(canStart
              ? 'Start ${kind.toLowerCase()} call'
              : 'Chat time is over'),
        ),
      ));
    } else if (status == 'started') {
      buttons.add(Expanded(
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: onEnd,
          icon: const Icon(Icons.call_end_rounded, size: 18),
          label: const Text('End call'),
        ),
      ));
    }

    return Align(
      alignment: providerView ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        decoration: BoxDecoration(
          color: AppColors.primaryTint,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.primaryBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primarySoft,
                child: Icon(callIcon, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        providerView
                            ? '${(message['senderName'] ?? 'Patient')} asks for ${video ? 'a video' : 'an audio'} call'
                            : '$kind call request',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink)),
                    Text(
                      [statusLabel(message), chatSentAt(message)]
                          .where((e) => e.isNotEmpty)
                          .join(' · '),
                      style: TextStyle(
                          fontSize: 12,
                          color: bad
                              ? AppColors.danger
                              : done
                                  ? AppColors.primary
                                  : AppColors.muted),
                    ),
                  ],
                ),
              ),
            ]),
            if (status == 'requested' || status == 'accepted')
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Calls last up to 15 minutes.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ),
            if (buttons.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(children: buttons),
              ),
          ],
        ),
      ),
    );
  }
}

/// A prescription the doctor sent: clearly labelled, with when it was sent.
/// Tapping opens it.
class PrescriptionCard extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isMe;
  final VoidCallback onOpen;

  const PrescriptionCard({
    super.key,
    required this.message,
    required this.isMe,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final note = (message['text'] ?? '').toString().trim();
    final from = (message['senderName'] ?? '').toString();
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.primary, width: 1.4),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.medication_rounded,
                        color: AppColors.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('PRESCRIPTION',
                            style: TextStyle(
                                fontSize: 11,
                                letterSpacing: 0.8,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary)),
                        Text(
                          (message['fileName'] ?? 'Prescription').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.open_in_new_rounded,
                      size: 18, color: AppColors.primary),
                ]),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(note, style: const TextStyle(height: 1.3)),
                ],
                const SizedBox(height: 6),
                Text(
                  [
                    if (from.isNotEmpty) 'From $from',
                    if (chatSentAt(message).isNotEmpty)
                      'Sent ${chatSentAt(message)}',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What a chat file is, shown before it is opened: icon, kind and name.
class ChatFileTile extends StatelessWidget {
  final IconData icon;
  final String kind;
  final String fileName;
  final String action;
  final bool isMe;
  final VoidCallback onTap;

  const ChatFileTile({
    super.key,
    required this.icon,
    required this.kind,
    required this.fileName,
    required this.action,
    required this.isMe,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = isMe ? Colors.white : AppColors.ink;
    final sub = isMe ? Colors.white70 : AppColors.muted;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe ? Colors.white.withValues(alpha: 0.2) : AppColors.page,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Icon(icon, color: isMe ? Colors.white : AppColors.primary, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kind.toUpperCase(),
                    style: TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w800,
                        color: sub)),
                Text(fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13, color: fg)),
                Text(action, style: TextStyle(fontSize: 11, color: sub)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
