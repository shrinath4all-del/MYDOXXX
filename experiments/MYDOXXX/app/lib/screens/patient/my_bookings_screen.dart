import '../../config/test_lab_config.dart';
import '../../utils/maps_navigation.dart';
import '../../utils/safe_cast.dart';
import '../../widgets/medcoins_choice.dart';
import '../../services/call_service.dart';
import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/payment_service.dart';
import '../../utils/appointment_rules.dart';
import '../common/appointments_calendar_screen.dart';
import '../../services/physio_agency_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/rate_doctor_dialog.dart';
import '../chat/chat_screen.dart';
import '../chat/video_call_screen.dart';
import '../../utils/error_messages.dart';
import '../../utils/stream_cache.dart';
import '../../utils/responsive.dart';
import '../../constants/app_colors.dart';

import '../../widgets/chat_button.dart';
import '../../utils/ist_clock.dart';
import '../../widgets/app_alert_dialog.dart';

class MyBookingsScreen extends StatefulWidget {
  final UserModel patient;

  /// Tab to open first: 0 Scheduled, 1 Urgent, 2 SOS Pipeline.
  final int initialTab;

  const MyBookingsScreen({
    super.key,
    required this.patient,
    this.initialTab = 0,
  });

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  // Live data connections kept open across redraws
  final StreamCache _streams = StreamCache();

  late int _selectedCategoryTab = widget.initialTab; // 0 = Scheduled Meetings, 1 = Urgent Consultations, 2 = SOS Emergency Pipeline
  int _selectedStatusTab = 0; // 0 = Upcoming, 1 = Completed

  // Bookings whose Razorpay payment is in progress
  final Set<String> _paying = {};

