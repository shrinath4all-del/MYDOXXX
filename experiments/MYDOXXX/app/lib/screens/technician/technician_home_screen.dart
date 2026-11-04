import '../../services/lab_device.dart';
import '../../widgets/circle_image.dart';
import '../../utils/safe_cast.dart';
import '../../services/push_service.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/payout_setup_banner.dart';
import '../../services/location_service.dart';
import '../../widgets/technician_home_visit_alert_dialog.dart';
import '../auth/login_screen.dart';
import '../chat/chat_screen.dart';
import 'edit_technician_profile_screen.dart';
import 'technician_schedule_screen.dart';
import '../../utils/error_messages.dart';
import '../../utils/stream_cache.dart';
import '../../utils/responsive.dart';
import '../../constants/app_colors.dart';

import '../../constants/app_strings.dart';
import '../../utils/appointment_rules.dart';

import '../../widgets/notification_bell.dart';

// Same layout and home blue palette as the therapist dashboard
const Color _kPrimary = AppColors.primary; // AppTheme.primaryTeal (home blue)
const Color _kPrimarySoft = AppColors.primarySoft; // AppTheme.pastelBlue
const Color _kBg = AppColors.page; // AppTheme.bgLight
const Color _kBorder = AppColors.lineSoft;
const Color _kInk = AppColors.ink;
const Color _kMuted = AppColors.muted;

class TechnicianHomeScreen extends StatefulWidget {
  final UserModel technician;

  const TechnicianHomeScreen({
    super.key,
    required this.technician,
  });

  @override
  State<TechnicianHomeScreen> createState() => _TechnicianHomeScreenState();
}

class _TechnicianHomeScreenState extends State<TechnicianHomeScreen> {
  // Live data connections kept open across redraws
  final StreamCache _streams = StreamCache();

  final AuthService _authService = AuthService();
  late UserModel _technician;
  Map<String, dynamic> _raw = {};
  StreamSubscription? _profileSub;
  Timer? _autoCloseTimer;

  Stream<List<Map<String, dynamic>>>? _bookingsStream;

  String _bookingsStreamKey = '';

  // 0 Today, 1 New requests, 2 Upcoming, 3 History, 4 My patients
  int _selectedTab = 0;
  final Set<String> _alertedIds = {};
  String _currentLocation = 'Detecting location...';
  bool _loadingLocation = false;


  @override
  void initState() {
    super.initState();
    PushService.registerForUser(widget.technician.uid);
    _technician = widget.technician;
    _fetchLiveLocation();
    // Close sessions left "In Progress" past their booked end time
    _autoCloseOverdue();
    _autoCloseTimer = Timer.periodic(
        const Duration(minutes: 1), (_) => _autoCloseOverdue());
    _profileSub = FirestoreService.getUserStream(_technician.uid, 'technician').listen((doc) {
      final data = doc.data();
      if (mounted && doc.exists && data != null) {
        setState(() {
          _raw = data;
          _technician = UserModel.fromMap(data, _technician.uid);
        });
      }
    });
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    _autoCloseTimer?.cancel();
    super.dispose();
  }

  Future<void> _updateFields(Map<String, dynamic> data) =>
      FirestoreService.updateProviderFields('technicians', _technician.uid, data);

  /// Detects the live location and saves the coordinates automatically, so
  /// patients' nearby search uses the current position.
  Future<void> _fetchLiveLocation() async {
    setState(() => _loadingLocation = true);
    final location = await LocationService.getCurrentLocation();
    if (mounted) {
      setState(() {
        _currentLocation = location;
        _loadingLocation = false;
      });
    }
    final pos = await _currentPosition();
    if (pos != null) {
      await _updateFields({
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'currentArea': location,
        'locationUpdatedAt': DateTime.now().toIso8601String(),
      });
    }
  }

