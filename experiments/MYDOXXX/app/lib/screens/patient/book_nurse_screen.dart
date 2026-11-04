import '../../services/service_otp.dart';
import '../../services/app_database.dart';
import '../../services/lab_device.dart';
import '../../utils/safe_cast.dart';
import '../../widgets/verification_gate.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../services/pricing_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/nurse_status_dialog.dart';
import '../../utils/error_messages.dart';
import '../../utils/stream_cache.dart';
import '../../utils/responsive.dart';
import '../../constants/app_colors.dart';

import '../../widgets/app_dialog.dart';
import '../../widgets/verified_badge.dart';
import '../../widgets/circle_image.dart';
import '../../services/images_master.dart';
import '../../constants/app_strings.dart';
import '../../utils/display_names.dart';

class BookNurseScreen extends StatefulWidget {
  final UserModel patient;

  const BookNurseScreen({
    super.key,
    required this.patient,
  });

  @override
  State<BookNurseScreen> createState() => _BookNurseScreenState();
}

class _BookNurseScreenState extends State<BookNurseScreen> {
  // Live data connections kept open across redraws
  final StreamCache _streams = StreamCache();

  int _selectedModeIndex =
      0; // 0 = Book for Later (3-7 Days), 1 = Urgent (Today)

  Position? _patientPosition;
  bool _loadingPosition = true;
  String _liveAreaName = 'Nearby Patient Area';

  // "Book for Later" State
  DateTime _startDate = DateTime.now().add(const Duration(days: 1));
  int _durationDays = 3; // Minimum 3 days, maximum 7 days

