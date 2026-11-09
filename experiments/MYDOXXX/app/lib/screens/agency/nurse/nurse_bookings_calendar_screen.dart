import 'package:flutter/material.dart';
import '../../../utils/safe_cast.dart';

import '../../../services/care_agency_service.dart';
import '../../../utils/stream_cache.dart';
import '../control_room_widgets.dart';
import '../../../utils/ist_clock.dart';

/// Partner's bookings by month: every duty (its own, its nurses'
/// claimed shifts and the hospital requests it took). A calendar with a dot
/// per booked day, the selected day's bookings, and the upcoming ones.
class NurseAgencyBookingsScreen extends StatefulWidget {
  final String agencyId;
  const NurseAgencyBookingsScreen({super.key, required this.agencyId});

  @override
  State<NurseAgencyBookingsScreen> createState() => _AgencyBookingsScreenState();
}

class _AgencyBookingsScreenState extends State<NurseAgencyBookingsScreen> {
  final StreamCache _streams = StreamCache();
  late DateTime _month = DateTime(IstClock.now().year, IstClock.now().month);
  late DateTime _day = _today;

  static DateTime get _today {
    final n = IstClock.now();
    return DateTime(n.year, n.month, n.day);
  }

  String get _from => CareAgencyService.dateKey(_month);
  String get _to => CareAgencyService.dateKey(
      DateTime(_month.year, _month.month + 1, 0)); // last day of the month

  void _moveMonth(int delta) => setState(() {
        _month = DateTime(_month.year, _month.month + delta);
        final today = _today;
        _day = (today.year == _month.year && today.month == _month.month)
            ? today
            : _month;
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ControlRoomColors.page,
      appBar: AppBar(title: const Text('Bookings & Calendar')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _streams.get('duties_$_from',
            () => CareAgencyService.dutiesStream(widget.agencyId, _from, _to)),
        builder: (context, snap) {
          final duties = (snap.data ?? const [])
              .where((d) => d['status'] != 'cancelled')
              .toList();
          final byDay = <String, List<Map<String, dynamic>>>{};
          for (final d in duties) {
            byDay.putIfAbsent((d['date'] ?? '').toString(), () => []).add(d);
          }
          int byStart(Map<String, dynamic> a, Map<String, dynamic> b) =>
              (CareAgencyService.asTime(a['shiftStart']) ?? DateTime(2100))
                  .compareTo(CareAgencyService.asTime(b['shiftStart']) ??
                      DateTime(2100));
          final dayList = [...?byDay[CareAgencyService.dateKey(_day)]]
            ..sort(byStart);
          final upcoming = duties.where((d) {
            final s = CareAgencyService.asTime(d['shiftStart']);
            return s != null && !s.isBefore(IstClock.now());
          }).toList()
            ..sort(byStart);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              MaxWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _calendar(byDay),
                    const SizedBox(height: 4),
                    SectionTitle(
                        '${_dayLabel(_day)} · ${dayList.length} BOOKING${dayList.length == 1 ? '' : 'S'}'),
                    if (snap.connectionState == ConnectionState.waiting &&
                        !snap.hasData)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      ListPanel(
                        rows: [for (final d in dayList) _row(d)],
                        emptyText: 'No bookings on this day.',
                      ),
                    SectionTitle(
                        'UPCOMING THIS MONTH · ${upcoming.length}'),
                    ListPanel(
                      rows: [for (final d in upcoming) _row(d, withDate: true)],
                      emptyText: 'No upcoming bookings this month.',
                      initialRows: 10,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String _dayLabel(DateTime d) =>
      '${_weekdays[d.weekday - 1].toUpperCase()} ${d.day} ${_months[d.month - 1].substring(0, 3).toUpperCase()}';

  Widget _calendar(Map<String, List<Map<String, dynamic>>> byDay) {
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
              _dayCell(DateTime(_month.year, _month.month, d), byDay, today),
          ],
        ),
      ]),
    );
  }

  Widget _dayCell(DateTime day, Map<String, List<Map<String, dynamic>>> byDay,
      DateTime today) {
    final count = byDay[CareAgencyService.dateKey(day)]?.length ?? 0;
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
          onTap: () => setState(() => _day = day),
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

  Widget _row(Map<String, dynamic> d, {bool withDate = false}) {
    final now = IstClock.now();
    final state = CareAgencyService.dutyState(d, now);
    final start = CareAgencyService.asTime(d['shiftStart']);
    final end = CareAgencyService.asTime(d['shiftEnd']);
    String hm(DateTime? t) {
      if (t == null) return '—';
      final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
      return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
    }

    final badge = switch (state) {
      'on_duty' => const StatusBadge('On duty', ControlRoomColors.green),
      'completed' => const StatusBadge('Completed', ControlRoomColors.green),
      'late' => const StatusBadge('Late', ControlRoomColors.orange),
      'absent' => const StatusBadge('Absent', ControlRoomColors.red),
      _ => const StatusBadge('Booked', ControlRoomColors.blue),
    };
    final emergency = d['type'] == 'emergency';
    final when = [
      if (withDate && start != null) _dayLabel(start),
      '${hm(start)} – ${hm(end)}',
    ].join(' · ');
    return ListRow(
      badge: badge,
      title: (d['doctorName'] ?? 'Nurse').toString(),
      lines: [
        '${d['hospitalName'] ?? ''}${emergency ? ' · Emergency locum' : ''}',
        when,
      ],
      trailing: Text(formatInr(toNum(d['hospitalRate']) ?? 0),
          style: const TextStyle(
              fontWeight: FontWeight.bold, color: ControlRoomColors.ink)),
    );
  }
}
