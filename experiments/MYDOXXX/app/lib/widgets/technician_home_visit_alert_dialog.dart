import '../services/lab_device.dart';
import 'package:flutter/material.dart';
import '../utils/safe_cast.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_messages.dart';
import '../constants/app_colors.dart';

class TechnicianHomeVisitAlertDialog extends StatefulWidget {
  final Map<String, dynamic> appointment;
  final String technicianUid;
  final String technicianName;

  const TechnicianHomeVisitAlertDialog({
    super.key,
    required this.appointment,
    this.technicianUid = '',
    this.technicianName = '',
  });

  @override
  State<TechnicianHomeVisitAlertDialog> createState() =>
      _TechnicianHomeVisitAlertDialogState();
}

class _TechnicianHomeVisitAlertDialogState
    extends State<TechnicianHomeVisitAlertDialog> {
  bool _isResponding = false;

  Future<void> _openMap(String locationName, double? lat, double? lng) async {
    final query = (lat != null && lng != null)
        ? '$lat,$lng'
        : Uri.encodeComponent(
            locationName.isNotEmpty ? locationName : 'Patient Address');
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
    final locationName = widget.appointment['locationName'] ?? 'Patient Address';
    final double? patientLat =
        toNum(widget.appointment['patientLat'])?.toDouble();
    final double? patientLng =
        toNum(widget.appointment['patientLng'])?.toDouble();

    try {
      final claimed = await FirestoreService.respondToEmergencyRequest(
        appointmentId: appointmentId,
        accept: accept,
        respondingDoctorUid: widget.technicianUid,
        respondingDoctorName: widget.technicianName,
      );

      if (!claimed) {
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(const SnackBar(
          content: Text('Another provider already accepted this request.'),
          backgroundColor: AppColors.warning,
        ));
        return;
      }

      if (!mounted) return;

      Navigator.pop(context);

      if (accept) {
        showDialog(
          context: context,
          builder: (ctx) => Dialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.science_rounded,
                        color: AppColors.primary, size: 48),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '🎉 Sample Visit Accepted!',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Navigate to patient\'s address for home sample collection.',
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
                            Flexible(child: const Text('Patient:',
                                style: TextStyle(color: AppTheme.textMuted))),
                            Flexible(child: Text(patientName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(child: const Text('Phone:',
                                style: TextStyle(color: AppTheme.textMuted))),
                            Flexible(child: Text(patientPhone,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Home Address:',
                                style: TextStyle(color: AppTheme.textMuted)),
                            Expanded(
                              child: Text(
                                locationName,
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand),
                    onPressed: () {
                      _openMap(locationName, patientLat, patientLng);
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.directions_outlined, size: 20),
                    label: const Text('Get Directions / Open Maps'),
                  ),

                  const SizedBox(height: 10),

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
                'Sample visit request declined and broadcasted to nearby technicians.'),
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
    final testCategory = widget.appointment['doctorCategory'] ?? 'Lab Test';
    final location = widget.appointment['locationName'] ?? 'Patient Address';
    final int price = toNum(widget.appointment['price'])?.toInt() ?? 0;
    final int basePrice =
        toNum(widget.appointment['basePrice'])?.toInt() ?? 0;
    final int extraOffered =
        toNum(widget.appointment['offeredExtraAmount'])?.toInt() ?? 0;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: const BorderSide(color: AppColors.primary, width: 2),
      ),
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.science_rounded,
                color: AppColors.primary,
                size: 44,
              ),
            ),

            const SizedBox(height: 16),

            const Text(
              '🔬 LAB TEST SAMPLE VISIT REQUEST',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),

            const SizedBox(height: 6),

            Text(
              '$patientName is requesting a home sample collection for $testCategory.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
            ),

            const SizedBox(height: 20),

            // Details Box
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
                      Flexible(child: const Text('Patient Name:',
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 12))),
                      Flexible(child: Text(patientName,
                          style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(child: const Text('Phone:',
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 12))),
                      Flexible(child: Text(patientPhone,
                          style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Home Area:',
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                      Expanded(
                        child: Text(
                          location,
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  // Only older bookings can carry an incentive
                  if (extraOffered > 0)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(child: const Text('Base Test + Offered Incentive:',
                          style: TextStyle(fontSize: 11, color: AppTheme.textMuted))),
                      Flexible(child: Text('₹$basePrice + ₹$extraOffered',
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.success), textAlign: TextAlign.right)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(child: const Text('Total Earning:',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, color: AppTheme.textDark))),
                      Flexible(child: Text(
                        '₹$price',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                       textAlign: TextAlign.right)),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Accept / Decline Buttons
            _isResponding
                ? const CircularProgressIndicator(color: AppColors.primary)
                : Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _handleResponse(false),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.danger, width: 1.5),
                            minimumSize: const Size(0, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                          child: const Text('Decline',
                              style: TextStyle(
                                  color: AppColors.danger,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _handleResponse(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.brand,
                            minimumSize: const Size(0, 48),
                          ),
                          child: const Text('Accept Visit'),
                        ),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}