  @override
  void initState() {
    super.initState();
    guardVerifiedRequester(context, widget.patient);
    _fetchPatientPosition();
    PricingService.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  /// ₹ per nursing day from Firestore app_settings/pricing (null: not set).
  int? get _dailyRate => PricingService.current.nurseDailyRate;

  /// "₹3,000" for [days], or "price not set".
  String _feeLabel(int days) {
    final fee = PricingService.current.nurseFee(days);
    return fee == null ? 'price not set' : '₹$fee';
  }

  void _priceNotSet() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text(PricingService.notSetMessage),
      backgroundColor: AppColors.warning,
    ));
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

  /// Option A: Handle Multi-Day Booking Confirmation (3-7 days at the daily
  /// rate from Firestore)
  // One booking at a time: a second tap on Confirm while the first is still
  // being saved would create a duplicate booking.
  bool _bookingInFlight = false;

  Future<void> _handleMultiDayBookingConfirmation({
    required Map<String, dynamic> nurseData,
    required DateTime startDate,
    required int days,
    required int totalFee,
  }) async {
    if (_bookingInFlight) return;
    _bookingInFlight = true;
    try {
      await _handleMultiDayBookingConfirmationImpl(nurseData: nurseData, startDate: startDate, days: days, totalFee: totalFee);
    } finally {
      _bookingInFlight = false;
    }
  }

  Future<void> _handleMultiDayBookingConfirmationImpl({
    required Map<String, dynamic> nurseData,
    required DateTime startDate,
    required int days,
    required int totalFee,
  }) async {
    final String nurseName = nurseData['name'] ?? 'Nurse';
    final String startStr = _formatDateStandard(startDate);
    final DateTime endDate = startDate.add(Duration(days: days - 1));
    final String endStr = _formatDateStandard(endDate);

    final dayText = DisplayNames.count(days, 'day');
    final bool confirm = await AppDialog.confirm(
      context,
      icon: Icons.calendar_month_rounded,
      title: 'Confirm home nursing?',
      message: days == 1
          ? 'Book nurse $nurseName on $startStr?\n\nWorking hours: 12:00 PM – 06:00 PM.'
          : 'Book nurse $nurseName for $dayText ($startStr to $endStr)?\n\nWorking hours: 12:00 PM – 06:00 PM each day.',
      content: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.page,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          children: [
            DialogInfoRow('Daily rate', '${_feeLabel(1)} / day'),
            DialogInfoRow('Days', dayText),
            const Divider(height: 16),
            DialogInfoRow(AppStrings.totalFee, '₹$totalFee',
                valueColor: AppColors.primary, bold: true),
          ],
        ),
      ),
      confirmLabel: 'Yes, book nurse',
    );

    if (!confirm || !mounted) return;

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
        'doctorUid': nurseData['uid'] ?? '',
        'doctorName': nurseName,
        'doctorCategory': nurseData['qualification'] ?? 'B.Sc Nursing',
        'hospital': nurseData['organisation'] ?? 'City Home Care Nursing',
        'date': startStr,
        'time': '12:00 PM - 06:00 PM Daily',
        'durationDays': days,
        'dailyRate': _dailyRate,
        'basePrice': totalFee,
        'offeredExtraAmount': 0,
        'price': totalFee,
        'locationName': _liveAreaName,
        // only a real GPS position (never the Pune map centre)
        if (_patientPosition != null) 'patientLat': _patientPosition!.latitude,
        if (_patientPosition != null) 'patientLng': _patientPosition!.longitude,
        'patientLocationKnown': _patientPosition != null,
        'consultationType': 'Multi-Day Home Nursing ($days Days)',
        'isUrgentEmergency': false,
        'isNurseRequest': true,
        'roleTarget': 'nurse',
        'status': 'Pending Home Visit',
        'paymentStatus': 'pending', // paid online after a provider accepts
        'otp': otp,
        'hasBeenRated': false,
        'declinedBy': [],
        'createdAt': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => NurseStatusDialog(
          appointmentId: appointmentId,
          nurseName: nurseName,
          basePrice: totalFee,
          surcharge: 0,
          totalPrice: totalFee,
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

  /// Option B: Show Urgent Nurse Booking Dialog (Same Day)
  void _showUrgentBookingDialog(Map<String, dynamic> nurseData) {
    DateTime selectedDate = DateTime.now();
    String selectedTime = '12:00 PM';
    final int? rate = _dailyRate;
    if (rate == null) return _priceNotSet();
    final int basePrice = rate;

    bool isNurseAvailable = true;
    bool checkingSchedule = false;
    List<String> availableSlots = [
      '09:00 AM',
      '11:00 AM',
      '02:00 PM',
      '05:00 PM'
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
            // No extra incentive for home visits (doctors only)
            const int currentOffer = 0;
            final int calculatedTotalPrice = basePrice + currentOffer;

            Future<void> checkNurseSchedule(DateTime date) async {
              setModalState(() => checkingSchedule = true);

              final nurseUid = nurseData['uid'] ?? '';
              final dateKey = _formatDateKey(date);
              final dateStr = _formatDateStandard(date);

              final scheduleData = await FirestoreService.getDoctorDateSchedule(
                doctorUid: nurseUid,
                dateKey: dateKey,
              );

              final doctorBookedSlots =
                  await FirestoreService.getDoctorBookedTimeSlots(
                doctorUid: nurseUid,
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
                  isNurseAvailable = avail;
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
                  isNurseAvailable = true;
                  availableSlots = [
                    '09:00 AM',
                    '11:00 AM',
                    '02:00 PM',
                    '05:00 PM'
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
                checkNurseSchedule(selectedDate);
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Urgent Home Nursing (Today)',
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

                  // Nurse Details
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor:
                            AppColors.primary.withValues(alpha: 0.15),
                        child: const Icon(Icons.local_hospital_rounded,
                            color: AppColors.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nurseData['name'] ?? 'Nurse',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              '${nurseData['qualification'] ?? 'B.Sc Nursing'} • ${nurseData['organisation'] ?? 'Hospital'}',
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

                  const SizedBox(height: 16),

                  // Select Time Slot
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
                          Text('Checking nurse schedule...'),
                        ],
                      ),
                    )
                  else if (!isNurseAvailable || availableSlots.isEmpty)
                    const Text(
                      'No available time slots for today.',
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
                                  if (val)
                                    setModalState(() => selectedTime = time);
                                },
                        );
                      }).toList(),
                    ),

                  const SizedBox(height: 24),

                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brand,
                    ),
                    onPressed: (!isNurseAvailable || availableSlots.isEmpty)
                        ? null
                        : () async {
                            Navigator.pop(ctx);

                            final docRef = AppDatabase.instance
                                .collection('appointments')
                                .doc();
                            final appointmentId = docRef.id;
                            final otp =
                                ServiceOtp.generate();

                            final dialogContext = context;

                            await docRef.set({
                              'appointmentId': appointmentId,
                              'patientUid': widget.patient.uid,
                              'patientName': widget.patient.name,
                              'patientPhone': widget.patient.phone ?? '',
                              'doctorUid': nurseData['uid'] ?? '',
                              'doctorName': nurseData['name'] ?? 'Nurse',
                              'doctorCategory':
                                  nurseData['qualification'] ?? 'B.Sc Nursing',
                              'hospital':
                                  nurseData['organisation'] ?? 'City Home Care',
                              'date': _formatDateStandard(selectedDate),
                              'time': selectedTime,
                              'durationDays': 1,
                              'basePrice': basePrice,
                              'offeredExtraAmount': currentOffer,
                              'price': calculatedTotalPrice,
                              'locationName': _liveAreaName,
                              // only a real GPS position (never the Pune map centre)
                              if (_patientPosition != null)
                                'patientLat': _patientPosition!.latitude,
                              if (_patientPosition != null)
                                'patientLng': _patientPosition!.longitude,
                              'patientLocationKnown': _patientPosition != null,
                              'consultationType': 'Urgent Home Nursing',
                              'isUrgentEmergency': true,
                              'isNurseRequest': true,
                              'roleTarget': 'nurse',
                              'status': 'Pending Home Visit',
                              'paymentStatus':
                                  'pending', // paid online after a provider accepts
                              'otp': otp,
                              'hasBeenRated': false,
                              'declinedBy': [],
                              'createdAt': DateTime.now().toIso8601String(),
                            });

                            if (!dialogContext.mounted) return;

                            showDialog(
                              context: dialogContext,
                              barrierDismissible: false,
                              builder: (_) => NurseStatusDialog(
                                appointmentId: appointmentId,
                                nurseName: nurseData['name'] ?? 'Nurse',
                                basePrice: basePrice,
                                surcharge: currentOffer,
                                totalPrice: calculatedTotalPrice,
                              ),
                            );
                          },
                    child: Text(
                      'Request Urgent Nursing (₹$calculatedTotalPrice)',
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

  @override
  Widget build(BuildContext context) {
    return ResponsiveCenter(
        child: Scaffold(
      backgroundColor: AppTheme.bgLight,
      appBar: AppBar(
        title: const Text('Book Home Nursing'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Mode Selector Toggle (Book for Later vs Urgent Today)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.lineStrong),
              ),
              child: Row(
                children: [
                  _buildModeTab(0, 'Book for Later (3-7 Days)'),
                  _buildModeTab(1, 'Urgent Nursing (Today)'),
                ],
              ),
            ),

            // Mode Details Header Card
            if (_selectedModeIndex == 0) ...[
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.successTint,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.calendar_month_rounded,
                            color: AppColors.primary, size: 22),
                        SizedBox(width: 8),
                        Text(
                          'Multi-Day Home Nursing Service',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.darkNavy,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '• Duration: Min 3 Days, Max 7 Days\n• Hours: Fixed 12:00 PM - 06:00 PM every day\n• Fee: ${_feeLabel(1)} / day',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.darkNavy,
                          height: 1.4,
                          fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 12),

                    // Start Date Picker & Duration Selector
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _startDate,
                                firstDate:
                                    DateTime.now().add(const Duration(days: 1)),
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 60)),
                              );
                              if (picked != null) {
                                setState(() => _startDate = picked);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.lineStrong),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.event,
                                      color: AppColors.primary, size: 16),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Start: ${_formatDateStandard(_startDate)}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Days Dropdown Selector
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.lineStrong),
                          ),
                          child: DropdownButton<int>(
                            menuMaxHeight: 320,
                            value: _durationDays,
                            underline: const SizedBox(),
                            icon: const Icon(Icons.arrow_drop_down,
                                color: AppColors.primary),
                            items: [3, 4, 5, 6, 7].map((days) {
                              return DropdownMenuItem<int>(
                                value: days,
                                child: Text('$days Days (${_feeLabel(days)})',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold)),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _durationDays = val);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.orangeTint,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.warningBorder),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.directions_run_rounded,
                        color: AppColors.warning, size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Urgent Same-Day Nursing: Book a nurse for today based on their availability.',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.darkNavy),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 14),

            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _streams.get(
                    'providers', () => FirestoreService.getNursesStream()),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return LoadErrorView(error: snapshot.error, what: 'nurses');
                  }
                  if (snapshot.connectionState == ConnectionState.waiting ||
                      _loadingPosition) {
                    return const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary),
                    );
                  }

                  final allNurses = snapshot.data ?? [];
                  final List<Map<String, dynamic>> nearbyNurses = [];

                  for (var nurse in allNurses) {
                    // STRICT ADMIN VERIFICATION GATE:
                    if (nurse['isVerified'] != true) continue;
                    // Blocked for 15 days after 3 absents in a month
                    if (FirestoreService.isProviderBlocked(nurse)) continue;
                    // Nurse switched Offline on their dashboard
                    if (nurse['isOnline'] == false) continue;

                    final List<dynamic> prefLocs =
                        nurse['preferredLocations'] as List<dynamic>? ?? [];

                    // Strict area rule: a provider who chose service areas only appears
                    // for patients inside those areas (Baner/Balewadi never sees Katraj).
                    // A provider without areas appears only if their real shared
                    // location is close by.
                    final bool hasRealLocation =
                        nurse['latitude'] is num && nurse['longitude'] is num;
                    final bool servesArea = prefLocs.isNotEmpty &&
                        FirestoreService.providerServesArea(
                            prefLocs, _liveAreaName);

                    double nurseLat = toNum(nurse['latitude'])?.toDouble() ??
                        (_patientPosition?.latitude ??
                                LocationService.defaultLat) +
                            0.02;
                    double nurseLng =
                        toNum(nurse['longitude'])?.toDouble() ??
                            (_patientPosition?.longitude ??
                                    LocationService.defaultLng) +
                                0.015;

                    double distanceInMeters = Geolocator.distanceBetween(
                      _patientPosition?.latitude ?? LocationService.defaultLat,
                      _patientPosition?.longitude ?? LocationService.defaultLng,
                      nurseLat,
                      nurseLng,
                    );

                    double distanceInKm = distanceInMeters / 1000.0;

                    if (servesArea ||
                        (prefLocs.isEmpty &&
                            hasRealLocation &&
                            distanceInKm <= 10.0)) {
                      nurse['calculatedDistanceKm'] = distanceInKm;
                      nurse['servesPatientArea'] = servesArea;
                      nearbyNurses.add(nurse);
                    }
                  }

                  // Sort: Nurses serving patient's exact area FIRST!
                  nearbyNurses.sort((a, b) {
                    final bool sA = a['servesPatientArea'] == true;
                    final bool sB = b['servesPatientArea'] == true;
                    if (sA && !sB) return -1;
                    if (!sA && sB) return 1;

                    final dA = (a['calculatedDistanceKm'] as double?) ?? 0;
                    final dB = (b['calculatedDistanceKm'] as double?) ?? 0;
                    return dA.compareTo(dB);
                  });

                  if (nearbyNurses.isEmpty) {
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
                              'No available nurses serving $_liveAreaName.',
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
                    itemCount: nearbyNurses.length,
                    itemBuilder: (context, index) {
                      final nurse = nearbyNurses[index];
                      final dist =
                          (nurse['calculatedDistanceKm'] as double?) ?? 2.5;
                      final nurseRating = FirestoreService.ratingLabel(nurse);
                      final bool isOnline = nurse['isOnline'] ?? true;
                      final bool servesArea =
                          nurse['servesPatientArea'] == true;
                      final String nurseUid = nurse['uid'] ?? '';

                      return FutureBuilder<bool>(
                        future: _selectedModeIndex == 0
                            ? FirestoreService.checkNurseMultiDayAvailability(
                                nurseUid: nurseUid,
                                startDate: _startDate,
                                durationDays: _durationDays,
                              )
                            : Future.value(true),
                        builder: (context, availSnap) {
                          final bool isMultiDayAvailable =
                              availSnap.data ?? true;
                          final bool canBook = isOnline && isMultiDayAvailable;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              border: servesArea
                                  ? Border.all(
                                      color: AppColors.primary, width: 2)
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
                                      color: AppColors.successTint,
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
                                            color: AppColors.primary,
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
                                      photoUrl:
                                          nurse['profilePicUrl']?.toString(),
                                      roleKey: ImagesMaster.service('Nurses'),
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
                                                nurse['name'] ?? 'Nurse',
                                                style: const TextStyle(
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppTheme.darkNavy,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: AppColors.warningTint,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  '★ $nurseRating',
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
                                          Text(
                                            '${nurse['qualification'] ?? 'B.Sc Nursing'} • ${nurse['organisation'] ?? 'City Care'}',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: AppTheme.textMuted,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 4,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              const VerifiedBadge(),
                                              if ((nurse['experience'] ?? '')
                                                  .toString()
                                                  .trim()
                                                  .isNotEmpty)
                                                Text(
                                                  '${nurse['experience']} yrs experience',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: AppTheme.textMuted,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: AppColors.successTint,
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                                child: Row(
                                                  children: [
                                                    const Icon(
                                                        Icons.near_me_rounded,
                                                        size: 12,
                                                        color:
                                                            AppColors.primary),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      '${dist.toStringAsFixed(1)} km away',
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color:
                                                            AppColors.primary,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              if (!isMultiDayAvailable &&
                                                  _selectedModeIndex == 0)
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.dangerSoft,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10),
                                                  ),
                                                  child: const Text(
                                                    'BOOKED ON THESE DATES',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: AppColors.danger,
                                                    ),
                                                  ),
                                                )
                                              else if (!isOnline)
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.dangerSoft,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10),
                                                  ),
                                                  child: const Text(
                                                    'OFFLINE',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold,
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
                                  onPressed: !canBook
                                      ? null
                                      : () {
                                          if (_selectedModeIndex == 0) {
                                            final fee = PricingService.current
                                                .nurseFee(_durationDays);
                                            if (fee == null) {
                                              return _priceNotSet();
                                            }
                                            _handleMultiDayBookingConfirmation(
                                              nurseData: nurse,
                                              startDate: _startDate,
                                              days: _durationDays,
                                              totalFee: fee,
                                            );
                                          } else {
                                            _showUrgentBookingDialog(nurse);
                                          }
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: !canBook
                                        ? AppColors.muted
                                        : AppColors.primary,
                                    minimumSize:
                                        const Size(double.infinity, 44),
                                  ),
                                  child: Text(
                                    !isMultiDayAvailable &&
                                            _selectedModeIndex == 0
                                        ? 'Booked on These Dates (Unavailable)'
                                        : !isOnline
                                            ? 'Nurse Offline (Unavailable)'
                                            : _selectedModeIndex == 0
                                                ? 'Book for $_durationDays Days (${_feeLabel(_durationDays)})'
                                                : 'Request Urgent Nursing (${_feeLabel(1)})',
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
        ),
      ),
    ));
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
            color: isSelected ? AppColors.primary : Colors.transparent,
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
}
