import 'dart:async';
import '../../../utils/safe_cast.dart';

import 'package:flutter/material.dart';

import '../../../services/care_agency_service.dart';
import '../../../services/firestore_service.dart';
import '../../../services/physio_agency_room.dart';
import '../../../services/physio_agency_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/error_messages.dart';
import '../../../utils/stream_cache.dart';
import '../control_room_widgets.dart';
import '../../../constants/app_colors.dart';
import '../../../widgets/notification_bell.dart';
import '../../../utils/ist_clock.dart';
import '../agency_staff_invite_screen.dart';
import '../../../services/agency_invite_service.dart';

/// Physio agency Control Room: same layout as the care physician agency,
/// for the agency's physio team and the home visits routed to it.
class PhysioControlRoomScreen extends StatefulWidget {
  final String agencyId;
  final VoidCallback onEditProfile;
  final VoidCallback? onInvite;
  final VoidCallback onLogout;
  const PhysioControlRoomScreen({
    super.key,
    required this.agencyId,
    required this.onEditProfile,
    this.onInvite,
    required this.onLogout,
  });

  @override
  State<PhysioControlRoomScreen> createState() =>
      _PhysioControlRoomScreenState();
}

class _PhysioControlRoomScreenState extends State<PhysioControlRoomScreen> {
  final StreamCache _streams = StreamCache();
  Timer? _tick;
  String _period = 'today';
  String _filter = 'all';
  String _teamFilter = 'all';

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = IstClock.now();
    return Scaffold(
      backgroundColor: ControlRoomColors.page,
      appBar: AppBar(
        title: const Text('Agency Control Room'),
        actions: [
          NotificationBell(
            uid: widget.agencyId,
            collection: 'agencies',
            forPatient: false,
            iconColor: AppColors.ink,
            onOpenItem: () {},
          ),
          IconButton(
            tooltip: 'Edit agency profile',
            icon: const Icon(Icons.edit_outlined),
            onPressed: widget.onEditProfile,
          ),
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: widget.onLogout,
          ),
        ],
      ),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: _streams.get('agency',
            () => CareAgencyService.agencyStream(widget.agencyId)),
        builder: (context, aSnap) =>
            StreamBuilder<List<Map<String, dynamic>>>(
          stream: _streams.get(
              'team', () => PhysioAgencyService.teamStream(widget.agencyId)),
          builder: (context, tSnap) =>
              StreamBuilder<List<Map<String, dynamic>>>(
            stream: _streams.get('visits',
                () => PhysioAgencyRoom.visitsStream(widget.agencyId)),
            builder: (context, vSnap) {
              final error = aSnap.error ?? tSnap.error ?? vSnap.error;
              if (error != null) {
                return LoadErrorView(error: error, what: 'the control room');
              }
              if (!tSnap.hasData || !vSnap.hasData) {
                return const Center(
                    child: CircularProgressIndicator(
                        color: AppTheme.primaryTeal));
              }
              return PhysioControlRoomView(
                agencyId: widget.agencyId,
                agency: aSnap.data ?? {'id': widget.agencyId},
                team: tSnap.data!,
                visits: vSnap.data!,
                now: now,
                period: _period,
                filter: _filter,
                teamFilter: _teamFilter,
                onPeriod: (p) => setState(() => _period = p),
                onFilter: (f) => setState(() => _filter = f),
                onTeamFilter: (f) => setState(() => _teamFilter = f),
                onEditProfile: widget.onEditProfile,
                onInvite: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => AgencyStaffInviteScreen(
                        agencyId: widget.agencyId,
                        role: InviteRole.therapist))),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Control Room contents for given data (no Firestore; used by layout tests).
class PhysioControlRoomView extends StatelessWidget {
  final String agencyId;
  final Map<String, dynamic> agency;
  final List<Map<String, dynamic>> team;
  final List<Map<String, dynamic>> visits;
  final DateTime now;
  final String period;
  final String filter;
  final String teamFilter;
  final ValueChanged<String> onPeriod;
  final ValueChanged<String> onFilter;
  final ValueChanged<String> onTeamFilter;
  final VoidCallback onEditProfile;
  final VoidCallback? onInvite;

  const PhysioControlRoomView({
    super.key,
    required this.agencyId,
    required this.agency,
    required this.team,
    required this.visits,
    required this.now,
    required this.period,
    required this.filter,
    required this.teamFilter,
    required this.onPeriod,
    required this.onFilter,
    required this.onTeamFilter,
    required this.onEditProfile,
    this.onInvite,
  });

  @override
  Widget build(BuildContext context) {
    final range = CareAgencyService.periodRange(period, now);
    final s = PhysioAgencyRoom.summarize(
      agencyId: agencyId,
      agency: agency,
      team: team,
      visits: visits,
      from: range.from,
      to: range.to,
      now: now,
    );
    final p = periodLabels[period]!.toUpperCase();
    final commission =
        toNum(agency['commissionPct']) ?? PhysioAgencyRoom.defaultCommissionPct;
    final areas = PhysioAgencyService.areasOf(agency);
    final receiving = agency['active'] == true && areas.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        MaxWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ControlRoomHeader(
                title: 'Physio Agency Control Room',
                subtitle: 'Agency: ${agency['name'] ?? '—'} · '
                    '${s.teamSize} physios in team · '
                    'Today, ${longDate(now)}',
                period: period,
                onPeriod: onPeriod,
              ),
              const SizedBox(height: 10),
              _areasCard(receiving, areas),
              const SizedBox(height: 10),
              QuickLinks(links: [
                (Icons.edit_outlined, 'Agency profile', onEditProfile),
                if (onInvite != null)
                  (Icons.person_add_alt_1_rounded, 'Invite staff', onInvite!),
              ]),
              const SectionTitle('1 · PHYSIO TEAM'),
              StatGrid(cards: [
                StatCard(
                    label: 'TOTAL PHYSIOS',
                    value: '${s.teamSize}',
                    color: ControlRoomColors.ink,
                    hint: 'Joined your agency'),
                StatCard(
                    label: 'ON AGENCY DUTY NOW',
                    value: '${s.onAgencyDuty}',
                    color: ControlRoomColors.green,
                    hint: 'Get your requests first'),
                StatCard(
                    label: 'FREELANCE NOW',
                    value: '${s.freelanceNow}',
                    color: ControlRoomColors.blue,
                    hint: 'Working on their own'),
                StatCard(
                    label: 'VISITS ACCEPTED $p',
                    value: '${s.visitsAccepted}',
                    color: ControlRoomColors.indigo,
                    hint: 'Through your agency'),
              ]),
              const SectionTitle("2 · TODAY'S VISITS"),
              StatGrid(minCardWidth: 150, cards: [
                StatCard(
                    label: 'WAITING FOR YOUR TEAM',
                    value: '${s.offeredNow}',
                    color: ControlRoomColors.orange,
                    hint: 'Open offers'),
                StatCard(
                    label: 'ACCEPTED',
                    value: '${s.accepted}',
                    color: ControlRoomColors.blue),
                StatCard(
                    label: 'IN PROGRESS',
                    value: '${s.inProgress}',
                    color: ControlRoomColors.green),
                StatCard(
                    label: 'COMPLETED',
                    value: '${s.completed}',
                    color: ControlRoomColors.green),
                StatCard(
                    label: 'LATE',
                    value: '${s.late}',
                    color: ControlRoomColors.orange,
                    hint: '30+ min after the booked time'),
                StatCard(
                    label: 'ABSENT',
                    value: '${s.absent}',
                    color: ControlRoomColors.red,
                    hint: 'Physio did not come'),
              ]),
              SectionTitle('3 · MONEY ($p)'),
              StatGrid(cards: [
                StatCard(
                    label: 'BILLED TO PATIENTS',
                    value: formatInr(s.billed),
                    color: ControlRoomColors.ink,
                    hint: 'Completed visits · 100%'),
                StatCard(
                    label: 'PHYSIO PAYOUTS',
                    value: formatInr(s.physioPayouts),
                    color: ControlRoomColors.green,
                    hint: 'After app share and agency commission'),
                StatCard(
                    label: 'AGENCY COMMISSION',
                    value: formatInr(s.agencyShare),
                    color: ControlRoomColors.indigo,
                    hint: '$commission% of the physio share'),
                StatCard(
                    label: 'APP SHARE (MEDCONNECT)',
                    value: formatInr(s.appShare),
                    color: ControlRoomColors.teal,
                    hint: '${PhysioAgencyRoom.appPct.round()}%'),
              ]),
              const SectionTitle('4 · VISIT LIST (TODAY)'),
              FilterBar(
                filters: const {
                  'all': 'All',
                  'offered': 'Waiting',
                  'accepted': 'Accepted',
                  'in_progress': 'In progress',
                  'late': 'Late',
                  'absent': 'Absent',
                },
                selected: filter,
                onSelected: onFilter,
              ),
              const SizedBox(height: 8),
              _visitList(),
              const SectionTitle('5 · TEAM'),
              FilterBar(
                filters: const {
                  'all': 'All',
                  'on_duty': 'On duty',
                  'freelance': 'Freelance',
                  'offline': 'Offline',
                },
                selected: teamFilter,
                onSelected: onTeamFilter,
              ),
              const SizedBox(height: 8),
              _teamList(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _areasCard(bool receiving, List<String> areas) => Container(
        padding: const EdgeInsets.all(12),
        decoration: controlRoomBox().copyWith(
          color: receiving ? AppColors.successTint : AppColors.orangeTint,
        ),
        child: Row(
          children: [
            Icon(receiving ? Icons.place_outlined : Icons.info_outline,
                color:
                    receiving ? ControlRoomColors.green : ControlRoomColors.orange),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                receiving
                    ? 'Receiving requests in: ${areas.join(', ')}'
                    : areas.isEmpty
                        ? 'The admin has not set your service areas yet, so your team does not get agency requests. Please contact MedConnect.'
                        : 'Your agency is paused by the admin, so your team does not get agency requests.',
                style: const TextStyle(fontSize: 12, color: ControlRoomColors.ink),
              ),
            ),
          ],
        ),
      );

  Widget _visitList() {
    final todayKey = CareAgencyService.dateKey(now);
    final rows = <Widget>[];
    final today = visits
        .where((v) =>
            PhysioAgencyRoom.dayOf(v) == todayKey ||
            PhysioAgencyRoom.visitState(v, now) == 'offered')
        .toList()
      ..sort((a, b) {
        // Problems first (absent, late), then waiting offers, in progress,
        // accepted and completed; same state by booked time
        int rank(Map<String, dynamic> v) {
          final state = PhysioAgencyRoom.visitState(v, now);
          if (state == 'absent') return 0;
          if (PhysioAgencyRoom.isLate(v, now)) return 1;
          return switch (state) {
            'offered' => 2,
            'in_progress' => 3,
            'accepted' => 4,
            _ => 5,
          };
        }

        final r = rank(a).compareTo(rank(b));
        if (r != 0) return r;
        return FirestoreService.timeSlotMinutes((a['time'] ?? '').toString())
            .compareTo(
                FirestoreService.timeSlotMinutes((b['time'] ?? '').toString()));
      });

    for (final v in today) {
      final state = PhysioAgencyRoom.visitState(v, now);
      if (state == 'closed') continue;
      final late = PhysioAgencyRoom.isLate(v, now);
      final match = switch (filter) {
        'offered' => state == 'offered',
        'accepted' => state == 'accepted',
        'in_progress' => state == 'in_progress',
        'late' => late,
        'absent' => state == 'absent',
        _ => true,
      };
      if (!match) continue;

      final lateBy = PhysioAgencyRoom.lateMinutes(v, now);
      final badge = switch (state) {
        'offered' => const StatusBadge('Waiting', ControlRoomColors.orange),
        'accepted' => late
            ? StatusBadge('Late ${lateBy}m', ControlRoomColors.orange)
            : const StatusBadge('Accepted', ControlRoomColors.blue),
        'in_progress' => StatusBadge(
            late ? 'In progress · late ${lateBy}m' : 'In progress',
            ControlRoomColors.green),
        'completed' => const StatusBadge('Completed', ControlRoomColors.green),
        _ => const StatusBadge('Absent', ControlRoomColors.red),
      };
      // Privacy: the patient's name only once a physio is assigned
      final assigned = state != 'offered';
      final area = (v['locationName'] ?? '').toString().split(',').first.trim();
      final therapy = (v['therapyName'] ?? 'Physiotherapy').toString();
      rows.add(ListRow(
        badge: badge,
        title: assigned
            ? (v['patientName'] ?? 'Patient').toString()
            : '$therapy · ${area.isEmpty ? 'Patient area' : area}',
        lines: [
          if (assigned)
            '$therapy · ${area.isEmpty ? 'Patient area' : area}',
          assigned
              ? 'Physio: ${v['doctorName'] ?? '—'}'
              : 'Open to your on-duty team until ${PhysioAgencyService.timeLabel(v['agencyOfferExpiresAt'])}',
          '${v['date'] ?? ''} @ ${v['time'] ?? ''}',
        ],
        cells: [
          assigned ? (v['patientName'] ?? 'Patient').toString() : 'Waiting for your team',
          therapy,
          area.isEmpty ? '—' : area,
          assigned
              ? (v['doctorName'] ?? '—').toString()
              : 'Until ${PhysioAgencyService.timeLabel(v['agencyOfferExpiresAt'])}',
          '${v['date'] ?? ''} ${v['time'] ?? ''}',
        ],
        trailing: Text(formatInr(toNum(v['price']) ?? 0),
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: ControlRoomColors.ink)),
      ));
    }
    return ListPanel(
      rows: rows,
      columns: const [
        ('PATIENT', 3),
        ('THERAPY', 3),
        ('AREA', 2),
        ('PHYSIO', 3),
        ('DATE & TIME', 2),
      ],
      trailingHeading: 'AMOUNT',
      emptyText: visits.isEmpty
          ? 'Visits your team takes through the agency will appear here.'
          : 'Nothing to show for this filter.',
    );
  }

  Widget _teamList() {
    final rows = <Widget>[];
    final sorted = [...team]
      ..sort((a, b) => (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
    for (final p in sorted) {
      final mode = PhysioAgencyRoom.teamMode(p, agencyId);
      final match = switch (teamFilter) {
        'on_duty' => mode == 'on_duty',
        'freelance' => mode == 'freelance',
        'offline' => mode == 'offline' || mode == 'unverified',
        _ => true,
      };
      if (!match) continue;
      final badge = switch (mode) {
        'on_duty' => const StatusBadge('On agency duty', ControlRoomColors.green),
        'freelance' => const StatusBadge('Freelance', ControlRoomColors.blue),
        'offline' => const StatusBadge('Offline', ControlRoomColors.muted),
        _ => const StatusBadge('Not verified', ControlRoomColors.orange),
      };
      final phone = (p['phone'] ?? p['mobileNumber'] ?? '').toString();
      rows.add(ListRow(
        badge: badge,
        title: (p['name'] ?? 'Physio').toString(),
        lines: [
          [
            (p['qualification'] ?? '').toString(),
            if (phone.isNotEmpty) phone,
            'Rating ${FirestoreService.ratingLabel(p)}',
          ].where((e) => e.isNotEmpty).join(' · '),
        ],
      ));
    }
    return ListPanel(
      rows: rows,
      emptyText: team.isEmpty
          ? 'No physios have joined yet. Physios join from "Join an agency" on their dashboard.'
          : 'Nothing to show for this filter.',
    );
  }
}
