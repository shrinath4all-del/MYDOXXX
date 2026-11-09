import '../../services/app_database.dart';
import '../../services/lab_device.dart';
import '../../widgets/circle_image.dart';
import '../../utils/safe_cast.dart';
import '../../utils/maps_navigation.dart';
import '../../services/push_service.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/sos_service.dart';
import '../../utils/appointment_rules.dart';
import '../common/appointments_calendar_screen.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/payout_setup_banner.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/doctor_emergency_alert_dialog.dart';
import '../../widgets/doctor_home_visit_alert_dialog.dart';
import '../auth/login_screen.dart';
import '../chat/chat_screen.dart';
import '../chat/video_call_screen.dart';
import '../../widgets/incoming_call_listener.dart';
import '../../widgets/notification_bell.dart';
import '../../services/call_service.dart';
import 'doctor_schedule_screen.dart';
import 'edit_doctor_profile_screen.dart';
import '../../utils/error_messages.dart';
import '../../utils/stream_cache.dart';
import '../../widgets/agency_duties_card.dart';
import '../../services/location_tracker.dart';
import '../../utils/responsive.dart';
import '../../constants/app_colors.dart';

import '../../widgets/chat_button.dart';
import '../../utils/ist_clock.dart';

class DoctorHomeScreen extends StatefulWidget {
  final UserModel doctor;

  const DoctorHomeScreen({
    super.key,
    required this.doctor,
  });

  @override
  State<DoctorHomeScreen> createState() => _DoctorHomeScreenState();
}

class _DoctorHomeScreenState extends State<DoctorHomeScreen> {
  // Live data connections kept open across redraws
  final StreamCache _streams = StreamCache();

  final AuthService _authService = AuthService();
  late UserModel _doctor;
  // Live profile listener; cancelled when the screen closes (e.g. logout)
  StreamSubscription? _profileSub;
  late IncomingCallWatcher _callWatcher;
  Map<String, dynamic> _raw = {};
  Timer? _autoCloseTimer;

  // Online / offline, saved on the doctor's profile. Offline: hidden from
  // patients, no bookings, no urgent requests, no emergency calls.
  bool get _isAvailable => _raw['isOnline'] != false;

  /// Live location in the background while the doctor is Online (urgent
  /// and SOS requests are matched on it); stopped when Offline.
  void _syncTracking() {
    if (_isAvailable && _doctor.isVerified) {
      LocationTracker.start(
        collection: 'doctors',
        uid: _doctor.uid,
        onPosition: (p) {
          // redraw only for a real move (the dashboard shows distances)
          final last = _doctorPos;
          final moved = last == null
              ? double.infinity
              : Geolocator.distanceBetween(
                  last.latitude, last.longitude, p.latitude, p.longitude);
          if (mounted && moved > 200) setState(() => _doctorPos = p);
        },
      );
    } else {
      LocationTracker.stop();
    }
  }

