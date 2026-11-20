import '../../../utils/ist_clock.dart';
import 'package:flutter/material.dart';

import '../../../services/agency_day_duties.dart';
import '../../../services/care_duty_service.dart';
import '../../../services/care_physician_service.dart';
import '../../../utils/stream_cache.dart';
import '../control_room_widgets.dart';
import 'care_doctor_profile_screen.dart';
import 'physician_photo.dart';

typedef _Cp = CarePhysicianService;
typedef _Day = AgencyDayDuties;

/// The partner's calendar. Pick a day, then drill down:
///   Locum | Full time  ->  ICU, Ward, Casualty, Speciality
///   ->  Morning, Afternoon, Night  ->  the care physicians working then
/// (photo, name, hospital); a tap opens the physician's profile. Every card
/// shows how many duties (or active people) it holds.
class AgencyBookingsScreen extends StatefulWidget {
  final String agencyId;
  const AgencyBookingsScreen({super.key, required this.agencyId});

  @override
  State<AgencyBookingsScreen> createState() => _AgencyBookingsScreenState();
}

class _AgencyBookingsScreenState extends State<AgencyBookingsScreen> {
  final StreamCache _streams = StreamCache();
  late DateTime _month = DateTime(IstClock.now().year, IstClock.now().month);
  late DateTime _day = _today;

  // where the agency is in the drill-down
  String? _kind; // locum | full
  String? _duty; // icu | ward | casualty | specialty
  String? _part; // morning | afternoon | night

  static DateTime get _today {
    final n = IstClock.now();
    return DateTime(n.year, n.month, n.day);
  }

  void _moveMonth(int delta) => setState(() {
        _month = DateTime(_month.year, _month.month + delta);
        final today = _today;
        _day = (today.year == _month.year && today.month == _month.month)
            ? today
            : _month;
        _reset();
      });

  void _reset() {
    _kind = null;
    _duty = null;
    _part = null;
  }

  /// One step back in the drill-down.
  void _back() => setState(() {
        if (_part != null) {
          _part = null;
        } else if (_duty != null) {
          _duty = null;
        } else {
          _kind = null;
        }
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ControlRoomColors.page,
      appBar: AppBar(title: const Text('Bookings & Calendar')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _streams.get(
            'shifts', () => _Cp.agencyShiftsStream(widget.agencyId)),
        builder: (context, shiftSnap) => StreamBuilder<List<Map<String, dynamic>>>(
          stream: _streams.get(
              'teams', () => CareDutyService.teamsOfAgency(widget.agencyId)),
          builder: (context, teamSnap) => StreamBuilder<List<Map<String, dynamic>>>(
          stream: _streams.get('teamRequests', _Cp.hospitalTeamRequestsStream),
          builder: (context, reqSnap) {
            final error = shiftSnap.error ?? teamSnap.error;
            if (error != null) {
              return Center(
                  child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not load the bookings: $error'),
              ));
            }
            if (!shiftSnap.hasData || !teamSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final shifts = shiftSnap.data!;
            // a team placed before duty types were saved takes it from its request
            final dutyOf = {
              for (final r in reqSnap.data ?? const <Map<String, dynamic>>[])
                r['id'].toString(): (r['dutyType'] ?? '').toString()
            };
            final teams = [
              for (final t in teamSnap.data!)
                if ((t['dutyType'] ?? '').toString().isEmpty &&
                    (dutyOf[t['requestId']?.toString()] ?? '').isNotEmpty)
                  {...t, 'dutyType': dutyOf[t['requestId'].toString()]}
                else
                  t
            ];
            final day = _Day.all(shifts, teams, _day);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                MaxWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _calendar(shifts, teams),
                      const SizedBox(height: 4),
                      SectionTitle(_dayLabel(_day)),
                      _drill(day),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- drill-down

  Widget _drill(List<AgencyDuty> day) {
    // the duties the current path has selected so far
    var rows = day;
    if (_kind != null) rows = rows.where((d) => d.kind == _kind).toList();
    if (_duty != null) rows = rows.where((d) => d.dutyType == _duty).toList();

    final crumbs = [
      if (_kind != null) _kind == 'locum' ? 'Locum' : 'Full time',
      if (_duty != null) _Day.dutyLabel(_duty!),
      if (_part != null) _Day.partLabel(_part!),
    ];

    final Widget body;
    if (_kind == null) {
      final locum = day.where((d) => d.kind == 'locum').toList();
      final full = day.where((d) => d.kind == 'full').toList();
      body = Row(children: [
        Expanded(
            child: _card('Locum', Icons.bolt_rounded, _Day.people(locum),
                '${locum.length} duties',
                () => setState(() => _kind = 'locum'))),
        const SizedBox(width: 10),
        Expanded(
            child: _card('Full time', Icons.groups_rounded, _Day.people(full),
                '${full.length} duties',
                () => setState(() => _kind = 'full'))),
      ]);
    } else if (_duty == null) {
      body = GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.25,
        children: [
          for (final t in _Day.dutyTypes)
            _card(
                _Day.dutyLabel(t),
                _dutyIcon(t),
                rows.where((d) => d.dutyType == t).length,
                'duties',
                () => setState(() => _duty = t)),
        ],
      );
    } else if (_part == null) {
      body = Row(children: [
        for (final p in _Day.parts) ...[
          if (p != _Day.parts.first) const SizedBox(width: 10),
          Expanded(
              child: _card(
                  _Day.partLabel(p),
                  _partIcon(p),
                  rows.where((d) => d.part == p).length,
                  'duties',
                  () => setState(() => _part = p))),
        ],
      ]);
    } else {
      body = _doctors(rows.where((d) => d.part == _part).toList());
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_kind != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            IconButton(
              tooltip: 'Back',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: _back,
            ),
            Expanded(
              child: Text(crumbs.join('  ›  '),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: ControlRoomColors.ink)),
            ),
          ]),
        ),
      body,
    ]);
  }

