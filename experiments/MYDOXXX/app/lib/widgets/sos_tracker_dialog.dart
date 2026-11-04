import '../services/app_database.dart';
import '../utils/maps_navigation.dart';
import '../utils/safe_cast.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/firestore_service.dart';
import '../services/sos_service.dart';
import '../theme/app_theme.dart';
import '../utils/stream_cache.dart';
import '../constants/app_colors.dart';
import '../utils/display_names.dart';
import 'ambulance_chat_button.dart';

/// Patient-side live tracker for an Emergency Help (SOS) request:
/// hospital -> doctor -> ambulance, with the current search radius and a
/// countdown. If the whole process isn't complete within 5 minutes the
/// request is closed and erased.
class SosTrackerDialog extends StatefulWidget {
  final String appointmentId;
  const SosTrackerDialog({super.key, required this.appointmentId});

  @override
  State<SosTrackerDialog> createState() => _SosTrackerDialogState();
}

class _SosTrackerDialogState extends State<SosTrackerDialog> {
  // Live data connections kept open across redraws
  final StreamCache _streams = StreamCache();

  Timer? _tick;
  Map<String, dynamic> _latest = {};
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted || _closing) return;
      final closedElsewhere = _latest['status'] == 'Expired';
      if (closedElsewhere ||
          FirestoreService.isUrgentRequestExpired(_latest)) {
        _closing = true;
        final kept = closedElsewhere ||
            FirestoreService.isPartlyAccepted(_latest);
        if (!closedElsewhere) {
          await FirestoreService.expireUrgentRequest(widget.appointmentId);
        }
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(SnackBar(
          content: Text(kept
              ? 'We could not complete your emergency request in time, so it was closed. The details stay in your bookings. Please call 108 or try again.'
              : 'We could not complete your emergency request in time, so it was closed and erased. Please call 108 or try again.'),
          backgroundColor: AppColors.danger,
          duration: const Duration(seconds: 8),
        ));
        return;
      }
      setState(() {});
    });
  }

  /// Close Tracker: while the request is still being arranged (hospital,
  /// doctor and ambulance not all assigned) this cancels it and deletes it
  /// from the appointments. Once everything is assigned it only closes.
  Future<void> _closeTracker(bool complete) async {
    if (complete) {
      Navigator.pop(context);
      return;
    }
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Cancel emergency request?'),
        content: const Text(
          'Your emergency request is still being arranged. Closing the tracker cancels it and deletes it.\n\nIf this is a real emergency, keep tracking or call 108.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep tracking'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, cancel request'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;

    _closing = true; // stop the timer's own auto-close handling
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      final ref = AppDatabase.instance
          .collection('appointments')
          .doc(widget.appointmentId);
      // marked first so the server doesn't tell the patient "request closed"
      await ref.update({'cancelledByPatient': true});
      await ref.delete();
      nav.pop();
      messenger.showSnackBar(const SnackBar(
        content: Text('Emergency request cancelled.'),
        backgroundColor: AppColors.warning,
      ));
    } catch (_) {
      _closing = false;
      messenger.showSnackBar(const SnackBar(
        content: Text('Could not cancel the request. Please try again.'),
        backgroundColor: AppColors.danger,
      ));
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _clock(int secs) {
    final s = secs.clamp(0, 3600);
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _streams.get('appointment', () => AppDatabase.instance
            .collection('appointments')
            .doc(widget.appointmentId)
            .snapshots()),
        builder: (context, snapshot) {
          final data = snapshot.data?.data() ?? {};
          _latest = data;
          final status =
              (data['status'] ?? 'Pending Hospital Acceptance').toString();
          final needsAmbulance = data['requiresAmbulance'] != false;

          // Each step is done only when the request has really moved past it
          // (never because of a decline or a generic "Broadcasted" status).
          const afterDoctor = {
            'Pending Ambulance Dispatch',
            'Ambulance Dispatched',
            'Patient Picked Up',
            'Confirmed',
            'In Progress',
            'Completed',
          };
          const afterAmbulance = {
            'Ambulance Dispatched',
            'Patient Picked Up',
            'In Progress',
            'Completed',
          };
          final bool doctorDone = afterDoctor.contains(status) ||
              data['doctorAcceptedAt'] != null;
          final bool hospitalDone = doctorDone ||
              status == 'Pending Doctor Assignment' ||
              data['assignedHospitalUid'] != null;
          final bool ambulanceDone = doctorDone &&
              (needsAmbulance ? afterAmbulance.contains(status) : true);

          final String hospitalSub = hospitalDone
              ? 'Hospital Accepted: ${data['assignedHospitalName'] ?? 'Verified Hospital'}'
              : 'Asking verified hospitals near you…';

          String doctorSub;
          if (doctorDone) {
            doctorSub =
                'Doctor Assigned: ${DisplayNames.doctor(data['assignedDoctorName'] ?? data['doctorName'] ?? 'Doctor')}';
          } else if (hospitalDone) {
            final phase = SosService.doctorPhase(data);
            doctorSub = phase.preferredOnly
                ? "Asking the hospital's preferred doctors first…"
                : 'Asking doctors near the hospital…';
          } else {
            doctorSub = 'Awaiting hospital acceptance…';
          }

          String ambSub;
          if (!needsAmbulance) {
            ambSub = 'Not needed – you are travelling to the hospital yourself';
          } else if (ambulanceDone) {
            ambSub =
                'Ambulance Dispatched: ${data['assignedAmbulanceDriver']} (${data['assignedVehicleNumber']})';
          } else if (doctorDone) {
            ambSub =
                'Asking ambulances near you…';
          } else {
            ambSub = 'Awaiting doctor assignment…';
          }

          final complete = ambulanceDone;
          final left =
              SosService.expiry(data).difference(DateTime.now()).inSeconds;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: AppColors.dangerSoft, shape: BoxShape.circle),
                  child: const Icon(Icons.warning_amber_rounded,
                      color: AppColors.danger, size: 44),
                ),
                const SizedBox(height: 16),
                const Text('🚨 SOS EMERGENCY TRACKER',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.danger)),
                const SizedBox(height: 6),
                const Text(
                    'Tracking real-time response from nearby hospitals, doctors & ambulances',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                const SizedBox(height: 16),
                if (!complete && snapshot.hasData && data.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.warningTint,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.warningBright),
                    ),
                    child: Text(
                      'Request closes in ${_clock(left)} if not fully arranged',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.darkNavy),
                    ),
                  ),
                const SizedBox(height: 14),
                if (!complete && hospitalDone) ..._otpCards(data, needsAmbulance, status),
                _step('Step 1: Hospital Acceptance', hospitalSub, hospitalDone,
                    Icons.local_hospital_rounded),
                const SizedBox(height: 10),
                _step('Step 2: Emergency Doctor Assigned', doctorSub,
                    doctorDone, Icons.medical_services_rounded),
                const SizedBox(height: 10),
                _step('Step 3: Ambulance Dispatched', ambSub, ambulanceDone,
                    Icons.airport_shuttle_rounded),
                if (needsAmbulance)
                  AmbulanceChatButton(
                      sos: data,
                      sosId: widget.appointmentId,
                      forAmbulance: false),
                if (hospitalDone && (data['assignedHospitalName'] ?? '').toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: OutlinedButton.icon(
                      onPressed: () => MapsNavigation.toHospital(
                        data['assignedHospitalName'].toString(),
                        lat: toNum(data['assignedHospitalLat'])?.toDouble(),
                        lng: toNum(data['assignedHospitalLng'])?.toDouble(),
                      ),
                      icon: const Icon(Icons.directions_outlined, size: 18),
                      label: Text('Navigate to ${data['assignedHospitalName']}'),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 44)),
                    ),
                  ),
                for (final line in SosService.timingLines(data))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(line,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.textMuted)),
                  ),
                const SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor:
                          complete ? AppTheme.primaryTeal : AppColors.danger),
                  onPressed: () => _closeTracker(complete),
                  child: Text(complete ? 'Close Tracker' : 'Close & Cancel Request'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// The patient's single OTP: the same code is given to the ambulance
  /// driver at pickup, to the hospital on arrival and to the doctor, whose
  /// entry closes the emergency.
  List<Widget> _otpCards(
      Map<String, dynamic> data, bool needsAmbulance, String status) {
    final arrived = data['hospitalReachedAt'] != null || status == 'In Progress';
    final otp = (data['otp'] ?? data['hospitalOtp'] ?? '').toString();
    if (otp.isEmpty) return [];
    final pickedUp = data['ambulancePickedUpAt'] != null ||
        status == 'Patient Picked Up';
    final hint = arrived
        ? 'Tell this code to your doctor when you meet. This closes the emergency.'
        : !needsAmbulance
        ? 'Tell this code to the hospital on arrival'
        : (pickedUp
            ? 'Tell this code to the hospital on arrival'
            : 'Tell this code to the ambulance driver at pickup, and again to the hospital on arrival');
    final color = AppColors.danger;
    return [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Column(
          children: [
            Text('YOUR EMERGENCY OTP',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(otp,
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 6,
                    color: color)),
            const SizedBox(height: 2),
            Text(hint,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
          ],
        ),
      ),
      const SizedBox(height: 14),
    ];
  }

  Widget _step(String title, String subtitle, bool done, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: done ? AppColors.successTint : AppTheme.bgLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: done ? AppColors.successLight : AppColors.lineStrong),
      ),
      child: Row(
        children: [
          Icon(done ? Icons.check_circle_rounded : icon,
              color: done ? AppColors.successDark : AppColors.muted, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color:
                            done ? AppColors.successDeep : AppTheme.darkNavy)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 11,
                        color: done
                            ? AppColors.successDeep
                            : AppTheme.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
