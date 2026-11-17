import 'package:flutter/material.dart';

import '../../models/care_duty_roster.dart';
import '../../services/technician_duty_service.dart';
import '../../services/technician_staffing_service.dart';
import '../care_physician/cp_widgets.dart';
import '../../utils/ist_clock.dart';

typedef _Cp = TechnicianStaffingService;

/// Where a duty is in time.
enum TechnicianDutyPhase { ongoing, upcoming, completed }

TechnicianDutyPhase technicianPhaseOfShift(Map<String, dynamic> s, DateTime now) {
  final status = (s['status'] ?? '').toString();
  if (status == 'on_duty') return TechnicianDutyPhase.ongoing;
  if (const {'completed', 'absent', 'cancelled', 'unfilled'}.contains(status)) {
    return TechnicianDutyPhase.completed;
  }
  final end = _Cp.shiftEnd(s);
  return end != null && !end.isAfter(IstClock.wall(now))
      ? TechnicianDutyPhase.completed
      : TechnicianDutyPhase.upcoming;
}

TechnicianDutyPhase technicianPhaseOfSlot(DutySlot s, DateTime now) {
  final at = IstClock.toInstant(now); // duty times are real instants
  if (!s.end.isAfter(at)) return TechnicianDutyPhase.completed;
  if (!s.start.isAfter(at)) return TechnicianDutyPhase.ongoing;
  return TechnicianDutyPhase.upcoming;
}

String technicianClockText(DateTime utc) {
  final i = CareDutyClock.utcToIst(utc);
  final h = i.hour % 12 == 0 ? 12 : i.hour % 12;
  final m = i.minute == 0 ? '' : ':${i.minute.toString().padLeft(2, '0')}';
  return '$h$m ${i.hour < 12 ? 'am' : 'pm'}';
}

String technicianSlotRangeText(DutySlot s) => '${technicianClockText(s.start)} – ${technicianClockText(s.end)}';

/// Calendar colours by the time of day a duty starts (India time):
/// morning yellow, afternoon orange, evening and night blue.
enum TechnicianDayPart { morning, afternoon, evening }

TechnicianDayPart technicianDayPartOf(DateTime startUtc) {
  final h = CareDutyClock.utcToIst(startUtc).hour;
  if (h >= 5 && h < 12) return TechnicianDayPart.morning;
  if (h >= 12 && h < 18) return TechnicianDayPart.afternoon;
  return TechnicianDayPart.evening;
}

Color technicianDayPartColor(TechnicianDayPart p) => switch (p) {
      TechnicianDayPart.morning => const Color(0xFFEAB308), // yellow
      TechnicianDayPart.afternoon => const Color(0xFFF97316), // orange
      TechnicianDayPart.evening => const Color(0xFF2563EB), // blue
    };

const _freeColor = Color(0xFF16A34A);

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
  'September', 'October', 'November', 'December'
];
const _dow = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// One duty as the calendar and the lists see it (a claimed shift or a duty
/// on a hospital rotation roster).
class TechnicianDutyEntry {
  final TechnicianDutyPhase phase;
  final DateTime start;
  final DateTime end;
  final String hospital;
  final String title;
  final Widget? card; // the full card of a claimed shift
  final bool counts; // false: a cancelled shift or a request not decided yet
  const TechnicianDutyEntry(this.phase, this.start, this.end, this.hospital, this.title,
      {this.card, this.counts = true});
}

/// "My duties": a calendar (blue dot = a duty that day, green dot = free)
/// and every ongoing, upcoming and completed duty.
class TechnicianMyDutiesView extends StatefulWidget {
  final String uid;
  final List<Map<String, dynamic>> myShifts;
  final DateTime now;
  final Widget Function(Map<String, dynamic> shift) cardFor;
  final Widget? header; // earnings, agency duties
  const TechnicianMyDutiesView({
    super.key,
    required this.uid,
    required this.myShifts,
    required this.now,
    required this.cardFor,
    this.header,
  });

  @override
  State<TechnicianMyDutiesView> createState() => _MyDutiesViewState();
}

class _MyDutiesViewState extends State<TechnicianMyDutiesView> {
  TechnicianDutyPhase _phase = TechnicianDutyPhase.upcoming;
  late DateTime _month = DateTime.utc(widget.now.year, widget.now.month, 1);
  DateTime? _day;

  // the hospital rotation teams (none when the backend is not reachable)
  late final Stream<List<Map<String, dynamic>>> _teams = _teamsStream();

  Stream<List<Map<String, dynamic>>> _teamsStream() {
    try {
      return TechnicianDutyService.teamsOf(widget.uid);
    } catch (_) {
      return Stream.value(const []);
    }
  }

