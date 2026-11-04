import '../../services/app_database.dart';
import '../../config/test_lab_config.dart';
import '../../services/lab_device.dart';
import '../../widgets/verification_gate.dart';
import '../../utils/safe_cast.dart';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/emergency_status_dialog.dart';
import 'my_bookings_screen.dart';
import '../../utils/error_messages.dart';
import '../../utils/stream_cache.dart';
import '../../services/pricing_service.dart';
import '../../utils/responsive.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_strings.dart';
import '../../utils/display_names.dart';
import '../../widgets/app_dialog.dart';
import '../../services/images_master.dart';
import '../../widgets/circle_image.dart';
import '../../widgets/verified_badge.dart';

class BookDoctorScreen extends StatefulWidget {
  final UserModel patient;
  final String? initialCategory;
  final String? initialLocationArea;
  final bool isUrgentEmergency;

  const BookDoctorScreen({
    super.key,
    required this.patient,
    this.initialCategory,
    this.initialLocationArea,
    this.isUrgentEmergency = false,
  });

  @override
  State<BookDoctorScreen> createState() => _BookDoctorScreenState();
}

class _BookDoctorScreenState extends State<BookDoctorScreen> {
  // Live data connections kept open across redraws
  final StreamCache _streams = StreamCache();

  String? _selectedCategory;
  List<Map<String, dynamic>> _categoriesWithPrice = [];
  bool _loadingCategories = true;
  // urgent % and home-visit extra (Firestore app_settings/pricing)
  PricingSettings _pricing = PricingService.current;

  int _selectedModeIndex =
      0; // 0 = Book for Later (Scheduled), 1 = Urgent Doctor (Today)

  Position? _patientPosition;
  Map<String, double> _candidateKm =
      {}; // uid -> hospital distance, within 8 km
  late String _selectedAreaName;

  @override
  void initState() {
    super.initState();
    guardVerifiedRequester(context, widget.patient);
    _selectedCategory = widget.initialCategory;
    _selectedAreaName = widget.initialLocationArea ?? 'Wakad';
    if (widget.isUrgentEmergency) {
      _selectedModeIndex = 1;
    }
    _fetchCategories();
    PricingService.load().then((p) {
      if (mounted) setState(() => _pricing = p);
    });
    _fetchPatientPosition();
  }

  Future<void> _fetchCategories() async {
    try {
      final list = await FirestoreService.getDoctorCategoriesWithPrice();
      if (mounted) {
        setState(() {
          _categoriesWithPrice = list;
          _loadingCategories = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _categoriesWithPrice = [];
          _loadingCategories = false;
        });
      }
    }
  }

  bool _locationFailed = false;
  // Radius actually used for the doctor list: 4 km, widening to 6 and 8 km
  // only when nobody is available closer.
  final ValueNotifier<int> _listRadiusKm = ValueNotifier<int>(4);
  // Book for later: the patient picks how far to search (4 / 6 / 8 km)
  int _radiusChoice = 4;

