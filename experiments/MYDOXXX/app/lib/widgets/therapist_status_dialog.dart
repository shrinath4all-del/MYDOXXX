import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/firestore_service.dart';
import '../services/physio_agency_service.dart';
import '../theme/app_theme.dart';
import '../utils/stream_cache.dart';
import '../constants/app_colors.dart';
import 'app_alert_dialog.dart';

/// Patient-side live tracker for a therapist home-visit request
/// (same flow as the technician tracker, with therapist wording).
class TherapistStatusDialog extends StatefulWidget {
  final String appointmentId;
  final String therapistName;
  final String therapyName;
  final int basePrice;
  final int urgentSurcharge;
  final int totalPrice;
  final bool isUrgent;

  const TherapistStatusDialog({
    super.key,
    required this.appointmentId,
    required this.therapistName,
    required this.therapyName,
    required this.basePrice,
    required this.urgentSurcharge,
    required this.totalPrice,
    required this.isUrgent,
  });

  @override
  State<TherapistStatusDialog> createState() => _TherapistStatusDialogState();
}

class _TherapistStatusDialogState extends State<TherapistStatusDialog>
    with SingleTickerProviderStateMixin {
  // Live data connections kept open across redraws
  final StreamCache _streams = StreamCache();

  static const Color _blue = AppTheme.primaryTeal;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  int _secondsRemaining = 60;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _startOneMinuteTimer();
  }

  void _startOneMinuteTimer() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsRemaining > 1) {
        setState(() => _secondsRemaining--);
      } else {
        _countdownTimer?.cancel();
        _broadcastToAll(); // Auto broadcast after 1 minute if still pending
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _broadcastToAll() async {
    _countdownTimer?.cancel();
    await FirestoreService.broadcastTherapistRequest(widget.appointmentId);
  }

  @override
  Widget build(BuildContext context) {
    return AppDialogShell(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _streams.get('appointment', () => FirestoreService.getAppointmentStream(widget.appointmentId)),
        builder: (context, snapshot) {
          final data = snapshot.data?.data() ?? {};
          final status = data['status'] ?? 'Pending Home Visit';
          final activeName = data['doctorName'] ?? widget.therapistName;

          final isAccepted = status == 'Confirmed' || status == 'In Progress';
          final isDeclined = status == 'Declined' || status == 'Cancelled';
          final isBroadcast = status == 'Broadcasted';
          if (isAccepted || isBroadcast || isDeclined) {
            _countdownTimer?.cancel();
          }

          final Color accent = isAccepted
              ? AppColors.successDark
              : isDeclined
                  ? AppColors.danger
                  : _blue;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header Badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isAccepted
                        ? AppColors.successTint
                        : isDeclined
                            ? AppColors.dangerSoft
                            : AppTheme.pastelBlue,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: accent),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isAccepted
                            ? Icons.check_circle_rounded
                            : isDeclined
                                ? Icons.warning_amber_rounded
                                : Icons.self_improvement_rounded,
                        color: accent,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          isAccepted
                              ? 'REQUEST ACCEPTED'
                              : isDeclined
                                  ? 'THERAPIST UNAVAILABLE'
                                  : isBroadcast
                                      ? 'FINDING A NEARBY THERAPIST'
                                      : widget.isUrgent
                                          ? 'URGENT THERAPY REQUEST'
                                          : 'THERAPY HOME VISIT REQUEST',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Animated Pulse Graphic
                ScaleTransition(
                  scale: _pulseAnim,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(
                        isAccepted
                            ? Icons.check_circle_rounded
                            : isDeclined
                                ? Icons.cancel_rounded
                                : Icons.radar_rounded,
                        color: accent,
                        size: 48,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Dynamic Status Text
                if (isAccepted) ...[
                  Text(
                    '🎉 $activeName Accepted!',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.darkNavy,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Therapist $activeName accepted your ${widget.therapyName} session and will visit you at home. Share your OTP from My Bookings when they arrive.',
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                  ),
                ] else if (isDeclined) ...[
                  Text(
                    '${widget.therapistName} is Unavailable',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.danger,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Tap below to send your request to all nearby therapists.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                  ),
                ] else if (isBroadcast) ...[
                  const Text(
                    'Finding a Nearby Therapist',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _blue,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    PhysioAgencyService.isAgencyWindowOpen(data)
                        ? 'Sent to ${data['agencyName'] ?? 'a partner agency'} physios first. If none accepts by ${PhysioAgencyService.timeLabel(data['agencyOfferExpiresAt'])}, all physios in your area get it.'
                        : 'Your request has been sent to verified therapists in your area. The first therapist to accept will be assigned.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                  ),
                ] else ...[
                  Text(
                    'Requesting ${widget.therapistName}...',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.darkNavy,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'If not accepted, your request goes to all nearby therapists in 00:${_secondsRemaining.toString().padLeft(2, '0')}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 13, color: _blue, fontWeight: FontWeight.bold),
                  ),
                ],

                const SizedBox(height: 20),

                // Price Breakdown Box
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.bgLight,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text('${widget.therapyName} Fee:',
                                style: const TextStyle(
                                    fontSize: 12, color: AppTheme.textMuted)),
                          ),
                          Text('₹${widget.basePrice}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      if (widget.urgentSurcharge > 0) ...[
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(child: const Text('Urgent Charge:',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.orange,
                                    fontWeight: FontWeight.bold))),
                            Flexible(child: Text('+₹${widget.urgentSurcharge}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.orange), textAlign: TextAlign.right)),
                          ],
                        ),
                      ],
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(child: const Text('Total Fee:',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.darkNavy))),
                          Flexible(child: Text('₹${widget.totalPrice}',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: _blue), textAlign: TextAlign.right)),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Dynamic Action Buttons
                if (isDeclined) ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _blue,
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    onPressed: _broadcastToAll,
                    icon: const Icon(Icons.cell_tower_rounded),
                    label: const Text('Send to All Nearby Therapists'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48)),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ] else if (isAccepted) ...[
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _blue,
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ] else ...[
                  if (!isBroadcast) ...[
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _blue,
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      onPressed: _broadcastToAll,
                      icon: const Icon(Icons.cell_tower_rounded, size: 18),
                      label: const Text('Send to All Nearby Therapists Now'),
                    ),
                    const SizedBox(height: 10),
                  ],
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48)),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close Tracker'),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
