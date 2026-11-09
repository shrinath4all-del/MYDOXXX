import '../../services/service_otp.dart';
import '../../services/app_database.dart';
import '../../services/lab_device.dart';
import 'dart:async';
import '../../utils/safe_cast.dart';
import '../../widgets/verification_gate.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../services/pricing_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/therapist_status_dialog.dart';
import '../../utils/error_messages.dart';
import '../../utils/stream_cache.dart';
import '../../utils/responsive.dart';
import '../../constants/app_colors.dart';
import '../../services/images_master.dart';
import '../../widgets/master_image.dart';
import '../../widgets/circle_image.dart';
import '../../widgets/verified_badge.dart';
import '../../widgets/app_dialog.dart';
import '../../constants/app_strings.dart';

/// Urgent (same-day) therapy bookings cost this much extra on the session fee.
/// Urgent charge from Firestore app_settings/pricing (0 while not loaded).
double get _kUrgentSurchargeRate =>
    (PricingService.current.urgentSurchargePct ?? 0) / 100;

class BookTherapistScreen extends StatefulWidget {
  final UserModel patient;
  final String? initialTherapyName;

  const BookTherapistScreen({
    super.key,
    required this.patient,
    this.initialTherapyName,
  });

  @override
  State<BookTherapistScreen> createState() => _BookTherapistScreenState();
}

class _BookTherapistScreenState extends State<BookTherapistScreen> {
  // Live data connections kept open across redraws
  final StreamCache _streams = StreamCache();

  String? _selectedTherapyName;
  // 0 = Book for Later (from tomorrow), 1 = Today (urgent same-day: the date is
  // today, only slots still ahead are offered, and the urgent surcharge applies).
  int _selectedModeIndex = 0;
  bool get _isUrgentMode => _selectedModeIndex == 1;
  List<Map<String, dynamic>> _therapiesWithPrice = [];
  bool _loadingTherapies = true;
  StreamSubscription? _therapiesSub;

  Position? _patientPosition;
  bool _loadingPosition = true;
  String _liveAreaName = 'Nearby Patient Area';