  Future<void> _pay(Map<String, dynamic> item) async {
    final id = (item['appointmentId'] ?? '').toString();
    if (id.isEmpty || _paying.contains(id)) return;
    // MedCoins (money returned to the wallet) can pay for it
    final useCoins = await askUseMedCoins(context,
        patientUid: widget.patient.uid,
        price: (toNum(item['price']) ?? 0));
    if (useCoins == null || !mounted) return;
    setState(() => _paying.add(id));
    final result = await PaymentService.payForBooking(id, useCoins: useCoins);
    if (!mounted) return;
    setState(() => _paying.remove(id));
    if (result.cancelled) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result.success
          ? (TestLabConfig.enabled ? 'TEST payment recorded. No money was charged.' : 'Payment successful. Your visit is confirmed.')
          : result.message),
      backgroundColor: result.success ? AppColors.successDark : AppColors.danger,
    ));
  }

  IconData _getConsultationIcon(String type) {
    if (type.contains('Online')) {
      return Icons.videocam_outlined;
    } else if (type.contains('Home') || type.contains('Dispatch')) {
      return Icons.home_outlined;
    } else if (type.contains('SOS')) {
      return Icons.warning_amber_rounded;
    }
    return Icons.local_hospital_outlined;
  }

  void _openVideoCall(BuildContext context, String docName,
      {required String doctorUid,
      String appointmentId = '',
      Map<String, dynamic>? booking}) {
    // Only inside the booked slot; the call ends by itself when it ends
    final window = booking == null
        ? (open: true, message: '', end: null as DateTime?)
        : AppointmentRules.videoWindow(booking);
    if (!window.open) {
      showDialog(
        context: context,
        builder: (ctx) => AppAlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Row(children: [
            Icon(Icons.schedule_rounded, color: AppColors.warning),
            SizedBox(width: 8),
            Expanded(child: Text('Video call not available')),
          ]),
          content: Text(window.message, style: const TextStyle(height: 1.4)),
          actions: [
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoCallScreen(
          callId: CallService.newCallId(
              appointmentId.isNotEmpty ? appointmentId : doctorUid),
          isCaller: true,
          appointmentId: appointmentId,
          currentUid: widget.patient.uid,
          callerName: widget.patient.name,
          peerUid: doctorUid,
          peerName: docName,
          peerRole: 'Doctor',
          endsAt: window.end,
        ),
      ),
    );
  }

  void _openChat(BuildContext context, String doctorUid, String doctorName,
      {String peerRole = 'Doctor'}) {
    final chatId = '${widget.patient.uid}_$doctorUid';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chatId: chatId,
          currentUserId: widget.patient.uid,
          currentUserName: widget.patient.name,
          peerName: doctorName,
          peerRole: peerRole,
        ),
      ),
    );
  }

  static bool _isTherapistBooking(Map<String, dynamic> item) =>
      item['isTherapistRequest'] == true || item['roleTarget'] == 'therapist';
  static bool _isNurseBooking(Map<String, dynamic> item) =>
      item['isNurseRequest'] == true || item['roleTarget'] == 'nurse';
  static bool _isTechnicianBooking(Map<String, dynamic> item) =>
      item['isTechnicianRequest'] == true || item['roleTarget'] == 'technician';

  /// Who the booking is with: 'Therapist', 'Nurse', 'Technician' or 'Doctor'.
  static String _providerRole(Map<String, dynamic> item) {
    if (_isTherapistBooking(item)) return 'Therapist';
    if (_isNurseBooking(item)) return 'Nurse';
    if (_isTechnicianBooking(item)) return 'Technician';
    return 'Doctor';
  }

  /// Firestore collection that holds the booked provider's profile.
  static String _providerCollection(Map<String, dynamic> item) =>
      switch (_providerRole(item)) {
        'Therapist' => 'therapists',
        'Nurse' => 'nurses',
        'Technician' => 'technicians',
        _ => 'doctors',
      };

  void _openRatingDialog(
      BuildContext context, Map<String, dynamic> appointmentData) {
    showDialog(
      context: context,
      builder: (_) => RateDoctorDialog(
        appointmentId: appointmentData['appointmentId'] ?? '',
        doctorUid: appointmentData['doctorUid'] ?? '',
        doctorName: appointmentData['doctorName'] ?? 'Doctor',
        patientUid: widget.patient.uid,
        patientName: widget.patient.name,
        // Ratings go to the provider's own collection, not always 'doctors'
        providerCollection: _providerCollection(appointmentData),
      ),
    );
  }

  Widget _buildCategoryChip(int index, String label, IconData icon) {
    final isSelected = _selectedCategoryTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedCategoryTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryTeal : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16,
                  color: isSelected ? Colors.white : AppTheme.darkNavy),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : AppTheme.darkNavy,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveCenter(child: Scaffold(
      backgroundColor: AppTheme.bgLight,
      appBar: AppBar(
        title: const Text('My Appointments'),
        actions: [
          IconButton(
            tooltip: 'Calendar view',
            icon: const Icon(Icons.calendar_month_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AppointmentCalendarScreen(
                    uid: widget.patient.uid, forDoctor: false),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. TOP CATEGORY TYPE BAR (Scheduled Meetings vs Urgent Consultations vs SOS Emergency)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.lineStrong),
            ),
            child: Row(
              children: [
                _buildCategoryChip(0, 'Scheduled', Icons.calendar_month_outlined),
                const SizedBox(width: 2),
                _buildCategoryChip(1, 'Urgent', Icons.bolt_rounded),
                const SizedBox(width: 2),
                _buildCategoryChip(2, 'SOS Pipeline', Icons.warning_amber_rounded),
              ],
            ),
          ),

          // 2. STATUS FILTER SUB-TABS (Upcoming vs Completed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Upcoming / Active'),
                  selected: _selectedStatusTab == 0,
                  selectedColor: AppTheme.primaryTeal.withValues(alpha: 0.15),
                  labelStyle: TextStyle(
                    color: _selectedStatusTab == 0
                        ? AppTheme.primaryTeal
                        : AppTheme.darkNavy,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  onSelected: (val) {
                    if (val) setState(() => _selectedStatusTab = 0);
                  },
                ),
                const SizedBox(width: 10),
                ChoiceChip(
                  label: const Text('Completed History'),
                  selected: _selectedStatusTab == 1,
                  selectedColor: AppColors.primaryBorder,
                  labelStyle: TextStyle(
                    color: _selectedStatusTab == 1
                        ? AppColors.navy
                        : AppTheme.darkNavy,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  onSelected: (val) {
                    if (val) setState(() => _selectedStatusTab = 1);
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Appointments Stream List
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _streams.get('bookings', () => FirestoreService.getPatientBookingsStream(widget.patient.uid)),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return LoadErrorView(error: snapshot.error, what: 'your bookings');
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppTheme.primaryTeal),
                  );
                }

                final allBookings = snapshot.data ?? [];

                // Filter by Category Type
                final categoryFilteredList = allBookings.where((item) {
                  final consultationType =
                      item['consultationType']?.toString() ?? 'Clinic/Visit';
                  final bool isUrgent = item['isUrgentEmergency'] == true;

                  if (_selectedCategoryTab == 2) {
                    return consultationType == 'SOS Emergency Pipeline';
                  } else if (_selectedCategoryTab == 1) {
                    return isUrgent && consultationType != 'SOS Emergency Pipeline';
                  } else {
                    return !isUrgent && consultationType != 'SOS Emergency Pipeline';
                  }
                }).toList();

                // Filter by Status Tab (Upcoming vs Completed)
                // Upcoming: today + tomorrow, slots that have not ended, earliest
                // first. Completed: finished or passed. Bookings after tomorrow
                // are in neither list yet (they show in the calendar).
                final nowTs = IstClock.now();
                final currentDisplayList = categoryFilteredList
                    .where((item) => _selectedStatusTab == 0
                        ? AppointmentRules.isUpcoming(item, now: nowTs)
                        : AppointmentRules.isHistory(item, now: nowTs))
                    .toList()
                  ..sort(_selectedStatusTab == 0
                      ? AppointmentRules.compareByStart
                      : AppointmentRules.compareByStartDesc);

                if (currentDisplayList.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _selectedStatusTab == 0
                              ? Icons.event_available_outlined
                              : Icons.task_alt_rounded,
                          size: 60,
                          color: AppColors.lineStrong,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _selectedStatusTab == 0
                              ? 'No active upcoming appointments'
                              : 'No completed consultation history',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.darkNavy,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: currentDisplayList.length,
                  itemBuilder: (context, index) {
                    final item = currentDisplayList[index];
                    final doctorUid = item['doctorUid'] ?? '';
                    final docName = item['doctorName'] ?? 'Doctor';
                    final category = item['doctorCategory'] ?? 'Specialist';
                    final hospital = item['hospital'] ?? item['assignedHospitalName'] ?? 'Clinic/Hospital';
                    final date = item['date'] ?? '';
                    final time = item['time'] ?? '';
                    final status = item['status'] ?? 'Confirmed';
                    final consultationType =
                        item['consultationType'] ?? 'Clinic/Visit';
                    final isUrgentEmergency = item['isUrgentEmergency'] == true;
                    final otp = item['otp'] ?? '----';
                    final hasBeenRated = item['hasBeenRated'] == true;
                    final startTime = item['startTimeFormatted'] ?? '';
                    final endTime = item['endTimeFormatted'] ?? '';
                    final providerRole = _providerRole(item);
                    // Therapist / nurse / technician bookings are home visits
                    final isHomeVisitProvider = providerRole != 'Doctor';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: isUrgentEmergency
                            ? Border.all(
                                color: AppColors.danger.withValues(alpha: 0.5),
                                width: 1.5)
                            : null,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 15,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: isUrgentEmergency
                                    ? AppColors.dangerSoft
                                    : AppColors.primaryTint,
                                child: Icon(
                                  _getConsultationIcon(consultationType),
                                  color: isUrgentEmergency
                                      ? AppColors.danger
                                      : AppTheme.primaryTeal,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      docName,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.darkNavy,
                                      ),
                                    ),
                                    Text(
                                      '$category • $hospital',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Status Badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: status == 'Completed'
                                      ? AppColors.primarySoft
                                      : (status == 'Declined' || status == 'Provider Absent')
                                          ? AppColors.dangerSoft
                                          : status == 'In Progress'
                                              ? AppColors.warningTint
                                              : isUrgentEmergency
                                                  ? AppColors.dangerSoft
                                                  : AppColors.successTint,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  isUrgentEmergency && status != 'Completed'
                                      ? '🚨 URGENT'
                                      : status,
                                  style: TextStyle(
                                    color: status == 'Completed'
                                        ? AppColors.primaryDark
                                        : (status == 'Declined' || status == 'Provider Absent')
                                            ? AppColors.danger
                                            : status == 'In Progress'
                                                ? AppColors.warningDeep
                                                : isUrgentEmergency
                                                    ? AppColors.danger
                                                    : AppColors.successDeep,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          if (status == 'Confirmed' &&
                              item['runningLateMinutes'] != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              '${item['doctorName'] ?? 'Your provider'} is running about '
                              '${item['runningLateMinutes']} mins late.',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.orange),
                            ),
                          ],
                          if (status == 'Broadcasted' &&
                              PhysioAgencyService.isAgencyWindowOpen(item)) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Sent to ${item['agencyName'] ?? 'a partner agency'} physios first. '
                              'If none accepts by ${PhysioAgencyService.timeLabel(item['agencyOfferExpiresAt'])}, '
                              'all physios in your area get it.',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary),
                            ),
                          ],
                          // Online payment (Razorpay) after the provider accepts
                          if (PaymentService.isCashCollected(item)) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.verified_rounded,
                                    size: 16, color: AppColors.successDark),
                                const SizedBox(width: 4),
                                Text(
                                  'Cash paid ₹${toNum(item['price'])?.round() ?? 0}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.successDark),
                                ),
                              ],
                            ),
                          ] else if (PaymentService.isCashDue(item) &&
                              status != 'Cancelled' &&
                              status != 'Declined') ...[
                            const SizedBox(height: 8),
                            Text(
                              'Pay ₹${toNum(item['price'])?.round() ?? 0} in cash to the doctor at the visit.',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.orange),
                            ),
                          ] else if (PaymentService.canPayNow(item)) ...[
                            const SizedBox(height: 10),
                            Text(
                              TestLabConfig.enabled ? 'Simulate payment to test OTP arrival. No money is charged.' : 'Pay to confirm your visit. The provider can start only after payment.',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.orange),
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _paying.contains(item['appointmentId'])
                                    ? null
                                    : () => _pay(item),
                                icon: _paying.contains(item['appointmentId'])
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.payment_rounded, size: 18),
                                label: Text(TestLabConfig.enabled ? 'Simulate payment • no charge' : 'Pay ₹${toNum(item['price'])?.round() ?? 0}'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.brand,
                                  minimumSize: const Size(0, 42),
                                ),
                              ),
                            ),
                          ] else if (PaymentService.isAwaitingPayment(item) &&
                              status != 'Cancelled') ...[
                            const SizedBox(height: 8),
                            const Text(
                              'You can pay once a provider accepts your booking.',
                              style: TextStyle(
                                  fontSize: 12, color: AppTheme.textMuted),
                            ),
                          ] else if (PaymentService.isPaid(item)) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.verified_rounded,
                                    size: 16, color: AppColors.successDark),
                                const SizedBox(width: 4),
                                Text(
                                  'Paid ₹${toNum(item['amountPaid'])?.round() ?? toNum(item['price'])?.round() ?? 0} online',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.successDark),
                                ),
                              ],
                            ),
                          ],
                          if (item['paymentStatus'] == 'refunded') ...[
                            const SizedBox(height: 8),
                            Text(
                              '₹${toNum(item['amountPaid'])?.round() ?? toNum(item['price'])?.round() ?? 0} refunded to your original payment method (5–7 working days).',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.successDark),
                            ),
                          ],
                          if (status == 'Cancelled' &&
                              (item['cancelReason'] ?? '').toString().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Cancelled: ${item['cancelReason']}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.danger),
                            ),
                          ],
                          if (status == 'Provider Absent') ...[
                            const SizedBox(height: 8),
                            const Text(
                              'The provider did not arrive in the booked time. '
                              'Please book again.',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.danger),
                            ),
                          ],
                          const SizedBox(height: 12),

                          // Consultation Mode + OTP Badge Row
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryTeal
                                      .withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Icon(_getConsultationIcon(consultationType),
                                        size: 14, color: AppTheme.primaryTeal),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Mode: ${AppointmentRules.modeLabel(consultationType)}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.primaryTeal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),

                              // OTP Share Badge for Patient (Only for Upcoming)
                              if (status != 'Completed' && status != 'Declined' &&
                                  status != 'Provider Absent')
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.warningTint,
                                    borderRadius: BorderRadius.circular(10),
                                    border:
                                        Border.all(color: AppColors.warningBorder),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.lock_clock,
                                          size: 14, color: AppColors.warningBright),
                                      const SizedBox(width: 4),
                                      Text(
                                        'OTP: $otp',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.warningDeep,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          // Date & Time Box
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppTheme.bgLight,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_today_outlined,
                                    size: 16, color: AppTheme.textMuted),
                                const SizedBox(width: 6),
                                Text(
                                  date,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textDark,
                                  ),
                                ),
                                const Spacer(),
                                const Icon(Icons.access_time_rounded,
                                    size: 16, color: AppTheme.textMuted),
                                const SizedBox(width: 6),
                                Text(
                                  time,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textDark,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          if (startTime.isNotEmpty || endTime.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.primaryTint,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  if (startTime.isNotEmpty)
                                    Text('Start Time: $startTime',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.primaryTeal)),
                                  if (endTime.isNotEmpty)
                                    Text('End Time: $endTime',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.blue)),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 16),

                          // Actions Row based on Consultation Status
                          Row(
                            children: [
                              // Chat: greyed out until the consultation starts,
                              // open until 24 h after it
                              if (doctorUid.isNotEmpty) ...[
                                Expanded(
                                  child: ChatButton(
                                    booking: item,
                                    viewerUid: widget.patient.uid,
                                    onChat: () => _openChat(
                                        context, doctorUid, docName,
                                        peerRole: providerRole),
                                  ),
                                ),
                                const SizedBox(width: 10),
                              ],

                              // Rate Doctor Button if Completed
                              if (status == 'Completed' && !hasBeenRated)
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () =>
                                        _openRatingDialog(context, item),
                                    icon: const Icon(Icons.star_rounded, size: 18),
                                    label: Text('Rate $providerRole'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.warning,
                                    ),
                                  ),
                                )
                              else if (consultationType == 'Online' &&
                                  status != 'Completed' &&
                                  status != 'Declined' &&
                                  status != 'Provider Absent')
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () => _openVideoCall(context, docName,
                                        doctorUid: doctorUid,
                                        appointmentId:
                                            (item['appointmentId'] ?? '').toString(),
                                        booking: item),
                                    icon: const Icon(Icons.videocam_rounded,
                                        size: 18),
                                    label: const Text('Join Call'),
                                  ),
                                )
                              // Home visits have no clinic to navigate to
                              else if (!isHomeVisitProvider &&
                                  !AppointmentRules.isHistory(item) &&
                                  status != 'Completed' &&
                                  status != 'Declined' &&
                                  status != 'Provider Absent')
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () => MapsNavigation.toHospitalWithHint(
                                        context, hospital.toString(),
                                        lat: toNum(item['doctorLat'])?.toDouble(),
                                        lng: toNum(item['doctorLng'])?.toDouble()),
                                    icon: const Icon(Icons.directions_outlined,
                                        size: 18),
                                    label: const Text('Clinic Location'),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ));
  }
}
