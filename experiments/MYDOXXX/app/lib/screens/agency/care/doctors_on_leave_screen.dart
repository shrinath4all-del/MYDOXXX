import '../../../utils/ist_clock.dart';
import 'package:flutter/material.dart';

import '../../../models/care_duty_roster.dart';
import '../../../services/agency_day_duties.dart';
import '../../../services/care_duty_service.dart';
import '../../../utils/stream_cache.dart';
import '../control_room_widgets.dart';
import 'care_doctor_profile_screen.dart';
import 'physician_photo.dart';

/// Which of the agency's care physicians are on leave on a day: the count
/// first, then (tap it) the list with photo, name, hospital and duty. A tap
/// on a physician opens the profile.
class DoctorsOnLeaveScreen extends StatefulWidget {
  final String agencyId;
  const DoctorsOnLeaveScreen({super.key, required this.agencyId});

  @override
  State<DoctorsOnLeaveScreen> createState() => _DoctorsOnLeaveScreenState();
}

class _DoctorsOnLeaveScreenState extends State<DoctorsOnLeaveScreen> {
  final StreamCache _streams = StreamCache();
  late DateTime _day = CareDutyClock.today(IstClock.now());
  bool _list = false;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct',
    'Nov', 'Dec'
  ];

  String get _dayText {
    final today = CareDutyClock.today(IstClock.now());
    final d = '${_day.day} ${_months[_day.month - 1]} ${_day.year}';
    final diff = _day.difference(today).inDays;
    return diff == 0
        ? 'Today, $d'
        : diff == 1
            ? 'Tomorrow, $d'
            : diff == -1
                ? 'Yesterday, $d'
                : d;
  }

  void _move(int days) => setState(() {
        _day = _day.add(Duration(days: days));
        _list = false;
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ControlRoomColors.page,
      appBar: AppBar(title: const Text('Doctors on leave')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _streams.get('leave',
            () => CareDutyService.leaveRequestsOfAgency(widget.agencyId)),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
                child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load the leave: ${snap.error}'),
            ));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final leaves = AgencyDayDuties.leaves(snap.data!, _day);
          final doctors = <String, List<AgencyLeave>>{};
          for (final l in leaves) {
            doctors.putIfAbsent(l.uid, () => []).add(l);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              MaxWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      IconButton(
                          tooltip: 'Previous day',
                          icon: const Icon(Icons.chevron_left_rounded),
                          onPressed: () => _move(-1)),
                      Expanded(
                        child: Text(_dayText,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: ControlRoomColors.ink)),
                      ),
                      IconButton(
                          tooltip: 'Next day',
                          icon: const Icon(Icons.chevron_right_rounded),
                          onPressed: () => _move(1)),
                    ]),
                    const SizedBox(height: 8),
                    if (!_list)
                      _countCard(doctors.length, leaves.length)
                    else ...[
                      TextButton.icon(
                        onPressed: () => setState(() => _list = false),
                        icon: const Icon(Icons.arrow_back_rounded, size: 18),
                        label: const Text('Back'),
                        style: TextButton.styleFrom(
                            alignment: Alignment.centerLeft),
                      ),
                      for (final e in doctors.entries) _row(e.value),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _countCard(int people, int duties) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: people == 0 ? null : () => setState(() => _list = true),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: controlRoomBox(),
            child: Row(children: [
              const Icon(Icons.event_busy_rounded,
                  size: 34, color: ControlRoomColors.orange),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$people',
                          style: const TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              color: ControlRoomColors.orange)),
                      Text(
                          people == 0
                              ? 'No doctor is on leave on this day.'
                              : 'doctor${people == 1 ? '' : 's'} on leave · $duties ${duties == 1 ? 'duty' : 'duties'}',
                          style: const TextStyle(
                              fontSize: 13, color: ControlRoomColors.muted)),
                      if (people > 0)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text('Tap to see the list',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: ControlRoomColors.blue)),
                        ),
                    ]),
              ),
            ]),
          ),
        ),
      );

  Widget _row(List<AgencyLeave> l) {
    final first = l.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => CareDoctorProfileScreen.open(context, first.uid,
              name: first.name),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: controlRoomBox(),
            child: Row(children: [
              PhysicianPhoto(uid: first.uid, name: first.name),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(first.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: ControlRoomColors.ink)),
                      Text(first.hospital.isEmpty ? '—' : first.hospital,
                          style: const TextStyle(
                              fontSize: 12.5, color: ControlRoomColors.muted)),
                      for (final x in l)
                        Text(
                            '${x.shiftLabel} · ${x.coveredBy.isEmpty ? 'finding a relief physician' : 'covered by ${x.coveredBy}'}',
                            style: const TextStyle(
                                fontSize: 12, color: ControlRoomColors.muted)),
                    ]),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: ControlRoomColors.muted),
            ]),
          ),
        ),
      ),
    );
  }
}
