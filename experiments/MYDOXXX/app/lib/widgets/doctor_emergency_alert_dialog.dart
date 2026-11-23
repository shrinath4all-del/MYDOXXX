import '../services/app_database.dart';
import 'scrollable_action_dialog.dart';
import '../services/lab_device.dart';
import '../utils/safe_cast.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/firestore_service.dart';
import '../services/sos_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_messages.dart';
import '../constants/app_colors.dart';
import '../utils/ist_clock.dart';
import 'app_alert_dialog.dart';

class DoctorEmergencyAlertDialog extends StatefulWidget {
  final Map<String, dynamic> appointment;
  final String doctorUid;
  final String doctorName;

  const DoctorEmergencyAlertDialog({
    super.key,
    required this.appointment,
    this.doctorUid = '',
    this.doctorName = '',
  });

  @override
  State<DoctorEmergencyAlertDialog> createState() =>
      _DoctorEmergencyAlertDialogState();
}

class _DoctorEmergencyAlertDialogState extends State<DoctorEmergencyAlertDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  bool _isResponding = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _openMap(String locationName, double? lat, double? lng) async {
    final query = (lat != null && lng != null)
        ? '$lat,$lng'
        : Uri.encodeComponent(
            locationName.isNotEmpty ? locationName : 'Assigned Hospital');
    final url =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    try {
      if (await labCanLaunchUrl(url)) {
        await labLaunchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  Future<void> _handleResponse(bool accept) async {
    setState(() => _isResponding = true);
    final appointmentId = widget.appointment['appointmentId'] ?? '';
    final patientName = widget.appointment['patientName'] ?? 'Patient';
    final patientPhone = widget.appointment['patientPhone'] ?? 'N/A';
    ({String name, double? lat, double? lng})? acceptedHospital;

    try {
      if (accept) {
        final bool isSosPipeline =
            widget.appointment['consultationType'] == 'SOS Emergency Pipeline';

        // First doctor to accept gets the case; later accepts are refused.
        final docRef =
            AppDatabase.instance.collection('appointments').doc(appointmentId);
        final hospital =
            await FirestoreService.getDoctorHospitalLocation(widget.doctorUid);
        final bool busy =
            await FirestoreService.hasActiveEmergency(widget.doctorUid);
        bool expired = false;
        // distance hospital -> doctor's live location sets the arrival limit
        double? liveDocKm;
        try {
          final dd = (await AppDatabase.instance
                  .collection('doctors')
                  .doc(widget.doctorUid)
                  .get())
              .data();
          final la = (dd?['latitude'] as num?)?.toDouble();
          final lo = (dd?['longitude'] as num?)?.toDouble();
          final hl =
              toNum(widget.appointment['assignedHospitalLat'])?.toDouble();
          final hn =
              toNum(widget.appointment['assignedHospitalLng'])?.toDouble();
          if (la != null && lo != null && hl != null && hn != null) {
            liveDocKm = SosService.distanceKm(hl, hn, la, lo);
          }
        } catch (_) {}
        double sosDocKm(Map<String, dynamic> d) =>
            liveDocKm ??
            ((d['sosDoctorCandidatesKm'] as Map?)?[widget.doctorUid] as num?)
                ?.toDouble() ??
            4;

        // SOS pipeline: line up the ambulances near the assigned hospital
        final bool needsAmbulance =
            widget.appointment['requiresAmbulance'] != false;
        Map<String, double> ambulanceCands = {};
        if (isSosPipeline && needsAmbulance) {
          // ambulances are measured from the patient's live location
          final pLat = toNum(widget.appointment['patientLat'])?.toDouble();
          final pLng = toNum(widget.appointment['patientLng'])?.toDouble();
          if (pLat != null && pLng != null) {
            ambulanceCands = await SosService.ambulanceCandidates(
                patientLat: pLat, patientLng: pLng);
          }
        }
        final claimed =
            await AppDatabase.instance.runTransaction<bool>((tx) async {
          final snap = await tx.get(docRef);
          final data = snap.data();
          if (data == null) return false;
          if (busy) return false;
          if (FirestoreService.isUrgentRequestExpired(data)) {
            expired = true;
            return false;
          }
          final status = (data['status'] ?? '').toString();
          final assigned = (data['assignedDoctorUid'] ?? '').toString();
          final alreadyTaken = data['doctorAcceptedAt'] != null ||
              (assigned.isNotEmpty && assigned != widget.doctorUid) ||
              status == 'Confirmed' ||
              status == 'In Progress' ||
              status == 'Completed' ||
              status == 'Declined';
          if (alreadyTaken) return false;
          tx.update(docRef, {
            'status': (isSosPipeline && needsAmbulance)
                ? 'Pending Ambulance Dispatch'
                : 'Confirmed',
            if (isSosPipeline) ...{
              'doctorOtp':
                  SosService.newOtp(), // shared with the hospital on arrival
              'doctorDistanceKm': sosDocKm(data),
              'doctorEtaMinutes': SosService.etaMinutesForKm(sosDocKm(data)),
              'doctorDeadlineAt': IstClock.now()
                  .add(Duration(
                      minutes: SosService.etaMinutesForKm(sosDocKm(data))))
                  .toIso8601String(),
            },
            if (isSosPipeline && needsAmbulance) ...{
              'sosAmbulanceCandidatesKm': ambulanceCands,
              'ambulanceStageStartedAt': IstClock.now().toIso8601String(),
            },
            'doctorUid': widget.doctorUid,
            'doctorName': widget.doctorName,
            'assignedDoctorName': widget.doctorName,
            'assignedDoctorUid': widget.doctorUid,
            'doctorAcceptedAt': IstClock.now().toIso8601String(),
            // Doctor's hospital + its live location, for navigation
            if (hospital != null) ...{
              'hospital': hospital.name,
              'doctorHospitalName': hospital.name,
              if (hospital.lat != null && hospital.lng != null) ...{
                'doctorLat': hospital.lat,
                'doctorLng': hospital.lng,
                'doctorHospitalLat': hospital.lat,
                'doctorHospitalLng': hospital.lng,
              },
            },
          });
          return true;
        });
        if (!claimed) {
          if (!mounted) return;
          final messenger = ScaffoldMessenger.of(context);
          Navigator.pop(context);
          messenger.showSnackBar(SnackBar(
            content: Text(expired
                ? 'This request has expired and was closed.'
                : busy
                    ? 'Complete your ongoing emergency before accepting another one.'
                    : 'Another provider already accepted this request.'),
            backgroundColor: AppColors.warning,
          ));
          return;
        }
        acceptedHospital = hospital;
      } else {
        await FirestoreService.respondToEmergencyRequest(
          appointmentId: appointmentId,
          accept: false,
          respondingDoctorUid: widget.doctorUid,
          respondingDoctorName: widget.doctorName,
        );
      }

      if (!mounted) return;

      // Close the alert popup
      Navigator.pop(context);

      if (accept) {
        final String navHospitalName =
            (widget.appointment['assignedHospitalName'] ?? '')
                    .toString()
                    .isNotEmpty
                ? widget.appointment['assignedHospitalName'].toString()
                : (acceptedHospital?.name ?? '');
        final double? navLat =
            toNum(widget.appointment['assignedHospitalLat'])?.toDouble() ??
                acceptedHospital?.lat;
        final double? navLng =
            toNum(widget.appointment['assignedHospitalLng'])?.toDouble() ??
                acceptedHospital?.lng;
        // Show Doctor Navigation & Map sheet
        showDialog(
          context: context,
          builder: (ctx) => AppDialogShell(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.successTint,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_circle_rounded,
                        color: AppColors.success, size: 48),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '🎉 Request Accepted!',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Patient has been notified and will travel to your clinic/hospital for urgent consultation.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.bgLight,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                                child: const Text('Patient:',
                                    style:
                                        TextStyle(color: AppTheme.textMuted))),
                            Flexible(
                                child: Text(patientName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.right)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                                child: const Text('Phone:',
                                    style:
                                        TextStyle(color: AppTheme.textMuted))),
                            Flexible(
                                child: Text(patientPhone,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.right)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Assigned Hospital:',
                                style: TextStyle(color: AppTheme.textMuted)),
                            Expanded(
                              child: Text(
                                navHospitalName.isNotEmpty
                                    ? navHospitalName
                                    : 'Assigned Hospital',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primaryTeal),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (navHospitalName.isNotEmpty) ...[
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brand),
                      onPressed: () {
                        _openMap(navHospitalName, navLat, navLng);
                        Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.local_hospital_rounded, size: 18),
                      label: const Text('Navigate to Hospital'),
                    ),
                    const SizedBox(height: 10),
                  ],
                  OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Request declined. It continues to other doctors in range.'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ErrorMessages.of(e, action: 'respond to this request')),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isResponding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final patientName = widget.appointment['patientName'] ?? 'Patient';
    final patientPhone = widget.appointment['patientPhone'] ?? 'N/A';
    final category = widget.appointment['emergencyCategory'] ??
        widget.appointment['doctorCategory'] ??
        'General';
    final location = widget.appointment['locationName'] ?? 'Nearby Patient';
    final int price = toNum(widget.appointment['price'])?.toInt() ?? 624;
    final int basePrice = toNum(widget.appointment['basePrice'])?.toInt() ?? 0;
    final int surcharge =
        toNum(widget.appointment['emergencySurcharge'])?.toInt() ?? 104;
    final bool requiresAmbulance =
        widget.appointment['requiresAmbulance'] ?? true;
    final Map<String, dynamic> qAnswers =
        Map<String, dynamic>.from(widget.appointment['questionAnswers'] ?? {});

    return ScrollableActionDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: const BorderSide(color: AppColors.danger, width: 2),
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Glowing Pulsing Red Siren Badge
          ScaleTransition(
            scale: _pulseAnim,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.dangerSoft,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.danger, width: 2),
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.danger,
                size: 48,
              ),
            ),
          ),

          const SizedBox(height: 16),

          const Text(
            '🚨 CRITICAL EMERGENCY ALERT',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.danger,
              letterSpacing: 0.5,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            '$patientName is requesting an urgent $category emergency consultation!',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
          ),

          const SizedBox(height: 20),

          // Patient & Payment Details Box
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.bgLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                        child: const Text('Patient Name:',
                            style: TextStyle(
                                color: AppTheme.textMuted, fontSize: 12))),
                    Flexible(
                        child: Text(patientName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            textAlign: TextAlign.right)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                        child: const Text('Contact Phone:',
                            style: TextStyle(
                                color: AppTheme.textMuted, fontSize: 12))),
                    Flexible(
                        child: Text(patientPhone,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            textAlign: TextAlign.right)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Flexible(
                      child: Text('Patient Area:',
                          style: TextStyle(
                              color: AppTheme.textMuted, fontSize: 12)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        location,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                        child: const Text('Transport Mode:',
                            style: TextStyle(
                                color: AppTheme.textMuted, fontSize: 12))),
                    Flexible(
                        child: Text(
                            requiresAmbulance
                                ? '🚑 Ambulance'
                                : '🚗 Patient Driving',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.darkNavy),
                            textAlign: TextAlign.right)),
                  ],
                ),
                if (qAnswers.isNotEmpty) ...[
                  const Divider(height: 16),
                  const Text('Questionnaire Responses:',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.darkNavy)),
                  const SizedBox(height: 4),
                  ...qAnswers.entries.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 2.0),
                        child: Text('• ${e.key}: ${e.value}',
                            style: const TextStyle(
                                fontSize: 11, color: AppTheme.textMuted)),
                      )),
                ],
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                        child: const Text('Base Fee + 20% Emergency Surcharge:',
                            style: TextStyle(
                                fontSize: 11, color: AppTheme.textMuted))),
                    Flexible(
                        child: Text('₹$basePrice + ₹$surcharge',
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w600),
                            textAlign: TextAlign.right)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                        child: const Text('Total Earning:',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textDark))),
                    Flexible(
                        child: Text('₹$price',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryTeal,
                            ),
                            textAlign: TextAlign.right)),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
      actions: DoctorEmergencyActions(
        responding: _isResponding,
        onDecline: () => _handleResponse(false),
        onAccept: () => _handleResponse(true),
      ),
    );
  }
}

/// Presentation only: the caller retains the existing transactional handlers.
class DoctorEmergencyActions extends StatelessWidget {
  const DoctorEmergencyActions(
      {super.key,
      required this.responding,
      required this.onDecline,
      required this.onAccept});
  final bool responding;
  final VoidCallback onDecline;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    if (responding) {
      return const SizedBox(
          height: 48,
          child: Center(
              child: CircularProgressIndicator(color: AppTheme.primaryTeal)));
    }
    final decline = OutlinedButton(
      key: const ValueKey('doctor-emergency-decline'),
      onPressed: onDecline,
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppColors.danger, width: 1.5),
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      child: const Text('Decline',
          textAlign: TextAlign.center,
          style:
              TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
    );
    final accept = ElevatedButton(
      key: const ValueKey('doctor-emergency-accept'),
      onPressed: onAccept,
      style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brand,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
      child: const Text('Accept Request', textAlign: TextAlign.center),
    );
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 320) {
        return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [accept, const SizedBox(height: 8), decline]);
      }
      return Row(children: [
        Expanded(child: decline),
        const SizedBox(width: 12),
        Expanded(child: accept)
      ]);
    });
  }
}
