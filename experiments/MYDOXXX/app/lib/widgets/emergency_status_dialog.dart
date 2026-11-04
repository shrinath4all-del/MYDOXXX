import '../utils/maps_navigation.dart';
import '../utils/safe_cast.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/stream_cache.dart';
import '../constants/app_colors.dart';
import '../utils/display_names.dart';

class EmergencyStatusDialog extends StatefulWidget {
  final String appointmentId;
  final String doctorName;
  final int basePrice;
  final int surcharge;
  final int totalPrice;

  const EmergencyStatusDialog({
    super.key,
    required this.appointmentId,
    required this.doctorName,
    required this.basePrice,
    required this.surcharge,
    required this.totalPrice,
  });

  @override
  State<EmergencyStatusDialog> createState() => _EmergencyStatusDialogState();
}

class _EmergencyStatusDialogState extends State<EmergencyStatusDialog>
    with SingleTickerProviderStateMixin {
  // Live data connections kept open across redraws
  final StreamCache _streams = StreamCache();

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  int _secondsRemaining = 60;
  Timer? _countdownTimer;
  Timer? _tickTimer;
  Map<String, dynamic> _latest = {};
  bool _closing = false;

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
    // Per-second refresh of the radius stage / countdown, and auto-close when
    // nobody accepted in time (request is deleted, nothing is stored).
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted || _closing) return;
      if (FirestoreService.isUrgentRequestExpired(_latest)) {
        _closing = true;
        await FirestoreService.expireUrgentRequest(widget.appointmentId);
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(const SnackBar(
          content: Text(
              'No doctor accepted your urgent request in time. The request was closed. Please try again.'),
          backgroundColor: AppColors.danger,
        ));
        return;
      }
      setState(() {});
    });
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
    _tickTimer?.cancel();
    super.dispose();
  }

  void _broadcastToAll() async {
    await FirestoreService.broadcastEmergencyToAllDoctors(
      appointmentId: widget.appointmentId,
    );
  }

  /// "Searching within X km" stepper (4 -> 6 -> 8 km) with a closing countdown.
  Widget _buildRadiusProgress(Map<String, dynamic> data) {
    final radius = FirestoreService.searchRadiusKm(data).round();
    final left = FirestoreService.urgentRequestExpiry(data)
        .difference(DateTime.now())
        .inSeconds
        .clamp(0, 3600);
    final mm = (left ~/ 60).toString().padLeft(2, '0');
    final ss = (left % 60).toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primaryTeal.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            'Searching nearby doctors…',
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppTheme.primaryTeal),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final km in const [4, 6, 8]) ...[
                Expanded(
                  // search widening, shown without distances
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: radius >= km
                          ? AppTheme.primaryTeal
                          : AppColors.line,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                if (km != 8) const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Widens every 30 seconds. Request closes in $mm:$ss if nobody accepts.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      backgroundColor: Colors.white,
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _streams.get('appointment', () => FirestoreService.getAppointmentStream(widget.appointmentId)),
        builder: (context, snapshot) {
          final data = snapshot.data?.data() ?? {};
          _latest = data;
          final status = data['status'] ?? 'Pending Emergency';
          final activeDoctorName = data['doctorName'] ?? widget.doctorName;
          final hospitalName = data['hospital'] ?? 'Doctor Clinic';

          final isAccepted = status == 'Confirmed' ||
              status == 'In Progress' ||
              data['doctorAcceptedAt'] != null;

          final isDeclined = status == 'Declined';
          final isBroadcast = status == 'Broadcasted';

          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Header Badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isAccepted
                        ? AppColors.successTint
                        : isDeclined
                            ? AppColors.dangerSoft
                            : AppColors.warningTint,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isAccepted
                          ? AppColors.success
                          : isDeclined
                              ? AppColors.danger
                              : AppTheme.primaryTeal,
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
                                : Icons.cell_tower_rounded,
                        color: isAccepted
                            ? AppColors.successDark
                            : isDeclined
                                ? AppColors.danger
                                : AppTheme.primaryTeal,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isAccepted
                            ? 'URGENT REQUEST ACCEPTED ✔'
                            : isDeclined
                                ? 'DOCTOR UNAVAILABLE'
                                : isBroadcast
                                    ? 'BROADCASTING TO ALL DOCTORS'
                                    : '🚨 URGENT EMERGENCY DISPATCH',
                        style: TextStyle(
                          color: isAccepted
                              ? AppColors.successDeep
                              : isDeclined
                                  ? AppColors.danger
                                  : AppTheme.primaryTeal,
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
                              : AppTheme.primaryTeal.withValues(alpha: 0.15),
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
                                : AppTheme.primaryTeal,
                        size: 48,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Dynamic Status Text
                if (isAccepted) ...[
                  Text(
                    '🎉 ${DisplayNames.doctor(activeDoctorName)} Accepted!',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${DisplayNames.doctor(activeDoctorName)} accepted your urgent request. Please travel to the doctor\'s clinic/hospital at $hospitalName for immediate consultation.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      minimumSize: const Size(double.infinity, 46),
                    ),
                    onPressed: () {
                      final docLat = toNum(data['doctorLat'])?.toDouble();
                      final docLng = toNum(data['doctorLng'])?.toDouble();
                      MapsNavigation.toHospital(hospitalName.toString(),
                          lat: docLat, lng: docLng);
                    },
                    icon: const Icon(Icons.directions_outlined, size: 20),
                    label: const Text('Navigate to Doctor\'s Clinic (Maps)'),
                  ),
                ] else if (isDeclined) ...[
                  Text(
                    '${widget.doctorName} is Unavailable',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.danger,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Preferred doctor is unavailable or on break. Broadcasting request to all other doctors in your area...',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                  ),
                ] else if (isBroadcast) ...[
                  const Text(
                    'Broadcasting to All Nearby Doctors!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryTeal,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Searching all available verified doctors in your area. The first available doctor to accept will be assigned.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                  ),
                ] else ...[
                  Text(
                    'Requesting ${widget.doctorName}...',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Auto-broadcasting to all nearby doctors in 00:${_secondsRemaining.toString().padLeft(2, '0')}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.primaryTeal,
                        fontWeight: FontWeight.bold),
                  ),
                ],

                if (!isAccepted && data['autoExpire'] == true) ...[
                  const SizedBox(height: 16),
                  _buildRadiusProgress(data),
                ],

                const SizedBox(height: 20),

                // Price Breakdown Box (Base + Surcharge)
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
                          Flexible(child: const Text('Base Consultation Fee:',
                              style: TextStyle(fontSize: 12, color: AppTheme.textMuted))),
                          Flexible(child: Text('₹${widget.basePrice}',
                              style: const TextStyle(fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(child: const Text('Emergency Surcharge (+20%):',
                              style: TextStyle(fontSize: 12, color: AppColors.danger, fontWeight: FontWeight.bold))),
                          Flexible(child: Text('+₹${widget.surcharge}',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.danger), textAlign: TextAlign.right)),
                        ],
                      ),
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(child: const Text('Total Fee:',
                              style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textDark))),
                          Flexible(child: Text('₹${widget.totalPrice}',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryTeal), textAlign: TextAlign.right)),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Dynamic Action Buttons
                if (isDeclined) ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                    onPressed: _broadcastToAll,
                    icon: const Icon(Icons.cell_tower_rounded),
                    label: const Text('Broadcast Request to All Doctors'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel Request'),
                  ),
                ] else if (isAccepted) ...[
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ] else ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand),
                    onPressed: _broadcastToAll,
                    icon: const Icon(Icons.cell_tower_rounded, size: 18),
                    label: const Text('Broadcast to All Doctors Now'),
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
