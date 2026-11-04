import '../../services/app_database.dart';
import '../../services/lab_device.dart';
import '../../utils/maps_navigation.dart';
import '../../utils/safe_cast.dart';
import '../../services/push_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../services/sos_service.dart';
import '../../theme/app_theme.dart';
import '../auth/login_screen.dart';
import 'edit_ambulance_profile_screen.dart';
import '../../utils/error_messages.dart';
import '../../utils/stream_cache.dart';
import '../../services/location_tracker.dart';
import '../../utils/responsive.dart';
import '../../constants/app_colors.dart';

import '../../widgets/notification_bell.dart';
import '../../widgets/ambulance_chat_button.dart';
import '../../services/role_notifications.dart';
import '../../constants/app_strings.dart';

class AmbulanceHomeScreen extends StatefulWidget {
  final UserModel ambulance;

  const AmbulanceHomeScreen({
    super.key,
    required this.ambulance,
  });

  @override
  State<AmbulanceHomeScreen> createState() => _AmbulanceHomeScreenState();
}

class _AmbulanceHomeScreenState extends State<AmbulanceHomeScreen> {
  // Live data connections kept open across redraws
  final StreamCache _streams = StreamCache();

  final AuthService _authService = AuthService();
  late UserModel _ambulance;
  // Live profile listener; cancelled when the screen closes (e.g. logout)
  StreamSubscription? _profileSub;
  String? _lastAlertAppointmentId;
  Timer? _locationTimer;
  Map<String, dynamic>? _lastProfile;
  String? _liveCity;
  Position? _livePos;
  bool _locationOk = false;

  @override
  void initState() {
    super.initState();
    PushService.registerForUser(widget.ambulance.uid);
    _ambulance = widget.ambulance;
    // Live location is what hospitals / the dispatch radius are measured from
    _saveLiveLocation();
    _locationTimer =
        Timer.periodic(const Duration(minutes: 1), (_) => _saveLiveLocation());
    // keeps the position saved in the background too (dispatches are
    // matched on the ambulance's live location)
    LocationTracker.start(
      collection: 'ambulances',
      uid: widget.ambulance.uid,
      onPosition: (p) => _livePos = p,
    );
    _profileSub =
        FirestoreService.getUserStream(_ambulance.uid, 'ambulance').listen((doc) {
      if (mounted && doc.exists && doc.data() != null) {
        // only the live position moved: no full dashboard rebuild
        if (_lastProfile != null &&
            sameExceptLocation(_lastProfile!, doc.data()!)) {
          _lastProfile = doc.data();
          return;
        }
        _lastProfile = doc.data();
        setState(() {
          _ambulance = UserModel.fromMap(doc.data()!, _ambulance.uid);
        });
      }
    });
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    _locationTimer?.cancel();
    LocationTracker.stop();
    super.dispose();
  }

