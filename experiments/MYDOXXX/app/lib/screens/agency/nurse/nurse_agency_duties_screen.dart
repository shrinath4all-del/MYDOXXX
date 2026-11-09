import 'package:flutter/material.dart';

import '../../../models/care_duty_roster.dart';
import '../../../services/care_agency_service.dart';
import '../../../services/nurse_duty_service.dart';
import '../../../services/nurse_staffing_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/error_messages.dart';
import '../../../utils/responsive.dart';
import '../../../utils/stream_cache.dart';
import 'nurse_profile_view_screen.dart';
import '../../nurse/nurse_my_duties_view.dart'
    show NurseDutyPhase, nursePhaseOfShift, nursePhaseOfSlot, nurseSlotRangeText, nurseClockText;
import '../../../utils/ist_clock.dart';

typedef _Cp = NurseStaffingService;

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov',
  'Dec'
];

/// What the agency's own nurses are doing: where each one works,
/// and their ongoing, upcoming and completed duties. Freelancers are not
/// included, and neither are patients' home visits.
class NurseAgencyDutiesScreen extends StatefulWidget {
  final String agencyId;
  const NurseAgencyDutiesScreen({super.key, required this.agencyId});

  @override
  State<NurseAgencyDutiesScreen> createState() => _AgencyDutiesScreenState();
}

class _Row {
  final NurseDutyPhase phase;
  final DateTime start;
  final String doctor;
  final String uid;
  final String hospital;
  final String what;
  final String when;
  final String? status;
  const _Row(this.phase, this.start, this.doctor, this.uid, this.hospital,
      this.what, this.when,
      [this.status]);
}

class _AgencyDutiesScreenState extends State<NurseAgencyDutiesScreen> {
  final StreamCache _streams = StreamCache();
  String _tab = 'ongoing'; // ongoing | upcoming | completed | placements

  String _dayText(DateTime utc) {
    final i = CareDutyClock.utcToIst(utc);
    return '${i.day} ${_months[i.month - 1]}';
  }