  Future<void> _fetchPatientPosition() async {
    if (mounted) setState(() => _locationFailed = false);
    try {
      var perm = await LabLocation.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await LabLocation.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw Exception('location permission denied');
      }
      final pos = await LabLocation.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (mounted) setState(() => _patientPosition = pos);
    } catch (_) {
      // Never guess a position: doctors are matched on the real live
      // location only (4 / 6 / 8 km rule).
      if (mounted) setState(() => _locationFailed = true);
    }
  }

  String _formatDateStandard(DateTime dt) {
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    return '$day/$month/${dt.year}';
  }

  String _formatDateKey(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  bool _isTimeSlotInPast(DateTime selectedDate, String timeSlotStr) {
    final now = DateTime.now();
    final isToday = selectedDate.year == now.year &&
        selectedDate.month == now.month &&
        selectedDate.day == now.day;

    if (!isToday) return false;

    try {
      final cleaned = timeSlotStr.split('-').first.trim().toUpperCase();
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

  /// The category's price from Firestore (null while it is not set).
  int? _getCategoryPrice(String categoryName) {
    for (final c in _categoriesWithPrice) {
      if ((c['name'] as String).toLowerCase() == categoryName.toLowerCase()) {
        return toNum(c['price'])?.toInt();
      }
    }
    return null;
  }

  void _priceNotSet() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text(PricingService.notSetMessage),
      backgroundColor: AppColors.warning,
    ));
  }

  void _showDoctorBookedPopup(String docName, String time, String date) {
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
              '${DisplayNames.doctor(docName)} is already attending another patient at $time on $date.\n\nPlease choose a different time slot or date for your consultation.',
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
              'You already have another appointment scheduled at $time on $date.\n\nTo prevent overlapping consultations, please select a different time slot.',
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
    required Map<String, dynamic> doctorData,
    required String selectedConsultationType,
    required DateTime selectedDate,
    required String selectedTime,
    required int basePrice,
    required int totalPrice,
    required int offeredExtra,
    required BuildContext bottomSheetContext,
  }) async {
    if (_bookingInFlight) return;
    _bookingInFlight = true;
    try {
      await _handleBookingConfirmationImpl(
          doctorData: doctorData,
          selectedConsultationType: selectedConsultationType,
          selectedDate: selectedDate,
          selectedTime: selectedTime,
          basePrice: basePrice,
          totalPrice: totalPrice,
          offeredExtra: offeredExtra,
          bottomSheetContext: bottomSheetContext);
    } finally {
      _bookingInFlight = false;
    }
  }

  Future<void> _handleBookingConfirmationImpl({
    required Map<String, dynamic> doctorData,
    required String selectedConsultationType,
    required DateTime selectedDate,
    required String selectedTime,
    required int basePrice,
    required int totalPrice,
    required int offeredExtra,
    required BuildContext bottomSheetContext,
  }) async {
    final String dateFormatted = _formatDateStandard(selectedDate);
    final String docName = doctorData['name'] ?? 'Doctor';
    final bool isUrgent = _selectedModeIndex == 1 || widget.isUrgentEmergency;

    // The doctor may have gone offline while the patient was choosing
    try {
      final fresh = (await AppDatabase.instance
              .collection('doctors')
              .doc((doctorData['uid'] ?? '').toString())
              .get())
          .data();
      if (fresh != null && fresh['isOnline'] == false) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${DisplayNames.doctor(docName)} just went offline and cannot take new bookings. Please choose another doctor.'),
          backgroundColor: AppColors.orange,
        ));
        return;
      }
    } catch (_) {}

    if (isUrgent &&
        await FirestoreService.patientHasActiveUrgentBooking(
            widget.patient.uid)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'You already have an urgent booking in progress. Please wait until it is completed before requesting another.'),
        backgroundColor: AppColors.danger,
      ));
      return;
    }

    if (!isUrgent) {
      final doubleCheckDoc = await FirestoreService.getDoctorBookedTimeSlots(
        doctorUid: doctorData['uid'] ?? '',
        date: dateFormatted,
      );

      if (doubleCheckDoc.contains(selectedTime.trim().toUpperCase())) {
        if (!mounted) return;
        _showDoctorBookedPopup(docName, selectedTime, dateFormatted);
        return;
      }

      final doubleCheckPatient =
          await FirestoreService.getPatientBookedTimeSlots(
        patientUid: widget.patient.uid,
        date: dateFormatted,
      );

      if (doubleCheckPatient.contains(selectedTime.trim().toUpperCase())) {
        if (!mounted) return;
        _showPatientBookedPopup(selectedTime, dateFormatted);
        return;
      }
    }

    if (!mounted) return;

    final isHomeVisit = selectedConsultationType == 'Home Visit';
    final doctorLabel = DisplayNames.doctor(docName);
    final bool confirm = await AppDialog.confirm(
      context,
      icon: (isUrgent || isHomeVisit)
          ? Icons.warning_amber_rounded
          : Icons.help_outline_rounded,
      color: (isUrgent || isHomeVisit) ? AppColors.danger : AppColors.primary,
      title: isUrgent
          ? 'Confirm urgent request?'
          : (isHomeVisit ? 'Confirm home visit request?' : 'Confirm booking?'),
      message: isUrgent
          ? 'Send an urgent same-day request to $doctorLabel?'
          : 'Book $doctorLabel on $dateFormatted at $selectedTime ($selectedConsultationType)?',
      content: PriceBreakdown(
        base: basePrice,
        extras: [
          (
            isUrgent ? AppStrings.urgentSurcharge : AppStrings.homeVisitCharge,
            offeredExtra
          ),
        ],
        total: totalPrice,
      ),
    );

    if (!confirm || !mounted) return;

    if (bottomSheetContext.mounted) {
      Navigator.pop(bottomSheetContext);
    }

    if (isUrgent || selectedConsultationType == 'Home Visit') {
      try {
        final docRef = AppDatabase.instance.collection('appointments').doc();
        final appointmentId = docRef.id;
        final otp = (1000 + Random().nextInt(9000)).toString();

        // Free doctors within 8 km (excluding the chosen one) get the request
        // as the search radius widens 4 -> 6 -> 8 km after it is broadcast.
        final busy = isUrgent
            ? await FirestoreService.getBusyEmergencyDoctorUids()
            : <String>{};
        final chosenUid = (doctorData['uid'] ?? '').toString();
        final candidates = <String, double>{
          for (final e in _candidateKm.entries)
            if (e.key.isNotEmpty && e.key != chosenUid && !busy.contains(e.key))
              e.key: e.value
        };
        // Chosen doctor still on another emergency: don't queue it for him,
        // send it to the other free doctors instead.
        final bool rerouted = isUrgent && busy.contains(chosenUid);
        if (rerouted && candidates.isEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'This doctor is on another emergency and no other doctor nearby is free.'),
            backgroundColor: AppColors.danger,
          ));
          return;
        }

        await docRef.set({
          'appointmentId': appointmentId,
          'patientUid': widget.patient.uid,
          'patientName': widget.patient.name,
          'patientPhone': widget.patient.phone ?? '',
          'doctorUid': rerouted ? '' : (doctorData['uid'] ?? ''),
          'doctorName':
              rerouted ? 'Nearby Doctors' : (doctorData['name'] ?? 'Doctor'),
          'doctorCategory': doctorData['category'] ?? 'General Physician',
          'emergencyCategory': doctorData['category'] ?? 'General Physician',
          'hospital': rerouted ? '' : (doctorData['hospital'] ?? ''),
          if (isUrgent && candidates.isNotEmpty)
            'candidateDistancesKm': candidates,
          if (isUrgent) 'autoExpire': true,
          if (rerouted) 'isBroadcast': true,
          if (rerouted) 'broadcastedAt': DateTime.now().toIso8601String(),
          'date': dateFormatted,
          'time': selectedTime,
          'basePrice': basePrice,
          'offeredExtraAmount': offeredExtra,
          'price': totalPrice,
          'locationName': _selectedAreaName,
          // only a real GPS position (never the Pune map centre)
          if (_patientPosition != null)
            'patientLat': _patientPosition!.latitude,
          if (_patientPosition != null)
            'patientLng': _patientPosition!.longitude,
          'patientLocationKnown': _patientPosition != null,
          'consultationType': selectedConsultationType,
          'isUrgentEmergency': isUrgent,
          'status': rerouted
              ? 'Broadcasted'
              : (isUrgent ? 'Pending Emergency' : 'Pending Home Visit'),
          'paymentStatus': 'cash', // doctor collects cash at the visit
          'otp': otp,
          'hasBeenRated': false,
          'declinedBy': [],
          'createdAt': DateTime.now().toIso8601String(),
        });

        if (!mounted) return;

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => EmergencyStatusDialog(
            appointmentId: appointmentId,
            doctorName: doctorData['name'] ?? 'Doctor',
            basePrice: basePrice,
            surcharge: offeredExtra,
            totalPrice: totalPrice,
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
    } else {
      try {
        await FirestoreService.createAppointment(
          patientUid: widget.patient.uid,
          patientName: widget.patient.name,
          patientPhone: widget.patient.phone ?? '',
          doctorUid: doctorData['uid'] ?? '',
          doctorName: doctorData['name'] ?? 'Doctor',
          doctorCategory: doctorData['category'] ?? 'General Physician',
          hospital: doctorData['hospital'] ?? '',
          date: dateFormatted,
          time: selectedTime,
          price: totalPrice,
          consultationType: selectedConsultationType,
          isUrgentEmergency: false,
          offeredExtraAmount: 0,
          locationName: _selectedAreaName,
          patientLat: _patientPosition?.latitude,
          patientLng: _patientPosition?.longitude,
        );

        if (!mounted) return;

        showDialog(
          context: context,
          builder: (_) => BookingSuccessDialog(
            doctorName: doctorData['name'] ?? 'Doctor',
            category: doctorData['category'] ?? 'General Physician',
            date: dateFormatted,
            time: selectedTime,
            consultationType: selectedConsultationType,
            price: totalPrice,
            onViewBookings: () {
              if (!mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MyBookingsScreen(patient: widget.patient),
                ),
              );
            },
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorMessages.of(e, action: 'complete the booking')),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  void _showBookingDialog(Map<String, dynamic> doctorData) {
    final String categoryName =
        doctorData['category'] ?? _selectedCategory ?? 'General Physician';
    final int? price = _getCategoryPrice(categoryName);
    final bool isUrgent = _selectedModeIndex == 1 || widget.isUrgentEmergency;
    final int? urgentExtra =
        price == null ? null : _pricing.urgentSurcharge(price);
    final int? homeVisitExtra = _pricing.doctorHomeVisitExtra;
    if (price == null ||
        (isUrgent && urgentExtra == null) ||
        (!isUrgent && homeVisitExtra == null)) {
      _priceNotSet();
      return;
    }
    final int basePrice = price;
    final int surcharge = isUrgent ? urgentExtra! : 0;

    String selectedConsultationType =
        isUrgent ? 'Urgent Visit' : 'Clinic/Visit';

    DateTime selectedDate = DateTime.now();
    String selectedTime = isUrgent ? 'ASAP (Immediate)' : '10:00 AM - 11:00 AM';

    double extraIncentiveOffer = (homeVisitExtra ?? 0).toDouble();

    bool isDoctorAvailable = true;
    bool checkingSchedule = false;
    List<String> availableSlots = [
      '09:00 AM - 10:00 AM',
      '10:00 AM - 11:00 AM',
      '11:00 AM - 12:00 PM',
      '02:00 PM - 03:00 PM',
      '04:00 PM - 05:00 PM'
    ];
    List<String> disabledSlots = [];
    bool hasInitializedSchedule = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      // stays below the status bar; the content scrolls when it is taller
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final int currentOffer = extraIncentiveOffer.round();
            final int calculatedTotalPrice = basePrice +
                (isUrgent
                    ? surcharge
                    : (selectedConsultationType == 'Home Visit'
                        ? currentOffer
                        : 0));

            Future<void> checkDoctorSchedule(DateTime date) async {
              setModalState(() => checkingSchedule = true);

              final doctorUid = doctorData['uid'] ?? '';
              final dateKey = _formatDateKey(date);
              final dateStr = _formatDateStandard(date);

              final scheduleData = await FirestoreService.getDoctorDateSchedule(
                doctorUid: doctorUid,
                dateKey: dateKey,
              );

              final doctorBookedSlots =
                  await FirestoreService.getDoctorBookedTimeSlots(
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
                  isDoctorAvailable = avail;
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
                  isDoctorAvailable = true;
                  availableSlots = [
                    '09:00 AM - 10:00 AM',
                    '10:00 AM - 11:00 AM',
                    '11:00 AM - 12:00 PM',
                    '02:00 PM - 03:00 PM',
                    '04:00 PM - 05:00 PM'
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

            if (!hasInitializedSchedule && !isUrgent) {
              hasInitializedSchedule = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                checkDoctorSchedule(selectedDate);
              });
            }

            // scrolls when the slots, a large font or a small phone make it
            // taller than the screen (the button stays reachable)
            return SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.viewInsetsOf(context).bottom +
                    MediaQuery.viewPaddingOf(context).bottom +
                    24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            if (isUrgent)
                              const Icon(Icons.warning_amber_rounded,
                                  color: AppColors.danger, size: 24),
                            if (isUrgent) const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                isUrgent
                                    ? 'Urgent Doctor Consultation'
                                    : 'Book Scheduled Appointment',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: isUrgent
                                      ? AppColors.danger
                                      : AppTheme.textDark,
                                ),
                              ),
                            ),
                          ],
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

                  // Doctor Summary
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: isUrgent
                            ? AppColors.dangerSoft
                            : AppTheme.primaryTeal.withValues(alpha: 0.15),
                        child: Icon(
                          Icons.person,
                          color: isUrgent
                              ? AppColors.danger
                              : AppTheme.primaryTeal,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              doctorData['name'] ?? 'Doctor',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              '${doctorData['category'] ?? ''} • ${doctorData['hospital'] ?? ''}',
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
                          color: isUrgent
                              ? AppColors.dangerSoft
                              : AppTheme.primaryTeal.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          '₹$calculatedTotalPrice',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isUrgent
                                ? AppColors.danger
                                : AppTheme.primaryTeal,
                          ),
                        ),
                      )
                    ],
                  ),

                  const SizedBox(height: 18),

                  if (!isUrgent) ...[
                    const Text(
                      'Select Consultation Mode',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 10),

                    Row(
                      children: [
                        _buildConsultationChip(
                          type: 'Clinic/Visit',
                          icon: Icons.local_hospital_outlined,
                          label: 'Clinic Visit',
                          sub: 'Visit Hospital',
                          selectedType: selectedConsultationType,
                          onSelect: (t) =>
                              setModalState(() => selectedConsultationType = t),
                        ),
                        const SizedBox(width: 8),
                        _buildConsultationChip(
                          type: 'Online',
                          icon: Icons.videocam_outlined,
                          label: 'Online',
                          sub: 'Video Call',
                          selectedType: selectedConsultationType,
                          onSelect: (t) =>
                              setModalState(() => selectedConsultationType = t),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Date Picker Row
                    const Text('Select Date',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime.now(),
                          lastDate:
                              DateTime.now().add(const Duration(days: 60)),
                        );
                        if (picked != null) {
                          setModalState(() => selectedDate = picked);
                          await checkDoctorSchedule(picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.lineStrong),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today,
                                color: AppTheme.primaryTeal, size: 18),
                            const SizedBox(width: 10),
                            Text(
                              '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const Spacer(),
                            const Icon(Icons.arrow_drop_down,
                                color: AppColors.muted),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    if (!isDoctorAvailable)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppColors.dangerSoft,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.danger),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.event_busy_rounded,
                                color: AppColors.danger, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${doctorData['name'] ?? 'Doctor'} is marked BUSY on this date. Please pick another date.',
                                style: const TextStyle(
                                  color: AppColors.danger,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

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
                                  color: AppTheme.primaryTeal,
                                )),
                            SizedBox(width: 10),
                            Text('Checking doctor schedule...'),
                          ],
                        ),
                      )
                    else if (!isDoctorAvailable || availableSlots.isEmpty)
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
                            selectedColor: AppTheme.primaryTeal,
                            disabledColor: AppColors.line,
                            labelStyle: TextStyle(
                              color: isUnavailable
                                  ? AppColors.muted
                                  : isSelected
                                      ? Colors.white
                                      : AppTheme.textDark,
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
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.dangerSoft,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.danger),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.directions_run_rounded,
                              color: AppColors.danger, size: 22),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Urgent Same-Day Request: Sends immediate alert to doctor with patient GPS location (+20% Emergency Surcharge).',
                              style: TextStyle(
                                color: AppColors.danger,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isUrgent ? AppColors.danger : AppTheme.primaryTeal,
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    onPressed: (!isUrgent &&
                            (!isDoctorAvailable || availableSlots.isEmpty))
                        ? null
                        : () => _handleBookingConfirmation(
                              doctorData: doctorData,
                              selectedConsultationType:
                                  selectedConsultationType,
                              selectedDate: selectedDate,
                              selectedTime: selectedTime,
                              basePrice: basePrice,
                              totalPrice: calculatedTotalPrice,
                              offeredExtra: isUrgent
                                  ? surcharge
                                  : (selectedConsultationType == 'Home Visit'
                                      ? currentOffer
                                      : 0),
                              bottomSheetContext: ctx,
                            ),
                    child: Text(
                      isUrgent
                          ? 'Send Urgent Request (₹$calculatedTotalPrice)'
                          : 'Confirm Booking (₹$calculatedTotalPrice)',
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildConsultationChip({
    required String type,
    required IconData icon,
    required String label,
    required String sub,
    required String selectedType,
    required Function(String) onSelect,
  }) {
    final isSelected = selectedType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => onSelect(type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryTeal : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? AppTheme.primaryTeal : AppColors.lineStrong,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: isSelected ? Colors.white : AppTheme.primaryTeal,
                  size: 22),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                sub,
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected ? Colors.white70 : AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeTab(int index, String label) {
    final isSelected = _selectedModeIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedModeIndex = index;
            if (index == 1) {
              _selectedCategory = null;
            }
          });
        },
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

  @override
  Widget build(BuildContext context) {
    final bool isUrgentMode =
        _selectedModeIndex == 1 || widget.isUrgentEmergency;

    return ResponsiveCenter(
        child: PopScope(
            // Back from a category's doctor list returns to "Find Doctor Specialist"
            canPop: _selectedCategory == null || widget.initialCategory != null,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) setState(() => _selectedCategory = null);
            },
            child: Scaffold(
              backgroundColor: AppTheme.bgLight,
              body: SafeArea(
                child: _selectedCategory == null
                    ? _buildCategorySelectionGrid()
                    : Column(
                        children: [
                          AppBar(
                            leading: BackButton(
                              onPressed: () {
                                if (widget.initialCategory != null) {
                                  Navigator.of(context).maybePop();
                                } else {
                                  setState(() => _selectedCategory = null);
                                }
                              },
                            ),
                            title: Text(
                              _categoryPageTitle(
                                  _selectedCategory!, isUrgentMode),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 18),
                            ),
                          ),
                          Expanded(child: _buildDoctorListForCategory()),
                        ],
                      ),
              ),
            )));
  }

  /// "Bones & Joints - Orthopedic" -> "Orthopedic Doctors" (no internal labels)
  static String _categoryPageTitle(String category, bool urgent) {
    final i = category.lastIndexOf(' - ');
    final name = (i >= 0 ? category.substring(i + 3) : category).trim();
    final label = name.toLowerCase().endsWith('s') ? name : '$name Doctors';
    return urgent ? 'Urgent $label' : label;
  }

  /// Step 1: Select Category with Price display
  Widget _buildCategorySelectionGrid() {
    if (_loadingCategories) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryTeal),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back Arrow
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
            'Find a Doctor Specialist',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppTheme.darkNavy,
              letterSpacing: -0.5,
            ),
          ),

          const SizedBox(height: 4),

          const Text(
            'Choose a specialist for a scheduled or same-day urgent visit.',
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(height: 14),

          // Top Mode Selector Bar (Book for Later vs Urgent Today)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.lineStrong),
            ),
            child: Row(
              children: [
                _buildModeTab(0, 'Book for Later (Scheduled)'),
                _buildModeTab(1, 'Urgent Doctor (Today)'),
              ],
            ),
          ),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.location_on_rounded,
                    color: AppColors.primary, size: 16),
                const SizedBox(width: 6),
                Text(
                  'Selected Area: $_selectedAreaName',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Specialty Categories Grid
          Expanded(
            child: GridView.builder(
              itemCount: _categoriesWithPrice.length,
              // columns from the screen width; tile tall enough for a
              // two-line name at any font size
              gridDelegate:
                  Responsive.grid(context, minTileWidth: 150, tileHeight: 236),
              itemBuilder: (context, index) {
                final catMap = _categoriesWithPrice[index];
                final String catName = catMap['name'] ?? '';
                final int? price = toNum(catMap['price'])?.toInt();

                return GestureDetector(
                  onTap: () {
                    if (price == null) return _priceNotSet();
                    setState(() => _selectedCategory = catName);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
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
                          imageKey: ImagesMaster.specialty(catName),
                          size: 96,
                          icon: _specialtyIcon(catName),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          catName,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primaryTint,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            price == null ? 'Price not set' : '₹$price',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryTeal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Icon for a speciality that has no matching photo.
  IconData _specialtyIcon(String catName) {
    final lower = catName.toLowerCase();
    bool has(List<String> words) => words.any(lower.contains);
    if (has(['cardio', 'heart'])) return Icons.monitor_heart_outlined;
    if (has(['neuro', 'brain'])) return Icons.psychology_outlined;
    if (has(['psych', 'mental'])) return Icons.self_improvement_rounded;
    if (has(['ent', 'ear', 'nose', 'throat'])) return Icons.hearing_rounded;
    if (has(['eye', 'ophthal'])) return Icons.visibility_outlined;
    if (has(['dent', 'tooth'])) return Icons.sentiment_satisfied_alt_outlined;
    if (has(['lung', 'pulmo', 'chest', 'respir'])) return Icons.air_rounded;
    if (has(['kidney', 'nephro', 'uro'])) return Icons.water_drop_outlined;
    if (has(['gastro', 'liver', 'stomach'])) return Icons.lunch_dining_outlined;
    if (has(['onco', 'cancer'])) return Icons.healing_outlined;
    if (has(['surg'])) return Icons.content_cut_rounded;
    return Icons.medical_services_outlined;
  }

  /// Urgent request sent to every verified doctor whose hospital is within 4 km.
  Future<void> _broadcastUrgentToNearby(
    List<Map<String, dynamic>> nearbyDoctors,
    int basePrice,
    int surcharge,
  ) async {
    if (await FirestoreService.patientHasActiveUrgentBooking(
        widget.patient.uid)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'You already have an urgent booking in progress. Please wait until it is completed before requesting another.'),
        backgroundColor: AppColors.danger,
      ));
      return;
    }
    final busy = await FirestoreService.getBusyEmergencyDoctorUids();
    final candidates = <String, double>{
      for (final e in _candidateKm.entries)
        if (e.key.isNotEmpty && !busy.contains(e.key)) e.key: e.value
    };
    final targetUids = candidates.entries
        .where((e) => e.value <= 4.0)
        .map((e) => e.key)
        .toList();
    if (!mounted) return;
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No free doctor found nearby right now.'),
        backgroundColor: AppColors.danger,
      ));
      return;
    }

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Broadcast Urgent Request?'),
        content: Text('Send your urgent request to all ${targetUids.length} '
            '$_selectedCategory doctor${targetUids.length == 1 ? '' : 's'} nearby? The first doctor to accept will be assigned.\n\nTotal: ₹${basePrice + surcharge}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Broadcast')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      final docRef = AppDatabase.instance.collection('appointments').doc();
      final now = DateTime.now();
      await docRef.set({
        'appointmentId': docRef.id,
        'patientUid': widget.patient.uid,
        'patientName': widget.patient.name,
        'patientPhone': widget.patient.phone ?? '',
        'doctorUid': '',
        'doctorName': 'Nearby Doctors',
        'doctorCategory': _selectedCategory ?? 'General Physician',
        'emergencyCategory': _selectedCategory ?? 'General Physician',
        'candidateDistancesKm': candidates,
        'isBroadcast': true,
        'autoExpire': true,
        'broadcastedAt': now.toIso8601String(),
        'hospital': '',
        'date': _formatDateStandard(now),
        'time': TimeOfDay.fromDateTime(now).format(context),
        'basePrice': basePrice,
        'offeredExtraAmount': surcharge,
        'price': basePrice + surcharge,
        'locationName': _selectedAreaName,
        // only a real GPS position (never the Pune map centre)
        if (_patientPosition != null) 'patientLat': _patientPosition!.latitude,
        if (_patientPosition != null) 'patientLng': _patientPosition!.longitude,
        'patientLocationKnown': _patientPosition != null,
        'consultationType': 'Home Visit',
        'isUrgentEmergency': true,
        'status': 'Broadcasted',
        'paymentStatus': 'cash', // doctor collects cash at the visit
        'otp': (1000 + Random().nextInt(9000)).toString(),
        'hasBeenRated': false,
        'declinedBy': [],
        'createdAt': now.toIso8601String(),
      });
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => EmergencyStatusDialog(
          appointmentId: docRef.id,
          doctorName: 'Nearby Doctors',
          basePrice: basePrice,
          surcharge: surcharge,
          totalPrice: basePrice + surcharge,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(ErrorMessages.of(e,
                action: 'send the request to nearby doctors')),
            backgroundColor: AppColors.danger),
      );
    }
  }

  /// Step 2: Show Available Doctors in selected area
  Widget _buildDoctorListForCategory() {
    final bool isUrgentMode =
        _selectedModeIndex == 1 || widget.isUrgentEmergency;
    final int? categoryPrice = _selectedCategory != null
        ? _getCategoryPrice(_selectedCategory!)
        : null;
    final int? urgentExtra =
        categoryPrice == null ? null : _pricing.urgentSurcharge(categoryPrice);
    if (!_loadingCategories &&
        (categoryPrice == null || (isUrgentMode && urgentExtra == null))) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child:
              Text(PricingService.notSetMessage, textAlign: TextAlign.center),
        ),
      );
    }
    final int baseCategoryPrice = categoryPrice ?? 0;
    final int surcharge = isUrgentMode ? (urgentExtra ?? 0) : 0;
    final int totalCategoryPrice = baseCategoryPrice + surcharge;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.white,
          child: Row(
            children: [
              if (isUrgentMode)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.dangerSoft,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.danger),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: AppColors.danger, size: 16),
                      SizedBox(width: 4),
                      Text(
                        'URGENT DOCTOR (+20% EXTRA)',
                        style: TextStyle(
                            color: AppColors.danger,
                            fontWeight: FontWeight.bold,
                            fontSize: 12),
                      ),
                    ],
                  ),
                )
              else if (_selectedCategory != null)
                Flexible(
                    child: Chip(
                  backgroundColor: AppTheme.primaryTeal,
                  label: Text(
                    '$_selectedCategory (₹$totalCategoryPrice)',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  deleteIcon:
                      const Icon(Icons.close, color: Colors.white, size: 18),
                  onDeleted: () {
                    setState(() => _selectedCategory = null);
                  },
                )),
            ],
          ),
        ),
        // (patients don't see km distances: the search widens on its own)

        const Divider(height: 1),

        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _streams.get('hospitals',
                () => AppDatabase.instance.collection('hospitals').snapshots()),
            builder: (context, hospSnap) {
              // A pending/failed hospital lookup is not evidence that no
              // doctors are nearby: every doctor's distance depends on it.
              if (hospSnap.hasError) {
                return LoadErrorView(
                    error: hospSnap.error, what: 'hospital locations');
              }
              if (!hospSnap.hasData) {
                return const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: AppTheme.primaryTeal),
                      SizedBox(height: 12),
                      Text('Loading nearby hospital locations...'),
                    ],
                  ),
                );
              }
              // hospital name (lowercase) -> (lat, lng) from hospital live location
              final Map<String, (double, double)> hospitalLocations = {};
              for (final h in hospSnap.data?.docs ?? []) {
                final d = h.data();
                final lat = toNum(d['latitude'])?.toDouble();
                final lng = toNum(d['longitude'])?.toDouble();
                final name = (d['name'] ?? d['hospital'] ?? '')
                    .toString()
                    .trim()
                    .toLowerCase();
                if (lat != null && lng != null && name.isNotEmpty) {
                  hospitalLocations[name] = (lat, lng);
                }
              }
              return StreamBuilder<List<Map<String, dynamic>>>(
                stream: _streams.get(
                    'doctors', () => FirestoreService.getDoctorsStream()),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return LoadErrorView(
                        error: snapshot.error, what: 'doctors');
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.primaryTeal),
                    );
                  }

                  final allDocs = snapshot.data ?? [];

                  // The 4 / 6 / 8 km rule needs the patient's real live location
                  if (_patientPosition == null) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: _locationFailed
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.location_off_rounded,
                                      size: 56, color: AppColors.muted),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'We need your live location to find doctors near you. Please turn on location and allow access.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textMuted),
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(
                                    onPressed: _fetchPatientPosition,
                                    icon: const Icon(Icons.my_location_rounded),
                                    label: const Text('Try again'),
                                  ),
                                ],
                              )
                            : const CircularProgressIndicator(
                                color: AppTheme.primaryTeal),
                      ),
                    );
                  }

                  final categoryDocs = _selectedCategory != null
                      ? allDocs.where((d) {
                          final cat =
                              (d['category'] as String?)?.toLowerCase() ?? '';
                          // Blocked for 15 days after 3 absents in a month
                          final bool verified = d['isVerified'] == true &&
                              !FirestoreService.isProviderBlocked(d) &&
                              d['isOnline'] !=
                                  false; // offline doctors are hidden
                          return verified &&
                              cat == _selectedCategory!.toLowerCase();
                        }).toList()
                      : allDocs
                          .where((d) =>
                              d['isVerified'] == true &&
                              !FirestoreService.isProviderBlocked(d) &&
                              d['isOnline'] != false)
                          .toList();

                  final List<Map<String, dynamic>> nearbyDoctors = [];
                  final Map<String, double> candidateKm = {};

                  for (var doc in categoryDocs) {
                    // Distance is measured to the doctor's preferred hospital
                    // (its live location), not the doctor's own position.
                    final hospLoc = hospitalLocations[(doc['hospital'] ?? '')
                        .toString()
                        .trim()
                        .toLowerCase()];
                    // hospital has no live location
                    if (hospLoc == null) continue;

                    double distanceInMeters = Geolocator.distanceBetween(
                      _patientPosition!.latitude,
                      _patientPosition!.longitude,
                      hospLoc.$1,
                      hospLoc.$2,
                    );

                    double distanceInKm = distanceInMeters / 1000.0;

                    // Wider pool (up to 8 km) used when an urgent request widens
                    if (distanceInKm <= 8.0) {
                      candidateKm[(doc['uid'] ?? '').toString()] = distanceInKm;
                    }

                    if (distanceInKm <= 8.0) {
                      doc['calculatedDistanceKm'] = distanceInKm;
                      nearbyDoctors.add(doc);
                    }
                  }

                  // Book for later: exactly the radius the patient chose. Urgent
                  // requests: 4 km first, widening to 6 then 8 km if nobody is closer.
                  int listRadius = _radiusChoice;
                  if (isUrgentMode) {
                    listRadius = 4;
                    if (!nearbyDoctors.any(
                        (d) => (d['calculatedDistanceKm'] as double) <= 4)) {
                      listRadius = nearbyDoctors.any(
                              (d) => (d['calculatedDistanceKm'] as double) <= 6)
                          ? 6
                          : 8;
                    }
                  }
                  nearbyDoctors.removeWhere((d) =>
                      (d['calculatedDistanceKm'] as double) > listRadius);
                  if (_listRadiusKm.value != listRadius) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _listRadiusKm.value = listRadius;
                    });
                  }

                  // Sort nearby doctors: Preferred doctor first, then by rating
                  nearbyDoctors.sort((a, b) {
                    final isPrefA = (widget.patient.preferredDoctorUids !=
                            null &&
                        widget.patient.preferredDoctorUids!.contains(a['uid']));
                    final isPrefB = (widget.patient.preferredDoctorUids !=
                            null &&
                        widget.patient.preferredDoctorUids!.contains(b['uid']));

                    if (isPrefA && !isPrefB) return -1;
                    if (!isPrefA && isPrefB) return 1;

                    final rA = FirestoreService.ratingAverage(a);
                    final rB = FirestoreService.ratingAverage(b);
                    return rB.compareTo(rA);
                  });

                  _candidateKm = candidateKm;

                  if (nearbyDoctors.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.person_off_rounded,
                                size: 60, color: AppColors.muted),
                            const SizedBox(height: 16),
                            Text(
                              isUrgentMode
                                  ? 'No verified emergency doctors found near your live location.'
                                  : 'No verified specialist doctors found for $_selectedCategory near your live location.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16,
                                color: AppTheme.textMuted,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (TestLabConfig.enabled) ...[
                              const SizedBox(height: 12),
                              Text(
                                'TEST directory: ${allDocs.length} doctors; '
                                '${categoryDocs.length} verified category matches; '
                                '${hospSnap.data!.docs.length} hospitals; '
                                '${hospitalLocations.length} positioned; '
                                '${candidateKm.length} within 8 km.\n'
                                'Hospital data: ${hospSnap.data!.metadata.isFromCache ? 'cached' : 'server'}; '
                                'patient: ${_patientPosition!.latitude.toStringAsFixed(4)}, '
                                '${_patientPosition!.longitude.toStringAsFixed(4)}.\n'
                                'Doctor hospital keys: ${categoryDocs.map((d) => (d['hospital'] ?? '').toString().trim().toLowerCase()).join(', ')}.\n'
                                'Hospital keys: ${hospitalLocations.keys.join(', ')}.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                            if (!isUrgentMode && _radiusChoice < 8) ...[
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: () => setState(() =>
                                    _radiusChoice = _radiusChoice == 4 ? 6 : 8),
                                icon: const Icon(Icons.zoom_out_map_rounded),
                                label: Text('Search a wider area'),
                              ),
                            ],
                            if (isUrgentMode) ...[
                              const SizedBox(height: 8),
                              const Text(
                                'You can still send an urgent request. It goes to the nearest doctors first, then further out if nobody accepts. It closes by itself if nobody accepts.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 12, color: AppTheme.textMuted),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.danger,
                                    minimumSize:
                                        const Size(double.infinity, 48)),
                                onPressed: () => _broadcastUrgentToNearby(
                                    nearbyDoctors,
                                    baseCategoryPrice,
                                    surcharge),
                                icon: const Icon(Icons.sensors_rounded),
                                label: const Text('Request Urgent Doctor'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }

                  final String? favDocUid = (_selectedCategory != null &&
                          widget.patient.favoriteDoctors != null)
                      ? widget.patient.favoriteDoctors![_selectedCategory!]
                      : null;
                  final String? favDocName = (_selectedCategory != null &&
                          widget.patient.favoriteDoctorNames != null)
                      ? widget.patient.favoriteDoctorNames![_selectedCategory!]
                      : null;

                  final favDocMap = nearbyDoctors.firstWhere(
                    (d) => d['uid'] == favDocUid,
                    orElse: () => {},
                  );

                  final bool hasFavDoc = favDocMap.isNotEmpty;
                  final bool showHeader = hasFavDoc || isUrgentMode;

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: nearbyDoctors.length + (showHeader ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (showHeader && index == 0) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.warningTint,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                                color: AppColors.warningBright, width: 1.5),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (hasFavDoc) ...[
                                Row(
                                  children: [
                                    const Icon(Icons.star_rounded,
                                        color: AppColors.warningBright,
                                        size: 22),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Favorite $_selectedCategory Doctor Option',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: AppTheme.darkNavy),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${DisplayNames.doctor(favDocName)} is set as your favorite doctor for $_selectedCategory.',
                                  style: const TextStyle(
                                      fontSize: 12, color: AppTheme.textMuted),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.brand,
                                      minimumSize: const Size(0, 40),
                                    ),
                                    onPressed: () =>
                                        _showBookingDialog(favDocMap),
                                    icon: const Icon(
                                        Icons.person_pin_circle_rounded,
                                        size: 16),
                                    label: Text(
                                        'Request ${DisplayNames.doctor(favDocName)} First'),
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                              if (isUrgentMode)
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                          color: AppTheme.primaryTeal),
                                      minimumSize: const Size(0, 40),
                                    ),
                                    onPressed: () => _broadcastUrgentToNearby(
                                        nearbyDoctors,
                                        baseCategoryPrice,
                                        surcharge),
                                    icon: const Icon(Icons.sensors_rounded,
                                        size: 16),
                                    label: Text(
                                        'Send to all ${DisplayNames.count(nearbyDoctors.length, 'nearby doctor')}'),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }

                      final int docIndex = showHeader ? index - 1 : index;
                      final doc = nearbyDoctors[docIndex];
                      final docRating = FirestoreService.ratingLabel(doc);
                      final isPreferred =
                          (widget.patient.preferredDoctorUids != null &&
                              widget.patient.preferredDoctorUids!
                                  .contains(doc['uid']));
                      final bool isOnline = doc['isOnline'] ?? true;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: isPreferred
                              ? Border.all(
                                  color: AppColors.warningBright, width: 2)
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
                            if (isPreferred)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: AppColors.warningTint,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.star_rounded,
                                        color: AppColors.warningBright,
                                        size: 16),
                                    SizedBox(width: 4),
                                    Text(
                                      'PREFERRED DOCTOR',
                                      style: TextStyle(
                                        color: AppColors.warningBright,
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
                                  photoUrl: doc['profilePicUrl']?.toString(),
                                  roleKey: ImagesMaster.service('Doctors'),
                                  icon: Icons.person_rounded,
                                  size: 72,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            doc['name'] ?? 'Doctor Name',
                                            style: const TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.darkNavy,
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
                                              '★ $docRating',
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
                                        '${doc['category'] ?? ''} • ${doc['hospital'] ?? ''}',
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
                                              color: AppTheme.primaryTeal
                                                  .withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                    Icons.location_on_rounded,
                                                    size: 12,
                                                    color:
                                                        AppTheme.primaryTeal),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Area: ${doc['city'] ?? _selectedAreaName}',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: AppTheme.primaryTeal,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          if (!isOnline)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppColors.dangerSoft,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: const Text(
                                                'OFFLINE',
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
                                if (!isOnline && !isUrgentMode) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          '${DisplayNames.doctor(doc['name'])} is currently Offline. Broadcasting request to available nearby doctors...'),
                                      backgroundColor: AppColors.orange,
                                    ),
                                  );
                                  return;
                                }
                                _showBookingDialog(doc);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isUrgentMode
                                    ? AppColors.danger
                                    : (!isOnline
                                        ? AppColors.muted
                                        : AppTheme.primaryTeal),
                                minimumSize: const Size(double.infinity, 44),
                              ),
                              child: Text(
                                isUrgentMode
                                    ? 'Request Urgent Consultation (₹$totalCategoryPrice)'
                                    : (!isOnline
                                        ? 'Doctor Offline'
                                        : 'Book Scheduled Appointment (₹$baseCategoryPrice)'),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
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

class BookingSuccessDialog extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Row(
        children: [
          Icon(Icons.check_circle_rounded, color: AppColors.success, size: 28),
          SizedBox(width: 8),
          Flexible(child: Text('Booking Confirmed!')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              'Your appointment with ${DisplayNames.doctor(doctorName)} ($category) has been scheduled.'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.bgLight,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(child: const Text('Date & Time:')),
                    Flexible(
                        child: Text('$date at $time',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            textAlign: TextAlign.right)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(child: const Text('Type:')),
                    Flexible(
                        child: Text(consultationType,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            textAlign: TextAlign.right)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(child: const Text('Total Fee:')),
                    Flexible(
                        child: Text('₹$price',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryTeal),
                            textAlign: TextAlign.right)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close', style: TextStyle(color: AppColors.muted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand),
          onPressed: () {
            Navigator.pop(context);
            onViewBookings();
          },
          child: const Text('View My Bookings'),
        ),
      ],
    );
  }
}
