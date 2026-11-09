import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../screens/chat/video_call_screen.dart';
import '../services/call_service.dart';
import '../theme/app_theme.dart';
import '../constants/app_colors.dart';
import '../utils/ist_clock.dart';

/// WhatsApp-style incoming video-call ringing for a signed-in home screen.
/// Call [start] in initState and [dispose] in dispose: while the app is open a
/// full-screen Accept / Decline screen appears when someone calls.
class IncomingCallWatcher {
  final BuildContext Function() contextProvider;
  final String uid;
  final String Function() userName;

  IncomingCallWatcher({
    required this.contextProvider,
    required this.uid,
    required this.userName,
  });

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  String? _showingCallId;

  void start() {
    _sub = CallService.incomingCalls(uid).listen((snap) {
      for (final doc in snap.docs) {
        final data = doc.data();
        if (CallService.isStale(data)) continue; // caller already gave up
        final endsAt = IstClock.tryParse((data['endsAt'] ?? '').toString());
        if (endsAt != null && IstClock.now().isAfter(endsAt)) continue; // slot over
        if (_showingCallId != null) return;
        final ctx = contextProvider();
        if (!ctx.mounted) return;
        _showingCallId = doc.id;
        Navigator.of(ctx)
            .push(MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => IncomingCallScreen(
                callId: doc.id,
                call: data,
                currentUid: uid,
                currentName: userName(),
              ),
            ))
            .whenComplete(() => _showingCallId = null);
        return;
      }
    });
  }

  void dispose() => _sub?.cancel();
}

class IncomingCallScreen extends StatelessWidget {
  final String callId;
  final Map<String, dynamic> call;
  final String currentUid;
  final String currentName;

  const IncomingCallScreen({
    super.key,
    required this.callId,
    required this.call,
    required this.currentUid,
    required this.currentName,
  });

  @override
  Widget build(BuildContext context) {
    final callerName = (call['callerName'] ?? 'Someone').toString();
    final audioOnly = call['audioOnly'] == true;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.ink,
        body: SafeArea(
          // Closes itself when the caller hangs up / the call is answered elsewhere
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: CallService.callRef(callId).snapshots(),
            builder: (context, snap) {
              final status = snap.data?.data()?['status'];
              if (snap.hasData && status != 'ringing') {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (context.mounted && Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                });
              }
              return Column(
                children: [
                  const Spacer(flex: 2),
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: AppTheme.primaryTeal.withValues(alpha: 0.3),
                    child: Text(
                      callerName.isNotEmpty ? callerName[0].toUpperCase() : '?',
                      style: const TextStyle(
                          fontSize: 52,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(callerName,
                      style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(height: 8),
                  Text(
                      audioOnly
                          ? 'Incoming audio call…'
                          : 'Incoming video call…',
                      style: const TextStyle(
                          fontSize: 15, color: Colors.white70)),
                  const Spacer(flex: 3),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _CallButton(
                          color: AppColors.danger,
                          icon: Icons.call_end_rounded,
                          label: 'Decline',
                          onTap: () async {
                            await CallService.setStatus(callId, 'declined');
                            if (context.mounted) Navigator.of(context).pop();
                          },
                        ),
                        _CallButton(
                          color: AppColors.success,
                          icon: audioOnly
                              ? Icons.call_rounded
                              : Icons.videocam_rounded,
                          label: 'Accept',
                          onTap: () {
                            final nav = Navigator.of(context);
                            nav.pushReplacement(MaterialPageRoute(
                              builder: (_) => VideoCallScreen(
                                callId: callId,
                                isCaller: false,
                                appointmentId:
                                    (call['appointmentId'] ?? '').toString(),
                                currentUid: currentUid,
                                callerName: currentName,
                                peerUid: (call['callerUid'] ?? '').toString(),
                                peerName: callerName,
                                peerRole: '',
                                audioOnly: audioOnly,
                              ),
                            ));
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 56),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _CallButton({
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }
}