  List<TechnicianDutyEntry> _entries(List<Map<String, dynamic>> teams) {
    final out = <TechnicianDutyEntry>[];
    for (final s in widget.myShifts) {
      final a = IstClock.maybeToInstant(_Cp.shiftStart(s));
      final b = IstClock.maybeToInstant(_Cp.shiftEnd(s));
      if (a == null || b == null) continue;
      if (s['status'] == 'team_applied') {
        out.add(TechnicianDutyEntry(TechnicianDutyPhase.upcoming, a, b,
            (s['hospitalName'] ?? '').toString(), 'Team request',
            card: widget.cardFor(s), counts: false));
        continue;
      }
      out.add(TechnicianDutyEntry(technicianPhaseOfShift(s, widget.now), a, b,
          (s['hospitalName'] ?? '').toString(), _Cp.slotLabel(s),
          card: widget.cardFor(s),
          counts: !const {'cancelled', 'unfilled'}.contains(s['status'])));
    }
    final today = CareDutyClock.today(widget.now);
    for (final t in teams) {
      final roster = TechnicianDutyService.rosterOf(t);
      for (final slot in roster.dutiesOf(widget.uid,
          today.subtract(const Duration(days: 30)),
          today.add(const Duration(days: 60)))) {
        out.add(TechnicianDutyEntry(technicianPhaseOfSlot(slot, widget.now), slot.start, slot.end,
            (t['hospitalName'] ?? '').toString(),
            '${slot.shift.label} duty · full-time team',
            card: _rosterCard(t, slot)));
      }
    }
    return out;
  }

