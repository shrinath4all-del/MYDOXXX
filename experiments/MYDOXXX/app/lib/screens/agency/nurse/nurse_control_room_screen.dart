import 'dart:async';
import '../../../utils/safe_cast.dart';

import 'package:flutter/material.dart';

import '../../../services/auth_service.dart';
import '../../../services/care_agency_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/error_messages.dart';
import '../../../utils/stream_cache.dart';
import '../../auth/login_screen.dart';
import '../../shifts/nurse_shift_board_screen.dart';
import 'nurse_bookings_calendar_screen.dart';
import 'nurse_agency_duties_screen.dart';
import '../care/earnings_screen.dart';
import 'nurse_hospital_requests_screen.dart';
import '../control_room_widgets.dart';
import 'nurse_forms.dart';
import '../../../constants/app_colors.dart';
import '../../../widgets/notification_bell.dart';

export '../control_room_widgets.dart' show formatInr;
import '../../../utils/ist_clock.dart';

/// Nurse Console (agency): doctor pool, today's attendance,
/// money and the duty list (handover v1, section 3).
class NurseAgencyControlRoomScreen extends StatefulWidget {
  final String agencyId;
  const NurseAgencyControlRoomScreen({super.key, required this.agencyId});

  @override
  State<NurseAgencyControlRoomScreen> createState() =>
      _AgencyControlRoomScreenState();
}

