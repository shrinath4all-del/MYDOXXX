import '../common/provider_patient_requests_screen.dart';
import '../../services/lab_device.dart';
import 'dart:async';
import 'technician_home_screen.dart';
import '../../utils/safe_cast.dart';

import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/technician_staffing_service.dart';
import '../../services/push_service.dart';
import '../../utils/error_messages.dart';
import '../../utils/responsive.dart';
import '../../utils/stream_cache.dart';
import '../../widgets/agency_duties_card.dart';
import '../../widgets/verification_documents_section.dart';
import '../agency/control_room_widgets.dart' show formatInr;
import '../auth/login_screen.dart';
import '../../services/technician_duty_service.dart';
import 'technician_duty_home_screen.dart';
import 'technician_profile_wizard.dart';
import 'technician_my_duties_view.dart';
import '../care_physician/cp_widgets.dart';
import '../../constants/app_colors.dart';

import '../../widgets/notification_bell.dart';
import '../../services/role_notifications.dart';
import '../../utils/ist_clock.dart';
import '../../widgets/delete_account_button.dart';

typedef _Cp = TechnicianStaffingService;

/// Technician dashboard: Shifts · Jobs · My duties · Profile.
class TechnicianStaffingScreen extends StatefulWidget {
  final UserModel user;
  const TechnicianStaffingScreen({super.key, required this.user});

  @override
  State<TechnicianStaffingScreen> createState() =>
      _CarePhysicianHomeScreenState();
}

class _CarePhysicianHomeScreenState extends State<TechnicianStaffingScreen> {
  final StreamCache _streams = StreamCache();
  Timer? _tick;
  String _tab = 'technician_shifts';
  // a physician on a hospital duty team opens on the duty roster; this
  // switches to the shifts, jobs and profile screens
  bool _showLegacy = true;
  String _shiftFilter = 'all';
  String _jobFilter = 'all';
  final Set<String> _busy = {};

  String get _uid => widget.user.uid;