  List<_Row> _rows(List<Map<String, dynamic>> shifts,
      List<Map<String, dynamic>> teams, DateTime now) {
    final out = <_Row>[];
    for (final s in shifts) {
      if (s['postedBy'] == 'patient') continue; // not the agency's business
      final a = IstClock.maybeToInstant(_Cp.shiftStart(s));
      final b = IstClock.maybeToInstant(_Cp.shiftEnd(s));
      if (a == null || b == null) continue;
      final status = (s['status'] ?? '').toString();
      if (const {'open', 'cancelled', 'unfilled'}.contains(status)) continue;
      out.add(_Row(
        nursePhaseOfShift(s, now),
        a,
        (s['claimedByName'] ?? 'Nurse').toString(),
        (s['claimedBy'] ?? '').toString(),
        (s['hospitalName'] ?? '').toString(),
        '${_Cp.dutyLabel(s['dutyType']?.toString())} · ${_Cp.slotLabel(s)}',
        '${_dayText(a)} · ${nurseClockText(a)} – ${nurseClockText(b)}',
        status,
      ));
    }
    final today = CareDutyClock.today(now);
    for (final t in teams) {
      final roster = NurseDutyService.rosterOf(t);
      for (var d = today.subtract(const Duration(days: 30));
          !d.isAfter(today.add(const Duration(days: 60)));
          d = d.add(const Duration(days: 1))) {
        for (final slot in roster.slotsOn(d)) {
          out.add(_Row(
            nursePhaseOfSlot(slot, now),
            slot.start,
            NurseDutyService.assigneeName(t, slot),
            roster.assigneeOf(slot),
            (t['hospitalName'] ?? '').toString(),
            '${slot.shift.label} duty · full-time team',
            '${_dayText(slot.start)} · ${nurseSlotRangeText(slot)}',
          ));
        }
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveCenter(
      child: Scaffold(
        backgroundColor: AppTheme.bgLight,
        appBar: AppBar(title: const Text('Nurses\' duties')),
        body: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _streams.get(
              'shifts', () => _Cp.agencyShiftsStream(widget.agencyId)),
          builder: (context, shiftSnap) =>
              StreamBuilder<List<Map<String, dynamic>>>(
            stream: _streams.get(
                'teams', () => NurseDutyService.teamsOfAgency(widget.agencyId)),
            builder: (context, teamSnap) =>
                StreamBuilder<List<Map<String, dynamic>>>(
              stream: _streams.get('nurses',
                  () => CareAgencyService.doctorsStream(widget.agencyId)),
              builder: (context, docSnap) {
                final error =
                    shiftSnap.error ?? teamSnap.error ?? docSnap.error;
                if (error != null) {
                  return LoadErrorView(error: error, what: 'the duties');
                }
                if (!shiftSnap.hasData || !teamSnap.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.primaryTeal));
                }
                final now = IstClock.now();
                final rows = _rows(shiftSnap.data!, teamSnap.data!, now);
                final count = {
                  'ongoing':
                      rows.where((r) => r.phase == NurseDutyPhase.ongoing).length,
                  'upcoming':
                      rows.where((r) => r.phase == NurseDutyPhase.upcoming).length,
                  'completed':
                      rows.where((r) => r.phase == NurseDutyPhase.completed).length,
                };
                return Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Wrap(spacing: 8, children: [
                      for (final e in {
                        'ongoing': 'Ongoing (${count['ongoing']})',
                        'upcoming': 'Upcoming (${count['upcoming']})',
                        'completed': 'Completed (${count['completed']})',
                        'placements': 'Who works where',
                      }.entries)
                        ChoiceChip(
                          label: Text(e.value),
                          selected: _tab == e.key,
                          onSelected: (_) => setState(() => _tab = e.key),
                        ),
                    ]),
                  ),
                  Expanded(
                    child: _tab == 'placements'
                        ? _placements(
                            teamSnap.data!, docSnap.data ?? const [], rows)
                        : _list(rows),
                  ),
                ]);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _list(List<_Row> rows) {
    final phase = {
      'ongoing': NurseDutyPhase.ongoing,
      'upcoming': NurseDutyPhase.upcoming,
      'completed': NurseDutyPhase.completed,
    }[_tab]!;
    final shown = rows.where((r) => r.phase == phase).toList()
      ..sort((a, b) => phase == NurseDutyPhase.completed
          ? b.start.compareTo(a.start)
          : a.start.compareTo(b.start));
    if (shown.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('No $_tab duties of your nurses.',
              style: const TextStyle(color: AppTheme.textMuted)),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: shown.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final r = shown[i];
        return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () =>
                NurseProfileViewScreen.open(context, r.uid, name: r.doctor),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(children: [
                const CircleAvatar(
                    backgroundColor: Color(0xFFE0F2FE),
                    child:
                        Icon(Icons.person_outline, color: Color(0xFF075985))),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(r.doctor,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: AppTheme.darkNavy)),
                      const SizedBox(height: 2),
                      Text('at ${r.hospital}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('${r.what} · ${r.when}',
                          style: const TextStyle(
                              fontSize: 12.5, color: AppTheme.textMuted)),
                      if (r.status == 'absent')
                        const Text('Did not check in',
                            style: TextStyle(
                                fontSize: 12, color: Colors.redAccent)),
                    ])),
                const Icon(Icons.chevron_right_rounded,
                    color: AppTheme.textMuted),
              ]),
            ));
      },
    );
  }

  /// Which nurse works in which hospital.
  Widget _placements(List<Map<String, dynamic>> teams,
      List<Map<String, dynamic>> doctors, List<_Row> rows) {
    final entries = <({String doctor, String uid, String where, String how})>[];
    final placed = <String>{};
    for (final t in teams) {
      final names = _Cp.listOf(t['memberNames']);
      final members = _Cp.listOf(t['members']);
      for (var i = 0; i < members.length; i++) {
        placed.add(members[i]);
        entries.add((
          doctor: i < names.length ? names[i] : '',
          uid: members[i],
          where: (t['hospitalName'] ?? '').toString(),
          how:
              'Full-time team (${CareDutyRoster.letters[i]}) since ${t['anchor']}',
        ));
      }
    }
    for (final d in doctors) {
      if (d['active'] == false || placed.contains(d['userUid'])) continue;
      final hosp =
          (d['permanentHospitalName'] ?? d['permanentHospitalId'] ?? '')
              .toString();
      if (d['placementType'] == 'permanent' && hosp.isNotEmpty) {
        entries.add((
          doctor: (d['name'] ?? '').toString(),
          uid: (d['userUid'] ?? '').toString(),
          where: hosp,
          how: 'Permanent placement'
        ));
      }
    }
    // working at a hospital right now on a locum shift
    final now = rows.where(
        (r) => r.phase == NurseDutyPhase.ongoing && !r.what.contains('full-time'));
    for (final r in now) {
      entries.add((
        doctor: r.doctor,
        uid: r.uid,
        where: r.hospital,
        how: 'On duty now (locum shift)'
      ));
    }
    if (entries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
              'None of your nurses is placed at a hospital yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted)),
        ),
      );
    }
    entries.sort(
        (a, b) => a.doctor.toLowerCase().compareTo(b.doctor.toLowerCase()));
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final e = entries[i];
        return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () =>
                NurseProfileViewScreen.open(context, e.uid, name: e.doctor),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(children: [
                const CircleAvatar(
                    backgroundColor: Color(0xFFE0F2FE),
                    child:
                        Icon(Icons.person_outline, color: Color(0xFF075985))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.doctor,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                        Text('works at ${e.where}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        Text(e.how,
                            style: const TextStyle(
                                fontSize: 12.5, color: AppTheme.textMuted)),
                      ]),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppTheme.textMuted),
              ]),
            ));
      },
    );
  }
}