  /// A card with a big count (duties, or active people on the first level).
  Widget _card(String title, IconData icon, int count, String caption,
      VoidCallback onTap) {
    final firstLevel = _kind == null;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: controlRoomBox(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: ControlRoomColors.blue),
              const SizedBox(height: 8),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: ControlRoomColors.ink)),
              const SizedBox(height: 4),
              Text('$count',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 26,
                      color: ControlRoomColors.blue)),
              Text(firstLevel ? 'active people · $caption' : caption,
                  style: const TextStyle(
                      fontSize: 11.5, color: ControlRoomColors.muted)),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _dutyIcon(String t) => switch (t) {
        'icu' => Icons.monitor_heart_rounded,
        'ward' => Icons.bed_rounded,
        'casualty' => Icons.local_hospital_rounded,
        _ => Icons.child_care_rounded,
      };

  static IconData _partIcon(String p) => switch (p) {
        'morning' => Icons.wb_twilight_rounded,
        'afternoon' => Icons.wb_sunny_rounded,
        _ => Icons.nights_stay_rounded,
      };

  /// The physicians of the chosen shift: photo, name, hospital.
  Widget _doctors(List<AgencyDuty> rows) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
            child: Text('No care physicians on this shift.',
                style: TextStyle(color: ControlRoomColors.muted))),
      );
    }
    return Column(children: [
      for (final d in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () =>
                  CareDoctorProfileScreen.open(context, d.uid, name: d.name),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: controlRoomBox(),
                child: Row(children: [
                  PhysicianPhoto(uid: d.uid, name: d.name),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: ControlRoomColors.ink)),
                          const SizedBox(height: 2),
                          Text(d.hospital.isEmpty ? '—' : d.hospital,
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  color: ControlRoomColors.muted)),
                        ]),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: ControlRoomColors.muted),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }

  // --------------------------------------------------------------- calendar

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String _dayLabel(DateTime d) =>
      '${_weekdays[d.weekday - 1].toUpperCase()} ${d.day} ${_months[d.month - 1].substring(0, 3).toUpperCase()}';

  Widget _calendar(List<Map<String, dynamic>> shifts,
      List<Map<String, dynamic>> teams) {
    final first = _month;
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final lead = first.weekday - 1; // Monday first
    final today = _today;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
      decoration: controlRoomBox(),
      child: Column(children: [
        Row(children: [
          IconButton(
            tooltip: 'Previous month',
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () => _moveMonth(-1),
          ),
          Expanded(
            child: Text('${_months[_month.month - 1]} ${_month.year}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: ControlRoomColors.ink)),
          ),
          IconButton(
            tooltip: 'Next month',
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: () => _moveMonth(1),
          ),
        ]),
        Row(children: [
          for (final w in _weekdays)
            Expanded(
              child: Center(
                child: Text(w.substring(0, 2),
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: ControlRoomColors.muted)),
              ),
            ),
        ]),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1,
          children: [
            for (var i = 0; i < lead; i++) const SizedBox(),
            for (var d = 1; d <= days; d++)
              _dayCell(DateTime(_month.year, _month.month, d), shifts, teams,
                  today),
          ],
        ),
      ]),
    );
  }

  Widget _dayCell(DateTime day, List<Map<String, dynamic>> shifts,
      List<Map<String, dynamic>> teams, DateTime today) {
    final count = _Day.all(shifts, teams, day).length;
    final selected = day == _day;
    final isToday = day == today;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: selected ? ControlRoomColors.blue : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: isToday && !selected
              ? const BorderSide(color: ControlRoomColors.blue)
              : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() {
            _day = day;
            _reset();
          }),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${day.day}',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color:
                          selected ? Colors.white : ControlRoomColors.ink)),
              const SizedBox(height: 2),
              // a dot per booked day (number when busy)
              if (count > 0)
                Text(count > 1 ? '•$count' : '•',
                    style: TextStyle(
                        fontSize: 10,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        color: selected
                            ? Colors.white
                            : ControlRoomColors.orange))
              else
                const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}
