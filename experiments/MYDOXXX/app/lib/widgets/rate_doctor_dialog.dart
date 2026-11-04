import 'package:flutter/material.dart';

import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_messages.dart';
import '../constants/app_colors.dart';

class RateDoctorDialog extends StatefulWidget {
  final String appointmentId;
  final String doctorUid;
  final String doctorName;
  final String patientUid;
  final String patientName;
  // Collection holding the provider: 'doctors' (default), 'therapists',
  // 'nurses' or 'technicians'
  final String providerCollection;

  const RateDoctorDialog({
    super.key,
    required this.appointmentId,
    required this.doctorUid,
    required this.doctorName,
    required this.patientUid,
    required this.patientName,
    this.providerCollection = 'doctors',
  });

  @override
  State<RateDoctorDialog> createState() => _RateDoctorDialogState();
}

class _RateDoctorDialogState extends State<RateDoctorDialog> {
  double _rating = 5.0;
  final TextEditingController _reviewController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  Future<void> _submitRating() async {
    setState(() => _isSubmitting = true);

    try {
      await FirestoreService.submitDoctorRating(
        appointmentId: widget.appointmentId,
        doctorUid: widget.doctorUid,
        patientUid: widget.patientUid,
        patientName: widget.patientName,
        rating: _rating,
        review: _reviewController.text.trim(),
        providerCollection: widget.providerCollection,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Thank you for rating ${widget.doctorName}!'),
          backgroundColor: AppTheme.primaryTeal,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ErrorMessages.of(e, action: 'submit your rating')),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_rounded, color: AppColors.warningBright, size: 52),
            const SizedBox(height: 12),
            Text(
              'Rate ${widget.doctorName}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'How was your consultation experience?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),

            const SizedBox(height: 16),

            // Interactive Star Rating Row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final starValue = index + 1;
                return IconButton(
                  icon: Icon(
                    starValue <= _rating ? Icons.star_rounded : Icons.star_border_rounded,
                    color: AppColors.warningBright,
                    size: 36,
                  ),
                  onPressed: () {
                    setState(() {
                      _rating = starValue.toDouble();
                    });
                  },
                );
              }),
            ),

            const SizedBox(height: 16),

            // Feedback / Review Input Box
            TextField(
              controller: _reviewController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Write your feedback or review (optional)...',
              ),
            ),

            const SizedBox(height: 24),

            _isSubmitting
                ? const CircularProgressIndicator(color: AppTheme.primaryTeal)
                : ElevatedButton(
                    onPressed: _submitRating,
                    child: Text('Submit Rating (${_rating.toStringAsFixed(1)} ★)'),
                  ),
          ],
        ),
      ),
    );
  }
}
