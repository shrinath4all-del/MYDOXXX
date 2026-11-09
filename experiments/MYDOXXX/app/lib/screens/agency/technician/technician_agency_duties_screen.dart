import 'package:flutter/material.dart';

import '../../../models/care_duty_roster.dart';
import '../../../services/care_agency_service.dart';
import '../../../services/technician_duty_service.dart';
import '../../../services/technician_staffing_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/error_messages.dart';
import '../../../utils/responsive.dart';
import '../../../utils/stream_cache.dart';
import '../../technician/technician_my_duties_view.dart'
    show TechnicianDutyPhase, technicianPhaseOfShift, technicianPhaseOfSlot, technicianSlotRangeText, technicianClockText;
import '../../../utils/ist_clock.dart';

typedef _Cp = TechnicianStaffingService;

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov',
  'Dec'
];

/// What the agency's own technicians are doing: where each one works,
/// and their ongoing, upcoming and completed duties. Freelancers are not
/// included, and neither are patients' home visits.
class TechnicianAgencyDutiesScreen extends StatefulWidget {
  final String agencyId;
  const TechnicianAgencyDutiesScreen({super.key, required this.agencyId});

  @override
  State<TechnicianAgencyDutiesScreen> createState() => _AgencyDutiesScreenState();
}

class _Row {
  final TechnicianDutyPhase phase;
  final DateTime start;
  final String doctor;
  final String hospital;
  final String what;
  final String when;
  final String? status;
  const _Row(this.phase, this.start, this.doctor, this.hospital, this.what,
      this.when, [this.status]);
}

class _AgencyDutiesScreenState extends State<TechnicianAgencyDutiesScreen> {
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
        technicianPhaseOfShift(s, now),
        a,
        (s['claimedByName'] ?? 'Technician').toString(),
        (s['hospitalName'] ?? '').toString(),
        '${_Cp.dutyLabel(s['dutyType']?.toString())} · ${_Cp.slotLabel(s)}',
        '${_dayText(a)} · ${technicianClockText(a)} – ${technicianClockText(b)}',
        status,
      ));
    }
    final today = CareDutyClock.today(now);
    for (final t in teams) {
      final roster = TechnicianDutyService.rosterOf(t);
      for (var d = today.subtract(const Duration(days: 30));
          !d.isAfter(today.add(const Duration(days: 60)));
          d = d.add(const Duration(days: 1))) {
        for (final slot in roster.slotsOn(d)) {
          out.add(_Row(
            technicianPhaseOfSlot(slot, now),
            slot.start,
            TechnicianDutyService.assigneeName(t, slot),
            (t['hospitalName'] ?? '').toString(),
            '${slot.shift.label} duty · full-time team',
            '${_dayText(slot.start)} · ${technicianSlotRangeText(slot)}',
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
        appBar: AppBar(title: const Text('Technicians\' duties')),
        body: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _streams.get('shifts',
              () => _Cp.agencyShiftsStream(widget.agencyId)),
          builder: (context, shiftSnap) =>
              StreamBuilder<List<Map<String, dynamic>>>(
            stream: _streams.get('teams',
                () => TechnicianDutyService.teamsOfAgency(widget.agencyId)),
            builder: (context, teamSnap) =>
                StreamBuilder<List<Map<String, dynamic>>>(
              stream: _streams.get('technicians',
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
                  'ongoing': rows.where((r) => r.phase == TechnicianDutyPhase.ongoing).length,
                  'upcoming': rows.where((r) => r.phase == TechnicianDutyPhase.upcoming).length,
                  'completed': rows.where((r) => r.phase == TechnicianDutyPhase.completed).length,
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
                        ? _placements(teamSnap.data!, docSnap.data ?? const [], rows)
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
      'ongoing': TechnicianDutyPhase.ongoing,
      'upcoming': TechnicianDutyPhase.upcoming,
      'completed': TechnicianDutyPhase.completed,
    }[_tab]!;
    final shown = rows.where((r) => r.phase == phase).toList()
      ..sort((a, b) => phase == TechnicianDutyPhase.completed
          ? b.start.compareTo(a.start)
          : a.start.compareTo(b.start));
    if (shown.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('No $_tab duties of your technicians.',
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
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.doctor,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppTheme.darkNavy)),
            const SizedBox(height: 2),
            Text('at ${r.hospital}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('${r.what} · ${r.when}',
                style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted)),
            if (r.status == 'absent')
              const Text('Did not check in',
                  style: TextStyle(fontSize: 12, color: Colors.redAccent)),
          ]),
        );
      },
    );
  }

  /// Which technician works in which hospital.
  Widget _placements(List<Map<String, dynamic>> teams,
      List<Map<String, dynamic>> doctors, List<_Row> rows) {
    final entries = <({String doctor, String where, String how})>[];
    final placed = <String>{};
    for (final t in teams) {
      final names = _Cp.listOf(t['memberNames']);
      final members = _Cp.listOf(t['members']);
      for (var i = 0; i < members.length; i++) {
        placed.add(members[i]);
        entries.add((
          doctor: i < names.length ? names[i] : '',
          where: (t['hospitalName'] ?? '').toString(),
          how: 'Full-time team (${CareDutyRoster.letters[i]}) since ${t['anchor']}',
        ));
      }
    }
    for (final d in doctors) {
      if (d['active'] == false || placed.contains(d['userUid'])) continue;
      final hosp = (d['permanentHospitalName'] ?? d['permanentHospitalId'] ?? '').toString();
      if (d['placementType'] == 'permanent' && hosp.isNotEmpty) {
        entries.add((doctor: (d['name'] ?? '').toString(), where: hosp, how: 'Permanent placement'));
      }
    }
    // working at a hospital right now on a locum shift
    final now = rows.where((r) => r.phase == TechnicianDutyPhase.ongoing && !r.what.contains('full-time'));
    for (final r in now) {
      entries.add((doctor: r.doctor, where: r.hospital, how: 'On duty now (locum shift)'));
    }
    if (entries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('None of your technicians is placed at a hospital yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted)),
        ),
      );
    }
    entries.sort((a, b) => a.doctor.toLowerCase().compareTo(b.doctor.toLowerCase()));
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final e = entries[i];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(children: [
            const CircleAvatar(
                backgroundColor: Color(0xFFE0F2FE),
                child: Icon(Icons.person_outline, color: Color(0xFF075985))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.doctor,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Text('works at ${e.where}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(e.how,
                    style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted)),
              ]),
            ),
          ]),
        );
      },
    );
  }
}