  /// GPS position, assuming permission was already handled by LocationService.
  Future<Position?> _currentPosition() async {
    try {
      final permission = await LabLocation.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      return await LabLocation.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (_) {
      try {
        return await LabLocation.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Derived profile state
  // ---------------------------------------------------------------------------

  bool get _online => _raw['isOnline'] != false;
  // Phone alerts are always on (the on/off button was removed)
  bool get _phoneAlerts => true;

  DateTime? get _notificationsReadAt =>
      DateTime.tryParse((_raw['notificationsReadAt'] ?? '').toString());

  Stream<List<Map<String, dynamic>>> _bookings() {
    final locs = _technician.preferredLocations ?? [];
    final key = locs.join('|');
    if (_bookingsStream == null || key != _bookingsStreamKey) {
      _bookingsStreamKey = key;
      _bookingsStream = _streams.get('bookings:$key', () => FirestoreService.getTechnicianBookingsStream(_technician.uid, locs));
    }
    return _bookingsStream!;
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _snack(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color ?? _kPrimary),
    );
  }

  Future<void> _toggleOnline() async {
    final next = !_online;
    setState(() => _raw = {..._raw, 'isOnline': next});
    await _updateFields({'isOnline': next});
    _snack(next
        ? 'You are online. New requests will reach you.'
        : 'You are offline. Patients cannot book you right now.');
    // going online saves where you are (distance shown to patients)
    if (next) _shareLocation(quiet: true);
  }

  Future<void> _shareLocation({bool quiet = false}) async {
    try {
      // Handles permission prompts and returns a readable area name
      final area = await LocationService.getCurrentLocation();
      if (mounted) setState(() => _currentLocation = area);
      final pos = await _currentPosition();

      if (pos == null) {
        if (!quiet) {
          _snack('Could not get your location. Check location permissions.',
              color: AppColors.danger);
        }
        return;
      }

      await _updateFields({
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'currentArea': area,
        'locationUpdatedAt': DateTime.now().toIso8601String(),
      });
      if (!quiet) _snack('Location shared: $area. Nearby patients can now find you.');
    } catch (_) {
      // best effort: without a position only the distance is hidden
    }
  }

  Future<void> _autoCloseOverdue() async {
    final r =
        await FirestoreService.runPunctualityChecks(providerUid: _technician.uid);
    if (r.absent > 0) {
      _snack(
          'Marked absent for ${r.absent} booking${r.absent == 1 ? '' : 's'} '
          'not started in time. Professional score reduced by '
          '${FirestoreService.absentPenaltyPoints}% each.',
          color: AppColors.danger);
    } else if (r.closed > 0) {
      _snack('${r.closed} session${r.closed == 1 ? '' : 's'} closed automatically '
          '(booked time ended).');
    }
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
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold, color: _kInk)),
              const SizedBox(height: 4),
              Text(
                'Tell ${b['patientName'] ?? 'the patient'} how late you will be. '
                'Telling them before you are 30 mins late means no score down.',
                style: const TextStyle(fontSize: 12, color: _kMuted),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [15, 30, 45, 60].map((m) {
                  return _pillButton(
                    label: '$m mins',
                    raised: true,
                    onTap: () async {
                      Navigator.pop(ctx);
                      final ok = await FirestoreService.notifyRunningLate(
                        appointmentId: b['appointmentId'] ?? '',
                        minutes: m,
                      );
                      ok
                          ? _snack('Patient told you will be about $m mins late.')
                          : _snack('Too late to tell: already counted as late.',
                              color: AppColors.warning);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBlockedBanner() {
    final until = FirestoreService.blockedUntil(_raw);
    final untilText = until == null
        ? ''
        : ' until ${until.day}/${until.month}/${until.year}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.dangerSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.dangerLight),
      ),
      child: Row(
        children: [
          Icon(Icons.block_rounded, color: AppColors.danger),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Blocked$untilText: ${FirestoreService.absencesBeforeBlock} absents this month. '
              'You will not get new requests until then. Accepted bookings stay with you.',
              style: const TextStyle(fontSize: 12, color: _kInk),
            ),
          ),
        ],
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

  Future<void> _openEditProfile() async {
    final updated = await Navigator.of(context).push<UserModel>(
      MaterialPageRoute(builder: (_) => EditTechnicianProfileScreen(technician: _technician)),
    );
    if (updated != null && mounted) {
      setState(() => _technician = updated);
    }
  }

  void _openSchedule() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TechnicianScheduleScreen(technician: _technician)),
    );
  }

  /// Opens the chat only while the booking allows it; otherwise says why.
  void _chatIfOpen(Map<String, dynamic> booking, VoidCallback open) {
    switch (AppointmentRules.chatState(booking)) {
      case ChatState.open:
        open();
      case ChatState.notStarted:
        _snack(AppStrings.chatLocked);
      case ChatState.expired:
        open(); // the chat shows its own "time is over" notice
    }
  }

  void _openChat(String patientUid, String patientName) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chatId: '${patientUid}_${_technician.uid}',
          currentUserId: _technician.uid,
          currentUserName: _technician.name,
          peerName: patientName,
          peerRole: 'Patient',
          allowVideo: false,
        ),
      ),
    );
  }

  Future<void> _openMap(String locationName, double? lat, double? lng) async {
    final query = (lat != null && lng != null)
        ? '$lat,$lng'
        : Uri.encodeComponent(
            locationName.isNotEmpty ? locationName : 'Patient Address');
    final url =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    try {
      await labLaunchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _callPatient(String phone) async {
    if (phone.trim().isEmpty) {
      _snack('Patient phone number not available.', color: AppColors.warning);
      return;
    }
    try {
      await labLaunchUrl(Uri.parse('tel:${phone.trim()}'));
    } catch (_) {}
  }

  Future<void> _accept(Map<String, dynamic> b) async {
    if (!_technician.isVerified) {
      _snack('Your account is awaiting admin verification.',
          color: AppColors.warning);
      return;
    }
    final ok = await FirestoreService.acceptProviderRequest(
      appointmentId: b['appointmentId'] ?? '',
      providerUid: _technician.uid,
      providerName: _technician.name,
    );
    if (ok) {
      _snack('Booking with ${b['patientName'] ?? 'patient'} confirmed.');
    } else {
      _snack('Another provider already accepted this request.',
          color: AppColors.warning);
    }
  }

  Future<void> _decline(Map<String, dynamic> b) async {
    await FirestoreService.declineProviderRequest(
      appointmentId: b['appointmentId'] ?? '',
      providerUid: _technician.uid,
    );
    _snack('Request declined. Other nearby technicians can take it.', color: _kMuted);
  }

  void _maybeAlert(List<Map<String, dynamic>> incoming) {
    if (_blocked || !_phoneAlerts || !_online || !_technician.isVerified) return;
    final readAt = _notificationsReadAt;
    for (final b in incoming) {
      final id = b['appointmentId'] ?? '';
      if (id.isEmpty || _alertedIds.contains(id)) continue;
      _alertedIds.add(id);
      final created = DateTime.tryParse((b['createdAt'] ?? '').toString());
      if (readAt != null && created != null && !created.isAfter(readAt)) {
        continue;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        HapticFeedback.vibrate();
        SystemSound.play(SystemSoundType.alert);
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => TechnicianHomeVisitAlertDialog(
            appointment: b,
            technicianUid: _technician.uid,
            technicianName: _technician.name,
          ),
        );
      });
      return; // one popup at a time
    }
  }

  // --- OTP / job lifecycle ---------------------------------------------------

  /// Same rule as the doctors and the server: not before the booked time
  /// (also for a same-day urgent booking with a chosen time).
  String? _slotNotStartedError(Map<String, dynamic> b) =>
      FirestoreService.earlyStartMessage(b, what: 'test visit');

  DateTime? _parseSlotStart(String dateStr, String timeStr) {
    final day = _parseDate(dateStr);
    if (day == null) return null;
    try {
      final cleaned = timeStr.trim().toUpperCase();
      final first = cleaned.split('-').first.trim().split(' ').first;
      final hm = first.split(':');
      var hour = int.parse(hm[0]);
      final minute = hm.length > 1 ? int.parse(hm[1]) : 0;
      final startPart = cleaned.split('-').first;
      if (startPart.contains('PM') && hour < 12) hour += 12;
      if (startPart.contains('AM') && hour == 12) hour = 0;
      return DateTime(day.year, day.month, day.day, hour, minute);
    } catch (_) {
      return null;
    }
  }

  void _promptOtp(Map<String, dynamic> b) {
    final err = _slotNotStartedError(b);
    if (err != null) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Time slot not started'),
          content: Text(err),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final otpController = TextEditingController();
    final patientName = b['patientName'] ?? 'Patient';
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Verify patient OTP'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ask $patientName for the 4-digit OTP to start sample collection.',
              style: const TextStyle(fontSize: 13, color: _kMuted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: otpController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              autofocus: true,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
                color: _kPrimary,
              ),
              decoration:
                  const InputDecoration(hintText: '• • • •', counterText: ''),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand),
            onPressed: () async {
              final entered = otpController.text.trim();
              Navigator.pop(dialogCtx);
              final int? lateBy;
              try {
                lateBy = await FirestoreService.startSessionWithOtp(
                  appointmentId: b['appointmentId'] ?? '',
                  enteredOtp: entered,
                );
              } catch (e) {
                _snack(e.toString().replaceFirst('Exception: ', ''),
                    color: AppColors.danger);
                return;
              }
              if (lateBy == null) {
                _snack('Invalid OTP. Please check with the patient.',
                      color: AppColors.danger);
              } else if (lateBy > FirestoreService.lateArrivalGraceMinutes) {
                _snack(
                    'Started $lateBy mins late. Professional score reduced by '
                    '${FirestoreService.latePenaltyPoints}%.',
                    color: AppColors.warning);
              } else {
                _snack('OTP verified. Sample collection for $patientName started.');
              }
            },
            child: const Text('Start sample collection'),
          ),
        ],
      ),
    );
  }

  Future<void> _complete(Map<String, dynamic> b) async {
    await FirestoreService.completeConsultation(b['appointmentId'] ?? '');
    _snack('Sample collection completed. Great work!');
  }

  // ---------------------------------------------------------------------------
  // Booking classification
  // ---------------------------------------------------------------------------

  static DateTime? _parseDate(String raw) {
    final key = FirestoreService.normalizeDateKey(raw);
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  _Buckets _classify(List<Map<String, dynamic>> all) {
    final me = _technician.uid;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monthAgo = now.subtract(const Duration(days: 30));
    final buckets = _Buckets();

    for (final b in all) {
      // Requests this provider declined are not shown
      if (b['declinedByMe'] == true) continue;
      final status = (b['status'] ?? '').toString();
      final mine = b['doctorUid'] == me;

      if (status == 'Broadcasted') {
        // offline: no new requests (accepted work still shows)
        if (_online) buckets.offers.add(b);
      } else if (mine &&
          (status == 'Pending Home Visit' || status == 'Pending Emergency')) {
        buckets.pending.add(b);
      } else if (mine && (status == 'Confirmed' || status == 'In Progress')) {
        buckets.active.add(b);
        final day = _parseDate((b['date'] ?? '').toString());
        if (day == null || day == today || status == 'In Progress') {
          buckets.today.add(b);
        } else if (day.isAfter(today)) {
          buckets.upcoming.add(b);
        }
      } else if (mine && status == 'Completed') {
        buckets.history.add(b);
        final done = DateTime.tryParse(
            (b['completedAt'] ?? b['createdAt'] ?? '').toString());
        if (done != null && done.isAfter(monthAgo)) {
          buckets.completed30d++;
          buckets.earnings30d += toNum(b['price'])?.toDouble() ?? 0;
        }
      } else if (mine) {
        buckets.history.add(b); // cancelled / declined by patient / absent
      }
    }

    int byDate(Map<String, dynamic> a, Map<String, dynamic> b) {
      final da = _parseSlotStart('${a['date']}', '${a['time']}') ?? now;
      final db = _parseSlotStart('${b['date']}', '${b['time']}') ?? now;
      return da.compareTo(db);
    }

    // Not approved yet, or blocked for 15 days after 3 absents: no new
    // offers or requests (own history and earnings still show)
    if (_blocked || !_technician.isVerified) {
      buckets.offers.clear();
      buckets.pending.clear();
    }

    int newestFirst(Map<String, dynamic> a, Map<String, dynamic> b) =>
        '${b['createdAt']}'.compareTo('${a['createdAt']}');

    buckets.today.sort(byDate);
    buckets.upcoming.sort(byDate);
    buckets.active.sort(byDate);
    buckets.pending.sort(newestFirst);
    buckets.offers.sort(newestFirst);
    buckets.history.sort((a, b) => '${b['completedAt'] ?? b['createdAt']}'
        .compareTo('${a['completedAt'] ?? a['createdAt']}'));

    return buckets;
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ResponsiveCenter(child: Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _bookings(),
          builder: (context, snapshot) {
            final buckets = _classify(snapshot.data ?? []);
            _maybeAlert([...buckets.pending, ...buckets.offers]);

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _buildHeader(),
                const SizedBox(height: 14),
                if (snapshot.hasError) ...[
                  _card(
                      child: LoadErrorView(
                          error: snapshot.error, what: 'your bookings')),
                  const SizedBox(height: 12),
                ],
                // Bank account for online payments (90% of each booking)
                PayoutSetupBanner(
                  provider: _raw,
                  email: _technician.email,
                  phone: _technician.phone ?? _technician.mobileNumber ?? '',
                  name: _technician.name,
                ),
                if (_blocked) ...[
                  _buildBlockedBanner(),
                  const SizedBox(height: 12),
                ],
                if (!_technician.isVerified) ...[
                  _buildVerificationBanner(),
                  const SizedBox(height: 12),
                ],
                _statGrid([
                  _Stat('${buckets.pending.length}', 'To confirm'),
                  _Stat('${buckets.today.length}', 'Today'),
                  _Stat('${buckets.upcoming.length}', 'Upcoming'),
                  _Stat('${buckets.completed30d}', 'Completed (30d)'),
                  _Stat('₹${buckets.earnings30d.round()}', 'Earnings (30d)'),
                ]),
                const SizedBox(height: 14),
                _buildQuickActions(),
                const SizedBox(height: 14),
                _statGrid([
                  _Stat('${buckets.offers.length}', 'New offers'),
                  _Stat('${buckets.active.length}', 'Active'),
                  _Stat('${FirestoreService.professionalScoreOf(_raw)}/100',
                      'Professional score',
                      dark: true),
                  // Average of all patient ratings, 0/5 until rated
                  _Stat(FirestoreService.ratingLabel(_raw), 'Overall rating',
                      dark: true),
                ]),
                const SizedBox(height: 18),
                _sectionTitle('New sample collection offers (${buckets.offers.length})'),
                if (buckets.offers.isEmpty)
                  _emptyCard(!_technician.isVerified
                      ? 'You will start receiving requests once the admin approves your documents.'
                      : _online
                          ? 'No new offers within your selected area.'
                          : 'You are offline. Switch on to receive offers.')
                else
                  ...buckets.offers.map((b) => _requestCard(b, isOffer: true)),
                const SizedBox(height: 18),
                _sectionTitle('Active assignments (${buckets.active.length})'),
                if (buckets.active.isEmpty)
                  _emptyCard('No active assignments.')
                else
                  ...buckets.active.map(_assignmentCard),
                const SizedBox(height: 18),
                _buildTabs(buckets),
                const SizedBox(height: 14),
                ..._buildTabBody(buckets),
              ],
            );
          },
        ),
      ),
    ));
  }

  /// Top nav bar, gradient profile card with edit button, online switch.
  Widget _buildHeader() {
    final name = _technician.name.isNotEmpty ? _technician.name : 'Technician';
    final pic = _technician.profilePicUrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Navigation Bar
        Row(
          children: [
            // opened from the technician dashboard: back to it
            if (Navigator.of(context).canPop())
              IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _kPrimary,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.science_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Technician Portal',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: _kInk,
                    ),
                  ),
                  const SizedBox(height: 2),
                  GestureDetector(
                    onTap: _fetchLiveLocation,
                    child: Row(
                      children: [
                        Icon(Icons.location_on, color: _kPrimary, size: 14),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(
                            _loadingLocation ? 'Locating...' : _currentLocation,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _kPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            NotificationBell(
              uid: _technician.uid,
              collection: 'technicians',
              forPatient: false,
              bookings: _bookings(),
              // no new requests until approved, or while blocked
              includeOffers: _technician.isVerified && !_blocked,
              iconColor: _kInk,
              onOpenItem: () => setState(() => _selectedTab = 0),
            ),
            IconButton(
              icon: const Icon(Icons.logout_rounded, color: AppColors.muted),
              tooltip: 'Sign Out',
              onPressed: _signOut,
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Profile Card (gradient) with Profile & settings button
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: const [
                AppColors.primaryDark,
                _kPrimary,
                AppColors.primaryLight,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: _kPrimary.withValues(alpha: 0.3),
                blurRadius: 15,
                offset: const Offset(0, 6),
              )
            ],
          ),
          child: Row(
            children: [
              SafeAvatar(
  imageUrl: pic,
  radius: 28,
  backgroundColor: Colors.white.withValues(alpha: 0.2),
  fallback: Icon(Icons.science_rounded, color: Colors.white, size: 32),
),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if ((_technician.qualification ?? '').isNotEmpty)
                          _technician.qualification!,
                        if ((_technician.experience ?? '').isNotEmpty)
                          '${_technician.experience} yrs exp',
                        if ((_technician.city ?? '').isNotEmpty) _technician.city!,
                      ].join(' • '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, color: Colors.white),
                tooltip: 'Profile & settings',
                onPressed: _openEditProfile,
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Online Availability Switch Card
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _kBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _online ? AppColors.success : AppColors.muted,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  !_technician.isVerified
                      ? 'Available after admin approval'
                      : _online
                          ? 'Online & Taking Requests'
                          : 'Offline / Not Taking Requests',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: _kInk,
                  ),
                ),
              ),
              Switch(
                value: _technician.isVerified && _online,
                activeColor: _kPrimary,
                // No incoming requests until the admin approves the account
                onChanged: _technician.isVerified ? (_) => _toggleOnline() : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVerificationBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warningTint,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.warningBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.pending_actions_rounded, color: AppColors.warning),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Verification pending. Upload your documents in Profile & settings. '
              'Patients can book you once the admin approves your account.',
              style: TextStyle(fontSize: 12, color: _kInk),
            ),
          ),
          TextButton(
            onPressed: _openEditProfile,
            child: Text('Upload',
                style: TextStyle(fontWeight: FontWeight.bold, color: _kPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: [
        _pillButton(
          label: 'My schedule',
          leading:
              const Icon(Icons.calendar_month_outlined, size: 16, color: _kInk),
          onTap: _openSchedule,
          raised: true,
        ),
      ],
    );
  }

  Widget _buildTabs(_Buckets buckets) {
    final labels = [
      'Today · ${buckets.today.length}',
      'New requests · ${buckets.pending.length}',
      'Upcoming · ${buckets.upcoming.length}',
      'History · ${buckets.history.length}',
      'My patients',
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(labels.length, (i) {
          final selected = _selectedTab == i;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _pillButton(
              label: labels[i],
              filled: selected,
              onTap: () => setState(() => _selectedTab = i),
            ),
          );
        }),
      ),
    );
  }

  List<Widget> _buildTabBody(_Buckets buckets) {
    const plural = 'sample collections';
    switch (_selectedTab) {
      case 1:
        return [
          _sectionTitle('New requests (${buckets.pending.length})'),
          if (buckets.pending.isEmpty)
            _emptyCard('No patient requests waiting for you.')
          else
            ...buckets.pending.map((b) => _requestCard(b, isOffer: false)),
        ];
      case 2:
        return [
          _sectionTitle('Upcoming $plural (${buckets.upcoming.length})'),
          if (buckets.upcoming.isEmpty)
            _emptyCard('No upcoming $plural booked.')
          else
            ...buckets.upcoming.map(_assignmentCard),
        ];
      case 3:
        return [
          _sectionTitle('History (${buckets.history.length})'),
          if (buckets.history.isEmpty)
            _emptyCard('Completed $plural will appear here.')
          else
            ...buckets.history.map(_historyCard),
        ];
      case 4:
        return [
          _sectionTitle('My patients'),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _streams.get('patients', () => FirestoreService.getDoctorAttendedPatientsStream(_technician.uid)),
            builder: (context, snap) {
              if (snap.hasError) {
                return _card(
                    child: LoadErrorView(
                        error: snap.error, what: 'your patients'));
              }
              final patients = snap.data ?? [];
              if (patients.isEmpty) {
                return _emptyCard(
                    'Patients whose $plural you complete will appear here.');
              }
              return Column(
                children: patients.map(_patientCard).toList(),
              );
            },
          ),
        ];
      default:
        return [
          _sectionTitle("Today's $plural (${buckets.today.length})"),
          if (buckets.today.isEmpty)
            _emptyCard('No $plural booked for today.')
          else
            ...buckets.today.map(_assignmentCard),
        ];
    }
  }

  // --- Booking cards ---------------------------------------------------------

  String _area(Map<String, dynamic> b) {
    final loc = (b['locationName'] ?? '').toString();
    return loc.isEmpty ? 'Patient area' : loc.split(',').first.trim();
  }

  String _serviceLabel(Map<String, dynamic> b) =>
      (b['testName'] ?? b['doctorCategory'] ?? 'Lab test').toString();

  Widget _bookingSummary(Map<String, dynamic> b, {Widget? trailing}) {
    final price = toNum(b['price'])?.toInt() ?? 0;
    final extra = toNum(b['offeredExtraAmount'])?.toInt() ?? 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(b['patientName'] ?? 'Patient',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold, color: _kInk)),
              const SizedBox(height: 2),
              Text('${_serviceLabel(b)} · Home visit',
                  style: const TextStyle(fontSize: 12, color: _kMuted)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  _metaChip(Icons.place_outlined, _area(b)),
                  _metaChip(Icons.schedule_rounded,
                      '${b['date'] ?? ''} @ ${b['time'] ?? ''}'),
                  _metaChip(Icons.currency_rupee_rounded,
                      extra > 0 ? '$price (incl. ₹$extra extra)' : '$price'),
                ],
              ),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _requestCard(Map<String, dynamic> b, {required bool isOffer}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _card(
        child: Column(
          children: [
            _bookingSummary(
              b,
              trailing: _statusChip(isOffer ? 'Open offer' : 'Awaiting you'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _decline(b),
                    style: _outlineStyle(),
                    child: Text(isOffer ? 'Skip' : 'Decline',
                        style: const TextStyle(color: _kInk)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _accept(b),
                    style: _filledStyle(),
                    child: const Text('Accept'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _assignmentCard(Map<String, dynamic> b) {
    final status = (b['status'] ?? '').toString();
    final inProgress = status == 'In Progress';
    final lat = toNum(b['patientLat'])?.toDouble();
    final lng = toNum(b['patientLng'])?.toDouble();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _card(
        child: Column(
          children: [
            _bookingSummary(b, trailing: _statusChip(status)),
            if (b['runningLateMinutes'] != null && status == 'Confirmed') ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    'You told the patient: about ${b['runningLateMinutes']} mins late',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.orange)),
              ),
            ],
            if (FirestoreService.canTellRunningLate(b)) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: _pillButton(
                  label: 'Running late',
                  leading: const Icon(Icons.schedule_send_outlined,
                      size: 15, color: _kInk),
                  onTap: () => _showRunningLateSheet(b),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                _iconAction(Icons.directions_outlined, 'Directions',
                    () => _openMap(_area(b), lat, lng)),
                const SizedBox(width: 8),
                _iconAction(Icons.call_outlined, 'Call',
                    () => _callPatient('${b['patientPhone'] ?? ''}')),
                const SizedBox(width: 8),
                _iconAction(
                    AppointmentRules.chatOpen(b)
                        ? Icons.chat_bubble_outline_rounded
                        : Icons.lock_outline_rounded,
                    AppStrings.chat,
                    () => _chatIfOpen(
                        b,
                        () => _openChat('${b['patientUid'] ?? ''}',
                            '${b['patientName'] ?? 'Patient'}'))),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed:
                        inProgress ? () => _complete(b) : () => _promptOtp(b),
                    style: _filledStyle(
                        color: inProgress ? AppColors.successDark : _kPrimary),
                    child: Text(inProgress ? 'Complete' : 'Start (OTP)'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyCard(Map<String, dynamic> b) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _card(
        child: Column(
          children: [
            _bookingSummary(b, trailing: _statusChip('${b['status']}')),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: _pillButton(
                label: AppStrings.chat,
                leading: const Icon(Icons.chat_bubble_outline_rounded,
                    size: 15, color: _kInk),
                onTap: () => _chatIfOpen(
                    b,
                    () => _openChat('${b['patientUid'] ?? ''}',
                        '${b['patientName'] ?? 'Patient'}')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _patientCard(Map<String, dynamic> p) {
    final pUid = (p['patientUid'] ?? '').toString();
    final pName = (p['patientName'] ?? 'Patient').toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _card(
        child: Row(
          children: [
            const CircleAvatar(
              radius: 20,
              backgroundColor: _kPrimarySoft,
              child: Icon(Icons.person, color: _kPrimary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pName,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: _kInk)),
                  const SizedBox(height: 2),
                  Text(
                      [
                        '${p['visits'] ?? 1} visit${(p['visits'] ?? 1) == 1 ? '' : 's'}',
                        if ('${p['lastConsultation'] ?? ''}'.isNotEmpty)
                          'last ${p['lastConsultation']}',
                      ].join(' · '),
                      style: const TextStyle(fontSize: 11, color: _kMuted)),
                ],
              ),
            ),
            _pillButton(
              label: 'Chat',
              leading: const Icon(Icons.chat_bubble_outline_rounded,
                  size: 15, color: _kInk),
              onTap: () => _chatIfOpen({
                'status': 'Completed',
                'completedAt': p['lastCompletedAt'],
              }, () => _openChat(pUid, pName)),
            ),
          ],
        ),
      ),
    );
  }

  // --- Small building blocks -------------------------------------------------

  Widget _card({required Widget child, VoidCallback? onTap}) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _kBorder),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _statGrid(List<_Stat> stats) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = (constraints.maxWidth - 10) / 2;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: stats
            .map((s) => SizedBox(
                  width: w,
                  child: _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: s.dark ? _kInk : _kPrimary)),
                        const SizedBox(height: 4),
                        Text(s.label,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: _kInk)),
                      ],
                    ),
                  ),
                ))
            .toList(),
      );
    });
  }

  Widget _pillButton({
    required String label,
    VoidCallback? onTap,
    Widget? leading,
    bool filled = false,
    bool raised = false,
  }) {
    final bg = filled
        ? _kPrimary
        : raised
            ? AppColors.divider
            : Colors.white;
    final fg = filled ? Colors.white : _kInk;
    return Material(
      color: bg,
      shape: StadiumBorder(
          side: BorderSide(color: filled ? Colors.transparent : _kBorder)),
      elevation: raised ? 1 : 0,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[leading, const SizedBox(width: 6)],
              Text(label,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, color: _kInk)),
      );

  Widget _emptyCard(String text) => _card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: _kMuted)),
        ),
      );

  Widget _metaChip(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: _kPrimary),
          const SizedBox(width: 3),
          Text(text,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: _kInk)),
        ],
      );

  Widget _statusChip(String status) {
    Color bg = _kPrimarySoft;
    Color fg = _kPrimary;
    if (status == 'In Progress') {
      bg = AppColors.warningTint;
      fg = AppColors.warningDeep;
    } else if (status == 'Completed') {
      bg = AppColors.successTint;
      fg = AppColors.successDeep;
    } else if (status == 'Declined' || status == 'Cancelled') {
      bg = AppColors.dangerSoft;
      fg = AppColors.danger;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(status,
          style:
              TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: fg)),
    );
  }

  Widget _iconAction(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.chip,
        shape: const CircleBorder(side: BorderSide(color: _kBorder)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: 18, color: _kInk),
          ),
        ),
      ),
    );
  }

  ButtonStyle _filledStyle({Color? color}) => ElevatedButton.styleFrom(
        backgroundColor: color ?? _kPrimary,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 42),
        shape: const StadiumBorder(),
        elevation: 0,
      );

  ButtonStyle _outlineStyle() => OutlinedButton.styleFrom(
        minimumSize: const Size(0, 42),
        shape: const StadiumBorder(),
        side: const BorderSide(color: _kBorder),
      );
}

class _Stat {
  final String value;
  final String label;
  final bool dark;
  const _Stat(this.value, this.label, {this.dark = false});
}

class _Buckets {
  final List<Map<String, dynamic>> offers = [];
  final List<Map<String, dynamic>> pending = [];
  final List<Map<String, dynamic>> active = [];
  final List<Map<String, dynamic>> today = [];
  final List<Map<String, dynamic>> upcoming = [];
  final List<Map<String, dynamic>> history = [];
  int completed30d = 0;
  double earnings30d = 0;

}