  Future<void> _setOnline(bool online) async {
    setState(() => _raw = {..._raw, 'isOnline': online});
    _syncTracking();
    try {
      await AppDatabase.instance.collection('doctors').doc(_doctor.uid).set({
        'isOnline': online,
        'onlineChangedAt': IstClock.now().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (_) {
      if (mounted) setState(() => _raw = {..._raw, 'isOnline': !online});
    }
  }
  String _currentLocation = 'Detecting location...';
  bool _isLoadingLocation = false;
  String? _lastAlertAppointmentId;
  int _selectedTabIndex = 0; // 0 = Upcoming, 1 = Completed

  /// Bookings drawn at a time ("Show more" adds the next page): the list
  /// sits in the dashboard's single scroll view, so every drawn card is
  /// laid out, and the Completed history keeps growing.
  static const int _pageSize = 20;
  int _shownBookings = _pageSize;

  @override
  void initState() {
    super.initState();
    _doctor = widget.doctor;
    PushService.registerForUser(widget.doctor.uid);
    PushService.openSignal.addListener(_onPushTap);
    _callWatcher = IncomingCallWatcher(
      contextProvider: () => context,
      uid: widget.doctor.uid,
      userName: () => _doctor.name,
    )..start();
    _fetchLiveLocation();
    // Close sessions left "In Progress" past their booked end time
    _autoCloseOverdue();
    _autoCloseTimer = Timer.periodic(
        const Duration(minutes: 1), (_) => _autoCloseOverdue());
    // keep the saved live position fresh: emergency requests are matched on it
    _liveLocationTimer =
        Timer.periodic(const Duration(minutes: 1), (_) => _refreshLivePosition());
    _profileSub =
        FirestoreService.getUserStream(_doctor.uid, 'doctor').listen((doc) {
      if (mounted && doc.exists && doc.data() != null) {
        // only the live position moved: no full dashboard rebuild
        if (sameExceptLocation(_raw, doc.data()!)) {
          _raw = doc.data()!;
          return;
        }
        setState(() {
          _raw = doc.data()!;
          _doctor = UserModel.fromMap(doc.data()!, _doctor.uid);
        });
        _syncTracking();
      }
    });
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    _callWatcher.dispose();
    _autoCloseTimer?.cancel();
    _liveLocationTimer?.cancel();
    LocationTracker.stop();
    super.dispose();
  }

  Future<void> _autoCloseOverdue() async {
    final r =
        await FirestoreService.runPunctualityChecks(providerUid: _doctor.uid);
    if (!mounted) return;
    if (r.absent > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Marked absent for ${r.absent} home visit${r.absent == 1 ? '' : 's'} '
            'not started in time. Professional score reduced by '
            '${FirestoreService.absentPenaltyPoints}% each.'),
        backgroundColor: AppColors.danger,
      ));
    } else if (r.closed > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${r.closed} consultation${r.closed == 1 ? '' : 's'} closed '
            'automatically (booked time ended).'),
        backgroundColor: AppTheme.primaryTeal,
      ));
    }
  }

  /// This doctor's live bookings. Reopened only when the category, areas or
  /// position (rounded to ~1 km) change, not on every redraw.
  Stream<List<Map<String, dynamic>>> _bookingsStream() {
    final lat = _doctorPos?.latitude ?? _doctor.latitude;
    final lng = _doctorPos?.longitude ?? _doctor.longitude;
    final key = 'bookings:${_doctor.category}:$_isAvailable:'
        '${(_doctor.preferredLocations ?? []).join('|')}:'
        '${lat?.toStringAsFixed(2)}:${lng?.toStringAsFixed(2)}';
    return _streams.get(
      key,
      () => FirestoreService.getDoctorBookingsStream(
        _doctor.uid,
        doctorCategory: _doctor.category,
        doctorLocations: _doctor.preferredLocations,
        doctorLat: lat,
        doctorLng: lng,
        doctorOnline: _isAvailable,
      ),
    );
  }

  bool get _blocked => FirestoreService.isProviderBlocked(_raw);

  void _showRunningLateSheet(Map<String, dynamic> b) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Running late?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                'Tell ${b['patientName'] ?? 'the patient'} how late you will be. '
                'Telling them before you are 30 mins late means no score down.',
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [15, 30, 45, 60].map((m) {
                  return OutlinedButton(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      Navigator.pop(ctx);
                      final ok = await FirestoreService.notifyRunningLate(
                        appointmentId: b['appointmentId'] ?? '',
                        minutes: m,
                      );
                      messenger.showSnackBar(SnackBar(
                        content: Text(ok
                            ? 'Patient told you will be about $m mins late.'
                            : 'Too late to tell: already counted as late.'),
                        backgroundColor:
                            ok ? AppTheme.primaryTeal : AppColors.warning,
                      ));
                    },
                    child: Text('$m mins'),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Position? _doctorPos;

  Timer? _liveLocationTimer;

  /// Saves the doctor's current position (no UI change). Not needed while
  /// background tracking runs (it saves the position itself).
  Future<void> _refreshLivePosition() async {
    if (LocationTracker.isRunning) return;
    try {
      final pos = await LabLocation.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      await AppDatabase.instance
          .collection('doctors')
          .doc(_doctor.uid)
          .set({'latitude': pos.latitude, 'longitude': pos.longitude},
              SetOptions(merge: true));
      if (mounted) setState(() => _doctorPos = pos);
    } catch (_) {}
  }

  Future<void> _fetchLiveLocation() async {
    setState(() => _isLoadingLocation = true);
    try {
      final pos = await LabLocation.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
      final location = await LocationService.getCurrentLocation();

      await AppDatabase.instance
          .collection('doctors')
          .doc(_doctor.uid)
          .set({
        'latitude': pos.latitude,
        'longitude': pos.longitude,
      }, SetOptions(merge: true));


      if (mounted) {
        setState(() {
          _doctorPos = pos;
          _currentLocation = location;
          _isLoadingLocation = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  void _signOut() async {
    await _authService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _openEditProfile() async {
    final updatedDoctor = await Navigator.of(context).push<UserModel>(
      MaterialPageRoute(
        builder: (_) => EditDoctorProfileScreen(doctor: _doctor),
      ),
    );

    if (updatedDoctor != null && mounted) {
      setState(() {
        _doctor = updatedDoctor;
      });
    }
  }

  void _openScheduleManager() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DoctorScheduleScreen(doctor: _doctor),
      ),
    );
  }

  void _openChatWithPatient(String patientUid, String patientName) {
    final chatId = '${patientUid}_${_doctor.uid}';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chatId: chatId,
          currentUserId: _doctor.uid,
          currentUserName: _doctor.name,
          peerName: patientName,
          peerRole: 'Patient',
          canSuggestTests: true,
        ),
      ),
    );
  }

  void _openVideoCall(String patientName,
      {required String patientUid,
      String appointmentId = '',
      Map<String, dynamic>? booking}) {
    // Only inside the booked slot; the call ends by itself when it ends
    final window = booking == null
        ? (open: true, message: '', end: null as DateTime?)
        : AppointmentRules.videoWindow(booking);
    if (!window.open) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
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
              appointmentId.isNotEmpty ? appointmentId : patientUid),
          isCaller: true,
          appointmentId: appointmentId,
          currentUid: _doctor.uid,
          callerName: _doctor.name,
          peerUid: patientUid,
          peerName: patientName,
          peerRole: 'Patient',
          endsAt: window.end,
        ),
      ),
    );
  }

  void _triggerEmergencyPopup(Map<String, dynamic> appointment) {
    if (!_isAvailable) return; // offline: no emergency calls
    // Blocked for 15 days after 3 absents in a month
    if (_blocked) return;
    // Not bookable until admin approves all mandatory documents
    if (!_doctor.isVerified) return;
    final id = appointment['appointmentId'] ?? '';
    if (id == _lastAlertAppointmentId) return;

    _lastAlertAppointmentId = id;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => DoctorEmergencyAlertDialog(
        appointment: appointment,
        doctorUid: _doctor.uid,
        doctorName: _doctor.name,
      ),
    );
  }

  void _triggerHomeVisitPopup(Map<String, dynamic> appointment) {
    if (!_isAvailable) return; // offline: no requests
    // Blocked for 15 days after 3 absents in a month
    if (_blocked) return;
    // Not bookable until admin approves all mandatory documents
    if (!_doctor.isVerified) return;
    final id = appointment['appointmentId'] ?? '';
    if (id == _lastAlertAppointmentId) return;

    _lastAlertAppointmentId = id;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => DoctorHomeVisitAlertDialog(
        appointment: appointment,
        doctorUid: _doctor.uid,
        doctorName: _doctor.name,
      ),
    );
  }

  String? _getConsultationTimeValidationError(
      String dateStr, String timeStr, bool isUrgentEmergency) {
    if (isUrgentEmergency ||
        timeStr.toUpperCase().contains('ASAP') ||
        dateStr.trim().isEmpty) {
      return null; // Emergency / Immediate ASAP start allowed
    }

    try {
      final now = IstClock.now();

      int year = now.year;
      int month = now.month;
      int day = now.day;

      if (dateStr.contains('/')) {
        final dParts = dateStr.trim().split('/');
        if (dParts.length == 3) {
          day = int.parse(dParts[0]);
          month = int.parse(dParts[1]);
          year = int.parse(dParts[2]);
        }
      } else if (dateStr.contains('-')) {
        final dParts = dateStr.trim().split('-');
        if (dParts.length == 3) {
          year = int.parse(dParts[0]);
          month = int.parse(dParts[1]);
          day = int.parse(dParts[2]);
        }
      }

      final cleanedTime = timeStr.trim().toUpperCase();
      final timePart = cleanedTime.split('-').first.trim();
      final parts = timePart.split(' ');

      if (parts.isEmpty) return null;

      final subParts = parts[0].split(':');
      int hour = int.parse(subParts[0]);
      final minute = subParts.length > 1 ? int.parse(subParts[1]) : 0;

      final isPm = cleanedTime.contains('PM');
      final isAm = cleanedTime.contains('AM');

      if (isPm && hour < 12) {
        hour += 12;
      } else if (isAm && hour == 12) {
        hour = 0;
      }

      final scheduledStart = DateTime(year, month, day, hour, minute);

      if (now.isBefore(scheduledStart)) {
        final diff = scheduledStart.difference(now);
        final diffMinutes = diff.inMinutes;
        final hoursLeft = diffMinutes ~/ 60;
        final minsLeft = diffMinutes % 60;
        final waitStr = hoursLeft > 0
            ? '$hoursLeft hr $minsLeft mins'
            : '$minsLeft mins';

        return 'Scheduled time slot ($timeStr on $dateStr) has not started yet.\n\nPlease wait $waitStr before verifying OTP and starting the consultation.';
      }
    } catch (_) {}

    return null; // Valid to start!
  }

  /// Emergency Help: the doctor takes the patient's emergency OTP when they
  /// meet, which closes the emergency.
  void _promptSosPatientOtp(Map<String, dynamic> sos) {
    final otpController = TextEditingController();
    final patientName = (sos['patientName'] ?? 'the patient').toString();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Patient emergency OTP'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Ask $patientName for their 4-digit emergency OTP. '
              'This closes the emergency.',
              style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: otpController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 8),
              decoration:
                  const InputDecoration(hintText: '• • • •', counterText: ''),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.muted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final otp = otpController.text.trim();
              Navigator.pop(dialogCtx);
              bool ok;
              try {
                ok = await SosService.closeWithPatientOtp(
                  appointmentId: (sos['appointmentId'] ?? '').toString(),
                  enteredOtp: otp,
                  doctorUid: _doctor.uid,
                );
              } catch (e) {
                messenger.showSnackBar(SnackBar(
                  content: Text(ErrorMessages.of(e, action: 'close the emergency')),
                  backgroundColor: AppColors.danger,
                ));
                return;
              }
              messenger.showSnackBar(SnackBar(
                content: Text(ok
                    ? 'OTP verified. The emergency is closed.'
                    : 'Invalid OTP. Ask the patient for the code on their emergency screen.'),
                backgroundColor: ok ? AppColors.successDark : AppColors.danger,
              ));
            },
            child: const Text('Verify & close'),
          ),
        ],
      ),
    );
  }

  void _promptEnterOtp(Map<String, dynamic> appointment) {
    final date = appointment['date'] ?? '';
    final time = appointment['time'] ?? '';
    final isUrgentEmergency = appointment['isUrgentEmergency'] == true;

    final err = FirestoreService.earlyStartMessage(appointment,
            what: 'consultation') ??
        _getConsultationTimeValidationError(date, time, isUrgentEmergency);
    if (err != null) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Row(
            children: [
              Icon(Icons.schedule_rounded, color: AppColors.warning, size: 28),
              SizedBox(width: 8),
              Flexible(child: Text('Time Slot Not Started')),
            ],
          ),
          content: Text(
            err,
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final TextEditingController otpController = TextEditingController();
    final appointmentId = appointment['appointmentId'] ?? '';
    final patientName = appointment['patientName'] ?? 'Patient';

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Row(
            children: [
              Icon(Icons.lock_person_rounded, color: AppTheme.primaryTeal),
              SizedBox(width: 8),
              Flexible(child: Text('Verify Patient OTP')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ask $patientName for the 4-digit consultation OTP to start meeting:',
                style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: otpController,
                keyboardType: TextInputType.number,
                maxLength: 4,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8,
                  color: AppTheme.primaryTeal,
                ),
                decoration: const InputDecoration(
                  hintText: '• • • •',
                  counterText: '',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel', style: TextStyle(color: AppColors.muted)),
            ),
            ElevatedButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final enteredOtp = otpController.text.trim();
                Navigator.pop(dialogCtx);

                final int? lateBy;
                try {
                  lateBy = await FirestoreService.startSessionWithOtp(
                    appointmentId: appointmentId,
                    enteredOtp: enteredOtp,
                  );
                } catch (e) {
                  messenger.showSnackBar(SnackBar(
                    content: Text(e.toString().replaceFirst('Exception: ', '')),
                    backgroundColor: AppColors.danger,
                  ));
                  return;
                }

                if (lateBy != null &&
                    lateBy > FirestoreService.lateArrivalGraceMinutes) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                          'Started $lateBy mins late. Professional score reduced by '
                          '${FirestoreService.latePenaltyPoints}%.'),
                      backgroundColor: AppColors.warning,
                    ),
                  );
                } else if (lateBy != null) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('OTP Verified! Consultation with $patientName started.'),
                      backgroundColor: AppTheme.primaryTeal,
                    ),
                  );
                } else {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Invalid OTP. Please check with patient.'),
                      backgroundColor: AppColors.danger,
                    ),
                  );
                }
              },
              child: const Text('Start Consultation'),
            ),
          ],
        );
      },
    );
  }

  /// End consultation. The doctor can also record that the patient paid cash.
  Future<void> _completeConsultation(String appointmentId, int fee) async {
    final messenger = ScaffoldMessenger.of(context);
    final booking = (await AppDatabase.instance
                .collection('appointments')
                .doc(appointmentId)
                .get())
            .data() ??
        const <String, dynamic>{};
    if (!mounted) return;
    // paid online already: no cash question
    if (FirestoreService.isPaidOnline(booking)) {
      final end = await showDialog<bool>(
        context: context,
        builder: (ctx) => _EndConsultationDialog(
          fee: fee,
          note: 'Paid online by the patient.',
          buttons: [
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: const Text('End consultation'),
            ),
          ],
        ),
      );
      if (end != true) return;
      await FirestoreService.completeConsultation(appointmentId);
      messenger.showSnackBar(const SnackBar(
        content: Text('Consultation completed.'),
        backgroundColor: AppColors.successDark,
      ));
      return;
    }
    if (!mounted) return;
    // null = cancelled, false = end only, true = end + cash collected
    final cash = await showDialog<bool>(
      context: context,
      builder: (ctx) => _EndConsultationDialog(
        fee: fee,
        note: 'Did you collect the fee in cash from the patient?',
        buttons: [
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.payments_rounded, size: 18),
            label: Text('Cash collected ₹$fee & end'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('End without cash'),
          ),
        ],
      ),
    );
    if (cash == null) return;
    await FirestoreService.completeConsultation(appointmentId, cashCollected: cash);
    messenger.showSnackBar(
      SnackBar(
        content: Text(cash
            ? 'Consultation completed. Cash ₹$fee recorded as collected.'
            : 'Consultation completed.'),
        backgroundColor: AppTheme.primaryTeal,
      ),
    );
  }

  /// A notification in the phone's panel was tapped: come back to the home
  /// screen, where the bell opens the notifications list.
  void _onPushTap() {
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveCenter(child: Scaffold(
      backgroundColor: AppTheme.bgLight,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Bar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: AppTheme.primaryTeal,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.medical_services_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'MyDox Doctor Portal',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textDark,
                                ),
                              ),
                              const SizedBox(height: 2),
                              // Live Location display
                              GestureDetector(
                                onTap: _fetchLiveLocation,
                                child: Row(
                                  children: [
                                    const Icon(Icons.location_on,
                                        color: AppTheme.primaryTeal, size: 14),
                                    const SizedBox(width: 2),
                                    Text(
                                      _isLoadingLocation ? 'Locating...' : _currentLocation,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.primaryTeal,
                                      ),
                                    ),
                                    if (_isLoadingLocation)
                                      const Padding(
                                        padding: EdgeInsets.only(left: 6.0),
                                        child: SizedBox(
                                          width: 10,
                                          height: 10,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.5,
                                            color: AppTheme.primaryTeal,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      Row(
                        children: [
                          NotificationBell(
                            uid: _doctor.uid,
                            collection: 'doctors',
                            forPatient: false,
                            bookings: _bookingsStream(),
                            // No new requests until approved, or while blocked
                            includeOffers: _doctor.isVerified && !_blocked,
                            iconColor: AppTheme.primaryTeal,
                            onOpenItem: () =>
                                setState(() => _selectedTabIndex = 0),
                          ),
                          IconButton(
                            icon: const Icon(Icons.logout_rounded, color: AppColors.muted),
                            tooltip: 'Sign Out',
                            onPressed: _signOut,
                          ),
                        ],
                      )
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Duties from a care physician agency: Check in / Check out
                  AgencyDutiesCard(
                    uid: _doctor.uid,
                    phone: _doctor.phone ?? _doctor.mobileNumber ?? '',
                  ),

                  // Bank account for online payments (90% of each booking)
                  PayoutSetupBanner(
                    provider: _raw,
                    email: _doctor.email,
                    phone: _doctor.phone ?? _doctor.mobileNumber ?? '',
                    name: _doctor.name,
                  ),
                  if (_blocked) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.dangerSoft,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.dangerLight),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.block_rounded, color: AppColors.danger),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Blocked until ${FirestoreService.blockedUntil(_raw)!.day}/'
                              '${FirestoreService.blockedUntil(_raw)!.month}: '
                              '${FirestoreService.absencesBeforeBlock} absents this month. '
                              'No new requests until then. Accepted bookings stay with you.',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (!_doctor.isVerified) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.warningTint,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.warningBright, width: 1.5),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.pending_actions_rounded,
                              color: AppColors.warning, size: 24),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Account Verification Pending ⏳',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.darkNavy,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Please upload and complete verification of all mandatory documents in Edit Profile. You can start receiving patient requests once your account is approved by Admin.',
                                  style: TextStyle(
                                      fontSize: 11, color: AppTheme.textMuted),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: _openEditProfile,
                            child: const Text('Upload',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primaryTeal)),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Doctor Profile Banner Header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryTeal.withValues(alpha: 0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 6),
                        )
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            SafeAvatar(
  imageUrl: _doctor.profilePicUrl,
  radius: 30,
  backgroundColor: Colors.white.withValues(alpha: 0.2),
  fallback: const Icon(
                                      Icons.person_outline_rounded,
                                      color: Colors.white,
                                      size: 36,
                                    ),
),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _doctor.name.isNotEmpty
                                        ? _doctor.name
                                        : 'Dr. Elizabeth Amelia',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          _doctor.category ?? 'Specialist',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      if (_doctor.experience != null && _doctor.experience!.isNotEmpty) ...[
                                        Text(
                                          _experienceLabel(_doctor.experience!),
                                          style: const TextStyle(
                                              color: Colors.white70, fontSize: 12),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, color: Colors.white),
                              tooltip: 'Edit Profile',
                              onPressed: _openEditProfile,
                            )
                          ],
                        ),

                        const SizedBox(height: 16),
                        const Divider(color: Colors.white24),
                        const SizedBox(height: 8),

                        Row(
                          children: [
                            const Icon(Icons.local_hospital_outlined,
                                color: Colors.white70, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _doctor.hospital ?? 'City Hospital',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 13),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 6),

                        Row(
                          children: [
                            const Icon(Icons.phone_android_outlined,
                                color: Colors.white70, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              _doctor.mobileNumber ?? 'N/A',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),


                  // Calendar Schedule Management Banner Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.3)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 10,
                        )
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryTeal.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.calendar_month_rounded,
                            color: AppTheme.primaryTeal,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Manage Your Availability',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Set your available dates and time slots.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _openScheduleManager,
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(0, 44),
                            ),
                            child: const Text('Manage Schedule'),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Availability Switch Card
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: _isAvailable ? AppColors.success : AppColors.muted,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _isAvailable ? 'Online & Accepting Patients' : 'Offline / On Break',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: AppTheme.textDark,
                              ),
                            ),
                          ],
                        ),
                        Switch(
                          value: _isAvailable,
                          activeColor: AppTheme.primaryTeal,
                          onChanged: _setOnline,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Overview Stats Stream
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _bookingsStream(),
                    builder: (context, snapshot) {
                      // Only this doctor's own bookings (not open requests
                      // broadcast to all doctors)
                      final bookings = (snapshot.data ?? [])
                          .where((b) => b['doctorUid'] == _doctor.uid)
                          .toList();
                      final totalPatients = bookings
                          .where((b) => b['status'] == 'Completed')
                          .map((b) => b['patientUid'])
                          .toSet()
                          .length;
                      final completedCount = bookings.where((b) => b['status'] == 'Completed').length;
                      // Live: recalculated whenever a booking changes
                      final earnings30d = FirestoreService.earningsLast30Days(
                          bookings, _doctor.uid);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Today\'s Summary',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textDark,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _statGrid([
                                _buildStatCard(
                                  title: 'Patients',
                                  value: '$totalPatients',
                                  icon: Icons.people_alt_outlined,
                                  color: AppColors.primaryDark,
                                ),
                                _buildStatCard(
                                  title: 'Consultations',
                                  value: '$completedCount',
                                  icon: Icons.check_circle_outline_rounded,
                                  color: AppColors.accent,
                                ),
                                _buildStatCard(
                                  // Average of all patient ratings, 0/5 until rated
                                  title: 'Overall rating',
                                  value: FirestoreService.ratingLabel(_raw),
                                  icon: Icons.star_border_rounded,
                                  color: AppColors.warning,
                                ),
                                _buildStatCard(
                                  title: 'Earnings (30d)',
                                  value: '₹${earnings30d.round()}',
                                  icon: Icons.currency_rupee_rounded,
                                  color: AppColors.successDark,
                                ),
                                // Drops 5 points per home visit started 30+ mins late
                                _buildStatCard(
                                  title: 'Prof. score',
                                  value:
                                      '${FirestoreService.professionalScoreOf(_raw)}/100',
                                  icon: Icons.verified_user_outlined,
                                  color: AppTheme.primaryTeal,
                                ),
                              ]),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // Segmented Control (Upcoming vs Completed vs My Patients)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.line,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Row(
                      children: [
                        _buildDoctorSegmentTab(0, 'Upcoming'),
                        _buildDoctorSegmentTab(1, 'Completed'),
                        _buildDoctorSegmentTab(2, 'My Patients'),
                      ],
                    ),
                  ),

                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AppointmentCalendarScreen(
                              uid: _doctor.uid, forDoctor: true),
                        ),
                      ),
                      icon: const Icon(Icons.calendar_month_rounded, size: 18),
                      label: const Text('Calendar view'),
                    ),
                  ),

                  // Consultations List Stream for Doctor
                  if (_selectedTabIndex == 2)
                    StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _streams.get('patients', () => FirestoreService.getDoctorAttendedPatientsStream(_doctor.uid)),
                      builder: (context, pSnap) {
                        if (pSnap.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(20.0),
                              child: CircularProgressIndicator(color: AppTheme.primaryTeal),
                            ),
                          );
                        }

                        final patients = pSnap.data ?? [];

                        if (patients.isEmpty) {
                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: AppColors.line),
                            ),
                            child: Column(
                              children: [
                                Icon(Icons.people_outline_rounded,
                                    size: 48, color: AppColors.lineStrong),
                                const SizedBox(height: 12),
                                const Text(
                                  'No Attended Patients Yet',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textDark,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Patients you have consulted with will appear here for direct messaging.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                ),
                              ],
                            ),
                          );
                        }

                        return Column(
                          children: patients.map((p) {
                            final pUid = p['patientUid'] ?? '';
                            final pName = p['patientName'] ?? 'Patient';
                            final lastDate = p['lastConsultation'] ?? '';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.03),
                                    blurRadius: 10,
                                  )
                                ],
                              ),
                              child: Row(
                                children: [
                                  const CircleAvatar(
                                    radius: 22,
                                    backgroundColor: AppTheme.pastelBlue,
                                    child: Icon(Icons.person, color: AppTheme.primaryTeal),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          pName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: AppTheme.textDark,
                                          ),
                                        ),
                                        Text(
                                          'Last Consultation: $lastDate',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: () => _openChatWithPatient(pUid, pName),
                                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                                    label: const Text('Chat'),
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: const Size(80, 38),
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      },
                    )
                  else
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _bookingsStream(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return LoadErrorView(error: snapshot.error, what: 'your bookings');
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20.0),
                            child: CircularProgressIndicator(color: AppTheme.primaryTeal),
                          ),
                        );
                      }

                      final allBookings = snapshot.data ?? [];

                      final bool isDoctorBusyInConsultation = allBookings.any((b) => b['status'] == 'In Progress');

                      if (!isDoctorBusyInConsultation) {
                        // Detect Emergency & Doctor Assignment Requests
                        final pendingEmergency = allBookings.firstWhere(
                          (b) =>
                              (b['status'] == 'Pending Doctor Assignment' ||
                                  b['status'] == 'Pending Emergency' ||
                                  b['status'] == 'Broadcasted') &&
                              b['status'] != 'Confirmed' &&
                              b['status'] != 'Completed' &&
                              b['status'] != 'Pending Ambulance Dispatch',
                          orElse: () => {},
                        );

                        if (pendingEmergency.isNotEmpty) {
                          final pendingId = pendingEmergency['appointmentId'] ?? '';
                          if (pendingId != _lastAlertAppointmentId) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _triggerEmergencyPopup(pendingEmergency);
                            });
                          }
                        }

                        // Detect Home Visit Requests for Doctor Alert Dialog Popup
                        final pendingHomeVisit = allBookings.firstWhere(
                          (b) =>
                              (b['status'] == 'Pending Home Visit' || b['status'] == 'Broadcasted') &&
                              b['consultationType'] == 'Home Visit',
                          orElse: () => {},
                        );

                        if (pendingHomeVisit.isNotEmpty) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _triggerHomeVisitPopup(pendingHomeVisit);
                          });
                        }
                      }

                      // Filter into Upcoming vs Completed lists
                      // Upcoming: today + tomorrow, slots that have not ended,
                      // earliest first (10-11 before 12-1). Urgent / SOS stay
                      // while active.
                      final nowTs = IstClock.now();
                      final upcomingBookings = allBookings
                          .where((b) => AppointmentRules.isUpcoming(b, now: nowTs))
                          .toList()
                        ..sort(AppointmentRules.compareByStart);

                      // Completed: finished, plus slots that passed unattended
                      final completedBookings = allBookings
                          .where((b) => AppointmentRules.isHistory(b, now: nowTs))
                          .toList()
                        ..sort(AppointmentRules.compareByStartDesc);

                      final displayList =
                          _selectedTabIndex == 0 ? upcomingBookings : completedBookings;

                      if (displayList.isEmpty) {
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: AppColors.line),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                _selectedTabIndex == 0
                                    ? Icons.event_available_outlined
                                    : Icons.task_alt_rounded,
                                size: 48,
                                color: AppColors.lineStrong,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _selectedTabIndex == 0
                                    ? 'No Upcoming Patient Consultations'
                                    : 'No Completed Consultation History',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textDark,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _selectedTabIndex == 0
                                    ? 'Your scheduled patient appointments will appear here.'
                                    : 'Completed patient consultations will appear here.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                              ),
                            ],
                          ),
                        );
                      }

                      final shown = displayList.take(_shownBookings);
                      final more = displayList.length - shown.length;
                      return Column(
                        children: [
                          ...shown.map((item) {
                          final appointmentId = item['appointmentId'] ?? '';
                          final patientUid = item['patientUid'] ?? '';
                          final patientName = item['patientName'] ?? 'Patient';
                          final time = item['time'] ?? '10:00 AM';
                          final date = item['date'] ?? '';
                          final mode = item['consultationType'] ?? 'Clinic/Visit';
                          final status = item['status'] ?? 'Confirmed';
                          final bool missed = AppointmentRules.isMissed(item);
                          // done or missed: no OTP / navigation; chat only for 24 h
                          final bool finished = AppointmentRules.isHistory(item);
                          // chat: greyed out until the consultation ends
                          const bool chatShown = true;
                          final isUrgent = item['isUrgentEmergency'] == true;
                          final int price = toNum(item['price'])?.toInt() ?? 0;

                          final startTime = item['startTimeFormatted'] ?? '';
                          final endTime = item['endTimeFormatted'] ?? '';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: isUrgent
                                  ? Border.all(color: AppColors.danger, width: 1.5)
                                  : null,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 10,
                                )
                              ],
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 22,
                                      backgroundColor: isUrgent
                                          ? AppColors.dangerSoft
                                          : AppTheme.primaryTeal.withValues(alpha: 0.1),
                                      child: Icon(
                                        isUrgent ? Icons.warning_amber_rounded : Icons.person,
                                        color: isUrgent ? AppColors.danger : AppTheme.primaryTeal,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                patientName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
                                                  color: AppTheme.textDark,
                                                ),
                                              ),
                                              if (isUrgent) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                      horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.dangerSoft,
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: const Text(
                                                    'URGENT (+20%)',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                      color: AppColors.danger,
                                                    ),
                                                  ),
                                                )
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${AppointmentRules.modeLabel(mode)} • $date @ $time • ₹$price',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppTheme.textMuted,
                                            ),
                                          ),
                                          if (startTime.isNotEmpty || endTime.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              '${startTime.isNotEmpty ? "Start: $startTime" : ""}${endTime.isNotEmpty ? " • End: $endTime" : ""}',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: AppTheme.primaryTeal,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: status == 'In Progress'
                                            ? AppColors.warningTint
                                            : status == 'Completed'
                                                ? AppColors.primarySoft
                                                : AppColors.successTint,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        missed ? 'Not attended' : status,
                                        style: TextStyle(
                                          color: status == 'In Progress'
                                              ? AppColors.warningDeep
                                              : status == 'Completed'
                                                  ? AppColors.primaryDark
                                                  : AppColors.successDeep,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 14),

                                if (item['runningLateMinutes'] != null &&
                                    status == 'Confirmed')
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(
                                      'You told the patient: about ${item['runningLateMinutes']} mins late',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.orange),
                                    ),
                                  ),
                                if (FirestoreService.canTellRunningLate(item))
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                      onPressed: () => _showRunningLateSheet(item),
                                      icon: const Icon(Icons.schedule_send_outlined,
                                          size: 16),
                                      label: const Text('Running late'),
                                    ),
                                  ),

                                // Doctor Action Buttons: "Chat with Patient" & "Start / Video / Complete Consultation"
                                if (!finished || chatShown)
                                Row(
                                  children: [
                                    // Chat with Patient
                                    if (chatShown) Expanded(
                                      child: ChatButton(
                                        booking: item,
                                        compact: true,
                                        viewerUid: _doctor.uid,
                                        onChat: () => _openChatWithPatient(patientUid, patientName),
                                      ),
                                    ),
                                    if (chatShown && !finished) const SizedBox(width: 8),

                                    // Start Consultation (Enter OTP) or Video Call or Complete Consultation
                                    if (finished)
                                      const SizedBox.shrink()
                                    else if (mode == SosService.type)
                                      SosService.doctorCanClose(item)
                                          ? Expanded(
                                              child: ElevatedButton.icon(
                                                onPressed: () => _promptSosPatientOtp(item),
                                                icon: const Icon(Icons.key_rounded, size: 16),
                                                label: const Text('Patient OTP'),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: AppColors.danger,
                                                  minimumSize: const Size(0, 40),
                                                ),
                                              ),
                                            )
                                          : const SizedBox.shrink()
                                    else if (status == 'Confirmed' || status == 'URGENT' || status == 'Pending Emergency' || status == 'Broadcasted' || status == 'Pending Home Visit')
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: () => _promptEnterOtp(item),
                                          icon: const Icon(Icons.key_rounded, size: 16),
                                          label: const Text('Enter OTP'),
                                          style: ElevatedButton.styleFrom(
                                            minimumSize: const Size(0, 40),
                                          ),
                                        ),
                                      )
                                    else if (status == 'In Progress' && mode == 'Online')
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: () => _openVideoCall(patientName,
                                              patientUid: patientUid,
                                              appointmentId: (item['appointmentId'] ?? '').toString(),
                                              booking: item),
                                          icon: const Icon(Icons.videocam_rounded, size: 16),
                                          label: const Text('Join Video Call'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.brand,
                                            minimumSize: const Size(0, 40),
                                          ),
                                        ),
                                      )
                                    else if (status == 'In Progress')
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: () => _completeConsultation(appointmentId, toNum(item['price'])?.round() ?? 0),
                                          icon: const Icon(Icons.check_circle_rounded, size: 16),
                                          label: const Text('End Consultation'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.successDark,
                                            minimumSize: const Size(0, 40),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),

                                // Cash status for finished consultations
                                if (status == 'Completed' && mode != SosService.type) ...[
                                  const SizedBox(height: 8),
                                  if (FirestoreService.isPaidOnline(item))
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        'Paid online ₹${toNum(item['price'])?.round() ?? 0}',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.successDark),
                                      ),
                                    )
                                  else if (item['cashCollected'] == true)
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        'Cash collected ₹${toNum(item['price'])?.round() ?? 0}',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.successDark),
                                      ),
                                    )
                                  else
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: () async {
                                          final messenger = ScaffoldMessenger.of(context);
                                          final ok = await FirestoreService
                                              .markCashCollected(appointmentId);
                                          messenger.showSnackBar(SnackBar(
                                            content: Text(ok
                                                ? 'Cash recorded as collected.'
                                                : 'This booking was already paid online.'),
                                            backgroundColor: ok
                                                ? AppColors.successDark
                                                : AppColors.danger,
                                          ));
                                        },
                                        icon: const Icon(Icons.payments_rounded, size: 16),
                                        label: const Text('Mark cash collected'),
                                      ),
                                    ),
                                ],

                                // Emergency Help: arrival limit + navigate to the assigned hospital
                                if (mode == SosService.type) ...[
                                  const SizedBox(height: 8),
                                  for (final line in SosService.timingLines(item)
                                      .where((l) => l.startsWith('Doctor')))
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(line,
                                          style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.darkNavy)),
                                    ),
                                  if (item['doctorReachedAt'] == null &&
                                      (item['doctorOtp'] ?? '').toString().isNotEmpty &&
                                      status != 'Completed')
                                    Container(
                                      width: double.infinity,
                                      margin: const EdgeInsets.only(top: 6),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: AppColors.dangerSoft,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: AppColors.danger.withValues(alpha: 0.5)),
                                      ),
                                      child: Column(
                                        children: [
                                          const Text('YOUR ARRIVAL OTP',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.danger)),
                                          Text(item['doctorOtp'].toString(),
                                              style: const TextStyle(
                                                  fontSize: 26,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 6,
                                                  color: AppColors.danger)),
                                          const Text(
                                              'Share this with the hospital when you reach',
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: AppTheme.textMuted)),
                                        ],
                                      ),
                                    ),
                                ],
                                // Normal clinic visit: navigate to the doctor's hospital
                                if (!finished &&
                                    (item['assignedHospitalName'] ?? '').toString().isEmpty &&
                                    (item['hospital'] ?? '').toString().isNotEmpty &&
                                    mode != 'Home Visit' &&
                                    mode != 'Online' &&
                                    mode != SosService.type) ...[
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: () => MapsNavigation.toHospitalWithHint(
                                        context,
                                        item['hospital'].toString(),
                                        lat: toNum(item['doctorLat'])?.toDouble(),
                                        lng: toNum(item['doctorLng'])?.toDouble(),
                                      ),
                                      icon: const Icon(Icons.local_hospital_rounded, size: 16),
                                      label: Text('Navigate to ${item['hospital']}'),
                                    ),
                                  ),
                                ],
                                if (!finished && (item['assignedHospitalName'] ?? '').toString().isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.brand,
                                        minimumSize: const Size(0, 40),
                                      ),
                                      onPressed: () => MapsNavigation.toHospital(
                                        item['assignedHospitalName'].toString(),
                                        lat: toNum(item['assignedHospitalLat'])?.toDouble(),
                                        lng: toNum(item['assignedHospitalLng'])?.toDouble(),
                                      ),
                                      icon: const Icon(Icons.local_hospital_rounded, size: 16),
                                      label: Text('Navigate to ${item['assignedHospitalName']}'),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }),
                          if (more > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: OutlinedButton.icon(
                                onPressed: () => setState(
                                    () => _shownBookings += _pageSize),
                                icon: const Icon(Icons.expand_more_rounded),
                                label: Text(
                                    'Show more ($more more)'),
                                style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 44)),
                              ),
                            ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                ],
              ),
            ),
          ],
        ),
      ),
    ));
  }

  Widget _buildDoctorSegmentTab(int index, String label) {
    final isSelected = _selectedTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _selectedTabIndex = index;
          _shownBookings = _pageSize;
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryTeal : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.white : AppTheme.textMuted,
            ),
          ),
        ),
      ),
    );
  }

  /// "20" -> "20 Years of Experience" ("1 Year ..."); text kept as typed.
  static String _experienceLabel(String raw) {
    final t = raw.trim();
    final n = int.tryParse(t.replaceAll(RegExp(r'\s*(yrs?|years?)\.?$', caseSensitive: false), ''));
    if (n == null) return t;
    return n == 1 ? '1 Year of Experience' : '$n Years of Experience';
  }

  /// Summary cards in one even grid: same width and height on every row
  /// (3 per row on phones, all 5 in a row on wide screens).
  Widget _statGrid(List<Widget> cards) => LayoutBuilder(builder: (context, c) {
        const gap = 12.0;
        final cols = c.maxWidth >= 640 ? cards.length : 3;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards)
              SizedBox(width: w, height: 118, child: card),
          ],
        );
      });

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              title,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "End consultation?": the fee in a box, one line of explanation, then the
/// choices as full-width buttons one under the other and Cancel last.
class _EndConsultationDialog extends StatelessWidget {
  final Object fee;
  final String note;
  final List<Widget> buttons;

  const _EndConsultationDialog({
    required this.fee,
    required this.note,
    required this.buttons,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      title: const Text('End consultation?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primaryTint,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.primaryBorder),
              ),
              child: Row(children: [
                const Expanded(
                  child: Text('Consultation fee',
                      style: TextStyle(color: AppColors.textBody)),
                ),
                Text('₹$fee',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary)),
              ]),
            ),
            const SizedBox(height: 14),
            Text(note,
                style: const TextStyle(height: 1.4, color: AppColors.textBody)),
            const SizedBox(height: 18),
            for (final b in buttons) ...[
              SizedBox(height: 48, child: b),
              const SizedBox(height: 10),
            ],
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.muted)),
            ),
          ],
        ),
      ),
    );
  }
}
