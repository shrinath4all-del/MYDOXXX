import '../../services/app_database.dart';
import '../../services/lab_device.dart';
import 'dart:math';
import '../../utils/safe_cast.dart';
import '../../widgets/verification_gate.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../services/pricing_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/technician_status_dialog.dart';
import '../../utils/error_messages.dart';
import '../../utils/stream_cache.dart';
import '../../utils/responsive.dart';
import '../../constants/app_colors.dart';
import '../../services/images_master.dart';
import '../../widgets/master_image.dart';
import '../../widgets/circle_image.dart';
import '../../widgets/verified_badge.dart';
import '../../services/test_suggestion_service.dart';
import '../../widgets/app_dialog.dart';
import '../../constants/app_strings.dart';

class BookTechnicianScreen extends StatefulWidget {
  final UserModel patient;
  final String? initialTestName;

  const BookTechnicianScreen({
    super.key,
    required this.patient,
    this.initialTestName,
  });

  @override
  State<BookTechnicianScreen> createState() => _BookTechnicianScreenState();
}

class _BookTechnicianScreenState extends State<BookTechnicianScreen> {
  // Live data connections kept open across redraws
  final StreamCache _streams = StreamCache();

  String? _selectedTestName;
  List<Map<String, dynamic>> _labTestsWithPrice = [];
  bool _loadingLabTests = true;

  Position? _patientPosition;
  bool _loadingPosition = true;
  String _liveAreaName = 'Nearby Patient Area';

  @override
  void initState() {
    super.initState();
    guardVerifiedRequester(context, widget.patient);
    _selectedTestName = widget.initialTestName;
    _fetchLabTests();
    _fetchPatientPosition();
  }