  Widget _rosterCard(Map<String, dynamic> team, DutySlot slot) => Container(
        padding: const EdgeInsets.all(14),
        decoration: cpCard(),
        child: Row(children: [
          const CpEmojiTile('🗓️', Color(0xFF2563EB)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((team['hospitalName'] ?? '').toString(),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800, color: CpColors.ink)),
              Text(
                  '${slot.shift.label} · ${technicianSlotRangeText(slot)} · ${slot.date.day} ${_monthNames[slot.date.month - 1].substring(0, 3)}',
                  style: const TextStyle(fontSize: 12, color: CpColors.muted)),
              const Text('Full-time rotation duty',
                  style: TextStyle(fontSize: 11.5, color: CpColors.muted)),
            ]),
          ),
        ]),
      );

  /// Calendar days (India dates) a duty touches.
  Set<DateTime> _daysOf(TechnicianDutyEntry e) {
    final out = <DateTime>{};
    final a = CareDutyClock.utcToIst(e.start);
    final b = CareDutyClock.utcToIst(e.end.subtract(const Duration(minutes: 1)));
    for (var d = DateTime.utc(a.year, a.month, a.day);
        !d.isAfter(DateTime.utc(b.year, b.month, b.day));
        d = d.add(const Duration(days: 1))) {
      out.add(d);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _teams,
      builder: (context, snap) {
        final all = _entries(snap.data ?? const []);
        final busy = <DateTime, List<TechnicianDutyEntry>>{};
        for (final e in all) {
          if (e.card == null || !e.counts) continue;
          for (final d in _daysOf(e)) {
            busy.putIfAbsent(d, () => []).add(e);
          }
        }
        final shown = all.where((e) => e.phase == _phase).toList()
          ..sort((a, b) => _phase == TechnicianDutyPhase.completed
              ? b.start.compareTo(a.start)
              : a.start.compareTo(b.start));
        final counts = {
          for (final p in TechnicianDutyPhase.values)
            p: all.where((e) => e.phase == p).length
        };
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            if (widget.header != null) ...[widget.header!, const SizedBox(height: 14)],
            _calendar(busy),
            const SizedBox(height: 14),
            Wrap(spacing: 8, children: [
              for (final p in TechnicianDutyPhase.values)
                ChoiceChip(
                  label: Text(
                      '${const {TechnicianDutyPhase.ongoing: 'Ongoing', TechnicianDutyPhase.upcoming: 'Upcoming', TechnicianDutyPhase.completed: 'Completed'}[p]} (${counts[p]})'),
                  selected: _phase == p,
                  onSelected: (_) => setState(() => _phase = p),
                ),
            ]),
            const SizedBox(height: 12),
            if (shown.isEmpty)
              CpEmpty('📋',
                  'No ${const {TechnicianDutyPhase.ongoing: 'ongoing', TechnicianDutyPhase.upcoming: 'upcoming', TechnicianDutyPhase.completed: 'completed'}[_phase]} duties.')
            else
              for (final e in shown)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: e.card!,
                ),
          ],
        );
      },
    );
  }

  Widget _calendar(Map<DateTime, List<TechnicianDutyEntry>> busy) {
    final today = CareDutyClock.today(widget.now);
    final daysInMonth = DateTime.utc(_month.year, _month.month + 1, 0).day;
    final lead = _month.weekday - 1;
    final selected = _day;
    // no going back to months before any duty: before launch (or before the
    // first duty) there is nothing to show, and "free" would be misleading
    final thisMonth = DateTime.utc(today.year, today.month, 1);
    final firstDuty = busy.entries
        .where((e) => e.value.isNotEmpty)
        .map((e) => DateTime.utc(e.key.year, e.key.month, 1))
        .fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
    final earliest = firstDuty != null && firstDuty.isBefore(thisMonth)
        ? firstDuty
        : thisMonth;
    final canGoBack = _month.isAfter(earliest);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: cpCard(),
      child: Column(children: [
        Row(children: [
          IconButton(
              tooltip: 'Previous month',
              onPressed: canGoBack
                  ? () => setState(() => _month =
                      DateTime.utc(_month.year, _month.month - 1, 1))
                  : null,
              icon: const Icon(Icons.chevron_left_rounded)),
          Expanded(
            child: Text('${_monthNames[_month.month - 1]} ${_month.year}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
          IconButton(
              onPressed: () => setState(() =>
                  _month = DateTime.utc(_month.year, _month.month + 1, 1)),
              icon: const Icon(Icons.chevron_right_rounded)),
        ]),
        Row(children: [
          for (final w in _dow)
            Expanded(
                child: Text(w,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11, color: CpColors.muted))),
        ]),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 0.95,
          children: [
            for (var i = 0; i < lead; i++) const SizedBox.shrink(),
            for (var d = 1; d <= daysInMonth; d++)
              _cell(DateTime.utc(_month.year, _month.month, d), today,
                  selected, busy),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
            alignment: WrapAlignment.center,
            spacing: 18,
            runSpacing: 4,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                _dot(_freeColor),
                const Text(' Free', style: TextStyle(fontSize: 12)),
              ]),
              for (final e in const {
                TechnicianDayPart.morning: 'Morning',
                TechnicianDayPart.afternoon: 'Afternoon',
                TechnicianDayPart.evening: 'Evening',
              }.entries)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  _dot(technicianDayPartColor(e.key)),
                  Text(' ${e.value}', style: const TextStyle(fontSize: 12)),
                ]),
            ]),
        if (selected != null) ...[
          const Divider(height: 20),
          _dayList(selected, busy[selected] ?? const []),
        ],
      ]),
    );
  }

  Widget _dot(Color c) => Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle));

  Widget _cell(DateTime day, DateTime today, DateTime? selected,
      Map<DateTime, List<TechnicianDutyEntry>> busy) {
    final onDuty = (busy[day] ?? const []).isNotEmpty;
    final isToday = day == today;
    final isSel = day == selected;
    // a past day with no duty: nothing to show (not "free")
    final pastEmpty = day.isBefore(today) && !onDuty;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: pastEmpty ? null : () => setState(() => _day = isSel ? null : day),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: isSel ? CpColors.chip : null,
          border: isToday ? Border.all(color: CpColors.navy) : null,
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('${day.day}',
              style: TextStyle(
                  fontSize: 12.5,
                  height: 1.1,
                  color: pastEmpty ? CpColors.muted.withValues(alpha: 0.45) : null,
                  fontWeight: isToday ? FontWeight.w900 : FontWeight.w500)),
          const SizedBox(height: 3),
          if (pastEmpty)
            const SizedBox(height: 9)
          else if (!onDuty)
            _dot(_freeColor)
          else
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (final p in TechnicianDayPart.values)
                if ((busy[day] ?? const []).any((e) => technicianDayPartOf(e.start) == p))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: _dot(technicianDayPartColor(p)),
                  ),
            ]),
        ]),
      ),
    );
  }

  Widget _dayList(DateTime day, List<TechnicianDutyEntry> duties) {
    final head =
        '${day.day} ${_monthNames[day.month - 1]}';
    if (duties.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text('$head: you are free.',
            style: const TextStyle(fontWeight: FontWeight.w600)),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(head, style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      for (final e in duties)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 6),
              child: _dot(technicianDayPartColor(technicianDayPartOf(e.start))),
            ),
            Expanded(
              child: Text(
                  '${e.hospital} · ${e.title} · ${technicianClockText(e.start)} – ${technicianClockText(e.end)}',
                  style: const TextStyle(fontSize: 13)),
            ),
          ]),
        ),
    ]);
  }
}