  @override
  void initState() {
    super.initState();
    guardVerifiedRequester(context, widget.patient);
    _selectedTherapyName = widget.initialTherapyName;
    _fetchTherapies();
    _fetchPatientPosition();
    PricingService.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  void _priceNotSet() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text(PricingService.notSetMessage),
      backgroundColor: AppColors.warning,
    ));
  }

  /// Therapies from Firestore 'therapies', live: a therapy the admin adds,
  /// renames, re-prices or switches off shows here straight away.
  void _fetchTherapies() {
    _therapiesSub = FirestoreService.therapiesStream().listen((list) {
      if (!mounted) return;
      setState(() {
        _therapiesWithPrice = list;
        _loadingTherapies = false;
      });
    }, onError: (_) {
      if (mounted) setState(() => _loadingTherapies = false);
    });
  }

  @override
  void dispose() {
    _therapiesSub?.cancel();
    super.dispose();
  }

  Future<void> _fetchPatientPosition() async {
    try {
      final pos = await LabLocation.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 6),
        ),
      );
      final area = await LocationService.getCurrentLocation();
      if (mounted) {
        setState(() {
          _patientPosition = pos;
          _liveAreaName = area;
        });
      }
    } catch (_) {
      // GPS failed: the position stays unknown (not the Pune map centre)
    } finally {
      if (mounted) setState(() => _loadingPosition = false);
    }
  }

  String _formatDateKey(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String _formatDateStandard(DateTime dt) {
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    return '$day/$month/${dt.year}';
  }

  bool _isTimeSlotInPast(DateTime selectedDate, String timeSlotStr) {
    final now = DateTime.now();
    final isToday = selectedDate.year == now.year &&
        selectedDate.month == now.month &&
        selectedDate.day == now.day;

    if (!isToday) return false;

    try {
      final cleaned = timeSlotStr.trim().toUpperCase();
      final parts = cleaned.split(' ');
      if (parts.isEmpty) return false;

      final timeParts = parts[0].split(':');
      int hour = int.parse(timeParts[0]);
      final minute = timeParts.length > 1 ? int.parse(timeParts[1]) : 0;

      final isPm = cleaned.contains('PM');
      final isAm = cleaned.contains('AM');

      if (isPm && hour < 12) {
        hour += 12;
      } else if (isAm && hour == 12) {
        hour = 0;
      }

      final slotTime = DateTime(now.year, now.month, now.day, hour, minute);
      return slotTime.isBefore(now);
    } catch (_) {
      return false;
    }
  }

  /// The therapy's price from Firestore (null while it is not set).
  int? _getTherapyPrice(String therapyName) {
    for (final c in _therapiesWithPrice) {
      if ((c['name'] as String).toLowerCase() == therapyName.toLowerCase()) {
        return toNum(c['price'])?.toInt();
      }
    }
    return null;
  }

  void _showDoctorBookedPopup(String techName, String time, String date) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.event_busy_rounded, color: AppColors.warning, size: 28),
            SizedBox(width: 8),
            Flexible(
                child: Text('Time Slot Busy',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Therapist $techName is already attending another patient at $time on $date.\n\nPlease choose a different time slot or date for your therapy session.',
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Choose Another Time'),
          ),
        ],
      ),
    );
  }

  void _showPatientBookedPopup(String time, String date) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.calendar_month_rounded,
                color: AppColors.warningBright, size: 28),
            SizedBox(width: 8),
            Flexible(
                child: Text('Meeting Conflict',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You already have another appointment scheduled at $time on $date.\n\nTo prevent overlapping visits, please select a different time slot.',
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Pick Different Time'),
          ),
        ],
      ),
    );
  }

  // One booking at a time: a second tap on Confirm while the first is still
  // being saved would create a duplicate booking.
  bool _bookingInFlight = false;

  Future<void> _handleBookingConfirmation({
    required Map<String, dynamic> therapistData,
    required DateTime selectedDate,
    required String selectedTime,
    required int basePrice,
    required int urgentSurcharge,
    required bool isUrgent,
    required int totalPrice,
    required BuildContext bottomSheetContext,
    bool anyPhysio = false,
  }) async {
    if (_bookingInFlight) return;
    _bookingInFlight = true;
    try {
      await _handleBookingConfirmationImpl(therapistData: therapistData, selectedDate: selectedDate, selectedTime: selectedTime, basePrice: basePrice, urgentSurcharge: urgentSurcharge, isUrgent: isUrgent, totalPrice: totalPrice, bottomSheetContext: bottomSheetContext, anyPhysio: anyPhysio);
    } finally {
      _bookingInFlight = false;
    }
  }

  Future<void> _handleBookingConfirmationImpl({
    required Map<String, dynamic> therapistData,
    required DateTime selectedDate,
    required String selectedTime,
    required int basePrice,
    required int urgentSurcharge,
    required bool isUrgent,
    required int totalPrice,
    required BuildContext bottomSheetContext,
    bool anyPhysio = false,
  }) async {
    final String dateFormatted = _formatDateStandard(selectedDate);
    final String therapistName = therapistData['name'] ?? 'Therapist';

    if (_isTimeSlotInPast(selectedDate, selectedTime)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'That time has already passed. Please select another time slot.'),
      ));
      return;
    }

    // Live Double-Check 1: Check if Therapist is ALREADY booked at this time slot
    final doubleCheckTherapist = anyPhysio
        ? const <String>[]
        : await FirestoreService.getDoctorBookedTimeSlots(
            doctorUid: therapistData['uid'] ?? '',
            date: dateFormatted,
          );

    if (doubleCheckTherapist.contains(selectedTime.trim().toUpperCase())) {
      if (!mounted) return;
      _showDoctorBookedPopup(therapistName, selectedTime, dateFormatted);
      return;
    }

    // Live Double-Check 2: Check if Patient ALREADY has an appointment booked at this time slot
    final doubleCheckPatient = await FirestoreService.getPatientBookedTimeSlots(
      patientUid: widget.patient.uid,
      date: dateFormatted,
    );

    if (doubleCheckPatient.contains(selectedTime.trim().toUpperCase())) {
      if (!mounted) return;
      _showPatientBookedPopup(selectedTime, dateFormatted);
      return;
    }

    if (!mounted) return;

    final bool confirm = await AppDialog.confirm(
      context,
      icon: Icons.home_work_rounded,
      title: 'Confirm therapy session?',
      message: anyPhysio
          ? 'Your request goes to available physiotherapists in your area. The first one to accept is assigned to you.\n\nHome visit · $dateFormatted · $selectedTime'
          : 'Send a home visit request to therapist $therapistName for $dateFormatted at $selectedTime? The therapist will accept or decline it.',
      content: PriceBreakdown(
        base: basePrice,
        baseLabel: 'Session fee',
        extras: [
          (
            '${AppStrings.urgentSurcharge} (${(_kUrgentSurchargeRate * 100).round()}%)',
            urgentSurcharge
          ),
        ],
        total: totalPrice,
      ),
    );

    if (!confirm || !mounted) return;

    if (bottomSheetContext.mounted) {
      Navigator.pop(bottomSheetContext);
    }

    try {
      final docRef =
          AppDatabase.instance.collection('appointments').doc();
      final appointmentId = docRef.id;
      final otp = ServiceOtp.generate();

      await docRef.set({
        'appointmentId': appointmentId,
        'patientUid': widget.patient.uid,
        'patientName': widget.patient.name,
        'patientPhone': widget.patient.phone ?? '',
        'doctorUid': therapistData['uid'] ?? '',
        'doctorName': anyPhysio ? '' : (therapistData['name'] ?? 'Therapist'),
        'doctorCategory': _selectedTherapyName ??
            therapistData['qualification'] ??
            'Therapist',
        'therapyName': _selectedTherapyName ?? 'Physiotherapy',
        'therapistQualification': therapistData['qualification'] ?? '',
        'hospital': anyPhysio
            ? 'MyDox Care'
            : (therapistData['organisation'] ?? 'MyDox Care'),
        'date': dateFormatted,
        'time': selectedTime,
        'basePrice': basePrice,
        'urgentSurcharge': urgentSurcharge,
        'emergencySurcharge': urgentSurcharge,
        'offeredExtraAmount': 0, // tips are not offered for therapy
        'price': totalPrice,
        'locationName': _liveAreaName,
        // only a real GPS position (never the Pune map centre)
        if (_patientPosition != null) 'patientLat': _patientPosition!.latitude,
        if (_patientPosition != null) 'patientLng': _patientPosition!.longitude,
        'patientLocationKnown': _patientPosition != null,
        'bookingType': isUrgent ? 'urgent' : 'later',
        'consultationType': isUrgent ? 'Urgent Home Visit' : 'Home Visit',
        'isUrgentEmergency': isUrgent,
        'isTherapistRequest': true,
        'roleTarget': 'therapist',
        'status': 'Pending Home Visit',
        'paymentStatus': 'pending', // paid online after a provider accepts
        'otp': otp,
        'hasBeenRated': false,
        'declinedBy': [],
        'createdAt': DateTime.now().toIso8601String(),
      });

      // No physio picked: goes out now (partner agency first, then everyone)
      if (anyPhysio) {
        await FirestoreService.broadcastTherapistRequest(appointmentId);
      }

      if (!mounted) return;

      // Show Status Tracker Dialog for Patient
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => TherapistStatusDialog(
          appointmentId: appointmentId,
          therapistName: therapistData['name'] ?? 'Therapist',
          therapyName: _selectedTherapyName ?? 'Therapy',
          basePrice: basePrice,
          urgentSurcharge: urgentSurcharge,
          totalPrice: totalPrice,
          isUrgent: isUrgent,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ErrorMessages.of(e, action: 'send your request')),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Widget _buildModeTab(int index, String label) {
    final isSelected = _selectedModeIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedModeIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryTeal : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.white : AppTheme.darkNavy,
            ),
          ),
        ),
      ),
    );
  }

  /// Request without picking a physio: partner agency physios in the area
  /// get it first, then all physios in the area.
  static const Map<String, dynamic> _anyPhysio = {
    'uid': '',
    'name': 'Any available physio',
    'qualification': 'Physiotherapist',
    'organisation': 'Nearest available',
  };

  void _showBookingDialog(Map<String, dynamic> therapistData,
      {bool anyPhysio = false}) {
    // Mode comes from the Book for Later / Urgent selector on the list screen.
    // Book for later starts from tomorrow; Urgent is always today.
    final bool isUrgent = _isUrgentMode;
    DateTime selectedDate =
        isUrgent ? DateTime.now() : DateTime.now().add(const Duration(days: 1));
    String selectedTime = '10:00 AM';

    final String therapyName = _selectedTherapyName ?? 'Therapy Session';
    final int? price = _getTherapyPrice(therapyName);
    if (price == null ||
        (isUrgent && PricingService.current.urgentSurchargePct == null)) {
      return _priceNotSet();
    }
    final int basePrice = price;

    bool isAvailable = true;
    bool checkingSchedule = false;
    List<String> availableSlots = [
      '09:00 AM',
      '11:00 AM',
      '02:00 PM',
      '04:00 PM',
      '06:00 PM'
    ];
    List<String> disabledSlots = [];
    bool hasInitializedSchedule = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final int urgentSurcharge =
                isUrgent ? (basePrice * _kUrgentSurchargeRate).round() : 0;
            final bool hasValidSlot = availableSlots.any((t) =>
                !disabledSlots.contains(t.trim().toUpperCase()) &&
                !_isTimeSlotInPast(selectedDate, t));
            final int calculatedTotalPrice = basePrice + urgentSurcharge;

            Future<void> checkTherapistSchedule(DateTime date) async {
              setModalState(() => checkingSchedule = true);

              final doctorUid = therapistData['uid'] ?? '';
              final dateKey = _formatDateKey(date);
              final dateStr = _formatDateStandard(date);

              // No physio picked yet: only the patient's own bookings matter
              final scheduleData = anyPhysio
                  ? null
                  : await FirestoreService.getDoctorDateSchedule(
                      doctorUid: doctorUid,
                      dateKey: dateKey,
                    );

              final doctorBookedSlots = anyPhysio
                  ? const <String>[]
                  : await FirestoreService.getDoctorBookedTimeSlots(
                      doctorUid: doctorUid,
                      date: dateStr,
                    );

              final patientBookedSlots =
                  await FirestoreService.getPatientBookedTimeSlots(
                patientUid: widget.patient.uid,
                date: dateStr,
              );

              disabledSlots = {...doctorBookedSlots, ...patientBookedSlots}
                  .map((s) => s.trim().toUpperCase())
                  .toList();

              if (scheduleData != null) {
                final bool avail = scheduleData['isAvailable'] ?? true;
                final List<dynamic> slots = scheduleData['timeSlots'] ?? [];

                setModalState(() {
                  isAvailable = avail;
                  if (avail && slots.isNotEmpty) {
                    availableSlots = List<String>.from(slots);
                    if (!availableSlots.contains(selectedTime) ||
                        disabledSlots
                            .contains(selectedTime.trim().toUpperCase()) ||
                        _isTimeSlotInPast(date, selectedTime)) {
                      final validFirst = availableSlots.firstWhere(
                        (s) =>
                            !disabledSlots.contains(s.trim().toUpperCase()) &&
                            !_isTimeSlotInPast(date, s),
                        orElse: () => availableSlots.first,
                      );
                      selectedTime = validFirst;
                    }
                  } else if (!avail) {
                    availableSlots = [];
                  }
                  checkingSchedule = false;
                });
              } else {
                setModalState(() {
                  isAvailable = true;
                  availableSlots = [
                    '09:00 AM',
                    '11:00 AM',
                    '02:00 PM',
                    '04:00 PM',
                    '06:00 PM'
                  ];
                  if (disabledSlots
                          .contains(selectedTime.trim().toUpperCase()) ||
                      _isTimeSlotInPast(date, selectedTime)) {
                    final validFirst = availableSlots.firstWhere(
                      (s) =>
                          !disabledSlots.contains(s.trim().toUpperCase()) &&
                          !_isTimeSlotInPast(date, s),
                      orElse: () => availableSlots.first,
                    );
                    selectedTime = validFirst;
                  }
                  checkingSchedule = false;
                });
              }
            }

            if (!hasInitializedSchedule) {
              hasInitializedSchedule = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                checkTherapistSchedule(selectedDate);
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                  child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Request Therapy Session',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 10),

                  // Summary
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor:
                            AppColors.primary.withValues(alpha: 0.15),
                        child: const Icon(Icons.self_improvement_rounded,
                            color: AppColors.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              therapistData['name'] ?? 'Therapist',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              '${therapistData['qualification'] ?? 'Certified Therapist'} • ${therapistData['organisation'] ?? 'Care Provider'}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          '₹$calculatedTotalPrice',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    ],
                  ),

                  const SizedBox(height: 18),

                  // Strictly Home Visit Only Notice
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.pastelBlue,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.home_work_rounded,
                            color: AppColors.primary, size: 22),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Home Visit Therapy: The therapist will arrive at your location for a 45-60 min session.',
                            style: TextStyle(
                              color: AppColors.primaryDark,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Selected booking mode (chosen on the list screen)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color:
                          isUrgent ? AppColors.orangeTint : AppTheme.pastelBlue,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isUrgent
                              ? Icons.bolt_rounded
                              : Icons.event_available_rounded,
                          color:
                              isUrgent ? AppColors.orange : AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isUrgent
                                ? 'Urgent (Today) · ₹$basePrice + ${(_kUrgentSurchargeRate * 100).round()}% urgent charge'
                                : 'Book for Later · ₹$basePrice',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isUrgent
                                  ? AppColors.orange
                                  : AppColors.primaryDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Date Picker Row (Urgent is fixed to today)
                  Text(
                      isUrgent
                          ? 'Session Date (Today)'
                          : 'Select Date for Session',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: isUrgent
                        ? null
                        : () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate:
                                  DateTime.now().add(const Duration(days: 1)),
                              lastDate:
                                  DateTime.now().add(const Duration(days: 60)),
                            );
                            if (picked != null) {
                              setModalState(() => selectedDate = picked);
                              await checkTherapistSchedule(picked);
                            }
                          },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isUrgent ? AppTheme.bgLight : null,
                        border: Border.all(color: AppColors.lineStrong),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today,
                              color: AppColors.primary, size: 18),
                          const SizedBox(width: 10),
                          Text(
                            '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          if (!isUrgent)
                            const Icon(Icons.arrow_drop_down,
                                color: AppColors.muted),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Time Slots Selection
                  const Text('Select Time Slot',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),

                  if (checkingSchedule)
                    const Padding(
                      padding: EdgeInsets.all(12.0),
                      child: Row(
                        children: [
                          SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                              )),
                          SizedBox(width: 10),
                          Text('Checking therapist schedule...'),
                        ],
                      ),
                    )
                  else if (!isAvailable || availableSlots.isEmpty)
                    const Text(
                      'No available time slots for this date.',
                      style: TextStyle(color: AppColors.muted, fontSize: 13),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: availableSlots.map((time) {
                        final isSelected = selectedTime == time;
                        final isBooked =
                            disabledSlots.contains(time.trim().toUpperCase());
                        final isPast = _isTimeSlotInPast(selectedDate, time);
                        final isUnavailable = isBooked || isPast;

                        return ChoiceChip(
                          label: Text(
                            isBooked
                                ? '$time (Booked)'
                                : isPast
                                    ? '$time (Past)'
                                    : time,
                          ),
                          selected: isSelected && !isUnavailable,
                          selectedColor: AppColors.primary,
                          disabledColor: AppColors.line,
                          labelStyle: TextStyle(
                            color: isUnavailable
                                ? AppColors.muted
                                : isSelected
                                    ? Colors.white
                                    : AppTheme.darkNavy,
                            fontWeight: FontWeight.bold,
                          ),
                          onSelected: isUnavailable
                              ? null
                              : (val) {
                                  if (val) {
                                    setModalState(() => selectedTime = time);
                                  }
                                },
                        );
                      }).toList(),
                    ),

                  // a request must always be for a slot that is still free and in the future
                  if (!checkingSchedule &&
                      isAvailable &&
                      availableSlots.isNotEmpty &&
                      !hasValidSlot)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        isUrgent
                            ? 'No available time slots are remaining for today. Please select another date.'
                            : 'No available time slots for this date. Please select another date.',
                        style: const TextStyle(
                            color: AppColors.danger, fontSize: 12.5),
                      ),
                    ),

                  const SizedBox(height: 24),

                  // Confirm Button
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brand,
                    ),
                    onPressed: (!isAvailable ||
                            availableSlots.isEmpty ||
                            !hasValidSlot ||
                            checkingSchedule ||
                            disabledSlots
                                .contains(selectedTime.trim().toUpperCase()) ||
                            _isTimeSlotInPast(selectedDate, selectedTime))
                        ? null
                        : () => _handleBookingConfirmation(
                              therapistData: therapistData,
                              selectedDate: selectedDate,
                              selectedTime: selectedTime,
                              basePrice: basePrice,
                              urgentSurcharge: urgentSurcharge,
                              isUrgent: isUrgent,
                              totalPrice: calculatedTotalPrice,
                              bottomSheetContext: ctx,
                              anyPhysio: anyPhysio,
                            ),
                    child: Text(
                      isUrgent
                          ? 'Request Urgent Visit (₹$calculatedTotalPrice)'
                          : 'Request Home Visit (₹$calculatedTotalPrice)',
                    ),
                  ),
                ],
              )),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveCenter(
        child: PopScope(
            // Back from a therapy's therapist list returns to the therapy list
            canPop: _selectedTherapyName == null ||
                widget.initialTherapyName != null,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) setState(() => _selectedTherapyName = null);
            },
            child: Scaffold(
              backgroundColor: AppTheme.bgLight,
              body: SafeArea(
                child: _selectedTherapyName == null
                    ? _buildCategorySelectionGrid()
                    : Column(
                        children: [
                          AppBar(
                            leading: BackButton(
                              onPressed: () {
                                if (widget.initialTherapyName != null) {
                                  Navigator.of(context).maybePop();
                                } else {
                                  setState(() => _selectedTherapyName = null);
                                }
                              },
                            ),
                            title: Text('Therapy: $_selectedTherapyName'),
                          ),
                          Expanded(child: _buildTherapistListForCategory()),
                        ],
                      ),
              ),
            )));
  }

  /// Step 1: Select Therapy Category
  Widget _buildCategorySelectionGrid() {
    if (_loadingTherapies) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: AppTheme.darkNavy,
              size: 26,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Find a Therapist',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppTheme.darkNavy,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Select the type of therapy you need for a home visit session.',
            style: TextStyle(
              fontSize: 15,
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),

          // Top Hero Banner (same layout as technician booking)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _liveAreaName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Home Therapy Sessions',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Certified therapists visit your home for 45-60 min sessions.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: MasterImage(
                    imageKey: ImagesMaster.banner('therapies'),
                    height: 85,
                    width: 85,
                    fit: BoxFit.cover,
                    placeholder: const Icon(
                      Icons.self_improvement_rounded,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Mode selector: Book for Later (from tomorrow) or Today (urgent)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.lineStrong),
            ),
            child: Row(
              children: [
                _buildModeTab(0, 'Book for Later'),
                _buildModeTab(1, 'Today (Urgent)'),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Mode Details Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _isUrgentMode ? AppColors.orangeTint : AppTheme.pastelBlue,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isUrgentMode
                    ? AppColors.warningBorder
                    : AppColors.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _isUrgentMode
                      ? Icons.directions_run_rounded
                      : Icons.calendar_month_rounded,
                  color: _isUrgentMode ? AppColors.warning : AppColors.primary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _isUrgentMode
                        ? 'Urgent Same-Day Therapy: therapist visits you today. Prices below include the ${(_kUrgentSurchargeRate * 100).round()}% urgent charge.'
                        : 'Book for Later: choose any date from tomorrow and a time slot from the therapist\'s schedule.',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.darkNavy,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          if (_therapiesWithPrice.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.line),
              ),
              child: const Text(
                'No therapy services are available right now. Please check back soon.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
              ),
            ),

          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _therapiesWithPrice.length,
            // columns from the screen width; tile tall enough for a
            // two-line name at any font size
            gridDelegate:
                Responsive.grid(context, minTileWidth: 150, tileHeight: 236),
            itemBuilder: (context, index) {
              final therapyMap = _therapiesWithPrice[index];
              final String name = therapyMap['name'] ?? '';
              // the list only holds therapies that have a price
              final int basePrice = (therapyMap['price'] as num).toInt();
              final int price = _isUrgentMode
                  ? basePrice + (basePrice * _kUrgentSurchargeRate).round()
                  : basePrice;

              return GestureDetector(
                onTap: () {
                  setState(() => _selectedTherapyName = name);
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: AppColors.line),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                      )
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircleImage(
                        imageKey: ImagesMaster.therapy(name),
                        size: 96,
                        icon: Icons.self_improvement_rounded,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: AppTheme.darkNavy,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.pastelBlue,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '₹$price',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Step 2: Show Available Therapists
  Widget _buildTherapistListForCategory() {
    final int? therapyPrice = _selectedTherapyName != null
        ? _getTherapyPrice(_selectedTherapyName!)
        : null;
    if (!_loadingTherapies && therapyPrice == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child:
              Text(PricingService.notSetMessage, textAlign: TextAlign.center),
        ),
      );
    }
    final int baseCategoryPrice = therapyPrice ?? 0;
    final int urgentCategoryPrice =
        baseCategoryPrice + (baseCategoryPrice * _kUrgentSurchargeRate).round();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.white,
          child: Row(
            children: [
              Flexible(
                child: Chip(
                  backgroundColor: AppColors.primary,
                  label: Text(
                    _isUrgentMode
                        ? '$_selectedTherapyName · Urgent (₹$urgentCategoryPrice)'
                        : '$_selectedTherapyName (₹$baseCategoryPrice)',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  deleteIcon:
                      const Icon(Icons.close, color: Colors.white, size: 18),
                  onDeleted: () {
                    setState(() => _selectedTherapyName = null);
                  },
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.near_me_rounded,
                  color: AppColors.primary, size: 16),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Text(
                  _liveAreaName.split(',').first,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: OutlinedButton.icon(
            onPressed: () => _showBookingDialog(_anyPhysio, anyPhysio: true),
            icon: const Icon(Icons.cell_tower_rounded, size: 18),
            label: const Text('Book any available physio'),
            style: OutlinedButton.styleFrom(
              iconColor: AppColors.brand,
              foregroundColor: AppColors.brand,
              side: const BorderSide(color: AppColors.brand),
              minimumSize: const Size(double.infinity, 44),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _streams.get(
                'providers', () => FirestoreService.getTherapistsStream()),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return LoadErrorView(error: snapshot.error, what: 'therapists');
              }
              if (snapshot.connectionState == ConnectionState.waiting ||
                  _loadingPosition) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                );
              }

              final allTherapists = snapshot.data ?? [];
              final List<Map<String, dynamic>> nearbyTherapists = [];

              for (var therapist in allTherapists) {
                // STRICT ADMIN VERIFICATION GATE:
                if (therapist['isVerified'] != true) continue;
                // Blocked for 15 days after 3 absents in a month
                if (FirestoreService.isProviderBlocked(therapist)) continue;

                // Therapist switched to Offline / turned off home visits
                if (therapist['isOnline'] == false ||
                    therapist['workMode'] == 'offline' ||
                    therapist['homeVisitsEnabled'] == false) {
                  continue;
                }

                // 1. FILTER BY THERAPY CATEGORY
                final List<dynamic> offered = (therapist['offeredTherapies'] ??
                        therapist['specialties']) as List<dynamic>? ??
                    [];
                if (!FirestoreService.therapistOffersTherapy(
                    offered, _selectedTherapyName)) {
                  continue;
                }

                // 2. FILTER BY LOCATION
                final List<dynamic> prefLocs =
                    therapist['preferredLocations'] as List<dynamic>? ?? [];

                // Strict area rule: a provider who chose service areas only appears
                // for patients inside those areas (Baner/Balewadi never sees Katraj).
                // A provider without areas appears only if their real shared
                // location is close by.
                final bool hasRealLocation = therapist['latitude'] is num &&
                    therapist['longitude'] is num;
                final bool servesArea = prefLocs.isNotEmpty &&
                    FirestoreService.providerServesArea(
                        prefLocs, _liveAreaName);

                double therapistLat = toNum(therapist['latitude'])
                        ?.toDouble() ??
                    (_patientPosition?.latitude ?? LocationService.defaultLat) +
                        0.02;
                double therapistLng =
                    toNum(therapist['longitude'])?.toDouble() ??
                        (_patientPosition?.longitude ??
                                LocationService.defaultLng) +
                            0.015;

                double distanceInMeters = Geolocator.distanceBetween(
                  _patientPosition?.latitude ?? LocationService.defaultLat,
                  _patientPosition?.longitude ?? LocationService.defaultLng,
                  therapistLat,
                  therapistLng,
                );

                double distanceInKm = distanceInMeters / 1000.0;

                if (servesArea ||
                    (prefLocs.isEmpty &&
                        hasRealLocation &&
                        distanceInKm <= 15.0)) {
                  therapist['calculatedDistanceKm'] = distanceInKm;
                  therapist['servesPatientArea'] = servesArea;
                  nearbyTherapists.add(therapist);
                }
              }

              // Sort
              nearbyTherapists.sort((a, b) {
                final bool sA = a['servesPatientArea'] == true;
                final bool sB = b['servesPatientArea'] == true;
                if (sA && !sB) return -1;
                if (!sA && sB) return 1;

                final dA = (a['calculatedDistanceKm'] as double?) ?? 0;
                final dB = (b['calculatedDistanceKm'] as double?) ?? 0;
                return dA.compareTo(dB);
              });

              if (nearbyTherapists.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.location_off_rounded,
                            size: 60, color: AppColors.muted),
                        const SizedBox(height: 16),
                        Text(
                          'No available therapists found for $_selectedTherapyName in $_liveAreaName.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            color: AppTheme.textMuted,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: nearbyTherapists.length,
                itemBuilder: (context, index) {
                  final therapist = nearbyTherapists[index];
                  final dist =
                      (therapist['calculatedDistanceKm'] as double?) ?? 2.5;
                  final rating = FirestoreService.ratingLabel(therapist);
                  final bool isOnline = therapist['isOnline'] ?? true;
                  final bool servesArea =
                      therapist['servesPatientArea'] == true;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: servesArea
                          ? Border.all(color: AppColors.primary, width: 2)
                          : null,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (servesArea)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: AppTheme.pastelBlue,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_circle_rounded,
                                    color: AppColors.primary, size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  'SERVES YOUR AREA (${_liveAreaName.split(',').first.toUpperCase()})',
                                  style: const TextStyle(
                                    color: AppColors.primaryDark,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Row(
                          children: [
                            ProviderAvatar(
                              photoUrl: therapist['profilePicUrl']?.toString(),
                              roleKey: ImagesMaster.service('Therapist'),
                              icon: Icons.person_rounded,
                              size: 72,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          therapist['name'] ?? 'Therapist',
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.darkNavy,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.warningTint,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '★ $rating',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.darkNavy,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  const SizedBox(height: 4),
                                  const VerifiedBadge(),
                                  Text(
                                    '${therapist['qualification'] ?? 'Certified Therapist'} • ${therapist['organisation'] ?? 'MyDox Care'}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.pastelBlue,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.near_me_rounded,
                                                size: 12,
                                                color: AppColors.primary),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${dist.toStringAsFixed(1)} km away',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.primaryDark,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      if (!isOnline)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.dangerSoft,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: const Text(
                                            'NOT AVAILABLE',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.danger,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        ElevatedButton(
                          onPressed: () {
                            if (!isOnline) {
                              // Offline: send the request to nearby physios
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      '${therapist['name']} is currently Offline. Your request will go to nearby physios.'),
                                  backgroundColor: AppColors.orange,
                                ),
                              );
                              _showBookingDialog(_anyPhysio, anyPhysio: true);
                              return;
                            }
                            _showBookingDialog(therapist);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                !isOnline ? AppColors.muted : AppColors.primary,
                            minimumSize: const Size(double.infinity, 44),
                          ),
                          child: Text(
                            !isOnline
                                ? 'Not Available (Offline)'
                                : _isUrgentMode
                                    ? 'Request Urgent Visit (₹$urgentCategoryPrice)'
                                    : 'Book Home Visit (₹$baseCategoryPrice)',
                          ),
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
    );
  }
}