  Future<void> _fetchLabTests() async {
    try {
      final list = await FirestoreService.getLabTestsWithPrice();
      if (mounted) {
        setState(() {
          _labTestsWithPrice = list;
          _loadingLabTests = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _labTestsWithPrice = [];
          _loadingLabTests = false;
        });
      }
    }
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

  /// The test's price from Firestore (null while it is not set).
  int? _getTestPrice(String testName) {
    for (final c in _labTestsWithPrice) {
      if ((c['name'] as String).toLowerCase() == testName.toLowerCase()) {
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
              'Technician $techName is already attending another patient at $time on $date.\n\nPlease choose a different time slot or date for your sample collection.',
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
    required Map<String, dynamic> techData,
    required DateTime selectedDate,
    required String selectedTime,
    required int basePrice,
    required int totalPrice,
    required BuildContext bottomSheetContext,
  }) async {
    if (_bookingInFlight) return;
    _bookingInFlight = true;
    try {
      await _handleBookingConfirmationImpl(techData: techData, selectedDate: selectedDate, selectedTime: selectedTime, basePrice: basePrice, totalPrice: totalPrice, bottomSheetContext: bottomSheetContext);
    } finally {
      _bookingInFlight = false;
    }
  }

  Future<void> _handleBookingConfirmationImpl({
    required Map<String, dynamic> techData,
    required DateTime selectedDate,
    required String selectedTime,
    required int basePrice,
    required int totalPrice,
    required BuildContext bottomSheetContext,
  }) async {
    final int offeredExtra = totalPrice - basePrice;
    final String dateFormatted = _formatDateStandard(selectedDate);
    final String techName = techData['name'] ?? 'Technician';

    // Live Double-Check 1: Check if Technician is ALREADY booked at this time slot
    final doubleCheckTech = await FirestoreService.getDoctorBookedTimeSlots(
      doctorUid: techData['uid'] ?? '',
      date: dateFormatted,
    );

    if (doubleCheckTech.contains(selectedTime.trim().toUpperCase())) {
      if (!mounted) return;
      _showDoctorBookedPopup(techName, selectedTime, dateFormatted);
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
      title: 'Confirm home sample visit?',
      message:
          'Send a home visit request to technician $techName for $dateFormatted at $selectedTime? The technician will accept or decline it.',
      content: PriceBreakdown(
        base: basePrice,
        baseLabel: 'Test fee',
        extras: [(AppStrings.urgentSurcharge, offeredExtra)],
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
      final otp = (1000 + Random().nextInt(9000)).toString();

      await docRef.set({
        'appointmentId': appointmentId,
        'patientUid': widget.patient.uid,
        'patientName': widget.patient.name,
        'patientPhone': widget.patient.phone ?? '',
        'doctorUid': techData['uid'] ?? '',
        'doctorName': techData['name'] ?? 'Technician',
        'doctorCategory': techData['qualification'] ?? 'Lab Technician',
        'hospital': techData['organisation'] ?? 'MyDox Lab',
        'date': dateFormatted,
        'time': selectedTime,
        'basePrice': basePrice,
        'offeredExtraAmount': offeredExtra,
        'price': totalPrice,
        'locationName': _liveAreaName,
        // only a real GPS position (never the Pune map centre)
        if (_patientPosition != null) 'patientLat': _patientPosition!.latitude,
        if (_patientPosition != null) 'patientLng': _patientPosition!.longitude,
        'patientLocationKnown': _patientPosition != null,
        'consultationType': 'Home Visit',
        // Shown on the technician's dashboard cards
        'testName': _selectedTestName ?? 'Lab - Blood Draw',
        'isUrgentEmergency': false,
        'isTechnicianRequest': true,
        'roleTarget': 'technician',
        'status': 'Pending Home Visit',
        'paymentStatus': 'pending', // paid online after a provider accepts
        'otp': otp,
        'hasBeenRated': false,
        'declinedBy': [],
        'createdAt': DateTime.now().toIso8601String(),
      });

      // A test the doctor suggested is now booked: stop its reminders
      await TestSuggestionService.markBookedByTest(
          widget.patient.uid, _selectedTestName ?? '', appointmentId);

      if (!mounted) return;

      // Show Radar Pulse Tracker Dialog for Patient
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => TechnicianStatusDialog(
          appointmentId: appointmentId,
          technicianName: techData['name'] ?? 'Technician',
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
  }

  void _showBookingDialog(Map<String, dynamic> techData) {
    DateTime selectedDate = DateTime.now();
    String selectedTime = '10:00 AM';

    final String testName = _selectedTestName ?? 'Lab - Blood Draw';
    final int? price = _getTestPrice(testName);
    if (price == null) return _priceNotSet();
    final int basePrice = price;

    bool isTechAvailable = true;
    bool checkingSchedule = false;
    List<String> availableSlots = [
      '09:00 AM',
      '10:00 AM',
      '11:30 AM',
      '02:00 PM',
      '04:30 PM'
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

            Future<void> checkTechSchedule(DateTime date) async {
              setModalState(() => checkingSchedule = true);

              final techUid = techData['uid'] ?? '';
              final dateKey = _formatDateKey(date);
              final dateStr = _formatDateStandard(date);

              final scheduleData = await FirestoreService.getDoctorDateSchedule(
                doctorUid: techUid,
                dateKey: dateKey,
              );

              final doctorBookedSlots =
                  await FirestoreService.getDoctorBookedTimeSlots(
                doctorUid: techUid,
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
                  isTechAvailable = avail;
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
                  isTechAvailable = true;
                  availableSlots = [
                    '09:00 AM',
                    '10:00 AM',
                    '11:30 AM',
                    '02:00 PM',
                    '04:30 PM'
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
                checkTechSchedule(selectedDate);
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
                        'Request Home Lab Test Visit',
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
                        child: const Icon(Icons.science_rounded,
                            color: AppColors.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              techData['name'] ?? 'Technician',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              '${techData['qualification'] ?? 'DMLT'} • ${techData['organisation'] ?? 'Lab'}',
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
                      color: AppColors.primarySoft,
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
                            'Strictly Home Visit: Technician will arrive at your home location for sample collection.',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Date Picker Row
                  const Text('Select Date for Sample Collection',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 60)),
                      );
                      if (picked != null) {
                        setModalState(() => selectedDate = picked);
                        await checkTechSchedule(picked);
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
                              color: AppColors.primary, size: 18),
                          const SizedBox(width: 10),
                          Text(
                            '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
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
                          Text('Checking technician schedule...'),
                        ],
                      ),
                    )
                  else if (!isTechAvailable || availableSlots.isEmpty)
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

                  const SizedBox(height: 24),

                  // Confirm Button
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brand,
                    ),
                    onPressed: (!isTechAvailable || availableSlots.isEmpty)
                        ? null
                        : () => _handleBookingConfirmation(
                              techData: techData,
                              selectedDate: selectedDate,
                              selectedTime: selectedTime,
                              basePrice: basePrice,
                              totalPrice: calculatedTotalPrice,
                              bottomSheetContext: ctx,
                            ),
                    child: Text(
                      'Request Home Test Visit (₹$calculatedTotalPrice)',
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
        child: PopScope(
            // Back from a test's technician list returns to the test list
            canPop: _selectedTestName == null || widget.initialTestName != null,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) setState(() => _selectedTestName = null);
            },
            child: Scaffold(
              backgroundColor: AppTheme.bgLight,
              body: SafeArea(
                child: _selectedTestName == null
                    ? _buildTestSelectionGrid()
                    : Column(
                        children: [
                          AppBar(
                            leading: BackButton(
                              onPressed: () {
                                if (widget.initialTestName != null) {
                                  Navigator.of(context).maybePop();
                                } else {
                                  setState(() => _selectedTestName = null);
                                }
                              },
                            ),
                            title: Text('Lab Test: $_selectedTestName'),
                          ),
                          Expanded(child: _buildTechnicianListForTest()),
                        ],
                      ),
              ),
            )));
  }

  /// Step 1: Select Lab Test Category Grid
  Widget _buildTestSelectionGrid() {
    if (_loadingLabTests) {
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
            'Find a Lab Technician',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppTheme.darkNavy,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Choose the lab test or home blood collection you need',
            style: TextStyle(
              fontSize: 15,
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),

          // Top Hero Banner with Uploaded Blood Draw Image
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primaryDark, AppColors.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
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
                        'Home Sample Collection',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Certified lab technicians visit your home with sterile equipment.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: MasterImage(
                    imageKey: ImagesMaster.banner('lab_tests'),
                    height: 85,
                    width: 85,
                    fit: BoxFit.cover,
                    placeholder: const Icon(
                      Icons.science_rounded,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _labTestsWithPrice.length,
            // columns from the screen width; tile tall enough for a
            // two-line name at any font size
            gridDelegate:
                Responsive.grid(context, minTileWidth: 150, tileHeight: 236),
            itemBuilder: (context, index) {
              final testMap = _labTestsWithPrice[index];
              final String testName = testMap['name'] ?? '';
              final int? price = toNum(testMap['price'])?.toInt();

              return GestureDetector(
                onTap: () {
                  if (price == null) return _priceNotSet();
                  setState(() => _selectedTestName = testName);
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
                        imageKey: ImagesMaster.labTest(testName),
                        size: 96,
                        icon: Icons.science_rounded,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        testName,
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
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          price == null ? 'Price not set' : '₹$price',
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

  /// Step 2: Show Available Technicians matching Patient Area & Lab Test Category
  Widget _buildTechnicianListForTest() {
    final int? testPrice =
        _selectedTestName != null ? _getTestPrice(_selectedTestName!) : null;
    if (!_loadingLabTests && testPrice == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child:
              Text(PricingService.notSetMessage, textAlign: TextAlign.center),
        ),
      );
    }
    final int baseTestPrice = testPrice ?? 0;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.white,
          child: Row(
            children: [
              Chip(
                backgroundColor: AppColors.primary,
                label: Text(
                  '$_selectedTestName (₹$baseTestPrice)',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
                deleteIcon:
                    const Icon(Icons.close, color: Colors.white, size: 18),
                onDeleted: () {
                  setState(() => _selectedTestName = null);
                },
              ),
              const Spacer(),
              Row(
                children: [
                  const Icon(Icons.near_me_rounded,
                      color: AppColors.primary, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    _liveAreaName.split(',').first,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _streams.get(
                'providers', () => FirestoreService.getTechniciansStream()),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return LoadErrorView(
                    error: snapshot.error, what: 'technicians');
              }
              if (snapshot.connectionState == ConnectionState.waiting ||
                  _loadingPosition) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                );
              }

              final allTechs = snapshot.data ?? [];
              final List<Map<String, dynamic>> nearbyTechs = [];

              for (var tech in allTechs) {
                // STRICT ADMIN VERIFICATION GATE:
                if (tech['isVerified'] != true) continue;
                // Blocked for 15 days after 3 absents in a month
                if (FirestoreService.isProviderBlocked(tech)) continue;
                // Technician switched Offline on their dashboard
                if (tech['isOnline'] == false) continue;

                // 1. FILTER BY OFFERED LAB TEST:
                final List<dynamic> offeredTests =
                    tech['offeredTests'] as List<dynamic>? ?? [];
                if (offeredTests.isNotEmpty && _selectedTestName != null) {
                  final bool offersSelectedTest = offeredTests.any((t) =>
                      t.toString().trim().toLowerCase() ==
                      _selectedTestName!.trim().toLowerCase());
                  if (!offersSelectedTest) continue; // SKIP!
                }

                // 2. FILTER BY PREFERRED SERVICE LOCATION:
                final List<dynamic> prefLocs =
                    tech['preferredLocations'] as List<dynamic>? ?? [];

                // Strict area rule: a provider who chose service areas only appears
                // for patients inside those areas (Baner/Balewadi never sees Katraj).
                // A provider without areas appears only if their real shared
                // location is close by.
                final bool hasRealLocation =
                    tech['latitude'] is num && tech['longitude'] is num;
                final bool servesArea = prefLocs.isNotEmpty &&
                    FirestoreService.providerServesArea(
                        prefLocs, _liveAreaName);

                double techLat = toNum(tech['latitude'])?.toDouble() ??
                    (_patientPosition?.latitude ?? LocationService.defaultLat) +
                        0.02;
                double techLng = toNum(tech['longitude'])?.toDouble() ??
                    (_patientPosition?.longitude ??
                            LocationService.defaultLng) +
                        0.015;

                double distanceInMeters = Geolocator.distanceBetween(
                  _patientPosition?.latitude ?? LocationService.defaultLat,
                  _patientPosition?.longitude ?? LocationService.defaultLng,
                  techLat,
                  techLng,
                );

                double distanceInKm = distanceInMeters / 1000.0;

                if (servesArea ||
                    (prefLocs.isEmpty &&
                        hasRealLocation &&
                        distanceInKm <= 10.0)) {
                  tech['calculatedDistanceKm'] = distanceInKm;
                  tech['servesPatientArea'] = servesArea;
                  nearbyTechs.add(tech);
                }
              }

              // Sort: Technicians serving patient's exact area FIRST!
              nearbyTechs.sort((a, b) {
                final bool sA = a['servesPatientArea'] == true;
                final bool sB = b['servesPatientArea'] == true;
                if (sA && !sB) return -1;
                if (!sA && sB) return 1;

                final dA = (a['calculatedDistanceKm'] as double?) ?? 0;
                final dB = (b['calculatedDistanceKm'] as double?) ?? 0;
                return dA.compareTo(dB);
              });

              if (nearbyTechs.isEmpty) {
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
                          'No available technicians offering $_selectedTestName in $_liveAreaName.',
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
                itemCount: nearbyTechs.length,
                itemBuilder: (context, index) {
                  final tech = nearbyTechs[index];
                  final dist = (tech['calculatedDistanceKm'] as double?) ?? 2.5;
                  final techRating = FirestoreService.ratingLabel(tech);
                  final bool isOnline = tech['isOnline'] ?? true;
                  final bool servesArea = tech['servesPatientArea'] == true;

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
                              color: AppColors.primarySoft,
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
                              photoUrl: tech['profilePicUrl']?.toString(),
                              roleKey: ImagesMaster.service('Technician'),
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
                                      Text(
                                        tech['name'] ?? 'Technician',
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
                                          '★ $techRating',
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
                                    '${tech['qualification'] ?? 'DMLT'} • ${tech['organisation'] ?? 'Lab'}',
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
                                          color: AppColors.primarySoft,
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
                                                color: AppColors.primary,
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
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      '${tech['name']} is currently NOT AVAILABLE / Offline. Broadcasting request to nearby technicians...'),
                                  backgroundColor: AppColors.orange,
                                ),
                              );
                              return;
                            }
                            _showBookingDialog(tech);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                !isOnline ? AppColors.muted : AppColors.primary,
                            minimumSize: const Size(double.infinity, 44),
                          ),
                          child: Text(
                            !isOnline
                                ? 'Not Available (Offline)'
                                : 'Request Home Sample Visit (₹$baseTestPrice)',
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