  @override
  void initState() {
    super.initState();
    // the lab tests technicians pick from
    TechnicianStaffingService.loadProcedures()
        .then((_) { if (mounted) setState(() {}); });
    PushService.registerForUser(_uid);
    // check-in opens 1 h before a shift; "Tonight" / "Tomorrow" labels
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.danger : AppColors.successDark,
    ));
  }

  Future<void> _logout() async {
    await AuthService().signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  Future<void> _editProfile(Map<String, dynamic> me) => Navigator.of(context)
      .push(MaterialPageRoute(
          builder: (_) => TechnicianProfileWizard(profile: me)));

  Future<void> _claim(Map<String, dynamic> shift, Map<String, dynamic> me,
      List<Map<String, dynamic>> mine) async {
    var reason = _Cp.claimBlockReason(shift, me, mine, IstClock.now());
    // a duty on a hospital rotation roster is busy time too
    reason ??= await _Cp.rosterClash(shift, me['uid'].toString());
    if (!mounted) return;
    if (reason != null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(_Cp.isHomeVisit(shift)
              ? 'Cannot accept this visit'
              : 'Cannot claim this shift'),
          content: Text(reason!),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      return;
    }
    if (_Cp.isTeam(shift)) {
      await _acceptTeam(shift, me);
      return;
    }
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _ConfirmClaimSheet(shift: shift),
    );
    if (ok != true) return;
    final id = shift['id'].toString();
    setState(() => _busy.add(id));
    try {
      await _Cp.claimShift(id, me);
      _snack(_Cp.isHomeVisit(shift)
          ? 'Visit accepted — the patient can see you are coming. Please reach by ${_Cp.clock(_Cp.reachBy(shift))}.'
          : 'Shift confirmed — ${shift['hospitalName']} can see you are coming.');
      if (mounted) setState(() => _tab = 'duties');
    } catch (e) {
      final msg = ErrorMessages.of(e, action: 'claim the shift');
      // an unknown failure: show what it was so it can be fixed
      final raw = e.toString();
      final detail = msg.startsWith('Could not')
          ? ' (${e.runtimeType}: ${raw.length > 140 ? raw.substring(0, 140) : raw})'
          : '';
      debugPrint('claimShift failed: $e');
      _snack('$msg$detail', error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  /// A hospital's team request: accepting only puts the doctor forward; the
  /// agency picks who goes.
  Future<void> _acceptTeam(
      Map<String, dynamic> request, Map<String, dynamic> me) async {
    final intro = request['rotation'] == true
        ? '${request['hospitalName']} needs 3 full-time technicians on a weekly rotation (Morning, Evening, Night) from ${request['anchor']}.'
        : '${request['hospitalName']} needs ${_Cp.teamSizeOf(request)} technicians on '
            '${_Cp.dayLabel(request, IstClock.now())}, ${_Cp.timeRange(request)}.';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Accept this team request?'),
        content: Text('$intro\n\n'
            'The best 10 applicants go to the agency, which picks the three for the hospital. You will be told if you are placed.\n\n'
            'Any duty you already have at the same time is released if you are placed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not now')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Accept')),
        ],
      ),
    );
    if (ok != true) return;
    final id = request['id'].toString();
    setState(() => _busy.add(id));
    try {
      await _Cp.applyTeam(id, me);
      _snack('Applied. The agency picks the team from the best 10 applicants.');
      if (mounted) setState(() => _tab = 'applied');
    } catch (e) {
      _snack(ErrorMessages.of(e, action: 'accept the request'), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _decline(Map<String, dynamic> shift) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline this visit?'),
        content: Text(
            '${shift['serviceName'] ?? 'This home visit'} will be removed from your list and stay open for other technicians.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                minimumSize: const Size(0, 40)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final id = shift['id'].toString();
    setState(() => _busy.add(id));
    try {
      await _Cp.declineShift(id, _uid);
      _snack('Visit declined.');
    } catch (e) {
      _snack(ErrorMessages.of(e, action: 'decline the visit'), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _checkIn(Map<String, dynamic> s) async {
    final id = s['id'].toString();
    setState(() => _busy.add(id));
    try {
      final late = await _Cp.checkIn(s);
      _snack(late > 0 ? 'Checked in ($late min late).' : 'Checked in. Have a good shift.');
    } catch (e) {
      _snack(ErrorMessages.of(e, action: 'check in'), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  /// A hospital's locum: the arrival OTP (the live location is read now).
  Future<void> _arrivalOtp(Map<String, dynamic> s) async {
    final id = s['id'].toString();
    setState(() => _busy.add(id));
    try {
      await _Cp.generateArrivalOtp(s);
      _snack('OTP ready. Show it to the hospital.');
    } catch (e) {
      _snack(ErrorMessages.of(e, action: 'get the OTP'), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _checkOut(Map<String, dynamic> s) async {
    final id = s['id'].toString();
    setState(() => _busy.add(id));
    try {
      await _Cp.checkOut(s);
      _snack('Checked out. Shift completed.');
    } catch (e) {
      _snack(ErrorMessages.of(e, action: 'check out'), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _interest(Map<String, dynamic> job, Map<String, dynamic> me) async {
    final id = job['id'].toString();
    setState(() => _busy.add(id));
    try {
      await _Cp.expressInterest(id, me);
      _snack('Interest sent. ${job['hospitalName']} will contact you.');
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      _snack(ErrorMessages.of(e, action: 'send your interest'), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  bool _synced = false;

  /// An agency may have added this doctor by mobile number.
  void _syncAgency(Map<String, dynamic> me) {
    if (_synced) return;
    _synced = true;
    _Cp.syncAgencyFromRecords(me).catchError((_) {});
  }

  Future<void> _joinAgency(Map<String, dynamic> me) async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: _Cp.careAgenciesStream(),
        builder: (ctx, snap) {
          final list = snap.data ?? const [];
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(20),
              children: [
                const Text('Join a technician agency',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text(
                    "You'll get the agency's patients' home visits first and appear in its doctor list.",
                    style: TextStyle(fontSize: 12, color: CpColors.muted)),
                const SizedBox(height: 12),
                if (!snap.hasData)
                  const Center(child: CircularProgressIndicator())
                else if (list.isEmpty)
                  const Text('No agencies yet.')
                else
                  for (final a in list)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Text('🏢', style: TextStyle(fontSize: 22)),
                      title: Text((a['name'] ?? '').toString(),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(_Cp.listOf(a['areas']).join(', ')),
                      trailing: a['id'] == me['agencyId']
                          ? const Text('Current')
                          : const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.pop(ctx, a),
                    ),
              ],
            ),
          );
        },
      ),
    );
    if (picked == null || picked['id'] == me['agencyId']) return;
    try {
      await _Cp.joinAgency(
          me, picked['id'].toString(), (picked['name'] ?? '').toString());
      _snack('You joined ${picked['name']}.');
    } catch (e) {
      _snack(ErrorMessages.of(e, action: 'join the agency'), error: true);
    }
  }

  Future<void> _leaveAgency(Map<String, dynamic> me) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave the agency?'),
        content: Text(
            'You will work as a freelancer. ${me['agencyName']} will no longer send you its visits first. Your profile and history are kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Stay')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _Cp.leaveAgency(me);
      _snack('You left the agency. You now work as a freelancer.');
    } catch (e) {
      _snack(ErrorMessages.of(e, action: 'leave the agency'), error: true);
    }
  }

  Future<void> _toggleAvailable(Map<String, dynamic> me) async {
    try {
      await _Cp.setAvailable(_uid, (me['available'] == false || me['isOnline'] == false));
    } catch (e) {
      _snack(ErrorMessages.of(e, action: 'change availability'), error: true);
    }
  }

  void _openJob(Map<String, dynamic> job, Map<String, dynamic> me) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _JobSheet(
        job: job,
        interested: _Cp.hasInterest(job, _uid),
        onInterest: () => _interest(job, me),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _streams.get('dutyTeams', () => TechnicianDutyService.teamsOf(_uid)),
      builder: (context, teamSnap) {
        final onTeam = (teamSnap.data ?? const []).isNotEmpty;
        if (!onTeam) return _legacyDashboard();
        if (_showLegacy) {
          return Scaffold(
            body: _legacyDashboard(),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () => setState(() => _showLegacy = false),
              icon: const Icon(Icons.calendar_month_rounded),
              label: const Text('Duty roster'),
            ),
          );
        }
        return StreamBuilder<Map<String, dynamic>>(
          stream: _streams.get('me', () => _Cp.profileStream(_uid)),
          builder: (context, meSnap) {
            final me = meSnap.data;
            if (me == null) {
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }
            return TechnicianDutyHomeScreen(
              me: me,
              onOpenShifts: () => setState(() => _showLegacy = true),
              onLogout: _logout,
            );
          },
        );
      },
    );
  }

  Widget _legacyDashboard() {
    return ResponsiveCenter(
      child: StreamBuilder<Map<String, dynamic>>(
        stream: _streams.get('me', () => _Cp.profileStream(_uid)),
        builder: (context, meSnap) {
          final me = meSnap.data;
          if (meSnap.hasError) {
            return Scaffold(
                body: LoadErrorView(error: meSnap.error, what: 'your profile'));
          }
          if (me == null) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          _syncAgency(me);
          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: _streams.get('open', _Cp.openShiftsStream),
            builder: (context, openSnap) =>
                StreamBuilder<List<Map<String, dynamic>>>(
              stream: _streams.get('mine', () => _Cp.myShiftsStream(_uid)),
              builder: (context, mineSnap) =>
                  StreamBuilder<List<Map<String, dynamic>>>(
                stream: _streams.get('jobs', _Cp.activeJobsStream),
                builder: (context, jobSnap) =>
                    StreamBuilder<List<Map<String, dynamic>>>(
                stream: _streams.get('applied', () => _Cp.myApplicationsStream(_uid)),
                builder: (context, appSnap) {
                  final now = IstClock.now();
                  final mine = mineSnap.data ?? const [];
                  _Cp.markNoShows(mine, now);
                  return TechnicianStaffingView(
                    me: me,
                    openShifts: openSnap.data,
                    myShifts: mine,
                    jobs: jobSnap.data,
                    applications: appSnap.data,
                    error: openSnap.error ?? mineSnap.error ?? jobSnap.error,
                    now: now,
                    tab: _tab,
                    shiftFilter: _shiftFilter,
                    jobFilter: _jobFilter,
                    busy: _busy,
                    onTab: (t) => setState(() => _tab = t),
                    onShiftFilter: (f) => setState(() => _shiftFilter = f),
                    onJobFilter: (f) => setState(() => _jobFilter = f),
                    onClaim: (s) => _claim(s, me, mine),
                    onDecline: _decline,
                    onCheckIn: _checkIn,
                    onArrivalOtp: _arrivalOtp,
                    onCheckOut: _checkOut,
                    onJob: (j) => _openJob(j, me),
                    onEditProfile: () => _editProfile(me),
                    onToggleAvailable: () => _toggleAvailable(me),
                    onLogout: _logout,
                    onJoinAgency: () => _joinAgency(me),
                    onLeaveAgency: () => _leaveAgency(me),
                    onDocuments: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => _DocumentsScreen(uid: _uid))),
                    // patients' lab-test bookings work as before
                    onPatientBookings: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) =>
                                TechnicianHomeScreen(technician: widget.user))),
                    bell: NotificationBell(
                      uid: _uid,
                      collection: _Cp.collection,
                      forPatient: false,
                      events: _streams.get(
                          'bell',
                          () => _Cp.myShiftsStream(_uid).map((s) =>
                              RoleNotifications.carePhysicianShifts(
                                  s, IstClock.now()))),
                      iconColor: Colors.white,
                      onOpenItem: () => setState(() => _tab = 'duties'),
                    ),
                    patientRequests: ProviderPatientRequestsButton(user: widget.user),
                    agencyDuties: AgencyDutiesCard(
                      uid: _uid,
                      phone: (me['phone'] ?? me['mobileNumber'] ?? '').toString(),
                    ),
                  );
                },
              ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The dashboard for given data (no Firestore; used by the screen and by
/// layout tests).
class TechnicianStaffingView extends StatelessWidget {
  final Map<String, dynamic> me;
  final List<Map<String, dynamic>>? openShifts; // null while loading
  final List<Map<String, dynamic>> myShifts;
  final List<Map<String, dynamic>>? jobs;
  final List<Map<String, dynamic>>? applications; // full-time team applications
  final Object? error;
  final DateTime now;
  final String tab;
  final String shiftFilter;
  final String jobFilter;
  final Set<String> busy;
  final ValueChanged<String> onTab;
  final ValueChanged<String> onShiftFilter;
  final ValueChanged<String> onJobFilter;
  final ValueChanged<Map<String, dynamic>> onClaim;
  final ValueChanged<Map<String, dynamic>>? onDecline;
  final ValueChanged<Map<String, dynamic>> onCheckIn;
  final ValueChanged<Map<String, dynamic>>? onArrivalOtp;
  final ValueChanged<Map<String, dynamic>> onCheckOut;
  final ValueChanged<Map<String, dynamic>> onJob;
  final VoidCallback onEditProfile;
  final VoidCallback onToggleAvailable;
  final VoidCallback onLogout;
  final VoidCallback? onJoinAgency;
  final VoidCallback? onLeaveAgency;
  final VoidCallback? onDocuments;
  final Widget? agencyDuties;
  final Widget? patientRequests;

  /// Opens the patients' lab-test bookings (requests, upcoming, history).
  final VoidCallback? onPatientBookings;

  /// Notification bell shown in the header (left out in layout tests).
  final Widget? bell;

  const TechnicianStaffingView({
    super.key,
    required this.me,
    required this.openShifts,
    required this.myShifts,
    required this.jobs,
    this.applications,
    this.error,
    required this.now,
    required this.tab,
    required this.shiftFilter,
    required this.jobFilter,
    this.busy = const {},
    required this.onTab,
    required this.onShiftFilter,
    required this.onJobFilter,
    required this.onClaim,
    this.onDecline,
    required this.onCheckIn,
    this.onArrivalOtp,
    required this.onCheckOut,
    required this.onJob,
    required this.onEditProfile,
    required this.onToggleAvailable,
    required this.onLogout,
    this.onJoinAgency,
    this.onLeaveAgency,
    this.onDocuments,
    this.agencyDuties,
    this.patientRequests,
    this.bell,
    this.onPatientBookings,
  });

  /// Off: no open shifts or home visits (claimed duties still show).
  /// A full-time team request is a job, so it is not listed with the shifts.
  List<Map<String, dynamic>> get _fittingShifts => (me['available'] == false || me['isOnline'] == false)
      ? const []
      : _Cp.sortShifts(
          (openShifts ?? const [])
              .where((s) => !_Cp.isTeam(s) && _Cp.shiftFits(s, me, now))
              .toList(),
          me);

  /// Full-time team requests of hospitals: shown in Jobs.
  List<Map<String, dynamic>> get _fittingTeams => (me['available'] == false || me['isOnline'] == false)
      ? const []
      : (openShifts ?? const [])
          .where((s) => _Cp.isTeam(s) && _Cp.shiftFits(s, me, now))
          .toList();

  List<Map<String, dynamic>> get _fittingJobs =>
      (jobs ?? const []).where((j) => _Cp.jobFits(j, me)).toList();

  bool get _profileIncomplete =>
      _Cp.listOf(me['dutyTypes']).isEmpty || _Cp.listOf(me['areas']).isEmpty;

  @override
  Widget build(BuildContext context) {
    final shifts = _fittingShifts;
    final fittingJobs = _fittingJobs;
    final teams = _fittingTeams;
    return Scaffold(
      backgroundColor: CpColors.page,
      body: Column(
        children: [
          _header(context),
          _tabs(shifts.length, fittingJobs.length + teams.length,
              (applications ?? const []).length),
          if (patientRequests != null) patientRequests!,
          Expanded(
            child: error != null
                ? LoadErrorView(error: error, what: 'shifts and jobs')
                : switch (tab) {
                    'jobs' => _jobsTab(fittingJobs, teams),
                    'applied' => _appliedTab(),
                    'duties' => _dutiesTab(),
                    'profile' => _profileTab(),
                    _ => _shiftsTab(shifts),
                  },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- header

  Widget _header(BuildContext context) {
    final available = me['available'] != false;
    final years = (me['experienceYears'] ?? me['experience'] ?? '').toString();
    final sub = [
      (me['name'] ?? '').toString(),
      (me['qualification'] ?? '').toString(),
      if (years.isNotEmpty && years != '0') '${years}y',
    ].where((e) => e.isNotEmpty).join(' · ');
    Widget round(IconData icon, String tip, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Material(
            color: Colors.white.withValues(alpha: 0.18),
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: tip,
              visualDensity: VisualDensity.compact,
              icon: Icon(icon, color: Colors.white, size: 20),
              onPressed: onTap,
            ),
          ),
        );
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            colors: [AppColors.navy, AppColors.primary]),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('🩺 Technician',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.primarySoft, fontSize: 12)),
                  ],
                ),
              ),
              Material(
                color: Colors.white.withValues(alpha: 0.18),
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: onToggleAvailable,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.circle,
                          size: 9,
                          color: available
                              ? AppColors.verifiedLight
                              : AppColors.lineStrong),
                      const SizedBox(width: 6),
                      Text(available ? 'Available' : 'Off',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                    ]),
                  ),
                ),
              ),
              if (bell != null)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Material(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: const CircleBorder(),
                    child: bell,
                  ),
                ),
              if (onPatientBookings != null)
                round(Icons.biotech_outlined, 'Patient bookings',
                    onPatientBookings!),
              round(Icons.logout_rounded, 'Log out', onLogout),
              round(Icons.person_outline_rounded, 'Profile',
                  () => onTab('profile')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabs(int shiftCount, int jobCount, [int appliedCount = 0]) {
    final tabs = {
      'shifts': 'Shifts ($shiftCount)',
      'jobs': 'Jobs ($jobCount)',
      'applied': 'Applied ($appliedCount)',
      'duties': 'My duties',
      'profile': 'Profile',
    };
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: Row(children: [
        for (final e in tabs.entries)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Material(
                color: tab == e.key ? CpColors.navy : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                      color: tab == e.key ? CpColors.navy : CpColors.line),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onTab(e.key),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(e.value,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: tab == e.key
                                  ? Colors.white
                                  : AppColors.slate)),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  // ---------------------------------------------------------------- shifts

  Widget _shiftsTab(List<Map<String, dynamic>> shifts) {
    final filters = {
      'all': 'All',
      for (final e in _Cp.dutyTypes.entries)
        e.key: switch (e.key) {
          'home' => 'Home',
          'ward' => 'Lab',
          'icu' => 'ICU',
          'specialty' => 'Department',
          _ => 'Casualty',
        },
    };
    final shown = shiftFilter == 'all'
        ? shifts
        : shifts.where((s) => s['dutyType'] == shiftFilter).toList();
    return ListView(
      padding: const EdgeInsets.only(top: 12, bottom: 24),
      children: [
        CpFilterChips(
            options: filters, selected: shiftFilter, onSelected: onShiftFilter),
        const SizedBox(height: 12),
        if (_profileIncomplete) _completeProfileBanner(),
        if (openShifts == null)
          const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()))
        else if (shown.isEmpty)
          CpEmpty(
              (me['available'] == false || me['isOnline'] == false) ? '🌙' : '🔍',
              (me['available'] == false || me['isOnline'] == false)
                  ? 'You are Off. Turn on Available (top right) to see and get new shifts and home visits.'
                  : 'No matching shifts right now. New duties appear here as soon as a hospital posts one that fits your profile.')
        else
          for (final s in shown)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: TechnicianShiftCard(
                fromMyAgency: _Cp.agencyWindowOpen(s, now),
                shift: s,
                now: now,
                busy: busy.contains(s['id']),
                onClaim: () => onClaim(s),
                onDecline: onDecline == null || !_Cp.isHomeVisit(s)
                    ? null
                    : () => onDecline!(s),
              ),
            ),
      ],
    );
  }

  Widget _completeProfileBanner() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.warningTint,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.warningBorder),
          ),
          child: Row(children: [
            const Text('📝', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                  'Add your duty types and areas so you only see shifts that fit you.',
                  style: TextStyle(fontSize: 13, color: AppColors.warningDeep)),
            ),
            TextButton(onPressed: onEditProfile, child: const Text('Complete')),
          ]),
        ),
      );

  // ------------------------------------------------------------------ jobs

  Widget _jobsTab(List<Map<String, dynamic>> fitting,
      [List<Map<String, dynamic>> teams = const []]) {
    final filters = {
      'all': 'All',
      for (final e in _Cp.jobTimings.entries) e.key: '${e.value.$2} ${e.value.$1}',
    };
    final shown = jobFilter == 'all'
        ? fitting
        : fitting.where((j) => j['timing'] == jobFilter).toList();
    return ListView(
      padding: const EdgeInsets.only(top: 14, bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: CpHero(
            label: 'Full-Time Technician Positions',
            value: '${fitting.length + teams.length}',
            valueSuffix: 'matching',
            note: 'Permanent hospital jobs · monthly salary · based on your profile',
          ),
        ),
        const SizedBox(height: 14),
        // hospitals asking for a full-time team (3 technicians, rotation)
        if (teams.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Full-time team openings',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: CpColors.ink)),
          ),
          for (final t in teams)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TechnicianShiftCard(
                shift: t,
                now: now,
                busy: busy.contains(t['id']),
                onClaim: () => onClaim(t),
              ),
            ),
          const SizedBox(height: 4),
        ],
        CpFilterChips(
            options: filters, selected: jobFilter, onSelected: onJobFilter),
        const SizedBox(height: 12),
        if (jobs == null)
          const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()))
        else if (shown.isEmpty && teams.isEmpty)
          const CpEmpty('🏥',
              'No full-time positions match your profile right now. Check back soon.')
        else
          for (final j in shown)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TechnicianJobCard(
                job: j,
                interested: _Cp.hasInterest(j, (me['uid'] ?? '').toString()),
                onTap: () => onJob(j),
              ),
            ),
      ],
    );
  }

  // --------------------------------------------------------- applied jobs

  /// The full-time team jobs the doctor applied to, and where each stands.
  Widget _appliedTab() {
    final uid = (me['uid'] ?? '').toString();
    final list = applications;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        if (list == null)
          const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()))
        else if (list.isEmpty)
          const CpEmpty('📨',
              'You have not applied to any full-time job yet. Open the Jobs tab to apply.')
        else
          for (final r in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _applicationCard(r, uid),
            ),
      ],
    );
  }

  Widget _applicationCard(Map<String, dynamic> r, String uid) {
    final status = _Cp.applicationStatus(r, uid);
    final (label, color, note) = switch (status) {
      'selected' => (
          'SELECTED',
          CpColors.green,
          'You are placed in this full-time team. Your duties are on your calendar and the duty roster.'
        ),
      'shortlisted' => (
          'SHORTLISTED',
          const Color(0xFFD97706),
          'You are among the best applicants. The agency is choosing the three for the hospital.'
        ),
      'not_selected' => (
          'NOT SELECTED',
          CpColors.red,
          'The agency placed other technicians for this team.'
        ),
      'closed' => (
          'CLOSED',
          CpColors.muted,
          'This opening was cancelled or the team was not placed in time.'
        ),
      _ => (
          'APPLIED',
          const Color(0xFF2563EB),
          'Waiting for the agency. The best 10 applicants are shortlisted for it.'
        ),
    };
    final first = (r['shiftAssignments'] as Map?)?.entries
        .where((e) => e.value == (me['name'] ?? ''))
        .map((e) => e.key.toString())
        .firstOrNull;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: cpCard(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CpEmojiTile(_Cp.dutyEmoji(r['dutyType']?.toString()),
              CpColors.duty(r['dutyType']?.toString())),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((r['hospitalName'] ?? 'Hospital').toString(),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800, color: CpColors.ink)),
              Text(
                  '${_Cp.dutyLabel(r['dutyType']?.toString())} · Full-time · weekly rotation from ${r['anchor'] ?? ''}',
                  style: const TextStyle(fontSize: 12, color: CpColors.muted)),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(formatInr(_Cp.doctorPayOf(r)),
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800, color: CpColors.navy)),
            const Text('per month',
                style: TextStyle(fontSize: 11, color: CpColors.muted)),
          ]),
        ]),
        const SizedBox(height: 10),
        CpTag(label, color, filled: false),
        const SizedBox(height: 6),
        Text(note, style: const TextStyle(fontSize: 12.5, color: CpColors.muted)),
        if (status == 'selected' && first != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('First week: ${const {
              'morning': 'Morning',
              'evening': 'Evening',
              'night': 'Night',
            }[first] ?? first} shift',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
      ]),
    );
  }

  // ---------------------------------------------------------------- duties

  Widget _dutiesTab() {
    final count = myShifts
        .where((s) => const {'claimed', 'on_duty', 'completed'}
            .contains(s['status']))
        .length;
    return TechnicianMyDutiesView(
      uid: (me['uid'] ?? '').toString(),
      myShifts: myShifts,
      now: now,
      header: Column(children: [
        CpHero(
          label: 'Confirmed shift earnings',
          value: formatInr(_Cp.confirmedEarnings(myShifts)),
          note: '$count shift${count == 1 ? '' : 's'} claimed · paid per shift, rate agreed up front',
        ),
        if (agencyDuties != null) ...[
          const SizedBox(height: 14),
          agencyDuties!,
        ],
      ]),
      cardFor: (s) => TechnicianDutyCard(
        shift: s,
        now: now,
        busy: busy.contains(s['id']),
        onCheckIn: () => onCheckIn(s),
        onArrivalOtp: onArrivalOtp == null ? null : () => onArrivalOtp!(s),
        onCheckOut: () => onCheckOut(s),
      ),
    );
  }

  // --------------------------------------------------------------- profile

  Widget _documentsRow() {
    final verified = _Cp.isVerified(me);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onDocuments,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: cpCard(),
          child: Row(children: [
            const Text('📄', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Verification documents',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, color: CpColors.ink)),
                  Text(
                      verified
                          ? 'Approved — you can claim duties.'
                          : 'Upload your documents. You can claim duties once the admin approves them.',
                      style:
                          const TextStyle(fontSize: 12, color: CpColors.muted)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: CpColors.muted),
          ]),
        ),
      ),
    );
  }

  Widget _agencyRow() {
    final name = (me['agencyName'] ?? '').toString();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: cpCard(),
      child: Row(children: [
        const Text('🏢', style: TextStyle(fontSize: 22)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name.isEmpty ? 'Freelancer' : name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: CpColors.ink)),
              Text(
                  name.isEmpty
                      ? 'Working with an agency? Join it to get its visits first.'
                      : "You get this agency's patients' home visits first.",
                  style: const TextStyle(fontSize: 12, color: CpColors.muted)),
            ],
          ),
        ),
        if (name.isEmpty && onJoinAgency != null)
          TextButton(onPressed: onJoinAgency, child: const Text('Join'))
        else if (name.isNotEmpty && onLeaveAgency != null)
          TextButton(
              onPressed: onLeaveAgency,
              child: const Text('Leave',
                  style: TextStyle(color: AppColors.danger))),
      ]),
    );
  }

  Widget _profileTab() {
    final verified = _Cp.isVerified(me);
    final years = (me['experienceYears'] ?? me['experience'] ?? '').toString();
    final line = [
      (me['qualification'] ?? '').toString(),
      if (years.isNotEmpty) '$years years',
      if ((me['regNo'] ?? '').toString().isNotEmpty) 'Reg ${me['regNo']}',
    ].where((e) => e.isNotEmpty).join(' · ');
    Widget section(String title, List<String> items) => Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: CpColors.ink)),
              const SizedBox(height: 8),
              CpChipWrap(items),
            ],
          ),
        );
    final procedures = [
      for (final k in _Cp.listOf(me['procedures']))
        if (_Cp.procedures[k] != null)
          '${_Cp.procedures[k]!.$1} ${_Cp.procedures[k]!.$2}'
    ];
    final duties = [
      for (final k in _Cp.listOf(me['dutyTypes']))
        if (_Cp.dutyTypes[k] != null)
          '${_Cp.dutyTypes[k]!.$1} ${_Cp.dutyTypes[k]!.$2}'
    ];
    final noShows = toNum(me['noShows']) ?? 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: cpCard(),
          child: Column(children: [
            Row(children: [
              const CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.primarySoft,
                child: Text('👩‍⚕️', style: TextStyle(fontSize: 26)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((me['name'] ?? '').toString(),
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: CpColors.ink)),
                    const SizedBox(height: 2),
                    Text(line,
                        style: const TextStyle(
                            fontSize: 12, color: CpColors.muted)),
                    const SizedBox(height: 6),
                    verified
                        ? const CpTag('✓ VERIFIED', CpColors.green,
                            filled: false)
                        : const CpTag('VERIFICATION PENDING', AppColors.warning,
                            filled: false),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onEditProfile,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 46),
                  foregroundColor: CpColors.navy,
                  side: const BorderSide(color: CpColors.line),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Edit profile',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        _agencyRow(),
        if (onDocuments != null) ...[
          const SizedBox(height: 12),
          _documentsRow(),
        ],
        if (noShows > 0)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
                'No-shows: $noShows of ${_Cp.maxNoShows}. At ${_Cp.maxNoShows} claiming is paused.',
                style: const TextStyle(fontSize: 12, color: CpColors.red)),
          ),
        section('Tests', procedures),
        section('Duty types', duties),
        section('Age groups', cpLabels(me['ageGroups'], _Cp.ageGroups)),
        section('Specialties', cpLabels(me['specialties'], _Cp.specialties)),
        section('Areas', [for (final a in _Cp.listOf(me['areas'])) '📍 $a']),
        section('Preferred hospitals',
            [for (final h in _Cp.listOf(me['preferredHospitals'])) '🏥 $h']),
        const DeleteAccountButton(),
      ],
    );
  }
}