class _AgencyControlRoomScreenState extends State<NurseAgencyControlRoomScreen> {
  final StreamCache _streams = StreamCache();
  Timer? _tick;
  String _period = 'today';
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    // Late / absent depend on the clock: refresh every minute
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _logout() async {
    await AuthService().signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _open(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.danger : ControlRoomColors.green,
    ));
  }


  Future<void> _dutyActions(
      Map<String, dynamic> agency, Map<String, dynamic> d, String state) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text((d['doctorName'] ?? '').toString(),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text((d['hospitalName'] ?? '').toString()),
            ),
            if (state == 'scheduled' || state == 'late')
              ListTile(
                leading: const Icon(Icons.person_off_outlined,
                    color: ControlRoomColors.red),
                title: const Text('Mark absent'),
                onTap: () => Navigator.pop(ctx, 'absent'),
              ),
            if (state == 'absent' || state == 'late')
              ListTile(
                leading: const Icon(Icons.swap_horiz_rounded),
                title: const Text('Reassign to a "No job" nurse'),
                onTap: () => Navigator.pop(ctx, 'reassign'),
              ),
            if (state == 'scheduled' || state == 'late')
              ListTile(
                leading: const Icon(Icons.cancel_outlined),
                title: const Text('Cancel duty'),
                onTap: () => Navigator.pop(ctx, 'cancelled'),
              ),
            if (state == 'on_duty' || state == 'completed')
              const ListTile(
                leading: Icon(Icons.info_outline),
                title:
                    Text('The nurse checks in and out from the nurse app.'),
              ),
          ],
        ),
      ),
    );
    if (action == null) return;
    try {
      if (action == 'reassign') {
        if (state == 'late') {
          await CareAgencyService.setDutyStatus(d['id'], 'absent');
        }
        _open(NurseDutyFormScreen(agency: agency, copyFrom: d));
        return;
      }
      await CareAgencyService.setDutyStatus(d['id'], action);
      _snack(action == 'absent' ? 'Marked absent.' : 'Duty cancelled.');
    } catch (e) {
      _snack(ErrorMessages.of(e, action: 'update the duty'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = IstClock.now();
    final range = CareAgencyService.periodRange(_period, now);

    return StreamBuilder<Map<String, dynamic>>(
      stream: _streams.get(
          'agency', () => CareAgencyService.agencyStream(widget.agencyId)),
      builder: (context, agencySnap) {
        final agency = agencySnap.data ?? {'id': widget.agencyId};
        return Scaffold(
          backgroundColor: ControlRoomColors.page,
          appBar: AppBar(
            title: const Text('Nurse Console'),
            actions: [
              NotificationBell(
                uid: widget.agencyId,
                collection: 'agencies',
                forPatient: false,
                iconColor: AppColors.ink,
                onOpenItem: () {},
              ),
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => showNurseAgencySettingsDialog(context, agency),
              ),
              IconButton(
                tooltip: 'Log out',
                icon: const Icon(Icons.logout_rounded),
                onPressed: _logout,
              ),
            ],
          ),
          body: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _streams.get('nurses',
                () => CareAgencyService.doctorsStream(widget.agencyId)),
            builder: (context, docSnap) =>
                StreamBuilder<List<Map<String, dynamic>>>(
              // the period always includes today, so attendance comes from
              // the same list
              stream: _streams.get(
                  'duties:${range.from}:${range.to}',
                  () => CareAgencyService.dutiesStream(
                      widget.agencyId, range.from, range.to)),
              builder: (context, dutySnap) {
                final error = docSnap.error ?? dutySnap.error;
                if (error != null) {
                  return LoadErrorView(error: error, what: 'the control room');
                }
                if (!docSnap.hasData || !dutySnap.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.primaryTeal));
                }
                final todayKey = CareAgencyService.dateKey(now);
                // 4 h without check-in: absent
                CareAgencyService.autoMarkAbsent(
                    dutySnap.data!.where((d) => d['date'] == todayKey).toList(),
                    now);
                return NurseControlRoomView(
                  agency: agency,
                  doctors: docSnap.data!,
                  duties: dutySnap.data!,
                  now: now,
                  period: _period,
                  filter: _filter,
                  onPeriod: (p) => setState(() => _period = p),
                  onFilter: (f) => setState(() => _filter = f),
                  onDoctors: () => _open(NurseAgencyDoctorsScreen(agency: agency)),
                  onHospitals: () =>
                      _open(NurseAgencyHospitalsScreen(agency: agency)),
                  onPayouts: () => _open(NurseAgencyPayoutsScreen(agency: agency)),
                  onBookings: () => _open(
                      NurseAgencyBookingsScreen(agencyId: widget.agencyId)),
                  onDuties: () => _open(
                      NurseAgencyDutiesScreen(agencyId: widget.agencyId)),
                  onEarnings: () => _open(
                      AgencyEarningsScreen(agencyId: widget.agencyId)),
                  onRequests: () => _open(NurseHospitalRequestsScreen(
                      agency: {...agency, 'id': widget.agencyId})),
                  // open shifts / jobs for any nurse in the area;
                  // a claimed shift becomes a duty here
                  onShiftBoard: () => _open(NurseShiftBoardScreen(
                    postedBy: 'agency',
                    posterId: widget.agencyId,
                    posterName: (agency['name'] ?? 'Partner').toString(),
                    agencyId: widget.agencyId,
                    hospitals:
                        CareAgencyService.hospitalsStream(widget.agencyId)
                            .map((list) => [
                                  for (final h in list)
                                    (
                                      id: h['id'].toString(),
                                      name: (h['name'] ?? '').toString(),
                                      area: (h['area'] ?? '').toString(),
                                    )
                                ]),
                  )),
                  onDuty: (d, state) => _dutyActions(agency, d, state),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// The Control Room contents for given data (no Firestore; used by the
/// screen and by layout tests).
class NurseControlRoomView extends StatelessWidget {
  final Map<String, dynamic> agency;
  final List<Map<String, dynamic>> doctors;
  final List<Map<String, dynamic>> duties; // duties of the period
  final DateTime now;
  final String period;
  final String filter;
  final ValueChanged<String> onPeriod;
  final ValueChanged<String> onFilter;
  final VoidCallback onDoctors;
  final VoidCallback onHospitals;
  final VoidCallback onPayouts;
  final VoidCallback? onShiftBoard;
  final VoidCallback? onRequests;
  final VoidCallback? onDuties;
  final VoidCallback? onEarnings;

  /// Bookings & Calendar: every duty by month.
  final VoidCallback? onBookings;

  final void Function(Map<String, dynamic> duty, String state) onDuty;

  const NurseControlRoomView({
    super.key,
    required this.agency,
    required this.doctors,
    required this.duties,
    required this.now,
    required this.period,
    required this.filter,
    required this.onPeriod,
    required this.onFilter,
    required this.onDoctors,
    required this.onHospitals,
    required this.onPayouts,
    this.onShiftBoard,
    this.onRequests,
    this.onDuties,
    this.onEarnings,
    this.onBookings,
    required this.onDuty,
  });

  @override
  Widget build(BuildContext context) {
    final s = CareAgencyService.summarize(
        doctors: doctors, periodDuties: duties, now: now);
    final todayKey = CareAgencyService.dateKey(now);
    final todayDuties = duties.where((d) => d['date'] == todayKey).toList();
    final p = periodLabels[period]!.toUpperCase();
    final doctorPct = toNum(agency['splitDoctorPct']) ?? 80;
    final agencyPct = toNum(agency['splitAgencyPct']) ?? 15;
    final appPct = toNum(agency['splitAppPct']) ?? 5;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        MaxWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ControlRoomHeader(
                title: 'Nurse Console',
                brand: 'MyDox × Partner',
                subtitle: 'Partner: ${agency['name'] ?? '—'} · '
                    '${s.totalDoctors} nurses · '
                    'Today, ${longDate(now)}',
                period: period,
                onPeriod: onPeriod,
              ),
              const SizedBox(height: 10),
              QuickLinks(links: [
                (Icons.groups_rounded, 'Nurses', onDoctors),
                (Icons.local_hospital_outlined, 'Hospitals', onHospitals),
                if (onBookings != null)
                  (Icons.calendar_month_rounded, 'Bookings & Calendar', onBookings!),
                (Icons.payments_outlined, 'Payouts', onPayouts),
                if (onEarnings != null)
                  (Icons.currency_rupee_rounded, 'Earnings', onEarnings!),
                if (onDuties != null)
                  (
                    Icons.assignment_ind_outlined,
                    'Nurses duties',
                    onDuties!
                  ),
                if (onRequests != null)
                  (
                    Icons.local_hospital_rounded,
                    'Hospital requests',
                    onRequests!
                  ),
                if (onShiftBoard != null)
                  (
                    Icons.work_outline_rounded,
                    'Open shifts & jobs',
                    onShiftBoard!
                  ),
              ]),
              const SectionTitle('1 · DOCTOR POOL'),
              StatGrid(cards: [
                StatCard(
                    label: 'TOTAL CARE PHYSICIANS',
                    value: '${s.totalDoctors}',
                    color: ControlRoomColors.ink),
                StatCard(
                    label: 'PERMANENT / FULL-TIME PLACED',
                    value: '${s.permanentPlaced}',
                    color: ControlRoomColors.indigo,
                    hint: 'Working at hospitals via partner'),
                StatCard(
                    label: 'LOCUM SENT $p',
                    value: '${s.locumSent}',
                    color: ControlRoomColors.blue,
                    hint: 'Ward / ICU / night cover'),
                StatCard(
                    label: 'EMERGENCY LOCUM $p',
                    value: '${s.emergencyLocum}',
                    color: ControlRoomColors.red,
                    hint: 'Urgent call-outs'),
              ]),
              const SectionTitle("2 · TODAY'S ATTENDANCE"),
              StatGrid(minCardWidth: 150, cards: [
                StatCard(
                    label: 'ON DUTY NOW',
                    value: '${s.onDutyNow}',
                    color: ControlRoomColors.green),
                StatCard(
                    label: 'LATE',
                    value: '${s.late}',
                    color: ControlRoomColors.orange,
                    hint: 'Not checked in by start'),
                StatCard(
                    label: 'ABSENT',
                    value: '${s.absent}',
                    color: ControlRoomColors.red,
                    hint: 'No-show / informed'),
                StatCard(
                    label: 'COMPLETED',
                    value: '${s.completed}',
                    color: ControlRoomColors.green),
                StatCard(
                    label: 'NO JOB TODAY',
                    value: '${s.noJobToday}',
                    color: ControlRoomColors.muted,
                    hint: 'Not placed anywhere'),
                StatCard(
                    label: 'ON LEAVE',
                    value: '${s.onLeave}',
                    color: ControlRoomColors.ink),
              ]),
              SectionTitle('3 · REVENUE ($p)'),
              StatGrid(cards: [
                StatCard(
                    label: 'BILLED TO HOSPITALS',
                    value: formatInr(s.billed),
                    color: ControlRoomColors.ink,
                    hint: '100%'),
                StatCard(
                    label: 'DOCTOR PAYOUTS',
                    value: formatInr(s.doctorPayouts),
                    color: ControlRoomColors.green,
                    hint:
                        '$doctorPct% · ${formatInr(s.doctorPaid)} paid · ${formatInr(s.doctorDue)} due'),
                StatCard(
                    label: 'PROFIT',
                    value: formatInr(s.agencyShare),
                    color: ControlRoomColors.indigo,
                    hint: '$agencyPct%'),
                StatCard(
                    label: 'APP SHARE (MYDOX)',
                    value: formatInr(s.appShare),
                    color: ControlRoomColors.teal,
                    hint: '$appPct%'),
              ]),
              const SectionTitle('4 · DUTY LIST (TODAY)'),
              FilterBar(
                filters: const {
                  'all': 'All',
                  'on_duty': 'On duty',
                  'late': 'Late',
                  'absent': 'Absent',
                  'no_job': 'No job',
                  'emergency': 'Emergency',
                },
                selected: filter,
                onSelected: onFilter,
              ),
              const SizedBox(height: 8),
              _dutyList(todayDuties, todayKey),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dutyList(List<Map<String, dynamic>> today, String todayKey) {
    // Problems first (absent, late, emergency), then on duty, scheduled and
    // completed; same state by shift start
    int rank(Map<String, dynamic> d) {
      final state = CareAgencyService.dutyState(d, now);
      if (state == 'absent') return 0;
      if (state == 'late') return 1;
      if (d['type'] == 'emergency') return 2;
      return switch (state) { 'on_duty' => 3, 'scheduled' => 4, _ => 5 };
    }

    final live = today.where((d) => d['status'] != 'cancelled').toList()
      ..sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        if (r != 0) return r;
        return (CareAgencyService.asTime(a['shiftStart']) ?? now)
            .compareTo(CareAgencyService.asTime(b['shiftStart']) ?? now);
      });

    // "No job": active, no duty today, not permanent, not on leave
    final busy = {for (final d in live) d['doctorId']};
    final noJob = doctors
        .where((d) =>
            d['active'] != false &&
            !busy.contains(d['id']) &&
            d['placementType'] != 'permanent' &&
            !CareAgencyService.isOnLeave(d, todayKey))
        .toList();

    final rows = <Widget>[];
    if (filter != 'no_job') {
      for (final d in live) {
        final state = CareAgencyService.dutyState(d, now);
        final lateBy = CareAgencyService.lateMinutes(d, now);
        final match = switch (filter) {
          'on_duty' => state == 'on_duty',
          'late' => state == 'late' || lateBy > 0,
          'absent' => state == 'absent',
          'emergency' => d['type'] == 'emergency',
          _ => true,
        };
        if (match) rows.add(_dutyRow(d, state, lateBy));
      }
    }
    if (filter == 'all' || filter == 'no_job') {
      for (final doc in noJob) {
        rows.add(ListRow(
          badge: const StatusBadge('No job', ControlRoomColors.muted),
          title: (doc['name'] ?? 'Nurse').toString(),
          lines: ['${doc['qualification'] ?? ''} · Available'],
          cells: [
            (doc['name'] ?? 'Nurse').toString(),
            '—',
            'Available',
            '—',
            '—'
          ],
        ));
      }
    }
    return ListPanel(
      rows: rows,
      columns: const [
        ('CARE PHYSICIAN', 3),
        ('HOSPITAL', 3),
        ('JOB TYPE', 2),
        ('SHIFT', 2),
        ('CHECK-IN', 1),
      ],
      trailingHeading: 'DAY PAY',
      initialRows: 10, // first 10, then "View all"
      emptyText: live.isEmpty && doctors.isEmpty
          ? 'No duties yet. Bookings from hospitals and the shift board show here.'
          : 'Nothing to show for this filter.',
    );
  }

  Widget _dutyRow(Map<String, dynamic> d, String state, int lateBy) {
    final emergency = d['type'] == 'emergency';
    final badge = switch (state) {
      'absent' => const StatusBadge('Absent', ControlRoomColors.red),
      'completed' => const StatusBadge('Completed', ControlRoomColors.green),
      'late' => StatusBadge('Late ${lateBy}m', ControlRoomColors.orange),
      'on_duty' => emergency
          ? const StatusBadge('Emergency', ControlRoomColors.red)
          : StatusBadge(lateBy > 0 ? 'On duty · late ${lateBy}m' : 'On duty',
              ControlRoomColors.green),
      _ => emergency
          ? const StatusBadge('Emergency', ControlRoomColors.red)
          : const StatusBadge('Scheduled', ControlRoomColors.muted),
    };
    final start = CareAgencyService.asTime(d['shiftStart']);
    final end = CareAgencyService.asTime(d['shiftEnd']);
    final checkIn = CareAgencyService.asTime(d['checkInAt']);
    final type = CareAgencyService.typeLabels[d['type']] ?? d['type'] ?? '';
    final unit = CareAgencyService.unitLabels[d['unit']] ?? '';

    return ListRow(
      badge: badge,
      title: (d['doctorName'] ?? 'Nurse').toString(),
      lines: [
        '${d['hospitalName'] ?? ''} · $type${emergency || unit.isEmpty ? '' : ' · $unit'}',
        'Shift ${hhmm(start)}–${hhmm(end)} · Check-in ${hhmm(checkIn)}',
      ],
      cells: [
        (d['doctorName'] ?? 'Nurse').toString(),
        (d['hospitalName'] ?? '').toString(),
        '$type${emergency || unit.isEmpty ? '' : ' · $unit'}',
        '${hhmm(start)}–${hhmm(end)}',
        hhmm(checkIn),
      ],
      trailing: Text(formatInr(toNum(d['hospitalRate']) ?? 0),
          style: const TextStyle(
              fontWeight: FontWeight.bold, color: ControlRoomColors.ink)),
      onTap: () => onDuty(d, state),
    );
  }
}
