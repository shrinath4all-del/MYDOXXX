import '../../services/app_database.dart';
import '../../services/lab_device.dart';
import '../../services/push_service.dart';
import '../../utils/safe_cast.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/sos_service.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../auth/login_screen.dart';
import '../patient/book_doctor_screen.dart';
import '../patient/book_therapist_screen.dart';
import '../patient/my_bookings_screen.dart';
import 'edit_hospital_profile_screen.dart';
import '../../utils/error_messages.dart';
import '../../utils/stream_cache.dart';
import '../../widgets/booked_care_physicians_card.dart';
import '../../services/care_physician_service.dart';
import '../../utils/responsive.dart';
import '../../widgets/verification_gate.dart';
import '../shifts/nurse_shift_board_screen.dart';
import '../shifts/technician_shift_board_screen.dart';
import '../shifts/shift_board_screen.dart';
import '../../constants/app_colors.dart';
import '../../widgets/notification_bell.dart';
import '../../services/role_notifications.dart';
import '../../constants/app_strings.dart';

class HospitalHomeScreen extends StatefulWidget {
  final UserModel hospital;

  const HospitalHomeScreen({
    super.key,
    required this.hospital,
  });

  @override
  State<HospitalHomeScreen> createState() => _HospitalHomeScreenState();
}

class _HospitalHomeScreenState extends State<HospitalHomeScreen> {
  // Live data connections kept open across redraws
  final StreamCache _streams = StreamCache();

  final AuthService _authService = AuthService();
  late UserModel _hospital;
  // Live profile listener; cancelled when the screen closes (e.g. logout)
  StreamSubscription? _profileSub;
  String? _lastAlertAppointmentId;
  int _selectedHospitalTab = 0;

  Position? _hospitalPos;
  String _hospitalLiveLocation = 'Locating Hospital GPS...';
  bool _loadingHospitalLoc = true;