/// An open shift with its Claim button; a patient's home visit has Accept
/// and Decline.
class TechnicianShiftCard extends StatelessWidget {
  final Map<String, dynamic> shift;
  final DateTime now;
  final bool busy;
  final VoidCallback onClaim;
  final VoidCallback? onDecline;

  /// Offered to my agency's doctors first (15 min).
  final bool fromMyAgency;
  const TechnicianShiftCard(
      {super.key,
      required this.shift,
      required this.now,
      this.busy = false,
      required this.onClaim,
      this.onDecline,
      this.fromMyAgency = false});

  @override
  Widget build(BuildContext context) {
    final type = shift['dutyType']?.toString();
    final urgent = shift['urgent'] == true;
    final color = CpColors.duty(type, urgent: urgent);
    final specialty = _Cp.specialtyLabel(shift['specialty']?.toString());
    final procs = _Cp.listOf(shift['procedures']);
    final visit = _Cp.isHomeVisit(shift);
    final team = _Cp.isTeam(shift);
    final accept = ElevatedButton(
      onPressed: busy ? null : onClaim,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 46),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
          busy
              ? (visit ? 'Accepting…' : 'Claiming…')
              : (visit || team ? 'Accept' : 'Claim this shift'),
          style: const TextStyle(fontWeight: FontWeight.w800)),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: cpCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CpEmojiTile(_Cp.dutyEmoji(type), color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((shift['hospitalName'] ?? 'Hospital').toString(),
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: CpColors.ink)),
                    Text(
                        [_Cp.dutyLabel(type), if (specialty.isNotEmpty) specialty]
                            .join(' · '),
                        style: const TextStyle(
                            fontSize: 12, color: CpColors.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (urgent) const CpTag('URGENT', CpColors.red),
                  if (urgent) const SizedBox(height: 4),
                  Text(formatInr(_Cp.doctorPayOf(shift)),
                      style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: color)),
                  Text(
                      visit
                          ? 'per visit'
                          : _Cp.isAgencySplit(shift)
                              ? 'your share'
                              : shift['payPeriod'] == 'month'
                                  ? 'per month'
                                  : 'per shift',
                      style: TextStyle(fontSize: 11, color: CpColors.muted)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (team)
              CpInfo(
                  '👥 Team of ${_Cp.teamSizeOf(shift)} · the agency picks',
                  color: const Color(0xFF7C3AED),
                  background: const Color(0xFFF3E8FF)),
            if (fromMyAgency)
              const CpInfo('🏢 From your agency · first 15 min',
                  color: AppColors.violet, background: AppColors.purpleSoft),
            if (shift['rotation'] == true)
              const CpInfo('🔁 Full-time · weekly rotation (Morning, Evening, Night)')
            else ...[
              CpInfo('📅 ${_Cp.dayLabel(shift, now)}'),
              CpInfo('🕐 ${_Cp.slotLabel(shift)} · ${_Cp.timeRange(shift)}'),
            ],
            if ((shift['area'] ?? '').toString().isNotEmpty)
              CpInfo('📍 ${shift['area']}'),
          ]),
          if (procs.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final p in procs)
                CpInfo(
                    '${_Cp.procedures[p]?.$1 ?? ''} ${_Cp.procedures[p]?.$2 ?? p}',
                    color: CpColors.navy,
                    background: AppColors.primarySoft),
            ]),
          ],
          const SizedBox(height: 12),
          if (onDecline == null)
            SizedBox(width: double.infinity, child: accept)
          else
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onDecline,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: CpColors.red,
                    side: const BorderSide(color: CpColors.red),
                    minimumSize: const Size(0, 46),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Decline',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: accept),
            ]),
        ],
      ),
    );
  }
}

