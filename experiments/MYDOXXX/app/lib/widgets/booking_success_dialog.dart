import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../constants/app_colors.dart';

class BookingSuccessDialog extends StatefulWidget {
  final String doctorName;
  final String category;
  final String date;
  final String time;
  final String consultationType;
  final int price;
  final VoidCallback onViewBookings;

  const BookingSuccessDialog({
    super.key,
    required this.doctorName,
    required this.category,
    required this.date,
    required this.time,
    required this.consultationType,
    required this.price,
    required this.onViewBookings,
  });

  @override
  State<BookingSuccessDialog> createState() => _BookingSuccessDialogState();
}

class _BookingSuccessDialogState extends State<BookingSuccessDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _scaleAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.elasticOut,
    );

    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Scale Animated Checkmark Icon Badge
            ScaleTransition(
              scale: _scaleAnim,
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: AppTheme.primaryTeal.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Container(
                    width: 68,
                    height: 68,
                    decoration: const BoxDecoration(
                      color: AppTheme.primaryTeal,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 44,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Fade Animated Title
            FadeTransition(
              opacity: _fadeAnim,
              child: Column(
                children: [
                  const Text(
                    '🎉 Congratulations!',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Your appointment has been successfully confirmed!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textMuted,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Appointment Summary Details Box
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
                            Flexible(child: const Text('Doctor:',
                                style: TextStyle(color: AppTheme.textMuted))),
                            Flexible(child: Text(widget.doctorName,
                                style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(child: const Text('Specialty:',
                                style: TextStyle(color: AppTheme.textMuted))),
                            Flexible(child: Text(widget.category,
                                style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(child: const Text('Date & Time:',
                                style: TextStyle(color: AppTheme.textMuted))),
                            Flexible(child: Text('${widget.date} @ ${widget.time}',
                                style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(child: const Text('Consultation Mode:',
                                style: TextStyle(color: AppTheme.textMuted))),
                            Flexible(child: Text(widget.consultationType,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primaryTeal), textAlign: TextAlign.right)),
                          ],
                        ),
                        const Divider(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(child: const Text('Amount Charged:',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textDark))),
                            Flexible(child: Text(
                              '₹${widget.price}',
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

                  // Action Buttons
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onViewBookings();
                    },
                    child: const Text('View My Bookings'),
                  ),

                  const SizedBox(height: 10),

                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppColors.lineStrong),
                    ),
                    child: const Text('Close', style: TextStyle(color: AppTheme.textDark)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