  @override
  void initState() {
    super.initState();
    PushService.registerForUser(widget.hospital.uid);
    _hospital = widget.hospital;
    _fetchHospitalLiveLocation();
    // re-check the widening radius even when no request changes
    _radiusTick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
    if (_hospital.locationLocked != true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _offerToLockLocation());
    }
    _profileSub =
        FirestoreService.getUserStream(_hospital.uid, 'hospital').listen((doc) {
      if (mounted && doc.exists && doc.data() != null) {
        setState(() {
          _hospital = UserModel.fromMap(doc.data()!, _hospital.uid);
        });
      }
    });
  }

  @override
  void dispose() {
    _radiusTick?.cancel();
    _profileSub?.cancel();
    super.dispose();
  }

  bool _askedToLock = false;
  Timer? _radiusTick;

  /// Hospitals registered before locations were fixed: set it once, here.
  Future<void> _offerToLockLocation() async {
    if (_askedToLock || _hospital.locationLocked == true || !mounted) return;
    _askedToLock = true;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Set your hospital location'),
        content: const Text(
          'Please do this while you are at the hospital. Your current GPS position becomes the hospital\'s fixed location, used to match patients within 4 / 6 / 8 km.\n\nIt cannot be changed afterwards.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Later', style: TextStyle(color: AppColors.muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Set location now'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      var perm = await LabLocation.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await LabLocation.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw Exception('Location permission is required.');
      }
      final pos = await LabLocation.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 15),
        ),
      );
      final area = await LocationService.getCurrentLocation();
      await AppDatabase.instance
          .collection('hospitals')
          .doc(_hospital.uid)
          .set({
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'locationName': area,
        'locationLocked': true,
        'locationCapturedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
      messenger.showSnackBar(const SnackBar(
        content: Text('Hospital location saved and fixed.'),
        backgroundColor: AppColors.success,
      ));
    } catch (e) {
      _askedToLock = false; // ask again next time
      messenger.showSnackBar(SnackBar(
        content: Text('Could not set the location: ${e.toString().replaceFirst('Exception: ', '')}'),
        backgroundColor: AppColors.danger,
      ));
    }
  }

  Future<void> _fetchHospitalLiveLocation() async {
    // Fixed location: never overwritten by the phone's current position
    if (_hospital.locationLocked == true) {
      if (mounted) {
        setState(() {
          _hospitalLiveLocation = _hospital.city ?? _hospital.homeAddress ?? 'Pune';
          _loadingHospitalLoc = false;
        });
      }
      return;
    }
    try {
      final pos = await LabLocation.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
      final area = await LocationService.getCurrentLocation();

      // (not saved: the location only becomes the hospital's when the
      // hospital confirms it in "Set your hospital location")

      if (mounted) {
        setState(() {
          _hospitalPos = pos;
          _hospitalLiveLocation = area;
          _loadingHospitalLoc = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _hospitalLiveLocation =
              _hospital.city ?? _hospital.homeAddress ?? 'Pune';
          _loadingHospitalLoc = false;
        });
      }
    }
  }

  Future<void> _openEditProfile() async {
    final updated = await Navigator.of(context).push<UserModel>(
      MaterialPageRoute(
        builder: (_) => EditHospitalProfileScreen(hospital: _hospital),
      ),
    );

    if (updated != null && mounted) {
      setState(() => _hospital = updated);
    }
  }

  Future<void> _openBookDoctor() async {
    if (!await ensureVerified(context, _hospital.isVerified)) return;
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookDoctorScreen(
          patient: _asBooker,
          initialLocationArea: _hospital.city ?? 'Wakad',
        ),
      ),
    );
  }

  /// The hospital as the requester of a service. It carries the hospital's
  /// verification: the booking screens turn an unverified one away.
  UserModel get _asBooker => UserModel(
        uid: _hospital.uid,
        email: _hospital.email,
        role: 'hospital',
        name: _hospital.name,
        phone: _hospital.mobileNumber ?? _hospital.phone,
        homeAddress: _hospital.homeAddress,
        isVerified: _hospital.isVerified,
      );

  Future<void> _openBookTherapist() async {
    if (!await ensureVerified(context, _hospital.isVerified)) return;
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BookTherapistScreen(patient: _asBooker)));
  }

  /// Everything this hospital booked (doctors, nurses, technicians, therapists).
  void _openMyBookings() => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MyBookingsScreen(patient: _asBooker)));

  Widget _serviceTile(String label, IconData icon, Color iconColor, Color bg,
          VoidCallback onTap) =>
      Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 88,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(20),
              border: bg == Colors.white ? Border.all(color: AppColors.lineStrong) : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: iconColor, size: 26),
                const SizedBox(height: 6),
                Text(label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11.5,
                        color: AppTheme.darkNavy)),
              ],
            ),
          ),
        ),
      );

  void _showSetHospitalPreferredDoctorsDialog() async {
    final doctorsSnap = await AppDatabase.instance
        .collection('doctors')
        .where('isVerified', isEqualTo: true)
        .get();

    if (!mounted) return;

    final docList = doctorsSnap.docs.map((d) {
      final map = d.data();
      map['uid'] = d.id;
      return map;
    }).toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Row(
              children: [
                Icon(Icons.star_rounded, color: AppColors.primary, size: 28),
                SizedBox(width: 8),
                Flexible(child: Text('On-Call Doctors (2 per Category)')),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select up to 2 preferred doctors for each category:',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                  const SizedBox(height: 16),
                  ...['General Physician', 'Cardiologist', 'Pediatrician', 'Neurologist', 'Dermatologist', 'Orthopedic'].map((cat) {
                    final List<String> currentFavNames =
                        _hospital.hospitalPreferredDoctorNames?[cat] ?? [];

                    final categoryDocs = docList.where((d) =>
                        (d['category'] as String?)?.toLowerCase() == cat.toLowerCase()).toList();

                    return Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primaryTint,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.primaryBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(cat, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.darkNavy)),
                          const SizedBox(height: 4),
                          Text('Preferred On-Call: ${currentFavNames.isEmpty ? "None Selected" : currentFavNames.join(", ")}',
                              style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          ...categoryDocs.map((doc) {
                            final name = doc['name'] ?? 'Doctor';
                            final uid = doc['uid'] ?? '';

                            final List<String> currentUids =
                                _hospital.hospitalPreferredDoctors?[cat] ?? [];
                            final bool isSelected = currentUids.contains(uid);

                            return CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              activeColor: AppColors.primary,
                              title: Text(name, style: const TextStyle(fontSize: 12)),
                              value: isSelected,
                              onChanged: (val) async {
                                final List<String> newUids = List<String>.from(currentUids);
                                final List<String> newNames = List<String>.from(currentFavNames);

                                if (val == true) {
                                  if (newUids.length >= 2) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('You can select a maximum of 2 preferred doctors per category.'),
                                        backgroundColor: AppColors.warning,
                                      ),
                                    );
                                    return;
                                  }
                                  newUids.add(uid);
                                  newNames.add(name);
                                } else {
                                  newUids.remove(uid);
                                  newNames.remove(name);
                                }

                                await FirestoreService.saveHospitalPreferredDoctors(
                                  hospitalUid: _hospital.uid,
                                  category: cat,
                                  doctorUids: newUids,
                                  doctorNames: newNames,
                                );

                                final updatedModel = await AuthService().getCurrentUserModel();
                                if (updatedModel != null && mounted) {
                                  setState(() => _hospital = updatedModel);
                                  setDialogState(() {});
                                }
                              },
                            );
                          }),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _signOut() async {
    await _authService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _showHospitalSosPopup(Map<String, dynamic> appointment) {
    final id = appointment['appointmentId'] ?? '';
    if (id == _lastAlertAppointmentId) return;

    _lastAlertAppointmentId = id;
    final patientName = appointment['patientName'] ?? 'Patient';
    final patientPhone = appointment['patientPhone'] ?? 'N/A';
    final locationName = appointment['locationName'] ?? 'Patient Area';
    final category = appointment['emergencyCategory'] ?? appointment['doctorCategory'] ?? 'General Emergency';
    final bool requiresAmbulance = appointment['requiresAmbulance'] ?? true;
    final Map<String, dynamic> qAnswers =
        Map<String, dynamic>.from(appointment['questionAnswers'] ?? {});

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          title: const Row(
            children: [
              Icon(Icons.local_hospital_rounded,
                  color: AppColors.danger, size: 28),
              SizedBox(width: 8),
              Flexible(child: Text('🚨 INCOMING SOS EMERGENCY')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$patientName has triggered a $category Emergency Alert near your hospital.',
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.dangerSoft,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.danger),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(child: const Text('Emergency Category:',
                            style: TextStyle(fontSize: 12, color: AppColors.muted))),
                        Flexible(child: Text(category,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.danger), textAlign: TextAlign.right)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(child: const Text('Transport Choice:',
                            style: TextStyle(fontSize: 12, color: AppColors.muted))),
                        Flexible(child: Text(
                            requiresAmbulance
                                ? '🚑 Requires Ambulance'
                                : '🚗 Patient Driving',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.darkNavy), textAlign: TextAlign.right)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(child: const Text('Patient:',
                            style: TextStyle(fontSize: 12, color: AppColors.muted))),
                        Flexible(child: Text(patientName,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(child: const Text('Phone:',
                            style: TextStyle(fontSize: 12, color: AppColors.muted))),
                        Flexible(child: Text(patientPhone,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Patient Location:',
                            style: TextStyle(fontSize: 12, color: AppColors.muted)),
                        Expanded(
                          child: Text(
                            locationName,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.danger),
                          ),
                        ),
                      ],
                    ),
                    if (qAnswers.isNotEmpty) ...[
                      const Divider(height: 16),
                      const Text('Symptoms / Questionnaire Answers:',
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
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogCtx);
                // Only this hospital drops out; others can still accept.
                await SosService.declineHospital(id, _hospital.uid);
              },
              child:
                  const Text('Decline', style: TextStyle(color: AppColors.muted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger),
              onPressed: () async {
                Navigator.pop(dialogCtx);

                final String cat = appointment['emergencyCategory'] ??
                    appointment['doctorCategory'] ??
                    'General Physician';

                final List<String> prefDocs =
                    _hospital.hospitalPreferredDoctors?[cat] ?? [];

                // STEP 1 COMPLETE: first hospital to accept is assigned -> Step 2
                final bool won = await SosService.acceptHospital(
                  appointmentId: id,
                  hospitalUid: _hospital.uid,
                  hospitalName: _hospital.name,
                  hospitalLat:
                      _hospitalPos?.latitude ?? _hospital.latitude ?? LocationService.defaultLat,
                  hospitalLng:
                      _hospitalPos?.longitude ?? _hospital.longitude ?? LocationService.defaultLng,
                  preferredDoctorUids: prefDocs,
                );

                if (!mounted) return;
                if (!won) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text(
                        'This emergency was already accepted by another hospital or has closed.'),
                    backgroundColor: AppColors.warning,
                  ));
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(prefDocs.isNotEmpty
                        ? 'SOS Accepted! Request sent to On-Call Preferred Doctors first.'
                        : 'SOS Accepted for $patientName! Emergency request sent to doctors.'),
                    backgroundColor: AppColors.successDark,
                  ),
                );
              },
              child: const Text('Accept SOS Emergency'),
            ),
          ],
        );
      },
    );
  }

  void _promptHospitalOtp(Map<String, dynamic> item, {bool forDoctor = false}) {
    final otpController = TextEditingController();
    final id = (item['appointmentId'] ?? '').toString();
    final patientName = item['patientName'] ?? 'Patient';
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.lock_person_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            Flexible(child: Text(forDoctor ? 'Doctor Arrival OTP' : 'Patient Arrival OTP')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              forDoctor
                  ? 'Ask the doctor for the 4-digit arrival OTP:'
                  : 'Ask $patientName for the 4-digit hospital OTP to confirm arrival:',
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
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final otp = otpController.text.trim();
              Navigator.pop(dialogCtx);
              final ok = forDoctor
                  ? await SosService.verifyDoctorArrival(
                      appointmentId: id,
                      enteredOtp: otp,
                      hospitalUid: _hospital.uid,
                    )
                  : await SosService.verifyHospitalArrival(
                      appointmentId: id,
                      enteredOtp: otp,
                      hospitalUid: _hospital.uid,
                    );
              messenger.showSnackBar(SnackBar(
                content: Text(ok
                    ? (forDoctor
                        ? 'Doctor arrival confirmed.'
                        : 'Arrival confirmed. The ambulance is now free and the doctor can start treatment.')
                    : (forDoctor
                        ? 'Invalid doctor OTP.'
                        : 'Invalid OTP, or the patient has not been picked up yet.')),
                backgroundColor: ok ? AppColors.successDark : AppColors.danger,
              ));
            },
            child: const Text('Confirm Arrival'),
          ),
        ],
      ),
    );
  }

  /// Technicians for the hospital (lab, X-Ray, ECG, EEG, OT…): a locum for
  /// a shift, or a full-time team, the same way as nurses and physicians.
  Future<void> _openTechnicianBoard() async {
    if (!await ensureVerified(context, _hospital.isVerified)) return;
    if (!mounted) return;
    final area = (_hospital.preferredLocations?.isNotEmpty ?? false)
        ? _hospital.preferredLocations!.first
        : (_hospital.city ?? '');
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TechnicianShiftBoardScreen(
        postedBy: 'hospital',
        posterId: _hospital.uid,
        posterName: _hospital.name,
        hospitals: Stream.value([
          (id: _hospital.uid, name: _hospital.name, area: area),
        ]),
      ),
    ));
  }

  /// Nurses for the hospital: a locum for a shift, or a full-time team.
  Future<void> _openNurseBoard() async {
    if (!await ensureVerified(context, _hospital.isVerified)) return;
    if (!mounted) return;
    final area = (_hospital.preferredLocations?.isNotEmpty ?? false)
        ? _hospital.preferredLocations!.first
        : (_hospital.city ?? '');
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => NurseShiftBoardScreen(
        postedBy: 'hospital',
        posterId: _hospital.uid,
        posterName: _hospital.name,
        hospitals: Stream.value([
          (id: _hospital.uid, name: _hospital.name, area: area),
        ]),
      ),
    ));
  }

  Future<void> _openShiftBoard() async {
    if (!await ensureVerified(context, _hospital.isVerified)) return;
    if (!mounted) return;
    final area = (_hospital.preferredLocations?.isNotEmpty ?? false)
        ? _hospital.preferredLocations!.first
        : (_hospital.city ?? '');
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ShiftBoardScreen(
        postedBy: 'hospital',
        posterId: _hospital.uid,
        posterName: _hospital.name,
        hospitals: Stream.value([
          (id: _hospital.uid, name: _hospital.name, area: area),
        ]),
      ),
    ));
  }

  /// Bell: emergencies this hospital accepted and care physicians booked
  /// for its shifts.
  Stream<List<Map<String, String>>> _notificationEvents() => combineLatest2(
        AppDatabase.instance
            .collection('appointments')
            .where('assignedHospitalUid', isEqualTo: _hospital.uid)
            .snapshots()
            .map((s) => [for (final d in s.docs) d.data()]),
        CarePhysicianService.posterShiftsStream(_hospital.uid),
        (List<Map<String, dynamic>> sos, List<Map<String, dynamic>> shifts) => [
          ...RoleNotifications.hospitalSos(sos, _hospital.uid),
          ...RoleNotifications.hospitalShifts(shifts, DateTime.now()),
        ]..sort((a, b) => b['at']!.compareTo(a['at']!)),
      );

  @override
  Widget build(BuildContext context) {
    return ResponsiveCenter(child: Scaffold(
      backgroundColor: AppTheme.bgLight,
      appBar: AppBar(
        title: const Text('Hospital Control Desk'),
        actions: [
          // Post per-shift duties and full-time jobs for care physicians
          IconButton(
            tooltip: 'Shifts & jobs',
            icon: const Icon(Icons.work_outline_rounded,
                color: AppTheme.primaryTeal),
            onPressed: _openShiftBoard,
          ),
          NotificationBell(
            uid: _hospital.uid,
            collection: 'hospitals',
            forPatient: false,
            events: _streams.get('bell', _notificationEvents),
            iconColor: AppColors.ink,
            onOpenItem: () {},
          ),
          IconButton(
            tooltip: AppStrings.logout,
            icon: const Icon(Icons.logout_rounded, color: AppColors.muted),
            onPressed: _signOut,
          )
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.navy, AppColors.primary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const CircleAvatar(
                          radius: 28,
                          backgroundColor: Colors.white24,
                          child: Icon(Icons.local_hospital_rounded,
                              color: Colors.white, size: 32),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _hospital.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'City: ${_hospital.city ?? "Pune"} • Emergency Desk',
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 13),
                              ),
                              const SizedBox(height: 2),
                              GestureDetector(
                                onTap: _fetchHospitalLiveLocation,
                                child: Row(
                                  children: [
                                    const Icon(Icons.my_location_rounded,
                                        color: Colors.white70, size: 14),
                                    const SizedBox(width: 4),
                                    Text(
                                      _loadingHospitalLoc
                                          ? 'Locating GPS...'
                                          : 'GPS: $_hospitalLiveLocation',
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, color: Colors.white),
                          onPressed: _openEditProfile,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // HOSPITAL QUICK SERVICES BOOKING ROW
              const Text(
                'Book Services for Your Hospital',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.darkNavy,
                ),
              ),
              const SizedBox(height: 12),

              Row(children: [
                _serviceTile('Book Doctor', Icons.health_and_safety_outlined,
                    AppTheme.primaryTeal, AppTheme.pastelBlue, _openBookDoctor),
                const SizedBox(width: 8),
                _serviceTile('Book Nurse', Icons.local_hospital_outlined,
                    AppColors.accent, AppTheme.pastelMint, _openNurseBoard),
                const SizedBox(width: 8),
                _serviceTile('Book Tech', Icons.science_outlined,
                    AppColors.purple, AppTheme.pastelPurple, _openTechnicianBoard),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                _serviceTile('Book Therapist', Icons.medication_rounded,
                    AppColors.danger, AppTheme.pastelPink, _openBookTherapist),
                const SizedBox(width: 8),
                // home care = care physician; goes to partner agencies and
                // care physicians as a hospital request
                _serviceTile('Care Physician', Icons.add_home_work_outlined,
                    AppColors.accent, AppTheme.pastelMint, _openShiftBoard),
                const SizedBox(width: 8),
                _serviceTile('My Bookings', Icons.receipt_long_outlined,
                    AppTheme.darkNavy, Colors.white, _openMyBookings),
              ]),

              const SizedBox(height: 16),

              // care physicians booked for this hospital's requests
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: _streams.get('care_shifts',
                    () => CarePhysicianService.posterShiftsStream(_hospital.uid)),
                builder: (context, snap) => BookedCarePhysiciansCard(
                  shifts: snap.data,
                  now: DateTime.now(),
                  onOpenAll: _openShiftBoard,
                ),
              ),

              const SizedBox(height: 16),

              // ON-CALL PREFERRED DOCTORS SELECTOR BANNER
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primaryTint,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.primaryBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.star_rounded, color: AppColors.primary, size: 24),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'On-Call Doctors (2 per Category)',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.darkNavy,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Set 2 preferred doctors for Cardiology, Pediatrics, ICU, etc.',
                            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brand,
                        minimumSize: const Size(0, 38),
                      ),
                      onPressed: _showSetHospitalPreferredDoctorsDialog,
                      child: const Text('Manage'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              if (!_hospital.isVerified)
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.warningTint,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.warningBright),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.pending_actions_rounded,
                          color: AppColors.warning, size: 24),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Hospital Verification Pending ⏳\nAdmin is reviewing your Bombay Nursing Home Registration certificate and other documents.',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.darkNavy),
                        ),
                      ),
                    ],
                  ),
                ),

              const Text(
                'Live Emergency Pipeline',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.darkNavy,
                ),
              ),
              const SizedBox(height: 12),

              // Segmented Tab Bar (Active Admissions vs Emergency History)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.lineStrong),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedHospitalTab = 0),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _selectedHospitalTab == 0
                                ? AppColors.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Active Admissions',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _selectedHospitalTab == 0
                                  ? Colors.white
                                  : AppTheme.darkNavy,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedHospitalTab = 1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _selectedHospitalTab == 1
                                ? AppColors.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Emergency History',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _selectedHospitalTab == 1
                                  ? Colors.white
                                  : AppTheme.darkNavy,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Stream SOS Requests for Hospital
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                // only SOS emergencies are shown here
                stream: _streams.get('appointments', () => AppDatabase.instance
                    .collection('appointments')
                    .where('consultationType', isEqualTo: SosService.type)
                    .snapshots()),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return LoadErrorView(error: snapshot.error, what: 'emergency requests');
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary));
                  }

                  final docs = snapshot.data?.docs ?? [];
                  final List<Map<String, dynamic>> activeRequests = [];
                  final List<Map<String, dynamic>> historyRequests = [];


                  for (var doc in docs) {
                    final data = doc.data();
                    data['appointmentId'] = doc.id;
                    final status = data['status'] ?? '';
                    final assignedHosp = data['assignedHospitalUid'] ?? '';

                    // Ran out of time (5 min): close it and erase everything
                    if (FirestoreService.isUrgentRequestExpired(data)) {
                      FirestoreService.expireUrgentRequest(doc.id);
                      continue;
                    }

                    final bool isMine = assignedHosp == _hospital.uid;

                    final double pLat = toNum(data['patientLat'])?.toDouble() ?? LocationService.defaultLat;
                    final double pLng = toNum(data['patientLng'])?.toDouble() ?? LocationService.defaultLng;
                    final double hLat = _hospitalPos?.latitude ?? _hospital.latitude ?? pLat;
                    final double hLng = _hospitalPos?.longitude ?? _hospital.longitude ?? pLng;

                    final double distanceMeters = Geolocator.distanceBetween(pLat, pLng, hLat, hLng);
                    final double distanceKm = distanceMeters / 1000.0;
                    // 4 km first, then 6 km after a minute, 8 km after two
                    final bool withinRadius =
                        distanceKm <= SosService.hospitalRadius(data);

                    if (isMine &&
                        (status == 'Pending Doctor Assignment' ||
                            status == 'Pending Ambulance Dispatch' ||
                            status == 'Ambulance Dispatched' ||
                            status == 'Patient Picked Up' ||
                            status == 'Confirmed' ||
                            status == 'In Progress')) {
                      activeRequests.add(data);
                    } else if (status == 'Pending Hospital Acceptance' &&
                        withinRadius &&
                        !((data['declinedHospitalUids'] as List?) ?? const [])
                            .contains(_hospital.uid)) {
                      activeRequests.add(data);
                    } else if (isMine &&
                        (status == 'Completed' ||
                            status == 'Hospital Declined')) {
                      historyRequests.add(data);
                    }
                  }

                  // EXCLUSIVE LOCK: Only trigger popup if not busy with active admission!
                  if (_hospital.isVerified) {
                    final pendingSos = activeRequests.firstWhere(
                      (r) => r['status'] == 'Pending Hospital Acceptance',
                      orElse: () => {},
                    );
                    if (pendingSos.isNotEmpty) {
                      final pId = pendingSos['appointmentId'] ?? '';
                      if (pId != _lastAlertAppointmentId) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _showHospitalSosPopup(pendingSos);
                        });
                      }
                    }
                  }

                  final currentDisplayList = _selectedHospitalTab == 0
                      ? activeRequests
                      : historyRequests;

                  if (currentDisplayList.isEmpty) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.local_hospital_outlined,
                              size: 48, color: AppColors.muted),
                          const SizedBox(height: 12),
                          Text(
                            _selectedHospitalTab == 0
                                ? 'No Active Emergency Admissions'
                                : 'No Past Emergency History',
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.darkNavy),
                          ),
                        ],
                      ),
                    );
                  }

                  return Column(
                    children: currentDisplayList.map((item) {
                      final pName = item['patientName'] ?? 'Patient';
                      final pPhone = item['patientPhone'] ?? '';
                      final status = item['status'] ?? 'Pending';
                      final loc = item['locationName'] ?? 'Patient Location';
                      final category = item['emergencyCategory'] ??
                          item['doctorCategory'] ??
                          'Emergency';
                      final bool requiresAmbulance =
                          item['requiresAmbulance'] ?? true;
                      final Map<String, dynamic> qAnswers =
                          Map<String, dynamic>.from(
                              item['questionAnswers'] ?? {});

                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.dangerLight),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const CircleAvatar(
                                  radius: 22,
                                  backgroundColor: AppTheme.pastelPink,
                                  child: Icon(Icons.person,
                                      color: AppColors.danger),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(pName,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16)),
                                      Text('Phone: $pPhone • Area: $loc',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: AppTheme.textMuted)),
                                      Text('Category: $category',
                                          style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.danger)),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.dangerSoft,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    status,
                                    style: const TextStyle(
                                        color: AppColors.danger,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                    requiresAmbulance
                                        ? '🚑 Requires Ambulance'
                                        : '🚗 Patient Driving Direct',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.darkNavy)),
                                if (qAnswers.isNotEmpty)
                                  Text(
                                    '${qAnswers.length} Questionnaire Responses',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.primaryTeal,
                                        fontWeight: FontWeight.bold),
                                  ),
                              ],
                            ),
                            for (final line in SosService.timingLines(item))
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(line,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.textMuted)),
                              ),
                            if (item['assignedHospitalUid'] == _hospital.uid &&
                                item['doctorOtp'] != null &&
                                item['doctorReachedAt'] == null &&
                                status != 'Completed') ...[
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(double.infinity, 42)),
                                onPressed: () =>
                                    _promptHospitalOtp(item, forDoctor: true),
                                icon: const Icon(Icons.medical_services_rounded,
                                    size: 18),
                                label: const Text('Enter Doctor Arrival OTP'),
                              ),
                            ],
                            if (item['assignedHospitalUid'] == _hospital.uid &&
                                (status == 'Patient Picked Up' ||
                                    (status == 'Confirmed' &&
                                        !requiresAmbulance))) ...[
                              const SizedBox(height: 10),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.brand,
                                    minimumSize: const Size(double.infinity, 42)),
                                onPressed: () => _promptHospitalOtp(item),
                                icon: const Icon(Icons.key_rounded, size: 18),
                                label: const Text('Enter Patient Hospital OTP'),
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ));
  }
}