/// A full-time job in the Jobs list.
class TechnicianJobCard extends StatelessWidget {
  final Map<String, dynamic> job;
  final bool interested;
  final VoidCallback onTap;
  const TechnicianJobCard(
      {super.key,
      required this.job,
      required this.interested,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final type = job['dutyType']?.toString();
    final urgent = job['urgent'] == true;
    final color = CpColors.duty(type, urgent: urgent);
    final timing = _Cp.jobTimings[job['timing']];
    final openings = toNum(job['openings'])?.toInt() ?? 1;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: CpColors.line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CpEmojiTile(_Cp.dutyEmoji(type), color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text((job['title'] ?? 'Position').toString(),
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: CpColors.ink)),
                        Text((job['hospitalName'] ?? '').toString(),
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primaryDark)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (urgent) const CpTag('URGENT', CpColors.red),
                      if (urgent) const SizedBox(height: 4),
                      Text(_Cp.salaryLabel(job),
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: color)),
                      const Text('per month',
                          style:
                              TextStyle(fontSize: 11, color: CpColors.muted)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (timing != null) CpInfo('${timing.$1} ${timing.$2}'),
                if ((job['unit'] ?? '').toString().isNotEmpty)
                  CpInfo('🏥 ${job['unit']}'),
                CpInfo('$openings opening${openings == 1 ? '' : 's'}',
                    color: CpColors.green,
                    background: AppColors.successSoft),
                if (interested)
                  const CpInfo('✓ Interest sent',
                      color: CpColors.navy, background: AppColors.primarySoft),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// A claimed shift in My duties, with Check in / Check out.
class TechnicianDutyCard extends StatelessWidget {
  final Map<String, dynamic> shift;
  final DateTime now;
  final bool busy;
  final VoidCallback onCheckIn;
  final VoidCallback? onArrivalOtp;
  final VoidCallback onCheckOut;
  const TechnicianDutyCard({
    super.key,
    required this.shift,
    required this.now,
    this.busy = false,
    required this.onCheckIn,
    this.onArrivalOtp,
    required this.onCheckOut,
  });

  @override
  Widget build(BuildContext context) {
    final type = shift['dutyType']?.toString();
    final status = (shift['status'] ?? '').toString();
    final otpMode = _Cp.usesArrivalOtp(shift);
    final activeOtp = _Cp.activeArrivalOtp(shift, now);
    final (label, color) = switch (status) {
      'pending_agency' => ('WAITING FOR AGENCY', AppColors.warning),
      'team_applied' => ('WAITING FOR AGENCY TO PICK', const Color(0xFFD97706)),
      'on_duty' => ('ON DUTY', CpColors.green),
      'completed' => ('COMPLETED', CpColors.green),
      'absent' => ('NO-SHOW', CpColors.red),
      'cancelled' => ('CANCELLED', CpColors.muted),
      _ => ('CONFIRMED', AppColors.blue),
    };
    final late = toNum(shift['lateMinutes'])?.toInt() ?? 0;
    final canIn = _Cp.canCheckIn(shift, now);
    final canOut = _Cp.canCheckOut(shift);
    String? note;
    if (status == 'team_applied') {
      note = 'You applied. The best 10 applicants go to the agency, which picks the three for the hospital.';
    } else if (status == 'pending_agency') {
      note = 'Your agency has to approve this request before it is allocated to the hospital.';
    } else if (status == 'claimed' && canIn && otpMode) {
      note = 'Please reach by ${_Cp.clock(_Cp.reachBy(shift))}. At the hospital, tap Get arrival OTP and show it to them. '
          'Your location is checked once, at that moment, and you must be within ${_Cp.arrivalRadiusMeters.round()} m.';
    } else if (status == 'claimed' && canIn) {
      note = 'Please reach by ${_Cp.clock(_Cp.reachBy(shift))} and check in.';
    } else if (status == 'claimed' && !canIn) {
      note = 'Confirmed — please reach by ${_Cp.clock(_Cp.reachBy(shift))}. '
          'Check-in opens 1 hour before the start.';
    } else if (status == 'cancelled') {
      note = 'The hospital cancelled this shift.';
    } else if (status == 'absent') {
      note = 'You did not check in. This counts as a no-show.';
    } else if (late > 0) {
      note = 'Checked in $late min late.';
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: cpCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CpEmojiTile(_Cp.dutyEmoji(type), CpColors.duty(type)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((shift['hospitalName'] ?? '').toString(),
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: CpColors.ink)),
                    Text(
                        '${_Cp.dutyLabel(type)} · ${_Cp.dayLabel(shift, now)} · '
                        '${_Cp.slotLabel(shift)} (${_Cp.timeRange(shift)})',
                        style: const TextStyle(
                            fontSize: 12, color: CpColors.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatInr(_Cp.doctorPayOf(shift)),
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: CpColors.navy)),
                  const SizedBox(height: 4),
                  CpTag(label, color, filled: false),
                ],
              ),
            ],
          ),
          if (_Cp.isHomeVisit(shift) &&
              const {'claimed', 'on_duty'}.contains(status)) ...[
            const SizedBox(height: 10),
            _patientDetails(),
          ],
          if (note != null) ...[
            const SizedBox(height: 8),
            Text(note,
                style: const TextStyle(fontSize: 12, color: CpColors.muted)),
          ],
          if (activeOtp != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Column(children: [
                const Text('YOUR ARRIVAL OTP',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF92400E))),
                Text(activeOtp,
                    style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 8,
                        color: CpColors.ink)),
                const Text('Show this to the hospital. Valid for 10 minutes.',
                    style: TextStyle(fontSize: 11.5, color: CpColors.muted)),
              ]),
            ),
          ],
          if (canIn && otpMode && onArrivalOtp != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: busy ? null : onArrivalOtp,
                icon: const Icon(Icons.pin_drop_rounded, size: 18),
                label: Text(activeOtp == null ? 'Get arrival OTP' : 'Get a new OTP',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: CpColors.green,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 44),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
          if ((canIn && !otpMode) || canOut) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: busy ? null : (canOut ? onCheckOut : onCheckIn),
                icon: Icon(canOut ? Icons.logout_rounded : Icons.login_rounded,
                    size: 18),
                label: Text(canOut ? 'Check out' : 'Check in',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: canOut ? CpColors.navy : CpColors.green,
                  iconColor: Colors.white,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 44),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

extension on TechnicianDutyCard {
  /// Home visit booked by a patient: who, where, how to reach them.
  Widget _patientDetails() {
    final phone = (shift['patientPhone'] ?? '').toString();
    final notes = (shift['notes'] ?? '').toString();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.mintTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('👤 ${shift['posterName'] ?? 'Patient'}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          if ((shift['address'] ?? '').toString().isNotEmpty)
            Text('🏠 ${shift['address']}, ${shift['area'] ?? ''}',
                style: const TextStyle(fontSize: 13)),
          if (notes.isNotEmpty)
            Text('📝 $notes',
                style: const TextStyle(fontSize: 12, color: CpColors.muted)),
          if (phone.isNotEmpty)
            TextButton.icon(
              onPressed: () => labLaunchUrl(Uri(scheme: 'tel', path: phone)),
              icon: const Icon(Icons.call_rounded, size: 18),
              label: Text('Call $phone'),
              style: TextButton.styleFrom(
                  padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
            ),
        ],
      ),
    );
  }
}