  Future<void> _saveLiveLocation() async {
    try {
      final pos = await LabLocation.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      final city = await LocationService.getCurrentLocation();
      final data = {
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'city': city,
      };
      final db = AppDatabase.instance;
      await db
          .collection('ambulances')
          .doc(_ambulance.uid)
          .set(data, SetOptions(merge: true));
      _livePos = pos;
      if (mounted) {
        setState(() {
          _liveCity = city;
          _locationOk = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _locationOk = false);
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
    final updated = await Navigator.of(context).push<UserModel>(
      MaterialPageRoute(
        builder: (_) => EditAmbulanceProfileScreen(ambulance: _ambulance),
      ),
    );

    if (updated != null && mounted) {
      setState(() => _ambulance = updated);
    }
  }

  void _openMap(String locationName, double? lat, double? lng) async {
    final query = (lat != null && lng != null)
        ? '$lat,$lng'
        : Uri.encodeComponent(
            locationName.isNotEmpty ? locationName : 'Target Location');
    final url =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    try {
      if (await labCanLaunchUrl(url)) {
        await labLaunchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  void _promptAmbulanceOtp(Map<String, dynamic> appointment) {
    final TextEditingController otpController = TextEditingController();
    final appointmentId = appointment['appointmentId'] ?? '';
    final patientName = appointment['patientName'] ?? 'Patient';

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Row(
            children: [
              Icon(Icons.lock_person_rounded, color: AppColors.primary),
              SizedBox(width: 8),
              Flexible(child: Text('Verify Ambulance OTP')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ask $patientName for the 4-digit OTP to confirm patient pickup:',
                style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: otpController,
                keyboardType: TextInputType.number,
                maxLength: 4,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8,
                  color: AppColors.primaryDark,
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
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryDark),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final enteredOtp = otpController.text.trim();
                Navigator.pop(dialogCtx);

                final success = await SosService.verifyAmbulancePickup(
                  appointmentId: appointmentId,
                  enteredOtp: enteredOtp,
                  ambulanceUid: _ambulance.uid,
                );

                if (success) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                          'OTP Verified! $patientName picked up. Now navigate to assigned hospital.'),
                      backgroundColor: AppColors.primaryDark,
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
              child: const Text('Verify OTP & Pick Up'),
            ),
          ],
        );
      },
    );
  }

  void _showAmbulanceDispatchPopup(Map<String, dynamic> appointment) {
    final id = appointment['appointmentId'] ?? '';
    if (id == _lastAlertAppointmentId) return;

    _lastAlertAppointmentId = id;
    final patientName = appointment['patientName'] ?? 'Patient';
    final patientPhone = appointment['patientPhone'] ?? 'N/A';
    final patientArea = appointment['locationName'] ?? 'Patient Location';
    final hospitalName =
        appointment['assignedHospitalName'] ?? 'Assigned Hospital';
    final category = appointment['emergencyCategory'] ?? appointment['doctorCategory'] ?? 'General Emergency';
    final Map<String, dynamic> qAnswers =
        Map<String, dynamic>.from(appointment['questionAnswers'] ?? {});
    final double? pLat = toNum(appointment['patientLat'])?.toDouble();
    final double? pLng = toNum(appointment['patientLng'])?.toDouble();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          title: const Row(
            children: [
              Icon(Icons.airport_shuttle_rounded,
                  color: AppColors.primary, size: 28),
              SizedBox(width: 8),
              Flexible(child: Text('🚑 AMBULANCE DISPATCH ALERT')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$category dispatch request for patient $patientName to be transported to $hospitalName.',
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primaryTint,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primaryBorder),
                ),
                child: Column(
                  children: [
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
                        const Text('Patient GPS Area:',
                            style: TextStyle(fontSize: 12, color: AppColors.muted)),
                        Expanded(
                          child: Text(
                            patientArea,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Destination Hospital:',
                            style: TextStyle(fontSize: 12, color: AppColors.muted)),
                        Expanded(
                          child: Text(
                            hospitalName,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.darkNavy),
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
                // Only this ambulance drops out; others can still accept.
                await SosService.declineAmbulance(id, _ambulance.uid);
              },
              child:
                  const Text('Decline', style: TextStyle(color: AppColors.muted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryDark),
              onPressed: () async {
                Navigator.pop(dialogCtx);

                // STEP 3 COMPLETE: first ambulance to accept gets the dispatch
                final bool won = await SosService.acceptAmbulance(
                  appointmentId: id,
                  ambulanceUid: _ambulance.uid,
                  driverName: _ambulance.name,
                  vehicleNumber: _ambulance.vehicleNumber ?? 'AMB-108',
                  // arrival limit from the live distance to the patient
                  distanceKm: (_livePos != null && pLat != null && pLng != null)
                      ? SosService.distanceKm(pLat, pLng,
                          _livePos!.latitude, _livePos!.longitude)
                      : null,
                );

                if (!mounted) return;
                if (!won) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text(
                        'Another ambulance already took this dispatch or it has closed.'),
                    backgroundColor: AppColors.warning,
                  ));
                  return;
                }
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24)),
                    title: const Row(
                      children: [
                        Icon(Icons.directions_car_filled_rounded,
                            color: AppColors.primary),
                        SizedBox(width: 8),
                        Flexible(child: Text('Ambulance Dispatched!')),
                      ],
                    ),
                    content: const Text(
                        'Navigate to patient live GPS location first to pick up patient and verify OTP.'),
                    actions: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryDark),
                        onPressed: () {
                          _openMap(patientArea, pLat, pLng);
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.person_pin_circle_rounded),
                        label: const Text('Navigate to Patient GPS'),
                      ),
                    ],
                  ),
                );
              },
              child: const Text('Accept & Dispatch Ambulance'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveCenter(child: Scaffold(
      backgroundColor: AppTheme.bgLight,
      appBar: AppBar(
        title: const Text('Ambulance Dispatch Desk'),
        actions: [
          // dispatches given to this ambulance
          NotificationBell(
            uid: _ambulance.uid,
            collection: 'ambulances',
            forPatient: false,
            events: _streams.get(
                'bell',
                () => AppDatabase.instance
                    .collection('appointments')
                    .where('assignedAmbulanceUid', isEqualTo: _ambulance.uid)
                    .snapshots()
                    .map((s) => RoleNotifications.ambulanceSos(
                        [for (final d in s.docs) d.data()], _ambulance.uid))),
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
                  gradient: LinearGradient(
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
                          child: Icon(Icons.airport_shuttle_rounded,
                              color: Colors.white, size: 32),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _ambulance.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Vehicle: ${_ambulance.vehicleNumber ?? "Not added"}',
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 13),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    _locationOk
                                        ? Icons.my_location_rounded
                                        : Icons.location_disabled_rounded,
                                    size: 14,
                                    color: _locationOk
                                        ? AppColors.successLight
                                        : Colors.white70,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      _locationOk
                                          ? 'Live: ${_liveCity ?? _ambulance.city ?? "Locating…"}'
                                          : 'Turn on location to receive dispatches',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined,
                              color: Colors.white),
                          onPressed: _openEditProfile,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              if (!_ambulance.isVerified)
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
                          'Ambulance Verification Pending ⏳\nAdmin is reviewing Driver License & Vehicle Details.',
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
                'Live Emergency Dispatches',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.darkNavy,
                ),
              ),
              const SizedBox(height: 12),

              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                // only SOS emergencies can need an ambulance
                stream: _streams.get('appointments', () => AppDatabase.instance
                    .collection('appointments')
                    .where('consultationType', isEqualTo: SosService.type)
                    .snapshots()),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return LoadErrorView(error: snapshot.error, what: 'dispatch requests');
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(color: AppColors.primary));
                  }

                  final docs = snapshot.data?.docs ?? [];
                  final List<Map<String, dynamic>> ambRequests = [];
                  final bool onActiveDispatch = docs.any((d) {
                    final x = d.data();
                    return x['assignedAmbulanceUid'] == _ambulance.uid &&
                        (x['status'] == 'Ambulance Dispatched' ||
                            x['status'] == 'Patient Picked Up');
                  });

                  for (var doc in docs) {
                    final data = doc.data();
                    data['appointmentId'] = doc.id;
                    final status = data['status'] ?? '';
                    final bool reqAmb = data['requiresAmbulance'] ?? true;

                    // Ran out of time (5 min): close it and erase everything
                    if (FirestoreService.isUrgentRequestExpired(data)) {
                      FirestoreService.expireUrgentRequest(doc.id);
                      continue;
                    }

                    // Skip ambulance dispatch if patient chose "We will drive to the hospital"
                    if (!reqAmb) continue;

                    // Pending dispatch: only ambulances within the current radius
                    // (4 -> 6 -> 8 km from the assigned hospital), not already
                    // on another dispatch, and that haven't declined.
                    bool eligible = false;
                    if (status == 'Pending Ambulance Dispatch') {
                      final cands = (data['sosAmbulanceCandidatesKm'] as Map?)
                              ?.cast<String, dynamic>() ??
                          {};
                      // Live distance: patient's live location to this
                      // ambulance's live location (saved list is the fallback)
                      final pLat = toNum(data['patientLat'])?.toDouble();
                      final pLng = toNum(data['patientLng'])?.toDouble();
                      final double? dist = (_livePos != null &&
                              pLat != null &&
                              pLng != null)
                          ? SosService.distanceKm(pLat, pLng,
                              _livePos!.latitude, _livePos!.longitude)
                          : toNum(cands[_ambulance.uid])?.toDouble();
                      final declined =
                          (data['declinedAmbulanceUids'] as List?) ?? const [];
                      eligible = dist != null &&
                          dist <= SosService.ambulanceRadius(data) &&
                          !declined.contains(_ambulance.uid) &&
                          !onActiveDispatch;
                    }

                    if (eligible && _ambulance.isVerified) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _showAmbulanceDispatchPopup(data);
                      });
                    }

                    if (data['assignedAmbulanceUid'] == _ambulance.uid ||
                        eligible) {
                      ambRequests.add(data);
                    }
                  }

                  if (ambRequests.isEmpty) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.airport_shuttle_outlined,
                              size: 48, color: AppColors.muted),
                          SizedBox(height: 12),
                          Text(
                            'No Active Ambulance Dispatches',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.darkNavy),
                          ),
                        ],
                      ),
                    );
                  }

                  return Column(
                    children: ambRequests.map((item) {
                      final pName = item['patientName'] ?? 'Patient';
                      final pPhone = item['patientPhone'] ?? '';
                      final status = item['status'] ?? 'Pending';
                      final loc = item['locationName'] ?? 'Patient Location';
                      final hospitalName =
                          item['assignedHospitalName'] ?? 'Assigned Hospital';
                      final lat = toNum(item['patientLat'])?.toDouble();
                      final lng = toNum(item['patientLng'])?.toDouble();
                      final hLat =
                          toNum(item['assignedHospitalLat'])?.toDouble();
                      final hLng =
                          toNum(item['assignedHospitalLng'])?.toDouble();

                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.primaryBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const CircleAvatar(
                                  radius: 22,
                                  backgroundColor: AppTheme.pastelYellow,
                                  child: Icon(Icons.airport_shuttle_rounded,
                                      color: AppColors.primary),
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
                                      Text('Hospital: $hospitalName',
                                          style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.primaryTeal)),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryTint,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    status,
                                    style: const TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Chat with the patient while on duty
                            if (item['assignedAmbulanceUid'] == _ambulance.uid)
                              AmbulanceChatButton(
                                  sos: item,
                                  sosId: item['appointmentId'].toString(),
                                  forAmbulance: true),

                            // Pickup / drop time and the 15-25-30 min limit
                            for (final line in SosService.timingLines(item))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(line,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.darkNavy)),
                              ),
                            if (status == 'Patient Picked Up')
                              const Padding(
                                padding: EdgeInsets.only(bottom: 8),
                                child: Text(
                                  'Take the patient to the hospital. The hospital will enter the patient\'s hospital OTP to complete the handover.',
                                  style: TextStyle(
                                      fontSize: 11, color: AppTheme.textMuted),
                                ),
                              ),

                            // Dynamic Action Buttons: Patient GPS + OTP BEFORE pickup, Hospital GPS AFTER pickup!
                            if (status == 'In Progress' || status == 'Completed')
                              const Text(
                                'Patient handed over to the hospital. You are free for new emergencies.',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.success),
                              )
                            else if (status == 'Patient Picked Up')
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primaryDark,
                                    minimumSize: const Size(double.infinity, 42)),
                                onPressed: () => MapsNavigation.toHospital(
                                    hospitalName.toString(),
                                    lat: hLat,
                                    lng: hLng),
                                icon: const Icon(Icons.local_hospital_rounded,
                                    size: 18),
                                label: const Text('Navigate to Assigned Hospital'),
                              )
                            else
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _openMap(loc, lat, lng),
                                      icon: const Icon(
                                          Icons.person_pin_circle_rounded,
                                          size: 16),
                                      label: const Text('Patient GPS'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.primaryDark),
                                      onPressed: () =>
                                          _promptAmbulanceOtp(item),
                                      icon: const Icon(Icons.key_rounded,
                                          size: 16),
                                      label: const Text('Enter OTP'),
                                    ),
                                  ),
                                ],
                              ),
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
