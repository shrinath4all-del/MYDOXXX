import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/stream_cache.dart';
import '../constants/app_colors.dart';
import 'app_alert_dialog.dart';

class TechnicianStatusDialog extends StatefulWidget {
  final String appointmentId;
  final String technicianName;
  final int basePrice;
  final int surcharge;
  final int totalPrice;

  const TechnicianStatusDialog({
    super.key,
    required this.appointmentId,
    required this.technicianName,
    required this.basePrice,
    required this.surcharge,
    required this.totalPrice,
  });

  @override
  State<TechnicianStatusDialog> createState() => _TechnicianStatusDialogState();
}

class _TechnicianStatusDialogState extends State<TechnicianStatusDialog>
    with SingleTickerProviderStateMixin {
  // Live data connections kept open across redraws
  final StreamCache _streams = StreamCache();

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
        _broadcastToAll(); // Auto broadcast after 1 minute!
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
    await FirestoreService.broadcastEmergencyToAllDoctors(
      appointmentId: widget.appointmentId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppDialogShell(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      backgroundColor: Colors.white,
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _streams.get('appointment', () => FirestoreService.getAppointmentStream(widget.appointmentId)),
        builder: (context, snapshot) {
          final data = snapshot.data?.data() ?? {};
          final status = data['status'] ?? 'Pending Home Visit';
          final activeTechName = data['doctorName'] ?? widget.technicianName;

          final isAccepted = status == 'Confirmed' || status == 'In Progress';
          final isDeclined = status == 'Declined';
          final isBroadcast = status == 'Broadcasted';

          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isAccepted
                        ? AppColors.successTint
                        : isDeclined
                            ? AppColors.dangerSoft
                            : AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isAccepted
                          ? AppColors.success
                          : isDeclined
                              ? AppColors.danger
                              : AppColors.primary,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isAccepted
                            ? Icons.check_circle_rounded
                            : isDeclined
                                ? Icons.warning_amber_rounded
                                : Icons.science_rounded,
                        color: isAccepted
                            ? AppColors.successDark
                            : isDeclined
                                ? AppColors.danger
                                : AppColors.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isAccepted
                            ? 'REQUEST ACCEPTED'
                            : isDeclined
                                ? 'TECHNICIAN UNAVAILABLE'
                                : isBroadcast
                                    ? 'BROADCASTING TO ALL TECHNICIANS'
                                    : '🔬 LAB TEST HOME VISIT REQUEST',
                        style: TextStyle(
                          color: isAccepted
                              ? AppColors.successDeep
                              : isDeclined
                                  ? AppColors.danger
                                  : AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Animated Radar/Pulse Graphic
                ScaleTransition(
                  scale: _pulseAnim,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: isAccepted
                          ? AppColors.successSoft
                          : isDeclined
                              ? AppColors.dangerSoft
                              : AppColors.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(
                        isAccepted
                            ? Icons.check_circle_rounded
                            : isDeclined
                                ? Icons.cancel_rounded
                                : Icons.radar_rounded,
                        color: isAccepted
                            ? AppColors.successDark
                            : isDeclined
                                ? AppColors.danger
                                : AppColors.primary,
                        size: 48,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Dynamic Status Text
                if (isAccepted) ...[
                  Text(
                    '🎉 $activeTechName Accepted!',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.darkNavy,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Technician $activeTechName accepted your request and is preparing for home sample collection.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                  ),
                ] else if (isDeclined) ...[
                  Text(
                    '${widget.technicianName} is Unavailable',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.danger,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Technician is unavailable. Tap below to broadcast to all nearby technicians in your area.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                  ),
                ] else if (isBroadcast) ...[
                  const Text(
                    'Broadcasting to Nearby Technicians!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Searching available lab technicians in your area. The first technician to accept will be assigned.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                  ),
                ] else ...[
                  Text(
                    'Requesting Technician ${widget.technicianName}...',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.darkNavy,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Auto-broadcasting to all nearby technicians in 00:${_secondsRemaining.toString().padLeft(2, '0')}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold),
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
                          Flexible(child: const Text('Base Test Fee:',
                              style: TextStyle(fontSize: 12, color: AppTheme.textMuted))),
                          Flexible(child: Text('₹${widget.basePrice}',
                              style: const TextStyle(fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
                        ],
                      ),
                      if (widget.surcharge > 0) ...[
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(child: const Text('Offered Extra Incentive:',
                                style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.bold))),
                            Flexible(child: Text('+₹${widget.surcharge}',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary), textAlign: TextAlign.right)),
                          ],
                        ),
                      ],
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(child: const Text('Total Fee:',
                              style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.darkNavy))),
                          Flexible(child: Text('₹${widget.totalPrice}',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary), textAlign: TextAlign.right)),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Dynamic Action Buttons
                if (isDeclined) ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand),
                    onPressed: _broadcastToAll,
                    icon: const Icon(Icons.cell_tower_rounded),
                    label: const Text('Broadcast Request to All Technicians'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel Request'),
                  ),
                ] else if (isAccepted) ...[
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Proceed'),
                  ),
                ] else ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand),
                    onPressed: _broadcastToAll,
                    icon: const Icon(Icons.cell_tower_rounded, size: 18),
                    label: const Text('Broadcast to All Technicians Now'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
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