class _ConfirmClaimSheet extends StatelessWidget {
  final Map<String, dynamic> shift;
  const _ConfirmClaimSheet({required this.shift});

  @override
  Widget build(BuildContext context) {
    final now = IstClock.now();
    final type = shift['dutyType']?.toString();
    final visit = _Cp.isHomeVisit(shift);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(visit ? 'Accept this home visit?' : 'Confirm this shift?',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: CpColors.ink)),
            const SizedBox(height: 6),
            Text('${shift['hospitalName']} · ${_Cp.dutyLabel(type)}',
                style: const TextStyle(color: CpColors.muted)),
            Text(
                '${_Cp.dayLabel(shift, now)} · ${_Cp.slotLabel(shift)} (${_Cp.timeRange(shift)})',
                style: const TextStyle(color: CpColors.muted)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primaryTint,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                Expanded(
                    child: Text(
                        visit
                            ? 'Visit fee'
                            : _Cp.isAgencySplit(shift)
                                ? 'You earn'
                                : 'Shift pay',
                        style: const TextStyle(fontWeight: FontWeight.w600))),
                Text(formatInr(_Cp.doctorPayOf(shift)),
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: CpColors.navy)),
              ]),
            ),
            const SizedBox(height: 12),
            Text(
                visit
                    ? 'Patient area: ${shift['area'] ?? ''}. Please reach by ${_Cp.clock(_Cp.reachBy(shift))}. Repeated no-shows reduce your reliability score and can suspend your account.'
                    : 'By claiming, you commit to attending this shift. Repeated no-shows reduce your reliability score and can suspend your account.',
                style: TextStyle(fontSize: 12, color: CpColors.muted)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48)),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CpColors.navy,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 48),
                  ),
                  child: Text(visit ? 'Accept visit' : 'Confirm shift',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _JobSheet extends StatelessWidget {
  final Map<String, dynamic> job;
  final bool interested;
  final VoidCallback onInterest;
  const _JobSheet(
      {required this.job, required this.interested, required this.onInterest});

  @override
  Widget build(BuildContext context) {
    final type = job['dutyType']?.toString();
    final timing = _Cp.jobTimings[job['timing']];
    final quals = _Cp.listOf(job['qualifications']);
    final procs = _Cp.listOf(job['procedures']);
    final openings = toNum(job['openings'])?.toInt() ?? 1;
    final benefits = (job['benefits'] ?? '').toString();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: [
          Row(children: [
            CpEmojiTile(_Cp.dutyEmoji(type),
                CpColors.duty(type, urgent: job['urgent'] == true)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (job['urgent'] == true)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 4),
                      child: CpTag('URGENT HIRING', CpColors.red),
                    ),
                  Text((job['title'] ?? '').toString(),
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: CpColors.ink)),
                  Text((job['hospitalName'] ?? '').toString(),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryDark)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 14),
          Text(
              [
                if ((job['unit'] ?? '').toString().isNotEmpty) '🏥 ${job['unit']}',
                if ((job['area'] ?? '').toString().isNotEmpty) '📍 ${job['area']}',
              ].join(' · '),
              style: const TextStyle(color: CpColors.muted)),
          const SizedBox(height: 10),
          Row(children: [
            Text(_Cp.salaryLabel(job),
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: CpColors.navy)),
            const Text('  per month', style: TextStyle(color: CpColors.muted)),
            const Spacer(),
            CpInfo('$openings opening${openings == 1 ? '' : 's'}',
                color: CpColors.green, background: AppColors.successSoft),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (timing != null)
              CpInfo([
                '${timing.$1} ${timing.$2}',
                if ((job['timingNote'] ?? '').toString().isNotEmpty)
                  job['timingNote'],
              ].join(' · ')),
            CpInfo('${_Cp.dutyEmoji(type)} ${_Cp.dutyLabel(type)}'),
            if ((job['createdAt'] ?? '').toString().isNotEmpty)
              CpInfo('📣 Posted ${_ago(job['createdAt'].toString())}'),
          ]),
          if (quals.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('Qualifications',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            CpChipWrap([for (final q in quals) '🎓 $q']),
          ],
          if (procs.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('Tests',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            CpChipWrap([
              for (final p in procs)
                '${_Cp.procedures[p]?.$1 ?? ''} ${_Cp.procedures[p]?.$2 ?? p}'
            ]),
          ],
          if (benefits.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.successTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('✅ $benefits',
                  style: const TextStyle(color: AppColors.successDeep)),
            ),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: interested ? null : onInterest,
            style: ElevatedButton.styleFrom(
              backgroundColor: CpColors.navy,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(interested ? '✓ Interest sent' : 'Express Interest',
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  static String _ago(String iso) {
    final t = IstClock.tryParse(iso);
    if (t == null) return '';
    final d = IstClock.now().difference(t);
    if (d.inDays >= 1) return '${d.inDays}d ago';
    if (d.inHours >= 1) return '${d.inHours}h ago';
    return 'just now';
  }
}

/// The technician's verification documents (same uploads and admin
/// review as every other provider).
class _DocumentsScreen extends StatelessWidget {
  final String uid;
  const _DocumentsScreen({required this.uid});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: CpColors.page,
        appBar: AppBar(title: const Text('Verification documents')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            VerificationDocumentsSection(
                role: 'technician',
                uid: uid,
                accentColor: CpColors.navy),
          ],
        ),
      );
}
